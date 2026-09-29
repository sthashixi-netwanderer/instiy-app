import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'package:video_player/video_player.dart';

import '../../config/app_theme.dart';
import '../../services/call_recording_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/responsive.dart';
import '../../widgets/skeleton.dart';

/// List of this user's call recordings (metadata in call_recordings, media
/// in R2). Tapping a row expands an inline player: voice recordings play
/// their mic and peer-audio tracks merged; video recordings chain their
/// muxed mp4 segments.
class RecordingsScreen extends ConsumerStatefulWidget {
  const RecordingsScreen({super.key});

  @override
  ConsumerState<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends ConsumerState<RecordingsScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _recordings = [];
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = SupabaseService.client.auth.currentUser?.id;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final rows = await SupabaseService.client
          .from('call_recordings')
          .select()
          .eq('recorded_by', uid)
          .order('started_at', ascending: false)
          .limit(200);
      if (!mounted) return;
      setState(() {
        _recordings = (rows as List)
            .map((row) => row as Map<String, dynamic>)
            .toList();
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> recording) async {
    final id = recording['id'] as String?;
    if (id == null) return;
    final confirmed = await showShadDialog<bool>(
      context: context,
      builder: (context) => ShadDialog.alert(
        title: const Text('Delete recording?'),
        description: const Text(
            'The recording and its uploaded files will be permanently removed.'),
        actions: [
          ShadButton.outline(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ShadButton.destructive(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final parts = (recording['parts'] as List?) ?? const [];
    await CallRecordingService.deleteRecording(id, parts);
    if (mounted) {
      setState(() {
        _recordings.removeWhere((r) => r['id'] == id);
        if (_expandedId == id) _expandedId = null;
      });
      ShadToaster.of(context).show(
        const ShadToast(title: Text('Recording deleted')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.cleanBackground,
      extendBodyBehindAppBar: true,
      appBar: AppTheme.glassAppBar(
        context: context,
        title: const Text('Recordings'),
      ),
      body: _isLoading
          ? Padding(
              padding: EdgeInsets.only(
                top: MediaQuery.paddingOf(context).top + 72,
              ),
              child: const ListSkeleton(count: 5),
            )
          : _recordings.isEmpty
              ? Padding(
                  padding: EdgeInsets.only(
                    top: MediaQuery.paddingOf(context).top + 72,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          LucideIcons.disc,
                          size: context.ri(44),
                          color: AppTheme.mutedSteel.withValues(alpha: 0.4),
                        ),
                        SizedBox(height: context.rh(12)),
                        Text(
                          'No recordings yet',
                          style: TextStyle(
                            fontSize: context.rsp(15),
                            fontWeight: FontWeight.w600,
                            color: AppTheme.charcoalInk,
                          ),
                        ),
                        SizedBox(height: context.rh(4)),
                        Text(
                          'Start a call and tap the record button to capture it.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: context.rsp(12),
                            color: AppTheme.mutedSteel,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    8,
                    MediaQuery.paddingOf(context).top + 72,
                    8,
                    24,
                  ),
                  itemCount: _recordings.length,
                  separatorBuilder: (_, _) => const Divider(indent: 16),
                  itemBuilder: (context, index) {
                    final recording = _recordings[index];
                    final id = recording['id'] as String?;
                    final expanded = id != null && _expandedId == id;
                    return _RecordingTile(
                      recording: recording,
                      expanded: expanded,
                      onToggle: () => setState(() {
                        _expandedId = expanded ? null : id;
                      }),
                      onDelete: () => _delete(recording),
                    );
                  },
                ),
    );
  }
}

class _RecordingTile extends StatelessWidget {
  final Map<String, dynamic> recording;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _RecordingTile({
    required this.recording,
    required this.expanded,
    required this.onToggle,
    required this.onDelete,
  });

  bool get _isVideo => recording['call_type'] == 'video';

  String get _statusLabel {
    switch (recording['status'] as String?) {
      case 'complete':
        return 'Complete';
      case 'failed':
        return 'Failed';
      default:
        return 'Partial';
    }
  }

  Color get _statusColor {
    switch (recording['status'] as String?) {
      case 'complete':
        return AppTheme.successMoss;
      case 'failed':
        return AppTheme.destructive;
      default:
        return AppTheme.warningAmber;
    }
  }

  String get _durationLabel {
    final seconds = (recording['duration_seconds'] as num?)?.toInt() ?? 0;
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String get _dateLabel {
    final raw = recording['started_at'] as String?;
    final at = raw != null ? DateTime.tryParse(raw)?.toLocal() : null;
    if (at == null) return '';
    return '${at.year}-${at.month.toString().padLeft(2, '0')}-${at.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final parts = (recording['parts'] as List?) ?? const [];
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.pureSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.whisperBorder),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: parts.isEmpty ? null : onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.accent.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      _isVideo ? LucideIcons.video : LucideIcons.phone,
                      size: 20,
                      color: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (recording['peer_name'] as String?)?.isNotEmpty ==
                                  true
                              ? recording['peer_name'] as String
                              : 'Unknown',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.charcoalInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_isVideo ? 'Video call' : 'Voice call'} · $_dateLabel · $_durationLabel',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.mutedSteel,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: _statusColor,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      LucideIcons.trash2,
                      size: 18,
                      color: AppTheme.mutedSteel,
                    ),
                    onPressed: onDelete,
                  ),
                  if (parts.isNotEmpty)
                    Icon(
                      expanded
                          ? LucideIcons.chevronUp
                          : LucideIcons.play,
                      size: 18,
                      color: AppTheme.accent,
                    ),
                ],
              ),
            ),
          ),
          if (expanded && parts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _RecordingPlayer(parts: parts, isVideo: _isVideo),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Playback
// ─────────────────────────────────────────────────────────────────────────────

List<String> _partUrls(List parts, String kind) {
  final entries = parts
      .whereType<Map>()
      .where((p) => p['kind'] == kind && p['url'] is String)
      .toList()
    ..sort((a, b) =>
        ((a['index'] as num?) ?? 0).compareTo(((b['index'] as num?) ?? 0)));
  return entries.map((p) => p['url'] as String).toList();
}

/// Picks the right player for a recording's parts.
class _RecordingPlayer extends StatelessWidget {
  final List parts;
  final bool isVideo;

  const _RecordingPlayer({required this.parts, required this.isVideo});

  @override
  Widget build(BuildContext context) {
    final videoUrls = _partUrls(parts, 'video');
    final micUrls = _partUrls(parts, 'mic');
    final remoteUrls = _partUrls(parts, 'remote');

    if (isVideo && videoUrls.isNotEmpty) {
      return _VideoPlaylistPlayer(urls: videoUrls);
    }
    if (micUrls.isEmpty && remoteUrls.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          'This recording has no playable media yet.',
          style: TextStyle(fontSize: 12, color: AppTheme.mutedSteel),
        ),
      );
    }
    return _DualAudioPlayer(primaryUrls: micUrls, secondaryUrls: remoteUrls);
  }
}

/// Merged playback of the two conversation sides: the mic track (what the
/// recorder said) and the peer track (what they said) are the same call
/// captured from one device, so both players run simultaneously and advance
/// segment-by-segment together. When one side is missing (iOS voice calls
/// only capture the mic), the single track plays alone.
class _DualAudioPlayer extends StatefulWidget {
  final List<String> primaryUrls;
  final List<String> secondaryUrls;

  const _DualAudioPlayer({
    required this.primaryUrls,
    required this.secondaryUrls,
  });

  @override
  State<_DualAudioPlayer> createState() => _DualAudioPlayerState();
}

class _DualAudioPlayerState extends State<_DualAudioPlayer> {
  AudioPlayer? _primary;
  AudioPlayer? _secondary;
  int _segment = 0;
  bool _playing = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _primaryDone = false;
  bool _secondaryDone = false;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _primaryCompleteSub;
  StreamSubscription? _secondaryCompleteSub;

  bool get _hasSecondary => widget.secondaryUrls.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _loadSegment();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _primaryCompleteSub?.cancel();
    _secondaryCompleteSub?.cancel();
    _primary?.dispose();
    _secondary?.dispose();
    super.dispose();
  }

  String? _urlAt(List<String> urls, int i) =>
      (i >= 0 && i < urls.length) ? urls[i] : null;

  Future<void> _loadSegment() async {
    final primaryUrl = _urlAt(widget.primaryUrls, _segment);
    final secondaryUrl = _urlAt(widget.secondaryUrls, _segment);
    if (primaryUrl == null && secondaryUrl == null) return;
    _primaryDone = primaryUrl == null;
    _secondaryDone = secondaryUrl == null || !_hasSecondary;
    _position = Duration.zero;
    _duration = Duration.zero;

    try {
      final primary = _primary ??= AudioPlayer();
      await _primaryCompleteSub?.cancel();
      await primary.stop();
      if (primaryUrl != null) {
        _primaryCompleteSub = primary.onPlayerComplete.listen((_) {
          _primaryDone = true;
          _maybeAdvance();
        });
        await _posSub?.cancel();
        _posSub = primary.onPositionChanged
            .listen((p) => mounted ? setState(() => _position = p) : null);
        await _durSub?.cancel();
        _durSub = primary.onDurationChanged
            .listen((d) => mounted ? setState(() => _duration = d) : null);
        await primary.setSource(UrlSource(primaryUrl));
      }
    } catch (_) {}

    if (_hasSecondary) {
      try {
        final secondary = _secondary ??= AudioPlayer();
        await _secondaryCompleteSub?.cancel();
        await secondary.stop();
        if (secondaryUrl != null) {
          await _secondaryCompleteSub?.cancel();
          _secondaryCompleteSub = secondary.onPlayerComplete.listen((_) {
            _secondaryDone = true;
            _maybeAdvance();
          });
          await secondary.setSource(UrlSource(secondaryUrl));
        }
      } catch (_) {}
    }

    if (mounted) setState(() {});
    await _playBoth();
  }

  Future<void> _playBoth() async {
    try {
      if (!_primaryDone) await _primary?.resume();
      if (_hasSecondary && !_secondaryDone) await _secondary?.resume();
      if (mounted) setState(() => _playing = true);
    } catch (_) {}
  }

  Future<void> _pauseBoth() async {
    try {
      await _primary?.pause();
      await _secondary?.pause();
      if (mounted) setState(() => _playing = false);
    } catch (_) {}
  }

  /// A segment advances only when every active side finished it, so the two
  /// conversation sides stay aligned.
  void _maybeAdvance() {
    if (!(_primaryDone || _primary == null)) return;
    if (_hasSecondary && !_secondaryDone) return;
    final nextPrimary = _urlAt(widget.primaryUrls, _segment + 1);
    final nextSecondary = _urlAt(widget.secondaryUrls, _segment + 1);
    if (nextPrimary == null && nextSecondary == null) {
      if (mounted) setState(() => _playing = false);
      return;
    }
    _segment++;
    unawaited(_loadSegment());
  }

  @override
  Widget build(BuildContext context) {
    final totalSegments =
        widget.primaryUrls.length > widget.secondaryUrls.length
            ? widget.primaryUrls.length
            : widget.secondaryUrls.length;
    String label = '0:00';
    final p = _position;
    label =
        '${p.inMinutes.remainder(60).toString().padLeft(2, '0')}:${p.inSeconds.remainder(60).toString().padLeft(2, '0')}';
    final d = _duration;
    final durLabel = _duration == Duration.zero
        ? '--:--'
        : '${d.inMinutes.remainder(60).toString().padLeft(2, '0')}:${d.inSeconds.remainder(60).toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.warmMist,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () =>
                    _playing ? unawaited(_pauseBoth()) : unawaited(_playBoth()),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.accent,
                  ),
                  child: Icon(
                    _playing ? LucideIcons.pause : LucideIcons.play,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$label / $durLabel',
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.mutedSteel),
                ),
              ),
              if (totalSegments > 1)
                Text(
                  'Segment ${_segment + 1}/$totalSegments',
                  style: const TextStyle(
                      fontSize: 11, color: AppTheme.mutedSteel),
                ),
            ],
          ),
          if (!_hasSecondary)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Mic track only — the other side was not captured on this device.',
                style: TextStyle(fontSize: 11, color: AppTheme.mutedSteel),
              ),
            ),
        ],
      ),
    );
  }
}

