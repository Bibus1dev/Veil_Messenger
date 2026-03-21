// NothingGlyphSettingsWidget.dart - обновленная версия
import 'package:flutter/material.dart';
import '../../services/NothingGlyphService.dart';

class NothingGlyphSettingsWidget extends StatefulWidget {
  const NothingGlyphSettingsWidget({super.key});

  @override
  State<NothingGlyphSettingsWidget> createState() => _NothingGlyphSettingsWidgetState();
}

class _NothingGlyphSettingsWidgetState extends State<NothingGlyphSettingsWidget> {
  final NothingGlyphService _glyphService = NothingGlyphService();
  bool _isLoading = true;
  Map<String, dynamic>? _status;
  bool _isTesting = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _glyphService.initialize();
    setState(() {
      _status = _glyphService.getStatusInfo();
      _isLoading = false;
    });
  }

  void _showBetaInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Beta версия'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Система находится в тестовом режиме и работает через отладочный интерфейс Nothing.',
            ),
            SizedBox(height: 16),
            Text(
              'Для полноценной работы в реальной системе необходимо:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text('• Получить официальный API ключ у Nothing'),
            Text('• Пройти верификацию приложения'),
            Text('• Интегрироваться с Glyph Developer Kit'),
            SizedBox(height: 16),
            Text(
              'Помогите нам расфорсить мессенджер!\nЧем больше пользователей проявит интерес, тем выше шанс получить официальный доступ.',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return _buildCard(
        child: const ListTile(
          leading: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('Nothing Glyph API'),
          subtitle: Text('Проверка устройства...'),
        ),
        isAvailable: false,
      );
    }

    final isAvailable = _status?['available'] ?? false;
    final isConnected = _status?['connected'] ?? false;
    final model = _status?['model']?.toString().replaceAll('NothingPhoneModel.', '').toUpperCase() ?? 'UNKNOWN';

    return _buildCard(
      isAvailable: isAvailable,
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isAvailable 
                    ? (isDark ? Colors.white.withOpacity(0.15) : Colors.grey.shade200)
                    : (isDark ? Colors.grey.shade600 : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.lightbulb_outline,
                color: isAvailable 
                    ? (isDark ? Colors.white : Colors.black87)
                    : (isDark ? Colors.grey.shade400 : Colors.grey.shade500),
              ),
            ),
            title: Row(
              children: [
                Text(
                  'Nothing Glyph API',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _showBetaInfo,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'BETA',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAvailable 
                      ? 'Phone ($model)'
                      : 'Устройство не поддерживается',
                  style: TextStyle(
                    color: isAvailable 
                        ? (isDark ? Colors.grey.shade400 : Colors.grey.shade600)
                        : (isDark ? Colors.grey.shade500 : Colors.grey.shade600),
                    fontSize: 14,
                  ),
                ),
                if (isAvailable)
                  Text(
                    isConnected ? 'Подключено' : 'Ожидание подключения...',
                    style: TextStyle(
                      color: isConnected ? Colors.green : Colors.orange,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
          ),
          
          if (isAvailable) ...[
            Divider(
              height: 1, 
              indent: 16, 
              endIndent: 16,
              color: isDark ? Colors.white24 : Colors.grey.shade300,
            ),
            
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Glyph интерфейс:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Картинка макета глифов - серая в черных тонах
                  Center(
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        0.3, 0.3, 0.3, 0, 0,
                        0.3, 0.3, 0.3, 0, 0,
                        0.3, 0.3, 0.3, 0, 0,
                        0,   0,   0,   1, 0,
                      ]),
                      child: Image.asset(
                        'assets/images/glyph_layout.png',
                        width: 280,
                        height: 180,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: 280,
                            height: 180,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                'Glyph Layout\n(только для Nothing Phone 3a)',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Кнопка TEST - теперь корректно отображается в светлой теме
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (isConnected && !_isTesting) ? _runTest : null,
                      icon: _isTesting 
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isDark ? Colors.black : Colors.white, // Цвет индикатора в зависимости от темы
                              ),
                            )
                          : Icon(
                              Icons.play_arrow,
                              color: isDark ? Colors.black : Colors.white, // Цвет иконки в зависимости от темы
                            ),
                      label: Text(
                        _isTesting ? 'Тест...' : 'Test Glyph',
                        style: TextStyle(
                          color: isDark ? Colors.black : Colors.white, // Цвет текста в зависимости от темы
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark ? Colors.white : Colors.black, // Меняем фон кнопки
                        foregroundColor: isDark ? Colors.black : Colors.white,
                        disabledBackgroundColor: isDark ? Colors.grey.shade400 : Colors.grey.shade300,
                        disabledForegroundColor: isDark ? Colors.black38 : Colors.white38,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  
                  if (!isConnected)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'ADB: settings put global nt_glyph_interface_debug_enable 1',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade300,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child, required bool isAvailable}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark 
            ? (isAvailable ? Colors.grey.shade900.withOpacity(0.9) : Colors.grey.shade900.withOpacity(0.7))
            : Colors.white.withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAvailable 
              ? (isDark ? Colors.white24 : Colors.grey.shade300)
              : (isDark ? Colors.grey.shade700 : Colors.grey.shade400),
          width: 1,
        ),
        boxShadow: isAvailable ? [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ] : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }

  Future<void> _runTest() async {
    setState(() => _isTesting = true);
    await _glyphService.runTestSequence();
    setState(() => _isTesting = false);
  }
}