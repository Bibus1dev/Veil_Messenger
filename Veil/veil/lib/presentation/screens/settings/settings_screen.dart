import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/theme_cubit.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/localization/extension.dart';
import '../../../core/localization/language_service.dart';
import '../../../core/localization/restart_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../services/wallpaper_service.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'dart:ui';
import 'dart:typed_data';
import 'dart:io';
import '../../../presentation/widgets/NothingGlyphSettingsWidget.dart';  // <-- ДОБАВЬ ЭТОТ ИМПОРТ
import 'package:image_picker/image_picker.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final WallpaperService _wallpaperService = WallpaperService();
  
  String? _wallpaperPath;
  double _wallpaperOpacity = 0.5;
  double _wallpaperBlur = 0.0;
  WallpaperType _wallpaperType = WallpaperType.image;
  List<Color>? _gradientColors;
  Alignment _gradientBegin = Alignment.topLeft;
  Alignment _gradientEnd = Alignment.bottomRight;
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    _wallpaperType = await _wallpaperService.getWallpaperType();
    _wallpaperPath = await _wallpaperService.getWallpaperPath();
    _wallpaperOpacity = await _wallpaperService.getWallpaperOpacity();
    _wallpaperBlur = await _wallpaperService.getWallpaperBlur();
    _gradientColors = await _wallpaperService.getGradientColors();
    _gradientBegin = await _wallpaperService.getGradientBegin();
    _gradientEnd = await _wallpaperService.getGradientEnd();
    
    if (mounted) setState(() {});
  }

  @override
