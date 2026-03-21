// lib/services/websocket_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class WebSocketService {
  static final WebSocketService _instance = WebSocketService._internal();
  factory WebSocketService() => _instance;
  WebSocketService._internal() {
    _initConnectivityListener();
  }

  // ============ КОНФИГУРАЦИЯ ============
  static const String _wsUrl = 'ws://45.132.255.167:8081';
  static const Duration _pingInterval = Duration(seconds: 5);
  static const Duration _pongTimeout = Duration(seconds: 10);
  static const Duration _reconnectDelay = Duration(seconds: 2);
  static const int _maxReconnectAttempts = 10;

  // ============ СОСТОЯНИЕ ============
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _shouldReconnect = true;
  String? _authToken;
  String? _currentUserId;
  int _reconnectAttempts = 0;

  // ============ ТАЙМЕРЫ ============
  Timer? _pingTimer;
  Timer? _pongTimer;
  Timer? _reconnectTimer;

  // ============ СТРИМЫ ============
  final StreamController<Map<String, dynamic>> _messageController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  final StreamController<bool> _connectionController = 
      StreamController<bool>.broadcast();

  // ============ КЕШ ============
  final Map<String, Map<String, dynamic>> _statusCache = {};
  final Set<String> _pendingStatusRequests = {};
  DateTime? _lastPongTime;

  // ============ ГЕТТЕРЫ ============
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String? get currentUserId => _currentUserId;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  // ============ CONNECTIVITY LISTENER ============
  void _initConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((result) {
      print('🌐 Network changed: $result');
      
      if (result != ConnectivityResult.none && !_isConnected && !_isConnecting) {
        if (_authToken != null && _currentUserId != null) {
          print('🌐 Internet back! Attempting reconnect with saved credentials...');
          reconnectNow();
        } else {
          print('🌐 Internet back but no saved credentials, waiting for connect() call');
        }
      }
    });
  }

  // ============ ПОДКЛЮЧЕНИЕ ============
  Future<void> connect(String token, String userId) async {
    if (_isConnecting) {
      print('⚠️ Already connecting, skipping...');
      return;
    }
    
    // Сохраняем credentials ДО проверки соединения, чтобы они были доступны для автопереподключения
    _authToken = token;
    _currentUserId = userId;
    _shouldReconnect = true;
    _reconnectAttempts = 0;

    if (_isConnected) {
      await _cleanupConnection();
    }
    
    _isConnecting = true;

    await _tryConnect();
  }

  

  Future<void> _tryConnect() async {
    try {
      final encodedToken = Uri.encodeComponent(_authToken!);
      final wsUrl = '$_wsUrl/ws?token=$encodedToken';
      
      print('🔌 Connecting to WebSocket... (attempt ${_reconnectAttempts + 1})');
      
      _channel = IOWebSocketChannel.connect(
        wsUrl,
        pingInterval: null,
        connectTimeout: const Duration(seconds: 10),
      );

      _channel!.stream.listen(
        _onMessage,
        onError: _onError,
        onDone: _onDone,
        cancelOnError: false,
      );

      await Future.delayed(const Duration(milliseconds: 800));
      
      if (_channel?.closeCode != null) {
        throw Exception('Connection closed immediately');
      }

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _lastPongTime = DateTime.now();
      
      _startPingTimer();
      
      _connectionController.add(true);
      
      _notify({
        'type': 'connected',
        'user_id': _currentUserId,
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
      
      // Отправляем накопленные pending запросы
      _flushPendingRequests();
      
      print('✅ WebSocket connected');

    } catch (e) {
      print('❌ WebSocket connection error: $e');
      _isConnecting = false;
      _connectionController.add(false);
      _scheduleReconnect();
    }
  }

  // ============ ОБРАБОТЧИКИ ============
  void _onMessage(dynamic data) {
    try {
      String messageStr;
      if (data is String) {
        messageStr = data;
      } else if (data is List<int>) {
        messageStr = utf8.decode(data);
      } else {
        messageStr = data.toString();
      }

      print('📨 WS received: $messageStr');
      
      final json = jsonDecode(messageStr) as Map<String, dynamic>;
      
      if (json['type'] == 'pong') {
        _lastPongTime = DateTime.now();
        _pongTimer?.cancel();
        print('🏓 Pong received');
        return;
      }
      
      if (json['type'] == 'user_status' || json['type'] == 'user_status_response') {
        _cacheUserStatus(json['user_id'], json);
        _pendingStatusRequests.remove(json['user_id']);
      }
      
      // Обработка новых типов сообщений
      _handleSpecialMessageTypes(json);
      
      _notify(json);
      
    } catch (e) {
      print('❌ Error parsing WebSocket message: $e');
    }
  }

  /// Обработка специальных типов сообщений
  void _handleSpecialMessageTypes(Map<String, dynamic> json) {
    final type = json['type'];
    
    switch (type) {
      case 'message_edited':
      case 'message_deleted':
      case 'reaction_added':
      case 'reaction_removed':
        // Эти типы просто прокидываем в UI
        break;
    }
  }

  void _cacheUserStatus(String userId, Map<String, dynamic> status) {
    _statusCache[userId] = {
      ...status,
      'cached_at': DateTime.now().millisecondsSinceEpoch,
    };
  }

  Map<String, dynamic>? getCachedUserStatus(String userId) {
    return _statusCache[userId];
  }

  void _onError(error) {
    print('❌ WebSocket error: $error');
    _handleDisconnect();
  }

  void _onDone() {
    print('🔌 WebSocket closed (onDone)');
    _handleDisconnect();
  }

  // ============ УПРАВЛЕНИЕ СОЕДИНЕНИЕМ ============
  void _handleDisconnect() {
    if (!_isConnected && !_isConnecting) return;
    
    print('⚠️ Handling disconnect...');
    _cleanupConnection();
    _connectionController.add(false);
    _scheduleReconnect();
  }

  Future<void> _cleanupConnection() async {
    _isConnected = false;
    _isConnecting = false;
    
    _pingTimer?.cancel();
    _pongTimer?.cancel();
    
    try {
      await _channel?.sink.close();
    } catch (e) {
      print('Error closing channel: $e');
    }
    _channel = null;
  }

  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) {
      if (!_isConnected) return;
      
      if (_lastPongTime != null) {
        final diff = DateTime.now().difference(_lastPongTime!);
        if (diff > _pongTimeout) {
          print('⏱️ Pong timeout! Last pong: ${diff.inSeconds}s ago');
          _handleDisconnect();
          return;
        }
      }
      
      _sendPing();
    });
  }

  void _sendPing() {
    if (!_isConnected) return;
    
    _send({
      'type': 'ping',
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    
    _pongTimer?.cancel();
    _pongTimer = Timer(_pongTimeout, () {
      print('⏱️ Pong not received in time, reconnecting...');
      _handleDisconnect();
    });
  }

  void _scheduleReconnect() {
    if (!_shouldReconnect) return;
    
    _reconnectAttempts++;
    if (_reconnectAttempts > _maxReconnectAttempts) {
      print('❌ Max reconnect attempts reached, giving up');
      return;
    }
    
    final delay = _reconnectDelay * _reconnectAttempts;
    print('🔄 Scheduling reconnect in ${delay.inSeconds}s (attempt $_reconnectAttempts)');
    
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      if (_authToken != null && _currentUserId != null && _shouldReconnect) {
        _tryConnect();
      }
    });
  }

  // ============ ПУБЛИЧНЫЕ МЕТОДЫ ============
  Future<void> disconnect() async {
    _shouldReconnect = false;
    _reconnectTimer?.cancel();
    await _cleanupConnection();
    print('🔌 WebSocket disconnected manually');
  }

  void reconnectNow() {
    print('🔄 Manual reconnect triggered');
    _shouldReconnect = true;
    _reconnectAttempts = 0;
    _reconnectTimer?.cancel();
    
    if (_isConnected || _isConnecting) {
      _cleanupConnection().then((_) {
        _tryConnect();
      });
    } else {
      _tryConnect();
    }
  }

  // ============ ОТПРАВКА ============
  void _send(Map<String, dynamic> data) {
    if (!_isConnected || _channel == null) {
      print('⚠️ Cannot send, not connected');
      return;
    }
    
    try {
      final jsonStr = jsonEncode(data);
      _channel!.sink.add(jsonStr);
    } catch (e) {
      print('❌ Send error: $e');
      _handleDisconnect();
    }
  }

  // --- API методы ---

  void sendTypingStart(String chatId) {
    _send({
      'type': 'typing_start',
      'chat_id': chatId,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  void sendTypingStop(String chatId) {
    _send({
      'type': 'typing_stop',
      'chat_id': chatId,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  void markMessageRead(String chatId, String messageId) {
    _send({
      'type': 'mark_read',
      'chat_id': chatId,
      'message_id': messageId,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  void markChatRead(String chatId) {
    _send({
      'type': 'mark_read',
      'chat_id': chatId,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  /// Отправка реакции через WebSocket (для мгновенной доставки)
  void sendReaction(String messageId, String reactionType) {
    _send({
      'type': 'add_reaction',
      'message_id': messageId,
      'reaction': reactionType,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  void removeReaction(String messageId) {
    _send({
      'type': 'remove_reaction',
      'message_id': messageId,
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  void getUserStatus(String userId) {
    if (userId.isEmpty) return;
    
    final cached = _statusCache[userId];
    if (cached != null) {
      _notify(cached);
    }
    
    if (_isConnected) {
      _send({
        'type': 'get_user_status',
        'user_id': userId,
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
    } else {
      _pendingStatusRequests.add(userId);
    }
  }

  void requestPendingDelivered() {
    if (!_isConnected) return;
    
    print('📡 Requesting pending delivered messages');
    _send({
      'type': 'get_pending_delivered',
      'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
  }

  void requestStatusForChats(List<String> userIds) {
    print('📡 Requesting status for ${userIds.length} users');
    for (var userId in userIds) {
      if (userId.isNotEmpty) {
        getUserStatus(userId);
      }
    }
  }

  // ============ УТИЛИТЫ ============
  void _notify(Map<String, dynamic> data) {
    if (!_messageController.isClosed) {
      _messageController.add(data);
    }
  }

  /// Отправка накопленных запросов после подключения
  void _flushPendingRequests() {
    if (_pendingStatusRequests.isNotEmpty) {
      print('📡 Flushing ${_pendingStatusRequests.length} pending status requests');
      final requests = Set<String>.from(_pendingStatusRequests);
      _pendingStatusRequests.clear();
      for (var userId in requests) {
        getUserStatus(userId);
      }
    }
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _connectionController.close();
  }
}