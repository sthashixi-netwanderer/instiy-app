import '../models/carousel_slide_model.dart';
import '../models/product_model.dart';
import 'supabase_service.dart';

class CarouselService {
  /// Fetch all visible carousel slides for the home screen
  static Future<List<CarouselSlide>> getVisibleSlides() async {
    final response = await SupabaseService.table('carousel_slides')
        .select()
        .eq('is_visible', true)
        .order('sort_order', ascending: true);

    return (response as List)
        .map((row) => CarouselSlide.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Fetch product data for slides that link to products
  static Future<Map<String, Product>> getLinkedProducts(List<CarouselSlide> slides) async {
    final productIds = slides
        .where((s) => s.buttonLinkType == 'product' && s.buttonLinkValue != null)
        .map((s) => s.buttonLinkValue!)
        .toSet()
        .toList();

    if (productIds.isEmpty) return {};

    final response = await SupabaseService.table('products')
        .select('id, seller_id, title, description, price, discount_percent, discount_start_date, discount_end_date, thumbnail_url, image_urls, created_at, updated_at')
        .inFilter('id', productIds);

    final map = <String, Product>{};
    for (final row in response as List) {
      final product = Product.fromJson(row as Map<String, dynamic>);
      map[product.id] = product;
    }
    return map;
  }
}
