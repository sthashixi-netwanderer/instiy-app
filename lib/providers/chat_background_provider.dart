import 'package:flutter/material.dart';
import '../models/chat_background_model.dart';
import '../services/chat_background_service.dart';

class ChatBackgroundProvider extends ChangeNotifier {
  ChatBackground? _background;
  bool _isLoading = false;

  ChatBackground? get background => _background;
  bool get isLoading => _isLoading;

  Future<void> loadBackground(String userId, String? conversationId) async {
    _isLoading = true;
    _background = null;
    notifyListeners();
    
    try {
      _background = await ChatBackgroundService.getBackground(userId, conversationId);
    } catch (e) {
      debugPrint('Error loading chat background: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> setBackground({
    required String userId,
    String? conversationId,
    required String backgroundType,
    String? gradientName,
    String? sourceImagePath,
    required double blurIntensity,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      _background = await ChatBackgroundService.saveBackground(
        userId: userId,
        conversationId: conversationId,
        backgroundType: backgroundType,
        gradientName: gradientName,
        sourceImagePath: sourceImagePath,
        blurIntensity: blurIntensity,
      );
    } catch (e) {
      debugPrint('Error saving chat background: $e');
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
