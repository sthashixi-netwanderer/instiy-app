class Category {
  final String id;
  final String name;
  final String? icon;
  final int colorIndex;
  final String type;
  final String? imageUrl;
  final String? slug;
  final DateTime createdAt;

  Category({
    required this.id,
    required this.name,
    this.icon,
    required this.colorIndex,
    this.type = 'product',
    this.imageUrl,
    this.slug,
    required this.createdAt,
  });

  factory Category.fromJson(Map<String, dynamic> json) {
    return Category(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      colorIndex: json['color_index'] as int? ?? 0,
      type: json['type'] as String? ?? 'product',
      imageUrl: json['image_url'] as String?,
      slug: json['slug'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'color_index': colorIndex,
      'type': type,
      'image_url': imageUrl,
      'slug': slug,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
