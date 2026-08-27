import 'package:flutter/foundation.dart';

enum CallType { audio, video }

enum CallStatus {
  idle,
  callingOutgoing,
  ringingOutgoing,
  ringingIncoming,
  connecting,
  active,
  ended,
}

enum CallEndReason {
  completed,
  rejected,
  busy,
  noAnswer,
  cancelled,
  declinedPermission,
  connectionFailed,
  peerDisconnected,
}

@immutable
class CallSession {
  final String id;
  final CallType type;
  final bool isIncoming;
  final String localUserId;
  final String peerId;
  final String? peerName;
  final String? peerAvatar;
  final CallStatus status;
  final DateTime createdAt;
  final CallEndReason? endReason;

  const CallSession({
    required this.id,
    required this.type,
    required this.isIncoming,
    required this.localUserId,
    required this.peerId,
    this.peerName,
    this.peerAvatar,
    required this.status,
    required this.createdAt,
    this.endReason,
  });

  CallSession copyWith({
    CallType? type,
    String? peerName,
    String? peerAvatar,
    CallStatus? status,
    CallEndReason? endReason,
  }) {
    return CallSession(
      id: id,
      type: type ?? this.type,
      isIncoming: isIncoming,
      localUserId: localUserId,
      peerId: peerId,
      peerName: peerName ?? this.peerName,
      peerAvatar: peerAvatar ?? this.peerAvatar,
      status: status ?? this.status,
      createdAt: createdAt,
      endReason: endReason ?? this.endReason,
    );
  }

  bool get isActiveOrRinging =>
      status == CallStatus.callingOutgoing ||
      status == CallStatus.ringingOutgoing ||
      status == CallStatus.ringingIncoming ||
      status == CallStatus.connecting ||
      status == CallStatus.active;

  String get statusLabel {
    switch (status) {
      case CallStatus.idle:
        return '';
      case CallStatus.callingOutgoing:
        return 'Calling…';
      case CallStatus.ringingOutgoing:
        return 'Ringing…';
      case CallStatus.ringingIncoming:
        return type == CallType.video
            ? 'Incoming video call'
            : 'Incoming voice call';
      case CallStatus.connecting:
        return 'Connecting…';
      case CallStatus.active:
        return 'Connected';
      case CallStatus.ended:
        switch (endReason) {
          case CallEndReason.completed:
            return 'Call ended';
          case CallEndReason.rejected:
            return 'Call declined';
          case CallEndReason.busy:
            return 'Line busy';
          case CallEndReason.noAnswer:
            return 'No answer';
          case CallEndReason.cancelled:
            return 'Call cancelled';
          case CallEndReason.declinedPermission:
            return 'Microphone access denied';
          case CallEndReason.connectionFailed:
            return 'Connection failed';
          case CallEndReason.peerDisconnected:
            return 'Connection lost';
          case null:
            return 'Call ended';
        }
    }
  }
}
