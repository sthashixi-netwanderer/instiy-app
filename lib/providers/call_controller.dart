import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/call_model.dart';
import '../services/call_signaling_service.dart';
import '../services/local_notification_service.dart';
import '../services/message_service.dart';
import '../services/secrets_service.dart';
import '../services/supabase_service.dart';
import '../services/system_call_ui_service.dart';
import '../services/webrtc_call_service.dart';

class CallController extends ChangeNotifier {
  static const Duration _ringTimeout = Duration(seconds: 30);
  static const Duration _endedFlashDuration = Duration(seconds: 2);

  final CallSignalingService _signaling = CallSignalingService.instance;
  final AudioPlayer _ringPlayer = AudioPlayer();
  final Uuid _uuid = const Uuid();

  /// Last missed incoming call, so the system missed-call "Call back"
  /// action (which carries only the call id) can redial the caller.
  Map<String, dynamic>? _lastMissedCall;
  StreamSubscription<CallEvent?>? _systemUiSub;

  CallSession? _session;
  DateTime? _connectedAt;

  bool micMuted = false;
  bool cameraOff = false;
  bool speakerOn = false;
  MediaStream? remoteStream;

  StreamSubscription<AuthState>? _authSub;
  Timer? _timeoutTimer;
  Timer _endedFlashTimer = Timer(Duration.zero, () {});
  bool _initialized = false;
  bool _acceptingOrConnecting = false;

  final List<Map<String, dynamic>> _pendingCandidates = [];
  Map<String, dynamic>? _pendingOffer;

  void Function()? onCallUiChanged;

  CallSession? get session => _session;
  DateTime? get connectedAt => _connectedAt;
  bool get hasActiveCall => _session?.isActiveOrRinging ?? false;
  String? get currentUserId => SupabaseService.client.auth.currentUser?.id;

