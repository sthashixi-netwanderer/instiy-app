import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../models/call_model.dart';
import '../../providers/call_controller.dart';
import '../../providers/providers.dart';
import '../../services/webrtc_call_service.dart';

/// Full-screen call surface rendered above every route via the app-level
/// overlay stack. State comes from [callProvider]; the widget itself is dumb.
class CallOverlay extends ConsumerWidget {
  const CallOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(callProvider);
    final session = controller.session;

    if (session == null || session.status == CallStatus.idle) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: Material(
        color: Colors.transparent,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF101828), Color(0xFF1D2939)],
            ),
          ),
          child: SafeArea(
            child: switch (session.status) {
              CallStatus.ringingIncoming =>
                _IncomingCallView(session: session, controller: controller),
              CallStatus.ringingOutgoing ||
              CallStatus.connecting =>
                _WaitingCallView(session: session, controller: controller),
              CallStatus.active =>
                _ActiveCallView(session: session, controller: controller),
              CallStatus.ended => const _EndedCallBadge(),
              CallStatus.idle => const SizedBox.shrink(),
            },
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared pieces
// ─────────────────────────────────────────────────────────────────────────────

const double _avatarSize = 132;

class _PeerAvatar extends StatelessWidget {
  final CallSession session;
  const _PeerAvatar({required this.session});

  @override
  Widget build(BuildContext context) {
    final initial = (session.peerName?.isNotEmpty ?? false)
        ? session.peerName![0].toUpperCase()
        : '?';
    return ClipOval(
      child: SizedBox(
        width: _avatarSize,
        height: _avatarSize,
        child: session.peerAvatar != null && session.peerAvatar!.isNotEmpty
            ? Image.network(
                session.peerAvatar!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => _FallbackAvatar(initial: initial),
              )
            : _FallbackAvatar(initial: initial),
      ),
    );
  }
}

class _FallbackAvatar extends StatelessWidget {
  final String initial;
  const _FallbackAvatar({required this.initial});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF344054),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 48,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _PulsingAvatar extends StatefulWidget {
  final CallSession session;
  const _PulsingAvatar({required this.session});

  @override
  State<_PulsingAvatar> createState() => _PulsingAvatarState();
}

class _PulsingAvatarState extends State<_PulsingAvatar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  double _phase(int i) {
    final raw = (_ctrl.value - i * 0.5).clamp(0.0, 1.0);
    return Curves.easeOut.transform(raw);
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return SizedBox(
          width: _avatarSize + 68,
          height: _avatarSize + 68,
          child: Stack(
            alignment: Alignment.center,
            children: [
              for (var i = 0; i < 2; i++)
                Container(
                  width: _avatarSize + _phase(i) * 60,
                  height: _avatarSize + _phase(i) * 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.35 * (1 - _phase(i))),
                      width: 2,
                    ),
                  ),
                ),
              _PeerAvatar(session: widget.session),
            ],
          ),
        );
      },
    );
  }
}

class _ControlButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _ControlButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.12),
        ),
        alignment: Alignment.center,
        child: Icon(
          icon,
          size: 26,
          color: active ? const Color(0xFF101828) : Colors.white,
        ),
      ),
    );
  }
}

class _EndCallButton extends StatelessWidget {
  final VoidCallback onTap;
  const _EndCallButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 66,
        height: 66,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFFEF4444),
        ),
        alignment: Alignment.center,
        child: const Icon(LucideIcons.phoneOff, size: 28, color: Colors.white),
      ),
    );
  }
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

// ─────────────────────────────────────────────────────────────────────────────
// Incoming ring
// ─────────────────────────────────────────────────────────────────────────────

class _IncomingCallView extends StatelessWidget {
  final CallSession session;
  final CallController controller;

