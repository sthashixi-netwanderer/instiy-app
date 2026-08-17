import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter/foundation.dart';

class HiveCacheService {
  static const String productsBoxName = 'products_cache';

  static Future<void> initialize() async {
    try {
      await Hive.initFlutter();
      // Pre-open the boxes during splash screen so they are ready synchronously
      await Hive.openBox<String>(productsBoxName);
    } catch (e) {
      debugPrint('Hive initialization error: $e');
    }
  }

  static Box<String> get productsBox => Hive.box<String>(productsBoxName);
}
