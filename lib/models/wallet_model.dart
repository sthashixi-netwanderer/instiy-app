class Wallet {
  final String id;
  final String userId;
  final double balance;
  final String currency;
  final DateTime createdAt;
  final DateTime updatedAt;

  Wallet({
    required this.id,
    required this.userId,
    required this.balance,
    this.currency = 'GHS',
    required this.createdAt,
    required this.updatedAt,
  });

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      balance: (json['balance'] as num).toDouble(),
      currency: json['currency'] as String? ?? 'GHS',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class WalletTransaction {
  final String id;
  final String walletId;
  final String type;
  final double amount;
  final double balanceBefore;
  final double balanceAfter;
  final String? description;
  final String? reference;
  final String? source;
  final DateTime createdAt;

  WalletTransaction({
    required this.id,
    required this.walletId,
    required this.type,
    required this.amount,
    required this.balanceBefore,
    required this.balanceAfter,
    this.description,
    this.reference,
    this.source,
    required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: json['id'] as String,
      walletId: json['wallet_id'] as String,
      type: json['type'] as String,
      amount: (json['amount'] as num).toDouble(),
      balanceBefore: (json['balance_before'] as num).toDouble(),
      balanceAfter: (json['balance_after'] as num).toDouble(),
      description: json['description'] as String?,
      reference: json['reference'] as String?,
      source: json['source'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class WithdrawalRequest {
  final String id;
  final String userId;
  final double amountRequested;
  final double? feeAmount;
  final double? amountToReceive;
  final String methodType;
  final String? providerType;
  final String? accountDetails;
  final String status;
  final String? adminNotes;
  final DateTime createdAt;

  WithdrawalRequest({
    required this.id,
    required this.userId,
    required this.amountRequested,
    this.feeAmount,
    this.amountToReceive,
    required this.methodType,
    this.providerType,
    this.accountDetails,
    required this.status,
    this.adminNotes,
    required this.createdAt,
  });

  factory WithdrawalRequest.fromJson(Map<String, dynamic> json) {
    return WithdrawalRequest(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      amountRequested: (json['amount_requested'] as num).toDouble(),
      feeAmount: (json['fee_amount'] as num?)?.toDouble(),
      amountToReceive: (json['amount_to_receive'] as num?)?.toDouble(),
      methodType: json['method_type'] as String,
      providerType: json['provider_type'] as String?,
      accountDetails: json['account_details'] as String?,
      status: json['status'] as String,
      adminNotes: json['admin_notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
