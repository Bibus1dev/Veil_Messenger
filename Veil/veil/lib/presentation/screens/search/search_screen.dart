import 'dart:async';
import 'package:flutter/material.dart';
import '../../../services/api_service.dart';
import '../../../data/models/chat_model.dart';
import '../../../data/local/local_database.dart';
import '../chat/chat_screen.dart';
import '../../../services/websocket_service.dart';
import '../../../core/localization/extension.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchCtrl = TextEditingController();
  final _focusNode = FocusNode();
  List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  bool _hasSearched = false;
  Timer? _debounceTimer;
  String? _error;
  
  // Храним ID пользователей, с которыми сейчас создается чат
  final Set<String> _initiatingChatIds = {};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchCtrl.text.trim();
    
    _debounceTimer?.cancel();
    
    if (query.isEmpty) {
      setState(() {
        _users = [];
        _hasSearched = false;
        _error = null;
      });
      return;
    }

    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _performSearch(query);
    });
  }

  Future<void> _performSearch(String query) async {
    if (query.isEmpty) return;
    
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final users = await ApiService().searchUsers(query);
      
      if (mounted) {
        setState(() {
          _users = users;
          _hasSearched = true;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to search: $e';
          _loading = false;
        });
      }
    }
  }

  Future<void> _startChat(Map<String, dynamic> user) async {
    final userId = user['id'].toString();
    
    // Предотвращаем повторное нажатие
    if (_initiatingChatIds.contains(userId)) return;

    setState(() {
      _initiatingChatIds.add(userId);
    });

    try {
      final existingChat = await LocalDatabase().getChatByUserId(userId);
      
      if (existingChat != null) {
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => ChatScreen(chat: existingChat)),
          );
        }
        return;
      }
      
      final tempChat = ChatModel(
        id: 'temp_${userId}_${DateTime.now().millisecondsSinceEpoch}',
        userId: userId,
        username: user['username'] ?? 'Unknown',
        displayName: user['display_name'] ?? user['username'] ?? 'Unknown',
        avatarUrl: user['avatar_url'],
        encryptionKey: '',
        lastMessage: null,
        lastMessageTime: DateTime.now().millisecondsSinceEpoch,
        lastMessageSenderId: null,
        lastMessageStatus: null,
        unreadCount: 0,
      );
      
      await LocalDatabase().insertChat(tempChat);
      WebSocketService().getUserStatus(userId);
      
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => ChatScreen(
              chat: tempChat,
              isNewChat: true,
              otherUserId: userId,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${context.l10n.errorGeneric}: $e'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _initiatingChatIds.remove(userId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        title: _buildSearchField(colorScheme, l10n),
      ),
      body: _buildBody(colorScheme),
    );
  }

  Widget _buildSearchField(ColorScheme colorScheme, dynamic l10n) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _searchCtrl,
        focusNode: _focusNode,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: l10n.searchHint,
          hintStyle: TextStyle(
            color: colorScheme.onSurfaceVariant.withOpacity(0.7),
            fontSize: 16,
          ),
          prefixIcon: Icon(
            Icons.search,
            color: colorScheme.onSurfaceVariant,
            size: 22,
          ),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                  onPressed: () {
                    _searchCtrl.clear();
                    _focusNode.requestFocus();
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
        ),
        style: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 16,
        ),
        onSubmitted: (_) => _performSearch(_searchCtrl.text.trim()),
      ),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    final l10n = context.l10n;
    
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: colorScheme.error.withOpacity(0.6),
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(
                  color: colorScheme.error,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => _performSearch(_searchCtrl.text.trim()),
                icon: const Icon(Icons.refresh),
                label: Text(l10n.actionRetry),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading && !_hasSearched) {
      return Center(
        child: CircularProgressIndicator(
          color: colorScheme.primary,
        ),
      );
    }

    if (!_hasSearched && _users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.search,
              size: 80,
              color: colorScheme.onSurfaceVariant.withOpacity(0.2),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.searchTitle,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Text(
                l10n.searchEmptyHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_hasSearched && _users.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_search_outlined,
              size: 80,
              color: colorScheme.onSurfaceVariant.withOpacity(0.2),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.searchEmpty,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.searchEmptyHint,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _users.length,
      itemBuilder: (context, index) {
        final user = _users[index];
        return _buildUserCard(user);
      },
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    
    final userId = user['id'].toString();
    final username = user['username'] ?? 'Unknown';
    final displayName = user['display_name'] ?? username;
    final avatarUrl = user['avatar_url'];
    final status = user['status'] ?? 'offline';
    final initial = username.isNotEmpty ? username[0].toUpperCase() : '?';
    
    // Проверяем, находится ли этот пользователь в процессе создания чата
    final isInitiating = _initiatingChatIds.contains(userId);

    Color statusColor;
    String statusText;
    switch (status) {
      case 'online':
        statusColor = Colors.green;
        statusText = l10n.statusOnline;
        break;
      case 'away':
        statusColor = Colors.orange;
        statusText = l10n.statusAway;
        break;
      default:
        statusColor = Colors.grey;
        statusText = l10n.statusOffline;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        // Легкая тень для объема (опционально, можно убрать для плоской темы)
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isInitiating ? null : () => _startChat(user),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Аватар
                Stack(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: avatarUrl != null && avatarUrl.isNotEmpty
                            ? Image.network(
                                'http://45.132.255.167:8080$avatarUrl',
                                fit: BoxFit.cover,
                                errorBuilder: (c, o, s) => _buildInitial(initial, colorScheme),
                              )
                            : _buildInitial(initial, colorScheme),
                      ),
                    ),
                    // Индикатор статуса
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: statusColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.surfaceContainerLow,
                            width: 2.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                
                // Информация о пользователе
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '@$username',
                            style: TextStyle(
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            width: 3,
                            height: 3,
                            decoration: BoxDecoration(
                              color: colorScheme.onSurfaceVariant.withOpacity(0.5),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 13,
                              color: statusColor,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(width: 8),
                
                // Кнопка действия
                FilledButton.icon(
                  onPressed: isInitiating ? null : () => _startChat(user),
                  icon: isInitiating 
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colorScheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: Text(l10n.searchStartChat),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInitial(String initial, ColorScheme colorScheme) {
    return Center(
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}