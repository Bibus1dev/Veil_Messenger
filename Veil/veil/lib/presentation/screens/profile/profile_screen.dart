import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/api_service.dart';
import '../../../data/local/local_database.dart';
import '../../../services/websocket_service.dart';
import '../auth/welcome_screen.dart';
import '../../../core/localization/extension.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _MenuItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  _MenuItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class _ProfileScreenState extends State<ProfileScreen> {
  Map<String, dynamic>? _userData;
  bool _isLoading = true;
  String? _currentUserId;
  bool _isDonationVisible = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadDonationVisibility();
  }

  Future<void> _loadDonationVisibility() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isDonationVisible = prefs.getBool('donation_visible') ?? true;
    });
  }

  Future<void> _hideDonation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('donation_visible', false);
    setState(() {
      _isDonationVisible = false;
    });
    
    if (mounted) {
      _showHiddenNotification(context);
    }
  }

  void _showHiddenNotification(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.check_circle_outline,
              size: 48,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.donationHiddenTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.donationHiddenMessage,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: Text(l10n.gotIt),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    
    try {
      final db = LocalDatabase();
      _currentUserId = await db.getCurrentUserId();
      
      if (_currentUserId == null) {
        setState(() => _isLoading = false);
        return;
      }

      var localData = await db.getUser(_currentUserId!);
      
      if (localData != null) {
        setState(() {
          _userData = localData;
          _isLoading = false;
        });
      }

      try {
        final response = await ApiService().getMyProfile();
        if (response.statusCode == 200) {
          final serverData = response.data as Map<String, dynamic>;
          
          await db.syncUserProfile({
            'id': _currentUserId!,
            'username': serverData['username'],
            'display_name': serverData['display_name'],
            'avatar_url': serverData['avatar_url'],
            'bio': serverData['bio'],
            'status': serverData['status'] ?? 'offline',
            'last_seen': serverData['last_seen'] ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'token': localData?['token'],
          });
          
          final freshData = await db.getUser(_currentUserId!);
          
          setState(() {
            _userData = freshData;
            _isLoading = false;
          });
        }
      } catch (e) {
        print('Failed to fetch profile from server: $e');
      }
    } catch (e) {
      print('Error loading user data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final db = LocalDatabase();
    
    await WebSocketService().disconnect();
    await db.clearUserData();
    
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
        (route) => false,
      );
    }
  }

  Future<void> _openDonation() async {
    final url = Uri.parse('https://yoomoney.ru/fundraise/1G4LAL62NO3.260224');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  String get _displayName {
    if (_userData == null) return 'Loading...';
    final displayName = _userData!['display_name'] as String?;
    final username = _userData!['username'] as String? ?? 'Unknown';
    return (displayName != null && displayName.isNotEmpty) ? displayName : username;
  }

  String get _username {
    return _userData?['username'] as String? ?? 'Unknown';
  }

  String? get _avatarUrl {
    final url = _userData?['avatar_url'] as String?;
    return (url != null && url.isNotEmpty) ? url : null;
  }

  String get _bio {
    return _userData?['bio'] as String? ?? 'No bio yet';
  }

  String get _initials {
    final name = _displayName;
    if (name.length >= 2) {
      return name.substring(0, 2).toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Scaffold(
      backgroundColor: isDark ? Colors.black : colorScheme.surface,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUserData,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    expandedHeight: 160,
                    floating: false,
                    pinned: true,
                    backgroundColor: isDark ? Colors.black : colorScheme.surface,
                    flexibleSpace: FlexibleSpaceBar(
                      background: Container(
                        color: isDark ? Colors.black : colorScheme.surface,
                        child: SafeArea(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 90,
                                height: 90,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isDark ? Colors.grey.shade800 : Colors.white,
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: _avatarUrl != null
                                      ? Image.network(
                                          'http://45.132.255.167:8080  $_avatarUrl',
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) {
                                            return _buildDefaultAvatar(colorScheme);
                                          },
                                        )
                                      : _buildDefaultAvatar(colorScheme),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          Text(
                            _displayName,
                            style: const TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '@$_username',
                            style: TextStyle(
                              fontSize: 16,
                              color: colorScheme.onSurface.withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 8),
                          
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              _bio,
                              style: TextStyle(
                                fontSize: 14,
                                color: colorScheme.onSurface.withOpacity(0.8),
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Colors.green,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  l10n.statusOnline,
                                  style: TextStyle(
                                    color: colorScheme.onPrimaryContainer,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          
                          _buildMenuCard(colorScheme),
                          const SizedBox(height: 24),
                          
                          if (_isDonationVisible) ...[
                            _buildDonationCard(colorScheme, isDark),
                            const SizedBox(height: 24),
                          ],
                          
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _logout,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isDark ? Colors.red.shade900 : Colors.red.shade50,
                                foregroundColor: isDark ? Colors.red.shade200 : Colors.red,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              icon: const Icon(Icons.logout),
                              label: Text(
                                l10n.profileLogout,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDefaultAvatar(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.primary,
      child: Center(
        child: Text(
          _initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildMenuCard(ColorScheme colorScheme) {
    final l10n = context.l10n;
    
    final menuItems = [
      _MenuItem(
        icon: Icons.edit,
        title: l10n.profileEdit,
        subtitle: l10n.profileEditSubtitle,
        onTap: () {},
      ),
      _MenuItem(
        icon: Icons.privacy_tip,
        title: l10n.profilePrivacy,
        subtitle: l10n.profilePrivacySubtitle,
        onTap: () {},
      ),
    ];

    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outline.withOpacity(0.2),
        ),
      ),
      child: Column(
        children: menuItems.asMap().entries.map((entry) {
          final index = entry.key;
          final item = entry.value;
          final isLast = index == menuItems.length - 1;
          
          return Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(item.icon, color: colorScheme.primary),
                ),
                title: Text(
                  item.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  item.subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurface.withOpacity(0.6),
                  ),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurface.withOpacity(0.4),
                ),
                onTap: item.onTap,
              ),
              if (!isLast)
                Divider(
                  height: 1,
                  indent: 72,
                  color: colorScheme.outline.withOpacity(0.2),
                ),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDonationCard(ColorScheme colorScheme, bool isDark) {
    final l10n = context.l10n;
    
    return Card(
      elevation: 0,
      color: isDark ? colorScheme.surface.withOpacity(0.5) : Colors.orange.shade50,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isDark ? Colors.orange.shade700.withOpacity(0.3) : Colors.orange.shade200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDark 
                      ? Colors.orange.shade900.withOpacity(0.3)
                      : Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.favorite,
                    color: isDark ? Colors.orange.shade300 : Colors.orange.shade700,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.donationTitle,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.donationSubtitle,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _hideDonation,
                  icon: Icon(
                    Icons.close,
                    size: 20,
                    color: colorScheme.onSurface.withOpacity(0.5),
                  ),
                  tooltip: l10n.hideDonation,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _openDonation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isDark ? Colors.orange.shade700 : Colors.orange.shade600,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.favorite_border, size: 20),
                label: Text(
                  l10n.supportProject,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}