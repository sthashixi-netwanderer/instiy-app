import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/carousel_slide_model.dart';
import '../models/product_model.dart';
import '../services/carousel_service.dart';
import '../services/supabase_service.dart';

class CarouselProvider extends ChangeNotifier {
  List<CarouselSlide> _slides = [];
  Map<String, Product> _linkedProducts = {};
  bool _isLoading = false;
  String? _error;

  RealtimeChannel? _channel;
  Timer? _pollTimer;
  bool _initialized = false;

  List<CarouselSlide> get slides => _slides;
  Map<String, Product> get linkedProducts => _linkedProducts;
  bool get isLoading => _isLoading;
  String? get error => _error;

  CarouselProvider() {
    Future.microtask(() {
      _init();
    });
  }

  void _init() {
    if (_initialized) return;
    _initialized = true;
    _subscribeToRealtime();
    _startPolling();
    loadSlides();
  }

  void ensureInitialized() {
    if (!_initialized) {
      _init();
    }
  }

  void _subscribeToRealtime() {
    _unsubscribeFromRealtime();

    try {
      _channel = SupabaseService.client
          .channel('carousel-home-${DateTime.now().millisecondsSinceEpoch}')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'carousel_slides',
            callback: (_) => _silentReload(),
          );
      _channel!.subscribe();
    } catch (_) {}
  }

  void _unsubscribeFromRealtime() {
    if (_channel != null) {
      try {
        SupabaseService.client.removeChannel(_channel!);
      } catch (_) {}
      _channel = null;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _silentReload());
  }

  Future<void> _silentReload() async {
    try {
      final slides = await CarouselService.getVisibleSlides();
      if (!_listEquals(_slides, slides)) {
        _slides = slides;
        _linkedProducts = await CarouselService.getLinkedProducts(slides);
        notifyListeners();
      }
    } catch (_) {}
  }

  bool _listEquals(List<CarouselSlide> a, List<CarouselSlide> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].sortOrder != b[i].sortOrder ||
          a[i].mediaUrl != b[i].mediaUrl ||
          a[i].mediaType != b[i].mediaType ||
          a[i].title != b[i].title ||
          a[i].subtitle != b[i].subtitle ||
          a[i].buttonText != b[i].buttonText ||
          a[i].buttonLinkType != b[i].buttonLinkType ||
          a[i].buttonLinkValue != b[i].buttonLinkValue ||
          a[i].isVisible != b[i].isVisible) {
        return false;
      }
    }
    return true;
  }

  Future<void> loadSlides() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _slides = await CarouselService.getVisibleSlides();
      _linkedProducts = await CarouselService.getLinkedProducts(_slides);
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() => loadSlides();

  @override
  void dispose() {
    _pollTimer?.cancel();
    _unsubscribeFromRealtime();
    super.dispose();
  }
}
