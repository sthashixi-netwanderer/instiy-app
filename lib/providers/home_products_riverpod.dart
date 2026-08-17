import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:instiy/models/product_model.dart';
import 'package:instiy/services/product_repository.dart';
import 'package:instiy/providers/providers.dart';

part 'home_products_riverpod.g.dart';

@riverpod
ProductRepository productRepository(Ref ref) {
  return ProductRepository();
}

@riverpod
class HomeProductsController extends _$HomeProductsController {
  @override
  Stream<List<Product>> build() {
    final repository = ref.watch(productRepositoryProvider);
    final blockProv = ref.watch(blockProvider);
    return repository.watchProducts().map(
      (products) => blockProv.filterProducts(products),
    );
  }
}