  const _IncomingCallView({required this.session, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Spacer(flex: 3),
        _PulsingAvatar(session: session),
        const SizedBox(height: 24),
        Text(
          session.peerName ?? 'Unknown',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          session.type == CallType.video
              ? 'Instiy video call…'
              : 'Instiy voice call…',
          style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 15),
        ),
        const Spacer(flex: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 56),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _RoundAction(
                icon: LucideIcons.phoneOff,
                color: const Color(0xFFEF4444),
                label: 'Decline',
                onTap: () => controller.rejectCall(),
              ),
              _RoundAction(
                icon: session.type == CallType.video
                    ? LucideIcons.video
                    : LucideIcons.phone,
                color: const Color(0xFF22C55E),
                label: 'Accept',
                onTap: () => controller.acceptCall(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  const _RoundAction({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
            alignment: Alignment.center,
            child: Icon(icon, size: 30, color: Colors.white),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(color: Color(0xFF98A2B3), fontSize: 13),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Outgoing / connecting
// ─────────────────────────────────────────────────────────────────────────────

class _WaitingCallView extends StatelessWidget {
  final CallSession session;
  final CallController controller;

  const _WaitingCallView({required this.session, required this.controller});

  @override
  Widget build(BuildContext context) {
    final connecting = session.status == CallStatus.connecting;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 24),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(LucideIcons.lock, size: 13, color: Color(0xFF667085)),
              const SizedBox(width: 6),
              Text(
                session.type == CallType.video
                    ? 'Instiy video call'
                    : 'Instiy voice call',
                style: const TextStyle(color: Color(0xFF667085), fontSize: 12),
              ),
            ],
          ),
        ),
        const Spacer(flex: 3),
        connecting
            ? _PeerAvatar(session: session)
            : _PulsingAvatar(session: session),
        const SizedBox(height: 24),
        Text(
          session.peerName ?? 'Unknown',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          session.statusLabel,
          style: TextStyle(
            color: connecting ? const Color(0xFF22C55E) : const Color(0xFF98A2B3),
            fontSize: 15,
          ),
        ),
        const Spacer(flex: 4),
        Center(
          child: _ControlButton(
            icon: controller.micMuted ? LucideIcons.micOff : LucideIcons.mic,
            active: controller.micMuted,
            onTap: () => controller.toggleMic(),
          ),
        ),
        const SizedBox(height: 32),
        Center(child: _EndCallButton(onTap: () => controller.endCall())),
        const SizedBox(height: 40),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active call
// ─────────────────────────────────────────────────────────────────────────────

class _ActiveCallView extends StatefulWidget {
  final CallSession session;
  final CallController controller;

  const _ActiveCallView({required this.session, required this.controller});

  @override
  State<_ActiveCallView> createState() => _ActiveCallViewState();
}

class _ActiveCallViewState extends State<_ActiveCallView> {
  Timer? _ticker;
  Timer? _videoPoll;
  Duration _elapsed = Duration.zero;
  Offset _pipOffset = const Offset(16, 90);

  @override
  void initState() {
    super.initState();
    final start = widget.controller.connectedAt ?? DateTime.now();
    _elapsed = DateTime.now().difference(start);
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsed = DateTime.now().difference(start));
    });
    if (widget.session.type == CallType.video) {
      _videoPoll = Timer.periodic(const Duration(seconds: 2), (_) async {
        if (!mounted) return;
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _videoPoll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = widget.session.type == CallType.video;
    return Stack(
      children: [
        if (isVideo)
          const _RemoteVideoLayer()
        else
          _AudioBackdrop(session: widget.session),
        Positioned(
          top: 18,
          left: 20,
          right: 20,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.session.peerName ?? 'Unknown',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_formatDuration(_elapsed)} · encrypted',
                      style: const TextStyle(
                        color: Color(0xFF98A2B3),
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: Colors.white.withValues(alpha: 0.10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        color: Color(0xFF22C55E),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Connected',
                      style: TextStyle(color: Colors.white70, fontSize: 11.5),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (isVideo)
          _DraggableLocalPip(
            initialOffset: _pipOffset,
            onMoved: (o) => _pipOffset = o,
          ),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 36, left: 16, right: 16),
            child: _buildControls(isVideo),
          ),
        ),
      ],
    );
  }

  Widget _buildControls(bool isVideo) {
    final c = widget.controller;
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      alignment: WrapAlignment.center,
      children: [
        _ControlButton(
          icon: c.micMuted ? LucideIcons.micOff : LucideIcons.mic,
          active: c.micMuted,
          onTap: () => c.toggleMic(),
        ),
        if (isVideo)
          _ControlButton(
            icon: c.cameraOff ? LucideIcons.videoOff : LucideIcons.video,
            active: c.cameraOff,
            onTap: () => c.toggleCamera(),
          ),
        if (isVideo)
          _ControlButton(
            icon: LucideIcons.switchCamera,
            onTap: () => c.flipCamera(),
          ),
        _ControlButton(
          icon: c.speakerOn ? LucideIcons.volume2 : LucideIcons.volume1,
          active: c.speakerOn,
          onTap: () => c.toggleSpeaker(),
        ),
        _EndCallButton(onTap: () => c.endCall()),
      ],
    );
  }
}

class _RemoteVideoLayer extends StatefulWidget {
  const _RemoteVideoLayer();

  @override
  State<_RemoteVideoLayer> createState() => _RemoteVideoLayerState();
}

class _RemoteVideoLayerState extends State<_RemoteVideoLayer>
    with WidgetsBindingObserver {
  RTCVideoRenderer? _renderer;
  MediaStream? _boundStream;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  Future<void> _bind() async {
    final stream = WebRtcCallEngine.instance.remoteStreamOrNull;
    if (stream == null) {
      await Future.delayed(const Duration(milliseconds: 250));
      if (mounted) await _bind();
      return;
    }
    if (_boundStream == stream && _renderer != null) return;
    try {
      final renderer =
          _renderer ?? await WebRtcCallEngine.instance.createRemoteRenderer();
      renderer.srcObject = stream;
      _boundStream = stream;
      if (mounted) setState(() => _renderer = renderer);
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _renderer?.srcObject = null;
      _renderer?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ProviderScope.containerOf(context).read(callProvider);
    unawaited(_bind());

    return Stack(
      fit: StackFit.expand,
      children: [
        Container(color: const Color(0xFF101828)),
        if (_renderer != null)
          RTCVideoView(
            _renderer!,
            objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
          )
        else
          Center(child: _PulsingAvatar(session: controller.session!)),
      ],
    );
  }
}

class _AudioBackdrop extends StatelessWidget {
  final CallSession session;
  const _AudioBackdrop({required this.session});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulsingAvatar(session: session),
          const SizedBox(height: 20),
          const _VoiceBars(),
        ],
      ),
    );
  }
}

