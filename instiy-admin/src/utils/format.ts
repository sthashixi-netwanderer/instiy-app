/**
 * Formats a number with thousand separators and 2 decimal places (e.g. 1,000,000.00).
 */
export function formatCurrency(amount: number): string {
  return new Intl.NumberFormat('en-US', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  }).format(amount);
}

/**
 * Formats a number with GH₵ symbol (e.g. GH₵ 1,000,000.00).
 */
export function formatGhs(amount: number): string {
  return `GH₵ ${formatCurrency(amount)}`;
}
