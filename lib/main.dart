import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'services/navigation_service.dart';
import 'services/supabase_service.dart';
import 'providers/providers.dart';
import 'services/secrets_service.dart';
import 'services/local_notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'models/product_model.dart';
import 'models/business_profile_model.dart';

// ── Eagerly-loaded screens (splash, auth, home, explore, product detail,
//    cart, checkout, deep-link targets, and high-traffic routes) ──
import 'screens/auth/login_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/auth/suspended_screen.dart';
import 'screens/explore/explore_screen.dart';
import 'screens/search/search_screen.dart';
import 'screens/video/video_feed_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/cart/cart_screen.dart';
import 'screens/checkout/checkout_screen.dart';
import 'screens/wallet/wallet_screen.dart';
import 'screens/orders/orders_screen.dart';
import 'screens/messages/messages_screen.dart';
import 'screens/services/services_screen.dart';
import 'screens/wishlist/wishlist_screen.dart';
import 'screens/notifications/notifications_screen.dart';
import 'screens/account/account_settings_screen.dart';
import 'screens/profile/following_screen.dart';
import 'screens/sell/sell_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'screens/product/product_detail_screen.dart';
import 'screens/product/create_listing_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/edit_profile_screen.dart';
import 'screens/seller/dashboard_screen.dart';
import 'screens/seller/reviews_screen.dart';
import 'screens/seller/business_profile_screen.dart';
import 'screens/orders/order_detail_screen.dart';
import 'screens/curated/curated_collection_screen.dart';
import 'services/hive_cache_service.dart';

// ── Deferred imports: rarely-used screens loaded on demand to reduce
//    cold-start bundle weight. Each is loaded via loadLibrary() before
//    the screen widget is constructed. ──
import 'screens/seller/analytics_screen.dart' deferred as deferred_analytics;
import 'screens/seller/video_analytics_screen.dart'
    deferred as deferred_video_analytics;
import 'screens/info/faq_screen.dart' deferred as deferred_faq;
import 'screens/info/about_screen.dart' deferred as deferred_about;
import 'screens/info/about_legal_screen.dart' deferred as deferred_about_legal;
import 'screens/legal/policy_view_screen.dart' deferred as deferred_policy;
import 'screens/seller/edit_business_profile_screen.dart'
    deferred as deferred_edit_business;
import 'screens/seller/seller_verify_screen.dart'
    deferred as deferred_seller_verify;
import 'screens/seller/seller_profile_verification_screen.dart'
    deferred as deferred_seller_profile_verification;
import 'screens/seller/seller_permissions_screen.dart'
    deferred as deferred_seller_permissions;

/// Top-level initialization future. Assigned in main() BEFORE runApp()
/// but never awaited in main() — the splash screen awaits it instead.
/// This ensures the Flutter framework starts rendering immediately while
/// services initialize in the background.
late final Future<void> appInitialization;

/// CRITICAL-PATH initialization only. Everything the very first frame of the
/// app (splash → home) actually needs to render. Anything that is not strictly
/// required to show the home screen is deferred to [_initializeDeferred] so the
/// splash dismisses as fast as possible (fast cold boot).
///
/// Only Supabase (auth/session) and the Hive cache (offline-first home feed)
/// are on the critical path. Notifications, Firebase, secrets, and FCM are all
/// deferred.
Future<void> _initializeApp() async {
  // Critical: Supabase (session restore) + Hive cache (cached home feed).
  // These run in parallel and are the ONLY things the splash waits on.
  // Use a timeout so the splash never hangs if something takes too long on web.
  await Future.wait([
    SupabaseService.initialize().timeout(
      const Duration(seconds: 8),
      onTimeout: () {
        debugPrint('Supabase init timed out — continuing with defaults');
      },
    ),
    HiveCacheService.initialize().timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        debugPrint('Hive init timed out — continuing without cache');
      },
    ),
  ]);

  // Kick off everything non-critical without blocking the splash. The home
  // screen renders immediately from cached/session data while these finish.
  unawaited(_initializeDeferred());
}

