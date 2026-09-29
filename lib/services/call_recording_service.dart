import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../models/call_model.dart';
import 'call_mic_recorder.dart';
import 'supabase_service.dart';
import 'webrtc_call_service.dart';

/// One uploaded piece of a call recording. A call produces several: the
/// recorder's own mic (m4a), the peer's audio (wav, Android voice calls) or
/// a muxed peer video+audio file (mp4, video calls) — one file per 60s
/// segment, appended to the `call_recordings.parts` array as uploads land.
class _Segment {
  final String kind; // 'mic' | 'remote' | 'video'
  final int index;
  final String path;
  final String ext;
  String? key;
  String? url;

  _Segment({
    required this.kind,
    required this.index,
    required this.path,
    required this.ext,
  });

  String get fileName => '$kind$index';
}

/// Device-side call recording with consent-gated start and segmented
/// "streaming" uploads: every [segmentDuration] the recorders are rotated —
/// the finalized file goes straight to R2 via a presigned PUT while the next
/// segment starts capturing, so a crash mid-call preserves all earlier
/// segments in the metadata row (status stays 'recording' = partial).
///
/// Track support by platform (flutter_webrtc MediaRecorder limits):
///  • voice + Android: mic (m4a) + peer audio (wav via OUTPUT channel)
///  • voice + iOS:     mic only — the plugin has no audio-only recorder
///  • video (both):    peer video+peer audio (muxed mp4) + mic
class CallRecordingService {
  CallRecordingService._();
  static final CallRecordingService instance = CallRecordingService._();

  /// How long one segment records before being finalized and uploaded.
  static const segmentDuration = Duration(seconds: 60);
  static const _folder = 'recordings';

  bool _recording = false;
  bool _rotating = false;
  bool _finalizing = false;
  int _pendingUploads = 0;
  String? _sessionId;
  CallType? _sessionType;
  String? _recordingRowId;
  DateTime? _startedAt;
  String? _dirPath;

  int _micSeq = 0;
  int _peerAudioSeq = 0;
  int _videoSeq = 0;

  CallMicRecorder? _micRecorder;
  MediaRecorder? _peerAudioRecorder;
  MediaRecorder? _videoRecorder;
  bool _micActive = false;
  bool _peerAudioActive = false;
  bool _videoActive = false;

  final List<Map<String, dynamic>> _parts = [];
  Future<void> _partsPersistChain = Future.value();

  bool get isRecording => _recording;
  DateTime? get startedAt => _startedAt;

  // ── Start / stop ────────────────────────────────────────────────────────

