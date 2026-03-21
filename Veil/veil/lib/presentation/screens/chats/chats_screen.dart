import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../data/local/local_database.dart';
import '../../../data/models/chat_model.dart';
import '../../../services/api_service.dart';
import 'dart:math' show sin;
import '../../../services/websocket_service.dart';
import '../Chat/chat_screen.dart';
import '../search/search_screen.dart';
import '../../../core/localization/extension.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/encryption/encryption_service.dart';
import '../../../services/secure_screen_service.dart';

class ChatsScreen extends StatefulWidget {
  const ChatsScreen({super.key});

  @override
  State<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends State<ChatsScreen> 
    with WidgetsBindingObserver, TickerProviderStateMixin {
  
  List<ChatModel> _chats = [];
  final Map<String, Map<String, dynamic>> _userStatuses = {};
  final Map<String, bool> _typingStatus = {};
  
  StreamSubscription? _wsSubscription;
  StreamSubscription? _connectionSubscription;
  
  bool _isLoading = false;
  String? _currentUserId;
  bool _isConnected = false;

  late AnimationController _waveController;
  late AnimationController _statusFadeController;
  late Animation<double> _statusFadeAnimation;

  @override
  void initState() {
    super.initState();

    SecureScreenService.enable();
    WidgetsBinding.instance.addObserver(this);

    _currentUserId = WebSocketService().currentUserId;
    _isConnected = WebSocketService().isConnected;

    // Контроллер для волновой анимации
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..repeat();

    // Контроллер для плавного появления статуса
    _statusFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _statusFadeAnimation = CurvedAnimation(
      parent: _statusFadeController,
      curve: Curves.easeInOut,
    );

    if (_isConnected) {
      _statusFadeController.forward();
    }

    _loadChats();

    _wsSubscription = WebSocketService().messageStream.listen(
      _onWebSocketMessage,
      onError: (error) => print('WebSocket stream error: $error'),
    );

    _connectionSubscription = WebSocketService().connectionStream.listen(
      _onConnectionChanged,
    );

    if (_isConnected) {
      _syncChatsFromServer();
      _requestAllStatuses();
    }
  }

  @override
  void dispose() {
    SecureScreenService.disable();
    WidgetsBinding.instance.removeObserver(this);
    _wsSubscription?.cancel();
    _connectionSubscription?.cancel();
    _waveController.dispose();
    _statusFadeController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      print('🔄 App resumed');
      
      final actuallyConnected = WebSocketService().isConnected;
      
      if (mounted) {
        setState(() {
          _isConnected = actuallyConnected;
        });
      }
      
      if (actuallyConnected) {
        _syncChatsFromServer();
        _requestAllStatuses();
      }
    }
  }

  void _onConnectionChanged(bool connected) {
    print('🔄 Connection state changed: $connected');

    if (mounted) {
      setState(() {
        _isConnected = connected;
      });

      if (connected) {
        _statusFadeController.forward();
      } else {
        _statusFadeController.reverse();
      }

      if (connected) {
        _syncChatsFromServer();
        _requestAllStatuses();

        Future.delayed(const Duration(milliseconds: 500), () {
          WebSocketService().requestPendingDelivered();
        });
      }
    }
  }

  void _onWebSocketMessage(Map<String, dynamic> data) {
    if (!mounted) return;
    
    print('📨 ChatsScreen received: ${data['type']}');

    switch (data['type']) {
      case 'new_message':
        _handleNewMessage(data);
        break;
        
      case 'message_delivered':
        _handleMessageDelivered(data);
        break;
        
      case 'message_read':
        _handleMessageRead(data);
        break;
        
      case 'message_edited':
        _handleMessageEdited(data);
        break;
        
      case 'message_deleted':
        _handleMessageDeleted(data);
        break;
        
      case 'reaction_added':
        _handleReactionAdded(data);
        break;
        
      case 'reaction_removed':
        _handleReactionRemoved(data);
        break;
        
      case 'typing':
        _handleTypingStatus(data);
        break;
        
      case 'user_status':
      case 'user_status_response':
        _handleUserStatus(data);
        break;
        
      case 'chat_read':
        _handleChatRead(data);
        break;
        
      case 'connected':
        if (mounted) {
          setState(() => _isConnected = true);
          Future.delayed(const Duration(milliseconds: 500), () {
            WebSocketService().requestPendingDelivered();
          });
        }
        break;
        
      case 'disconnected':
        if (mounted) setState(() => _isConnected = false);
        break;
    }
  }

