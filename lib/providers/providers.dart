import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/legacy.dart';
export 'package:flutter_riverpod/legacy.dart' show ChangeNotifierProvider;
import 'auth_provider.dart';
import 'product_provider.dart';
import 'cart_provider.dart';
import 'order_provider.dart';
import 'wallet_provider.dart';
import 'message_provider.dart';
import 'seller_provider.dart';
import 'sound_provider.dart';
import 'home_provider.dart';
import 'business_profile_provider.dart';
import 'curated_provider.dart';
import 'carousel_provider.dart';
import 'block_provider.dart';

class ExploreRefreshNotifier extends ChangeNotifier {
  int _state = 0;
  int get state => _state;

  void increment() {
    _state++;
    notifyListeners();
  }
}

final authProvider = ChangeNotifierProvider((ref) => AuthProvider());
final productProvider = ChangeNotifierProvider((ref) => ProductProvider());
final cartProvider = ChangeNotifierProvider((ref) => CartProvider());
final orderProvider = ChangeNotifierProvider((ref) => OrderProvider());
final walletProvider = ChangeNotifierProvider((ref) => WalletProvider());
final messageProvider = ChangeNotifierProvider((ref) => MessageProvider());
final sellerProvider = ChangeNotifierProvider((ref) => SellerProvider());
final soundProvider = ChangeNotifierProvider((ref) => SoundProvider());
final homeProvider = ChangeNotifierProvider((ref) => HomeProvider());
final businessProfileProvider = ChangeNotifierProvider((ref) => BusinessProfileProvider());
final curatedProvider = ChangeNotifierProvider((ref) => CuratedProvider());
final carouselProvider = ChangeNotifierProvider((ref) => CarouselProvider());
final blockProvider = ChangeNotifierProvider((ref) => BlockProvider());
final exploreRefreshProvider = ChangeNotifierProvider<ExploreRefreshNotifier>((ref) => ExploreRefreshNotifier());