/// Non-critical, post-first-frame initialization. Runs in the background after
/// the splash has handed off to the home screen. Each step is isolated so a
/// failure in one does not break the others.
Future<void> _initializeDeferred() async {
  if (!kIsWeb) {
    // Firebase + local notifications can initialize together.
    // Explicit DefaultFirebaseOptions (from flutterfire configure) match
    // the native GoogleService-Info.plist; on iOS the native
    // FirebaseApp.configure() in AppDelegate has already run, so this
    // returns the existing default app.
    await Future.wait([
      Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ).catchError((e) {
        debugPrint('Firebase init failed (deferred): $e');
        return Firebase.app();
      }),
      LocalNotificationService.initialize().catchError((e) {
        debugPrint('LocalNotificationService init failed (deferred): $e');
      }),
    ]);

    // Crashlytics: forward uncaught Dart errors once Firebase is ready.
    // Native crashes are captured by the Crashlytics SDK itself.
    FlutterError.onError =
        FirebaseCrashlytics.instance.recordFlutterFatalError;
    PlatformDispatcher.instance.onError = (error, stack) {
      FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      return true;
    };

    // FCM listeners depend on Firebase being initialized.
    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      unawaited(LocalNotificationService.setupFcmListeners());
    } catch (e) {
      debugPrint('FCM listener setup skipped or failed (deferred): $e');
    }
  }

  // Secrets are only needed for uploads / payments / Giphy, none of which
  // happen on first frame. SecretsService already exposes safe local defaults,
  // so fetching the remote overrides is fire-and-forget and never blocks boot.
  unawaited(
    SecretsService.instance.initialize().catchError((e) {
      debugPrint('SecretsService init failed (deferred), using defaults: $e');
    }),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Use clean URL paths on web (no # hash), enabling shareable deep links.
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  // Kick off initialization immediately but do NOT await it here.
  // The splash screen will await this future so the UI can render
  // its first frame without any delay.
  appInitialization = _initializeApp();

  // Show the splash screen immediately — heavy init runs in the background
  // so there's no dark gap between the native splash and Flutter's first frame.
  runApp(const InstiyApp());
}

// ─────────────────────────────────────────────────────────────────────────────
// Deferred-loading helper widget
// ─────────────────────────────────────────────────────────────────────────────

/// A lightweight widget that calls [loadLibrary] for a deferred import,
/// shows a minimal loading indicator, then builds the actual screen.
/// Used by onGenerateRoute for rarely-visited routes to reduce cold-start
/// bundle size.
class _DeferredLoader extends StatelessWidget {
  final Future<void> Function() loadLibrary;
  final Widget Function() builder;

  const _DeferredLoader({required this.loadLibrary, required this.builder});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: loadLibrary(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            backgroundColor: Color(0xFFFAFAF9),
            body: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFF78716C),
                ),
              ),
            ),
          );
        }
        if (snapshot.hasError) {
          return Scaffold(
            backgroundColor: const Color(0xFFFAFAF9),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 32,
                    color: Color(0xFF78716C),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Failed to load screen',
                    style: TextStyle(color: Colors.grey[600], fontSize: 14),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () {
                      // Force rebuild by navigating to the same route
                      final route = ModalRoute.of(context)?.settings.name;
                      if (route != null) {
                        Navigator.of(context).pushReplacementNamed(route);
                      }
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        return builder();
      },
    );
  }
}

class InstiyApp extends StatefulWidget {
  const InstiyApp({super.key});

  @override
  State<InstiyApp> createState() => _InstiyAppState();
}

