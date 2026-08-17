class ChatBackground {
  final String id;
  final String userId;
  final String? conversationId;
  final String backgroundType; // 'none', 'gradient', 'image'
  final String? gradientName;
  /// Local file path to the custom background image stored in the app's
  /// documents directory. This is intentionally NOT uploaded to the cloud —
  /// it is cleared when the user clears the app data.
  final String? localImagePath;
  final double blurIntensity;

  ChatBackground({
    required this.id,
    required this.userId,
    this.conversationId,
    required this.backgroundType,
    this.gradientName,
    this.localImagePath,
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
      'blur_intensity': blurIntensity,
    };
  }

  ChatBackground copyWith({
    String? backgroundType,
    String? gradientName,
    String? localImagePath,
    double? blurIntensity,
  }) {
    return ChatBackground(
      id: id,
      userId: userId,
      conversationId: conversationId,
      backgroundType: backgroundType ?? this.backgroundType,
      gradientName: gradientName ?? this.gradientName,
      localImagePath: localImagePath ?? this.localImagePath,
      blurIntensity: blurIntensity ?? this.blurIntensity,
    );
  }
}
