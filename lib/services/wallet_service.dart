import 'dart:math';
import 'dart:isolate';
import 'supabase_service.dart';
import '../models/wallet_model.dart';
import 'local_notification_service.dart';
import 'email_service.dart';

class WalletService {
  static Future<Wallet?> getWallet() async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return null;

    var response = await supabase
        .from('wallets')
        .select('*')
        .eq('user_id', uid)
        .maybeSingle();

    if (response == null) {
      try {
        response = await supabase
            .from('wallets')
            .insert({
              'user_id': uid,
              'balance': 0.0,
              'currency': 'GHS',
            })
            .select('*')
            .single();
      } catch (e) {
        response = await supabase
            .from('wallets')
            .select('*')
            .eq('user_id', uid)
            .maybeSingle();
      }
    }

    if (response == null) return null;
    return Wallet.fromJson(response);
  }

  static const int _pageSize = 20;

  static Future<List<WalletTransaction>> getTransactions({
    int offset = 0,
    int limit = _pageSize,
    String? type,
    String? search,
  }) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return [];

    final wallet = await supabase
        .from('wallets')
        .select('id')
        .eq('user_id', uid)
        .maybeSingle();

    if (wallet == null) return [];

    var query = supabase
        .from('wallet_transactions')
        .select('*')
        .eq('wallet_id', wallet['id']);

    if (type != null && type != 'all') {
      if (type == 'credit') {
        query = query.inFilter('type', ['deposit', 'transfer_in']);
      } else if (type == 'debit') {
        query = query.neq('type', 'deposit').neq('type', 'transfer_in');
      } else {
        query = query.eq('type', type);
      }
    }

    if (search != null && search.isNotEmpty) {
      query = query.or('description.ilike.%$search%,reference.ilike.%$search%,source.ilike.%$search%,type.ilike.%$search%');
    }

    final response = await query
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);

    return Isolate.run(() => _parseTransactionsList(response));
  }

  static List<WalletTransaction> _parseTransactionsList(List<Map<String, dynamic>> response) {
    return response
        .map((json) => WalletTransaction.fromJson(json))
        .toList();
  }

  static Future<double> getPendingBalance() async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return 0;

    final response = await SupabaseService.client
        .rpc('get_pending_balance', params: {'p_user_id': uid});

    return ((response as num?)?.toDouble() ?? 0);
  }

  static Future<List<WithdrawalRequest>> getWithdrawalRequests() async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return [];

    final response = await supabase
        .from('withdrawal_requests')
        .select('*')
        .eq('user_id', uid)
        .order('created_at', ascending: false);

    return Isolate.run(() => _parseWithdrawalsList(response));
  }

  static List<WithdrawalRequest> _parseWithdrawalsList(List<Map<String, dynamic>> response) {
    return response
        .map((json) => WithdrawalRequest.fromJson(json))
        .toList();
  }

  static Future<void> requestWithdrawal({
    required double amount,
    required String methodType,
    String? providerType,
    String? accountDetails,
  }) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser!.id;

    await supabase.from('withdrawal_requests').insert({
      'user_id': uid,
      'amount_requested': amount,
      'method_type': methodType,
      'provider_type': providerType,
      'account_details': accountDetails,
      'status': 'pending',
    });
  }

  static Future<void> transferToUser({
    required String recipientId,
    required double amount,
    String? description,
  }) async {
    // Get sender and recipient info before transfer
    final senderId = SupabaseService.auth.currentUser?.id;
    final sender = await SupabaseService.client
        .from('users')
        .select('full_name, email')
        .eq('id', senderId!)
        .maybeSingle();

    final recipient = await SupabaseService.client
        .from('users')
        .select('full_name, email')
        .eq('id', recipientId)
        .maybeSingle();

    final ref = 'TFR-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(99999)}';
    final recipientName = recipient?['full_name'] as String? ?? 'User';
    final senderName = sender?['full_name'] as String? ?? 'User';

    final success = await SupabaseService.client.rpc('transfer_wallet_funds', params: {
      'recipient_id': recipientId,
      'amount': amount,
      'description': description,
      'p_reference': ref,
      'p_recipient_name': recipientName,
      'p_sender_name': senderName,
    });

    if (success != true) {
      throw Exception('Transfer failed. Please check your balance and try again.');
    }

    // Send device notifications
    await LocalNotificationService.notifyTransferSent(
      amount: amount,
      recipientName: recipientName,
    );
    await LocalNotificationService.notifyTransferReceived(
      amount: amount,
      senderName: senderName,
    );

    // Send emails
    final senderEmail = sender?['email'] as String?;
    final recipientEmail = recipient?['email'] as String?;
    if (senderEmail != null) {
      await EmailService.sendTransferSent(
        senderEmail: senderEmail,
        senderName: senderName,
        recipientName: recipientName,
        amount: amount,
      );
    }
    if (recipientEmail != null) {
      await EmailService.sendTransferReceived(
        recipientEmail: recipientEmail,
        recipientName: recipientName,
        senderName: senderName,
        amount: amount,
      );
    }
  }

  static Future<bool> deductWallet({
    required double amount,
    required String description,
    String? reference,
  }) async {
    final supabase = SupabaseService.instance;
    final uid = supabase.currentUser?.id;
    if (uid == null) return false;

    final result = await SupabaseService.client.rpc('deduct_wallet', params: {
      'p_user_id': uid,
      'p_amount': amount,
      'p_description': description,
      'p_reference': reference,
    });
    return result as bool;
  }

  static Future<bool> checkBalance(double amount) async {
    final wallet = await getWallet();
    if (wallet == null) return false;
    final pending = await getPendingBalance();
    return (wallet.balance - pending) >= amount;
  }
}
