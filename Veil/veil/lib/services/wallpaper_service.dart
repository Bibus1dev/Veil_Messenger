import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';

enum WallpaperType {
  image,
  gradient,
}

class GradientPreset {
  final String name;
  final List<Color> colors;
  final Alignment begin;
  final Alignment end;

  const GradientPreset({
    required this.name,
    required this.colors,
    this.begin = Alignment.topLeft,
    this.end = Alignment.bottomRight,
  });
}

class WallpaperService {
  static final WallpaperService _instance = WallpaperService._internal();
  factory WallpaperService() => _instance;
  WallpaperService._internal();

  static const String _wallpaperTypeKey = 'chat_wallpaper_type';
  static const String _wallpaperPathKey = 'chat_wallpaper_path';
  static const String _wallpaperOpacityKey = 'chat_wallpaper_opacity';
  static const String _wallpaperBlurKey = 'chat_wallpaper_blur';
  
  // Градиент настройки
  static const String _gradientColorsKey = 'chat_gradient_colors';
  static const String _gradientBeginKey = 'chat_gradient_begin';
  static const String _gradientEndKey = 'chat_gradient_end';

  // Готовые градиенты
  final List<GradientPreset> gradientPresets = [
    const GradientPreset(
      name: 'Ocean',
      colors: [Color(0xFF2196F3), Color(0xFF9C27B0)],
    ),
    const GradientPreset(
      name: 'Sunset',
      colors: [Color(0xFFFF5722), Color(0xFFFFC107), Color(0xFF9C27B0)],
    ),
    const GradientPreset(
      name: 'Forest',
      colors: [Color(0xFF4CAF50), Color(0xFF2E7D32)],
    ),
    const GradientPreset(
      name: 'Berry',
      colors: [Color(0xFFE91E63), Color(0xFF9C27B0)],
    ),
    const GradientPreset(
      name: 'Midnight',
      colors: [Color(0xFF1A237E), Color(0xFF311B92), Color(0xFF4A148C)],
    ),
    const GradientPreset(
      name: 'Fire',
      colors: [Color(0xFFFF5722), Color(0xFFFF9800)],
    ),
    const GradientPreset(
      name: 'Aurora',
      colors: [Color(0xFF00BCD4), Color(0xFF4CAF50), Color(0xFF8BC34A)],
    ),
    const GradientPreset(
      name: 'Peach',
      colors: [Color(0xFFFFAB91), Color(0xFFFFCCBC)],
    ),
  ];

  Future<WallpaperType> getWallpaperType() async {
    final prefs = await SharedPreferences.getInstance();
    final typeStr = prefs.getString(_wallpaperTypeKey) ?? 'image';
    return typeStr == 'gradient' ? WallpaperType.gradient : WallpaperType.image;
  }

