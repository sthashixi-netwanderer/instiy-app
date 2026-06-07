class CarouselSlide {
  final String id;
  final String mediaUrl;
  final String mediaType; // 'image', 'video', 'gif'
  final String? thumbnailUrl;
  final String? title;
  final String? subtitle;
  final String? buttonText;
  final String? buttonLinkType; // 'product', 'category', 'url'
  final String? buttonLinkValue;
  final bool isVisible;
  final int sortOrder;

  CarouselSlide({
    required this.id,
    required this.mediaUrl,
    required this.mediaType,
    this.thumbnailUrl,
    this.title,
    this.subtitle,
    this.buttonText,
    this.buttonLinkType,
    this.buttonLinkValue,
    this.isVisible = true,
    this.sortOrder = 0,
  });

  factory CarouselSlide.fromJson(Map<String, dynamic> json) {
    return CarouselSlide(
      id: json['id'] as String,
      mediaUrl: json['media_url'] as String,
      mediaType: json['media_type'] as String? ?? 'image',
      thumbnailUrl: json['thumbnail_url'] as String?,
      title: json['title'] as String?,
      subtitle: json['subtitle'] as String?,
      buttonText: json['button_text'] as String?,
      buttonLinkType: json['button_link_type'] as String?,
      buttonLinkValue: json['button_link_value'] as String?,
      isVisible: json['is_visible'] as bool? ?? true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isVideo => mediaType == 'video';
  bool get isGif => mediaType == 'gif';
  bool get isImage => mediaType == 'image';
  bool get hasOverlay => title != null || subtitle != null;
  bool get hasButton => buttonText != null && buttonText!.isNotEmpty;
}
