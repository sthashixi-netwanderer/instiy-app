/// Withdrawal fee rates retrieved from platform_settings table.
class WithdrawalFees {
  final double mobileMoneyRate;
  final double bankRate;

  const WithdrawalFees({
    required this.mobileMoneyRate,
    required this.bankRate,
  });

  factory WithdrawalFees.fromJson(Map<String, dynamic> json) {
    return WithdrawalFees(
      mobileMoneyRate: (json['mobile_money'] as num).toDouble(),
      bankRate: (json['bank'] as num).toDouble(),
    );
  }

  /// Returns the fee rate for a given method type.
  double rateFor(String methodType) {
    switch (methodType) {
      case 'mobile_money':
        return mobileMoneyRate;
      case 'bank':
        return bankRate;
      default:
        return 0.02; // fallback 2%
    }
  }

  /// Calculates fee amount and payout for a given withdrawal amount.
  ({double fee, double payout}) calculate(double amount, String methodType) {
    final rate = rateFor(methodType);
    final fee = (amount * rate * 100).round() / 100;
    final payout = amount - fee;
    return (fee: fee, payout: payout);
  }
}
