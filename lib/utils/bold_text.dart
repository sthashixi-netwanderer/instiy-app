/// Converts ASCII text to Unicode Mathematical Bold Sans-Serif characters.
/// These render as **bold** on WhatsApp, X, Facebook, Instagram, and most
/// social platforms — no markdown needed.
class BoldText {
  BoldText._();

  static const _upperA = 0x1D5D4; // 𝗔
  static const _lowerA = 0x1D5EE; // 𝗮
  static const _digitZero = 0x1D7EC; // 𝟬

  static String convert(String input) {
    final buf = StringBuffer();
    for (final code in input.runes) {
      final ch = String.fromCharCode(code);
      if (ch == ch.toUpperCase() && ch.toUpperCase() != ch.toLowerCase()) {
        buf.writeCharCode(_upperA + (code - 0x41));
      } else if (ch == ch.toLowerCase() && ch.toUpperCase() != ch.toLowerCase()) {
        buf.writeCharCode(_lowerA + (code - 0x61));
      } else if (code >= 0x30 && code <= 0x39) {
        buf.writeCharCode(_digitZero + (code - 0x30));
      } else {
        buf.writeCharCode(code);
      }
    }
    return buf.toString();
  }
}
