---
name: add-notification-for-event
description: Add in-app, push, and/or email notifications when a new event occurs in the Instiy app
source: auto-skill
extracted_at: '2026-05-31T18:10:04.545Z'
---

# Adding Notifications for a New Event

## Architecture

Instiy has a **3-layer notification system**:

| Layer | Mechanism | Trigger |
|-------|-----------|---------|
| **In-app** | INSERT into `notifications` table | Manual (Dart code) |
| **Push (FCM)** | Edge Function `push-notifications` | **Auto-triggered** by webhook on `notifications` INSERT |
| **Email** | Edge Function `send-email` | Manual call via `EmailService` |

Key insight: **inserting into the `notifications` table automatically sends a push notification** via the Supabase webhook → FCM pipeline. You do NOT need to call push separately.

## Procedure

### Step 1: Find the event source

Identify the Dart method where the event occurs (e.g., `ReviewService.submitReview()`, `FollowService.follow()`).

### Step 2: Add in-app notification INSERT

Use the existing pattern from `follow_service.dart`:

```dart
await SupabaseService.table('notifications').insert({
  'user_id': recipientUserId,
  'title': 'Short notification title',
  'body': 'Descriptive body with context',
  'type': 'event_type',  // used for filtering and routing
  'data': {
    'relevant_id': someId,  // JSONB payload for deep-linking
  },
});
```

- `type` values used in the app: `order`, `delivery`, `delivery_approved`, `message`, `new_message`, `payment`, `transfer_sent`, `transfer_received`, `deposit`, `withdrawal`, `review`, `new_product`, `new_follower`, `verification_approved`, `verification_rejected`
- `data` is JSONB — include IDs needed for deep-linking when the notification is tapped
- The notifications screen (`notifications_screen.dart`) routes by `type` to navigate to the correct screen

### Step 3: Add email notification (if needed)

Call the appropriate `EmailService` static method. If no template exists yet, add one to `email_service.dart` using the `_sendEmail()` private method that calls the `send-email` Edge Function.

### Step 4: Verify

Run `flutter analyze` on the changed files.

## Key Files

| Purpose | File |
|---------|------|
| Notification model | `lib/models/notification_model.dart` |
| Notification service (read/mark) | `lib/services/notification_service.dart` |
| Local device notifications + Realtime subscription | `lib/services/local_notification_service.dart` |
| Email templates | `lib/services/email_service.dart` |
| Notification UI + deep-linking | `lib/screens/notifications/notifications_screen.dart` |
| Push notification badge (Realtime) | `lib/providers/message_provider.dart` |
| Notification table definition | `supabase/migrations/20260527130000_wallet_orders_paystack.sql` |
| Push Edge Function | `supabase/functions/push-notifications/index.ts` |
| Email Edge Function | `supabase/functions/send-email/index.ts` |

## Example: Review notification

When a buyer submits a review on a product, the seller needs to be notified:

```dart
// In ReviewService.submitReview(), after the review INSERT:
final product = await SupabaseService.table('products')
    .select('seller_id, title')
    .eq('id', productId)
    .maybeSingle();

if (product != null) {
  final sellerId = product['seller_id'];
  final reviewer = await SupabaseService.table('users')
      .select('full_name')
      .eq('id', reviewerId)
      .maybeSingle();

  // In-app notification (auto-triggers push via webhook)
  await SupabaseService.table('notifications').insert({
    'user_id': sellerId,
    'title': 'New review on your product',
    'body': '${reviewer?['full_name']} reviewed "${product['title']}" — ★★★★☆',
    'type': 'review',
    'data': {'product_id': productId, 'reviewer_id': reviewerId},
  });
}
```

## Bidirectional Notifications

When an event involves two parties (e.g., buyer reviews a product → seller notified; seller replies → buyer notified), add **both** notification directions in the same pass. Both directions often share the same fetched data (product info, user info), so it's efficient to handle them together.

Example — review event has two notification points:
1. `ReviewService.submitReview()` → notify **seller** that their product was reviewed
2. `SellerProvider.replyToReview()` → notify **reviewer** that the seller replied

Check both the "create" and "respond" methods for the same entity type.

## Notes

- The `type` field in `data` JSONB is used by the notifications screen to route taps to the correct detail screen
- Notification sounds are handled by `SoundService` based on the `type` field
- FCM tokens are stored in `user_push_tokens` table — the push Edge Function fetches them automatically
- Batch inserts work for notifying multiple recipients (e.g., `notifyFollowersOfNewProduct` in `follow_service.dart`)
