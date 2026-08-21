import 'dart:async';
import 'package:pay_with_paystack/pay_with_paystack.dart';
import 'navigation_service.dart';
import 'supabase_service.dart';
import 'secrets_service.dart';

/// Paystack checkout built on `pay_with_paystack` (WebView-based).
///
/// The package initializes transactions client-side, so it is configured with
/// the secret key fetched at runtime from the worker (never bundled in the
/// binary). Verification before crediting a wallet or order is still done
/// server-side via the `paystack/verify` worker endpoint — the client-side
/// result alone never moves money.
class PaystackService {
  static bool _configured = false;

  /// Loads the remote Paystack key and configures the checkout package.
  /// Idempotent. Returns false when the key can't be fetched (e.g. the user
  /// is not signed in), in which case payments must not proceed.
  static Future<bool> initializeSDK() async {
    if (_configured) return true;
    try {
      // Ensure the remote Paystack keys are loaded before configuring the
      // checkout. On a fast cold boot the secrets fetch may still be in
      // flight, and payments must not use stale/empty keys.
      await SecretsService.instance.ensureLoaded();
      // The startup fetch is anonymous and gets no secret key; re-fetch with
      // the signed-in user's JWT attached.
      if (SecretsService.instance.paystackSecretKey.isEmpty) {
        await SecretsService.instance.refresh();
      }
      final secretKey = SecretsService.instance.paystackSecretKey;
      if (secretKey.isEmpty) {
        return false;
      }
      PayWithPayStack.configure(PaystackConfig(
        secretKey: secretKey,
        currency: 'GHS',
        // Only used as the redirect marker the WebView watches for — the
        // navigation is intercepted before this URL is actually loaded.
        callbackUrl: 'https://instiy.com/paystack/callback',
        enableLogging: false,
      ));
      _configured = true;
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Server-side verification via the worker (holds the secret key). This is
  /// the authoritative check before any wallet credit or order update.
  static Future<PaystackResult> verifyTransaction(String reference) async {
    try {
      final data = await SupabaseService.callFunction('paystack/verify', body: {
        'reference': reference,
      });
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

  /// Opens the pay_with_paystack checkout WebView and resolves with the
  /// outcome. The route pushes on the root navigator, so no screen context
  /// needs to be threaded through providers.
  static Future<PaystackResult> _launchCheckout({
    required double amount,
    required String email,
    required String reference,
    Map<String, dynamic>? metadata,
  }) async {
    final context = NavigationService.navigatorKey.currentContext;
    if (context == null) {
      return PaystackResult(success: false, error: 'Checkout unavailable, please try again');
    }

    // The package delivers its result via callbacks (the pushed route pops
    // without a return value), so bridge them to a Future.
    final outcome = Completer<PaystackResult>();
    unawaited(
      PayWithPayStack().now(
        context: context,
        customerEmail: email,
        reference: reference,
        amount: amount,
        metadata: metadata,
        transactionCompleted: (data) {
          if (!outcome.isCompleted) {
            outcome.complete(PaystackResult(
              success: data.status == 'success',
              reference: data.reference,
              error: data.status == 'success' ? null : (data.message ?? data.gatewayResponse ?? 'Payment not completed'),
            ));
          }
        },
        transactionNotCompleted: (reason) {
          if (!outcome.isCompleted) {
            outcome.complete(PaystackResult(success: false, reference: reference, error: reason));
          }
        },
        transactionCancelled: () {
          if (!outcome.isCompleted) {
            outcome.complete(PaystackResult(success: false, reference: reference, error: 'cancelled'));
          }
        },
      ).then((_) {
        // Checkout closed without any callback firing — treat as cancelled.
        if (!outcome.isCompleted) {
          outcome.complete(PaystackResult(success: false, reference: reference, error: 'cancelled'));
        }
      }),
    );
    return outcome.future;
  }

  static Future<PaystackResult> fundWallet(double amount) async {
    final supabase = SupabaseService.instance;
    final user = supabase.currentUser;
    if (user == null) {
      return PaystackResult(success: false, error: 'User not authenticated');
    }

    if (!await initializeSDK()) {
      return PaystackResult(success: false, error: 'Failed to initialize Paystack');
    }

    final reference = PayWithPayStack().generateUuidV4();
    final checkoutResult = await _launchCheckout(
      amount: amount,
      email: user.email!,
      reference: reference,
      metadata: {'user_id': user.id, 'purpose': 'wallet_funding'},
    );
    if (!checkoutResult.success) return checkoutResult;

    final verifyResult = await verifyTransaction(checkoutResult.reference ?? reference);
    if (!verifyResult.success) return verifyResult;

    final creditResult = await SupabaseService.client.rpc('credit_wallet', params: {
      'p_user_id': user.id,
      'p_amount': amount,
      'p_reference': checkoutResult.reference ?? reference,
      'p_description': 'Wallet funding via Paystack',
    });

    if (creditResult != true) {
      return PaystackResult(success: false, error: 'Database wallet update failed.');
    }

    return PaystackResult(success: true, reference: checkoutResult.reference ?? reference);
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

    if (!await initializeSDK()) {
      return PaystackResult(success: false, error: 'Failed to initialize Paystack');
    }

    final reference = 'ORDER-$orderId';
    final checkoutResult = await _launchCheckout(
      amount: amount,
      email: user.email!,
      reference: reference,
      metadata: {'user_id': user.id, 'order_id': orderId, 'purpose': 'order_payment'},
    );
    if (!checkoutResult.success) return checkoutResult;

    final verifyResult = await verifyTransaction(checkoutResult.reference ?? reference);
    if (!verifyResult.success) return verifyResult;

    final payResult = await SupabaseService.client.rpc('mark_order_paid', params: {
      'p_order_id': orderId,
      'p_reference': checkoutResult.reference ?? reference,
    });

    if (payResult != true) {
      return PaystackResult(success: false, error: 'Database order status update failed.');
    }

    return PaystackResult(success: true, reference: checkoutResult.reference ?? reference);
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
