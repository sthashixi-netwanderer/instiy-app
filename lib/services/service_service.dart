import 'supabase_service.dart';
import 'storage_service.dart';
import '../models/service_model.dart';
import '../models/category_model.dart';

/// Supabase access for the services marketplace: browse queries embed the
/// provider, category and pricing packages; writes are owner-scoped and
/// enforced by RLS.
class ServiceService {
  static const _select = '''
    *,
    provider:users!services_provider_id_fkey(full_name, avatar_url),
    category:categories(name, slug),
    packages:service_packages(*)
  ''';

  /// Browse published services. Signed-out friendly (public read policy).
  static Future<List<Service>> getServices({
    String? categoryId,
    String? searchQuery,
    String? providerId,
    List<ServiceStatus>? statuses,
    String? tag,
    int? limit,
    int? offset,
  }) async {
    var query = SupabaseService.table('services').select(_select);

    if (providerId != null) {
      query = query.eq('provider_id', providerId);
    } else if (statuses == null) {
      // Browse defaults to published listings only.
      query = query.eq('status', 'active');
    }
    if (statuses != null && statuses.isNotEmpty) {
      query = query.inFilter(
        'status',
        statuses.map((s) => s.name).toList(),
      );
    }
    if (categoryId != null) {
      query = query.eq('category_id', categoryId);
    }
    if (tag != null && tag.isNotEmpty) {
      query = query.contains('search_tags', [tag]);
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      query = query.or(
        'title.ilike.%$searchQuery%,description.ilike.%$searchQuery%',
      );
    }

    final ordered = query.order('created_at', ascending: false);
    final response = limit != null
        ? await ordered.range(offset ?? 0, (offset ?? 0) + limit - 1)
        : await ordered;
    return response
        .map<Service>((row) => Service.fromJson(row))
        .toList();
  }

  static Future<Service?> getService(String serviceId) async {
    final response = await SupabaseService.table('services')
        .select(_select)
        .eq('id', serviceId)
        .maybeSingle();
    if (response == null) return null;
    return Service.fromJson(response);
  }

  /// All listings of the current user (any status) — the "My Services"
  /// dashboard inside the Services screen.
  static Future<List<Service>> getMyServices() async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return [];
    return getServices(providerId: userId, statuses: ServiceStatus.values);
  }

  /// Whether the current user has opted in as a service provider.
  static Future<bool> isServiceProvider() async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) return false;
    final row = await SupabaseService.table('users')
        .select('is_service_provider')
        .eq('id', userId)
        .maybeSingle();
    return row?['is_service_provider'] == true;
  }

  /// One-way opt-in executed from the Services screen only.
  static Future<void> becomeServiceProvider() async {
    await SupabaseService.client.rpc('become_service_provider');
  }

  static Future<List<Category>> getServiceCategories() async {
    final response = await SupabaseService.table('categories')
        .select()
        .eq('type', 'service')
        .order('name');
    return response
        .map<Category>((row) => Category.fromJson(row))
        .toList();
  }

  /// Uploads gallery images to R2 under the services folder.
  static Future<List<String>> uploadServiceImages(
    List<dynamic> images,
  ) async {
    final urls = <String>[];
    for (final image in images) {
      final url = await StorageService.uploadImage(file: image, folder: 'services');
      urls.add(url);
    }
    return urls;
  }

  static Future<Service> createService({
    required String title,
    required String description,
    required String categoryId,
    required String categoryName,
    required double price,
    String priceType = 'fixed',
    int? deliveryDays,
    List<String> imageUrls = const [],
    List<String> searchTags = const [],
    List<ServicePackage> packages = const [],
  }) async {
    final userId = SupabaseService.auth.currentUser?.id;
    if (userId == null) throw Exception('Not authenticated');

    final inserted = await SupabaseService.table('services').insert({
      'provider_id': userId,
      'title': title,
      'description': description,
      'category': categoryName,
      'category_id': categoryId,
      'price': price,
      'price_type': priceType,
      'delivery_days': deliveryDays,
      'image_urls': imageUrls,
      'search_tags': searchTags,
      'status': ServiceStatus.active.name,
    }).select('id').single();

    final serviceId = inserted['id'] as String;
    await _savePackages(serviceId, packages);

    final created = await getService(serviceId);
    return created ??
        Service(
          id: serviceId,
          providerId: userId,
          title: title,
          description: description,
          categoryId: categoryId,
          categoryName: categoryName,
          price: price,
          imageUrls: imageUrls,
          searchTags: searchTags,
          createdAt: DateTime.now(),
          packages: packages
              .map((p) => p.copyWith(serviceId: serviceId))
              .toList(),
        );
  }

  static Future<void> updateService(
    String serviceId, {
    required String title,
    required String description,
    required String categoryId,
    required String categoryName,
    required double price,
    String priceType = 'fixed',
    int? deliveryDays,
    List<String> imageUrls = const [],
    List<String> searchTags = const [],
    List<ServicePackage> packages = const [],
  }) async {
    await SupabaseService.table('services').update({
      'title': title,
      'description': description,
      'category': categoryName,
      'category_id': categoryId,
      'price': price,
      'price_type': priceType,
      'delivery_days': deliveryDays,
      'image_urls': imageUrls,
      'search_tags': searchTags,
    }).eq('id', serviceId);

    await _savePackages(serviceId, packages);
  }

  /// Pause (hide from browse) or re-publish a listing.
  static Future<void> setServiceStatus(
    String serviceId,
    ServiceStatus status,
  ) async {
    await SupabaseService.table('services')
        .update({'status': status.name})
        .eq('id', serviceId);
  }

  static Future<void> deleteService(String serviceId) async {
    await SupabaseService.table('services').delete().eq('id', serviceId);
  }

  /// Replace-then-insert package rows (same pattern as product institution
  /// fees). The price-sync trigger refreshes the service's starting price.
  static Future<void> _savePackages(
    String serviceId,
    List<ServicePackage> packages,
  ) async {
    await SupabaseService.table('service_packages')
        .delete()
        .eq('service_id', serviceId);
    if (packages.isEmpty) return;
    await SupabaseService.table('service_packages').insert(
      packages
          .map((p) => p.toJson(serviceId: serviceId))
          .toList(),
    );
  }
}
