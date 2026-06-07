import 'package:audioplayers/audioplayers.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoundService {
  static const String _selectedSoundKey = 'selected_notification_sound';
  static const String _soundEnabledKey = 'notification_sound_enabled';
  static final AudioPlayer _player = AudioPlayer();

  static const Map<String, String> availableSounds = {
    'notification_alert': 'assets/sounds/notification_alert.mp3',
    'new_message': 'assets/sounds/new_message.mp3',
    'in_chat_message': 'assets/sounds/in_chat_message.mp3',
    'slack_message': 'assets/sounds/slack_message.mp3',
    'windows_notification': 'assets/sounds/windows_notification.mp3',
    'telegram_notification': 'assets/sounds/telegram_notification.mp3',
    'discord_notification': 'assets/sounds/discord_notification.mp3',
    'pixel_notification': 'assets/sounds/pixel_notification.mp3',
  };

  static Future<bool> _isSoundEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_soundEnabledKey) ?? true;
  }

  static Future<String> _getSelectedSoundId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_selectedSoundKey) ?? 'notification_alert';
  }

  static Future<void> playNotificationSound() async {
    final enabled = await _isSoundEnabled();
    if (!enabled) return;

    try {
      final soundId = await _getSelectedSoundId();
      final path = availableSounds[soundId] ?? availableSounds.values.first;
      final assetSource = AssetSource(path.replaceFirst('assets/', ''));
      await _player.stop();
      await _player.play(assetSource);
    } catch (_) {}
  }

  static Future<void> playSoundForType(String type) async {
    final enabled = await _isSoundEnabled();
    if (!enabled) return;

    String soundId;
    switch (type) {
      case 'message':
      case 'new_message':
        soundId = 'new_message';
        break;
      case 'in_chat_message':
        soundId = 'in_chat_message';
        break;
      default:
        soundId = await _getSelectedSoundId();
    }

    try {
      final path = availableSounds[soundId] ?? availableSounds.values.first;
      final assetSource = AssetSource(path.replaceFirst('assets/', ''));
      await _player.stop();
      await _player.play(assetSource);
    } catch (_) {}
  }
}
