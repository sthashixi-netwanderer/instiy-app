import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_ui/shadcn_ui.dart';
import 'config/app_config.dart';
import 'config/app_theme.dart';
import 'services/navigation_service.dart';
import 'services/supabase_service.dart';
import 'services/secrets_service.dart';
import 'services/local_notification_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'models/product_model.dart';
import 'models/business_profile_model.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/reset_password_screen.dart';
import 'screens/explore/explore_screen.dart';
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
import 'screens/info/about_screen.dart';
import 'screens/info/faq_screen.dart';
import 'screens/info/about_legal_screen.dart';
import 'screens/product/product_detail_screen.dart';
import 'screens/product/create_listing_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/profile/edit_profile_screen.dart';
import 'screens/seller/dashboard_screen.dart';
import 'screens/seller/reviews_screen.dart';
import 'screens/seller/analytics_screen.dart';
import 'screens/seller/video_analytics_screen.dart';
import 'screens/seller/seller_verify_screen.dart';
import 'screens/seller/seller_profile_verification_screen.dart';
import 'screens/seller/business_profile_screen.dart';
import 'screens/seller/edit_business_profile_screen.dart';
import 'screens/orders/order_detail_screen.dart';
import 'screens/legal/policy_view_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Parallelize independent initializations to reduce cold-start time.
  // Supabase (network), Local Notifications (plugin), and Firebase (SDK)
  // are independent of each other, so they can init concurrently.
  await Future.wait([
    SupabaseService.initialize(),
    if (!kIsWeb) LocalNotificationService.initialize(),
    if (!kIsWeb) Firebase.initializeApp(),
  ]);

  // Fetch app secrets after Supabase is initialized but before any service
  // that depends on them (R2, Hubtel, Paystack, Giphy) is called.
  await SecretsService.instance.initialize();

  runApp(const InstiyApp());

  // Defer non-critical FCM setup to after the first frame renders.
  // These are not needed for the splash-to-first-frame transition and
  // blocking on them (especially getInitialMessage()) delays the UI.
  try {
    if (!kIsWeb) {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      LocalNotificationService.setupFcmListeners();
    }
  } catch (e) {
    debugPrint('Firebase background push initialization skipped or failed: $e');
  }
}

class InstiyApp extends StatefulWidget {
  const InstiyApp({super.key});

  @override
  State<InstiyApp> createState() => _InstiyAppState();
}

class _InstiyAppState extends State<InstiyApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinking();
  }

  void _initDeepLinking() {
    _appLinks = AppLinks();

    // Handle incoming links when app is in foreground / background
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('Failed to receive deep link: $err');
      },
    );

    // Also check for initial link if app was opened by a link
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        _handleDeepLink(uri);
      }
    }).catchError((err) {
      debugPrint('Failed to get initial deep link: $err');
    });
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('Received deep link: $uri');
    if (uri.scheme == 'io.supabase.instiy' && uri.host == 'store') {
      final sellerId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
      if (sellerId.isNotEmpty) {
        NavigationService.navigatorKey.currentState?.pushNamed(
          '/business-profile',
          arguments: sellerId,
        );
      }
    } else if (uri.path.startsWith('/store/')) {
      final sellerId = uri.pathSegments.length > 1 ? uri.pathSegments[1] : '';
      if (sellerId.isNotEmpty) {
        NavigationService.navigatorKey.currentState?.pushNamed(
          '/business-profile',
          arguments: sellerId,
        );
      }
    }
  }

  @override
  void dispose() {
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
        initialRoute: '/home',
        onGenerateRoute: (settings) {
          // Helper to wrap all routes with smooth fade+slide transition
          Route<T> route<T>(Widget page) => AppTheme.fadeSlideRoute<T>(page);

          final name = settings.name ?? '';
          if (name.isNotEmpty) {
            try {
              final uri = Uri.parse(name);
              // Handle deep link io.supabase.instiy://store/<sellerId>
              if (uri.scheme == 'io.supabase.instiy' && uri.host == 'store') {
                final sellerId = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : '';
                if (sellerId.isNotEmpty) {
                  return route(BusinessProfileScreen(sellerId: sellerId));
                }
              }
              // Also support path-only formats (like '/store/<sellerId>')
              if (uri.path.startsWith('/store/')) {
                final sellerId = uri.pathSegments.length > 1 ? uri.pathSegments[1] : '';
                if (sellerId.isNotEmpty) {
                  return route(BusinessProfileScreen(sellerId: sellerId));
                }
              }
            } catch (_) {
              // Ignore parsing errors and fall back to standard switch
            }
          }

          switch (settings.name) {
            case '/':
            case '/get-started':
            case '/login':
              return route(const LoginScreen());
            case '/forgot-password':
              return route(const ForgotPasswordScreen());
            case '/reset-password':
              return route(const ResetPasswordScreen());
            case '/clips':
              return route(const VideoFeedScreen());
            case '/home':
              return route(const HomeScreen());
            case '/explore':
              final categoryId = settings.arguments as String?;
              return route(ExploreScreen(initialCategoryId: categoryId));
            case '/cart':
              return route(const CartScreen());
            case '/checkout':
              final buyNowProduct = settings.arguments as Product?;
              return route(CheckoutScreen(buyNowProduct: buyNowProduct));
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
            case '/about':
              return route(const AboutScreen());
            case '/privacy-policy':
              return route(const PolicyViewScreen(
                policyType: 'privacy_policy',
                title: 'Privacy Policy',
              ));
            case '/terms-conditions':
              return route(const PolicyViewScreen(
                policyType: 'terms_conditions',
                title: 'Terms & Conditions',
              ));
            case '/about-legal':
              return route(const AboutLegalScreen());
            case '/faq':
              return route(const FaqScreen());
            case '/seller-dashboard':
              return route(const SellerDashboardScreen());
            case '/seller-reviews':
              return route(const SellerReviewsScreen());
            case '/seller-analytics':
              return route(const SellerAnalyticsScreen());
            case '/seller-video-analytics':
              return route(const VideoAnalyticsScreen());
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
              return route(CreateListingScreen(
                existingProduct: product,
                source: source,
              ));
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
              return route(const SellerVerifyScreen());
            case '/seller-profile-verification':
              return route(const SellerProfileVerificationScreen());
            case '/business-profile':
              final sellerId = settings.arguments as String;
              return route(BusinessProfileScreen(sellerId: sellerId));
            case '/edit-business-profile':
              final existingProfile = settings.arguments as BusinessProfile?;
              return route(EditBusinessProfileScreen(existingProfile: existingProfile));
            default:
              return route(const LoginScreen());
          }
        },
      ),
    );
  }
}