  Future<String?> getWallpaperPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_wallpaperPathKey);
  }

  Future<List<Color>?> getGradientColors() async {
    final prefs = await SharedPreferences.getInstance();
    final colorsStr = prefs.getStringList(_gradientColorsKey);
    if (colorsStr == null) return null;
    return colorsStr.map((s) => Color(int.parse(s))).toList();
  }

  Future<Alignment> getGradientBegin() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_gradientBeginKey) ?? 'topLeft';
    return _alignmentFromString(val);
  }

  Future<Alignment> getGradientEnd() async {
    final prefs = await SharedPreferences.getInstance();
    final val = prefs.getString(_gradientEndKey) ?? 'bottomRight';
    return _alignmentFromString(val);
  }

  Alignment _alignmentFromString(String s) {
    switch (s) {
      case 'topLeft': return Alignment.topLeft;
      case 'topCenter': return Alignment.topCenter;
      case 'topRight': return Alignment.topRight;
      case 'centerLeft': return Alignment.centerLeft;
      case 'center': return Alignment.center;
      case 'centerRight': return Alignment.centerRight;
      case 'bottomLeft': return Alignment.bottomLeft;
      case 'bottomCenter': return Alignment.bottomCenter;
      case 'bottomRight': return Alignment.bottomRight;
      default: return Alignment.topLeft;
    }
  }

  String _alignmentToString(Alignment a) {
    if (a == Alignment.topLeft) return 'topLeft';
    if (a == Alignment.topCenter) return 'topCenter';
    if (a == Alignment.topRight) return 'topRight';
    if (a == Alignment.centerLeft) return 'centerLeft';
    if (a == Alignment.center) return 'center';
    if (a == Alignment.centerRight) return 'centerRight';
    if (a == Alignment.bottomLeft) return 'bottomLeft';
    if (a == Alignment.bottomCenter) return 'bottomCenter';
    if (a == Alignment.bottomRight) return 'bottomRight';
    return 'topLeft';
  }

  Future<double> getWallpaperOpacity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_wallpaperOpacityKey) ?? 0.5;
  }

  Future<double> getWallpaperBlur() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_wallpaperBlurKey) ?? 0.0;
  }

  Future<void> setImageWallpaper(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wallpaperTypeKey, 'image');
    await prefs.setString(_wallpaperPathKey, path);
  }

  Future<void> setGradientWallpaper(List<Color> colors, Alignment begin, Alignment end) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_wallpaperTypeKey, 'gradient');
    await prefs.setStringList(_gradientColorsKey, colors.map((c) => c.value.toString()).toList());
    await prefs.setString(_gradientBeginKey, _alignmentToString(begin));
    await prefs.setString(_gradientEndKey, _alignmentToString(end));
  }

  Future<void> setWallpaperOpacity(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_wallpaperOpacityKey, value);
  }

  Future<void> setWallpaperBlur(double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_wallpaperBlurKey, value);
  }

  Future<void> removeWallpaper() async {
    final prefs = await SharedPreferences.getInstance();
    
    final path = prefs.getString(_wallpaperPathKey);
    if (path != null) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (e) {
        print('Error deleting wallpaper file: $e');
      }
    }
    
    await prefs.remove(_wallpaperTypeKey);
    await prefs.remove(_wallpaperPathKey);
    await prefs.remove(_gradientColorsKey);
    await prefs.remove(_gradientBeginKey);
    await prefs.remove(_gradientEndKey);
    await prefs.remove(_wallpaperOpacityKey);
    await prefs.remove(_wallpaperBlurKey);
  }

  Future<String?> pickImageFromGallery() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 95,
    );
    
    if (picked != null) {
      final originalFile = File(picked.path);
      final dir = await getApplicationDocumentsDirectory();
      final ext = picked.path.split('.').last.toLowerCase();
      final safeExt = ['jpg', 'jpeg', 'png', 'webp'].contains(ext) ? ext : 'jpg';
      final fileName = 'wallpaper_${DateTime.now().millisecondsSinceEpoch}.$safeExt';
      final savedPath = '${dir.path}/$fileName';
      
      await originalFile.copy(savedPath);
      return savedPath;
    }
    return null;
  }

  Future<Uint8List?> getWallpaperBytes() async {
    final path = await getWallpaperPath();
    if (path != null && File(path).existsSync()) {
      return await File(path).readAsBytes();
    }
    return null;
  }

  // Получить виджет обоев для превью
  Future<Widget> getWallpaperPreview({
    double opacity = 1.0,
    double blur = 0.0,
    double? width,
    double? height,
  }) async {
    final type = await getWallpaperType();
    
    Widget background;
    
    if (type == WallpaperType.gradient) {
      final colors = await getGradientColors();
      final begin = await getGradientBegin();
      final end = await getGradientEnd();
      
      if (colors != null && colors.length >= 2) {
        background = Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: begin,
              end: end,
            ),
          ),
        );
      } else {
        background = Container(color: Colors.grey);
      }
    } else {
      final path = await getWallpaperPath();
      if (path != null && File(path).existsSync()) {
        background = Image.file(
          File(path),
          fit: BoxFit.cover,
          width: width,
          height: height,
        );
      } else {
        background = Container(color: Colors.grey);
      }
    }
    
    return Stack(
      fit: StackFit.expand,
      children: [
        background,
        Container(color: Colors.black.withOpacity(1.0 - opacity)),
        if (blur > 0)
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
            child: Container(color: Colors.transparent),
          ),
      ],
    );
  }
}