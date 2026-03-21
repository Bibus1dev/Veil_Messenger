import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

class ThemeState extends Equatable {
  final ColorSchemeType colorScheme;
  final bool isDark;
  
  const ThemeState({
    this.colorScheme = ColorSchemeType.blue, // Базовый теперь Blue
    this.isDark = false,
  });
  
  ThemeState copyWith({ColorSchemeType? colorScheme, bool? isDark}) {
    return ThemeState(
      colorScheme: colorScheme ?? this.colorScheme,
      isDark: isDark ?? this.isDark,
    );
  }
  
  @override
  List<Object?> get props => [colorScheme, isDark];
}

class ThemeCubit extends Cubit<ThemeState> {
  ThemeCubit() : super(const ThemeState());

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final colorIndex = prefs.getInt('theme_color') ?? ColorSchemeType.blue.index;
    final isDark = prefs.getBool('theme_dark') ?? false;
    
    var colorScheme = ColorSchemeType.values[colorIndex];
    
    // Проверяем доступность темы
    if (!colorScheme.isAvailable(isDark)) {
      // Если тема недоступна, переключаем на базовую
      colorScheme = ColorSchemeType.blue;
    }
    
    emit(ThemeState(
      colorScheme: colorScheme,
      isDark: isDark,
    ));
  }

  Future<void> setColorScheme(ColorSchemeType scheme) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_color', scheme.index);
    emit(state.copyWith(colorScheme: scheme));
  }

  Future<void> toggleDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    final newIsDark = !state.isDark;
    await prefs.setBool('theme_dark', newIsDark);
    
    // Проверяем, доступна ли текущая тема в новом режиме
    if (!state.colorScheme.isAvailable(newIsDark)) {
      // Переключаем на базовую тему
      await prefs.setInt('theme_color', ColorSchemeType.blue.index);
      emit(ThemeState(colorScheme: ColorSchemeType.blue, isDark: newIsDark));
    } else {
      emit(state.copyWith(isDark: newIsDark));
    }
  }
}