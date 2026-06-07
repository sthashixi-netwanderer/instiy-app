import 'supabase_service.dart';
import '../models/service_model.dart';

class ServiceService {
  static Future<List<Service>> getServices({
    String? category,
    String? searchQuery,
    List<String>? institutionCodes,
  }) async {
    final supabase = SupabaseService.instance;
    var query = supabase
        .from('services')
        .select('''
          *,
          profiles:users!services_provider_id_fkey(full_name, avatar_url)
        ''');

    if (category != null) {
      query = query.eq('category', category);
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      query = query.or(
        'title.ilike.%$searchQuery%,description.ilike.%$searchQuery%',
      );
    }

    final response = await query.order('created_at', ascending: false);

    return response.map((json) {
      final profile = json['profiles'] as Map<String, dynamic>?;
      return Service(
        id: json['id'] as String,
        providerId: json['provider_id'] as String,
        providerName: profile?['full_name'] as String?,
        providerAvatar: profile?['avatar_url'] as String?,
        title: json['title'] as String,
        description: json['description'] as String?,
        category: json['category'] as String?,
        price: (json['price'] as num).toDouble(),
        priceType: json['price_type'] as String?,
        imageUrls: (json['image_urls'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        institutionCodes: (json['institution_codes'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            [],
        status: json['status'] as String?,
        averageRating: (json['average_rating'] as num?)?.toDouble(),
        reviewCount: (json['review_count'] as num?)?.toInt(),
        createdAt: DateTime.parse(json['created_at'] as String),
      );
    }).toList();
  }

  static Future<Service?> getService(String serviceId) async {
    final supabase = SupabaseService.instance;

    final response = await supabase
        .from('services')
        .select('''
          *,
          profiles:users!services_provider_id_fkey(full_name, avatar_url)
        ''')
        .eq('id', serviceId)
        .maybeSingle();

    if (response == null) return null;

    final profile = response['profiles'] as Map<String, dynamic>?;
    return Service(
      id: response['id'] as String,
      providerId: response['provider_id'] as String,
      providerName: profile?['full_name'] as String?,
      providerAvatar: profile?['avatar_url'] as String?,
      title: response['title'] as String,
      description: response['description'] as String?,
      category: response['category'] as String?,
      price: (response['price'] as num).toDouble(),
      priceType: response['price_type'] as String?,
      imageUrls: (response['image_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      institutionCodes: (response['institution_codes'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      status: response['status'] as String?,
      averageRating: (response['average_rating'] as num?)?.toDouble(),
      reviewCount: (response['review_count'] as num?)?.toInt(),
      createdAt: DateTime.parse(response['created_at'] as String),
    );
  }
}
