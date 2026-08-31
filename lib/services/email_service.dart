import 'package:flutter/foundation.dart';
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

  /// Humanizes a permission duration for notification copy, e.g.
  /// "1 hour", "6 hours", "3 days".
  static String formatPermissionDuration(Duration d) {
    if (d.inHours >= 24) {
      final days = d.inDays;
      return days == 1 ? '1 day' : '$days days';
    }
    if (d.inHours >= 1) {
      return d.inHours == 1 ? '1 hour' : '${d.inHours} hours';
    }
    final mins = d.inMinutes;
    return mins <= 1 ? '1 minute' : '$mins minutes';
  }

  static Future<void> sendPurchasePermissionGranted({
    required String buyerEmail,
    required String buyerName,
    required String sellerName,
    required String productTitle,
    required String code,
    required Duration duration,
    required String productId,
  }) async {
    final durationText = formatPermissionDuration(duration);
    final productLink = 'https://instiy.com/product/$productId';
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
    .duration-box { background: #ecfdf5; border: 1px solid #a7f3d0; border-radius: 12px; padding: 14px 18px; margin: 16px 0; text-align: center; color: #065f46; font-size: 14px; font-weight: 600; }
    .cta-btn { display: block; width: 100%; box-sizing: border-box; background: #6c47ff; color: white !important; text-decoration: none; text-align: center; padding: 14px 24px; border-radius: 12px; font-size: 15px; font-weight: 700; margin: 24px 0 8px; }
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

      <div class="duration-box">⏱️ Permission duration: $durationText</div>

      <a href="$productLink" class="cta-btn">View "$productTitle" →</a>

      <p class="warning">⚠️ This permission is valid for $durationText only. Please complete your purchase before it expires!</p>
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

  static Future<void> sendPurchasePermissionRequested({
    required String sellerEmail,
    required String sellerName,
    required String buyerName,
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
    .header { background: linear-gradient(135deg, #f59e0b, #d97706); color: white; padding: 32px 24px; text-align: center; }
    .header h1 { margin: 0; font-size: 22px; font-weight: 700; letter-spacing: -0.5px; }
    .content { padding: 32px 24px; color: #44403c; line-height: 1.6; font-size: 15px; }
    .code-box { background: #f5f5f4; border-radius: 12px; padding: 20px; margin: 24px 0; text-align: center; border: 1px dashed #f59e0b; }
    .code-label { font-size: 12px; text-transform: uppercase; color: #78716c; letter-spacing: 0.5px; display: block; margin-bottom: 6px; font-weight: 600; }
    .code-value { font-size: 28px; color: #d97706; letter-spacing: 3.0px; font-family: monospace; font-weight: 700; }
    .footer { background: #f5f5f4; padding: 20px; text-align: center; font-size: 12px; color: #78716c; border-top: 1px solid #e7e5e4; }
    .footer p { margin: 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Purchase Permission Request</h1>
    </div>
    <div class="content">
      <p>Hi <strong>$sellerName</strong>,</p>
      <p>A buyer <strong>$buyerName</strong> wants to purchase <strong>"$productTitle"</strong> from your store. They are from a different institution and need your approval.</p>

      <div class="code-box">
        <span class="code-label">Buyer's Access Code</span>
        <span class="code-value">$code</span>
      </div>

      <p>Open the Instiy app, go to <strong>Seller Dashboard → Buyer Permissions</strong>, and enter this code to grant or reject the request.</p>
    </div>
    <div class="footer">
      <p>Instiy — Automated Access Notification</p>
    </div>
  </div>
</body>
</html>''';

    await _sendEmail(
      to: sellerEmail,
      subject: 'Permission Request: "$productTitle" — Buyer Needs Approval',
      htmlBody: htmlBody,
    );
  }

  static Future<void> sendPurchasePermissionRejected({
    required String buyerEmail,
    required String buyerName,
    required String sellerName,
    required String productTitle,
  }) async {
    final htmlBody = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background-color: #f5f5f4; margin: 0; padding: 40px 20px; -webkit-font-smoothing: antialiased; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #dc2626, #b91c1c); color: white; padding: 32px 24px; text-align: center; }
    .header h1 { margin: 0; font-size: 22px; font-weight: 700; letter-spacing: -0.5px; }
    .content { padding: 32px 24px; color: #44403c; line-height: 1.6; font-size: 15px; }
    .footer { background: #f5f5f4; padding: 20px; text-align: center; font-size: 12px; color: #78716c; border-top: 1px solid #e7e5e4; }
    .footer p { margin: 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Permission Request Declined</h1>
    </div>
    <div class="content">
      <p>Hi <strong>$buyerName</strong>,</p>
      <p>Unfortunately, the seller <strong>$sellerName</strong> has declined your permission request to buy <strong>"$productTitle"</strong>.</p>
      <p>You can try messaging the seller directly to discuss the purchase.</p>
    </div>
    <div class="footer">
      <p>Instiy — Automated Access Notification</p>
    </div>
  </div>
</body>
</html>''';

    await _sendEmail(
      to: buyerEmail,
      subject: 'Permission Request Declined: "$productTitle"',
      htmlBody: htmlBody,
    );
  }

  static Future<void> sendPurchasePermissionRevoked({
    required String buyerEmail,
    required String buyerName,
    required String sellerName,
    required String productTitle,
  }) async {
    final htmlBody = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background-color: #f5f5f4; margin: 0; padding: 40px 20px; -webkit-font-smoothing: antialiased; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #dc2626, #b91c1c); color: white; padding: 32px 24px; text-align: center; }
    .header h1 { margin: 0; font-size: 22px; font-weight: 700; letter-spacing: -0.5px; }
    .content { padding: 32px 24px; color: #44403c; line-height: 1.6; font-size: 15px; }
    .footer { background: #f5f5f4; padding: 20px; text-align: center; font-size: 12px; color: #78716c; border-top: 1px solid #e7e5e4; }
    .footer p { margin: 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Access Permission Revoked</h1>
    </div>
    <div class="content">
      <p>Hi <strong>$buyerName</strong>,</p>
      <p>The seller <strong>$sellerName</strong> has revoked your permission to buy <strong>"$productTitle"</strong>.</p>
      <p>If you still want this item, please message the seller or send a new permission request.</p>
    </div>
    <div class="footer">
      <p>Instiy — Automated Access Notification</p>
    </div>
  </div>
</body>
</html>''';

    await _sendEmail(
      to: buyerEmail,
      subject: 'Permission Revoked: "$productTitle"',
      htmlBody: htmlBody,
    );
  }

  // ─── Service Provider Disabled Appeal / Complaint ────────────────

  static Future<void> sendServiceProviderComplaintConfirmation({
    required String userEmail,
    required String userName,
    required String complaintText,
  }) async {
    final subject = 'Your Service Provider Complaint Has Been Received';
    final htmlBody = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background-color: #f5f5f4; margin: 0; padding: 40px 20px; -webkit-font-smoothing: antialiased; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #f59e0b, #d97706); color: white; padding: 32px 24px; text-align: center; }
    .header h1 { margin: 0; font-size: 22px; font-weight: 700; letter-spacing: -0.5px; }
    .content { padding: 32px 24px; color: #44403c; line-height: 1.6; font-size: 15px; }
    .label { color: #78716c; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 4px; font-weight: 600; }
    .desc-box { background: #f5f5f4; border-left: 4px solid #f59e0b; border-radius: 8px; padding: 14px 18px; margin: 16px 0; color: #1c1917; font-size: 14px; line-height: 1.5; white-space: pre-wrap; }
    .notice-box { background: #eff6ff; border: 1px solid #bfdbfe; border-radius: 10px; padding: 14px 16px; margin: 20px 0; color: #1e40af; font-size: 14px; }
    .footer { background: #f5f5f4; padding: 20px; text-align: center; font-size: 12px; color: #78716c; border-top: 1px solid #e7e5e4; }
    .footer p { margin: 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Complaint Under Review</h1>
    </div>
    <div class="content">
      <p>Hi <strong>$userName</strong>,</p>
      <p>We have received your complaint regarding the disabled status of your service provider account. Our administrative moderation team has been notified and is reviewing your request.</p>
      
      <div class="label">Your Submitted Statement:</div>
      <div class="desc-box">$complaintText</div>

      <div class="notice-box">
        <strong>Please keep watch in your email.</strong> We will notify you here as soon as our administrative team completes the review of your account.
      </div>
      
      <p>Thank you for your patience while we review your account.</p>
    </div>
    <div class="footer">
      <p>&copy; ${DateTime.now().year} Instiy Support Team</p>
    </div>
  </div>
</body>
</html>''';

    await _sendEmail(
      to: userEmail,
      subject: subject,
      htmlBody: htmlBody,
    );
  }

  static Future<void> sendAdminServiceProviderComplaintNotification({
    required String adminEmail,
    required String userName,
    required String userEmail,
    required String userUniversity,
    required String complaintText,
    required String userId,
  }) async {
    final subject = '[Action Required] Service Provider Appeal — $userName';
    final htmlBody = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background-color: #f5f5f4; margin: 0; padding: 40px 20px; -webkit-font-smoothing: antialiased; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #ef4444, #dc2626); color: white; padding: 32px 24px; text-align: center; }
    .header h1 { margin: 0; font-size: 22px; font-weight: 700; letter-spacing: -0.5px; }
    .content { padding: 32px 24px; color: #44403c; line-height: 1.6; font-size: 15px; }
    .divider { border-top: 1px solid #e7e5e4; margin: 16px 0; }
    .label { color: #78716c; font-size: 12px; text-transform: uppercase; letter-spacing: 0.05em; margin-bottom: 4px; font-weight: 600; }
    .value { color: #1c1917; font-size: 15px; font-weight: 600; margin-bottom: 12px; }
    .desc-box { background: #f5f5f4; border-left: 4px solid #ef4444; border-radius: 8px; padding: 14px 18px; margin: 16px 0; color: #1c1917; font-size: 14px; line-height: 1.5; white-space: pre-wrap; }
    .btn { display: block; width: 100%; box-sizing: border-box; background: linear-gradient(135deg, #ef4444, #dc2626); color: white !important; text-decoration: none; text-align: center; padding: 14px 24px; border-radius: 12px; font-size: 15px; font-weight: 700; margin: 24px 0 8px; }
    .footer { background: #f5f5f4; padding: 20px; text-align: center; font-size: 12px; color: #78716c; border-top: 1px solid #e7e5e4; }
    .footer p { margin: 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Service Provider Appeal</h1>
    </div>
    <div class="content">
      <p>A user whose service provider account is disabled has submitted a complaint/appeal for administrative review.</p>
      
      <div class="divider"></div>
      <div class="label">Provider Name</div>
      <div class="value">$userName</div>

      <div class="label">Email</div>
      <div class="value">$userEmail</div>

      <div class="label">University</div>
      <div class="value">$userUniversity</div>

      <div class="label">User ID</div>
      <div class="value" style="font-family: monospace; font-size: 13px;">$userId</div>

      <div class="label">Submitted Complaint / Appeal</div>
      <div class="desc-box">$complaintText</div>

      <div style="text-align: center;">
        <a href="https://instiy.com/admin/reports" class="btn">Open Reports in Admin Panel</a>
      </div>
    </div>
    <div class="footer">
      <p>Instiy — Admin Report System</p>
    </div>
  </div>
</body>
</html>''';

    await _sendEmail(
      to: adminEmail,
      subject: subject,
      htmlBody: htmlBody,
    );
  }

  static Future<void> sendServiceProviderReinstatedNotification({
    required String userEmail,
    required String userName,
  }) async {
    final subject = 'Your Service Provider Account Has Been Reinstated';
    final htmlBody = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="utf-8">
  <title>$subject</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; background-color: #f5f5f4; margin: 0; padding: 40px 20px; -webkit-font-smoothing: antialiased; }
    .container { max-width: 500px; margin: 0 auto; background: white; border-radius: 16px; overflow: hidden; box-shadow: 0 2px 12px rgba(0,0,0,0.08); }
    .header { background: linear-gradient(135deg, #7c3aed, #9333ea); color: white; padding: 32px 24px; text-align: center; }
    .header h1 { margin: 0; font-size: 22px; font-weight: 700; letter-spacing: -0.5px; }
    .content { padding: 32px 24px; color: #44403c; line-height: 1.6; font-size: 15px; }
    .notice-box { background: #f5f3ff; border: 1px solid #ddd6fe; border-radius: 10px; padding: 14px 16px; margin: 20px 0; color: #5b21b6; font-size: 14px; }
    .btn { display: block; width: 100%; box-sizing: border-box; background: linear-gradient(135deg, #7c3aed, #6d28d9); color: white !important; text-decoration: none; text-align: center; padding: 14px 24px; border-radius: 12px; font-size: 15px; font-weight: 700; margin: 24px 0 8px; }
    .footer { background: #f5f5f4; padding: 20px; text-align: center; font-size: 12px; color: #78716c; border-top: 1px solid #e7e5e4; }
    .footer p { margin: 0; }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <img src="https://media.instiy.com/logo.png" alt="Instiy Logo" style="height: 40px; margin-bottom: 12px; display: inline-block;" />
      <h1>Account Reinstated</h1>
    </div>
    <div class="content">
      <p>Hi <strong>$userName</strong>,</p>
      <p>Great news! Your <strong>Instiy Service Provider account</strong> has been reviewed and reinstated by our administrative moderation team.</p>
      
      <div class="notice-box">
        <strong>You can now access your service dashboard:</strong> Create new service listings, manage pricing tiers, and connect with customers on Instiy.
      </div>

      <p>If you had existing listings that were set to inactive during the review period, you can now visit the <strong>My Services</strong> tab in the app to review and publish them at any time.</p>

      <div style="text-align: center;">
        <a href="https://instiy.com" class="btn">Open Instiy Services</a>
      </div>
    </div>
    <div class="footer">
      <p>&copy; ${DateTime.now().year} Instiy Support Team</p>
    </div>
  </div>
</body>
</html>''';

    await _sendEmail(
      to: userEmail,
      subject: subject,
      htmlBody: htmlBody,
    );
  }
}