  Future<void> ensureInitialized() async {
    if (_initialized) return;
    _initialized = true;

    unawaited(
      SecretsService.instance.ensureLoaded().catchError((_) {}),
    );

    try {
      await _ringPlayer.setReleaseMode(ReleaseMode.loop);
      await _ringPlayer.setVolume(0.9);
    } catch (_) {}

    LocalNotificationService.onCallActionReceived = (action, data) {
      debugPrint('CallController: received notification action: $action data=$data');
      unawaited(_handleCallAction(action, data));
    };

    final userId = currentUserId;
    if (userId != null) {
      await _startRingListener(userId);
    }

    unawaited(_initSystemCallUi());

    _authSub = SupabaseService.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      final newUserId = data.session?.user.id;
      if (event == AuthChangeEvent.signedOut || newUserId == null) {
        unawaited(_signaling.stopListening());
        if (hasActiveCall) {
          unawaited(endCall());
        }
        return;
      }
      if (event == AuthChangeEvent.signedIn ||
          event == AuthChangeEvent.initialSession ||
          event == AuthChangeEvent.tokenRefreshed) {
        unawaited(_startRingListener(newUserId));
      }
    });
  }

  Future<void> _startRingListener(String userId) async {
    await _signaling.listenForInvites(
      userId,
      onInvite: (payload) => unawaited(_handleIncomingInvite(payload)),
      onCancel: (payload) => _handleIncomingCancelled(payload),
    );
  }

  /// Subscribes to the OS call-UI events (accept/decline/timeout from the
  /// native incoming screen) and drops orphaned system UI left by a
  /// previous run — sessions never survive a restart.
  Future<void> _initSystemCallUi() async {
    if (!SystemCallUiService.isSupported) return;
    await SystemCallUiService.clearAll();
    await _systemUiSub?.cancel();
    _systemUiSub = FlutterCallkitIncoming.onEvent.listen(
      (event) {
        final e = event;
        if (e == null) return;
        unawaited(_handleSystemCallEvent(e));
      },
      // The event channel throws here when the native side isn't
      // registered (e.g. hot-restarted after adding the plugin instead
      // of a full reinstall). Swallow it — event-driven accept/decline
      // just won't arrive — instead of crashing the services library.
      onError: (Object e) {
        debugPrint('CallController: system call events unavailable: $e');
      },
    );
  }

  Future<void> _handleSystemCallEvent(CallEvent event) async {
    switch (event) {
      case CallEventActionCallAccept(:final callKitParams):
        await _onSystemAccept(callKitParams);
      case CallEventActionCallDecline(:final callKitParams):
        await _onSystemDecline(callKitParams);
      case CallEventActionCallTimeout(:final id):
        _onSystemTimeout(id);
      case CallEventActionCallEnded(:final callKitParams):
        _onSystemEnded(callKitParams);
      case CallEventActionCallCallback(:final id):
        await _onSystemCallback(id);
      default:
        break;
    }
  }

  Future<void> _onSystemAccept(CallKitParams params) async {
    final session = _session;
    if (session != null && session.id == params.id) {
      if (session.isIncoming && session.isActiveOrRinging) {
        await acceptCall();
      }
      return;
    }
    // Accepted from system UI for a call this isolate never saw (shown
    // from the FCM background handler): rebuild like the open path.
    if (hasActiveCall) return;
    final extra = params.extra;
    final callerId = extra?['caller_id'] as String?;
    final me = currentUserId;
    if (callerId == null || me == null || callerId == me) return;
    _resetControlState();
    final video = (extra?['call_type'] as String?) == 'video';
    final reconstructed = CallSession(
      id: params.id,
      type: video ? CallType.video : CallType.audio,
      isIncoming: true,
      localUserId: me,
      peerId: callerId,
      peerName: (extra?['caller_name'] as String?) ?? 'Instiy User',
      peerAvatar: extra?['caller_avatar'] as String?,
      status: CallStatus.ringingIncoming,
      createdAt: DateTime.now(),
    );
    _setSession(reconstructed);
    await _joinChannelFor(reconstructed);
    await acceptCall();
  }

  Future<void> _onSystemDecline(CallKitParams params) async {
    final session = _session;
    if (session == null || session.id != params.id) return;
    if (session.isIncoming && session.isActiveOrRinging) {
      await rejectCall();
    }
  }

  void _onSystemTimeout(String id) {
    // Remember who rang so "Call back" can redial, then run the same
    // cleanup as a remote cancel; the caller's own timer ends their side.
    final session = _session;
    if (session != null && session.id == id && session.isIncoming) {
      _lastMissedCall = {
        'call_id': id,
        'caller_id': session.peerId,
        'caller_name': session.peerName,
        'caller_avatar': session.peerAvatar,
        'call_type': session.type == CallType.video ? 'video' : 'voice',
      };
    }
    _handleIncomingCancelled({'call_id': id});
  }

  void _onSystemEnded(CallKitParams params) {
    // endCall echoes back as an ended event — only act while still
    // ringing locally; connected sessions end through signaling.
    final session = _session;
    if (session == null || session.id != params.id) return;
    if (session.isIncoming && session.status == CallStatus.ringingIncoming) {
      _handleIncomingCancelled({'call_id': params.id});
    }
  }

  /// Missed-call "Call back" action — redials the stored caller.
  Future<void> _onSystemCallback(String id) async {
    final missed = _lastMissedCall;
    if (missed == null || missed['call_id'] != id) return;
    final peerId = missed['caller_id'] as String?;
    if (peerId == null || hasActiveCall) return;
    await startCall(
      peerId: peerId,
      peerName: missed['caller_name'] as String?,
      peerAvatar: missed['caller_avatar'] as String?,
      video: (missed['call_type'] as String?) == 'video',
    );
  }

  Future<void> startCall({
    required String peerId,
    required String? peerName,
    required String? peerAvatar,
    required bool video,
  }) async {
    final me = currentUserId;
    if (me == null) {
      debugPrint('CallController: startCall aborted — not authenticated');
      return;
    }
    if (me == peerId) {
      debugPrint('CallController: startCall aborted — cannot call self');
      return;
    }
    if (hasActiveCall) {
      debugPrint('CallController: startCall aborted — already in call ${_session?.id}');
      return;
    }

    _resetControlState();

    // Resolve the caller identity shown on the receiver's screen: sellers
    // ring as their business name (same convention as chat), and the profile
    // picture is users.avatar_url — the authoritative source — with auth
    // metadata as fallback.
    final identity = await _resolveUserIdentity(me);
    final myName = identity.displayName ?? 'Instiy User';
    final myAvatar = identity.avatarUrl;

    final session = CallSession(
      id: _uuid.v4(),
      type: video ? CallType.video : CallType.audio,
      isIncoming: false,
      localUserId: me,
      peerId: peerId,
      peerName: peerName,
      peerAvatar: peerAvatar,
      status: CallStatus.callingOutgoing,
      createdAt: DateTime.now(),
    );

    debugPrint('CallController: startCall ${session.id} ${video ? 'video' : 'audio'} to $peerId (caller: $myName)');
    if (SecretsService.instance.turnUrl.isEmpty) {
      debugPrint('CallController: TURN not configured — STUN-only mode, NAT traversal may fail. Set TURN_URL env.');
    }

    final granted = await WebRtcCallEngine.requestPermissions(session.type);
    if (!granted) {
      debugPrint('CallController: permissions denied for ${session.type}');
      _finishLocally(session, CallEndReason.declinedPermission);
      return;
    }

    _setSession(session);
    await _joinChannelFor(session);

    try {
      await WebRtcCallEngine.instance.startLocalMedia(session.type);
      debugPrint('CallController: local media started for ${session.id}');
    } catch (e) {
      debugPrint('CallController: media init failed: $e');
      await _teardownMedia();
      _finishLocally(session, CallEndReason.declinedPermission);
      return;
    }

    final sent = await _signaling.sendInvite(
      calleeId: peerId,
      session: session,
      callerName: myName,
      callerAvatar: myAvatar,
    );

    if (!sent) {
      debugPrint('CallController: sendInvite failed for ${session.id} to $peerId — check Realtime RLS/subscription');
      await _leaveAndDispose();
      _finishLocally(session, CallEndReason.connectionFailed);
      return;
    }
    debugPrint('CallController: invite sent ${session.id} to $peerId');

    // Trigger push notification in background for callee (in case WebSocket is sleeping)
    unawaited(
      SupabaseService.client.rpc('create_notification', params: {
        'p_user_id': peerId,
        'p_title': myName,
        'p_body': video ? 'Incoming video call…' : 'Incoming voice call…',
        'p_type': 'call',
        'p_data': {
          'call_id': session.id,
          'caller_id': me,
          'caller_name': myName,
          'caller_avatar': myAvatar,
          'call_type': video ? 'video' : 'voice',
        },
      }).catchError((e) {
        debugPrint('CallController: push trigger via RPC failed: $e');
      }),
    );

    unawaited(_playSound(outgoing: true));
    _armTimeout(CallEndReason.noAnswer);
  }

  Future<void> acceptCall() async {
    final session = _session;
    if (session == null || !session.isIncoming || _acceptingOrConnecting) return;
    _acceptingOrConnecting = true;

    _cancelNotification(session.id);

    try {
      final granted = await WebRtcCallEngine.requestPermissions(session.type);
      if (!granted) {
        await _send('reject', {'reason': 'permissions'});
        unawaited(_stopSound());
        _finishLocally(session, CallEndReason.declinedPermission);
        return;
      }

      unawaited(_stopSound());
      _cancelTimeout();
      _updateStatus(CallStatus.connecting);

      // Start local media BEFORE setting up peer so tracks are ready to be sent
      try {
        await WebRtcCallEngine.instance.startLocalMedia(session.type);
      } catch (e) {
        debugPrint('CallController: callee local media failed: $e');
      }

      await _send('accept', {});

      await _setupPeer(session);
      await _maybeProcessPendingOffer();
    } finally {
      _acceptingOrConnecting = false;
    }
  }

  Future<void> rejectCall() async {
    final session = _session;
    if (session == null) return;
    _cancelNotification(session.id);
    await _send('reject', {'reason': 'declined'});
    await _leaveChannel();
    await _teardownMedia();
    await _stopSound();
    _cancelTimeout();
    _goIdle();
  }

  Future<void> endCall() async {
    final session = _session;
    if (session == null) return;
    _cancelNotification(session.id);
    await _send('end', {});
    await _leaveChannel();
    await _teardownMedia();
    await _stopSound();
    _cancelTimeout();
    _finishLocally(session, CallEndReason.completed);
  }

  Future<void> toggleMic() async {
    micMuted = !micMuted;
    await WebRtcCallEngine.instance.toggleMic(micMuted);
    notifyListeners();
  }

  Future<void> toggleCamera() async {
    cameraOff = !cameraOff;
    await WebRtcCallEngine.instance.toggleCamera(cameraOff);
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    await WebRtcCallEngine.instance.setSpeakerphone(speakerOn);
    notifyListeners();
  }

  Future<void> flipCamera() async {
    await WebRtcCallEngine.instance.switchCamera();
    notifyListeners();
  }

  // ── Incoming invite ──────────────────────────────────────────────────────

  /// Display identity for call surfaces: business name for sellers, full
  /// name otherwise, plus the profile avatar. DB values win over auth
  /// metadata, which can be missing (email sign-ups) or stale.
  Future<({String? displayName, String? avatarUrl})> _resolveUserIdentity(
    String userId,
  ) async {
    final meUser = SupabaseService.client.auth.currentUser;
    final isSelf = userId == meUser?.id;
    var displayName = isSelf
        ? (meUser?.userMetadata?['full_name'] as String?) ??
              (meUser?.userMetadata?['name'] as String?)
        : null;
    var avatarUrl = isSelf
        ? (meUser?.userMetadata?['avatar_url'] as String?) ??
              (meUser?.userMetadata?['picture'] as String?)
        : null;

    try {
      final results = await Future.wait([
        SupabaseService.client
            .from('users')
            .select('full_name, avatar_url')
            .eq('id', userId)
            .maybeSingle(),
        SupabaseService.client
            .from('business_profiles')
            .select('business_name')
            .eq('seller_id', userId)
            .maybeSingle(),
      ]);
      final user = results[0];
      final business = results[1];

      final businessName = (business?['business_name'] as String?)?.trim();
      final fullName = (user?['full_name'] as String?)?.trim();
      if (businessName != null && businessName.isNotEmpty) {
        displayName = businessName;
      } else if (fullName != null && fullName.isNotEmpty) {
        displayName = fullName;
      }

      final profileAvatar = (user?['avatar_url'] as String?)?.trim();
      if (profileAvatar != null && profileAvatar.isNotEmpty) {
        avatarUrl = profileAvatar;
      }
    } catch (_) {}

    return (displayName: displayName, avatarUrl: avatarUrl);
  }

  Future<void> _handleIncomingInvite(Map<String, dynamic> payload) async {
    debugPrint('CallController: incoming invite raw=$payload');
    final callId = payload['call_id'] as String?;
    final callerId = payload['caller_id'] as String?;
    final me = currentUserId;
    if (callId == null || callerId == null || me == null) {
      debugPrint('CallController: invite dropped — missing ids callId=$callId callerId=$callerId me=$me');
      return;
    }
    if (callId == _session?.id) return;

    if (hasActiveCall) {
      debugPrint('CallController: invite busy — already in ${_session?.id}, rejecting $callId');
      final busyChannel = await _signaling.joinCallChannel(callId, handlers: {});
      try {
        await busyChannel.sendBroadcastMessage(event: 'busy', payload: {'by': me});
      } catch (e) {
        debugPrint('CallController: busy send failed: $e');
      }
      await _signaling.leaveCallChannel(callId);
      return;
    }

    _resetControlState();

    final type = payload['call_type'] == 'video' ? CallType.video : CallType.audio;
    final createdAtRaw = payload['created_at'] as String?;
    final createdAt = createdAtRaw != null
        ? DateTime.tryParse(createdAtRaw)?.toLocal() ?? DateTime.now()
        : DateTime.now();

    var callerName = payload['caller_name'] as String?;
    var callerAvatar = payload['caller_avatar'] as String?;

    // Backfill identity from the DB (business name for sellers, profile
    // avatar) when the invite payload is missing or incomplete.
    final nameMissing = callerName == null ||
        callerName.isEmpty ||
        callerName == 'Instiy User';
    final avatarMissing = callerAvatar == null || callerAvatar.isEmpty;
    if (nameMissing || avatarMissing) {
      final identity = await _resolveUserIdentity(callerId);
      if (nameMissing && identity.displayName != null) {
        callerName = identity.displayName;
      }
      if (avatarMissing && identity.avatarUrl != null) {
        callerAvatar = identity.avatarUrl;
      }
    }

    final session = CallSession(
      id: callId,
      type: type,
      isIncoming: true,
      localUserId: me,
      peerId: callerId,
      peerName: callerName ?? 'Instiy User',
      peerAvatar: callerAvatar,
      status: CallStatus.ringingIncoming,
      createdAt: createdAt,
    );

    _setSession(session);

    await _joinChannelFor(session);

    // Notify caller that receiver's device received the call and is ringing
    unawaited(_send('ringing', {'call_id': callId, 'by': me}));

    await _presentIncoming(session);
    _armTimeout(CallEndReason.noAnswer);
  }

  /// Silent incoming display: the receiver's phone never rings audibly —
  /// only the caller hears ringback (via [_playSound] outgoing) so they
  /// know the call is going through. The receiver gets a silent full-screen
  /// notification plus the in-app incoming screen (vibration only).
  Future<void> _presentIncoming(CallSession session) async {
    final video = session.type == CallType.video;
    unawaited(
      LocalNotificationService.showIncomingCallNotification(
        callId: session.id,
        callerName: session.peerName ?? 'Instiy User',
        callType: video ? 'video' : 'voice',
        callerAvatar: session.peerAvatar,
        callerId: session.peerId,
        silent: true,
      ),
    );
  }

  void _handleIncomingCancelled(Map<String, dynamic> payload) {
    final callId = payload['call_id'] as String?;
    if (_session?.id != callId) return;
    _cancelNotification(callId);
    if (_session?.status == CallStatus.ringingIncoming) {
      // Caller gave up (manual hangup or 30s no-answer): their side writes
      // the shared missed log, so clear locally without a second write.
      unawaited(_stopSound());
      _cancelTimeout();
      unawaited(_leaveAndDispose());
      _goIdle();
    }
  }

  /// Acts on incoming-call notification actions. When the invite broadcast
  /// was received the session already exists; otherwise (app was backgrounded
  /// and only the FCM push arrived) the session is rebuilt from the payload
  /// so accept/decline still work.
  Future<void> _handleCallAction(String action, Map<String, dynamic> data) async {
    final callId = data['call_id'] as String?;
    final session = _session;
    if (session != null && session.id == callId) {
      if (action == 'accept') {
        await acceptCall();
      } else if (action == 'decline') {
        await rejectCall();
      }
      return; // 'open' — the in-call overlay is already visible
    }
    if (hasActiveCall || callId == null) return;

    final callerId = data['caller_id'] as String?;
    final me = currentUserId;
    if (callerId == null || me == null) return;

    _resetControlState();
    final type = data['call_type'] == 'video' ? CallType.video : CallType.audio;
    final reconstructed = CallSession(
      id: callId,
      type: type,
      isIncoming: true,
      localUserId: me,
      peerId: callerId,
      peerName: (data['caller_name'] as String?) ?? 'Instiy User',
      peerAvatar: data['caller_avatar'] as String?,
      status: CallStatus.ringingIncoming,
      createdAt: DateTime.now(),
    );
    _setSession(reconstructed);
    await _joinChannelFor(reconstructed);

    if (action == 'accept') {
      await acceptCall();
    } else if (action == 'decline') {
      await rejectCall();
    } else {
      // 'open' — present the incoming-call UI and tell the caller we ring.
      unawaited(_send('ringing', {'call_id': callId, 'by': me}));
      await _presentIncoming(reconstructed);
      _armTimeout(CallEndReason.noAnswer);
    }
  }

  // ── Channel signal handlers ──────────────────────────────────────────────

  Future<void> _joinChannelFor(CallSession session) async {
    await _signaling.joinCallChannel(session.id, handlers: {
      'ringing': (_) => _onPeerRinging(session.id),
      'accept': (_) => _onPeerAccepted(session.id),
      'reject': (p) => _onPeerRejected(session.id, p),
      'busy': (_) => _onPeerBusy(session.id),
      'end': (_) => _onPeerEnded(session.id),
      'offer': (p) => _onOffer(session.id, p),
      'answer': (p) => _onAnswer(session.id, p),
      'ice': (p) => _onIceCandidate(session.id, p),
    });
  }

  void _onPeerRinging(String callId) {
    final session = _session;
    if (session == null || session.id != callId) return;
    if (session.isIncoming) return;
    if (session.status == CallStatus.callingOutgoing) {
      debugPrint('CallController: peer acknowledged ringing for $callId — changing Calling… to Ringing…');
      _updateStatus(CallStatus.ringingOutgoing);
    }
  }

  Future<bool> _send(String event, Map<String, dynamic> payload) async {
    final id = _session?.id;
    if (id == null) return false;
    return _signaling.sendSignal(id, event, payload);
  }

  Future<void> _onPeerAccepted(String callId) async {
    final session = _session;
    if (session == null || session.id != callId) return;
    if (session.isIncoming) return;
    if (session.status == CallStatus.connecting ||
        session.status == CallStatus.active) {
      return;
    }

    unawaited(_stopSound());
    _cancelTimeout();
    _updateStatus(CallStatus.connecting);

    try {
      await _setupPeer(session);
      final offer = await WebRtcCallEngine.instance.createOffer();
      await _send('offer', {
        'sdp': offer.toMap(),
      });
    } catch (e) {
      debugPrint('CallController: offer creation failed: $e');
      await _send('end', {});
      _finishLocally(session, CallEndReason.connectionFailed);
    }
  }

  void _onPeerRejected(String callId, Map<String, dynamic> payload) {
    debugPrint('CallController: peer rejected $callId payload=$payload');
    final session = _session;
    if (session == null || session.id != callId || session.isIncoming) return;
    _stopSound();
    _cancelTimeout();
    _leaveAndDispose();
    _showEnded(CallEndReason.rejected);
  }

  void _onPeerBusy(String callId) {
    debugPrint('CallController: peer busy $callId');
    final session = _session;
    if (session == null || session.id != callId || session.isIncoming) return;
    _stopSound();
    _cancelTimeout();
    _leaveAndDispose();
    _showEnded(CallEndReason.busy);
  }

  void _onPeerEnded(String callId) {
    debugPrint('CallController: peer ended $callId status=${_session?.status}');
    final session = _session;
    if (session == null || session.id != callId) return;
    _stopSound();
    _cancelTimeout();
    // Pre-answer hangup (caller gave up before pick-up): the caller writes
    // the single shared missed/no-answer log, so just clear locally here.
    // Writing a second 'cancelled' row would duplicate the bubble and break
    // the missed-call badge on the bottom nav.
    if (session.status != CallStatus.active) {
      unawaited(_leaveAndDispose());
      _goIdle();
      return;
    }
    _leaveAndDispose();
    _showEnded(CallEndReason.completed);
  }

  Future<void> _onOffer(String callId, Map<String, dynamic> payload) async {
    final session = _session;
    if (session == null || session.id != callId || !session.isIncoming) return;

    final sdp = payload['sdp'];
    if (sdp == null) return;

    if (WebRtcCallEngine.instance.peerReady) {
      try {
        await WebRtcCallEngine.instance.setRemoteDescription(
          Map<String, dynamic>.from(sdp as Map),
          'offer',
        );
        await _drainPendingCandidates();
        final answer = await WebRtcCallEngine.instance.createAnswer();
        await _send('answer', {'sdp': answer.toMap()});
      } catch (e) {
        debugPrint('CallController: answering failed: $e');
        await _send('end', {});
        _finishLocally(session, CallEndReason.connectionFailed);
      }
    } else {
      _pendingOffer = Map<String, dynamic>.from(sdp as Map);
    }
  }

  Future<void> _onAnswer(String callId, Map<String, dynamic> payload) async {
    final session = _session;
    if (session == null || session.id != callId || session.isIncoming) return;
    final sdp = payload['sdp'];
    if (sdp == null) return;
    try {
      await WebRtcCallEngine.instance.setRemoteDescription(
        Map<String, dynamic>.from(sdp as Map),
        'answer',
      );
      await _drainPendingCandidates();
    } catch (e) {
      debugPrint('CallController: applying answer failed: $e');
    }
  }

  Future<void> _onIceCandidate(String callId, Map<String, dynamic> payload) async {
    if (_session?.id != callId) return;
    final candidate = payload['candidate'];
    if (candidate == null) return;
    final map = Map<String, dynamic>.from(candidate as Map);
    if (WebRtcCallEngine.instance.peerReady &&
        WebRtcCallEngine.instance.hasRemoteDescription) {
      try {
        await WebRtcCallEngine.instance.addRemoteCandidate(map);
      } catch (_) {}
    } else {
      _pendingCandidates.add(map);
    }
  }

  Future<void> _maybeProcessPendingOffer() async {
    final offer = _pendingOffer;
    if (offer == null) return;
    _pendingOffer = null;
    await _onOffer(_session?.id ?? '', {'sdp': offer});
  }

  Future<void> _drainPendingCandidates() async {
    if (_pendingCandidates.isEmpty) return;
    final queued = List.of(_pendingCandidates);
    _pendingCandidates.clear();
    for (final c in queued) {
      try {
        await WebRtcCallEngine.instance.addRemoteCandidate(c);
      } catch (_) {}
    }
  }

  // ── Peer connection lifecycle ────────────────────────────────────────────

  Future<void> _setupPeer(CallSession session) async {
    await WebRtcCallEngine.instance.initializePeerConnection(
      onLocalCandidate: (candidate) {
        unawaited(_send('ice', {'candidate': candidate.toMap()}));
      },
      onConnectionState: (state) =>
          _onConnectionStateChanged(session.id, state),
      onRemoteStream: (stream) {
        remoteStream = stream;
        notifyListeners();
      },
    );

    await _maybeProcessPendingOffer();
  }

  void _onConnectionStateChanged(String callId, RTCPeerConnectionState state) {
    final session = _session;
    if (session == null || session.id != callId) return;
    debugPrint('CallController: peerConnectionState $state for $callId status=${session.status}');

    if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
      if (session.status != CallStatus.active) {
        _connectedAt = DateTime.now();
        _applyDefaultAudioRoute(session.type);
        _updateStatus(CallStatus.active);
      }
      return;
    }

    if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
        state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
      debugPrint('CallController: connection failed/closed $state — ending call');
      if (session.isActiveOrRinging) {
        _leaveAndDispose();
        _showEnded(
          session.status == CallStatus.active
              ? CallEndReason.peerDisconnected
              : CallEndReason.connectionFailed,
        );
      }
    }
  }

  Future<void> _applyDefaultAudioRoute(CallType type) async {
    speakerOn = type == CallType.video;
    await WebRtcCallEngine.instance.setSpeakerphone(speakerOn);
    notifyListeners();
  }

  void _cancelNotification([String? callId]) {
    final id = callId ?? _session?.id;
    if (id != null) {
      unawaited(LocalNotificationService.cancelCallNotification(id));
      // Single choke point for dropping the system UI too — accept,
      // reject, end, timeout and cancel all flow through here.
      unawaited(SystemCallUiService.dismiss(id));
    }
  }

  void _armTimeout(CallEndReason reasonOnExpire) {
    _cancelTimeout();
    // 30s no-answer: caller hangs up, sends cancel, and writes the single
    // shared missed log (status 'no_answer'). That insert flows through the
    // messages realtime channel into MessageProvider.loadUnreadCount, which
    // raises missedCallCount and flips the bottom-nav Chats button to its
    // phone phase. Callee just clears locally — no second write.
    _timeoutTimer = Timer(_ringTimeout, () {
      final session = _session;
      if (session == null || !session.isActiveOrRinging) return;
      _cancelNotification(session.id);
      if (!session.isIncoming && reasonOnExpire == CallEndReason.noAnswer) {
        unawaited(_signaling.sendCancel(calleeId: session.peerId, callId: session.id));
        unawaited(_leaveAndDispose());
        _showEnded(CallEndReason.noAnswer);
      } else if (session.isIncoming) {
        unawaited(_stopSound());
        unawaited(_leaveAndDispose());
        _goIdle();
      }
    });
  }

  void _cancelTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = null;
  }

  /// Ringback for the caller only. The receiver's side stays silent by
  /// design (visual notification + vibration), so incoming calls never
  /// play an audible ring on the receiving phone.
  Future<void> _playSound({required bool outgoing}) async {
    if (!outgoing) return;

    try {
      await _ringPlayer.setVolume(0.35);
      await _ringPlayer.play(AssetSource('sounds/notification_alert.mp3'));
    } catch (e) {
      debugPrint('CallController: ringtone failed: $e');
    }
  }

  Future<void> _stopSound() async {
    try {
      await _ringPlayer.stop();
    } catch (_) {}
  }

  void _setSession(CallSession session) {
    _session = session;
    notifyListeners();
  }

  void _updateStatus(CallStatus status) {
    final s = _session;
    if (s == null) return;
    _session = s.copyWith(status: status);
    notifyListeners();
  }

  bool _callLogRecorded = false;

  void _recordCallLog(CallSession session, CallEndReason reason) {
    if (_callLogRecorded) return;
    _callLogRecorded = true;

    final durationSeconds = _connectedAt != null
        ? DateTime.now().difference(_connectedAt!).inSeconds
        : 0;

    String status = 'completed';
    if (reason == CallEndReason.rejected) {
      status = 'declined';
    } else if (reason == CallEndReason.noAnswer) {
      status = 'no_answer';
    } else if (reason == CallEndReason.cancelled) {
      status = 'cancelled';
    } else if (reason == CallEndReason.busy) {
      status = 'busy';
    } else if (durationSeconds == 0) {
      status = 'missed';
    }

    final peerId = session.peerId;
    final callType = session.type == CallType.video ? 'video' : 'voice';

    unawaited(
      MessageService.sendCallLog(
        peerId: peerId,
        callType: callType,
        durationSeconds: durationSeconds,
        status: status,
      ),
    );
  }

  void _resetControlState() {
    _callLogRecorded = false;
    micMuted = false;
    cameraOff = false;
    speakerOn = false;
    remoteStream = null;
    _pendingCandidates.clear();
    _pendingOffer = null;
    _connectedAt = null;
  }

  /// Ends without notifying the peer (they are gone / never reached).
  void _finishLocally(CallSession session, CallEndReason reason) {
    _recordCallLog(session, reason);
    _cancelNotification(session.id);
    _stopSound();
    _cancelTimeout();
    _leaveAndDispose();
    _showEnded(reason);
  }

  void _showEnded(CallEndReason reason) {
    final s = _session;
    if (s == null) return;
    _recordCallLog(s, reason);
    _cancelNotification(s.id);
    _session = s.copyWith(status: CallStatus.ended, endReason: reason);
    notifyListeners();

    _endedFlashTimer.cancel();
    _endedFlashTimer = Timer(_endedFlashDuration, () {
      if (_session?.status == CallStatus.ended) {
        _goIdle();
      }
    });
  }

  void _goIdle() {
    _cancelNotification(_session?.id);
    _session = null;
    _connectedAt = null;
    _resetControlState();
    notifyListeners();
  }

  Future<void> _leaveChannel() async {
    final id = _session?.id;
    if (id != null) await _signaling.leaveCallChannel(id);
  }

  Future<void> _teardownMedia() async {
    await WebRtcCallEngine.instance.dispose();
  }

  Future<void> _leaveAndDispose() async {
    _cancelNotification(_session?.id);
    unawaited(_stopSound());
    await _leaveChannel();
    await _teardownMedia();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    unawaited(_systemUiSub?.cancel() ?? Future.value());
    _cancelTimeout();
    _endedFlashTimer.cancel();
    _ringPlayer.dispose();
    _signaling.disposeAll();
    super.dispose();
  }
}
