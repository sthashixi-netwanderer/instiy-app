import 'package:flutter/foundation.dart';
import '../models/product_model.dart';
import 'supabase_service.dart';
import 'package:instiy/utils/formatters.dart';

class EmailService {
  /// Send an email via Supabase Edge Function
  static Future<void> _sendEmail({
    required String to,
    required String subject,
    required String htmlBody,
  }) async {
    try {
      await SupabaseService.client.functions.invoke(
        'send-email',
        body: {
          'to': to,
          'subject': subject,
          'html': htmlBody,
        },
      );
    } catch (e) {
      // Silently fail — email is non-critical
      debugPrint('Email send failed: $e');
    }
  }

  // ─── Product Out of Stock ──────────────────────────────────────

  static Future<void> sendProductOutOfStock({
    required String sellerEmail,
    required String productTitle,
  }) async {
    final subject = 'Action Required: "$productTitle" is out of stock!';
    await _sendEmail(
      to: sellerEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #ef4444, #dc2626); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .value { color: #1c1917; font-size: 15px; font-weight: 600; margin-bottom: 16px; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Out of Stock Notice</h1>
    </div>
    <div class="body">
      <p class="value">Your product "<strong>$productTitle</strong>" has run out of stock.</p>
      <p>Please update your inventory or restock the item so buyers can continue purchasing it.</p>
    </div>
    <div class="footer">
      <p>&copy; ${DateTime.now().year} Instiy. All rights reserved.</p>
    </div>
  </div>
</body>
</html>
''',
    );
  }

  // ─── Product Low Stock ────────────────────────────────────────

  static Future<void> sendProductLowStock({
    required String sellerEmail,
    required String productTitle,
    required int remainingStock,
  }) async {
    final subject = 'Low Stock Alert: "$productTitle" has only $remainingStock left';
    await _sendEmail(
      to: sellerEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #f59e0b, #d97706); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .value { color: #1c1917; font-size: 15px; font-weight: 600; margin-bottom: 16px; }
    .stock-badge { display: inline-block; background: #fef3c7; color: #92400e; padding: 6px 16px; border-radius: 20px; font-weight: 700; font-size: 18px; margin: 12px 0; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Low Stock Alert</h1>
    </div>
    <div class="body">
      <p class="value">Your product "<strong>$productTitle</strong>" is running low on stock.</p>
      <p style="text-align:center"><span class="stock-badge">$remainingStock remaining</span></p>
      <p>Consider restocking soon to avoid missing out on sales.</p>
    </div>
    <div class="footer">
      <p>&copy; ${DateTime.now().year} Instiy. All rights reserved.</p>
    </div>
  </div>
</body>
</html>
''',
    );
  }

  // ─── Product Purchased ─────────────────────────────────────────

