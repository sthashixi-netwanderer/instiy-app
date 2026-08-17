import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/wallet_model.dart';
import '../models/withdrawal_fees_model.dart';
import '../services/wallet_service.dart';
import '../services/paystack_service.dart';
import '../services/supabase_service.dart';
import '../services/email_service.dart';

class WalletProvider extends ChangeNotifier {
  Wallet? _wallet;
  List<WalletTransaction> _transactions = [];
  List<WithdrawalRequest> _withdrawalRequests = [];
  double _pendingBalance = 0;
  WithdrawalFees _withdrawalFees = const WithdrawalFees(mobileMoneyRate: 0.02, bankRate: 0.01);
  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _transactionPage = 0;
  String? _error;
  String _searchQuery = '';
  String _filterType = 'all';

  RealtimeChannel? _walletChannel;
  RealtimeChannel? _transactionsChannel;
  RealtimeChannel? _withdrawalsChannel;

  String? _currentUserId;

  WalletProvider() {
    _initAuthListener();
  }

  void _initAuthListener() {
    SupabaseService.auth.onAuthStateChange.listen((data) {
      final session = data.session;
      if (session != null) {
        final userId = session.user.id;
        if (_currentUserId == userId) return;
        _currentUserId = userId;
        _subscribeToRealtime(userId);
      } else {
        _unsubscribeFromRealtime();
        clearSession();
        _currentUserId = null;
      }
    });

    final currentUser = SupabaseService.auth.currentUser;
    if (currentUser != null) {
      _currentUserId = currentUser.id;
      _subscribeToRealtime(currentUser.id);
    }
  }

  void _subscribeToRealtime(String userId) {
    _unsubscribeFromRealtime();

    _walletChannel = SupabaseService.client
        .channel('wallet:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallets',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _silentReload(),
        );
    _walletChannel!.subscribe();

    _transactionsChannel = SupabaseService.client
        .channel('wallet-txns:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'wallet_transactions',
          callback: (_) => _silentReload(),
        );
    _transactionsChannel!.subscribe();

    _withdrawalsChannel = SupabaseService.client
        .channel('wallet-withdrawals:$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'withdrawal_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _silentReload(),
        );
    _withdrawalsChannel!.subscribe();
  }

  void _unsubscribeFromRealtime() {
    for (final ch in [_walletChannel, _transactionsChannel, _withdrawalsChannel]) {
      if (ch != null) SupabaseService.client.removeChannel(ch);
    }
    _walletChannel = null;
    _transactionsChannel = null;
    _withdrawalsChannel = null;
  }

  Future<void> _silentReload() async {
    try {
      _wallet = await WalletService.getWallet();
      _transactions = await WalletService.getTransactions(type: _filterType, search: _searchQuery);
      _pendingBalance = await WalletService.getPendingBalance();
      _withdrawalRequests = await WalletService.getWithdrawalRequests();
      notifyListeners();
    } catch (_) {}
  }

  void clearSession() {
    _wallet = null;
    _transactions = [];
    _withdrawalRequests = [];
    _pendingBalance = 0;
    _error = null;
    _searchQuery = '';
    _filterType = 'all';
    notifyListeners();
  }

  Wallet? get wallet => _wallet;
  List<WalletTransaction> get transactions => _transactions;
  List<WithdrawalRequest> get withdrawalRequests => _withdrawalRequests;
  double get pendingBalance => _pendingBalance;
  WithdrawalFees get withdrawalFees => _withdrawalFees;
  double get availableBalance =>
      (_wallet?.balance ?? 0) - _pendingBalance;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  String get searchQuery => _searchQuery;
  String get filterType => _filterType;

  void setSearchQuery(String query) {
    if (_searchQuery == query) return;
    _searchQuery = query;
    loadWallet();
  }

  void setFilterType(String type) {
    if (_filterType == type) return;
    _filterType = type;
    loadWallet();
  }

  Future<void> loadWallet() async {
    _isLoading = true;
    _transactionPage = 0;
    _hasMore = true;
    notifyListeners();

    try {
      _wallet = await WalletService.getWallet();
      _transactions = await WalletService.getTransactions(offset: 0, type: _filterType, search: _searchQuery);
      _hasMore = _transactions.length >= 20;
      _pendingBalance = await WalletService.getPendingBalance();
      _withdrawalRequests = await WalletService.getWithdrawalRequests();
      _withdrawalFees = await WalletService.getWithdrawalFees();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh wallet data without showing skeleton loader
  Future<void> silentRefresh() async {
    try {
      _wallet = await WalletService.getWallet();
      _transactions = await WalletService.getTransactions(offset: 0, type: _filterType, search: _searchQuery);
      _hasMore = _transactions.length >= 20;
      _pendingBalance = await WalletService.getPendingBalance();
      _withdrawalRequests = await WalletService.getWithdrawalRequests();
      _withdrawalFees = await WalletService.getWithdrawalFees();
      _transactionPage = 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> loadMoreTransactions() async {
    if (_isLoadingMore || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();

    try {
      _transactionPage++;
      final more = await WalletService.getTransactions(offset: _transactionPage * 20, type: _filterType, search: _searchQuery);
      _transactions.addAll(more);
      _hasMore = more.length >= 20;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> requestWithdrawal({
    required double amount,
    required String methodType,
    String? providerType,
    String? accountDetails,
    double? feeAmount,
    double? amountToReceive,
  }) async {
    try {
      await WalletService.requestWithdrawal(
        amount: amount,
        methodType: methodType,
        providerType: providerType,
        accountDetails: accountDetails,
        feeAmount: feeAmount,
        amountToReceive: amountToReceive,
      );

      // Send email notification
      final userId = SupabaseService.auth.currentUser?.id;
      if (userId != null) {
        final user = await SupabaseService.client
            .from('users')
            .select('full_name, email')
            .eq('id', userId)
            .maybeSingle();

        if (user != null) {
          final email = user['email'] as String?;
          if (email != null) {
            await EmailService.sendWithdrawalRequest(
              userEmail: email,
              userName: user['full_name'] as String? ?? 'User',
              amount: amount,
              method: methodType,
            );
          }
        }
      }

      await silentRefresh();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> transferToUser({
    required String recipientId,
    required double amount,
    String? description,
  }) async {
    try {
      await WalletService.transferToUser(
        recipientId: recipientId,
        amount: amount,
        description: description,
      );
      await silentRefresh();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<String?> fundWalletWithPaystack(double amount) async {
    try {
      final result = await PaystackService.fundWallet(amount);
      if (result.success) {
        await silentRefresh();
        return null;
      }
      return result.error;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> deductAndCreateOrder({
    required double amount,
    required String orderId,
    required String description,
  }) async {
    final hasBalance = await WalletService.checkBalance(amount);
    if (!hasBalance) return 'Insufficient wallet balance';

    try {
      final ok = await WalletService.deductWallet(
        amount: amount,
        description: description,
        reference: 'ORDER-$orderId',
      );
      if (ok) {
        await silentRefresh();
        return null;
      }
      return 'Failed to deduct from wallet';
    } catch (e) {
      return e.toString();
    }
  }

  @override
  void dispose() {
    _unsubscribeFromRealtime();
    super.dispose();
  }
}
