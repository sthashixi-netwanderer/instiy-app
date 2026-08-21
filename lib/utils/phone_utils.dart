/// Phone number helpers.
library;

/// Normalizes a phone number for wa.me links.
///
/// wa.me requires full international format with no `+` (e.g. `233244123456`).
/// Sellers typically store Ghanaian numbers in local format — `0244123456`
/// or sometimes `244123456` — which wa.me rejects. Local formats are
/// converted to the +233 international form; anything already international
/// is passed through unchanged.
String normalizeWhatsAppNumber(String number) {
  var cleaned = number.replaceAll(RegExp(r'[^\d]'), '');
  if (cleaned.startsWith('0')) {
    cleaned = '233${cleaned.substring(1)}';
  } else if (cleaned.length == 9) {
    cleaned = '233$cleaned';
  }
  return cleaned;
}