/// Chains the muxed mp4 segments of a video-call recording: when a segment
/// finishes, the next controller loads and resumes playing.
class _VideoPlaylistPlayer extends StatefulWidget {
  final List<String> urls;

  const _VideoPlaylistPlayer({required this.urls});

  @override
  State<_VideoPlaylistPlayer> createState() => _VideoPlaylistPlayerState();
}

class _VideoPlaylistPlayerState extends State<_VideoPlaylistPlayer> {
  VideoPlayerController? _controller;
  int _segment = 0;
  bool _initialized = false;
  bool _playing = false;
  bool _switching = false;

  @override
  void initState() {
    super.initState();
    _loadSegment();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onControllerUpdated);
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _loadSegment() async {
    if (_segment >= widget.urls.length) return;
    _switching = true;
    _initialized = false;
    final old = _controller;
    final controller =
        VideoPlayerController.networkUrl(Uri.parse(widget.urls[_segment]));
    _controller = controller;
    controller.addListener(_onControllerUpdated);
    if (mounted) setState(() {});
    try {
      await controller.initialize();
      if (mounted) setState(() => _initialized = true);
      unawaited(controller.play());
      _playing = true;
    } catch (_) {}
    if (old != null && old != controller) {
      old.removeListener(_onControllerUpdated);
      try {
        await old.dispose();
      } catch (_) {}
    }
    _switching = false;
    if (mounted) setState(() {});
  }

