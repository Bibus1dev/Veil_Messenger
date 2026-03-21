import 'package:flutter/material.dart';
import '../chats/chats_screen.dart';
import '../settings/settings_screen.dart';
import '../profile/profile_screen.dart';
import '../../../core/localization/extension.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  
  late final List<Widget> _screens;
  late final List<_NavItem> _items;

  @override
  void initState() {
    super.initState();
    _initNavItems();
  }

  void _initNavItems() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _screens = [
            const ChatsScreen(),
            const Placeholder(), // Contacts
            const SettingsScreen(),
            const ProfileScreen(),
          ];

          final l10n = context.l10n;
          _items = [
            _NavItem(
              icon: Icons.chat_bubble_outline, 
              activeIcon: Icons.chat_bubble, 
              label: l10n.tabChats,
            ),
            _NavItem(
              icon: Icons.contacts_outlined, 
              activeIcon: Icons.contacts, 
              label: l10n.tabContacts, 
              disabled: true,
            ),
            _NavItem(
              icon: Icons.settings_outlined, 
              activeIcon: Icons.settings, 
              label: l10n.tabSettings,
            ),
            _NavItem(
              icon: Icons.person_outline, 
              activeIcon: Icons.person, 
              label: l10n.tabProfile,
            ),
          ];
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    
    if (_items.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        body: _screens[_currentIndex],
        // ← ИСПРАВЛЕНО: используем SafeArea для правильных отступов
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.only(left: 32, right: 32, bottom: 16),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: List.generate(_items.length, (index) {
                  final item = _items[index];
                  final isActive = _currentIndex == index;
                  final isDisabled = item.disabled;
                  
                  return GestureDetector(
                    onTap: isDisabled ? null : () => setState(() => _currentIndex = index),
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive && !isDisabled
                            ? colorScheme.primaryContainer.withOpacity(0.3)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: AnimatedScale(
                        scale: isActive ? 1.05 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 200),
                              transitionBuilder: (child, animation) {
                                return ScaleTransition(
                                  scale: animation,
                                  child: child,
                                );
                              },
                              child: Icon(
                                isActive ? item.activeIcon : item.icon,
                                key: ValueKey(isActive),
                                color: isDisabled 
                                    ? Colors.grey 
                                    : isActive 
                                        ? colorScheme.primary 
                                        : colorScheme.onSurfaceVariant,
                                size: 22,
                              ),
                            ),
                            const SizedBox(height: 2),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                                color: isDisabled 
                                    ? Colors.grey 
                                    : isActive 
                                        ? colorScheme.primary 
                                        : colorScheme.onSurfaceVariant,
                              ),
                              child: Text(item.label),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final bool disabled;

  _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.disabled = false,
  });
}