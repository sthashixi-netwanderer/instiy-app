import 'package:flutter/material.dart';
import '../models/product_model.dart';
import 'product_service.dart';

class NavigationService {
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  static final RouteObserver<ModalRoute<dynamic>> routeObserver = RouteObserver<ModalRoute<dynamic>>();

  /// Buffer for a deep link received during cold start (before navigator is ready).
  static Uri? pendingDeepLink;

  /// Set of deep link URIs already handled in the current foreground session.
  /// Prevents duplicate navigation when Android recreates the Activity
  /// (e.g. keyboard open on some OEM devices), which causes app_links
  /// to re-emit the original deep link via EventChannel re-subscription.
  /// Cleared when the app goes to background so the same link can be
  /// legitimately opened again from a notification or external source.
  static final Set<String> _handledLinks = {};

  /// Timestamp when the app was last backgrounded. Deep links arriving
  /// within [_resumeGracePeriod] of resuming are suppressed — they are
  /// stale re-emissions from Activity recreation, not genuine new links.
  static DateTime? _backgroundedAt;
  static const _resumeGracePeriod = Duration(seconds: 3);

  /// Called when the app transitions to background (paused/detached).
  /// Clears the dedup set so a genuine new deep link can be handled,
  /// but records the timestamp for grace-period suppression.
  static void onAppBackgrounded() {
    _backgroundedAt = DateTime.now();
    _handledLinks.clear();
  }

  /// Navigate to the resolved product screen.
  static void _navigateToProduct(String productId) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.pushNamedAndRemoveUntil('/home', (route) => false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigatorKey.currentState;
      if (nav != null) {
        nav.pushNamed('/product', arguments: productId);
      }
    });
  }

  /// Navigate to a business profile screen.
  static void _navigateToBusinessProfile(String sellerId) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;

    navigator.pushNamedAndRemoveUntil('/home', (route) => false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final nav = navigatorKey.currentState;
      if (nav != null) {
        nav.pushNamed('/business-profile', arguments: sellerId);
      }
    });
  }

  /// Handle a deep link URI. Pushes home first to ensure a clean back-stack,
  /// then pushes the target screen on top.
  static Future<void> handleDeepLink(Uri uri) async {
    debugPrint('Handling deep link: $uri');

    final uriStr = uri.toString();

    // 1. Permanent session-level dedup: if this exact URI was already
    //    handled in the current foreground session, skip it.
    if (_handledLinks.contains(uriStr)) {
      debugPrint('Deep link ignored (already handled this session): $uri');
      return;
    }

    // 2. Grace-period suppression: after returning from background, ignore
    //    deep links that arrive within [_resumeGracePeriod]. These are stale
    //    re-emissions from Activity recreation (keyboard open on some OEM
    //    Android devices causes the Activity to be recreated despite
    //    configChanges, and app_links re-emits the stored initialLink).
    if (_backgroundedAt != null) {
      final elapsed = DateTime.now().difference(_backgroundedAt!);
      if (elapsed < _resumeGracePeriod) {
        debugPrint('Deep link ignored (within resume grace period): $uri');
        _handledLinks.add(uriStr);
        return;
      }
      _backgroundedAt = null;
    }

    _handledLinks.add(uriStr);

    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      debugPrint('Navigator not ready, buffering deep link');
      pendingDeepLink = uri;
      return;
    }

    // Parse the route and arguments from the URI
    String? routeName;
    String? arguments;

    // HTTPS instiy.com links
    if (uri.scheme == 'https' && uri.host == 'instiy.com') {
      if (uri.path.startsWith('/products/')) {
        routeName = '/product';
        final slugId = uri.pathSegments.length > 1 ? uri.pathSegments[1] : '';
        arguments = Product.extractId(slugId);
        // If UUID extraction failed, try slug-based DB lookup
        if (arguments == slugId) {
          final product = await ProductService.getProductBySlug(slugId);
          if (product != null) {
            arguments = product.id;
          }
        }
      } else if (uri.path.startsWith('/store/')) {
        routeName = '/business-profile';
        arguments = uri.pathSegments.length > 1 ? uri.pathSegments[1] : '';
      }
    }
    // Custom scheme: io.supabase.instiy://
    else if (uri.scheme == 'io.supabase.instiy' && uri.host == 'store') {
      routeName = '/business-profile';
      arguments = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
    } else if (uri.scheme == 'io.supabase.instiy' && uri.host == 'product') {
      routeName = '/product';
      arguments = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
      if (arguments.isEmpty) {
        arguments = uri.queryParameters['id'] ?? '';
      }
    }
    // Path-based fallbacks
    else if (uri.path.startsWith('/products/')) {
      routeName = '/product';
      final slugId = uri.pathSegments.length > 1 ? uri.pathSegments[1] : '';
      arguments = Product.extractId(slugId);
      // If UUID extraction failed, try slug-based DB lookup
      if (arguments == slugId) {
        final product = await ProductService.getProductBySlug(slugId);
        if (product != null) {
          arguments = product.id;
        }
      }
    } else if (uri.path.startsWith('/store/')) {
      routeName = '/business-profile';
      arguments = uri.pathSegments.length > 1 ? uri.pathSegments[1] : '';
    }
    // Edge function share-product link
    else if (uri.path.contains('/functions/v1/share-product')) {
      routeName = '/product';
      arguments = uri.queryParameters['id'] ?? '';
      if (arguments.isEmpty) {
        final index = uri.pathSegments.indexOf('share-product');
        if (index != -1 && uri.pathSegments.length > index + 1) {
          arguments = uri.pathSegments[index + 1];
        }
      }
    }

    if (routeName != null && arguments != null && arguments.isNotEmpty) {
      if (routeName == '/product') {
        _navigateToProduct(arguments);
      } else if (routeName == '/business-profile') {
        _navigateToBusinessProfile(arguments);
      }
    }
  }

  /// Called by SplashScreen after its animation completes to consume
  /// any deep link that arrived during cold start.
  static void flushPendingDeepLink() {
    if (pendingDeepLink != null) {
      final uri = pendingDeepLink;
      pendingDeepLink = null;
      handleDeepLink(uri!);
    }
  }
}
