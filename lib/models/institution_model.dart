class Institution {
  final String id;
  final String code;
  final String name;
  final String? logoUrl;
  final String? location;
  final String? url;
  final String? region;
  final int productCount;

  Institution({
    required this.id,
    required this.code,
    required this.name,
    this.logoUrl,
    this.location,
    this.url,
    this.region,
    this.productCount = 0,
  });

  factory Institution.fromJson(Map<String, dynamic> json) {
    return Institution(
      id: json['id'] as String,
      code: json['code'] as String,
      name: json['name'] as String,
      logoUrl: json['logo_url'] as String?,
      location: json['location'] as String?,
      url: json['url'] as String?,
      region: json['region'] as String?,
      productCount: (json['product_count'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'logo_url': logoUrl,
      'location': location,
      'url': url,
      'region': region,
    };
  }
}
