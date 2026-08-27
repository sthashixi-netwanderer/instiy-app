import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/call_model.dart';
import 'secrets_service.dart';

class WebRtcCallEngine {
  WebRtcCallEngine._();
  static final WebRtcCallEngine instance = WebRtcCallEngine._();

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  CallType _callType = CallType.audio;

  bool get isMicMuted {
    final track = _localStream?.getAudioTracks().firstOrNull;
    return track == null ? false : !track.enabled;
  }

  bool get isCameraOff {
    final track = _localStream?.getVideoTracks().firstOrNull;
    return track == null ? true : !track.enabled;
  }

  bool get peerReady => _pc != null;

  MediaStream? get remoteStreamOrNull => _remoteStream;

  List<Map<String, dynamic>> _iceServers() {
    final servers = <Map<String, dynamic>>[
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ];
    final turnUrls = SecretsService.instance.turnUrl;
    if (turnUrls.isNotEmpty) {
      final urls = turnUrls.split(',').map((u) => u.trim()).where((u) => u.isNotEmpty).toList();
      debugPrint('WebRtcEngine: using TURN $urls user=${SecretsService.instance.turnUsername}');
      servers.add({
        'urls': urls,
        'username': SecretsService.instance.turnUsername,
        'credential': SecretsService.instance.turnCredential,
      });
    } else {
      debugPrint('WebRtcEngine: TURN not configured — STUN-only (set TURN_URL/USERNAME/CREDENTIAL)');
    }
    return servers;
  }

  static Future<bool> requestPermissions(CallType type) async {
    try {
      final statuses = await [
        Permission.microphone,
        if (type == CallType.video) Permission.camera,
      ].request();
      return statuses.values.every((s) => s.isGranted || s.isLimited);
    } catch (_) {
      return true;
    }
  }

  Future<void> startLocalMedia(CallType type) async {
    await dispose();
    _callType = type;
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': type == CallType.video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
              'frameRate': {'ideal': 24},
            }
          : false,
    });
  }

  Future<RTCVideoRenderer> createLocalRenderer() async {
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    renderer.srcObject = _localStream;
    return renderer;
  }

  Future<RTCVideoRenderer> createRemoteRenderer() async {
    final renderer = RTCVideoRenderer();
    await renderer.initialize();
    return renderer;
  }

  Future<void> initializePeerConnection({
    required void Function(RTCIceCandidate) onLocalCandidate,
    required void Function(RTCPeerConnectionState) onConnectionState,
    required void Function(MediaStream) onRemoteStream,
  }) async {
    final ice = _iceServers();
    debugPrint('WebRtcEngine: creating PeerConnection iceServers=$ice');
    _pc = await createPeerConnection({
      'iceServers': ice,
      'sdpSemantics': 'unified-plan',
      'iceCandidatePoolSize': 4,
    });

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        await _pc!.addTrack(track, stream);
      }
    }

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate != null) onLocalCandidate(candidate);
    };

    _pc!.onConnectionState = (state) => onConnectionState(state);

    _pc!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams.first;
        onRemoteStream(event.streams.first);
      }
    };
  }

  Future<RTCSessionDescription> createOffer() async {
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    return offer;
  }

  Future<RTCSessionDescription> createAnswer() async {
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    return answer;
  }

  Future<void> setRemoteDescription(Map<String, dynamic> sdpMap, String type) async {
    await _pc!.setRemoteDescription(
      RTCSessionDescription(sdpMap['sdp'] as String, type),
    );
  }

  Future<void> addRemoteCandidate(Map<String, dynamic> candidateMap) async {
    final candidate = candidateMap['candidate'];
    if (candidate == null) return;
    await _pc!.addCandidate(
      RTCIceCandidate(
        candidate as String,
        candidateMap['sdpMid'] as String?,
        candidateMap['sdpMLineIndex'] as int?,
      ),
    );
  }

  /// True when the remote side is actually sending video frames.
  /// Uses inbound-rtp stats so a disabled remote camera reads as inactive
  /// even though the track itself still exists.
  Future<bool> remoteVideoActive() async {
    if (_callType != CallType.video) return false;
    final pc = _pc;
    if (pc == null) return false;
    try {
      final stats = await pc.getStats();
      for (final report in stats) {
        if (report.type == 'inbound-rtp' && report.values['kind'] == 'video') {
          final fps = report.values['framesPerSecond'];
          final frames =
              report.values['framesDecoded'] ?? report.values['framesReceived'];
          if (fps is num && fps > 0) return true;
          if (frames is num && frames > 0) return true;
        }
      }
    } catch (_) {}
    return false;
  }

  Future<void> toggleMic(bool muted) async {
    for (final track in _localStream?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
  }

  Future<void> toggleCamera(bool off) async {
    for (final track in _localStream?.getVideoTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !off;
    }
  }

  Future<void> switchCamera() async {
    final track = _localStream?.getVideoTracks().firstOrNull;
    if (track != null) {
      try {
        await Helper.switchCamera(track);
      } catch (e) {
        debugPrint('WebRtcEngine: switchCamera failed: $e');
      }
    }
  }

  Future<void> setSpeakerphone(bool on) async {
    try {
      await Helper.setSpeakerphoneOn(on);
    } catch (e) {
      debugPrint('WebRtcEngine: speakerphone control unavailable: $e');
    }
  }

  Future<void> dispose() async {
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    _remoteStream = null;
  }
}
