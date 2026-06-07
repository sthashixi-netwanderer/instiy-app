import 'package:flutter/services.dart';
import 'package:paystack_flutter_sdk/paystack_flutter_sdk.dart';
import 'supabase_service.dart';
import 'secrets_service.dart';

class PaystackService {
  static final Paystack _paystack = Paystack();
  static bool _initialized = false;

  static Future<bool> initializeSDK() async {
    if (_initialized) return true;
    try {
      _initialized = await _paystack.initialize(SecretsService.instance.paystackPublicKey, false);
      return _initialized;
    } catch (e) {
      return false;
    }
  }

  /// Calls the 'paystack' edge function with a sub-path action via the
  /// Supabase client's built-in functions.invoke(). This automatically sends
  /// the user's JWT and handles auth/CORS correctly.
  static Future<PaystackResult> initializeTransaction({
    required double amount,
    required String email,
    String? reference,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final response = await SupabaseService.client.functions.invoke(
        'paystack/initialize',
        body: <String, dynamic>{
          'email': email,
          'amount': (amount * 100).toStringAsFixed(0),
          'reference': ?reference,
          'metadata': ?metadata,
        },
      );

      final data = response.data as Map<String, dynamic>;
      if (data['status'] == true) {
        return PaystackResult(
          success: true,
          accessCode: data['data']['access_code'] as String,
          reference: data['data']['reference'] as String,
        );
      }
      return PaystackResult(success: false, error: data['message'] as String?);
    } catch (e) {
      return PaystackResult(success: false, error: e.toString());
    }
  }

  static Future<PaystackResult> verifyTransaction(String reference) async {
    try {
      final response = await SupabaseService.client.functions.invoke(
        'paystack/verify',
        body: {'reference': reference},
      );

      final data = response.data as Map<String, dynamic>;
      if (data['status'] == true) {
        final gatewayResponse = data['data'];
        return PaystackResult(
          success: gatewayResponse['status'] == 'success',
          reference: reference,
          amount: double.tryParse(gatewayResponse['amount']?.toString() ?? ''),
        );
      }
      return PaystackResult(success: false, error: data['message'] as String?);
    } catch (e) {
      return PaystackResult(success: false, error: e.toString());
    }
  }

  static Future<PaystackResult> launchPayment(String accessCode) async {
    if (!_initialized && !await initializeSDK()) {
      return PaystackResult(success: false, error: 'SDK initialization failed');
    }

    try {
      final response = await _paystack.launch(accessCode);
      return PaystackResult(
        success: response.status == 'success',
        reference: response.reference,
        error: response.status == 'success' ? null : response.message,
      );
    } on PlatformException catch (e) {
      return PaystackResult(success: false, error: e.message);
    } on Exception catch (e) {
      return PaystackResult(success: false, error: e.toString());
    } catch (e) {
      return PaystackResult(success: false, error: e.toString());
    }
  }

  static Future<PaystackResult> fundWallet(double amount) async {
    final supabase = SupabaseService.instance;
    final user = supabase.currentUser;
    if (user == null) {
      return PaystackResult(success: false, error: 'User not authenticated');
    }

    final initResult = await initializeTransaction(
      amount: amount,
      email: user.email!,
      metadata: {'user_id': user.id, 'purpose': 'wallet_funding'},
    );

    if (!initResult.success) return initResult;

    final launchResult = await launchPayment(initResult.accessCode!);
    if (!launchResult.success) return launchResult;

    final verifyResult = await verifyTransaction(launchResult.reference!);
    if (!verifyResult.success) return verifyResult;

    final creditResult = await SupabaseService.client.rpc('credit_wallet', params: {
      'p_user_id': user.id,
      'p_amount': amount,
      'p_reference': launchResult.reference,
      'p_description': 'Wallet funding via Paystack',
    });

    if (creditResult != true) {
      return PaystackResult(success: false, error: 'Database wallet update failed.');
    }

    return PaystackResult(success: true, reference: launchResult.reference);
  }

  static Future<PaystackResult> payForOrder({
    required double amount,
    required String orderId,
  }) async {
    final supabase = SupabaseService.instance;
    final user = supabase.currentUser;
    if (user == null) {
      return PaystackResult(success: false, error: 'User not authenticated');
    }

    final initResult = await initializeTransaction(
      amount: amount,
      email: user.email!,
      reference: 'ORDER-$orderId',
      metadata: {'user_id': user.id, 'order_id': orderId, 'purpose': 'order_payment'},
    );

    if (!initResult.success) return initResult;

    final launchResult = await launchPayment(initResult.accessCode!);
    if (!launchResult.success) return launchResult;

    final verifyResult = await verifyTransaction(launchResult.reference!);
    if (!verifyResult.success) return verifyResult;

    final payResult = await SupabaseService.client.rpc('mark_order_paid', params: {
      'p_order_id': orderId,
      'p_reference': launchResult.reference,
    });

    if (payResult != true) {
      return PaystackResult(success: false, error: 'Database order status update failed.');
    }

    return PaystackResult(success: true, reference: launchResult.reference);
  }
}

class PaystackResult {
  final bool success;
  final String? accessCode;
  final String? reference;
  final double? amount;
  final String? error;

  PaystackResult({
    required this.success,
    this.accessCode,
    this.reference,
    this.amount,
    this.error,
  });
}
