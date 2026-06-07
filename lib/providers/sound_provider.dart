import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoundOption {
  final String id;
  final String label;
  final String assetPath;
  final IconData icon;

  const SoundOption({
    required this.id,
    required this.label,
    required this.assetPath,
    required this.icon,
  });
}

class SoundProvider extends ChangeNotifier {
  static const String _selectedSoundKey = 'selected_notification_sound';
  static const String _soundEnabledKey = 'notification_sound_enabled';
  final AudioPlayer _player = AudioPlayer();

  String _selectedSoundId = 'notification_alert';
  bool _isSoundEnabled = true;
  bool _isInitialized = false;

  String get selectedSoundId => _selectedSoundId;
  bool get isSoundEnabled => _isSoundEnabled;
  bool get isInitialized => _isInitialized;

  static const List<SoundOption> availableSounds = [
    SoundOption(
      id: 'notification_alert',
      label: 'Notification Alert',
      assetPath: 'assets/sounds/notification_alert.mp3',
      icon: Icons.notifications_active,
    ),
    SoundOption(
      id: 'new_message',
      label: 'New Message',
      assetPath: 'assets/sounds/new_message.mp3',
      icon: Icons.message,
    ),
    SoundOption(
      id: 'in_chat_message',
      label: 'Chat Message',
      assetPath: 'assets/sounds/in_chat_message.mp3',
      icon: Icons.chat,
    ),
    SoundOption(
      id: 'slack_message',
      label: 'Soft Alert',
      assetPath: 'assets/sounds/slack_message.mp3',
      icon: Icons.notifications,
    ),
    SoundOption(
      id: 'windows_notification',
      label: 'Windows Note',
      assetPath: 'assets/sounds/windows_notification.mp3',
      icon: Icons.desktop_windows,
    ),
    SoundOption(
      id: 'telegram_notification',
      label: 'Telegram',
      assetPath: 'assets/sounds/telegram_notification.mp3',
      icon: Icons.telegram,
    ),
    SoundOption(
      id: 'discord_notification',
      label: 'Discord',
      assetPath: 'assets/sounds/discord_notification.mp3',
      icon: Icons.headset,
    ),
    SoundOption(
      id: 'pixel_notification',
      label: 'Pixel',
      assetPath: 'assets/sounds/pixel_notification.mp3',
      icon: Icons.smartphone,
    ),
  ];

  SoundOption get selectedSound {
    return availableSounds.firstWhere(
      (s) => s.id == _selectedSoundId,
      orElse: () => availableSounds.first,
    );
  }

  Future<void> initialize() async {
    if (_isInitialized) return;
    final prefs = await SharedPreferences.getInstance();
    _selectedSoundId = prefs.getString(_selectedSoundKey) ?? 'notification_alert';
    _isSoundEnabled = prefs.getBool(_soundEnabledKey) ?? true;
    _isInitialized = true;
    notifyListeners();
  }

  Future<void> setSelectedSound(String id) async {
    _selectedSoundId = id;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_selectedSoundKey, id);
    notifyListeners();
  }

  Future<void> setSoundEnabled(bool enabled) async {
    _isSoundEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_soundEnabledKey, enabled);
    notifyListeners();
  }

  Future<void> playSound(String? soundId) async {
    if (!_isSoundEnabled) return;

    final id = soundId ?? _selectedSoundId;
    try {
      final option = availableSounds.firstWhere((s) => s.id == id);
      await _player.stop();
      await _player.play(AssetSource(option.assetPath.replaceFirst('assets/', '')));
    } catch (_) {}
  }

  Future<void> previewSound(String id) async {
    try {
      final option = availableSounds.firstWhere((s) => s.id == id);
      await _player.stop();
      await _player.play(AssetSource(option.assetPath.replaceFirst('assets/', '')));
    } catch (_) {}
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
