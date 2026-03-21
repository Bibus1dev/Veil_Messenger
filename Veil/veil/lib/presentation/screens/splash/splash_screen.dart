import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../auth/welcome_screen.dart';
import '../main/main_screen.dart';
import '../../../services/api_service.dart';
import '../../../services/websocket_service.dart';
import '../../../data/local/local_database.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000), // Медленнее
    )..repeat();
    _checkAuth();
  }

  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  Future<void> _checkAuth() async {
    await Future.delayed(const Duration(seconds: 2));
    
    try {
      final db = LocalDatabase();
      final userId = await db.getCurrentUserId();
      print('🔍 Checking auth... UserId: $userId');
      
      if (userId == null) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          );
        }
        return;
      }

      final userData = await db.getUser(userId);
      final token = userData?['token'] as String?;
      
      print('   Token: ${token != null ? "present" : "null"}');
      print('   Local data found: ${userData != null}');

      if (token == null || userData == null) {
        await _clearAuthData(db);
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const WelcomeScreen()),
          );
        }
        return;
      }

      final apiService = ApiService();
      apiService.setAuthToken(token);
      
      bool serverAvailable = false;
      try {
        final response = await apiService.getMyProfile().timeout(
          const Duration(seconds: 5),
          onTimeout: () => throw Exception('Timeout'),
        );
        
        if (response.statusCode == 200) {
          print('✅ Server available, syncing data...');
          serverAvailable = true;
          
          final freshData = response.data as Map<String, dynamic>;
          await db.syncUserProfile({
            'id': userId,
            'username': freshData['username'],
            'display_name': freshData['display_name'],
            'avatar_url': freshData['avatar_url'],
            'bio': freshData['bio'],
            'status': freshData['status'] ?? 'offline',
            'last_seen': freshData['last_seen'] ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'token': token,
          });
          
          _connectWebSocketInBackground(token, userId);
        }
      } catch (e) {
        print('⚠️ Server unavailable or timeout: $e');
      }

      print('✅ Entering app (server: $serverAvailable)');
      
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainScreen()),
        );
      }
      
    } catch (e) {
      print('❌ Splash error: $e');
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        );
      }
    }
  }

  void _connectWebSocketInBackground(String token, String userId) async {
    try {
      await WebSocketService().connect(token, userId);
    } catch (e) {
      print('⚠️ WebSocket connection failed: $e');
    }
  }

  Future<void> _clearAuthData(LocalDatabase db) async {
    await db.clearUserData();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = Theme.of(context).colorScheme.onSurface.withOpacity(0.3);
    final waveHighlight = Theme.of(context).colorScheme.onSurface.withOpacity(0.9);
    final waveMid = Theme.of(context).colorScheme.onSurface.withOpacity(0.6);

    return Scaffold(
      body: Column(
        children: [
          // Верхняя часть с логотипом по центру
          Expanded(
            child: Center(
              child: Image.asset(
                'assets/icon/veil_startscreen.png',
                width: 200,
                height: 200,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Icon(
                    Icons.shield_outlined,
                    size: 150,
                    color: Theme.of(context).colorScheme.primary,
                  );
                },
              ).animate().scale(
                duration: 800.ms,
                curve: Curves.easeOutBack,
              ).fadeIn(),
            ),
          ),
          
          // Текст в самом низу с той же волной что в ChatsScreen
          Padding(
            padding: const EdgeInsets.only(bottom: 48),
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (context, child) {
                // Тот же принцип: волна уходит за край и появляется снова
                final double wavePosition = -0.7 + (_waveController.value * 2.4);
                
                return ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        baseColor,
                        baseColor,
                        waveMid,
                        waveHighlight,
                        waveMid,
                        baseColor,
                        baseColor,
                      ],
                      stops: [
                        wavePosition - 0.7, // Длинная волна
                        wavePosition - 0.4,
                        wavePosition - 0.15,
                        wavePosition,
                        wavePosition + 0.15,
                        wavePosition + 0.4,
                        wavePosition + 0.7, // Длинная волна
                      ],
                      tileMode: TileMode.clamp, // Без обрывов
                    ).createShader(bounds);
                  },
                  blendMode: BlendMode.srcIn,
                  child: Text(
                    'Secure Messenger',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                );
              },
            ).animate().fadeIn(delay: 600.ms),
          ),
        ],
      ),
    );
  }
}