  // === ИСПРАВЛЕННЫЙ МЕТОД: обработка нового сообщения ===
  void _handleNewMessage(Map<String, dynamic> data) async {
    final messageData = data['message'] as Map<String, dynamic>?;
    if (messageData == null) return;
    
    final chatId = messageData['chat_id'] as String?;
    final senderId = messageData['sender_id'] as String?;
    final currentUserId = WebSocketService().currentUserId;
    
    if (chatId == null || senderId == null) {
      print('❌ new_message missing chat_id or sender_id');
      return;
    }
    
    final isFromMe = senderId == currentUserId;
    
    // === КРИТИЧНО: Находим именно тот чат, для которого сообщение ===
    final targetChatIndex = _chats.indexWhere((c) => c.id == chatId);
    
    // Если чата нет в списке — загружаем новый чат с сервера
    if (targetChatIndex == -1) {
      print('⚠️ new_message for unknown chat $chatId, loading...');
      await _loadNewChatFromServer(chatId, messageData);
      return;
    }
    
    final targetChat = _chats[targetChatIndex];
    
    // === КРИТИЧНО: Используем ключ именно этого чата для расшифровки ===
    final encryptionKey = targetChat.encryptionKey;
    
    final msgTimestamp = (messageData['timestamp'] as int?) != null 
        ? (messageData['timestamp'] as int) < 10000000000
            ? (messageData['timestamp'] as int) * 1000
            : messageData['timestamp'] as int
        : DateTime.now().millisecondsSinceEpoch;
    
    final messageType = messageData['type'] as String? ?? 'text';
    final encryptedContent = messageData['encrypted_content'] as String?;
    final caption = messageData['caption'] as String?;
    
    String displayLastMessage;
    
    // Расшифровываем ТОЛЬКО если это текст и есть ключ этого чата
    if (messageType == 'text') {
      if (encryptedContent != null && 
          encryptionKey != null && 
          encryptionKey.isNotEmpty) {
        try {
          displayLastMessage = EncryptionService.decryptMessage(
            encryptedContent, 
            encryptionKey
          );
        } catch (e) {
          print('⚠️ Decrypt failed for chat $chatId: $e');
          displayLastMessage = '[Message]';
        }
      } else {
        displayLastMessage = encryptedContent ?? '[Message]';
      }
    } else if (messageType == 'sticker') {
      displayLastMessage = '[Стикер]';
    } else {
      // Медиа — показываем caption или "Media"
      displayLastMessage = caption?.isNotEmpty == true ? caption! : 'Media';
    }
    
    if (!mounted) return;
    
    // === ОБНОВЛЯЕМ ТОЛЬКО ЦЕЛЕВОЙ ЧАТ ===
    setState(() {
      _chats[targetChatIndex] = targetChat.copyWith(
        lastMessage: displayLastMessage,
        lastMessageTime: msgTimestamp,
        lastMessageSenderId: senderId,
        lastMessageStatus: isFromMe ? 'sent' : 'delivered',
        unreadCount: !isFromMe ? targetChat.unreadCount + 1 : targetChat.unreadCount,
      );
      
      // Перемещаем наверх списка
      if (targetChatIndex != 0) {
        final updated = _chats.removeAt(targetChatIndex);
        _chats.insert(0, updated);
      }
    });
    
    // Сохраняем в БД
    await LocalDatabase().insertChat(_chats[0]);
    
    // Уведомление только для чужих сообщений
    if (!isFromMe && mounted) {
      final chatName = _chats[0].displayName ?? _chats[0].username;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.newMessageFrom(chatName))),
      );
    }
  }

  // === НОВЫЙ МЕТОД: загрузка нового чата с сервера ===
  Future<void> _loadNewChatFromServer(
    String chatId, 
    Map<String, dynamic> messageData
  ) async {
    try {
      final serverChats = await ApiService().getMyChats();
      
      final chatData = serverChats.firstWhere(
        (c) => c['id'] == chatId,
        orElse: () => null as dynamic,
      );
      
      if (chatData == null) {
        print('❌ Chat $chatId not found on server');
        return;
      }
      
      final currentUserId = await LocalDatabase().getCurrentUserId();
      final user1Id = chatData['user1_id'] as String?;
      final user2Id = chatData['user2_id'] as String?;
      final otherUserId = (user1Id == currentUserId) ? user2Id : user1Id;
      
      if (otherUserId == null) {
        print('❌ Cannot determine other user for chat $chatId');
        return;
      }
      
      // Получаем профиль другого пользователя
      final userResponse = await ApiService().getUserProfile(otherUserId);
      final userData = userResponse.data;
      
      // Определяем last_message из messageData или chatData
      String lastMessage;
      final msgType = messageData['type'] as String? ?? 'text';
      final encryptionKey = chatData['encryption_key'] as String?;
      
      if (msgType == 'text') {
        final encrypted = messageData['encrypted_content'] as String?;
        if (encrypted != null && encryptionKey != null) {
          try {
            lastMessage = EncryptionService.decryptMessage(encrypted, encryptionKey);
          } catch (e) {
            lastMessage = '[Message]';
          }
        } else {
          lastMessage = '[Message]';
        }
      } else if (msgType == 'sticker') {
        lastMessage = '[Стикер]';
      } else {
        final caption = messageData['caption'] as String?;
        lastMessage = caption?.isNotEmpty == true ? caption! : 'Media';
      }
      
      final newChat = ChatModel(
        id: chatId,
        userId: otherUserId,
        username: userData['username'] ?? '',
        displayName: userData['display_name'],
        avatarUrl: userData['avatar_url'],
        encryptionKey: encryptionKey,
        lastMessage: lastMessage,
        lastMessageTime: (messageData['timestamp'] as int?) != null
            ? (messageData['timestamp'] as int) < 10000000000
                ? (messageData['timestamp'] as int) * 1000
                : messageData['timestamp'] as int
            : null,
        lastMessageSenderId: messageData['sender_id'] as String?,
        lastMessageStatus: 'delivered',
        unreadCount: messageData['sender_id'] != currentUserId ? 1 : 0,
      );
      
      await LocalDatabase().insertChat(newChat);
      
      if (mounted) {
        setState(() {
          _chats.insert(0, newChat);
        });
        
        if (messageData['sender_id'] != currentUserId) {
          final chatName = newChat.displayName ?? newChat.username;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.newMessageFrom(chatName))),
          );
        }
      }
    } catch (e, stack) {
      print('❌ Failed to load new chat: $e');
      print(stack);
    }
  }

  void _handleMessageDelivered(Map<String, dynamic> data) {
    final chatId = data['chat_id'] as String?;
    final messageId = data['message_id'] as String?;
    if (chatId == null) return;
    
    final index = _chats.indexWhere((c) => c.id == chatId);
    if (index == -1) return;
    
    // Обновляем статус только если это наше сообщение
    if (_chats[index].lastMessageSenderId == _currentUserId) {
      setState(() {
        _chats[index] = _chats[index].copyWith(
          lastMessageStatus: 'delivered',
        );
      });
    }
  }

  void _handleMessageRead(Map<String, dynamic> data) {
    final chatId = data['chat_id'] as String?;
    if (chatId == null) return;
    
    final index = _chats.indexWhere((c) => c.id == chatId);
    if (index == -1) return;
    
    if (_chats[index].lastMessageSenderId == _currentUserId) {
      setState(() {
        _chats[index] = _chats[index].copyWith(
          lastMessageStatus: 'read',
        );
      });
    }
  }

  void _handleMessageEdited(Map<String, dynamic> data) {
    final chatId = data['chat_id'] as String?;
    if (chatId == null) return;
    
    // Перезагруваем чаты при редактировании
    _syncChatsFromServer();
  }

  void _handleMessageDeleted(Map<String, dynamic> data) {
    final chatId = data['chat_id'] as String?;
    if (chatId == null) return;
    
    _syncChatsFromServer();
  }

  void _handleReactionAdded(Map<String, dynamic> data) {
    // Реакции не влияют на last_message, можно игнорировать или обновлять
  }

  void _handleReactionRemoved(Map<String, dynamic> data) {
    // Аналогично
  }

  void _handleTypingStatus(Map<String, dynamic> data) {
    final userId = data['user_id'] as String?;
    final chatId = data['chat_id'] as String?;
    final isTyping = data['is_typing'] == true;
    
    if (userId == null || chatId == null) return;
    
    // Находим чат с этим пользователем
    final index = _chats.indexWhere((c) => c.id == chatId);
    if (index == -1) return;
    
    setState(() {
      if (isTyping) {
        _typingStatus[userId] = true;
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() => _typingStatus.remove(userId));
          }
        });
      } else {
        _typingStatus.remove(userId);
      }
    });
  }

  void _handleUserStatus(Map<String, dynamic> data) {
    final userId = data['user_id'] as String?;
    if (userId == null) return;
    
    final status = data['status'] as String? ?? 'offline';
    final lastSeen = data['last_seen'] != null 
        ? (data['last_seen'] as int) * 1000 
        : null;
    
    setState(() {
      _userStatuses[userId] = {
        'status': status,
        'last_seen': lastSeen,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      };
    });
    
    LocalDatabase().updateUserStatus(userId, status, lastSeen ?? 0).catchError((e) {
      print('Error updating user status: $e');
    });
  }

  void _handleChatRead(Map<String, dynamic> data) {
    final chatId = data['chat_id'] as String?;
    final readerId = data['reader_id'] as String?;
    
    if (chatId == null || readerId == null) return;
    if (readerId == _currentUserId) return; // Мы сами прочитали — не обновляем
    
    final index = _chats.indexWhere((c) => c.id == chatId);
    if (index == -1) return;
    
    setState(() {
      _chats[index] = _chats[index].copyWith(
        unreadCount: 0,
      );
    });
  }

  void _requestAllStatuses() {
    if (!WebSocketService().isConnected) return;
    
    final userIds = _chats
        .where((c) => c.userId.isNotEmpty)
        .map((c) => c.userId)
        .toSet()
        .toList();
    
    if (userIds.isNotEmpty) {
      WebSocketService().requestStatusForChats(userIds);
    }
  }

  Future<void> _syncChatsFromServer() async {
    if (!WebSocketService().isConnected) return;
    
    setState(() => _isLoading = true);
    
    try {
      final serverChats = await ApiService().getMyChats();
      final serverChatIds = serverChats.map((c) => c['id'] as String).toSet();
      
      // Удаляем чаты, которых больше нет на сервере
      final localChats = await LocalDatabase().getChats();
      for (var localChat in localChats) {
        if (!serverChatIds.contains(localChat.id)) {
          await LocalDatabase().deleteChat(localChat.id);
        }
      }
      
      // Обновляем или создаем чаты из сервера
      for (var chatData in serverChats) {
        await _updateChatFromServerData(chatData);
      }
      
      await _loadChats();
      
    } catch (e) {
      print('❌ Sync chats error: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateChatFromServerData(Map<String, dynamic> chatData) async {
    final chatId = chatData['id'] as String?;
    if (chatId == null) return;
    
    final encryptionKey = chatData['encryption_key'] as String?;
    
    // Определяем last_message
    String lastMessage = chatData['last_message'] as String? ?? '';
    final lastMsgType = chatData['last_message_type'] as String? ?? 'text';
    final lastCaption = chatData['last_message_caption'] as String?;
    
    // Расшифровываем только текстовые сообщения
    if (lastMsgType == 'text' && lastMessage.isNotEmpty && encryptionKey != null) {
      try {
        lastMessage = EncryptionService.decryptMessage(lastMessage, encryptionKey);
      } catch (e) {
        print('⚠️ Failed to decrypt last_message for chat $chatId: $e');
        lastMessage = '[Message]';
      }
    } else if (lastMsgType == 'sticker') {
      lastMessage = '[Стикер]';
    } else if (lastMsgType != 'text') {
      lastMessage = lastCaption?.isNotEmpty == true ? lastCaption! : 'Media';
    }
    
    // Ограничиваем размер
    if (lastMessage.length > 1000) {
      lastMessage = lastMessage.substring(0, 1000);
    }
    
    final lastMessageTime = chatData['last_message_time'] != null 
        ? (chatData['last_message_time'] as int) < 10000000000
            ? (chatData['last_message_time'] as int) * 1000
            : chatData['last_message_time'] as int
        : null;
    
    // Определяем статус
    String lastMessageStatus = 'sent';
    if (chatData['last_message_read'] == true) {
      lastMessageStatus = 'read';
    } else if (chatData['last_message_delivered'] == true) {
      lastMessageStatus = 'delivered';
    }
    
    final chat = ChatModel(
      id: chatId,
      userId: chatData['user_id'] as String? ?? '',
      username: chatData['username'] as String? ?? '',
      displayName: chatData['display_name'] as String?,
      avatarUrl: chatData['avatar_url'] as String?,
      encryptionKey: encryptionKey,
      lastMessage: lastMessage.isNotEmpty ? lastMessage : null,
      lastMessageTime: lastMessageTime,
      lastMessageSenderId: chatData['last_message_sender'] as String?,
      lastMessageStatus: lastMessageStatus,
      unreadCount: chatData['unread_count'] as int? ?? 0,
    );
    
    await LocalDatabase().insertChat(chat);
  }

  Future<void> _loadChats() async {
    final chats = await LocalDatabase().getChats();
    if (!mounted) return;
    
    setState(() {
      _chats = chats;
      _sortChats();
    });
    
    if (WebSocketService().isConnected) {
      _requestAllStatuses();
    }
  }

  void _sortChats() {
    _chats.sort((a, b) {
      if (a.unreadCount > 0 && b.unreadCount == 0) return -1;
      if (a.unreadCount == 0 && b.unreadCount > 0) return 1;
      return (b.lastMessageTime ?? 0).compareTo(a.lastMessageTime ?? 0);
    });
  }

  Future<void> _onRefresh() async {
    final l10n = context.l10n;
    
    setState(() {
      _isConnected = WebSocketService().isConnected;
    });
    
    if (!WebSocketService().isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.connectionNoConnection)),
      );
      return;
    }
    
    await _syncChatsFromServer();
    _requestAllStatuses();
  }

  String _formatLastSeen(int? timestamp) {
    final l10n = context.l10n;
    if (timestamp == null) return l10n.statusOffline;
    
    final now = DateTime.now();
    final lastSeen = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final diff = now.difference(lastSeen);
    
    if (diff.inMinutes < 1) return l10n.statusJustNow;
    if (diff.inMinutes < 60) return l10n.statusMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.statusHoursAgo(diff.inHours);
    if (diff.inDays < 7) return l10n.statusDaysAgo(diff.inDays);
    
    return '${lastSeen.day}/${lastSeen.month}/${lastSeen.year}';
  }

  String _getStatusText(String userId) {
    final l10n = context.l10n;
    if (_typingStatus.containsKey(userId)) return l10n.statusTyping;
    
    final status = _userStatuses[userId];
    if (status == null) return l10n.statusOffline;
    
    final statusStr = status['status'] as String?;
    if (statusStr == 'online') return l10n.statusOnline;
    if (statusStr == 'away') return l10n.statusAway;
    
    return _formatLastSeen(status['last_seen']);
  }

  Color _getStatusColor(String userId) {
    if (_typingStatus.containsKey(userId)) return Colors.green;
    
    final status = _userStatuses[userId];
    if (status == null) return Colors.grey;
    
    switch (status['status']) {
      case 'online': return Colors.green;
      case 'away': return Colors.orange;
      default: return Colors.grey;
    }
  }

  String _formatTime(int? timestamp) {
    if (timestamp == null) return '';
    
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    
    if (date.day == now.day && date.month == now.month && date.year == now.year) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    if (date.year == now.year) {
      return '${date.day}/${date.month}';
    }
    return '${date.day}/${date.month}/${date.year}';
  }

  IconData _getMessageStatusIcon(String? status) {
    switch (status) {
      case 'sending': return Icons.access_time;
      case 'sent': return Icons.check;
      case 'delivered': return Icons.done_all;
      case 'read': return Icons.done_all;
      case 'failed': return Icons.error;
      default: return Icons.check;
    }
  }

  Color _getMessageStatusColor(String? status) {
    switch (status) {
      case 'read': return Colors.blue;
      case 'failed': return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getLastMessageDisplayText(ChatModel chat) {
    final l10n = context.l10n;
    
    if (chat.lastMessage == null || chat.lastMessage!.isEmpty) {
      return l10n.messageNoMessages;
    }
    
    final lastMessage = chat.lastMessage!;
    
    if (lastMessage == 'Media' || lastMessage == '[Медиа]') {
      return l10n.messageMedia;
    }
    
    if (lastMessage == '[Стикер]') {
      return 'Стикер';
    }
    
    // Если это зашифрованный JSON — показываем Media
    if (lastMessage.length > 50 && 
        (lastMessage.startsWith('[') || lastMessage.startsWith('{')) &&
        lastMessage.contains('"encrypted_content"')) {
      return l10n.messageMedia;
    }
    
    return lastMessage;
  }

  bool _isLastMessageMedia(ChatModel chat) {
    if (chat.lastMessage == null) return false;
    
    final msg = chat.lastMessage!;
    return msg == 'Media' || 
           msg == '[Медиа]' || 
           msg == '[Стикер]' ||
           (msg.length > 50 && 
            (msg.startsWith('[') || msg.startsWith('{')) &&
            msg.contains('"encrypted_content"'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseColor = colorScheme.onSurface.withOpacity(0.3);
    final waveHighlight = colorScheme.onSurface.withOpacity(0.9);
    final waveMid = colorScheme.onSurface.withOpacity(0.6);

    return Scaffold(
      backgroundColor: isDark ? Colors.black : colorScheme.surface,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: isDark ? Colors.black : colorScheme.surface,
        titleSpacing: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
        title: Padding(
          padding: const EdgeInsets.only(left: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.tabChats,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2),
              AnimatedBuilder(
                animation: _waveController,
                builder: (context, child) {
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
                          wavePosition - 0.5,
                          wavePosition - 0.3,
                          wavePosition - 0.1,
                          wavePosition,
                          wavePosition + 0.1,
                          wavePosition + 0.3,
                          wavePosition + 0.5,
                        ],
                        tileMode: TileMode.clamp,
                      ).createShader(bounds);
                    },
                    blendMode: BlendMode.srcIn,
                    child: Text(
                      _isConnected ? l10n.connectionConnected : l10n.connectionDisconnected,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
          ),
        ],
      ),
      body: _chats.isEmpty
          ? _buildEmptyState(context)
          : RefreshIndicator(
              onRefresh: _onRefresh,
              child: ListView.builder(
                itemCount: _chats.length,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemBuilder: (context, index) => _buildChatTile(_chats[index]),
              ),
            ),
    );
  }

  Widget _buildChatTile(ChatModel chat) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    final isTyping = _typingStatus.containsKey(chat.userId);
    final displayName = chat.displayName ?? chat.username;
    final isMe = chat.lastMessageSenderId == _currentUserId;
    final isMedia = _isLastMessageMedia(chat);
    
    return Dismissible(
      key: Key(chat.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        _showDeleteOptions(chat);
        return false;
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Stack(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: colorScheme.primaryContainer,
              backgroundImage: chat.avatarUrl?.isNotEmpty == true
                  ? NetworkImage('http://45.132.255.167:8080${chat.avatarUrl}')
                  : null,
              child: chat.avatarUrl?.isNotEmpty != true
                  ? Text(
                      displayName[0].toUpperCase(),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    )
                  : null,
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: _getStatusColor(chat.userId),
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.surface, width: 2),
                ),
              ),
            ),
          ],
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                displayName,
                style: const TextStyle(
                  fontWeight: FontWeight.w600, 
                  fontSize: 16,
                ),
              ),
            ),
            if (chat.lastMessageTime != null)
              Text(
                _formatTime(chat.lastMessageTime!),
                style: TextStyle(
                  fontSize: 12,
                  color: chat.unreadCount > 0 
                      ? colorScheme.primary 
                      : Colors.grey.shade500,
                ),
              ),
          ],
        ),
        subtitle: Row(
          children: [
            if (isMe && chat.lastMessage != null && !isMedia)
              Icon(
                _getMessageStatusIcon(chat.lastMessageStatus),
                size: 14,
                color: _getMessageStatusColor(chat.lastMessageStatus),
              ),
            if (isMedia)
              Icon(
                Icons.photo,
                size: 14,
                color: isTyping ? Colors.green : Colors.grey.shade600,
              ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                isTyping 
                    ? l10n.statusTyping 
                    : _getLastMessageDisplayText(chat),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isTyping ? Colors.green : Colors.grey.shade600,
                  fontWeight: isTyping || chat.unreadCount > 0 
                      ? FontWeight.w500 
                      : FontWeight.normal,
                  fontStyle: isTyping ? FontStyle.italic : null,
                ),
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (chat.unreadCount > 0)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${chat.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
        onTap: () async {
          await LocalDatabase().resetUnreadCount(chat.id);
          if (!mounted) return;
          
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => ChatScreen(chat: chat)),
          ).then((_) {
            if (WebSocketService().isConnected) {
              _syncChatsFromServer();
            } else {
              _loadChats();
            }
          });
        },
      ),
    );
  }

  void _showDeleteOptions(ChatModel chat) {
    final l10n = context.l10n;
    final isOnline = WebSocketService().isConnected;
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.chatDeleteTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${l10n.chatDeleteTitle} ${chat.displayName ?? chat.username}?'),
            const SizedBox(height: 8),
            Text(
              '• ${l10n.chatDeleteForBoth}: removes chat for both users',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            Text(
              '• ${l10n.chatDeleteForMe}: removes only for you',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.chatDeleteCancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _deleteChatForMe(chat);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.orange),
            child: Text(l10n.chatDeleteForMe),
          ),
          if (isOnline)
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _deleteChatPublicly(chat);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.chatDeleteForBoth),
            ),
        ],
      ),
    );
  }

  Future<void> _deleteChatForMe(ChatModel chat) async {
    final l10n = context.l10n;
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );
      
      await LocalDatabase().deleteChatMessages(chat.id);
      await ApiService().hideChat(chat.id);
      await LocalDatabase().deleteChat(chat.id);
      
      if (mounted) {
        Navigator.pop(context);
        
        setState(() {
          _chats.removeWhere((c) => c.id == chat.id);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.chatDeleteForMe)),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.errorGeneric}: $e')),
      );
    }
  }

  Future<void> _deleteChatPublicly(ChatModel chat) async {
    final l10n = context.l10n;
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(child: CircularProgressIndicator()),
      );
      
      await ApiService().deleteChat(chat.id);
      await LocalDatabase().deleteChat(chat.id);
      
      if (mounted) {
        Navigator.pop(context);
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.chatDeleteConfirm(chat.displayName ?? chat.username)),
            duration: const Duration(seconds: 2),
          ),
        );
        
        _loadChats();
      }
    } on DioException catch (e) {
      if (mounted) Navigator.pop(context);
      
      if (e.response?.statusCode == 401) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.errorSessionExpired)),
        );
      } else if (e.response?.statusCode == 404) {
        await LocalDatabase().deleteChat(chat.id);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat already deleted on server, removed locally')),
        );
        _loadChats();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l10n.errorNetwork}: $e')),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${l10n.errorGeneric}: $e')),
      );
    }
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = context.l10n;
    final colorScheme = Theme.of(context).colorScheme;
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 16),
          Text(
            l10n.chatEmptyTitle,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.chatEmptySubtitle,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
            icon: const Icon(Icons.search),
            label: Text(l10n.chatEmptyButton),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}