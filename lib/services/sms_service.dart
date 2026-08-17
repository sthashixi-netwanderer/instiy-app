import 'package:flutter/foundation.dart';
import 'supabase_service.dart';

class SmsService {
  static String normalizePhoneNumber(String phone) {
    var cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleaned.startsWith('0')) {
      cleaned = '+233${cleaned.substring(1)}';
    } else if (cleaned.isNotEmpty && !cleaned.startsWith('+')) {
      cleaned = '+$cleaned';
    }
    return cleaned;
  }

  static Future<bool> sendSms({
    required String to,
    required String content,
  }) async {
    final normalizedPhone = normalizePhoneNumber(to.trim());

    try {
      final data = await SupabaseService.callFunction('send-sms', body: {
        'to': normalizedPhone,
        'content': content,
      });

      return data['success'] == true;
    } catch (e) {
      debugPrint('SMS send failed via Edge Function: $e');
      return false;
    }
  }

  static Future<bool> sendOtp({
    required String to,
    required String otp,
  }) async {
    final content = 'Your Instiy verification code is: $otp. Please use this code to complete registration.';
    return await sendSms(to: to, content: content);
  }
}
