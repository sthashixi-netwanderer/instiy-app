import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/call_model.dart';
import 'supabase_service.dart';

typedef SignalHandler = void Function(Map<String, dynamic> payload);

class CallSignalingService {
  CallSignalingService._();
  static final CallSignalingService instance = CallSignalingService._();

  static const String _ringPrefix = 'calls:';
  static const String _callPrefix = 'call:';

  final SupabaseClient _client = SupabaseService.client;

  RealtimeChannel? _ringChannel;
  String? _ringUserId;

  final Map<String, RealtimeChannel> _callChannels = {};

  static String ringTopic(String userId) => '$_ringPrefix$userId';
  static String callTopic(String callId) => '$_callPrefix$callId';

  Future<void> listenForInvites(
    String userId, {
    required SignalHandler onInvite,
    required SignalHandler onCancel,
  }) async {
    if (_ringUserId == userId && _ringChannel != null) return;
    await stopListening();

    _ringUserId = userId;
    _ringChannel = _client.channel(
      ringTopic(userId),
      opts: const RealtimeChannelConfig(private: true),
    );

    _ringChannel!
        .onBroadcast(event: 'invite', callback: onInvite)
        .onBroadcast(event: 'cancel', callback: onCancel);

    final joined = Completer<bool>();
    _ringChannel!.subscribe((status, error) {
      if (!joined.isCompleted) {
        joined.complete(status == RealtimeSubscribeStatus.subscribed);
      }
    });
    await joined.future.timeout(const Duration(seconds: 6), onTimeout: () => false);
  }

  Future<void> stopListening() async {
    final channel = _ringChannel;
    _ringChannel = null;
    _ringUserId = null;
    if (channel != null) {
      try {
        await _client.removeChannel(channel);
      } catch (_) {}
    }
  }

  Future<bool> sendInvite({
    required String calleeId,
    required CallSession session,
  }) {
    return _sendToRing(ringTopic(calleeId), 'invite', {
      'call_id': session.id,
      'caller_id': session.localUserId,
      'caller_name': session.peerName,
      'caller_avatar': session.peerAvatar,
      'call_type': session.type == CallType.video ? 'video' : 'audio',
      'created_at': session.createdAt.toIso8601String(),
    });
  }

  Future<bool> sendCancel({required String calleeId, required String callId}) {
    return _sendToRing(ringTopic(calleeId), 'cancel', {'call_id': callId});
  }

  Future<RealtimeChannel> joinCallChannel(
    String callId, {
    required Map<String, SignalHandler> handlers,
  }) async {
    var channel = _callChannels[callId];
    if (channel != null) {
      await leaveCallChannel(callId);
    }

    final newChannel = _client.channel(
      callTopic(callId),
      opts: const RealtimeChannelConfig(private: true),
    );
    channel = newChannel;

    handlers.forEach((event, handler) {
      newChannel.onBroadcast(event: event, callback: handler);
    });

    final joined = Completer<bool>();
    newChannel.subscribe((status, error) {
      if (!joined.isCompleted) {
        joined.complete(status == RealtimeSubscribeStatus.subscribed);
      }
    });
    await joined.future.timeout(const Duration(seconds: 6), onTimeout: () => false);

    _callChannels[callId] = channel;
    return channel;
  }

  Future<bool> sendSignal(
    String callId,
    String event,
    Map<String, dynamic> payload,
  ) async {
    final channel = _callChannels[callId];
    if (channel == null) return false;
    try {
      final status = await channel
          .sendBroadcastMessage(event: event, payload: payload)
          .timeout(const Duration(seconds: 8));
      return status == ChannelResponse.ok;
    } catch (e) {
      debugPrint('CallSignaling: send "$event" failed: $e');
      return false;
    }
  }

  Future<void> leaveCallChannel(String callId) async {
    final channel = _callChannels.remove(callId);
    if (channel == null) return;
    try {
      await _client.removeChannel(channel);
    } catch (_) {}
  }

  Future<void> disposeAll() async {
    await stopListening();
    for (final callId in List.of(_callChannels.keys)) {
      await leaveCallChannel(callId);
    }
  }

  Future<bool> _sendToRing(
    String topic,
    String event,
    Map<String, dynamic> payload,
  ) async {
    final channel = _client.channel(topic, opts: const RealtimeChannelConfig(private: true));
    try {
      final joined = Completer<bool>();
      channel.subscribe((status, error) {
        if (!joined.isCompleted) {
          joined.complete(status == RealtimeSubscribeStatus.subscribed);
        }
      });
      final ok = await joined.future.timeout(
        const Duration(seconds: 6),
        onTimeout: () => false,
      );
      if (!ok) return false;

      final status = await channel
          .sendBroadcastMessage(event: event, payload: payload)
          .timeout(const Duration(seconds: 8));
      return status == ChannelResponse.ok;
    } catch (e) {
      debugPrint('CallSignaling: $event to $topic failed: $e');
      return false;
    } finally {
      try {
        await _client.removeChannel(channel);
      } catch (_) {}
    }
  }
}
