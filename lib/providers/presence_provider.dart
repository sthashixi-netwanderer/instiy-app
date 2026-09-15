import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:instiy/providers/providers.dart';

/// Reactive online status for a chat peer, derived from the message
/// provider's live conversations. Avatars watching this flip between the
/// online/offline dot on their own — no manual refresh: realtime user
/// updates, the 60s presence heal, and the 10s re-evaluation tick all flow
/// through [messageProvider], and widgets here rebuild only when the
/// derived value for their peer actually changes.
final peerOnlineProvider =
    Provider.autoDispose.family<bool, String>((ref, peerUserId) {
  final msgProv = ref.watch(messageProvider);
  for (final c in msgProv.conversations) {
    if (c.otherUserId == peerUserId) return c.isOnline;
  }
  for (final c in msgProv.archivedConversations) {
    if (c.otherUserId == peerUserId) return c.isOnline;
  }
  final active = msgProv.activeConversation;
  if (active != null && active.otherUserId == peerUserId) {
    return active.isOnline;
  }
  return false;
});