class _InstiyAppState extends State<InstiyApp> with WidgetsBindingObserver {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initDeepLinking();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      NavigationService.onAppBackgrounded();
    }

    // Check suspension on resume — catches cases where the admin suspended
    // the user while the app was backgrounded (Realtime events are missed).
    if (state == AppLifecycleState.resumed) {
      _checkSuspensionOnResume();
    }
  }

  void _checkSuspensionOnResume() {
    try {
      final container = ProviderScope.containerOf(context, listen: false);
      final auth = container.read(authProvider);
      auth.checkSuspensionOnResume();
    } catch (_) {
      // Non-critical — widget tree may not be ready yet
    }
  }

  void _initDeepLinking() {
    _appLinks = AppLinks();

    // Handle incoming links when app is in foreground / background.
    // Guard against background emissions — Android may re-emit the initial
    // URI when the activity is recreated (keyboard open, locale change, etc.).
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        // Only handle deep links when the app is in the foreground.
        // Background emissions cause spurious navigation (e.g. keyboard open
        // triggers activity recreation → uriLinkStream fires → stack cleared).
        if (_lifecycleState != AppLifecycleState.resumed) {
          debugPrint('Deep link ignored (app not in foreground): $uri');
          return;
        }
        NavigationService.handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('Failed to receive deep link: $err');
      },
    );

    // If the app was opened by a link (cold start), store it for the splash
    // screen to consume after its animation completes. This avoids the race
    // condition where getInitialLink() resolves before the splash finishes
    // and pushNamed('/product') gets destroyed by pushReplacementNamed('/home').
    _appLinks
        .getInitialLink()
        .then((uri) {
          if (uri != null) {
            debugPrint('Deep link (cold start), stored for splash: $uri');
            NavigationService.pendingDeepLink = uri;
          }
        })
        .catchError((err) {
          debugPrint('Failed to get initial deep link: $err');
        });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      child: ShadApp(
        navigatorKey: NavigationService.navigatorKey,
        navigatorObservers: [NavigationService.routeObserver],
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.light,
        materialThemeBuilder: (context, theme) {
          final isDark = theme.brightness == Brightness.dark;
          return theme.copyWith(
            popupMenuTheme: AppTheme.popupMenuTheme(isDark: isDark),
          );
        },
        initialRoute: '/splash',
        onGenerateRoute: (settings) {
          // Helper to wrap all routes with smooth fade+slide transition
          Route<T> route<T>(Widget page) => AppTheme.fadeSlideRoute<T>(page);

          final name = settings.name ?? '';
          if (name.isNotEmpty) {
            try {
              final uri = Uri.parse(name);
              // Handle HTTPS instiy.com links
              if (uri.scheme == 'https' && uri.host == 'instiy.com') {
                if (uri.path.startsWith('/products/')) {
                  final slugId = uri.pathSegments.length > 1
                      ? uri.pathSegments[1]
                      : '';
                  final productId = Product.extractId(slugId);
                  if (productId.isNotEmpty) {
                    return route(ProductDetailScreen(productId: productId));
                  }
                } else if (uri.path.startsWith('/store/')) {
                  final sellerId = uri.pathSegments.length > 1
                      ? uri.pathSegments[1]
                      : '';
                  if (sellerId.isNotEmpty) {
                    return route(BusinessProfileScreen(sellerId: sellerId));
                  }
                }
              }
              // Handle deep link io.supabase.instiy://store/<sellerId>
              if (uri.scheme == 'io.supabase.instiy' && uri.host == 'store') {
                final sellerId = uri.pathSegments.isNotEmpty
                    ? uri.pathSegments.first
                    : '';
                if (sellerId.isNotEmpty) {
                  return route(BusinessProfileScreen(sellerId: sellerId));
                }
              }
              // Also support path-only formats (like '/store/<sellerId>')
              if (uri.path.startsWith('/store/')) {
                final sellerId = uri.pathSegments.length > 1
                    ? uri.pathSegments[1]
                    : '';
                if (sellerId.isNotEmpty) {
                  return route(BusinessProfileScreen(sellerId: sellerId));
                }
              }
              // Handle deep link io.supabase.instiy://product/<productId>
              if (uri.scheme == 'io.supabase.instiy' && uri.host == 'product') {
                String productId = uri.pathSegments.isNotEmpty
                    ? uri.pathSegments.first
                    : '';
                if (productId.isEmpty) {
                  productId = uri.queryParameters['id'] ?? '';
                }
                if (productId.isNotEmpty) {
                  return route(ProductDetailScreen(productId: productId));
                }
              }
              // Also support path-only formats (like '/products/<slug>-<productId>')
              if (uri.path.startsWith('/products/')) {
                final slugId = uri.pathSegments.length > 1
                    ? uri.pathSegments[1]
                    : '';
                final productId = Product.extractId(slugId);
                if (productId.isNotEmpty) {
                  return route(ProductDetailScreen(productId: productId));
                }
              }
              // Handle direct HTTPS link to functions/v1/share-product
              if (uri.path.contains('/functions/v1/share-product')) {
                String productId = uri.queryParameters['id'] ?? '';
                if (productId.isEmpty) {
                  final index = uri.pathSegments.indexOf('share-product');
                  if (index != -1 && uri.pathSegments.length > index + 1) {
                    productId = uri.pathSegments[index + 1];
                  }
                }
                if (productId.isNotEmpty) {
                  return route(ProductDetailScreen(productId: productId));
                }
              }
            } catch (_) {
              // Ignore parsing errors and fall back to standard switch
            }
          }

          switch (settings.name) {
            case '/splash':
              return route(const SplashScreen());
            case '/':
            case '/get-started':
            case '/login':
              return route(const LoginScreen());
            case '/forgot-password':
              return route(const ForgotPasswordScreen());
            case '/reset-password':
              return route(const ResetPasswordScreen());
            case '/suspended':
              return route(const SuspendedScreen());
            case '/clips':
              return route(const VideoFeedScreen());
            case '/home':
              return route(const HomeScreen());
            case '/explore':
              final categoryId = settings.arguments as String?;
              return route(ExploreScreen(initialCategoryId: categoryId));
            case '/search':
              return route(const SearchScreen());
            case '/cart':
              return route(const CartScreen());
            case '/checkout':
              final args = settings.arguments;
              Product? buyNowProduct;
              if (args is Map<String, dynamic>) {
                buyNowProduct = args['product'] as Product?;
              } else if (args is Product) {
                buyNowProduct = args;
              }
              return route(
                CheckoutScreen(
                  buyNowProduct: buyNowProduct,
                ),
              );
            case '/wallet':
              return route(const WalletScreen());
            case '/orders':
              return route(const OrdersScreen());
            case '/messages':
              return route(const MessagesScreen());
            case '/services':
              return route(const ServicesScreen());
            case '/wishlist':
              return route(const WishlistScreen());
            case '/notifications':
              return route(const NotificationsScreen());
            case '/account':
              return route(const AccountSettingsScreen());
            case '/sell':
              return route(const SellScreen());
            case '/curated-collection':
              final collectionId = settings.arguments as String;
              return route(CuratedCollectionScreen(collectionId: collectionId));

            // ── Deferred routes: loaded on first visit ──

            case '/about':
              return route(
                _DeferredLoader(
                  loadLibrary: deferred_about.loadLibrary,
                  builder: () => deferred_about.AboutScreen(),
                ),
              );
            case '/privacy-policy':
              return route(
                _DeferredLoader(
                  loadLibrary: deferred_policy.loadLibrary,
                  builder: () => deferred_policy.PolicyViewScreen(
                    policyType: 'privacy_policy',
                    title: 'Privacy Policy',
                  ),
                ),
              );
            case '/terms-conditions':
              return route(
                _DeferredLoader(
                  loadLibrary: deferred_policy.loadLibrary,
                  builder: () => deferred_policy.PolicyViewScreen(
                    policyType: 'terms_conditions',
                    title: 'Terms & Conditions',
                  ),
                ),
              );
            case '/about-legal':
              return route(
                _DeferredLoader(
                  loadLibrary: deferred_about_legal.loadLibrary,
                  builder: () => deferred_about_legal.AboutLegalScreen(),
                ),
              );
            case '/faq':
              return route(
                _DeferredLoader(
                  loadLibrary: deferred_faq.loadLibrary,
                  builder: () => deferred_faq.FaqScreen(),
                ),
              );
            case '/seller-dashboard':
              return route(const SellerDashboardScreen());
            case '/seller-reviews':
              return route(const SellerReviewsScreen());
            case '/seller-analytics':
              return route(
                _DeferredLoader(
                  loadLibrary: deferred_analytics.loadLibrary,
                  builder: () => deferred_analytics.SellerAnalyticsScreen(),
                ),
              );
            case '/seller-video-analytics':
              return route(
                _DeferredLoader(
                  loadLibrary: deferred_video_analytics.loadLibrary,
                  builder: () =>
                      deferred_video_analytics.VideoAnalyticsScreen(),
                ),
              );
            case '/product':
              final productId = settings.arguments as String;
              return route(ProductDetailScreen(productId: productId));
            case '/create-listing':
              Product? product;
              String? source;
              if (settings.arguments is Map) {
                final args = settings.arguments as Map;
                product = args['product'] as Product?;
                source = args['source'] as String?;
              } else {
                product = settings.arguments as Product?;
              }
              return route(
                CreateListingScreen(existingProduct: product, source: source),
              );
            case '/profile':
              return route(const ProfileScreen());
            case '/edit-profile':
              return route(const EditProfileScreen());
            case '/following':
              final initialTab = settings.arguments as int? ?? 0;
              return route(FollowingScreen(initialTab: initialTab));
            case '/order-detail':
              final orderId = settings.arguments as String;
              return route(OrderDetailScreen(orderId: orderId));
            case '/seller-verify':
              return route(
                _DeferredLoader(
                  loadLibrary: deferred_seller_verify.loadLibrary,
                  builder: () => deferred_seller_verify.SellerVerifyScreen(),
                ),
              );
            case '/seller-permissions':
              return route(
                _DeferredLoader(
                  loadLibrary: deferred_seller_permissions.loadLibrary,
                  builder: () =>
                      deferred_seller_permissions.SellerPermissionsScreen(),
                ),
              );
            case '/seller-profile-verification':
              return route(
                _DeferredLoader(
                  loadLibrary: deferred_seller_profile_verification.loadLibrary,
                  builder: () =>
                      deferred_seller_profile_verification.SellerProfileVerificationScreen(),
                ),
              );
            case '/business-profile':
              final sellerId = settings.arguments as String;
              return route(BusinessProfileScreen(sellerId: sellerId));
            case '/edit-business-profile':
              final existingProfile = settings.arguments as BusinessProfile?;
              return route(
                _DeferredLoader(
                  loadLibrary: deferred_edit_business.loadLibrary,
                  builder: () =>
                      deferred_edit_business.EditBusinessProfileScreen(
                        existingProfile: existingProfile,
                      ),
                ),
              );
            default:
              return route(const LoginScreen());
          }
        },
      ),
    );
  }
}
