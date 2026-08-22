class ChatBackground {
  final String id;
  final String userId;
  final String? conversationId;
  final String backgroundType; // 'none', 'gradient', 'image'
  final String? gradientName;
  /// Local cached copy of the custom background image in the app's
  /// documents directory. Used for fast/offline rendering; the canonical
  /// copy lives in R2 storage ([imageUrl]).
  final String? localImagePath;
  /// Public R2 URL of the custom background image. Persisted in the
  /// chat_backgrounds table so the setting survives reinstalls, app-data
  /// clears and new devices.
  final String? imageUrl;
  final double blurIntensity;

  ChatBackground({
    required this.id,
    required this.userId,
    this.conversationId,
    required this.backgroundType,
    this.gradientName,
    this.localImagePath,
    this.imageUrl,
    this.blurIntensity = 0.0,
  });

  factory ChatBackground.fromJson(Map<String, dynamic> json) {
    return ChatBackground(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      conversationId: json['conversation_id'] as String?,
      backgroundType: json['background_type'] as String? ?? 'none',
      gradientName: json['gradient_name'] as String?,
      localImagePath: json['local_image_path'] as String?,
      imageUrl: json['image_url'] as String?,
      blurIntensity: (json['blur_intensity'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'conversation_id': conversationId,
      'background_type': backgroundType,
      'gradient_name': gradientName,
      'local_image_path': localImagePath,
      'image_url': imageUrl,
      'blur_intensity': blurIntensity,
    };
  }
}
