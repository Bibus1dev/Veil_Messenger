import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/theme/theme_cubit.dart';
import '../../../core/localization/extension.dart';
import '../../../core/localization/language_service.dart';
import '../../../core/localization/restart_widget.dart'; // ← импорт
import 'login_screen.dart';
import 'register_screen.dart';
import '../../../core/localization/extension.dart'; // ← НОВЫЙ ИМПОРТ
import '../../../core/localization/app_localizations.dart'; // Добавьте этот импорт

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  bool _privacyAccepted = false;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _showLanguagePicker() {
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
                l10n.selectLanguage,
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
                  Navigator.pop(context); // закрываем bottom sheet
                  await LanguageService().setLocale('en');
                  if (context.mounted) {
                    // Используем RestartWidget для перезагрузки
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
                  Navigator.pop(context); // закрываем bottom sheet
                  await LanguageService().setLocale('ru');
                  if (context.mounted) {
                    // Используем RestartWidget для перезагрузки
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Theme Toggle and Language Selector
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Language Selector Button
                  IconButton(
                    icon: const Icon(Icons.language),
                    onPressed: _showLanguagePicker,
                    tooltip: l10n.selectLanguage,
                  ),
                  const SizedBox(width: 8),
                  BlocBuilder<ThemeCubit, ThemeState>(
                    builder: (context, state) {
                      return IconButton(
                        icon: Icon(
                          state.isDark ? Icons.light_mode : Icons.dark_mode,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        onPressed: () {
                          context.read<ThemeCubit>().toggleDarkMode();
                        },
                        tooltip: state.isDark ? l10n.lightMode : l10n.darkMode,
                      );
                    },
                  ),
                ],
              ),
            ),

            // Onboarding Pages
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _currentPage = index),
                itemCount: 4,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildIcon(index),
                        const SizedBox(height: 48),
                        Text(
                          _getTitle(index, l10n),
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _getDescription(index, l10n),
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                            height: 1.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),

            // Page Indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                4,
                (index) => Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentPage == index
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade300,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Privacy Policy
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Checkbox(
                    value: _privacyAccepted,
                    onChanged: (value) => setState(() => _privacyAccepted = value!),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showPrivacyPolicy(),
                      child: RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          children: [
                            TextSpan(text: l10n.iHaveReadAndAgree),
                            TextSpan(
                              text: l10n.privacyPolicy,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Buttons
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: _privacyAccepted
                        ? () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const RegisterScreen()),
                          )
                        : null,
                      child: Text(
                        l10n.createAccount,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      onPressed: _privacyAccepted
                        ? () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => const LoginScreen()),
                          )
                        : null,
                      child: Text(
                        l10n.signIn,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getTitle(int index, AppLocalizations l10n) {
    switch (index) {
      case 0:
        return l10n.welcomeTitle;
      case 1:
        return l10n.militaryGradeEncryption;
      case 2:
        return l10n.noDataCollection;
      case 3:
        return l10n.selfDestructingMessages;
      default:
        return '';
    }
  }

  String _getDescription(int index, AppLocalizations l10n) {
    switch (index) {
      case 0:
        return l10n.welcomeDescription1;
      case 1:
        return l10n.welcomeDescription2;
      case 2:
        return l10n.welcomeDescription3;
      case 3:
        return l10n.welcomeDescription4;
      default:
        return '';
    }
  }

  Widget _buildIcon(int index) {
    IconData iconData;
    switch (index) {
      case 0:
        iconData = Icons.shield_outlined;
        break;
      case 1:
        iconData = Icons.lock_outline;
        break;
      case 2:
        iconData = Icons.storage_outlined;
        break;
      case 3:
        iconData = Icons.timer_outlined;
        break;
      default:
        iconData = Icons.circle;
    }
    
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(
        iconData,
        size: 60,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  void _showPrivacyPolicy() {
    final l10n = context.l10n;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.privacyPolicyTitle),
        content: SingleChildScrollView(
          child: Text(l10n.privacyPolicyText),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.close),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() => _privacyAccepted = true);
              Navigator.pop(context);
            },
            child: Text(l10n.iAgree),
          ),
        ],
      ),
    );
  }
}