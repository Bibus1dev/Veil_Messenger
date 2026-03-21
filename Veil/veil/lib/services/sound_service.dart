import 'dart:math';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _sendPlayer = AudioPlayer();
  final AudioPlayer _receivePlayer = AudioPlayer();
  final Random _random = Random();

  bool _initialized = false;
  bool _enabled = true;

  // Пути к звукам
  final List<String> _sendSounds = [
    'assets/MessageSounds/SendingMessage_1.mp3',
    'assets/MessageSounds/SendingMessage_2.mp3',
  ];

  final List<String> _receiveSounds = [
    'assets/MessageSounds/ReceivingMessage_1.mp3',
    'assets/MessageSounds/ReceivingMessage_2.mp3',
    'assets/MessageSounds/ReceivingMessage_3.mp3',
  ];

  Future<void> init() async {
    if (_initialized) return;
    
    // Проверяем существование файлов
    try {
      await rootBundle.load(_sendSounds[0]);
      await rootBundle.load(_receiveSounds[0]);
      _initialized = true;
      print('🔊 SoundService initialized');
    } catch (e) {
      print('⚠️ Sound files not found: $e');
      _enabled = false;
    }
  }

  void setEnabled(bool enabled) {
    _enabled = enabled;
  }

  Future<void> playSendSound() async {
    if (!_enabled || !_initialized) return;
    
    try {
      final soundPath = _sendSounds[_random.nextInt(_sendSounds.length)];
      await _sendPlayer.setAsset(soundPath);
      await _sendPlayer.play();
    } catch (e) {
      print('❌ Error playing send sound: $e');
    }
  }

  Future<void> playReceiveSound() async {
    if (!_enabled || !_initialized) return;
    
    try {
      final soundPath = _receiveSounds[_random.nextInt(_receiveSounds.length)];
      await _receivePlayer.setAsset(soundPath);
      await _receivePlayer.play();
    } catch (e) {
      print('❌ Error playing receive sound: $e');
    }
  }

  void dispose() {
    _sendPlayer.dispose();
    _receivePlayer.dispose();
  }
}