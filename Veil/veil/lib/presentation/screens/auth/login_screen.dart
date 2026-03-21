import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../services/websocket_service.dart';
import '../../../data/local/local_database.dart';
import '../main/main_screen.dart';
import '../../../core/localization/extension.dart'; // ← ДОБАВИТЬ

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  Future<void> _login() async {
    final l10n = context.l10n;
    
    if (_usernameCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      _showError(l10n.fillAllFields);
      return;
    }

    setState(() => _loading = true);
    try {
      final response = await ApiService().login(
        _usernameCtrl.text.trim(),
        _passwordCtrl.text,
      );
      
      final userId = response.data['user_id'] as String;
      final token = response.data['token'] as String;
      final username = response.data['username'] as String;
      final avatarUrl = response.data['avatar_url'] as String?;
      
      final db = LocalDatabase();
      await db.setCurrentUser(userId);
      await db.saveUserWithToken(userId, {
        'username': username,
        'display_name': username,
        'avatar_url': avatarUrl,
        'bio': null,
        'status': 'online',
      }, token);
      
      ApiService().setAuthToken(token);
      
      print('🟡 Login success - connecting WebSocket...');
      await WebSocketService().connect(token, userId);
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
    } catch (e) {
      _showError(l10n.invalidCredentials);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n; // ← ДОБАВИТЬ
    
    return Scaffold(
      appBar: AppBar(title: Text(l10n.signInTitle)), // ← ИЗМЕНИТЬ
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 32),
            Text(
              l10n.signInTitle, // ← ИЗМЕНИТЬ
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.signInSubtitle, // ← ИЗМЕНИТЬ
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 32),
            
            TextField(
              controller: _usernameCtrl,
              decoration: InputDecoration(
                labelText: l10n.username, // ← ИЗМЕНИТЬ
                prefixIcon: const Icon(Icons.person_outline),
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
            const SizedBox(height: 24),
            
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _login,
                child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(l10n.signIn, style: const TextStyle(fontSize: 16)), // ← ИЗМЕНИТЬ
              ),
            ),
          ],
        ),
      ),
    );
  }
}