  static Future<void> sendProductPurchasedToSeller({
    required String sellerEmail,
    required String sellerName,
    required String buyerName,
    required String productTitle,
    required double price,
    required int quantity,
    required String orderId,
  }) async {
    final subject = 'Your product "$productTitle" has been purchased!';
    await _sendEmail(
      to: sellerEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #6c47ff, #8B5CF6); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .label { color: #78716c; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 4px; }
    .value { color: #1c1917; font-size: 15px; font-weight: 600; margin-bottom: 16px; }
    .divider { border-top: 1px solid #e7e5e4; margin: 16px 0; }
    .amount { font-size: 28px; font-weight: 700; color: #4D7C59; text-align: center; margin: 20px 0; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>New Sale!</h1>
    </div>
    <div class="body">
      <p>Hi $sellerName,</p>
      <p>Your product has been purchased by <strong>$buyerName</strong>.</p>
      <div class="divider"></div>
      <div class="label">Product</div>
      <div class="value">$productTitle</div>
      <div class="label">Quantity</div>
      <div class="value">$quantity</div>
      <div class="label">Order ID</div>
      <div class="value">#${orderId.substring(0, 8).toUpperCase()}</div>
      <div class="divider"></div>
      <div class="amount">${formatGhs(price)}</div>
      <p style="color: #78716c; font-size: 13px; text-align: center;">
        Please prepare the item for delivery. You can mark it as delivered once the buyer receives it.
      </p>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>''',
    );
  }

  static Future<void> sendProductPurchasedToBuyer({
    required String buyerEmail,
    required String buyerName,
    required String sellerName,
    required String productTitle,
    required double price,
    required int quantity,
    required String orderId,
  }) async {
    final subject = 'Order Confirmation — "$productTitle"';
    await _sendEmail(
      to: buyerEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #6c47ff, #8B5CF6); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .label { color: #78716c; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 4px; }
    .value { color: #1c1917; font-size: 15px; font-weight: 600; margin-bottom: 16px; }
    .divider { border-top: 1px solid #e7e5e4; margin: 16px 0; }
    .amount { font-size: 28px; font-weight: 700; color: #6c47ff; text-align: center; margin: 20px 0; }
    .info-box { background: #f5f5f4; border-radius: 8px; padding: 12px 16px; margin: 12px 0; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Order Confirmed!</h1>
    </div>
    <div class="body">
      <p>Hi $buyerName,</p>
      <p>Your order has been placed successfully. Here are the details:</p>
      <div class="divider"></div>
      <div class="label">Product</div>
      <div class="value">$productTitle</div>
      <div class="label">Seller</div>
      <div class="value">$sellerName</div>
      <div class="label">Quantity</div>
      <div class="value">$quantity</div>
      <div class="label">Order ID</div>
      <div class="value">#${orderId.substring(0, 8).toUpperCase()}</div>
      <div class="divider"></div>
      <div class="amount">${formatGhs(price)}</div>
      <div class="info-box">
        <p style="margin: 0; font-size: 13px; color: #78716c;">
          <strong>Next steps:</strong> Wait for the seller to confirm delivery. You'll receive a delivery code to share with the seller upon receiving your item.
        </p>
      </div>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>''',
    );
  }

  // ─── Transfer ──────────────────────────────────────────────────

  static Future<void> sendTransferSent({
    required String senderEmail,
    required String senderName,
    required String recipientName,
    required double amount,
  }) async {
    final subject = 'Transfer of ${formatGhs(amount)} sent';
    await _sendEmail(
      to: senderEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #DC2626, #EF4444); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .amount { font-size: 28px; font-weight: 700; color: #DC2626; text-align: center; margin: 20px 0; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Transfer Sent</h1>
    </div>
    <div class="body">
      <p>Hi $senderName,</p>
      <p>You have successfully transferred funds to <strong>$recipientName</strong>.</p>
      <div class="amount">-${formatGhs(amount)}</div>
      <p style="color: #78716c; font-size: 13px; text-align: center;">The amount has been deducted from your wallet balance.</p>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>''',
    );
  }

  static Future<void> sendTransferReceived({
    required String recipientEmail,
    required String recipientName,
    required String senderName,
    required double amount,
  }) async {
    final subject = 'You received ${formatGhs(amount)}';
    await _sendEmail(
      to: recipientEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #4D7C59, #059669); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .amount { font-size: 28px; font-weight: 700; color: #4D7C59; text-align: center; margin: 20px 0; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Transfer Received</h1>
    </div>
    <div class="body">
      <p>Hi $recipientName,</p>
      <p>You have received funds from <strong>$senderName</strong>.</p>
      <div class="amount">+${formatGhs(amount)}</div>
      <p style="color: #78716c; font-size: 13px; text-align: center;">The amount has been added to your wallet balance.</p>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>''',
    );
  }

  // ─── Withdrawal ────────────────────────────────────────────────

  static Future<void> sendWithdrawalRequest({
    required String userEmail,
    required String userName,
    required double amount,
    required String method,
  }) async {
    final subject = 'Withdrawal request of ${formatGhs(amount)}';
    await _sendEmail(
      to: userEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #D97706, #F59E0B); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .amount { font-size: 28px; font-weight: 700; color: #D97706; text-align: center; margin: 20px 0; }
    .info-box { background: #f5f5f4; border-radius: 8px; padding: 12px 16px; margin: 12px 0; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Withdrawal Request</h1>
    </div>
    <div class="body">
      <p>Hi $userName,</p>
      <p>Your withdrawal request has been submitted.</p>
      <div class="amount">${formatGhs(amount)}</div>
      <div class="info-box">
        <p style="margin: 0; font-size: 13px; color: #78716c;"><strong>Method:</strong> $method</p>
      </div>
      <p style="color: #78716c; font-size: 13px;">Your request is being reviewed. You'll receive an email once it's processed.</p>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>''',
    );
  }

  static Future<void> sendWithdrawalProcessed({
    required String userEmail,
    required String userName,
    required double amount,
  }) async {
    final subject = 'Withdrawal of ${formatGhs(amount)} processed';
    await _sendEmail(
      to: userEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #4D7C59, #059669); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .amount { font-size: 28px; font-weight: 700; color: #4D7C59; text-align: center; margin: 20px 0; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Withdrawal Processed</h1>
    </div>
    <div class="body">
      <p>Hi $userName,</p>
      <p>Your withdrawal has been processed successfully.</p>
      <div class="amount">${formatGhs(amount)}</div>
      <p style="color: #78716c; font-size: 13px; text-align: center;">The funds have been sent to your account.</p>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>''',
    );
  }

  // ─── Delivery ──────────────────────────────────────────────────

  static Future<void> sendDeliveryConfirmed({
    required String buyerEmail,
    required String buyerName,
    required String sellerName,
    required String productTitle,
    required double amount,
  }) async {
    final subject = 'Delivery confirmed for "$productTitle"';
    await _sendEmail(
      to: buyerEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #4D7C59, #059669); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .info-box { background: #f5f5f4; border-radius: 8px; padding: 12px 16px; margin: 12px 0; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Delivery Confirmed</h1>
    </div>
    <div class="body">
      <p>Hi $buyerName,</p>
      <p>Your delivery for <strong>$productTitle</strong> has been confirmed by <strong>$sellerName</strong>.</p>
      <div class="info-box">
        <p style="margin: 0; font-size: 13px; color: #78716c;">
          Payment of <strong>${formatGhs(amount)}</strong> has been released to the seller.
        </p>
      </div>
      <p style="color: #78716c; font-size: 13px;">Thank you for using Instiy! We hope you enjoy your purchase.</p>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>''',
    );
  }

  // ─── Seller Verification ───────────────────────────────────────

  static Future<void> sendVerificationApproved({
    required String userEmail,
    required String userName,
  }) async {
    final subject = 'Your seller profile has been verified!';
    await _sendEmail(
      to: userEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #4D7C59, #059669); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; text-align: center; }
    .check { font-size: 48px; margin: 16px 0; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Verification Approved</h1>
    </div>
    <div class="body">
      <div class="check">\u2705</div>
      <p>Hi $userName,</p>
      <p>Congratulations! Your seller profile has been <strong>verified</strong>.</p>
      <p>You now have a verified badge on your profile, which helps buyers trust your listings.</p>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>''',
    );
  }

  static Future<void> sendVerificationRejected({
    required String userEmail,
    required String userName,
    String? reason,
  }) async {
    final subject = 'Verification request update';
    await _sendEmail(
      to: userEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #DC2626, #EF4444); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .info-box { background: #f5f5f4; border-radius: 8px; padding: 12px 16px; margin: 12px 0; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Verification Update</h1>
    </div>
    <div class="body">
      <p>Hi $userName,</p>
      <p>Unfortunately, your verification request could not be approved at this time.</p>
      ${reason != null ? '<div class="info-box"><p style="margin: 0; font-size: 13px; color: #78716c;"><strong>Reason:</strong> $reason</p></div>' : ''}
      <p style="color: #78716c; font-size: 13px;">You can re-submit your verification request after addressing the issue.</p>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>''',
    );
  }

  // ─── Reviews ───────────────────────────────────────────────────

  static Future<void> sendNewReview({
    required String sellerEmail,
    required String sellerName,
    required String reviewerName,
    required String productTitle,
    required int rating,
    required String? comment,
  }) async {
    final stars = '\u2B50' * rating;
    final subject = 'New review on "$productTitle"';
    await _sendEmail(
      to: sellerEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #D97706, #F59E0B); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .stars { font-size: 24px; text-align: center; margin: 16px 0; }
    .comment { background: #f5f5f4; border-radius: 8px; padding: 12px 16px; margin: 12px 0; font-style: italic; color: #78716c; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>New Review</h1>
    </div>
    <div class="body">
      <p>Hi $sellerName,</p>
      <p><strong>$reviewerName</strong> left a review on <strong>$productTitle</strong>.</p>
      <div class="stars">$stars</div>
      ${comment != null ? '<div class="comment">"$comment"</div>' : ''}
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>''',
    );
  }

  static Future<void> sendReviewReply({
    required String reviewerEmail,
    required String reviewerName,
    required String sellerName,
    required String productTitle,
    required String reply,
  }) async {
    final subject = '$sellerName replied to your review';
    await _sendEmail(
      to: reviewerEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #6c47ff, #8B5CF6); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .reply { background: #f5f5f4; border-radius: 8px; padding: 12px 16px; margin: 12px 0; border-left: 3px solid #6c47ff; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Seller Replied</h1>
    </div>
    <div class="body">
      <p>Hi $reviewerName,</p>
      <p><strong>$sellerName</strong> replied to your review on <strong>$productTitle</strong>.</p>
      <div class="reply">
        <p style="margin: 0; color: #1c1917;">$reply</p>
      </div>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>''',
    );
  }

  // ─── New Product from Followed Seller ─────────────────────────

  static Future<void> sendNewProductFromFollowedSeller({
    required String followerEmail,
    required String followerName,
    required String sellerName,
    required String productTitle,
    required double productPrice,
    required String? productThumbnail,
    required String productId,
  }) async {
    final slug = Product.generateSlug(productTitle);
    final deepLink = 'https://instiy.com/products/$slug-$productId';
    final thumbnailHtml = productThumbnail != null
        ? '<img src="$productThumbnail" alt="$productTitle" style="width: 100%; max-width: 400px; border-radius: 12px; margin: 16px 0;" />'
        : '';

    final subject = '$sellerName just listed a new product';
    await _sendEmail(
      to: followerEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #6c47ff, #8B5CF6); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .product-card { background: #f5f5f4; border-radius: 12px; padding: 16px; margin: 16px 0; text-align: center; }
    .product-title { font-size: 16px; font-weight: 600; color: #1c1917; margin: 8px 0 4px; }
    .product-price { font-size: 20px; font-weight: 700; color: #6c47ff; }
    .btn { display: inline-block; background: linear-gradient(135deg, #6c47ff, #8B5CF6); color: white; text-decoration: none; padding: 14px 32px; border-radius: 10px; font-weight: 600; font-size: 15px; margin: 16px 0; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>New Listing!</h1>
    </div>
    <div class="body">
      <p>Hi $followerName,</p>
      <p><strong>$sellerName</strong>, who you follow, just listed a new product:</p>
      <div class="product-card">
        $thumbnailHtml
        <div class="product-title">$productTitle</div>
        <div class="product-price">${formatGhs(productPrice)}</div>
      </div>
      <div style="text-align: center;">
        <a href="$deepLink" class="btn">View Product</a>
      </div>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>''',
    );
  }

  // ─── Product Report Confirmation (to reporter) ──────────────

  static Future<void> sendProductReportConfirmation({
    required String reporterEmail,
    required String reporterName,
    required String productTitle,
    required String category,
  }) async {
    final subject = 'Report received — "$productTitle"';
    await _sendEmail(
      to: reporterEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #6c47ff, #8B5CF6); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .label { color: #78716c; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 4px; }
    .value { color: #1c1917; font-size: 15px; font-weight: 600; margin-bottom: 16px; }
    .divider { border-top: 1px solid #e7e5e4; margin: 16px 0; }
    .badge { display: inline-block; background: #fef3c7; color: #92400e; padding: 4px 12px; border-radius: 20px; font-size: 13px; font-weight: 600; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Report Received</h1>
    </div>
    <div class="body">
      <p>Hi $reporterName,</p>
      <p>Thank you for helping keep Instiy safe. We've received your report and our team will review it shortly.</p>
      <div class="divider"></div>
      <div class="label">Product</div>
      <div class="value">$productTitle</div>
      <div class="label">Reason</div>
      <div class="value"><span class="badge">$category</span></div>
      <div class="divider"></div>
      <p style="color: #78716c; font-size: 13px;">
        You'll be notified once we've reviewed this report. If we need more information, we'll reach out to you.
      </p>
    </div>
    <div class="footer">
      <p>Instiy — Student Marketplace</p>
    </div>
  </div>
</body>
</html>''',
    );
  }

  // ─── Admin Product Report Notification ──────────────────────

  static Future<void> sendAdminProductReportNotification({
    required String adminEmail,
    required String productTitle,
    required String reporterName,
    required String category,
    String? description,
    required String productId,
  }) async {
    final subject = '[Report] $category — "$productTitle"';
    await _sendEmail(
      to: adminEmail,
      subject: subject,
      htmlBody: '''
<!DOCTYPE html>
<html>
<head>
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; background: #f5f5f4; margin: 0; padding: 20px; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #dc2626, #ef4444); padding: 32px 24px; text-align: center; }
    .header h1 { color: white; margin: 0; font-size: 20px; }
    .body { padding: 24px; }
    .label { color: #78716c; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 4px; }
    .value { color: #1c1917; font-size: 15px; font-weight: 600; margin-bottom: 16px; }
    .divider { border-top: 1px solid #e7e5e4; margin: 16px 0; }
    .badge { display: inline-block; background: #fee2e2; color: #991b1b; padding: 4px 12px; border-radius: 20px; font-size: 13px; font-weight: 600; }
    .desc-box { background: #f5f5f4; border-radius: 8px; padding: 12px 16px; margin: 12px 0; color: #1c1917; font-size: 14px; line-height: 1.5; }
    .btn { display: inline-block; background: linear-gradient(135deg, #dc2626, #ef4444); color: white; text-decoration: none; padding: 12px 28px; border-radius: 10px; font-weight: 600; font-size: 14px; margin: 8px 0; }
    .footer { padding: 16px 24px; background: #f5f5f4; text-align: center; color: #78716c; font-size: 12px; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>New Product Report</h1>
    </div>
    <div class="body">
      <p>A product has been reported and requires your review.</p>
      <div class="divider"></div>
      <div class="label">Product</div>
      <div class="value">$productTitle</div>
      <div class="label">Category</div>
      <div class="value"><span class="badge">$category</span></div>
      <div class="label">Reported by</div>
      <div class="value">$reporterName</div>
      ${description != null && description.isNotEmpty ? '''
      <div class="label">Details from reporter</div>
      <div class="desc-box">$description</div>
      ''' : ''}
      <div class="divider"></div>
      <div style="text-align: center;">
        <a href="https://instiy.com/admin/reports" class="btn">View in Admin Panel</a>
      </div>
      <p style="color: #78716c; font-size: 12px; text-align: center; margin-top: 8px;">
        Product ID: ${productId.substring(0, 8)}...
      </p>
    </div>
    <div class="footer">
      <p>Instiy — Admin Report Notification</p>
    </div>
  </div>
</body>
</html>''',
    );
  }

  // ─── Purchase Permission ─────────────────────────────────────────

  static Future<void> sendPurchasePermissionGranted({
    required String buyerEmail,
    required String buyerName,
    required String sellerName,
    required String productTitle,
    required String code,
  }) async {
    final htmlBody = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background-color: #f5f5f4; margin: 0; padding: 40px 20px; -webkit-font-smoothing: antialiased; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #6c47ff, #8B5CF6); color: white; padding: 32px 24px; text-align: center; }
    .header h1 { margin: 0; font-size: 22px; font-weight: 700; letter-spacing: -0.5px; }
    .content { padding: 32px 24px; color: #44403c; line-height: 1.6; font-size: 15px; }
    .code-box { background: #f5f5f4; border-radius: 12px; padding: 20px; margin: 24px 0; text-align: center; border: 1px dashed #6c47ff; }
    .code-label { font-size: 12px; text-transform: uppercase; color: #78716c; letter-spacing: 0.5px; display: block; margin-bottom: 6px; font-weight: 600; }
    .code-value { font-size: 28px; color: #6c47ff; letter-spacing: 3.0px; font-family: monospace; font-weight: 700; }
    .warning { color: #dc2626; font-size: 13px; font-weight: 600; text-align: center; margin-top: 16px; }
    .footer { background: #f5f5f4; padding: 20px; text-align: center; font-size: 12px; color: #78716c; border-top: 1px solid #e7e5e4; }
    .footer p { margin: 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Permission Granted!</h1>
    </div>
    <div class="content">
      <p>Hi <strong>$buyerName</strong>,</p>
      <p>Good news! The seller <strong>$sellerName</strong> has granted you permission to buy <strong>"$productTitle"</strong> from their institution.</p>
      
      <div class="code-box">
        <span class="code-label">Access Code</span>
        <span class="code-value">$code</span>
      </div>

      <p class="warning">⚠️ This permission is valid for 24 hours only. Please complete your purchase before it expires!</p>
    </div>
    <div class="footer">
      <p>Instiy — Automated Access Notification</p>
    </div>
  </div>
</body>
</html>''';

    await _sendEmail(
      to: buyerEmail,
      subject: 'Permission Granted: Buy "$productTitle"',
      htmlBody: htmlBody,
    );
  }
}
