import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../../services/api_service.dart';
import '../../../services/websocket_service.dart';
import '../../../data/local/local_database.dart';
import '../main/main_screen.dart';
import '../../../core/localization/extension.dart'; // ← ДОБАВИТЬ
import 'package:dio/dio.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _codeWordCtrl = TextEditingController();
  final _codeWordHintCtrl = TextEditingController();
  
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _usernameAvailable = false;
  bool _checkingUsername = false;
  String? _usernameError;
  File? _avatarFile;

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _avatarFile = File(picked.path));
    }
  }

  Future<void> _checkUsername(String username) async {
    final l10n = context.l10n;
    
    if (username.length < 3) {
      setState(() {
        _usernameError = l10n.minCharacters.replaceAll('{count}', '3');
        _usernameAvailable = false;
      });
      return;
    }

    setState(() => _checkingUsername = true);
    try {
      final response = await ApiService().checkUsername(username);
      
      // ФИКС: проверяем banned флаг
      if (response['banned'] == true) {
        setState(() {
          _usernameAvailable = false;
          _usernameError = response['error'] ?? l10n.usernameBanned; // Новая строка
        });
        return;
      }
      
      setState(() {
        _usernameAvailable = response['available'] == true;
        _usernameError = _usernameAvailable ? null : l10n.usernameTaken;
      });
    } catch (e) {
      setState(() => _usernameError = l10n.checkFailed);
    } finally {
      setState(() => _checkingUsername = false);
    }
  }

  void _showConfirmationPanel() {
    final l10n = context.l10n; // ← ДОБАВИТЬ
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              l10n.rememberThisInformation, // ← ИЗМЕНИТЬ
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.yourSecretCodeWord, // ← ИЗМЕНИТЬ
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _codeWordCtrl.text,
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 2),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 32),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _register();
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
                child: Text(
                  l10n.iUnderstandCreateAccount, // ← ИЗМЕНИТЬ
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            
            const SizedBox(height: 12),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(l10n.goBack), // ← ИЗМЕНИТЬ
              ),
            ),
            
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

    Future<void> _register() async {
    if (!_validateInputs()) return;

    setState(() => _loading = true);
    try {
      final response = await ApiService().register(
        email: _emailCtrl.text.trim(),
        username: _usernameCtrl.text.trim(),
        displayName: _displayNameCtrl.text.trim(),
        bio: _bioCtrl.text.isEmpty ? null : _bioCtrl.text,
        password: _passwordCtrl.text,
        codeWord: _codeWordCtrl.text,
        codeWordHint: _codeWordHintCtrl.text.isEmpty ? null : _codeWordHintCtrl.text,
        avatar: _avatarFile,
      );
      
      final userId = response.data['user_id'] as String;
      final token = response.data['token'] as String;
      final username = response.data['username'] as String;
      final avatarUrl = response.data['avatar_url'] as String?;
      
      final db = LocalDatabase();
      await db.setCurrentUser(userId);
      await db.saveUserWithToken(userId, {
        'username': username,
        'display_name': _displayNameCtrl.text.trim(),
        'avatar_url': avatarUrl,
        'bio': _bioCtrl.text.isEmpty ? null : _bioCtrl.text,
        'status': 'online',
      }, token);
      
      ApiService().setAuthToken(token);
      
      print('🟡 Register success - connecting WebSocket...');
      await WebSocketService().connect(token, userId);
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    } on DioException catch (e) {
      // ФИКС: правильная обработка ошибок бана
      if (e.response?.statusCode == 403) {
        final data = e.response?.data;
        if (data is Map && data['banned'] == true) {
          _showError(data['error']?.toString() ?? context.l10n.registrationBanned);
          setState(() => _loading = false);
          return;
        }
        // Другая 403 ошибка (например, IP бан)
        _showError(data is Map && data['error'] != null 
            ? data['error'].toString() 
            : context.l10n.accessDenied);
        setState(() => _loading = false);
        return;
      }
      
      // Обработка 409 (уже существует)
      if (e.response?.statusCode == 409) {
        final data = e.response?.data;
        final field = data is Map ? data['field']?.toString() : null;
        final errorMsg = data is Map && data['error'] != null 
            ? data['error'].toString() 
            : context.l10n.registrationFailed;
            
        if (field == 'email') {
          _showError(context.l10n.emailAlreadyExists);
        } else if (field == 'username') {
          _showError(context.l10n.usernameTaken);
        } else {
          _showError(errorMsg);
        }
        setState(() => _loading = false);
        return;
      }
      
      // Обработка 400 (невалидные данные)
      if (e.response?.statusCode == 400) {
        final data = e.response?.data;
        final errorMsg = data is Map && data['error'] != null 
            ? data['error'].toString() 
            : context.l10n.invalidData;
        _showError(errorMsg);
        setState(() => _loading = false);
        return;
      }
      
      // Обработка 500 (серверная ошибка)
      if (e.response?.statusCode == 500) {
        final data = e.response?.data;
        final errorMsg = data is Map && data['error'] != null 
            ? data['error'].toString() 
            : context.l10n.serverError;
        _showError(errorMsg);
        setState(() => _loading = false);
        return;
      }
      
      // Остальные Dio ошибки
      _showError(context.l10n.registrationFailed.replaceAll('{error}', e.message ?? e.toString()));
    } catch (e) {
      _showError(context.l10n.registrationFailed.replaceAll('{error}', e.toString()));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  bool _validateInputs() {
    final l10n = context.l10n;
    
    if (_emailCtrl.text.isEmpty || !_emailCtrl.text.contains('@')) {
      _showError(l10n.enterValidEmail); // ← ИЗМЕНИТЬ
      return false;
    }
    if (!_usernameAvailable) {
      _showError(l10n.usernameTaken); // ← ИЗМЕНИТЬ
      return false;
    }
    if (_displayNameCtrl.text.isEmpty) {
      _showError(l10n.displayName); // ← ИЗМЕНИТЬ
      return false;
    }
    if (_passwordCtrl.text.length < 6) {
      _showError(l10n.passwordMinChars.replaceAll('{count}', '6')); // ← ИЗМЕНИТЬ
      return false;
    }
    if (_passwordCtrl.text != _confirmPasswordCtrl.text) {
      _showError(l10n.passwordsDoNotMatch); // ← ИЗМЕНИТЬ
      return false;
    }
    if (_codeWordCtrl.text.isEmpty) {
      _showError(l10n.secretCodeWord); // ← ИЗМЕНИТЬ
      return false;
    }
    return true;
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _bioCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _codeWordCtrl.dispose();
    _codeWordHintCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n; // ← ДОБАВИТЬ
    
    return Scaffold(
      appBar: AppBar(title: Text(l10n.createAccountTitle)), // ← ИЗМЕНИТЬ
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            GestureDetector(
              onTap: _pickAvatar,
              child: CircleAvatar(
                radius: 50,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: _avatarFile != null ? FileImage(_avatarFile!) : null,
                child: _avatarFile == null
                    ? const Icon(Icons.camera_alt, size: 40, color: Colors.grey)
                    : null,
              ),
            ),
            const SizedBox(height: 24),
            
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: l10n.email, // ← ИЗМЕНИТЬ
                prefixIcon: const Icon(Icons.email_outlined),
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _usernameCtrl,
              onChanged: (value) {
                if (value.length >= 3) {
                  _checkUsername(value);
                }
              },
              decoration: InputDecoration(
                labelText: l10n.username, // ← ИЗМЕНИТЬ
                prefixIcon: const Icon(Icons.person_outline),
                suffixIcon: _checkingUsername
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : _usernameAvailable
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : _usernameError != null
                            ? const Icon(Icons.error, color: Colors.red)
                            : null,
                errorText: _usernameError,
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _displayNameCtrl,
              decoration: InputDecoration(
                labelText: l10n.displayName, // ← ИЗМЕНИТЬ
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _bioCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: l10n.bioOptional, // ← ИЗМЕНИТЬ
                prefixIcon: const Icon(Icons.info_outline),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: l10n.password, // ← ИЗМЕНИТЬ
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _confirmPasswordCtrl,
              obscureText: _obscureConfirm,
              decoration: InputDecoration(
                labelText: l10n.confirmPassword, // ← ИЗМЕНИТЬ
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscureConfirm ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                ),
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _codeWordCtrl,
              decoration: InputDecoration(
                labelText: l10n.secretCodeWord, // ← ИЗМЕНИТЬ
                prefixIcon: const Icon(Icons.key_outlined),
                helperText: l10n.codeWordHelper, // ← ИЗМЕНИТЬ
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _codeWordHintCtrl,
              decoration: InputDecoration(
                labelText: l10n.codeWordHintOptional, // ← ИЗМЕНИТЬ
                prefixIcon: const Icon(Icons.help_outline),
              ),
            ),
            const SizedBox(height: 32),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _showConfirmationPanel,
                child: _loading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(l10n.createAccount, style: const TextStyle(fontSize: 16)), // ← ИЗМЕНИТЬ
              ),
            ),
          ],
        ),
      ),
    );
  }
}