  /// Starts capture for [session]. Call only after the peer accepted the
  /// recording request and the call is connected. Returns false (with no
  /// side effects) when recording cannot start in this state.
  Future<bool> startCapture(CallSession session) async {
    if (_recording || _finalizing || kIsWeb) return false;

    final dir = await getTemporaryDirectory();
    final dirPath = '${dir.path}/call_recordings/${session.id}';
    try {
      await Directory(dirPath).create(recursive: true);
    } catch (_) {
      return false;
    }

    // Muxed peer video needs the remote video track; it can land a beat
    // after the connection reports active, so retry once before falling
    // back to audio-only capture for this call.
    MediaStreamTrack? videoTrack;
    if (session.type == CallType.video) {
      for (var attempt = 0; attempt < 2 && videoTrack == null; attempt++) {
        final remote = WebRtcCallEngine.instance.remoteStreamOrNull;
        final tracks = remote?.getVideoTracks() ?? const [];
        if (tracks.isNotEmpty) {
          videoTrack = tracks.first;
        } else if (attempt == 0) {
          await Future<void>.delayed(const Duration(seconds: 3));
        }
      }
    }

    _sessionId = session.id;
    _sessionType = videoTrack != null ? CallType.video : CallType.audio;
    _dirPath = dirPath;
    _parts.clear();
    _micSeq = 0;
    _peerAudioSeq = 0;
    _videoSeq = 0;

    // Metadata row first — uploaded segments reference it as they land.
    Map<String, dynamic>? row;
    try {
      row = await SupabaseService.client
          .from('call_recordings')
          .insert({
            'call_id': session.id,
            'recorded_by': session.localUserId,
            'peer_id': session.peerId,
            'peer_name': session.peerName,
            'call_type': _sessionType == CallType.video ? 'video' : 'voice',
            'status': 'recording',
            'started_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select('id')
          .single();
    } catch (_) {
      row = null;
    }
    if (row == null) {
      // Without the metadata row the segments would be unreachable later —
      // refuse to record rather than writing orphan files.
      _resetState();
      return false;
    }
    _recordingRowId = row['id'] as String;

    _startedAt = DateTime.now();
    _recording = true;

    // Own mic — available on every platform.
    _micActive = await _startMicSegment();
    // Peer audio-only recorder — Android voice calls (wav via OUTPUT channel).
    if (_sessionType == CallType.audio && !kIsWeb && Platform.isAndroid) {
      _peerAudioActive = await _startPeerAudioSegment();
    }
    // Muxed peer video+audio — video calls on both mobile platforms.
    if (videoTrack != null) {
      _videoActive = await _startVideoSegment(videoTrack);
    }

    if (!_micActive && !_peerAudioActive && !_videoActive) {
      // Nothing could be captured — don't leave a stale metadata row behind.
      _recording = false;
      await _finalize('failed');
      _resetState();
      return false;
    }

    Timer.periodic(segmentDuration, (timer) {
      if (!_recording) {
        timer.cancel();
        return;
      }
      unawaited(_rotateSegments());
    });
    return true;
  }

  /// Stops capture and schedules finalization. Fast: only stops the
  /// recorders (the call's tracks are about to be disposed) and hands the
  /// trailing uploads + metadata finalization to the background. Idempotent;
  /// safe to call from every call-end path.
  Future<void> stop() async {
    if (!_recording || _finalizing) return;
    _finalizing = true;
    _recording = false;

    final trailing = <_Segment>[];
    final mic = await _stopMicSegment();
    if (mic != null) trailing.add(mic);
    final peerAudio = await _stopPeerAudioSegment();
    if (peerAudio != null) trailing.add(peerAudio);
    final video = await _stopVideoSegment();
    if (video != null) trailing.add(video);

    unawaited(_drainAndFinalize(trailing));
  }

  Future<void> _drainAndFinalize(List<_Segment> trailing) async {
    for (final seg in trailing) {
      unawaited(_uploadSegment(seg));
    }
    // Give trailing uploads a bounded window to land before finalizing so
    // the parts array is complete in the common case; stragglers still
    // persist themselves afterwards.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (_pendingUploads > 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await _finalize('complete');
    _resetState();
  }

  // ── Segment rotation ────────────────────────────────────────────────────

  Future<void> _rotateSegments() async {
    if (!_recording || _rotating) return;
    _rotating = true;
    try {
      // Stop the current segments first, then immediately start the next
      // ones — the upload runs in the background and never blocks capture.
      final finalized = <_Segment>[];
      final mic = await _stopMicSegment();
      if (mic != null) finalized.add(mic);
      final peerAudio = await _stopPeerAudioSegment();
      if (peerAudio != null) finalized.add(peerAudio);
      final video = await _stopVideoSegment();
      if (video != null) finalized.add(video);

      unawaited(_startMicSegment());
      if (_sessionType == CallType.audio && !kIsWeb && Platform.isAndroid) {
        unawaited(_startPeerAudioSegment());
      }
      if (_sessionType == CallType.video) {
        final tracks =
            WebRtcCallEngine.instance.remoteStreamOrNull?.getVideoTracks();
        if (tracks?.isNotEmpty ?? false) {
          unawaited(_startVideoSegment(tracks!.first));
        }
      }

      for (final seg in finalized) {
        unawaited(_uploadSegment(seg));
      }
    } finally {
      _rotating = false;
    }
  }

  Future<String> _nextSegmentPath(String kind, int seq, String ext) async {
    final dir = _dirPath ?? (await getTemporaryDirectory()).path;
    return '$dir/${_sessionId ?? 'call'}_${kind}_$seq.$ext';
  }

  // ── Mic track (record package, all platforms) ───────────────────────────

  Future<bool> _startMicSegment() async {
    try {
      final recorder = _micRecorder ??= CallMicRecorder();
      final path = await _nextSegmentPath('mic', _micSeq, 'm4a');
      final ok = await recorder.start(path);
      return ok;
    } catch (_) {
      return false;
    }
  }

  Future<_Segment?> _stopMicSegment() async {
    final recorder = _micRecorder;
    if (recorder == null || !_micActive) return null;
    _micActive = false;
    final path = await recorder.stop();
    if (path == null) return null;
    return _Segment(kind: 'mic', index: _micSeq++, path: path, ext: 'm4a');
  }

  // ── Peer audio track (Android voice calls, wav via OUTPUT channel) ──────

  Future<bool> _startPeerAudioSegment() async {
    try {
      final path = await _nextSegmentPath('remote', _peerAudioSeq, 'wav');
      final recorder = _peerAudioRecorder ??= MediaRecorder(albumName: null);
      await recorder.start(path, audioChannel: RecorderAudioChannel.OUTPUT);
      return true;
    } catch (_) {
      _peerAudioRecorder = null;
      return false;
    }
  }

  Future<_Segment?> _stopPeerAudioSegment() async {
    final recorder = _peerAudioRecorder;
    if (recorder == null || !_peerAudioActive) return null;
    _peerAudioActive = false;
    try {
      final result = await recorder.stop();
      _peerAudioRecorder = null;
      final path = result is String ? result : null;
      if (path == null) return null;
      return _Segment(
          kind: 'remote', index: _peerAudioSeq++, path: path, ext: 'wav');
    } catch (_) {
      _peerAudioRecorder = null;
      return null;
    }
  }

  // ── Muxed peer video+audio (video calls, mp4) ───────────────────────────

  Future<bool> _startVideoSegment(MediaStreamTrack videoTrack) async {
    try {
      final path = await _nextSegmentPath('video', _videoSeq, 'mp4');
      final recorder = _videoRecorder ??= MediaRecorder(albumName: null);
      await recorder.start(
        path,
        videoTrack: videoTrack,
        audioChannel: RecorderAudioChannel.OUTPUT,
      );
      return true;
    } catch (_) {
      _videoRecorder = null;
      return false;
    }
  }

  Future<_Segment?> _stopVideoSegment() async {
    final recorder = _videoRecorder;
    if (recorder == null || !_videoActive) return null;
    _videoActive = false;
    try {
      final result = await recorder.stop();
      _videoRecorder = null;
      final path = result is String ? result : null;
      if (path == null) return null;
      return _Segment(
          kind: 'video', index: _videoSeq++, path: path, ext: 'mp4');
    } catch (_) {
      _videoRecorder = null;
      return null;
    }
  }

  // ── Upload + metadata ───────────────────────────────────────────────────

  Future<void> _uploadSegment(_Segment seg) async {
    _pendingUploads++;
    try {
      final file = File(seg.path);
      if (!await file.exists()) return;
      var ok = await _putSegment(file, seg);
      if (!ok) ok = await _putSegment(file, seg); // single retry
      if (ok) {
        final bytes = await file.length();
        _parts.add({
          'kind': seg.kind,
          'index': seg.index,
          'key': seg.key,
          'url': seg.url,
          'bytes': bytes,
        });
        await _persistParts();
      }
      try {
        await file.delete();
      } catch (_) {}
    } catch (_) {
      // Segment lost — the recording continues; the gap shows in playback.
    } finally {
      _pendingUploads--;
    }
  }

  Future<bool> _putSegment(File file, _Segment seg) async {
    try {
      final res = await SupabaseService.callFunction('get-r2-upload-url',
          body: {
            'folder': _folder,
            'extension': seg.ext,
            'fileName': seg.fileName,
          });
      final uploadUrl = res['uploadUrl'] as String?;
      final key = res['key'] as String?;
      final url = res['publicUrl'] as String?;
      final rawHeaders = res['headers'];
      if (uploadUrl == null || key == null || url == null) return false;

      final headers = rawHeaders is Map
          ? rawHeaders.map((k, v) => MapEntry(k.toString(), v.toString()))
          : <String, String>{};
      headers.remove('Host'); // dart:io derives Host from the URI.
      headers.remove('Content-Length');

      final bytes = await file.readAsBytes();
      final response = await http
          .put(Uri.parse(uploadUrl), headers: headers, body: bytes)
          .timeout(const Duration(minutes: 5));
      if (response.statusCode == 200 || response.statusCode == 201) {
        seg.key = key;
        seg.url = url;
        return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Persists the parts array through a serialized chain — concurrent
  /// segment uploads must not last-write-wins over each other.
  Future<void> _persistParts() async {
    final rowId = _recordingRowId;
    if (rowId == null) return;
    final snapshot = List<Map<String, dynamic>>.from(_parts);
    _partsPersistChain = _partsPersistChain.then((_) async {
      try {
        await SupabaseService.client
            .from('call_recordings')
            .update({'parts': snapshot}).eq('id', rowId);
      } catch (_) {}
    });
    await _partsPersistChain;
  }

  Future<void> _finalize(String status) async {
    final rowId = _recordingRowId;
    if (rowId == null) return;
    try {
      final started = _startedAt;
      await SupabaseService.client.from('call_recordings').update({
        'status': status,
        'ended_at': DateTime.now().toUtc().toIso8601String(),
        'duration_seconds':
            started != null ? DateTime.now().difference(started).inSeconds : 0,
      }).eq('id', rowId);
    } catch (_) {}
  }

  void _resetState() {
    _recording = false;
    _finalizing = false;
    _sessionId = null;
    _sessionType = null;
    _recordingRowId = null;
    _startedAt = null;
    _dirPath = null;
    _micRecorder = null;
    _peerAudioRecorder = null;
    _videoRecorder = null;
    _micActive = _peerAudioActive = _videoActive = false;
  }

  // ── Delete (Recordings screen) ──────────────────────────────────────────

  /// Deletes a finished recording: the metadata row plus every uploaded R2
  /// part. Failures are tolerated (orphaned parts are harmless).
  static Future<void> deleteRecording(String rowId, List parts) async {
    for (final part in parts) {
      if (part is Map && part['key'] is String) {
        try {
          await SupabaseService.callFunction('delete-r2-object',
              body: {'key': part['key']});
        } catch (_) {}
      }
    }
    try {
      await SupabaseService.client
          .from('call_recordings')
          .delete()
          .eq('id', rowId);
    } catch (_) {}
  }
}