class _VoiceBars extends StatefulWidget {
  const _VoiceBars();

  @override
  State<_VoiceBars> createState() => _VoiceBarsState();
}

class _VoiceBarsState extends State<_VoiceBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(5, (i) {
            final t = math.sin((_ctrl.value * math.pi * 2) + i * 0.9).abs();
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: 4,
              height: 10 + t * 22,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                color: Colors.white.withValues(alpha: 0.55),
              ),
            );
          }),
        );
      },
    );
  }
}

class _DraggableLocalPip extends StatefulWidget {
  final Offset initialOffset;
  final ValueChanged<Offset> onMoved;

  const _DraggableLocalPip({
    required this.initialOffset,
    required this.onMoved,
  });

  @override
  State<_DraggableLocalPip> createState() => _DraggableLocalPipState();
}

class _DraggableLocalPipState extends State<_DraggableLocalPip> {
  RTCVideoRenderer? _renderer;
  late Offset _offset = widget.initialOffset;

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

  Future<void> _initRenderer() async {
    try {
      final r = await WebRtcCallEngine.instance.createLocalRenderer();
      if (mounted) setState(() => _renderer = r);
    } catch (_) {}
  }

  @override
  void dispose() {
    try {
      _renderer?.srcObject = null;
      _renderer?.dispose();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final double dx = _offset.dx.clamp(0.0, math.max(0.0, size.width - 120));
    final double dy =
        _offset.dy.clamp(60.0, math.max(61.0, size.height - 260));

    return Positioned(
      left: dx,
      top: dy,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _offset += d.delta;
          });
          widget.onMoved(_offset);
        },
        child: Container(
          width: 108,
          height: 156,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: const Color(0xFF344054),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.45),
                blurRadius: 14,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: 108,
              height: 192,
              child: _renderer == null
                  ? const SizedBox.expand()
                  : RTCVideoView(
                      _renderer!,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ended flash
// ─────────────────────────────────────────────────────────────────────────────

class _EndedCallBadge extends StatelessWidget {
  const _EndedCallBadge();

  @override
  Widget build(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    final session = container.read(callProvider).session;

    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: Colors.black.withValues(alpha: 0.65),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(LucideIcons.phoneMissed,
                size: 16, color: Color(0xFF98A2B3)),
            const SizedBox(width: 8),
            Text(
              session?.statusLabel ?? 'Call ended',
              style: const TextStyle(color: Colors.white, fontSize: 13.5),
            ),
          ],
        ),
      ),
    );
  }
}