  void _onControllerUpdated() {
    final controller = _controller;
    if (controller == null || _switching || !controller.value.isInitialized) {
      return;
    }
    final value = controller.value;
    if (value.position >= value.duration &&
        value.duration > Duration.zero &&
        !value.isPlaying) {
      if (_segment < widget.urls.length - 1) {
        _segment++;
        unawaited(_loadSegment());
        return;
      }
    }
    if (mounted &&
        (_playing != value.isPlaying ||
            _initialized != controller.value.isInitialized)) {
      setState(() {
        _playing = value.isPlaying;
        _initialized = value.isInitialized;
      });
    }
  }

  void _toggle() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isPlaying) {
      unawaited(controller.pause());
    } else {
      unawaited(controller.play());
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Positioned.fill(
              child: ColoredBox(color: Colors.black),
            ),
            if (controller != null && _initialized)
              AspectRatio(
                aspectRatio: controller.value.aspectRatio == 0
                    ? 16 / 9
                    : controller.value.aspectRatio,
                child: VideoPlayer(controller),
              )
            else
              const CircularProgressIndicator(strokeWidth: 2),
            Positioned.fill(
              child: GestureDetector(
                onTap: _toggle,
                behavior: HitTestBehavior.opaque,
                child: Center(
                  child: _playing
                      ? const SizedBox.shrink()
                      : Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.black54,
                          ),
                          child: const Icon(
                            LucideIcons.play,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ),
            if (widget.urls.length > 1)
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Segment ${_segment + 1}/${widget.urls.length}',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 11),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
