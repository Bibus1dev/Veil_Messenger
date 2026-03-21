// lib/services/secure_screen_service.dart
import 'package:no_screenshot/no_screenshot.dart';

class SecureScreenService {
  static final _noScreenshot = NoScreenshot.instance;
  static bool _isEnabled = false;
  static int _enableCount = 0; // Счётчик вложенных вызовов

  /// Включить защиту от скриншотов
  static Future<void> enable() async {
    _enableCount++;
    
    // Включаем только при первом вызове
    if (_enableCount == 1) {
      try {
        final result = await _noScreenshot.screenshotOff();
        _isEnabled = result;
        print('🔒 Secure screen enabled: $result (count: $_enableCount)');
      } catch (e) {
        print('❌ Failed to enable secure screen: $e');
        _enableCount--; // Откатываем счётчик при ошибке
      }
    } else {
      print('🔒 Secure screen already enabled (count: $_enableCount)');
    }
  }

  /// Отключить защиту
  static Future<void> disable() async {
    if (_enableCount <= 0) return;
    
    _enableCount--;
    
    // Отключаем только когда счётчик достигает 0
    if (_enableCount == 0 && _isEnabled) {
      try {
        final result = await _noScreenshot.screenshotOn();
        _isEnabled = !result;
        print('🔓 Secure screen disabled: $result');
      } catch (e) {
        print('❌ Failed to disable secure screen: $e');
      }
    } else {
      print('🔒 Secure screen still enabled (count: $_enableCount)');
    }
  }

  /// Принудительно отключить (для emergency)
  static Future<void> forceDisable() async {
    _enableCount = 0;
    if (_isEnabled) {
      try {
        final result = await _noScreenshot.screenshotOn();
        _isEnabled = !result;
        print('🔓 Secure screen force disabled');
      } catch (e) {
        print('❌ Failed to force disable: $e');
      }
    }
  }

  static bool get isEnabled => _isEnabled;
  static int get enableCount => _enableCount;
}