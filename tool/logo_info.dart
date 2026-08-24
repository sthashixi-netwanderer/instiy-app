import 'dart:io';
import 'package:image/image.dart';

void main() {
  for (final path in ['assets/logo.png', 'assets/logo_highres.png', 'assets/notification_icons/ic_notification_default.png', 'assets/notification_icons/ic_notification_message.png']) {
    final bytes = File(path).readAsBytesSync();
    final img = decodePng(bytes);
    if (img == null) { print('$path: NOT PNG decodable'); continue; }
    var transparent = 0, opaque = 0;
    for (final p in img) {
      if (p.a < 10) transparent++;
      else if (p.a > 245) opaque++;
    }
    final total = img.width * img.height;
    print('$path: ${img.width}x${img.height}, transparent=${(transparent*100/total).toStringAsFixed(1)}%, opaque=${(opaque*100/total).toStringAsFixed(1)}%');
  }
}