Widget build(BuildContext context) {
  final l10n = context.l10n;
  final colorScheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final currentLocale = Localizations.localeOf(context);

  return Scaffold(
    backgroundColor: isDark ? Colors.black : colorScheme.surface,
    appBar: AppBar(
      elevation: 0,
      backgroundColor: Colors.transparent,
      title: Text(
        l10n.settingsTitle,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    ),
    body: BlocBuilder<ThemeCubit, ThemeState>(
      builder: (context, state) {
        String currentThemeName = _getThemeName(state.colorScheme, l10n);
        String currentLanguage = currentLocale.languageCode == 'ru' ? 'Русский' : 'English';
        
        final hasWallpaper = _wallpaperType == WallpaperType.image 
            ? _wallpaperPath != null 
            : _gradientColors != null;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // === СЕКЦИЯ: Внешний вид ===
            _buildSectionTitle(context, l10n.appearance),
            
            // Тёмная тема
            _buildGlassCard(
              child: SwitchListTile(
                secondary: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: state.isDark 
                        ? Colors.amber.withOpacity(0.2)
                        : Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    state.isDark ? Icons.dark_mode : Icons.light_mode,
                    color: state.isDark ? Colors.amber : Colors.blue,
                  ),
                ),
                title: Text(
                  l10n.settingsDarkMode,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  state.isDark ? l10n.settingsDarkModeOn : l10n.settingsDarkModeOff,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                value: state.isDark,
                onChanged: (_) {
                  context.read<ThemeCubit>().toggleDarkMode();
                },
                activeColor: colorScheme.primary,
              ),
            ),
            
            const SizedBox(height: 12),
            
            // Цветовая тема
            _buildGlassCard(
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: _getThemeGradient(state.colorScheme),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                title: Text(
                  l10n.settingsColorTheme,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  currentThemeName,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: colorScheme.primary,
                  ),
                ),
                onTap: () => _showColorPicker(context, state),
              ),
            ),
            
            const SizedBox(height: 12),
            
            // === ОБОИ ЧАТА ===
            _buildGlassCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.wallpaper, color: Colors.purple),
                    ),
                    title: Text(
                      l10n.settingsWallpaper,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      hasWallpaper 
                          ? (_wallpaperType == WallpaperType.gradient ? 'Градиент' : 'Изображение')
                          : 'Не установлены',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.purple.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.arrow_forward_ios,
                        size: 16,
                        color: Colors.purple,
                      ),
                    ),
                    onTap: () => _showWallpaperPicker(),
                  ),
                  
                  if (hasWallpaper) ...[
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Превью обоев
                          Container(
                            height: 200,
                            width: double.infinity,
                            clipBehavior: Clip.antiAlias,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: _buildWallpaperPreview(),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Center(
                            child: Text(
                              'Предпросмотр',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500,
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Непрозрачность
                          Row(
                            children: [
                              Icon(Icons.opacity, size: 20, color: Colors.grey.shade600),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Непрозрачность фона',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          '${(_wallpaperOpacity * 100).toInt()}%',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Slider(
                                      value: _wallpaperOpacity,
                                      min: 0.1,
                                      max: 1.0,
                                      divisions: 18,
                                      activeColor: colorScheme.primary,
                                      onChanged: (value) {
                                        setState(() => _wallpaperOpacity = value);
                                      },
                                      onChangeEnd: (value) async {
                                        await _wallpaperService.setWallpaperOpacity(value);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 8),
                          
                          // Размытие
                          Row(
                            children: [
                              Icon(Icons.blur_on, size: 20, color: Colors.grey.shade600),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Размытие',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          '${_wallpaperBlur.toInt()}',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Slider(
                                      value: _wallpaperBlur,
                                      min: 0,
                                      max: 20,
                                      divisions: 20,
                                      activeColor: colorScheme.primary,
                                      onChanged: (value) {
                                        setState(() => _wallpaperBlur = value);
                                      },
                                      onChangeEnd: (value) async {
                                        await _wallpaperService.setWallpaperBlur(value);
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          
                          const SizedBox(height: 16),
                          
                          // Кнопка удаления
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await _wallpaperService.removeWallpaper();
                                setState(() {
                                  _wallpaperPath = null;
                                  _gradientColors = null;
                                  _wallpaperOpacity = 0.5;
                                  _wallpaperBlur = 0.0;
                                });
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Обои удалены')),
                                );
                              },
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              label: const Text('Удалить обои', style: TextStyle(color: Colors.red)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // === НОВАЯ СЕКЦИЯ: NOTHING PHONE ===
            _buildSectionTitle(context, 'Nothing Phone'),
            
            // Nothing Glyph API плашка
            const NothingGlyphSettingsWidget(),
            
            const SizedBox(height: 24),
            
            // === СЕКЦИЯ: Язык и регион ===
            _buildSectionTitle(context, l10n.languageRegion),
            
            // Язык
            _buildGlassCard(
              child: ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.language, color: Colors.teal),
                ),
                title: Text(
                  l10n.settingsLanguage,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  currentLanguage,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.teal.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: Colors.teal,
                  ),
                ),
                onTap: () => _showLanguagePicker(context),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // === СЕКЦИЯ: О приложении ===
            _buildSectionTitle(context, l10n.about),
            
            // О мессенджере
            _buildGlassCard(
              child: AboutListTile(
                icon: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.info_outline, color: Colors.blue),
                ),
                applicationName: l10n.appName,
                applicationVersion: '0.3.0 ALPHA',
                applicationLegalese: l10n.settingsAbout,
                aboutBoxChildren: [
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock, color: colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'End-to-end encrypted messenger',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),
            
            // === СЕКЦИЯ: Поддержка ===
            _buildSectionTitle(context, l10n.support),
            
            // Пожертвования
            FutureBuilder<bool>(
              future: SharedPreferences.getInstance().then((prefs) => prefs.getBool('donation_visible') ?? true),
              builder: (context, snapshot) {
                final isVisible = snapshot.data ?? true;
                return _buildGlassCard(
                  child: SwitchListTile(
                    secondary: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.favorite, color: Colors.red),
                    ),
                    title: Text(
                      l10n.settingsShowDonation,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      isVisible ? l10n.visible : l10n.hidden,
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                    value: isVisible,
                    onChanged: (value) async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('donation_visible', value);
                      setState(() {});
                    },
                    activeColor: colorScheme.primary,
                  ),
                );
              },
            ),
            
            const SizedBox(height: 32),
          ],
        );
      },
    ),
  );
}

  // === ПРЕВЬЮ ОБОЕВ С ЖИВЫМ ОБНОВЛЕНИЕМ ===
    // === ПРЕВЬЮ ОБОЕВ С ЖИВЫМ ОБНОВЛЕНИЕМ ===
  Widget _buildWallpaperPreview() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    Widget background;
    
    if (_wallpaperType == WallpaperType.gradient && _gradientColors != null) {
      background = Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: _gradientColors!,
            begin: _gradientBegin,
            end: _gradientEnd,
          ),
        ),
      );
    } else if (_wallpaperPath != null && File(_wallpaperPath!).existsSync()) {
      background = Image.file(
        File(_wallpaperPath!),
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    } else {
      background = Container(
        color: isDark ? Colors.grey.shade900 : Colors.grey.shade200,
        child: Center(
          child: Icon(
            Icons.image_not_supported,
            color: Colors.grey.shade500,
            size: 48,
          ),
        ),
      );
    }
    
    return Stack(
      fit: StackFit.expand,
      children: [
        background,
        // Затемнение
        Container(
          color: Colors.black.withOpacity(1.0 - _wallpaperOpacity),
        ),
        // Размытие
        if (_wallpaperBlur > 0)
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: _wallpaperBlur, sigmaY: _wallpaperBlur),
            child: Container(color: Colors.transparent),
          ),
        // Пример сообщения для наглядности
        Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 32),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.9),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Text(
              'Пример сообщения',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }

  // === ВЫБОР ОБОЕВ: Изображение, Градиенты, Свой градиент ===
  void _showWallpaperPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) {
          return SafeArea(
            child: SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  const Text(
                    'Выберите фон чата',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  
                  // Изображение из галереи
                  ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.photo_library, color: Colors.blue),
                    ),
                    title: const Text('Изображение из галереи'),
                    subtitle: const Text('Использовать свою фотографию'),
                    onTap: () async {
                      Navigator.pop(context);
                      final path = await _wallpaperService.pickImageFromGallery();
                      if (path != null) {
                        await _wallpaperService.setImageWallpaper(path);
                        setState(() {
                          _wallpaperType = WallpaperType.image;
                          _wallpaperPath = path;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Обои установлены')),
                        );
                      }
                    },
                  ),
                  
                  const Divider(height: 32),
                  
                  // Готовые градиенты
                  const Text(
                    'Градиенты',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.5,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: _wallpaperService.gradientPresets.length,
                    itemBuilder: (context, index) {
                      final preset = _wallpaperService.gradientPresets[index];
                      return GestureDetector(
                        onTap: () async {
                          Navigator.pop(context);
                          await _wallpaperService.setGradientWallpaper(
                            preset.colors,
                            preset.begin,
                            preset.end,
                          );
                          setState(() {
                            _wallpaperType = WallpaperType.gradient;
                            _gradientColors = preset.colors;
                            _gradientBegin = preset.begin;
                            _gradientEnd = preset.end;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Градиент "${preset.name}" установлен')),
                          );
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: LinearGradient(
                              colors: preset.colors,
                              begin: preset.begin,
                              end: preset.end,
                            ),
                          ),
                          child: Align(
                            alignment: Alignment.bottomLeft,
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                preset.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black54,
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Свой градиент
                  ListTile(
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.pink, Colors.purple, Colors.blue],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.palette, color: Colors.white),
                    ),
                    title: const Text('Свой градиент'),
                    subtitle: const Text('Создать уникальный градиент'),
                    onTap: () {
                      Navigator.pop(context);
                      _showCustomGradientBuilder();
                    },
                  ),
                  
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // === КОНСТРУКТОР СВОЕГО ГРАДИЕНТА ===
    // === КОНСТРУКТОР СВОЕГО ГРАДИЕНТА (ИСПРАВЛЕННЫЙ) ===
  void _showCustomGradientBuilder() {
    List<Color> colors = [Colors.blue, Colors.purple];
    Alignment begin = Alignment.topLeft;
    Alignment end = Alignment.bottomRight;
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Свой градиент',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    
                    // === ПРЕВЬЮ (ЖИВОЕ ОБНОВЛЕНИЕ) ===
                    Container(
                      height: 150,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          colors: colors,
                          begin: begin,
                          end: end,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    
                    // Выбор цветов
                    const Text(
                      'Цвета (нажмите чтобы изменить, × чтобы удалить)',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ...colors.asMap().entries.map((entry) {
                          final index = entry.key;
                          final color = entry.value;
                          return GestureDetector(
                            onTap: () async {
                              final newColor = await _showColorPickerDialog(color);
                              if (newColor != null) {
                                setModalState(() {
                                  colors[index] = newColor;
                                });
                                // === ИСПРАВЛЕНО: НЕ НУЖНО менять направление, превью обновится автоматически ===
                              }
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: color,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: index == 0
                                  ? null  // Первый цвет просто цвет
                                  : GestureDetector(
                                      onTap: () {
                                        setModalState(() {
                                          colors.removeAt(index);
                                        });
                                      },
                                      child: Container(
                                        decoration: BoxDecoration(
                                          color: Colors.black.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: const Icon(Icons.close, color: Colors.white, size: 20),
                                      ),
                                    ),
                            ),
                          );
                        }).toList(),
                        
                        if (colors.length < 5)
                          GestureDetector(
                            onTap: () async {
                              final newColor = await _showColorPickerDialog(Colors.white);
                              if (newColor != null) {
                                setModalState(() {
                                  colors.add(newColor);
                                });
                              }
                            },
                            child: Container(
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey.shade400,
                                  style: BorderStyle.solid,
                                  width: 2,
                                ),
                              ),
                              child: const Icon(Icons.add, color: Colors.grey),
                            ),
                          ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // === ИСПРАВЛЕНО: НАПРАВЛЕНИЕ - ТОЛЬКО ИКОНКИ, БЕЗ СМАЙЛИКОВ ===
                    const Text(
                      'Направление',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: [
                        _buildDirectionButton(
                          alignment: Alignment.topLeft,
                          icon: Icons.north_west,
                          label: '↖',
                          currentBegin: begin,
                          currentEnd: end,
                          onTap: (b, e) {
                            setModalState(() {
                              begin = b;
                              end = e;
                            });
                          },
                        ),
                        _buildDirectionButton(
                          alignment: Alignment.topCenter,
                          icon: Icons.arrow_upward,
                          label: '↑',
                          currentBegin: begin,
                          currentEnd: end,
                          onTap: (b, e) {
                            setModalState(() {
                              begin = b;
                              end = e;
                            });
                          },
                        ),
                        _buildDirectionButton(
                          alignment: Alignment.topRight,
                          icon: Icons.north_east,
                          label: '↗',
                          currentBegin: begin,
                          currentEnd: end,
                          onTap: (b, e) {
                            setModalState(() {
                              begin = b;
                              end = e;
                            });
                          },
                        ),
                        _buildDirectionButton(
                          alignment: Alignment.centerLeft,
                          icon: Icons.arrow_back,
                          label: '←',
                          currentBegin: begin,
                          currentEnd: end,
                          onTap: (b, e) {
                            setModalState(() {
                              begin = b;
                              end = e;
                            });
                          },
                        ),
                        _buildDirectionButton(
                          alignment: Alignment.center,
                          icon: Icons.all_inclusive,
                          label: '⊙',
                          currentBegin: begin,
                          currentEnd: end,
                          onTap: (b, e) {
                            setModalState(() {
                              begin = Alignment.topLeft;
                              end = Alignment.bottomRight;
                            });
                          },
                        ),
                        _buildDirectionButton(
                          alignment: Alignment.centerRight,
                          icon: Icons.arrow_forward,
                          label: '→',
                          currentBegin: begin,
                          currentEnd: end,
                          onTap: (b, e) {
                            setModalState(() {
                              begin = b;
                              end = e;
                            });
                          },
                        ),
                        _buildDirectionButton(
                          alignment: Alignment.bottomLeft,
                          icon: Icons.south_west,
                          label: '↙',
                          currentBegin: begin,
                          currentEnd: end,
                          onTap: (b, e) {
                            setModalState(() {
                              begin = b;
                              end = e;
                            });
                          },
                        ),
                        _buildDirectionButton(
                          alignment: Alignment.bottomCenter,
                          icon: Icons.arrow_downward,
                          label: '↓',
                          currentBegin: begin,
                          currentEnd: end,
                          onTap: (b, e) {
                            setModalState(() {
                              begin = b;
                              end = e;
                            });
                          },
                        ),
                        _buildDirectionButton(
                          alignment: Alignment.bottomRight,
                          icon: Icons.south_east,
                          label: '↘',
                          currentBegin: begin,
                          currentEnd: end,
                          onTap: (b, e) {
                            setModalState(() {
                              begin = b;
                              end = e;
                            });
                          },
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Кнопки
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Отмена'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: () async {
                              Navigator.pop(context);
                              await _wallpaperService.setGradientWallpaper(colors, begin, end);
                              setState(() {
                                _wallpaperType = WallpaperType.gradient;
                                _gradientColors = colors;
                                _gradientBegin = begin;
                                _gradientEnd = end;
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Градиент установлен')),
                              );
                            },
                            child: const Text('Применить'),
                          ),
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // === ИСПРАВЛЕННАЯ КНОПКА НАПРАВЛЕНИЯ ===
  Widget _buildDirectionButton({
    required Alignment alignment,
    required IconData icon,
    required String label,
    required Alignment currentBegin,
    required Alignment currentEnd,
    required Function(Alignment begin, Alignment end) onTap,
  }) {
    // Определяем end на основе begin
    Alignment end;
    if (alignment == Alignment.center) {
      end = Alignment.bottomRight; // Для центра - диагональ
    } else {
      // Инвертируем для end
      end = Alignment(
        -alignment.x,
        -alignment.y,
      );
    }
    
    final isSelected = currentBegin == alignment;
    
    return GestureDetector(
      onTap: () => onTap(alignment, end),
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: isSelected ? Colors.purple : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.purple.shade700 : Colors.grey.shade400,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? Colors.white : Colors.grey.shade700,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<Color?> _showColorPickerDialog(Color initialColor) async {
    Color selectedColor = initialColor;
    
    return showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выберите цвет'),
        content: SingleChildScrollView(
          child: ColorPicker(
            pickerColor: initialColor,
            onColorChanged: (color) => selectedColor = color,
            pickerAreaHeightPercent: 0.8,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, selectedColor),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // Остальные методы без изменений...
  Widget _buildSectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Colors.grey.shade600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildGlassCard({required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark 
            ? Colors.grey.shade900.withOpacity(0.7)
            : Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark 
              ? Colors.grey.shade800
              : Colors.grey.shade200,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }

  String _getThemeName(ColorSchemeType type, AppLocalizations l10n) {
    switch (type) {
      case ColorSchemeType.red:
        return l10n.colorThemeRed;
      case ColorSchemeType.birch:
        return l10n.colorThemeBirch;
      case ColorSchemeType.blue:
        return l10n.colorThemeBlue;
      case ColorSchemeType.shimmering:
        return l10n.colorThemeShimmering;
      case ColorSchemeType.darkOrange:
        return l10n.colorThemeDarkOrange;
      case ColorSchemeType.darkYellow:
        return l10n.colorThemeDarkYellow;
      case ColorSchemeType.lightYellow:
        return l10n.colorThemeLightYellow;
      case ColorSchemeType.lightOrange:
        return l10n.colorThemeLightOrange;
    }
  }

  Gradient _getThemeGradient(ColorSchemeType type) {
    switch (type) {
      case ColorSchemeType.red:
        return LinearGradient(
          colors: [Colors.red.shade600, Colors.red.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ColorSchemeType.birch:
        return LinearGradient(
          colors: [Colors.brown.shade600, Colors.brown.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ColorSchemeType.blue:
        return LinearGradient(
          colors: [Colors.blue.shade700, Colors.blue.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ColorSchemeType.shimmering:
        return LinearGradient(
          colors: [Colors.purple.shade700, Colors.purple.shade400],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ColorSchemeType.darkOrange:
        return LinearGradient(
          colors: [const Color(0xFFFF6D00), const Color(0xFFFF9100)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ColorSchemeType.darkYellow:
        return LinearGradient(
          colors: [const Color(0xFFFFD600), const Color(0xFFFFEA00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ColorSchemeType.lightYellow:
        return LinearGradient(
          colors: [const Color(0xFFFBC02D), const Color(0xFFFDD835)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case ColorSchemeType.lightOrange:
        return LinearGradient(
          colors: [const Color(0xFFF57C00), const Color(0xFFFF9800)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  void _showColorPicker(BuildContext context, ThemeState currentState) {
    final l10n = context.l10n;
    
    final availableSchemes = ColorSchemeType.values.where(
      (scheme) => scheme.isAvailable(currentState.isDark)
    ).toList();

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.colorThemeSelect,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                currentState.isDark 
                    ? l10n.colorThemeAvailableForDark
                    : l10n.colorThemeAvailableForLight,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
              ...availableSchemes.map((scheme) {
                final isSelected = scheme == currentState.colorScheme;
                final colors = _getPreviewColors(scheme);
                
                String themeName = _getThemeName(scheme, l10n);
                
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colors.primary, colors.secondary],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected 
                          ? Border.all(color: Colors.white, width: 3)
                          : null,
                      boxShadow: isSelected
                          ? [BoxShadow(
                              color: colors.primary.withOpacity(0.4),
                              blurRadius: 8,
                              spreadRadius: 2,
                            )]
                          : null,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                  title: Text(
                    themeName,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: colors.primary)
                      : null,
                  onTap: () {
                    context.read<ThemeCubit>().setColorScheme(scheme);
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context) {
    final l10n = context.l10n;
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.settingsLanguage,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('English'),
                trailing: Localizations.localeOf(context).languageCode == 'en'
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  await LanguageService().setLocale('en');
                  if (context.mounted) {
                    RestartWidget.restartApp(context);
                  }
                },
              ),
              ListTile(
                leading: const Icon(Icons.language),
                title: const Text('Русский'),
                trailing: Localizations.localeOf(context).languageCode == 'ru'
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () async {
                  Navigator.pop(context);
                  await LanguageService().setLocale('ru');
                  if (context.mounted) {
                    RestartWidget.restartApp(context);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  ({Color primary, Color secondary}) _getPreviewColors(ColorSchemeType type) {
    switch (type) {
      case ColorSchemeType.red:
        return (primary: Colors.red.shade600, secondary: Colors.red.shade400);
      case ColorSchemeType.birch:
        return (primary: Colors.brown.shade600, secondary: Colors.brown.shade400);
      case ColorSchemeType.blue:
        return (primary: Colors.blue.shade700, secondary: Colors.blue.shade400);
      case ColorSchemeType.shimmering:
        return (primary: Colors.purple.shade700, secondary: Colors.purple.shade400);
      case ColorSchemeType.darkOrange:
        return (primary: const Color(0xFFFF6D00), secondary: const Color(0xFFFF9100));
      case ColorSchemeType.darkYellow:
        return (primary: const Color(0xFFFFD600), secondary: const Color(0xFFFFEA00));
      case ColorSchemeType.lightYellow:
        return (primary: const Color(0xFFFBC02D), secondary: const Color(0xFFFDD835));
      case ColorSchemeType.lightOrange:
        return (primary: const Color(0xFFF57C00), secondary: const Color(0xFFFF9800));
    }
  }
}