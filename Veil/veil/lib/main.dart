import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_cubit.dart';
import 'presentation/screens/splash/splash_screen.dart';
import 'services/websocket_service.dart';
import 'data/local/local_database.dart';
import 'core/localization/app_localizations.dart';
import 'core/localization/language_service.dart';
import 'core/localization/restart_widget.dart';
import '../../../services/sound_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  
  try {
    await LocalDatabase().init();
    print('✅ Local database initialized');
  } catch (e) {
    print('❌ Failed to initialize database: $e');
  }
  
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  runApp(const VeilMessengerApp());
  await SoundService().init();
}

class VeilMessengerApp extends StatelessWidget {
  const VeilMessengerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return RestartWidget(
      child: BlocProvider(
        create: (context) => ThemeCubit()..loadTheme(),
        child: BlocBuilder<ThemeCubit, ThemeState>(
          builder: (context, themeState) {
            return FutureBuilder<Locale>(
              future: LanguageService().getLocale(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return MaterialApp(
                    home: Scaffold(
                      body: Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                  );
                }
                
                return MaterialApp(
                  title: 'Veil Messenger',
                  debugShowCheckedModeBanner: false,
                  theme: AppTheme.getTheme(
                    colorScheme: themeState.colorScheme,
                    isDark: themeState.isDark,
                  ),
                  locale: snapshot.data,
                  supportedLocales: AppLocalizations.supportedLocales,
                  localizationsDelegates: AppLocalizations.localizationsDelegates,
                  home: const SplashScreen(),
                );
              },
            );
          },
        ),
      ),
    );
  }
}