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

  static Map<String, dynamic> _unwrap(Map<String, dynamic> raw) {
    // Supabase Realtime versions differ: some deliver {payload:{...}} envelope,
    // some deliver the payload directly. Handle both so invite/offer/answer are not lost.
    if (raw.containsKey('payload') && raw['payload'] is Map) {
      final hasDirectKeys = raw.containsKey('call_id') ||
          raw.containsKey('sdp') ||
          raw.containsKey('candidate') ||
          raw.containsKey('reason');
      if (!hasDirectKeys) {
        return Map<String, dynamic>.from(raw['payload'] as Map);
      }
    }
    return raw;
  }

  static SignalHandler _wrap(SignalHandler h) {
    return (Map<String, dynamic> raw) {
      try {
        h(_unwrap(raw));
      } catch (e) {
        debugPrint('CallSignaling: handler error: $e raw=$raw');
      }
    };
  }

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
        .onBroadcast(event: 'invite', callback: _wrap(onInvite))
        .onBroadcast(event: 'cancel', callback: _wrap(onCancel));

    final joined = Completer<bool>();
    String lastStatus = 'pending';
    _ringChannel!.subscribe((status, error) {
      lastStatus = status.name;
      if (error != null) debugPrint('CallSignaling: ring subscribe error $error status=$status');
      if (!joined.isCompleted) {
        joined.complete(status == RealtimeSubscribeStatus.subscribed);
      }
    });
    final ok = await joined.future.timeout(const Duration(seconds: 10), onTimeout: () => false);
    debugPrint('CallSignaling: ring ${ringTopic(userId)} subscribe=$ok status=$lastStatus');
    if (!ok) {
      debugPrint('CallSignaling: ring subscribe timeout/failed for $userId — invites will be missed');
    }
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
      newChannel.onBroadcast(event: event, callback: _wrap(handler));
    });

    final joined = Completer<bool>();
    String lastStatus = 'pending';
    Object? lastError;
    newChannel.subscribe((status, error) {
      lastStatus = status.name;
      lastError = error;
      if (error != null) debugPrint('CallSignaling: call $callId subscribe error $error status=$status');
      if (!joined.isCompleted) {
        joined.complete(status == RealtimeSubscribeStatus.subscribed);
      }
    });
    final ok = await joined.future.timeout(const Duration(seconds: 10), onTimeout: () => false);
    debugPrint('CallSignaling: call ${callTopic(callId)} subscribe=$ok status=$lastStatus err=$lastError');
    if (!ok) {
      debugPrint('CallSignaling: call $callId subscribe failed — signals may be lost');
    }

    _callChannels[callId] = channel;
    return channel;
  }

  Future<bool> sendSignal(
    String callId,
    String event,
    Map<String, dynamic> payload,
  ) async {
    final channel = _callChannels[callId];
    if (channel == null) {
      debugPrint('CallSignaling: send "$event" no channel for $callId');
      return false;
    }
    try {
      final status = await channel
          .sendBroadcastMessage(event: event, payload: payload)
          .timeout(const Duration(seconds: 10));
      if (status != ChannelResponse.ok) {
        debugPrint('CallSignaling: send "$event" status=$status for $callId');
      }
      return status == ChannelResponse.ok;
    } catch (e) {
      debugPrint('CallSignaling: send "$event" failed: $e for $callId');
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
      String lastStatus = 'pending';
      Object? lastError;
      channel.subscribe((status, error) {
        lastStatus = status.name;
        lastError = error;
        if (error != null) debugPrint('CallSignaling: _sendToRing $event subscribe error $error status=$status topic=$topic');
        if (!joined.isCompleted) {
          joined.complete(status == RealtimeSubscribeStatus.subscribed);
        }
      });
      final ok = await joined.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => false,
      );
      if (!ok) {
        debugPrint('CallSignaling: _sendToRing $event subscribe failed topic=$topic status=$lastStatus err=$lastError');
        return false;
      }

      final status = await channel
          .sendBroadcastMessage(event: event, payload: payload)
          .timeout(const Duration(seconds: 10));
      if (status != ChannelResponse.ok) {
        debugPrint('CallSignaling: _sendToRing $event status=$status topic=$topic payload=$payload');
      }
      // Small pause to allow WebSocket transport to flush packet before removing channel
      await Future.delayed(const Duration(milliseconds: 60));
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
