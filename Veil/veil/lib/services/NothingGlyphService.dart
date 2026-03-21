import 'dart:io';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:nothing_glyph_interface/nothing_glyph_interface.dart';

enum NothingPhoneModel {
  phone2a,     // is23111() - 3 полоски
  phone3a,     // is24111() - 3 полоски (твой)
  unsupported,
}

class GlyphConfig {
  final int zoneCount;
  final List<String> zoneNames;
  final Map<String, int> zoneMapping;

  GlyphConfig({
    required this.zoneCount,
    required this.zoneNames,
    required this.zoneMapping,
  });
}

// Только 3 полоски для 3a и 2a
final Map<NothingPhoneModel, GlyphConfig> kGlyphConfigs = {
  NothingPhoneModel.phone3a: GlyphConfig(
    zoneCount: 3,
    zoneNames: ['left', 'center', 'right'],
    zoneMapping: {
      'all': -1,
      'left': 0, 'center': 1, 'right': 2,
    },
  ),
  
  NothingPhoneModel.phone2a: GlyphConfig(
    zoneCount: 3,
    zoneNames: ['left', 'center', 'right'],
    zoneMapping: {
      'all': -1,
      'left': 0, 'center': 1, 'right': 2,
    },
  ),
};

class NothingGlyphService {
  static final NothingGlyphService _instance = NothingGlyphService._internal();
  factory NothingGlyphService() => _instance;
  NothingGlyphService._internal();

  final NothingGlyphInterface _glyphInterface = NothingGlyphInterface();
  
  NothingPhoneModel? _detectedModel;
  GlyphConfig? _config;
  bool _isInitialized = false;
  bool _isAvailable = false;
  bool _isConnected = false;

  NothingPhoneModel? get detectedModel => _detectedModel;
  GlyphConfig? get config => _config;
  bool get isAvailable => _isAvailable;
  bool get isInitialized => _isInitialized;
  bool get isConnected => _isConnected;

  Future<void> initialize() async {
    if (_isInitialized) return;
    
    try {
      // Слушаем подключение к сервису
      _glyphInterface.onServiceConnection.listen((bool connected) {
        print('🔗 Glyph Service Connection: $connected');
        _isConnected = connected;
      });

      // Определяем модель через API плагина
      _detectedModel = await _detectPhoneModel();
      _config = kGlyphConfigs[_detectedModel];
      _isAvailable = _detectedModel != NothingPhoneModel.unsupported;
      
      if (_isAvailable) {
        _isInitialized = true;
        print('✅ Nothing Glyph API initialized for $_detectedModel');
      } else {
        _isInitialized = true;
      }
    } catch (e) {
      print('❌ Glyph service error: $e');
      _detectedModel = NothingPhoneModel.unsupported;
      _isInitialized = true;
    }
  }

  Future<NothingPhoneModel> _detectPhoneModel() async {
    try {
      // Проверяем через API плагина
      final is24111Result = await _glyphInterface.is24111();
      if (is24111Result == true) {
        print('✅ Nothing Phone (3a) - 3 полоски');
        return NothingPhoneModel.phone3a;
      }
      
      final is23111Result = await _glyphInterface.is23111();
      if (is23111Result == true) {
        print('✅ Nothing Phone (2a) - 3 полоски');
        return NothingPhoneModel.phone2a;
      }
      
      // Fallback на device_info если API не сработал
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final model = androidInfo.model?.toLowerCase() ?? '';
      final brand = androidInfo.brand?.toLowerCase() ?? '';
      
      if (brand.contains('nothing') || (androidInfo.manufacturer?.toLowerCase().contains('nothing') ?? false)) {
        if (model.contains('3a')) return NothingPhoneModel.phone3a;
        if (model.contains('2a')) return NothingPhoneModel.phone2a;
        return NothingPhoneModel.phone3a; // default
      }
      
      return NothingPhoneModel.unsupported;
    } catch (e) {
      print('❌ Error detecting via API: $e');
      return NothingPhoneModel.unsupported;
    }
  }

  /// Построить GlyphFrame через Builder
  Future<void> _buildAndToggle({String zone = 'all', int period = 1000, int cycles = 1, int interval = 0}) async {
    if (!_isAvailable || !_isConnected) return;
    
    try {
      final builder = GlyphFrameBuilder();
      
      // Добавляем каналы в зависимости от зоны
      if (zone == 'all') {
        // Все 3 полоски
        builder.buildChannelA().buildChannelB().buildChannelC();
      } else {
        // Конкретная зона
        final zoneValue = _config?.zoneMapping[zone] ?? -1;
        if (zoneValue == 0) builder.buildChannelA();
        if (zoneValue == 1) builder.buildChannelB();
        if (zoneValue == 2) builder.buildChannelC();
      }
      
      // Строим фрейм с параметрами
      final frame = builder
          .buildPeriod(period)
          .buildCycles(cycles)
          .buildInterval(interval)
          .build();
      
      // Отправляем в интерфейс
      await _glyphInterface.buildGlyphFrame(frame);
      
    } catch (e) {
      print('❌ _buildAndToggle error: $e');
    }
  }

  /// Включить глифы
  Future<void> turnOn({String zone = 'all', int brightness = 100}) async {
    if (!_isAvailable) return;
    
    try {
      await _buildAndToggle(zone: zone, period: 1000, cycles: 1);
      await _glyphInterface.toggle();
    } catch (e) {
      print('❌ turnOn error: $e');
    }
  }

  /// Выключить глифы
  Future<void> turnOff() async {
    if (!_isAvailable) return;
    
    try {
      await _glyphInterface.turnOff();
    } catch (e) {
      print('❌ turnOff error: $e');
    }
  }

  /// Мигание
  Future<void> pulse({String zone = 'all', int durationMs = 1000}) async {
    if (!_isAvailable) return;
    
    try {
      await _buildAndToggle(zone: zone, period: durationMs ~/ 2, cycles: 2, interval: 100);
      await _glyphInterface.animate();
    } catch (e) {
      print('❌ pulse error: $e');
    }
  }

  /// Тестовая последовательность
  Future<void> runTestSequence() async {
    if (!_isAvailable || _config == null) return;
    
    print('🔥 Тест глифов для $_detectedModel');
    
    // Последовательно каждая зона
    for (int i = 0; i < _config!.zoneCount; i++) {
      try {
        final zoneName = _config!.zoneNames[i];
        print('  → Testing zone: $zoneName');
        
        await turnOn(zone: zoneName, brightness: 100);
        await Future.delayed(const Duration(milliseconds: 300));
        await turnOff();
        await Future.delayed(const Duration(milliseconds: 100));
      } catch (e) {
        print('⚠️ Zone $i error: $e');
      }
    }
    
    // Все вместе
    try {
      print('  → All zones');
      await turnOn(zone: 'all', brightness: 100);
      await Future.delayed(const Duration(milliseconds: 500));
      await turnOff();
    } catch (e) {
      print('❌ All zones error: $e');
    }
    
    print('✅ Тест завершён');
  }

  Map<String, dynamic> getStatusInfo() {
    return {
      'model': _detectedModel?.toString() ?? 'unknown',
      'available': _isAvailable,
      'initialized': _isInitialized,
      'connected': _isConnected,
      'zoneCount': _config?.zoneCount ?? 0,
      'zoneNames': _config?.zoneNames ?? [],
    };
  }
}