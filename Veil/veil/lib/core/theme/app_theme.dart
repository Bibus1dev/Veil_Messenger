import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

enum ColorSchemeType {
  red,      // Кровавый закат
  birch,    // Древесный дух
  blue,     // Ледяная бездна (базовый)
  shimmering, // Космическая пыль
  darkOrange, // Огненная ночь (только тёмная)
  darkYellow, // Янтарный призрак (только тёмная)
  lightYellow, // Солнечный мед (только светлая)
  lightOrange, // Персиковый рассвет (только светлая)
}

extension ColorSchemeName on ColorSchemeType {
  String get displayName {
    switch (this) {
      case ColorSchemeType.red:
        return 'Кровавый закат';
      case ColorSchemeType.birch:
        return 'Древесный дух';
      case ColorSchemeType.blue:
        return 'Ледяная бездна';
      case ColorSchemeType.shimmering:
        return 'Космическая пыль';
      case ColorSchemeType.darkOrange:
        return 'Огненная ночь';
      case ColorSchemeType.darkYellow:
        return 'Янтарный призрак';
      case ColorSchemeType.lightYellow:
        return 'Солнечный мед';
      case ColorSchemeType.lightOrange:
        return 'Персиковый рассвет';
    }
  }

  bool get isDarkOnly {
    return this == ColorSchemeType.darkOrange || 
           this == ColorSchemeType.darkYellow;
  }

  bool get isLightOnly {
    return this == ColorSchemeType.lightYellow || 
           this == ColorSchemeType.lightOrange;
  }

  bool isAvailable(bool isDark) {
    if (isDarkOnly) return isDark;
    if (isLightOnly) return !isDark;
    return true;
  }
}

class AppTheme {
  static ThemeData getTheme({
    required ColorSchemeType colorScheme,
    required bool isDark,
  }) {
    final colors = _getColors(colorScheme, isDark);
    
    // AMOLED black for dark mode
    final backgroundColor = isDark ? Colors.black : const Color(0xFFFFFFFF);
    final surfaceColor = isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);
    
    return ThemeData(
      useMaterial3: true,
      brightness: isDark ? Brightness.dark : Brightness.light,
      
      scaffoldBackgroundColor: backgroundColor,
      
      colorScheme: ColorScheme.fromSeed(
        seedColor: colors.primary,
        brightness: isDark ? Brightness.dark : Brightness.light,
        primary: colors.primary,
        secondary: colors.secondary,
        surface: surfaceColor,
        background: backgroundColor,
      ),
      
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        systemOverlayStyle: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: colors.primary,
        unselectedItemColor: isDark ? Colors.grey : Colors.grey.shade600,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      
      cardTheme: CardThemeData(
        elevation: 0,
        color: isDark ? const Color(0xFF1C1C1C) : const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF1C1C1C) : const Color(0xFFF0F0F0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  static _ColorSet _getColors(ColorSchemeType type, bool isDark) {
    switch (type) {
      case ColorSchemeType.red:
        return _ColorSet(
          primary: const Color(0xFFE53935),
          secondary: const Color(0xFFEF5350),
        );
      case ColorSchemeType.birch:
        return _ColorSet(
          primary: const Color(0xFF5D4037),
          secondary: const Color(0xFF8D6E63),
        );
      case ColorSchemeType.blue:
        return _ColorSet(
          primary: const Color(0xFF1976D2),
          secondary: const Color(0xFF42A5F5),
        );
      case ColorSchemeType.shimmering:
        return _ColorSet(
          primary: const Color(0xFF7B1FA2),
          secondary: const Color(0xFFBA68C8),
        );
      case ColorSchemeType.darkOrange:
        // Чёрно-оранжевая: чёрный фон, оранжевые акценты
        return _ColorSet(
          primary: const Color(0xFFFF6D00), // Яркий оранжевый
          secondary: const Color(0xFFFF9100), // Светлее оранжевый
        );
      case ColorSchemeType.darkYellow:
        // Чёрно-жёлтая: чёрный фон, жёлтые акценты
        return _ColorSet(
          primary: const Color(0xFFFFD600), // Яркий жёлтый
          secondary: const Color(0xFFFFEA00), // Светлее жёлтый
        );
      case ColorSchemeType.lightYellow:
        // Бело-жёлтая: белый фон, жёлтые акценты
        return _ColorSet(
          primary: const Color(0xFFFBC02D), // Тёмно-жёлтый
          secondary: const Color(0xFFFDD835), // Жёлтый
        );
      case ColorSchemeType.lightOrange:
        // Бело-оранжевая: белый фон, оранжевые акценты
        return _ColorSet(
          primary: const Color(0xFFF57C00), // Тёмно-оранжевый
          secondary: const Color(0xFFFF9800), // Оранжевый
        );
    }
  }
}

class _ColorSet {
  final Color primary;
  final Color secondary;
  _ColorSet({required this.primary, required this.secondary});
}