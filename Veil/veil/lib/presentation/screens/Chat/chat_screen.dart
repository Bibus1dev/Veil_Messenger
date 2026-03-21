import 'package:flutter/gestures.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import '../../widgets/voice_preview_sheet.dart';
import '../../widgets/video_note_preview_sheet.dart';
import 'package:dio/dio.dart';
import 'package:audio_waveforms/audio_waveforms.dart' as aw;
import 'package:camera/camera.dart';
import 'package:video_player/video_player.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:just_audio/just_audio.dart';

import '../../../services/sound_service.dart';
import '../../widgets/voice_preview_sheet.dart';
import '../../widgets/video_note_preview_sheet.dart';
import '../../widgets/sticker_store_sheet.dart';

import '../../../data/models/chat_model.dart';
import '../../../data/models/message_model.dart';
import '../../../data/models/sticker_pack_model.dart';
import '../../../data/local/local_database.dart';
import '../../../core/encryption/encryption_service.dart';
import '../../../core/localization/extension.dart';
import '../../../core/localization/language_service.dart';
import '../../../services/api_service.dart';
import '../../../services/websocket_service.dart';
import '../../../services/media_service.dart';
import '../../../services/sticker_service.dart';
import '../../../services/secure_screen_service.dart';
import '../../../services/wallpaper_service.dart';

import '../media/media_viewer_screen.dart';
import '../chats/chats_screen.dart';
import '../../widgets/video_note_preview_sheet.dart' as video;

class AttachedMedia {
  final File file;
  final MediaType type;
  final String? thumbnail;
  
  AttachedMedia({
    required this.file,
    required this.type,
    this.thumbnail,
  });
}

class ChatScreen extends StatefulWidget {
  final ChatModel chat;
  final bool isNewChat;
  final String? otherUserId;

  const ChatScreen({
    super.key, 
    required this.chat,
    this.isNewChat = false,
    this.otherUserId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageCtrl = TextEditingController();
  final List<MessageModel> _messages = [];
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
    bool _showStickersTab = false;
  final StickerService _stickerService = StickerService();
  List<StickerPackModel> _installedPacks = [];
  List<StickerModel> _currentStickers = [];
   late final VoidCallback _stickerServiceListener;
   
  int _selectedPackIndex = 0;
  bool _loadingStickers = false;
  
  String? _encryptionKey; // Nullable, чтобы отслеживать неинициализированное состояние
  bool _isLoading = false;
  String? _currentUserId;
  
  bool _isOtherTyping = false;
  String? _otherUserStatus;
  int? _otherUserLastSeen;
  Timer? _typingDebounceTimer;
  StreamSubscription? _wsSubscription;

  String? _wallpaperPath;
double _wallpaperOpacity = 0.5;
double _wallpaperBlur = 0.0;
  
  final Map<String, String> _tempIdToRealId = {};
  final Map<String, String> _realIdToTempId = {};

  bool _showEmojiPicker = false;
  
  final List<String> _emojis = [
    '😀', '😃', '😄', '😁', '😆', '😅', '😂', '🤣', '😊', '😇',
    '🙂', '🙃', '😉', '😌', '😍', '🥰', '😘', '😗', '😙', '😚',
    '😋', '😛', '😝', '😜', '🤪', '🤨', '🧐', '🤓', '😎', '🥸',
    '🤩', '🥳', '😏', '😒', '😞', '😔', '😟', '😕', '🙁', '☹️',
    '😣', '😖', '😫', '😩', '🥺', '😢', '😭', '😤', '😠', '😡',
    '🤬', '🤯', '😳', '🥵', '🥶', '😱', '😨', '😰', '😥', '😓',
    '🤗', '🤔', '🤭', '🤫', '🤥', '😶', '😐', '😑', '😬', '🙄',
    '😯', '😦', '😧', '😮', '😲', '🥱', '😴', '🤤', '😪', '😵',
    '🤐', '🥴', '🤢', '🤮', '🤧', '😷', '🤒', '🤕', '🤑', '🤠',
    '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '🤎', '💔',
    '👍', '👎', '👏', '🙌', '🤝', '🤞', '✌️', '🤟', '🤘', '👌',
  ];

  final List<Map<String, dynamic>> _reactionTypes = [
    {'emoji': '👍', 'name': 'like'},
    {'emoji': '👎', 'name': 'dislike'},
    {'emoji': '❤️', 'name': 'heart'},
    {'emoji': '🔥', 'name': 'fire'},
    {'emoji': '💔', 'name': 'broken_heart'},
    {'emoji': '😂', 'name': 'laugh'},
    {'emoji': '😢', 'name': 'cry'},
  ];
  
  final Map<String, Map<String, dynamic>> _pendingStatusUpdates = {};
  
  bool _isCompressing = false;
  bool _disableCompression = false;
  String? _compressingProgress;

  // ОСТАВИТЬ ТОЛЬКО ЭТИ ПОЛЯ:
final Map<String, aw.PlayerController> _voicePlayers = {};
final Map<String, VideoPlayerController> _videoNoteControllers = {};

  
  List<AttachedMedia> _attachedMediaList = [];

  MessageModel? _editingMessage;
  MessageModel? _replyingToMessage;

  bool _isCreatingChat = false;

     @override
void initState() {
  super.initState();
  SecureScreenService.enable();
  
  // НЕ инициализируем ключ здесь, делаем это в _initializeEncryptionKey
  _encryptionKey = null; // Явно сбрасываем
  
  _loadCurrentUser();
  _initializeEncryptionKey(); // Новый метод
  _loadMessages();
  _stickerService.init();
  _loadInstalledPacks();
  SoundService().init();
  
  
  _stickerServiceListener = () {
    if (mounted) {
      print('🔄 ChatScreen: StickerService changed, reloading packs...');
      _loadInstalledPacks();
    }
  };
  
  _stickerService.addListener(_stickerServiceListener);
  _stickerSubscription = _stickerService.onChange.listen((_) {
    if (mounted) {
      print('🔄 ChatScreen: Stream update, reloading packs...');
      _loadInstalledPacks();
    }
  });
  
  if (!widget.isNewChat && WebSocketService().isConnected) {
    _syncMessagesFromServer().then((_) => _markIncomingAsRead());
  }
  
  _wsSubscription = WebSocketService().messageStream.listen(_onWebSocketMessage);
  _requestUserStatus();
  
  MediaService().cleanupTempFiles();
  
  _focusNode.addListener(() {
    if (_focusNode.hasFocus) {
      setState(() {
        _showEmojiPicker = false;
        _showStickersTab = false;
      });
    }
  });
}
Future<void> _initializeEncryptionKey() async {
  if (widget.isNewChat) {
    // Для нового чата ключ будет получен после создания на сервере
    setState(() => _encryptionKey = '');
    return;
  }
  
  // Пробуем получить ключ из widget
  String? key = widget.chat.encryptionKey;
  
  // Если нет в widget — ищем в локальной БД (актуальнее)
  if (key == null || key.isEmpty) {
    final dbChat = await LocalDatabase().getChat(widget.chat.id);
    key = dbChat?.encryptionKey;
    print('🔑 Loaded key from DB: ${key != null ? "found" : "not found"}');
  }
  
  // Если всё ещё нет — генерируем (fallback для совместимости)
  if (key == null || key.isEmpty) {
    key = EncryptionService.generateKey();
    print('⚠️ Generated new key (chat should exist)');
  }
  
  if (mounted) {
    setState(() => _encryptionKey = key);
  }
}

  // === ДОБАВЬ ЭТО ПОЛЕ в начало класса _ChatScreenState ===
  StreamSubscription? _stickerSubscription;

  // ДОБАВЛЕННЫЙ МЕТОД: запрос статуса пользователя
  void _requestUserStatus() {
    if (widget.isNewChat) return;
    WebSocketService().getUserStatus(widget.chat.userId);
  }

 Future<void> _loadInstalledPacks() async {
    print('📦 ChatScreen: Loading installed packs...');
    
    final packs = await _stickerService.getStickerPacks();
    final installed = packs.where((p) => p.isInstalled).toList();
    
    print('📦 Found ${installed.length} installed packs');
    
    setState(() {
      _installedPacks = installed;
    });
    
    if (_installedPacks.isNotEmpty) {
      // Если выбранный пак больше не существует — сбрасываем на 0
      if (_selectedPackIndex >= _installedPacks.length) {
        _selectedPackIndex = 0;
      }
      await _loadPackStickers(_selectedPackIndex);
    } else {
      setState(() {
        _currentStickers = [];
      });
    }
  }

  Future<void> _loadPackStickers(int index) async {
    if (index >= _installedPacks.length) return;
    
    setState(() {
      _selectedPackIndex = index;
      _loadingStickers = true;
    });
    
    final pack = _installedPacks[index];
    print('🎨 Loading stickers for pack: ${pack.name} (${pack.id})');
    
    // === КЛЮЧЕВОЕ ИСПРАВЛЕНИЕ: forceRefresh чтобы получить актуальные данные ===
    final stickers = await _stickerService.getPackStickers(pack.id, forceRefresh: true);
    
    print('🎨 Loaded ${stickers.length} stickers');
    
    if (mounted) {
      setState(() {
        _currentStickers = stickers;
        _loadingStickers = false;
      });
    }
  }

    @override
void dispose() {
  _typingDebounceTimer?.cancel();
  if (_messageCtrl.text.isEmpty && _attachedMediaList.isEmpty) {
    WebSocketService().sendTypingStop(widget.chat.id);
  }
  _wsSubscription?.cancel();
  _messageCtrl.dispose();
  _scrollController.dispose();
  _focusNode.dispose();

  for (var player in _voicePlayers.values) {
    player.dispose();
  }
  _voicePlayers.clear();
  
  // === ОЧИСТКА ВИДЕО-КРУЖКОВ ===
  for (var controller in _videoNoteControllers.values) {
    controller.dispose();
  }
  _videoNoteControllers.clear();
  
  MediaService().dispose();
  
  _stickerService.removeListener(_stickerServiceListener);
  _stickerSubscription?.cancel();
  
  _encryptionKey = null;
  
  SecureScreenService.disable();
  super.dispose();
}


String get _safeEncryptionKey {
  final key = _encryptionKey;
  if (key == null || key.isEmpty) {
    throw StateError('Encryption key not initialized for chat ${widget.chat.id}');
  }
  return key;
}


  Future<void> _pickMultipleImages() async {
    try {
      final List<XFile> picked = await _imagePicker.pickMultiImage(
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 100,
      );
      
      if (picked.isEmpty) return;
      
      for (final file in picked) {
        await _addMediaToList(file.path, MediaType.image);
      }
    } catch (e) {
      _showError('Failed to pick images: $e');
    }
  }

  Future<void> _pickImage() async {
    await _pickMultipleImages();
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? picked = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 4096,
        maxHeight: 4096,
        imageQuality: 100,
      );
      
      if (picked == null) return;
      
      await _processSelectedMedia(picked.path, MediaType.image);
    } catch (e) {
      _showError('Failed to take photo: $e');
    }
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? picked = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );
      
      if (picked == null) return;
      
      final file = File(picked.path);
      final fileSize = await file.length();
      
      if (fileSize > 1073741824) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video too large. Maximum size is 1GB'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      
      await _addMediaToList(picked.path, MediaType.video);
    } catch (e) {
      _showError('Failed to pick video: $e');
    }
  }

  Future<void> _addMediaToList(String filePath, MediaType type) async {
    setState(() {
      _isCompressing = true;
      _compressingProgress = 'Processing ${type == MediaType.image ? 'image' : 'video'}...';
    });

    try {
      String? thumbnail;
      if (type == MediaType.video) {
        thumbnail = await MediaService().generateVideoThumbnail(filePath);
      }

      if (mounted) {
        setState(() {
          _attachedMediaList.add(AttachedMedia(
            file: File(filePath),
            type: type,
            thumbnail: thumbnail,
          ));
          _isCompressing = false;
          _compressingProgress = null;
        });
      }
    } catch (e) {
      setState(() {
        _isCompressing = false;
        _compressingProgress = null;
      });
      _showError('Failed to process media: $e');
    }
  }

  void _removeAttachedMedia(int index) {
    setState(() {
      _attachedMediaList.removeAt(index);
    });
  }

  void _clearAttachedMedia() {
    setState(() {
      _attachedMediaList.clear();
    });
  }

  Future<void> _recordVideo() async {
    try {
      final XFile? picked = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );
      
      if (picked == null) return;
      
      await _processSelectedMedia(picked.path, MediaType.video);
    } catch (e) {
      _showError('Failed to record video: $e');
    }
  }

  Future<void> _processSelectedMedia(String filePath, MediaType type) async {
    setState(() {
      _isCompressing = true;
      _compressingProgress = type == MediaType.image ? 'Compressing image...' : 'Compressing video...';
    });

    try {
      String? thumbnail;
      if (type == MediaType.video) {
        thumbnail = await MediaService().generateVideoThumbnail(filePath);
      }

      if (mounted) {
        setState(() {
          _attachedMediaList.add(AttachedMedia(
            file: File(filePath),
            type: type,
            thumbnail: thumbnail,
          ));
          _isCompressing = false;
          _compressingProgress = null;
        });
      }
    } catch (e) {
      setState(() {
        _isCompressing = false;
        _compressingProgress = null;
      });
      _showError('Failed to process media: $e');
    }
  }

  // === ИСПРАВЛЕННЫЙ МЕТОД: отправка сообщения ===
    // === ПОЛНОСТЬЮ ИСПРАВЛЕННЫЙ МЕТОД: отправка сообщения ===
    Future<void> _sendMessage() async {
  // Защита от двойного нажатия
  if (_isSending || _isLoading || _isCreatingChat) {
    print('⏳ Send already in progress, ignoring');
    return;
  }
  
  final textContent = _messageCtrl.text.trim();

  if (textContent.isEmpty && _attachedMediaList.isEmpty) return;
  if (_currentUserId == null) return;

  _isSending = true; // Блокируем отправку

  try {
    if (_editingMessage != null) {
      await _editMessage(_editingMessage!, textContent);
      return;
    }

    String? replyToId;
    String? replyToContent;
    String? replyToSenderId;
    
    if (_replyingToMessage != null) {
      replyToId = _replyingToMessage!.id;
      replyToContent = _replyingToMessage!.content;
      replyToSenderId = _replyingToMessage!.senderId;
    }

    if (widget.isNewChat && widget.chat.id.startsWith('temp_')) {
      if (_attachedMediaList.isNotEmpty) {
        await _sendFirstMediaMessage(
          textContent, 
          replyToId: replyToId, 
          replyToContent: replyToContent, 
          replyToSenderId: replyToSenderId,
        );
      } else {
        await _sendFirstMessage(
          textContent, 
          replyToId: replyToId, 
          replyToContent: replyToContent, 
          replyToSenderId: replyToSenderId,
        );
      }
      return;
    }

    if (_attachedMediaList.isNotEmpty) {
      await _sendMediaMessage(
        textContent, 
        replyToId: replyToId, 
        replyToContent: replyToContent, 
        replyToSenderId: replyToSenderId,
      );
    } else {
      await _sendTextMessage(
        textContent, 
        replyToId: replyToId, 
        replyToContent: replyToContent, 
        replyToSenderId: replyToSenderId,
      );
    }

    SoundService().playSendSound();
    
    _cancelReply();
  } finally {
    _isSending = false; // Разблокируем
  }
}

  // === ИСПРАВЛЕННЫЙ МЕТОД: отправка первого сообщения ===
  Future<void> _sendFirstMessage(
  String content, {
  String? replyToId,
  String? replyToContent,
  String? replyToSenderId,
}) async {
  if (_isCreatingChat) return;
  
  setState(() => _isCreatingChat = true);
  _messageCtrl.clear();
  
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final tempId = 'temp_${timestamp}_${_messages.length}';

  final tempMessage = MessageModel(
    id: tempId,
    chatId: widget.chat.id,
    senderId: _currentUserId!,
    content: content,
    encryptedContent: '',
    type: 'text',
    timestamp: timestamp,
    status: 'sending',
    replyToMessageId: replyToId,
    replyToContent: replyToContent,
    replyToSenderId: replyToSenderId,
  );

  setState(() => _messages.insert(0, tempMessage));
  _scrollToBottom();

  try {
    final chatResponse = await ApiService().createOrGetChat(
      chatId: widget.chat.id,
      otherUserId: widget.otherUserId!,
    );
    
    final serverChatId = chatResponse.data['chat_id'] as String;
    final serverKey = chatResponse.data['encryption_key'] as String;
    
    print('✅ Chat ready: $serverChatId');
    
    final updatedChat = widget.chat.copyWith(
      id: serverChatId,
      encryptionKey: serverKey,
    );
    await LocalDatabase().deleteChat(widget.chat.id);
    await LocalDatabase().insertChat(updatedChat);
    setState(() => _encryptionKey = serverKey);
    
    final encrypted = EncryptionService.encryptMessage(content, serverKey);
    
    final msgResponse = await ApiService().sendMessage(
      serverChatId,
      encrypted,
      replyToMessageId: replyToId,
    );
    
    final serverMessageId = msgResponse.data['message_id'] as String;
    final serverTime = msgResponse.data['timestamp'] as int;
    final msServerTime = serverTime < 10000000000 ? serverTime * 1000 : serverTime;
    
    final sentMessage = tempMessage.copyWith(
      id: serverMessageId,
      chatId: serverChatId,
      encryptedContent: encrypted,
      timestamp: msServerTime,
      status: 'sent',
    );
    
    setState(() {
      final index = _messages.indexWhere((m) => m.id == tempId);
      if (index != -1) _messages[index] = sentMessage;
    });
    
    await LocalDatabase().insertMessage(sentMessage, encryptionKey: serverKey);
    
    print('✅ First message sent securely');

  } catch (e) {
    print('❌ Failed: $e');
    setState(() {
      final index = _messages.indexWhere((m) => m.id == tempId);
      if (index != -1) _messages[index] = _messages[index].copyWith(status: 'failed');
    });
    _showError('Failed to send: $e');
  } finally {
    setState(() => _isCreatingChat = false);
  }
}

  // === ИСПРАВЛЕННЫЙ МЕТОД: отправка текстового сообщения ===
    Future<void> _sendTextMessage(
  String content, {
  String? replyToId,
  String? replyToContent,
  String? replyToSenderId,
}) async {
  // Проверяем ключ перед использованием
  final key = _encryptionKey;
  if (key == null || key.isEmpty) {
    _showError('Encryption key not available');
    return;
  }

  _messageCtrl.clear();
  WebSocketService().sendTypingStop(widget.chat.id);
  
  final encrypted = EncryptionService.encryptMessage(content, key);
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final tempId = 'temp_${timestamp}_${_messages.length}';

  final tempMessage = MessageModel(
    id: tempId,
    chatId: widget.chat.id,
    senderId: _currentUserId!,
    content: content,
    encryptedContent: encrypted,
    type: 'text',
    timestamp: timestamp,
    status: 'sending',
    replyToMessageId: replyToId,
    replyToContent: replyToContent,
    replyToSenderId: replyToSenderId,
  );

  setState(() {
    _messages.insert(0, tempMessage);
  });
  _scrollToBottom();

  try {
    final response = await ApiService().sendMessage(
      widget.chat.id, 
      encrypted,
      replyToMessageId: replyToId,
    );
    final serverId = response.data['message_id'] as String;
    final serverTime = response.data['timestamp'] as int;
    final msServerTime = serverTime < 10000000000 ? serverTime * 1000 : serverTime;

    final sentMessage = tempMessage.copyWith(
      id: serverId,
      timestamp: msServerTime,
      status: 'sent',
    );

    setState(() {
      final index = _messages.indexWhere((m) => m.id == tempId);
      if (index != -1) _messages[index] = sentMessage;
    });

    await LocalDatabase().insertMessage(sentMessage, encryptionKey: key);

  } catch (e) {
    _handleSendError(tempId, e);
  }
}

  // === ИСПРАВЛЕННЫЙ МЕТОД: отправка медиа ===
    // === ИСПРАВЛЕННЫЙ МЕТОД: отправка медиа в существующий чат ===
  Future<void> _sendMediaMessage(
  String? caption, {
  String? replyToId,
  String? replyToContent,
  String? replyToSenderId,
}) async {
  // Дополнительная защита от повторной отправки
  if (_isLoading) {
    print('⏳ Media send already in progress');
    return;
  }
  
  if (widget.isNewChat && widget.chat.id.startsWith('temp_')) {
    await _sendFirstMediaMessage(
      caption,
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSenderId: replyToSenderId,
    );
    return;
  }

  final key = _encryptionKey;
  if (key == null || key.isEmpty) {
    _showError('Encryption key not available');
    return;
  }

  if (_attachedMediaList.isEmpty) {
    print('❌ No media to send');
    return;
  }

  _messageCtrl.clear();
  WebSocketService().sendTypingStop(widget.chat.id);
  setState(() => _isLoading = true);

  try {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final tempId = 'temp_album_${timestamp}_${_messages.length}';

    final List<Map<String, dynamic>> mediaDataList = [];
    final List<String> localPaths = [];

    for (int i = 0; i < _attachedMediaList.length; i++) {
      final media = _attachedMediaList[i];

      final compressed = media.type == MediaType.image
          ? await MediaService().compressImage(media.file.path, disableCompression: _disableCompression)
          : await MediaService().compressVideo(media.file.path, disableCompression: _disableCompression);

      final encrypted = await MediaService().encryptFile(
        compressed.path,
        key,
        fileName: path.basename(media.file.path),
      );

      mediaDataList.add({
        'index': i,
        'type': media.type == MediaType.image ? 'image' : 'video',
        'encrypted_content': encrypted.encryptedBase64,
        'file_name': encrypted.fileName,
        'file_size': encrypted.encryptedSize,
        'width': compressed.width,
        'height': compressed.height,
        'duration': compressed.duration,
      });

      localPaths.add(media.file.path);
    }

    final pathsToSave = localPaths.join(',');
    final mediaCount = mediaDataList.length;

    _clearAttachedMedia();

    final tempMessage = MessageModel(
      id: tempId,
      chatId: widget.chat.id,
      senderId: _currentUserId!,
      content: caption ?? '',
      encryptedContent: jsonEncode(mediaDataList),
      type: 'album',
      timestamp: timestamp,
      status: 'sending',
      localPath: pathsToSave,
      fileName: '${mediaCount} files',
      fileSize: mediaCount,
      replyToMessageId: replyToId,
      replyToContent: replyToContent,
      replyToSenderId: replyToSenderId,
    );

    setState(() {
      _isLoading = false;
      _messages.insert(0, tempMessage);
    });
    _scrollToBottom();

    final response = await ApiService().sendMediaAlbum(
      chatId: widget.chat.id,
      mediaItems: mediaDataList,
      caption: caption,
      replyToMessageId: replyToId,
    );

    final serverId = response.data['message_id'] as String;
    final serverTime = response.data['timestamp'] as int;
    final msServerTime = serverTime < 10000000000 ? serverTime * 1000 : serverTime;

    final sentMessage = tempMessage.copyWith(
      id: serverId,
      timestamp: msServerTime,
      status: 'sent',
    );

    setState(() {
      final index = _messages.indexWhere((m) => m.id == tempId);
      if (index != -1) _messages[index] = sentMessage;
    });

    await LocalDatabase().insertMessage(sentMessage, encryptionKey: key);

  } catch (e) {
    setState(() => _isLoading = false);
    _handleSendError('temp_album_${DateTime.now().millisecondsSinceEpoch}_${_messages.length}', e);
    _showError('Failed to send media: $e');
  } finally {
    _clearAttachedMedia();
  }
}

  // === ИСПРАВЛЕННЫЙ МЕТОД: отправка первого альбома ===
    // === ИСПРАВЛЕННЫЙ МЕТОД: отправка первого альбома ===
  Future<void> _sendFirstMediaMessage(
  String? caption, {
  String? replyToId,
  String? replyToContent,
  String? replyToSenderId,
}) async {
  if (_attachedMediaList.isEmpty) return;
  
  // Защита от повторного создания чата
  if (_isCreatingChat) {
    print('⏳ Chat creation already in progress');
    return;
  }

  setState(() {
    _isCreatingChat = true;
    _isLoading = true;
  });

  _messageCtrl.clear();
  WebSocketService().sendTypingStop(widget.chat.id);

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final tempId = 'temp_album_${timestamp}_${_messages.length}';

  final List<String> localPaths = _attachedMediaList.map((m) => m.file.path).toList();

  final tempMessage = MessageModel(
    id: tempId,
    chatId: widget.chat.id,
    senderId: _currentUserId!,
    content: caption ?? '',
    encryptedContent: null,
    type: 'album',
    timestamp: timestamp,
    status: 'sending',
    localPath: localPaths.join(','),
    fileName: '${_attachedMediaList.length} files',
    fileSize: _attachedMediaList.length,
    replyToMessageId: replyToId,
    replyToContent: replyToContent,
    replyToSenderId: replyToSenderId,
  );

  setState(() => _messages.insert(0, tempMessage));
  _scrollToBottom();

  try {
    final chatResponse = await ApiService().createOrGetChat(
      chatId: widget.chat.id,
      otherUserId: widget.otherUserId!,
    );

    final serverChatId = chatResponse.data['chat_id'] as String;
    final serverKey = chatResponse.data['encryption_key'] as String;

    print('✅ Chat ready for album: $serverChatId');

    final updatedChat = widget.chat.copyWith(
      id: serverChatId,
      encryptionKey: serverKey,
    );
    await LocalDatabase().deleteChat(widget.chat.id);
    await LocalDatabase().insertChat(updatedChat);
    setState(() => _encryptionKey = serverKey);

    final List<Map<String, dynamic>> mediaDataList = [];

    for (int i = 0; i < localPaths.length; i++) {
      final filePath = localPaths[i];
      final media = _attachedMediaList.firstWhere(
        (m) => m.file.path == filePath,
        orElse: () => AttachedMedia(
          file: File(filePath),
          type: filePath.contains('.mp4') || filePath.contains('.mov')
              ? MediaType.video
              : MediaType.image
        ),
      );

      final compressed = media.type == MediaType.image
          ? await MediaService().compressImage(media.file.path, disableCompression: _disableCompression)
          : await MediaService().compressVideo(media.file.path, disableCompression: _disableCompression);

      final encrypted = await MediaService().encryptFile(
        compressed.path,
        serverKey,
        fileName: path.basename(media.file.path),
      );

      mediaDataList.add({
        'index': i,
        'type': media.type == MediaType.image ? 'image' : 'video',
        'encrypted_content': encrypted.encryptedBase64,
        'file_name': encrypted.fileName,
        'file_size': encrypted.encryptedSize,
        'width': compressed.width,
        'height': compressed.height,
        'duration': compressed.duration,
      });
    }

    _clearAttachedMedia();

    final msgResponse = await ApiService().sendMediaAlbum(
      chatId: serverChatId,
      mediaItems: mediaDataList,
      caption: caption,
      replyToMessageId: replyToId,
    );

    final serverMessageId = msgResponse.data['message_id'] as String;
    final serverTime = msgResponse.data['timestamp'] as int;
    final msServerTime = serverTime < 10000000000 ? serverTime * 1000 : serverTime;

    final sentMessage = tempMessage.copyWith(
      id: serverMessageId,
      chatId: serverChatId,
      encryptedContent: jsonEncode(mediaDataList),
      timestamp: msServerTime,
      status: 'sent',
    );

    setState(() {
      final index = _messages.indexWhere((m) => m.id == tempId);
      if (index != -1) _messages[index] = sentMessage;
    });

    await LocalDatabase().insertMessage(sentMessage, encryptionKey: serverKey);

  } catch (e) {
    setState(() => _isLoading = false);
    _showError('Failed to send album: $e');
  } finally {
    setState(() {
      _isCreatingChat = false;
      _isLoading = false;
    });
    _clearAttachedMedia();
  }
}

  // === ИСПРАВЛЕННЫЙ МЕТОД: обработка успеха отправки ===
  Future<void> _handleSendSuccess(
    Response response,
    String tempId,
    MessageModel tempMessage, {
    String? localPath,
  }) async {
    final serverId = response.data['message_id'] as String;
    final serverTime = response.data['timestamp'] as int;
    final msServerTime = serverTime < 10000000000 ? serverTime * 1000 : serverTime;

    final existingIndex = _messages.indexWhere((m) => m.id == serverId);
    if (existingIndex != -1) {
      setState(() => _messages.removeWhere((m) => m.id == tempId));
      return;
    }

    bool alreadyDelivered = _pendingStatusUpdates.containsKey(serverId) &&
        _pendingStatusUpdates[serverId]!['type'] == 'delivered';
    final otherOnline = _otherUserStatus == 'online';
    final finalStatus = (alreadyDelivered || otherOnline) ? 'delivered' : 'sent';

    _tempIdToRealId[tempId] = serverId;
    _realIdToTempId[serverId] = tempId;

    final sentMessage = tempMessage.copyWith(
      id: serverId,
      timestamp: msServerTime,
      status: finalStatus,
      isDelivered: finalStatus == 'delivered',
      localPath: localPath ?? tempMessage.localPath,
    );

    setState(() {
      final index = _messages.indexWhere((m) => m.id == tempId);
      if (index != -1) _messages[index] = sentMessage;
    });

    // Сохраняем в БД — ПЕРЕДАЁМ КЛЮЧ для текстовых сообщений
    await LocalDatabase().insertMessage(sentMessage, encryptionKey: _encryptionKey);

    if (_pendingStatusUpdates.containsKey(serverId)) {
      final pending = _pendingStatusUpdates.remove(serverId);
      if (pending?['type'] == 'delivered') {
        _updateMessageStatus(serverId, 'delivered', isDelivered: true);
      } else if (pending?['type'] == 'read') {
        _updateMessageStatus(serverId, 'read', isRead: true);
      }
    }
  }

  // === ИСПРАВЛЕННЫЙ МЕТОД: повторная отправка ===
  Future<void> _retrySend(MessageModel failedMessage) async {
  print('🔄 Retrying send for message: ${failedMessage.id}');
  
  final index = _messages.indexWhere((m) => m.id == failedMessage.id);
  if (index == -1) {
    print('❌ Message not found in list');
    return;
  }
  
  // Проверяем ключ перед использованием
  final key = _encryptionKey;
  if (key == null || key.isEmpty) {
    _showError('Encryption key not available');
    setState(() {
      _messages[index] = failedMessage.copyWith(status: 'failed');
    });
    return;
  }
  
  setState(() {
    _messages[index] = failedMessage.copyWith(status: 'sending');
  });
  
  try {
    if (failedMessage.isMedia) {
      if (failedMessage.localPath == null || failedMessage.encryptedContent == null) {
        throw Exception('Missing media data for retry');
      }
      
      final file = File(failedMessage.localPath!);
      if (!file.existsSync()) {
        throw Exception('Local media file not found');
      }
      
      final response = await ApiService().sendMediaMessage(
        chatId: widget.chat.id,
        encryptedContent: failedMessage.encryptedContent!,
        type: failedMessage.type,
        caption: failedMessage.content,
        fileName: failedMessage.fileName,
        fileSize: failedMessage.fileSize,
        width: failedMessage.width,
        height: failedMessage.height,
        duration: failedMessage.duration,
      );
      
      await _handleRetrySuccess(response, failedMessage.id, failedMessage);
      
    } else {
      String encryptedContent;
      if (failedMessage.encryptedContent != null && failedMessage.encryptedContent!.isNotEmpty) {
        encryptedContent = failedMessage.encryptedContent!;
      } else {
        encryptedContent = EncryptionService.encryptMessage(failedMessage.content, key);
      }
      
      final response = await ApiService().sendMessage(
        widget.chat.id,
        encryptedContent,
      );
      
      await _handleRetrySuccess(response, failedMessage.id, failedMessage.copyWith(
        encryptedContent: encryptedContent,
      ));
    }
    
  } catch (e) {
    print('❌ Retry failed: $e');
    if (mounted) {
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == failedMessage.id);
        if (idx != -1) {
          _messages[idx] = failedMessage.copyWith(status: 'failed');
        }
      });
    }
    _showError('Failed to resend: $e');
  }
}


  // === ИСПРАВЛЕННЫЙ МЕТОД: обработка успеха повторной отправки ===
  Future<void> _handleRetrySuccess(
    Response response,
    String originalMessageId,
    MessageModel originalMessage,
  ) async {
    final serverId = response.data['message_id'] as String;
    final serverTime = response.data['timestamp'] as int;
    final msServerTime = serverTime < 10000000000 ? serverTime * 1000 : serverTime;
    
    final existingIndex = _messages.indexWhere((m) => m.id == serverId && m.id != originalMessageId);
    if (existingIndex != -1) {
      print('⚠️ Server returned existing ID, removing duplicate');
      setState(() {
        _messages.removeWhere((m) => m.id == originalMessageId);
      });
      return;
    }
    
    final updatedMessage = originalMessage.copyWith(
      id: serverId,
      timestamp: msServerTime,
      status: 'sent',
    );
    
    setState(() {
      final index = _messages.indexWhere((m) => m.id == originalMessageId);
      if (index != -1) {
        _messages[index] = updatedMessage;
      }
    });
    
    // Обновляем в БД — ПЕРЕДАЁМ КЛЮЧ
    await LocalDatabase().deleteMessage(originalMessageId);
    await LocalDatabase().insertMessage(updatedMessage, encryptionKey: _encryptionKey);
    
    print('✅ Message resent successfully: $originalMessageId → $serverId');
  }

  // === ИСПРАВЛЕННЫЙ МЕТОД: обработка входящего сообщения ===
  Future<void> _processIncomingMessage(Map<String, dynamic> messageData) async {
  try {
    // Проверяем ключ перед использованием
    final key = _encryptionKey;
    if (key == null || key.isEmpty) {
      print('❌ Cannot process message: encryption key not initialized');
      return;
    }
    
    final messageId = messageData['id'];
    final hadPendingDelivery = _pendingStatusUpdates.containsKey(messageId);
    
    final exists = await LocalDatabase().messageExists(messageId);
    if (exists) return;

    final type = messageData['type'] ?? 'text';
    String content = messageData['content'] ?? '';
    String? localPath;

    if (type == 'text') {
      final encrypted = messageData['encrypted_content'] as String?;
      if (encrypted != null) {
        content = EncryptionService.decryptMessage(encrypted, key);
      }
      
    } else if (type == 'sticker') {
      final encrypted = messageData['encrypted_content'] as String?;
      if (encrypted != null) {
        final fileName = messageData['file_name'] ?? 'sticker_$messageId.webp';
        localPath = await MediaService().decryptAndSave(
          encrypted, 
          key, 
          fileName,
        );
        content = '';
      }

    } else {
      final encrypted = messageData['encrypted_content'] as String?;
      if (encrypted != null) {
        final fileName = messageData['file_name'] ?? 'media_$messageId';
        localPath = await MediaService().decryptAndSave(
          encrypted, 
          key, 
          fileName,
        );
        content = messageData['caption'] ?? '';
      }
    }

    final message = MessageModel.fromServer({
      ...messageData,
      'content': content,
      'local_path': localPath,
    });

    await LocalDatabase().insertMessage(message, encryptionKey: key);
    
    await LocalDatabase().updateChatLastMessage(
      widget.chat.id,
      type == 'text' ? message.encryptedContent : (content.isNotEmpty ? content : '[Медиа]'),
      message.timestamp,
      senderId: message.senderId,
      status: 'delivered',
      messageType: type,
      encryptionKey: key,
    );
    SoundService().playReceiveSound();

    WebSocketService().markMessageRead(widget.chat.id, message.id);

    if (mounted) {
      setState(() => _messages.insert(0, message));
      if (hadPendingDelivery) _pendingStatusUpdates.remove(messageId);
      _scrollToBottom();
    }
  } catch (e) {
    print('Error processing message: $e');
  }
}

  // === ОСТАЛЬНЫЕ МЕТОДЫ БЕЗ ИЗМЕНЕНИЙ (кроме добавления encryptionKey в вызовы) ===

   void _onWebSocketMessage(Map<String, dynamic> data) {
    if (!mounted) return;
    
    print('📨 ChatScreen received: ${data['type']}');

    switch (data['type']) {
      case 'new_message':
        // === КРИТИЧНО: Проверяем chat_id ДО обработки ===
        final msgData = data['message'] as Map<String, dynamic>?;
        final chatId = msgData?['chat_id'] as String? ?? data['chat_id'] as String?;
        
        if (chatId == null || chatId != widget.chat.id) {
          print('🚫 Ignoring new_message for chat: $chatId (my: ${widget.chat.id})');
          return;
        }
        _handleNewMessage(data);
        break;
        
      case 'message_delivered':
        final chatId = data['chat_id'] as String?;
        if (chatId == widget.chat.id) {
          _handleMessageDelivered(data);
        }
        break;
        
      case 'message_read':
        final chatId = data['chat_id'] as String?;
        if (chatId == widget.chat.id) {
          _handleMessageRead(data);
        }
        break;
        
      case 'message_edited':
        final chatId = data['chat_id'] as String? ?? data['message']?['chat_id'] as String?;
        if (chatId == null || chatId == widget.chat.id) {
          _handleMessageEdited(data);
        }
        break;
        
      case 'message_deleted':
        final chatId = data['chat_id'] as String?;
        if (chatId == null || chatId == widget.chat.id) {
          _handleMessageDeleted(data);
        }
        break;
        
      case 'reaction_added':
        final chatId = data['chat_id'] as String?;
        if (chatId == null || chatId == widget.chat.id) {
          _handleReactionAdded(data);
        }
        break;
        
      case 'reaction_removed':
        final chatId = data['chat_id'] as String?;
        if (chatId == null || chatId == widget.chat.id) {
          _handleReactionRemoved(data);
        }
        break;
        
      case 'typing':
        final chatId = data['chat_id'] as String?;
        final userId = data['user_id'] as String?;
        if (chatId == widget.chat.id && userId != _currentUserId) {
          setState(() => _isOtherTyping = data['is_typing'] == true);
        }
        break;
        
      case 'user_status':
      case 'user_status_response':
        final userId = data['user_id'] as String?;
        if (userId == widget.chat.userId) {
          setState(() {
            _otherUserStatus = data['status'];
            _otherUserLastSeen = data['last_seen'] != null 
                ? (data['last_seen'] as int) * 1000 
                : null;
          });
        }
        break;
        
      case 'chat_read':
        final chatId = data['chat_id'] as String?;
        final readerId = data['reader_id'] as String?;
        if (chatId == widget.chat.id && readerId != _currentUserId) {
          _markAllMyMessagesAsRead();
        }
        break;
    }
  }


    void _handleNewMessage(Map<String, dynamic> data) {
    final messageData = data['message'] as Map<String, dynamic>?;
    if (messageData == null) return;
    
    // chat_id уже проверен в _onWebSocketMessage
    final senderId = messageData['sender_id'] as String?;
    
    // Не обрабатываем свои собственные сообщения (мы уже добавили их при отправке)
    if (senderId == _currentUserId) {
      print('🚫 Ignoring own message from WebSocket');
      return;
    }

    _processIncomingMessage(messageData);
  }

  void _handleMessageEdited(Map<String, dynamic> data) {
  final messageId = data['message_id'] as String?;
  final newContent = data['content'] as String?;
  final editedAt = data['edited_at'] as int?;
  final chatId = data['chat_id'] as String?;
  
  // Проверяем что редактирование для нашего чата
  if (chatId != null && chatId != widget.chat.id) {
    print('🚫 Ignoring edit for different chat: $chatId');
    return;
  }
  
  if (messageId == null) return;
  
  final index = _messages.indexWhere((m) => m.id == messageId);
  if (index != -1) {
    setState(() {
      _messages[index] = _messages[index].copyWith(
        content: newContent ?? _messages[index].content,
        editedAt: editedAt != null && editedAt < 10000000000 
            ? editedAt * 1000 
            : editedAt,
      );
    });
  }
}

  void _handleMessageDeleted(Map<String, dynamic> data) {
  final messageId = data['message_id'] as String?;
  final chatId = data['chat_id'] as String?;
  
  // Проверяем что удаление для нашего чата
  if (chatId != null && chatId != widget.chat.id) {
    print('🚫 Ignoring delete for different chat: $chatId');
    return;
  }
  
  if (messageId == null) return;
  
  setState(() {
    _messages.removeWhere((m) => m.id == messageId);
  });
  
  LocalDatabase().deleteMessage(messageId);
}

  void _handleReactionAdded(Map<String, dynamic> data) {
  final messageId = data['message_id'] as String?;
  final userId = data['user_id'] as String?;
  final reaction = data['reaction'] as String?;
  final chatId = data['chat_id'] as String?;
  
  // Проверяем что реакция для нашего чата
  if (chatId != null && chatId != widget.chat.id) {
    print('🚫 Ignoring reaction for different chat: $chatId');
    return;
  }
  
  if (messageId == null || userId == null || reaction == null) return;
  
  final index = _messages.indexWhere((m) => m.id == messageId);
  if (index != -1) {
    final updatedReactions = Map<String, String>.from(_messages[index].reactions);
    updatedReactions[userId] = reaction;
    
    setState(() {
      _messages[index] = _messages[index].copyWith(reactions: updatedReactions);
    });
  }
}

  void _handleReactionRemoved(Map<String, dynamic> data) {
  final messageId = data['message_id'] as String?;
  final userId = data['user_id'] as String?;
  final chatId = data['chat_id'] as String?;
  
  // Проверяем что реакция для нашего чата
  if (chatId != null && chatId != widget.chat.id) {
    print('🚫 Ignoring reaction removal for different chat: $chatId');
    return;
  }
  
  if (messageId == null || userId == null) return;
  
  final index = _messages.indexWhere((m) => m.id == messageId);
  if (index != -1) {
    final updatedReactions = Map<String, String>.from(_messages[index].reactions);
    updatedReactions.remove(userId);
    
    setState(() {
      _messages[index] = _messages[index].copyWith(reactions: updatedReactions);
    });
  }
}


  void _handleMessageDelivered(Map<String, dynamic> data) {
  final String messageId = data['message_id'];
  final String? chatId = data['chat_id'];
  
  // Уже проверено в _onWebSocketMessage, но на всякий случай
  if (chatId != null && chatId != widget.chat.id) {
    return;
  }
  
  int? index = _messages.indexWhere((m) => m.id == messageId);
  
  if (index == -1 && _realIdToTempId.containsKey(messageId)) {
    index = _messages.indexWhere((m) => m.id == _realIdToTempId[messageId]);
  }
  
  if (index != -1 && index < _messages.length) {
    _updateMessageStatus(messageId, 'delivered', isDelivered: true);
  } else {
    _pendingStatusUpdates[messageId] = {
      'type': 'delivered',
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }
}

  void _handleMessageRead(Map<String, dynamic> data) {
  final String messageId = data['message_id'];
  final String? chatId = data['chat_id'];
  
  // Уже проверено в _onWebSocketMessage, но на всякий случай
  if (chatId != null && chatId != widget.chat.id) {
    return;
  }
  
  int? index = _messages.indexWhere((m) => m.id == messageId);
  
  if (index == -1 && _realIdToTempId.containsKey(messageId)) {
    index = _messages.indexWhere((m) => m.id == _realIdToTempId[messageId]);
  }
  
  if (index != -1 && index < _messages.length) {
    _updateMessageStatus(messageId, 'read', isRead: true);
  } else {
    _pendingStatusUpdates[messageId] = {
      'type': 'read',
      'data': data,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };
  }
}

bool _isSending = false; // Флаг отправки

  Future<void> _updateMessageStatus(
    String messageId,
    String newStatus, {
    bool? isRead,
    bool? isDelivered,
  }) async {
    int? index;
    String realId = messageId;

    if (_tempIdToRealId.containsKey(messageId)) {
      realId = _tempIdToRealId[messageId]!;
      index = _messages.indexWhere((m) => m.id == realId);
      if (index == -1) index = _messages.indexWhere((m) => m.id == messageId);
    } else {
      index = _messages.indexWhere((m) => m.id == messageId);
      if (index == -1 && _realIdToTempId.containsKey(messageId)) {
        index = _messages.indexWhere((m) => m.id == _realIdToTempId[messageId]);
      }
    }

    if (index == -1 || index >= _messages.length) return;

    final oldMsg = _messages[index];
    
    final statusPriority = {'sending': 0, 'sent': 1, 'delivered': 2, 'read': 3, 'failed': -1};
    if ((statusPriority[newStatus] ?? 0) <= (statusPriority[oldMsg.status] ?? 0) &&
        !(oldMsg.status == 'sending' && newStatus == 'sent')) {
      return;
    }

    final updatedMsg = oldMsg.copyWith(
      status: newStatus,
      isRead: isRead ?? oldMsg.isRead,
      isDelivered: isDelivered ?? oldMsg.isDelivered,
    );

    setState(() => _messages[index!] = updatedMsg);
    await LocalDatabase().updateMessageStatus(realId, newStatus);
    if (isRead != null || isDelivered != null) {
      await LocalDatabase().updateMessageFlags(realId, isRead: isRead, isDelivered: isDelivered);
    }

    _pendingStatusUpdates.remove(messageId);
    _pendingStatusUpdates.remove(realId);
  }

  Future<void> _markAllMyMessagesAsRead() async {
    final myMessages = _messages.where((m) => 
      m.senderId == _currentUserId && m.status != 'read'
    ).toList();
    
    for (var msg in myMessages) {
      await _updateMessageStatus(msg.id, 'read', isRead: true);
    }
  }

  Future<void> _markIncomingAsRead() async {
    if (_currentUserId == null) return;
    
    final unreadFromOther = _messages.where((m) => 
      m.senderId != _currentUserId && !m.isRead
    ).toList();
    
    if (unreadFromOther.isEmpty) return;
    
    WebSocketService().markChatRead(widget.chat.id);
    await LocalDatabase().resetUnreadCount(widget.chat.id);
    
    for (var msg in unreadFromOther) {
      final index = _messages.indexWhere((m) => m.id == msg.id);
      if (index != -1) {
        setState(() {
          _messages[index] = _messages[index].copyWith(isRead: true, status: 'read');
        });
      }
    }
  }

  void _handleSendError(String tempId, dynamic error) {
    setState(() {
      final index = _messages.indexWhere((m) => m.id == tempId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(status: 'failed');
      }
    });
  }

  Future<void> _editMessage(MessageModel message, String newContent) async {
  setState(() => _editingMessage = null);
  _messageCtrl.clear();
  
  // Проверяем ключ перед использованием
  final key = _encryptionKey;
  if (key == null || key.isEmpty) {
    _showError('Encryption key not available');
    return;
  }
  
  final encrypted = EncryptionService.encryptMessage(newContent, key);
  
  final index = _messages.indexWhere((m) => m.id == message.id);
  if (index != -1) {
    setState(() {
      _messages[index] = _messages[index].copyWith(
        content: newContent,
        status: 'sending',
      );
    });
  }

  try {
    await ApiService().editMessage(message.id, encrypted);
    
    if (index != -1) {
      setState(() {
        _messages[index] = _messages[index].copyWith(
          content: newContent,
          status: 'sent',
          editedAt: DateTime.now().millisecondsSinceEpoch,
        );
      });
    }
    
    await LocalDatabase().updateMessage(message.id, {
      'content': newContent,
      'encrypted_content': encrypted,
      'edited_at': DateTime.now().millisecondsSinceEpoch,
    });
    
  } catch (e) {
    _showError('Failed to edit message: $e');
    if (index != -1) {
      setState(() {
        _messages[index] = _messages[index].copyWith(status: 'failed');
      });
    }
  }
}

  // === UI МЕТОДЫ (без изменений, кроме добавления encryptionKey в вызовы) ===

  void _showMessageActions(MessageModel message, bool isMe) {
    final l10n = context.l10n;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!message.isMedia) ...[
                _buildReactionsBar(message),
                const Divider(height: 1),
              ],
              
              ..._buildActionItems(message, isMe),
              
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReactionsBar(MessageModel message) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: _reactionTypes.map((reaction) {
          final isSelected = message.reactions[_currentUserId] == reaction['name'];
          return GestureDetector(
            onTap: () {
              Navigator.pop(context);
              _toggleReaction(message, reaction['name'] as String);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected 
                    ? Theme.of(context).colorScheme.primaryContainer 
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                reaction['emoji'] as String,
                style: const TextStyle(fontSize: 28),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  List<Widget> _buildActionItems(MessageModel message, bool isMe) {
    final l10n = context.l10n;
    final items = <Widget>[];

    items.add(_buildActionTile(
      icon: Icons.reply,
      title: l10n.actionReply,
      onTap: () {
        Navigator.pop(context);
        _startReply(message);
      },
    ));

    items.add(_buildActionTile(
      icon: Icons.forward,
      title: l10n.actionForward,
      onTap: () {
        Navigator.pop(context);
        _showForwardDialog(message);
      },
    ));

    if (!message.isMedia) {
      items.add(_buildActionTile(
        icon: Icons.copy,
        title: l10n.actionCopy,
        onTap: () {
          Navigator.pop(context);
          Clipboard.setData(ClipboardData(text: message.content));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(l10n.actionCopy)),
          );
        },
      ));
    }

    if (isMe) {
      if (!message.isMedia) {
        items.add(_buildActionTile(
          icon: Icons.edit,
          title: l10n.actionEdit,
          onTap: () {
            Navigator.pop(context);
            _startEditing(message);
          },
        ));
      }

      items.add(_buildActionTile(
        icon: Icons.delete,
        title: l10n.actionDelete,
        color: Colors.red,
        onTap: () {
          Navigator.pop(context);
          _showDeleteDialog(message, canDeleteForEveryone: true);
        },
      ));
    } else {
      items.add(_buildActionTile(
        icon: Icons.delete_outline,
        title: l10n.actionDeleteForMe,
        onTap: () {
          Navigator.pop(context);
          _showDeleteDialog(message, canDeleteForEveryone: false);
        },
      ));

      items.add(_buildActionTile(
        icon: Icons.report,
        title: l10n.actionReport,
        color: Colors.orange,
        onTap: () {
          Navigator.pop(context);
          _showReportDialog(message);
        },
      ));
    }

    return items;
  }

  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        title,
        style: TextStyle(color: color),
      ),
      onTap: onTap,
    );
  }

  void _startEditing(MessageModel message) {
    setState(() {
      _editingMessage = message;
      _messageCtrl.text = message.content;
    });
    _focusNode.requestFocus();
  }

  void _cancelEditing() {
    setState(() {
      _editingMessage = null;
      _messageCtrl.clear();
    });
  }

  void _startReply(MessageModel message) {
    setState(() => _replyingToMessage = message);
    _focusNode.requestFocus();
  }

  void _cancelReply() {
    setState(() => _replyingToMessage = null);
  }

  Future<void> _toggleReaction(MessageModel message, String reactionType) async {
    final currentReaction = message.reactions[_currentUserId];
    
    final index = _messages.indexWhere((m) => m.id == message.id);
    if (index == -1) return;

    if (currentReaction == reactionType) {
      final updatedReactions = Map<String, String>.from(message.reactions);
      updatedReactions.remove(_currentUserId);
      
      setState(() {
        _messages[index] = message.copyWith(reactions: updatedReactions);
      });
      
      try {
        await ApiService().removeReaction(message.id);
        WebSocketService().removeReaction(message.id);
      } catch (e) {
        setState(() {
          _messages[index] = message;
        });
      }
    } else {
      final updatedReactions = Map<String, String>.from(message.reactions);
      updatedReactions[_currentUserId!] = reactionType;
      
      setState(() {
        _messages[index] = message.copyWith(reactions: updatedReactions);
      });
      
      try {
        await ApiService().addReaction(message.id, reactionType);
        WebSocketService().sendReaction(message.id, reactionType);
      } catch (e) {
        setState(() {
          _messages[index] = message;
        });
      }
    }
  }

  void _showDeleteDialog(MessageModel message, {required bool canDeleteForEveryone}) {
    final l10n = context.l10n;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.actionDelete),
        content: Text('${l10n.actionDelete}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.chatDeleteCancel),
          ),
          if (canDeleteForEveryone)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _deleteMessage(message, forEveryone: true);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text(l10n.actionDelete),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMessage(message, forEveryone: false);
            },
            child: Text(l10n.actionDeleteForMe),
          ),
        ],
      ),
    );
  }

   Future<void> _startVoiceRecording() async {
    try {
      final result = await MediaService().startVoiceRecording();
      
      // Показываем панель записи
      if (mounted) {
        _showVoiceRecordingPanel(result);
      }
    } catch (e) {
      _showError('Failed to start recording: $e');
    }
  }

  void _showVoiceRecordingPanel(VoiceRecordingResult recording) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _VoiceRecordingPanel(
        recording: recording,
        onStop: (result) {
          Navigator.pop(context);
          _showVoicePreview(result);
        },
        onCancel: () {
          Navigator.pop(context);
          MediaService().cancelVoiceRecording();
        },
      ),
    );
  }


  

  




  



  // === ОТПРАВКА ===

 Future<void> _sendVoiceMessage(VoiceRecordingResult recording, {int? trimStart, int? trimEnd}) async {
  if (_currentUserId == null) return;

  if (widget.isNewChat && widget.chat.id.startsWith('temp_')) {
    await _sendFirstVoiceMessage(recording, trimStart: trimStart, trimEnd: trimEnd);
    return;
  }

  final key = _encryptionKey;
  if (key == null || key.isEmpty) {
    _showError('Encryption key not available');
    return;
  }

  setState(() => _isLoading = true);

  try {
    int duration = recording.duration ?? 0;
    if (trimStart != null && trimEnd != null) duration = trimEnd - trimStart;

    final encrypted = await MediaService().encryptFile(recording.filePath, key, fileName: path.basename(recording.filePath));
    
    final response = await ApiService().sendVoiceMessage(
      chatId: widget.chat.id,
      encryptedContent: encrypted.encryptedBase64,
      fileName: path.basename(recording.filePath),
      fileSize: encrypted.originalSize,
      duration: duration,
      waveform: recording.waveform,
      replyToMessageId: _replyingToMessage?.id,
    );

    final serverId = response.data['message_id'] as String;
    final serverTime = response.data['timestamp'] as int;
    final msServerTime = serverTime < 10000000000 ? serverTime * 1000 : serverTime;

    final message = MessageModel(
  id: serverId,
  chatId: widget.chat.id,
  senderId: _currentUserId!,
  content: '[Voice]',
  encryptedContent: encrypted.encryptedBase64,
  type: 'voice',
  timestamp: msServerTime,
  status: 'sent',
  fileName: path.basename(recording.filePath),
  fileSize: encrypted.originalSize,
  localPath: recording.filePath,
  duration: duration,
  waveform: recording.waveform, // <-- ДОБАВЬ ЭТО
  replyToMessageId: _replyingToMessage?.id,
  replyToContent: _replyingToMessage?.content,
  replyToSenderId: _replyingToMessage?.senderId,
);

    await LocalDatabase().insertMessage(message, encryptionKey: key);
    
    setState(() {
      _messages.insert(0, message);
      _isLoading = false;
      _cancelReply();
    });
    _scrollToBottom();

  } catch (e) {
    setState(() => _isLoading = false);
    _showError('Failed to send voice: $e');
  }
}

Future<void> _sendFirstVoiceMessage(VoiceRecordingResult recording, {int? trimStart, int? trimEnd}) async {
  if (_isCreatingChat) return;
  
  setState(() => _isCreatingChat = true);

  try {
    final chatResponse = await ApiService().createOrGetChat(
      chatId: widget.chat.id,
      otherUserId: widget.otherUserId!,
    );
    
    final serverChatId = chatResponse.data['chat_id'] as String;
    final serverKey = chatResponse.data['encryption_key'] as String;
    
    final updatedChat = widget.chat.copyWith(id: serverChatId, encryptionKey: serverKey);
    await LocalDatabase().deleteChat(widget.chat.id);
    await LocalDatabase().insertChat(updatedChat);
    setState(() => _encryptionKey = serverKey);

    int duration = recording.duration ?? 0;
    if (trimStart != null && trimEnd != null) duration = trimEnd - trimStart;

    final encrypted = await MediaService().encryptFile(recording.filePath, serverKey, fileName: path.basename(recording.filePath));
    
    final response = await ApiService().sendVoiceMessage(
      chatId: serverChatId,
      encryptedContent: encrypted.encryptedBase64,
      fileName: path.basename(recording.filePath),
      fileSize: encrypted.originalSize,
      duration: duration,
      waveform: recording.waveform,
      replyToMessageId: _replyingToMessage?.id,
    );

    final serverId = response.data['message_id'] as String;
    final serverTime = response.data['timestamp'] as int;
    final msServerTime = serverTime < 10000000000 ? serverTime * 1000 : serverTime;

    final message = MessageModel(
      id: serverId,
      chatId: serverChatId,
      senderId: _currentUserId!,
      content: '[Voice]',
      encryptedContent: encrypted.encryptedBase64,
      type: 'voice',
      timestamp: msServerTime,
      status: 'sent',
      fileName: path.basename(recording.filePath),
      fileSize: encrypted.originalSize,
      localPath: recording.filePath,
      duration: duration,
      waveform: recording.waveform,
      replyToMessageId: _replyingToMessage?.id,
      replyToContent: _replyingToMessage?.content,
      replyToSenderId: _replyingToMessage?.senderId,
    );

    await LocalDatabase().insertMessage(message, encryptionKey: serverKey);
    
    setState(() {
      _messages.insert(0, message);
      _isCreatingChat = false;
      _cancelReply();
    });
    _scrollToBottom();

  } catch (e) {
    setState(() => _isCreatingChat = false);
    _showError('Failed to send voice: $e');
  }
}

  Future<void> _sendVideoNote(VideoNoteResult result) async {
  if (_currentUserId == null) return;

  if (widget.isNewChat && widget.chat.id.startsWith('temp_')) {
    await _sendFirstVideoNote(result);
    return;
  }

  final key = _encryptionKey;
  if (key == null || key.isEmpty) {
    _showError('Encryption key not available');
    return;
  }

  setState(() => _isLoading = true);

  try {
    final encrypted = await MediaService().encryptFile(result.filePath, key, fileName: path.basename(result.filePath));
    
    final response = await ApiService().sendVideoNote(
      chatId: widget.chat.id,
      encryptedContent: encrypted.encryptedBase64,
      fileName: path.basename(result.filePath),
      fileSize: encrypted.originalSize,
      duration: result.duration,
      width: result.width,
      height: result.height,
      replyToMessageId: _replyingToMessage?.id,
    );

    final serverId = response.data['message_id'] as String;
    final serverTime = response.data['timestamp'] as int;
    final msServerTime = serverTime < 10000000000 ? serverTime * 1000 : serverTime;

    final message = MessageModel(
      id: serverId,
      chatId: widget.chat.id,
      senderId: _currentUserId!,
      content: '[Video Note]',
      encryptedContent: encrypted.encryptedBase64,
      type: 'video_note',
      timestamp: msServerTime,
      status: 'sent',
      fileName: path.basename(result.filePath),
      fileSize: encrypted.originalSize,
      localPath: result.filePath,
      width: result.width,
      height: result.height,
      duration: result.duration,
      replyToMessageId: _replyingToMessage?.id,
      replyToContent: _replyingToMessage?.content,
      replyToSenderId: _replyingToMessage?.senderId,
    );

    await LocalDatabase().insertMessage(message, encryptionKey: key);
    
    setState(() {
      _messages.insert(0, message);
      _isLoading = false;
      _cancelReply();
    });
    _scrollToBottom();

  } catch (e) {
    setState(() => _isLoading = false);
    _showError('Failed to send video note: $e');
  }
}

Future<void> _sendFirstVideoNote(VideoNoteResult result) async {
  if (_isCreatingChat) return;
  
  setState(() => _isCreatingChat = true);

  try {
    final chatResponse = await ApiService().createOrGetChat(
      chatId: widget.chat.id,
      otherUserId: widget.otherUserId!,
    );
    
    final serverChatId = chatResponse.data['chat_id'] as String;
    final serverKey = chatResponse.data['encryption_key'] as String;
    
    final updatedChat = widget.chat.copyWith(id: serverChatId, encryptionKey: serverKey);
    await LocalDatabase().deleteChat(widget.chat.id);
    await LocalDatabase().insertChat(updatedChat);
    setState(() => _encryptionKey = serverKey);

    final encrypted = await MediaService().encryptFile(result.filePath, serverKey, fileName: path.basename(result.filePath));
    
    final response = await ApiService().sendVideoNote(
      chatId: serverChatId,
      encryptedContent: encrypted.encryptedBase64,
      fileName: path.basename(result.filePath),
      fileSize: encrypted.originalSize,
      duration: result.duration,
      width: result.width,
      height: result.height,
      replyToMessageId: _replyingToMessage?.id,
    );

    final serverId = response.data['message_id'] as String;
    final serverTime = response.data['timestamp'] as int;
    final msServerTime = serverTime < 10000000000 ? serverTime * 1000 : serverTime;

    final message = MessageModel(
      id: serverId,
      chatId: serverChatId,
      senderId: _currentUserId!,
      content: '[Video Note]',
      encryptedContent: encrypted.encryptedBase64,
      type: 'video_note',
      timestamp: msServerTime,
      status: 'sent',
      fileName: path.basename(result.filePath),
      fileSize: encrypted.originalSize,
      localPath: result.filePath,
      width: result.width,
      height: result.height,
      duration: result.duration,
      replyToMessageId: _replyingToMessage?.id,
      replyToContent: _replyingToMessage?.content,
      replyToSenderId: _replyingToMessage?.senderId,
    );

    await LocalDatabase().insertMessage(message, encryptionKey: serverKey);
    
    setState(() {
      _messages.insert(0, message);
      _isCreatingChat = false;
      _cancelReply();
    });
    _scrollToBottom();

  } catch (e) {
    setState(() => _isCreatingChat = false);
    _showError('Failed to send video note: $e');
  }
}

  // === UI МЕТОДЫ ===

  void _showVoicePreview(VoiceRecordingResult recording) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => VoicePreviewSheet(
      recording: recording,
      onSend: (trimStart, trimEnd) {
        Navigator.pop(context);
        _sendVoiceMessage(recording, trimStart: trimStart, trimEnd: trimEnd);
      },
      onCancel: () {
        Navigator.pop(context);
        try {
          File(recording.filePath).delete();
        } catch (e) {}
      },
    ),
  );
}

  void _showVideoNotePreview(VideoNoteResult result) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => video.VideoNotePreviewSheet(
        result: result,
        onSend: () {
          Navigator.pop(context);
          _sendVideoNote(result);
        },
        onCancel: () {
          Navigator.pop(context);
          try {
            File(result.filePath).delete();
            if (result.thumbnail != null) {
              File(result.thumbnail!).delete();
            }
          } catch (e) {}
        },
      ),
    );
  }


  Future<void> _deleteMessage(MessageModel message, {required bool forEveryone}) async {
    setState(() {
      _messages.removeWhere((m) => m.id == message.id);
    });
    
    try {
      if (forEveryone) {
        await ApiService().deleteMessage(message.id, forEveryone: true);
        await LocalDatabase().deleteMessage(message.id);
        
        if (message.localPath != null) {
          try {
            await File(message.localPath!).delete();
          } catch (e) {
            print('⚠️ Failed to delete local file: $e');
          }
        }
      } else {
        await ApiService().hideMessageForMe(message.id);
        await LocalDatabase().deleteMessage(message.id);
        await LocalDatabase().hideMessageLocally(message.id);
        
        if (message.localPath != null) {
          try {
            await File(message.localPath!).delete();
          } catch (e) {
            print('⚠️ Failed to delete local file: $e');
          }
        }
        
        print('🙈 Message ${message.id} deleted for me');
      }
    } catch (e) {
      print('❌ Failed to delete message: $e');
      _showError('Failed to delete: $e');
      _loadMessages();
    }
  }

  // === ОСТАЛЬНЫЕ МЕТОДЫ (forward, search, и т.д.) без изменений ===

  void _showForwardDialog(MessageModel message) async {
    final chats = await ApiService().getAllChats();
    
    if (!mounted) return;
    
    final sourceChat = await LocalDatabase().getChat(message.chatId);
    if (sourceChat == null) {
      _showError('Source chat not found');
      return;
    }
    
    bool expandUser = false;
    
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          return DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.3,
            maxChildSize: 0.9,
            builder: (_, controller) => Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Forward to...',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        Checkbox(
                          value: expandUser,
                          onChanged: (v) {
                            setModalState(() {
                              expandUser = v ?? false;
                            });
                          },
                        ),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Expand user'),
                              Text(
                                'Show "forwarded from @username"',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const Divider(),
                  
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      itemCount: chats.length,
                      itemBuilder: (context, index) {
                        final chat = chats[index];
                        final isCurrentChat = chat['id'] == widget.chat.id;
                        
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundImage: chat['avatar_url']?.isNotEmpty == true
                                ? NetworkImage('http://45.132.255.167:8080   ${chat['avatar_url']}')
                                : null,
                            child: chat['avatar_url']?.isEmpty != false
                                ? Text((chat['display_name'] ?? chat['username'])[0].toUpperCase())
                                : null,
                          ),
                          title: Text(chat['display_name'] ?? chat['username']),
                          subtitle: isCurrentChat ? const Text('Current chat') : null,
                          trailing: isCurrentChat 
                              ? const Icon(Icons.check_circle, color: Colors.green)
                              : null,
                          enabled: !isCurrentChat,
                          onTap: isCurrentChat 
                              ? null 
                              : () async {
                                  Navigator.pop(context);
                                  
                                  showDialog(
                                    context: this.context,
                                    barrierDismissible: false,
                                    builder: (dialogContext) => const Center(child: CircularProgressIndicator()),
                                  );
                                  
                                  try {
                                    await _forwardMessageWithReencryption(
                                      message: message,
                                      targetChatId: chat['id'],
                                      sourceEncryptionKey: sourceChat.encryptionKey!,
                                      expandUser: expandUser,
                                      targetChatInfo: chat,
                                    );
                                    
                                    if (mounted) {
                                      Navigator.of(this.context).pop();
                                    }
                                    
                                  } catch (e) {
                                    if (mounted) {
                                      Navigator.of(this.context).pop();
                                      _showError('Failed to forward: $e');
                                    }
                                  }
                                },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _forwardMessageWithReencryption({
  required MessageModel message,
  required String targetChatId,
  required String sourceEncryptionKey,
  required bool expandUser,
  required Map<String, dynamic> targetChatInfo,
}) async {
  try {
    print('🔄 Forwarding with reencryption: ${message.id} -> $targetChatId');
    
    final targetChat = await LocalDatabase().getChat(targetChatId);
    String targetEncryptionKey;
    
    if (targetChat != null && targetChat.encryptionKey != null) {
      targetEncryptionKey = targetChat.encryptionKey!;
    } else {
      final response = await ApiService().createOrGetChat(
        chatId: targetChatId,
        otherUserId: targetChatInfo['user_id'],
      );
      targetEncryptionKey = response.data['encryption_key'] as String;
    }
    
    String? forwardedFrom;
    String? originalSenderUsername;
    if (expandUser) {
      String originalSenderName = 'unknown';
      if (message.senderId == _currentUserId) {
        final myProfile = await ApiService().getMyProfile();
        originalSenderName = myProfile.data['username'] ?? 'me';
      } else {
        final sender = await ApiService().getUserById(message.senderId);
        originalSenderName = sender?['username'] ?? 'unknown';
      }
      originalSenderUsername = originalSenderName;
      forwardedFrom = '@$originalSenderName';
    } else {
      forwardedFrom = 'hidden';
    }
    
    String reencryptedContent;
    String messageType = message.type;
    String? caption = message.content.isNotEmpty ? message.content : null;
    String? fileName = message.fileName;
    int? fileSize = message.fileSize;
    int? width = message.width;
    int? height = message.height;
    int? duration = message.duration;
    
    // === КЛЮЧЕВОЕ ИСПРАВЛЕНИЕ: правильная обработка разных типов медиа ===
    if (message.type == 'album') {
      // Альбом - encryptedContent это JSON массив
      final List<dynamic> mediaItems = jsonDecode(message.encryptedContent!);
      final List<Map<String, dynamic>> reencryptedItems = [];
      
      for (final item in mediaItems) {
        final encryptedBase64 = item['encrypted_content'] as String;
        final decryptedBytes = EncryptionService.decryptFile(encryptedBase64, sourceEncryptionKey);
        final newEncrypted = EncryptionService.encryptFile(decryptedBytes, targetEncryptionKey);
        
        reencryptedItems.add({
          'index': item['index'],
          'type': item['type'],
          'encrypted_content': newEncrypted,
          'file_name': item['file_name'],
          'file_size': item['file_size'],
          'width': item['width'],
          'height': item['height'],
          'duration': item['duration'],
        });
      }
      
      reencryptedContent = jsonEncode(reencryptedItems);
      messageType = 'album';
      
    } else if (message.isMedia || message.type == 'sticker') {
      // Одиночное медиа или стикер - encryptedContent это просто base64 строка
      String encryptedBase64;
      
      if (message.localPath != null && File(message.localPath!).existsSync()) {
        // Читаем и шифруем заново из локального файла (оптимально)
        final fileBytes = await File(message.localPath!).readAsBytes();
        reencryptedContent = EncryptionService.encryptFile(fileBytes, targetEncryptionKey);
      } else {
        // Скачиваем с сервера
        encryptedBase64 = await ApiService().downloadMedia(message.id);
        final decryptedBytes = EncryptionService.decryptFile(encryptedBase64, sourceEncryptionKey);
        reencryptedContent = EncryptionService.encryptFile(decryptedBytes, targetEncryptionKey);
      }
      
      // Для стикера сохраняем тип
      if (message.type == 'sticker') {
        messageType = 'sticker';
      } else if (message.isVideo) {
        messageType = 'video';
      } else {
        messageType = 'image';
      }
      
    } else {
      // Текст
      final decryptedText = EncryptionService.decryptMessage(
        message.encryptedContent!, 
        sourceEncryptionKey
      );
      reencryptedContent = EncryptionService.encryptMessage(decryptedText, targetEncryptionKey);
      messageType = 'text';
    }
    
    // === ИСПРАВЛЕНИЕ: правильный вызов API в зависимости от типа ===
    late Response response;
    
    if (messageType == 'album') {
      // Альбом через специальный метод
      final List<dynamic> items = jsonDecode(reencryptedContent);
      response = await ApiService().forwardMediaAlbum(
        messageId: message.id,
        targetChatId: targetChatId,
        mediaItems: items.cast<Map<String, dynamic>>(),
        caption: caption,
        expandUser: expandUser,
        forwardedFrom: forwardedFrom,
        originalSenderUsername: originalSenderUsername,
      );
    } else if (messageType == 'sticker') {
      // Стикер
      response = await ApiService().forwardSticker(
        messageId: message.id,
        targetChatId: targetChatId,
        encryptedContent: reencryptedContent,
        fileName: fileName ?? 'sticker.webp',
        fileSize: fileSize ?? 0,
        width: width ?? 512,
        height: height ?? 512,
        expandUser: expandUser,
        forwardedFrom: forwardedFrom,
        originalSenderUsername: originalSenderUsername,
      );
    } else if (messageType == 'image' || messageType == 'video') {
      // Одиночное медиа
      response = await ApiService().forwardMediaMessage(
        messageId: message.id,
        targetChatId: targetChatId,
        encryptedContent: reencryptedContent,
        type: messageType,
        caption: caption,
        fileName: fileName,
        fileSize: fileSize,
        width: width,
        height: height,
        duration: duration,
        expandUser: expandUser,
        forwardedFrom: forwardedFrom,
        originalSenderUsername: originalSenderUsername,
      );
    } else {
      // Текст
      response = await ApiService().forwardMessage(
        messageId: message.id,
        targetChatId: targetChatId,
        encryptedContent: reencryptedContent,
        expandUser: expandUser,
        forwardedFrom: forwardedFrom,
        originalSenderUsername: originalSenderUsername,
      );
    }
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(expandUser 
          ? 'Forwarded with sender info' 
          : 'Forwarded anonymously'),
      ),
    );
    
    print('✅ Forwarded successfully: ${response.data['message_id']}');
    
  } catch (e, stack) {
    print('❌ Forward failed: $e');
    print(stack);
    _showError('Failed to forward: $e');
  }
}

  void _showReportDialog(MessageModel message) {
    final reasons = [
      'Spam',
      'Harassment',
      'Inappropriate content',
      'Violence',
      'Other',
    ];

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Report message',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ...reasons.map((reason) => ListTile(
              title: Text(reason),
              onTap: () {
                Navigator.pop(context);
                _reportMessage(message, reason);
              },
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _reportMessage(MessageModel message, String reason) async {
    try {
      await ApiService().reportUser(message.senderId, 'Message report: $reason');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report sent. Thank you!')),
      );
    } catch (e) {
      _showError('Failed to send report: $e');
    }
  }

  List<TextSpan> _parseMessageText(String text, Color defaultColor) {
  final spans = <TextSpan>[];
  final regex = RegExp(r'@(\w+)');
  final matches = regex.allMatches(text);
  
  int lastEnd = 0;
  
  for (final match in matches) {
    if (match.start > lastEnd) {
      spans.add(TextSpan(
        text: text.substring(lastEnd, match.start),
        style: TextStyle(color: defaultColor),
      ));
    }
    
    final username = match.group(1)!;
    spans.add(TextSpan(
      text: match.group(0),
      style: const TextStyle(
        color: Colors.blue,
        fontWeight: FontWeight.bold,
        decoration: TextDecoration.underline,
      ),
      recognizer: TapGestureRecognizer()..onTap = () => _onUsernameTap(username),
    ));
    
    lastEnd = match.end;
  }
  
  if (lastEnd < text.length) {
    spans.add(TextSpan(
      text: text.substring(lastEnd),
      style: TextStyle(color: defaultColor),
    ));
  }
  
  return spans.isEmpty 
      ? [TextSpan(text: text, style: TextStyle(color: defaultColor))]
      : spans;
}

    Widget _buildStickersContent() {
  if (_installedPacks.isEmpty) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.emoji_emotions_outlined, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(
            'No stickers installed',
            style: TextStyle(color: Colors.grey.shade500),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _openStickerStore,
            child: const Text('Get Stickers'),
          ),
        ],
      ),
    );
  }

  return Column(
    children: [
      Container(
        height: 60,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          itemCount: _installedPacks.length + 1,
          itemBuilder: (context, index) {
            if (index == _installedPacks.length) {
              return _buildAddPackButton();
            }
            return _buildPackIcon(index);
          },
        ),
      ),
      const Divider(height: 1),
      Expanded(
        child: _loadingStickers
            ? const Center(child: CircularProgressIndicator())
            : GridView.builder(
                padding: const EdgeInsets.all(8),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 1,
                ),
                itemCount: _currentStickers.length,
                itemBuilder: (context, index) {
                  return _buildStickerItem(_currentStickers[index]);
                },
              ),
      ),
    ],
  );
}

  Widget _buildPackIcon(int index) {
    final pack = _installedPacks[index];
    final isSelected = index == _selectedPackIndex;
    
    return GestureDetector(
      onTap: () => _loadPackStickers(index),
      onLongPress: () => _showPackOptions(pack),
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(color: Theme.of(context).colorScheme.primary, width: 2)
              : null,
          color: isSelected 
              ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
              : Colors.grey.shade100,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: _buildPackThumbnail(pack),
        ),
      ),
    );
  }

  Widget _buildPackThumbnail(StickerPackModel pack) {
    return FutureBuilder<List<StickerModel>>(
      future: _stickerService.getPackStickers(pack.id),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final first = snapshot.data!.first;
          if (first.localPath != null) {
            return Image.file(
              File(first.localPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildDefaultThumbnail(pack),
            );
          }
        }
        return _buildDefaultThumbnail(pack);
      },
    );
  }

  Widget _buildDefaultThumbnail(StickerPackModel pack) {
    return Center(
      child: Text(
        pack.name[0].toUpperCase(),
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildAddPackButton() {
    return GestureDetector(
      onTap: _openStickerStore,
      child: Container(
        width: 44,
        height: 44,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
          color: Colors.grey.shade50,
        ),
        child: Icon(
          Icons.add,
          color: Theme.of(context).colorScheme.primary,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildStickerItem(StickerModel sticker) {
    return GestureDetector(
      onTap: () => _sendSticker(sticker),
      child: Container(
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey.shade50,
        ),
        child: sticker.localPath != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(sticker.localPath!),
                  fit: BoxFit.contain,
                ),
              )
            : const Icon(Icons.image, color: Colors.grey),
      ),
    );
  }

 Future<void> _sendSticker(StickerModel sticker) async {
  if (_currentUserId == null) return;

  if (widget.isNewChat && widget.chat.id.startsWith('temp_')) {
    await _sendFirstSticker(sticker);
    return;
  }

  final key = _encryptionKey;
  if (key == null || key.isEmpty) {
    _showError('Encryption key not available');
    return;
  }

  setState(() => _showEmojiPicker = false);

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final tempId = 'temp_sticker_${timestamp}_${_messages.length}';

  try {
    final file = File(sticker.localPath!);
    final bytes = await file.readAsBytes();
    
    final encrypted = EncryptionService.encryptFile(bytes, key);

    final tempMessage = MessageModel(
      id: tempId,
      chatId: widget.chat.id,
      senderId: _currentUserId!,
      content: '[Sticker]',
      encryptedContent: encrypted,
      type: 'sticker',
      timestamp: timestamp,
      status: 'sending',
      fileName: sticker.fileName,
      fileSize: bytes.length,
      localPath: sticker.localPath,
      width: 512,
      height: 512,
    );

    setState(() => _messages.insert(0, tempMessage));
    _scrollToBottom();

    final response = await ApiService().sendSticker(
      chatId: widget.chat.id,
      encryptedContent: encrypted,
      fileName: sticker.fileName,
      fileSize: bytes.length,
      width: 512,
      height: 512,
    );

    final serverId = response.data['message_id'] as String;
    final serverTime = response.data['timestamp'] as int;
    final msServerTime = serverTime < 10000000000 ? serverTime * 1000 : serverTime;

    final sentMessage = tempMessage.copyWith(
      id: serverId,
      timestamp: msServerTime,
      status: 'sent',
    );

    setState(() {
      final index = _messages.indexWhere((m) => m.id == tempId);
      if (index != -1) _messages[index] = sentMessage;
    });

    await LocalDatabase().insertMessage(sentMessage, encryptionKey: key);

  } catch (e) {
    setState(() {
      final index = _messages.indexWhere((m) => m.id == tempId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(status: 'failed');
      }
    });
    _showError('Failed to send sticker: $e');
  }
}

  Future<void> _sendFirstSticker(StickerModel sticker) async {
  if (_isCreatingChat) return;
  
  setState(() => _isCreatingChat = true);
  
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final tempId = 'temp_${timestamp}_${_messages.length}';

  final tempMessage = MessageModel(
    id: tempId,
    chatId: widget.chat.id,
    senderId: _currentUserId!,
    content: '',
    encryptedContent: '',
    type: 'sticker',
    timestamp: timestamp,
    status: 'sending',
    fileName: sticker.fileName,
    localPath: sticker.localPath,
    width: 512,
    height: 512,
  );

  setState(() => _messages.insert(0, tempMessage));
  _scrollToBottom();

  try {
    final chatResponse = await ApiService().createOrGetChat(
      chatId: widget.chat.id,
      otherUserId: widget.otherUserId!,
    );
    
    final serverChatId = chatResponse.data['chat_id'] as String;
    final serverKey = chatResponse.data['encryption_key'] as String;
    
    final updatedChat = widget.chat.copyWith(
      id: serverChatId,
      encryptionKey: serverKey,
    );
    await LocalDatabase().deleteChat(widget.chat.id);
    await LocalDatabase().insertChat(updatedChat);
    setState(() => _encryptionKey = serverKey);

    final file = File(sticker.localPath!);
    final bytes = await file.readAsBytes();
    final encrypted = EncryptionService.encryptFile(bytes, serverKey);

    final msgResponse = await ApiService().sendSticker(
      chatId: serverChatId,
      encryptedContent: encrypted,
      fileName: sticker.fileName,
      fileSize: bytes.length,
    );

    final serverMessageId = msgResponse.data['message_id'] as String;
    final serverTime = msgResponse.data['timestamp'] as int;
    final msServerTime = serverTime < 10000000000 ? serverTime * 1000 : serverTime;

    final sentMessage = tempMessage.copyWith(
      id: serverMessageId,
      chatId: serverChatId,
      encryptedContent: encrypted,
      timestamp: msServerTime,
      status: 'sent',
    );

    setState(() {
      final index = _messages.indexWhere((m) => m.id == tempId);
      if (index != -1) _messages[index] = sentMessage;
    });

    await LocalDatabase().insertMessage(sentMessage, encryptionKey: serverKey);

  } catch (e) {
    setState(() {
      final index = _messages.indexWhere((m) => m.id == tempId);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(status: 'failed');
      }
    });
    _showError('Failed to send: $e');
  } finally {
    setState(() => _isCreatingChat = false);
  }
}

  void _showPackOptions(StickerPackModel pack) {
  showModalBottomSheet(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(pack.name),
            subtitle: Text('${pack.stickerCount} stickers'),
          ),
          const Divider(),
          
          // === МОЙ ПАК: Add Stickers + Delete Pack ===
          if (pack.isMine) ...[
            ListTile(
              leading: const Icon(Icons.add_photo_alternate),
              title: const Text('Add Stickers'),
              onTap: () {
                Navigator.pop(context);
                _addStickersToPack(pack);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('Delete Pack', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(context);
                _deletePack(pack); // Удаляет с сервера полностью
              },
            ),
          ] 
          
          // === ЧУЖОЙ ПАК (Official или Community): Remove ===
          else ...[
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Remove'),
              onTap: () {
                Navigator.pop(context);
                _removePack(pack); // Удаляет только у меня
              },
            ),
          ],
          
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

  Future<void> _addStickersToPack(StickerPackModel pack) async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    if (picked.isEmpty) return;

    final files = picked.map((x) => File(x.path)).toList();
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final success = await _stickerService.addStickersToPack(pack.id, files);
    
    if (mounted) {
      Navigator.pop(context);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Stickers added!')),
        );
        // === ИСПРАВЛЕНО: Принудительно перезагружаем текущий пак ===
        await _loadPackStickers(_selectedPackIndex);
      }
    }
  }

  Future<void> _deletePack(StickerPackModel pack) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Pack?'),
        content: Text('Delete "${pack.name}" permanently?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _stickerService.deletePack(pack);
      _loadInstalledPacks();
    }
  }

  Future<void> _removePack(StickerPackModel pack) async {
    await _stickerService.deletePack(pack);
    _loadInstalledPacks();
  }

  void _openStickerStore() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StickerStoreSheet(
        onPackInstalled: () {
          print('✅ Pack installed from store, reloading...');
          // === ИСПРАВЛЕНО: Принудительно перезагружаем ===
          _loadInstalledPacks();
        },
      ),
    );
  }

  Future<void> _onUsernameTap(String username) async {
    final users = await ApiService().searchUsers(username);
    final exactMatch = users.firstWhere(
      (u) => u['username'].toString().toLowerCase() == username.toLowerCase(),
      orElse: () => {},
    );
    
    if (exactMatch.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User @$username not found')),
      );
      return;
    }
    
    final userId = exactMatch['id'];
    
    final existingChat = await LocalDatabase().getChatByUserId(userId);
    
    if (existingChat != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(chat: existingChat)),
      );
    } else {
      final tempChat = ChatModel(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}_$userId',
        userId: userId,
        username: exactMatch['username'],
        displayName: exactMatch['display_name'],
        avatarUrl: exactMatch['avatar_url'],
        encryptionKey: null,
      );
      
      await LocalDatabase().insertChat(tempChat);
      
      Navigator.push(
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
  }

  // === ЗАГРУЗКА СООБЩЕНИЙ ===

  Future<void> _loadCurrentUser() async {
    _currentUserId = await LocalDatabase().getCurrentUserId();
    if (mounted) setState(() {});
  }

  bool _isSyncing = false;

Future<void> _syncMessagesFromServer() async {
  if (!WebSocketService().isConnected) {
    print('⚠️ No WebSocket connection, skipping sync');
    return;
  }
  
  if (_isSyncing) {
    print('⏭️ Sync already in progress, skipping duplicate');
    return;
  }
  
  // Ждём инициализации ключа
  if (_encryptionKey == null) {
    print('⏳ Waiting for encryption key...');
    await _initializeEncryptionKey();
  }
  
  final key = _encryptionKey;
  if (key == null || key.isEmpty) {
    print('❌ Cannot sync: encryption key not available');
    return;
  }
  
  _isSyncing = true;
  print('🔄 === STARTING SYNC for chat: ${widget.chat.id} ===');
  
  try {
    final response = await ApiService().getMessages(widget.chat.id);
    final serverMessages = response.data['messages'] as List<dynamic>? ?? [];
    
    print('📥 Server returned ${serverMessages.length} messages');
    
    final hiddenIds = await LocalDatabase().getAllHiddenMessageIds();
    print('🙈 Locally hidden messages: ${hiddenIds.length}');
    
    int newCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;
    int errorCount = 0;
    List<String> errorDetails = [];

    for (int i = 0; i < serverMessages.length; i++) {
      final msgData = serverMessages[i] as Map<String, dynamic>;
      final msgId = msgData['id']?.toString() ?? 'unknown_$i';
      
      if (hiddenIds.contains(msgId)) {
        print('🙈 Skipping hidden message: $msgId');
        skippedCount++;
        continue;
      }
      
      try {
        final type = msgData['type']?.toString() ?? 'text';
        String content = msgData['content'] ?? '';
        String? localPath;
        
        final existingMsg = await LocalDatabase().getMessage(msgId);
        final existingIndex = _messages.indexWhere((m) => m.id == msgId);
        
        switch (type) {
          case 'text':
            final encrypted = msgData['encrypted_content']?.toString();
            if (encrypted != null && encrypted.isNotEmpty) {
              try {
                content = EncryptionService.decryptMessage(encrypted, key);
              } catch (e) {
                print('   ❌ Text decrypt error: $e');
                content = '[Decrypt error]';
              }
            }
            break;
            
          case 'sticker':
            print('   🎨 Processing STICKER: $msgId');
            
            if (existingMsg?.localPath != null && File(existingMsg!.localPath!).existsSync()) {
              print('   ✅ Using EXISTING sticker from DB: ${existingMsg.localPath}');
              localPath = existingMsg.localPath;
            } else if (existingIndex != -1 && 
                      _messages[existingIndex].localPath != null &&
                      File(_messages[existingIndex].localPath!).existsSync()) {
              print('   ✅ Using EXISTING sticker from memory: ${_messages[existingIndex].localPath}');
              localPath = _messages[existingIndex].localPath;
            } else {
              final encrypted = msgData['encrypted_content']?.toString();
              if (encrypted != null && encrypted.isNotEmpty) {
                try {
                  final fileName = msgData['file_name']?.toString() ?? 'sticker_$msgId.webp';
                  
                  localPath = await MediaService().decryptAndSave(
                    encrypted, 
                    key, 
                    fileName,
                  );
                  print('   ✅ Sticker saved to: $localPath');
                } catch (e, stack) {
                  print('   ❌ Sticker decrypt FAILED: $e');
                  localPath = null;
                }
              }
            }
            
            content = '';
            break;

          case 'album':
            print('   📁 Processing ALBUM: $msgId');
            content = msgData['caption']?.toString() ?? '';
            if (existingMsg?.localPath != null) {
              final paths = existingMsg!.localPath!.split(',');
              final allExist = paths.every((p) => File(p).existsSync());
              if (allExist) {
                print('   ✅ Using EXISTING album files from DB');
                localPath = existingMsg.localPath;
              } else {
                print('   ⚠️ Some album files missing, will re-download on click');
                localPath = null;
              }
            }
            break;

          case 'image':
          case 'video':
            print('   📷 Processing MEDIA ($type): $msgId');
            
            if (existingMsg?.localPath != null && File(existingMsg!.localPath!).existsSync()) {
              print('   ✅ Using EXISTING media from DB: ${existingMsg.localPath}');
              localPath = existingMsg.localPath;
            } else if (existingIndex != -1 && 
                      _messages[existingIndex].localPath != null &&
                      File(_messages[existingIndex].localPath!).existsSync()) {
              print('   ✅ Using EXISTING media from memory: ${_messages[existingIndex].localPath}');
              localPath = _messages[existingIndex].localPath;
            } else {
              final encrypted = msgData['encrypted_content']?.toString();
              
              if (encrypted != null && encrypted.isNotEmpty) {
                final fileName = msgData['file_name']?.toString() ?? 
                                msgData['fileName']?.toString() ?? 
                                'media_$msgId';
                
                try {
                  localPath = await MediaService().decryptAndSave(
                    encrypted, 
                    key, 
                    fileName,
                  );
                  content = msgData['caption']?.toString() ?? '';
                } catch (e, stack) {
                  print('   ❌ Media decrypt FAILED: $e');
                  content = '[Media failed]';
                  localPath = null;
                }
              } else {
                content = '[Media pending]';
              }
            }
            break;
            
          default:
            print('   ⚠️ Unknown type: $type, treating as text');
        }

        final messageData = {
          ...msgData,
          'chat_id': widget.chat.id,
          'content': content,
          'local_path': localPath,
          'type': type,
        };
        
        final message = MessageModel.fromServer(messageData);
        
        if (message.type != type) {
          print('   ⚠️ Type mismatch! Server: $type, Model: ${message.type}');
        }
        
        await LocalDatabase().insertMessage(message, encryptionKey: key);
        
        String lastMessageText;
        if (type == 'text') {
          lastMessageText = message.encryptedContent ?? content;
        } else if (type == 'sticker') {
          lastMessageText = '[Стикер]';
        } else {
          lastMessageText = content.isNotEmpty ? content : '[Медиа]';
        }
        
        await LocalDatabase().updateChatLastMessage(
          widget.chat.id,
          lastMessageText,
          message.timestamp,
          senderId: message.senderId,
          status: 'delivered',
          messageType: type,
          encryptionKey: key,
        );

        if (message.senderId != _currentUserId && !message.isRead) {
          WebSocketService().markMessageRead(widget.chat.id, message.id);
        }

        if (mounted) {
          setState(() {
            if (existingIndex != -1) {
              if (_messages[existingIndex].localPath != message.localPath ||
                  _messages[existingIndex].status != message.status ||
                  _messages[existingIndex].isRead != message.isRead) {
                _messages[existingIndex] = message;
                updatedCount++;
              }
            } else {
              _messages.insert(0, message);
              newCount++;
            }
          });
        }
        
      } catch (e, stack) {
        print('   ❌ CRITICAL ERROR processing $msgId: $e');
        errorCount++;
        errorDetails.add('$msgId: $e');
      }
    }
    
    print('\n=== SYNC SUMMARY ===');
    print('Total from server: ${serverMessages.length}');
    print('New added: $newCount');
    print('Updated: $updatedCount');
    print('Skipped (hidden): $skippedCount');
    print('Errors: $errorCount');
    
    if (mounted && (newCount > 0 || updatedCount > 0)) {
      setState(() {
        _messages.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      });
    }
    
  } catch (e, stack) {
    print('❌ SYNC FAILED: $e');
    print(stack);
  } finally {
    _isSyncing = false;
  }
}

  Future<void> _loadMessages() async {
  print('📂 === STARTING _loadMessages ===');
  setState(() => _isLoading = true);
  
  try {
    // 1. Загружаем из локальной БД (всегда, даже без интернета)
    final dbMessages = await LocalDatabase().getMessages(widget.chat.id);
    print('📂 Loaded ${dbMessages.length} messages from database');
    
    if (mounted) {
      setState(() {
        _messages.clear();
        _messages.addAll(dbMessages..sort((a, b) => b.timestamp.compareTo(a.timestamp)));
      });
    }
    
    // 2. Если есть интернет — синхронизируем с сервером
    if (WebSocketService().isConnected && !widget.isNewChat) {
      print('🌐 Online, syncing with server...');
      await _syncMessagesFromServer().then((_) => _markIncomingAsRead());
    } else {
      print('📴 Offline or new chat, using local data only');
    }
    
    // 3. Применяем отложенные статусы
    int appliedPending = 0;
    for (var pendingId in _pendingStatusUpdates.keys.toList()) {
      final index = _messages.indexWhere((m) => m.id == pendingId);
      if (index != -1) {
        final pending = _pendingStatusUpdates[pendingId];
        if (pending?['type'] == 'delivered') {
          _updateMessageStatus(pendingId, 'delivered', isDelivered: true);
        } else if (pending?['type'] == 'read') {
          _updateMessageStatus(pendingId, 'read', isRead: true);
        }
        appliedPending++;
      }
    }
    
    _scrollToBottom();
    
  } catch (e, stack) {
    print('❌ _loadMessages failed: $e');
    // Даже при ошибке показываем то, что есть в локальной БД
  } finally {
    if (mounted) setState(() => _isLoading = false);
  }
}

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients && mounted) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChanged(String text) {
    setState(() {});
    
    if (text.isNotEmpty || _attachedMediaList.isNotEmpty) {
      WebSocketService().sendTypingStart(widget.chat.id);
      _typingDebounceTimer?.cancel();
      _typingDebounceTimer = Timer(const Duration(seconds: 3), () {
        if (_messageCtrl.text.isEmpty && _attachedMediaList.isEmpty) {
          WebSocketService().sendTypingStop(widget.chat.id);
        }
      });
    } else {
      WebSocketService().sendTypingStop(widget.chat.id);
    }
  }

  void _insertEmoji(String emoji) {
    final text = _messageCtrl.text;
    final selection = _messageCtrl.selection;
    
    final newText = text.replaceRange(
      selection.start,
      selection.end,
      emoji,
    );
    
    _messageCtrl.text = newText;
    _messageCtrl.selection = TextSelection.collapsed(
      offset: selection.start + emoji.length,
    );
    
    setState(() {});
    _onTextChanged(newText);
  }

    Widget _buildEmojiPicker() {
    return Container(
      height: 250,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      child: Column(
        children: [
          Container(
            height: 40,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.grey.shade200),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _showStickersTab = true),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _showStickersTab 
                                ? Theme.of(context).colorScheme.primary 
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        'Stickers',
                        style: TextStyle(
                          color: _showStickersTab 
                              ? Theme.of(context).colorScheme.primary 
                              : Colors.grey.shade400,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _showStickersTab = false),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: !_showStickersTab 
                                ? Theme.of(context).colorScheme.primary 
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                      child: Text(
                        'Smiles',
                        style: TextStyle(
                          color: !_showStickersTab 
                              ? Theme.of(context).colorScheme.primary 
                              : Colors.grey.shade400,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _showStickersTab 
                ? _buildStickersContent()
                : GridView.builder(
                    padding: const EdgeInsets.all(8),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 8,
                      childAspectRatio: 1,
                    ),
                    itemCount: _emojis.length,
                    itemBuilder: (context, index) {
                      return InkWell(
                        onTap: () => _insertEmoji(_emojis[index]),
                        child: Center(
                          child: Text(
                            _emojis[index],
                            style: const TextStyle(fontSize: 24),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatLastSeen(int? timestamp) {
    final l10n = context.l10n;
    
    if (_otherUserStatus == 'online') return l10n.statusOnline;
    if (timestamp == null) return l10n.statusOffline;
    
    final now = DateTime.now();
    final lastSeen = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final diff = now.difference(lastSeen);
    
    if (diff.inMinutes < 1) return l10n.statusJustNow;
    if (diff.inMinutes < 60) return l10n.statusMinutesAgo(diff.inMinutes);
    if (diff.inHours < 24) return l10n.statusHoursAgo(diff.inHours);
    return l10n.statusDaysAgo(diff.inDays);
  }

  void _showError(String message) {
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        action: message == l10n.errorNetwork 
            ? SnackBarAction(
                label: l10n.actionRetry,
                textColor: Colors.white,
                onPressed: () {},
              )
            : null,
      ),
    );
  }

  Widget _buildReactionsRow(MessageModel msg) {
    if (msg.reactions.isEmpty) return const SizedBox.shrink();
    
    final reactionCounts = <String, int>{};
    final userReaction = msg.reactions[_currentUserId];
    
    for (final reaction in msg.reactions.values) {
      reactionCounts[reaction] = (reactionCounts[reaction] ?? 0) + 1;
    }
    
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 4,
        children: reactionCounts.entries.map((entry) {
          final reaction = _reactionTypes.firstWhere(
            (r) => r['name'] == entry.key,
            orElse: () => {'emoji': '👍', 'name': entry.key},
          );
          final isMine = userReaction == entry.key;
          
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isMine 
                  ? Theme.of(context).colorScheme.primaryContainer 
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
              border: isMine 
                  ? Border.all(color: Theme.of(context).colorScheme.primary)
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(reaction['emoji'] as String, style: const TextStyle(fontSize: 12)),
                const SizedBox(width: 2),
                Text(
                  '${entry.value}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isMine 
                        ? Theme.of(context).colorScheme.primary 
                        : Colors.grey.shade700,
                    fontWeight: isMine ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

     Widget _buildVoiceMessage(MessageModel msg, bool isMe, String timeStr) {
  final colorScheme = Theme.of(context).colorScheme;
  final bool hasFile = msg.localPath != null && File(msg.localPath!).existsSync();
  final bool isDownloading = msg.status == 'sending' && !hasFile;
  
  // Проверяем есть ли waveform данные
  final bool hasWaveform = msg.waveform != null && msg.waveform!.isNotEmpty;
  
  return Align(
    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
      child: GestureDetector(
        onTap: () {
          if (hasFile) {
            _playVoiceMessage(msg);
          } else if (!isDownloading) {
            _downloadMedia(msg, openAfterDownload: false);
          }
        },
        onLongPress: () => _showMessageActions(msg, isMe),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isMe ? colorScheme.primary : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(18).copyWith(
              bottomRight: isMe ? const Radius.circular(4) : null,
              bottomLeft: !isMe ? const Radius.circular(4) : null,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Кнопка play/загрузка
                  GestureDetector(
                    onTap: () {
                      if (hasFile) {
                        _playVoiceMessage(msg);
                      } else if (!isDownloading) {
                        _downloadMedia(msg, openAfterDownload: false);
                      }
                    },
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isMe 
                            ? Colors.white.withOpacity(0.2) 
                            : colorScheme.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: isDownloading
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: isMe ? Colors.white : colorScheme.primary,
                              ),
                            )
                          : Icon(
                              hasFile 
                                  ? ((msg.isPlaying ?? false) ? Icons.pause : Icons.play_arrow)
                                  : Icons.download,
                              color: isMe ? Colors.white : colorScheme.primary,
                              size: 24,
                            ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // === ИСПРАВЛЕННЫЙ WAVEFORM С SEEK ===
                  if (hasFile && hasWaveform)
                    GestureDetector(
                      onTapDown: (details) {
                        final RenderBox box = context.findRenderObject() as RenderBox;
                        final localPosition = box.globalToLocal(details.globalPosition);
                        const waveformWidth = 120.0;
                        const leftOffset = 64.0; // 52 + отступы
                        final seekPercent = (localPosition.dx - leftOffset) / waveformWidth;
                        if (seekPercent >= 0 && seekPercent <= 1) {
                          _seekVoiceMessage(msg, seekPercent);
                        }
                      },
                      child: SizedBox(
                        width: 120,
                        height: 36,
                        child: _buildVoiceWaveform(msg.waveform!, msg, isMe),
                      ),
                    )
                  else if (hasFile && !hasWaveform)
                    SizedBox(
                      width: 120,
                      height: 36,
                      child: FutureBuilder<List<double>>(
                        future: MediaService().extractWaveformFromFile(msg.localPath!),
                        builder: (context, snapshot) {
                          if (snapshot.hasData && snapshot.data!.isNotEmpty) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              final index = _messages.indexWhere((m) => m.id == msg.id);
                              if (index != -1 && _messages[index].waveform == null) {
                                setState(() {
                                  _messages[index] = _messages[index].copyWith(waveform: snapshot.data);
                                });
                              }
                            });
                            return GestureDetector(
                              onTapDown: (details) {
                                final RenderBox box = context.findRenderObject() as RenderBox;
                                final localPosition = box.globalToLocal(details.globalPosition);
                                const waveformWidth = 120.0;
                                const leftOffset = 64.0;
                                final seekPercent = (localPosition.dx - leftOffset) / waveformWidth;
                                if (seekPercent >= 0 && seekPercent <= 1) {
                                  _seekVoiceMessage(msg, seekPercent);
                                }
                              },
                              child: _buildVoiceWaveform(snapshot.data!, msg, isMe),
                            );
                          }
                          return Container(
                            width: 80,
                            height: 2,
                            color: isMe 
                                ? Colors.white.withOpacity(0.3) 
                                : colorScheme.onSurfaceVariant.withOpacity(0.3),
                          );
                        },
                      ),
                    )
                  else if (isDownloading)
                    Container(
                      width: 120,
                      height: 36,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: isMe ? Colors.white70 : colorScheme.primary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Loading...',
                            style: TextStyle(
                              fontSize: 12,
                              color: isMe ? Colors.white70 : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    GestureDetector(
                      onTap: () => _downloadMedia(msg, openAfterDownload: false),
                      child: Container(
                        width: 120,
                        height: 36,
                        alignment: Alignment.center,
                        child: Container(
                          width: 80,
                          height: 2,
                          color: isMe 
                              ? Colors.white.withOpacity(0.3) 
                              : colorScheme.onSurfaceVariant.withOpacity(0.3),
                        ),
                      ),
                    ),
                    
                  const SizedBox(width: 12),
                  Text(
                    '${(msg.duration ?? 0) ~/ 60}:${((msg.duration ?? 0) % 60).toString().padLeft(2, '0')}',
                    style: TextStyle(
                      fontSize: 12, 
                      color: isMe ? Colors.white70 : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              
              // Время и статус
              Padding(
                padding: const EdgeInsets.only(top: 6, left: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeStr, 
                      style: TextStyle(
                        fontSize: 11, 
                        color: isMe ? Colors.white70 : colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4), 
                      _buildStatusIconForSticker(msg.status),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget _buildVoiceWaveform(List<double> waveform, MessageModel msg, bool isMe) {
  final colorScheme = Theme.of(context).colorScheme;
  final totalBars = 28;
  final step = waveform.length / totalBars;
  double progress = 0;
  if (msg.duration != null && msg.duration! > 0) {
    progress = (msg.playbackPosition ?? 0) / msg.duration!;
  }
  final playedBars = (progress * totalBars).toInt();
  
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: List.generate(totalBars, (index) {
      final startIdx = (index * step).toInt();
      final endIdx = ((index + 1) * step).toInt();
      double avgAmp = 0;
      if (endIdx > startIdx) {
        double sum = 0;
        for (int i = startIdx; i < endIdx && i < waveform.length; i++) sum += waveform[i];
        avgAmp = sum / (endIdx - startIdx);
      }
      final isPlayed = index < playedBars;
      final height = (4 + avgAmp * 28).clamp(4.0, 32.0);
      
      return Container(
        width: 3,
        height: height,
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: isMe
              ? (isPlayed ? Colors.white.withOpacity(0.5) : Colors.white)
              : (isPlayed ? colorScheme.primary.withOpacity(0.4) : colorScheme.primary),
          borderRadius: BorderRadius.circular(1.5),
        ),
      );
    }),
  );
}


/// Мини waveform для списка сообщений
Widget _buildMiniWaveform(List<double> waveform, MessageModel msg, bool isMe) {
  final colorScheme = Theme.of(context).colorScheme;
  final playedCount = ((msg.playbackPosition ?? 0) / (msg.duration ?? 1) * waveform.length).toInt();
  
  return Row(
    mainAxisAlignment: MainAxisAlignment.center,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: waveform.take(30).map((amp) {
      final index = waveform.indexOf(amp);
      final isPlayed = index < playedCount;
      
      return Container(
        width: 3,
        height: 4 + (amp * 30),
        margin: const EdgeInsets.symmetric(horizontal: 0.5),
        decoration: BoxDecoration(
          color: isMe 
              ? (isPlayed ? Colors.white70 : Colors.white)
              : (isPlayed ? colorScheme.onSurfaceVariant : colorScheme.onSurface),
          borderRadius: BorderRadius.circular(1.5),
        ),
      );
    }).toList(),
  );
}

Future<void> _toggleVideoNotePlayback(MessageModel msg) async {
  final existingController = _videoNoteControllers[msg.id];
  
  // Если уже играет - останавливаем
  if (existingController != null && existingController.value.isPlaying) {
    await existingController.pause();
    setState(() {
      final index = _messages.indexWhere((m) => m.id == msg.id);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(isPlaying: false);
      }
    });
    return;
  }
  
  // Останавливаем все другие видео-кружки
  for (var entry in _videoNoteControllers.entries) {
    if (entry.key != msg.id && entry.value.value.isPlaying) {
      await entry.value.pause();
      final i = _messages.indexWhere((m) => m.id == entry.key);
      if (i != -1) {
        setState(() {
          _messages[i] = _messages[i].copyWith(isPlaying: false);
        });
      }
    }
  }
  
  // Создаем или используем существующий контроллер
  VideoPlayerController? videoController = _videoNoteControllers[msg.id];
  
  if (videoController == null && msg.localPath != null) {
    print('🎥 Creating new video controller for: ${msg.id}');
    videoController = VideoPlayerController.file(File(msg.localPath!));
    
    try {
      await videoController.initialize();
      videoController.setLooping(true);
      
      videoController.addListener(() {
        if (!mounted) return;
        // Обновляем UI при изменении состояния
        if (videoController!.value.isInitialized) {
          setState(() {});
        }
      });
      
      _videoNoteControllers[msg.id] = videoController;
      print('✅ Video controller initialized');
    } catch (e) {
      print('❌ Failed to initialize video: $e');
      return;
    }
  }
  
  if (videoController != null && videoController.value.isInitialized) {
    // Проверяем закончилось ли видео
    final isAtEnd = videoController.value.position >= videoController.value.duration - const Duration(milliseconds: 100);
    
    if (isAtEnd) {
      // Видео закончилось - сбрасываем в начало и останавливаем
      await videoController.seekTo(Duration.zero);
      await videoController.pause();
      
      setState(() {
        final index = _messages.indexWhere((m) => m.id == msg.id);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(isPlaying: false);
        }
      });
      print('⏹️ Video finished, stopped at beginning');
      return;
    }
    
    // Видео не закончилось - продолжаем/начинаем воспроизведение
    await videoController.play();
    setState(() {
      final index = _messages.indexWhere((m) => m.id == msg.id);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(isPlaying: true);
      }
    });
    print('▶️ Video playing');
  }
}

Widget _buildVideoNoteMessage(MessageModel msg, bool isMe, String timeStr) {
  final colorScheme = Theme.of(context).colorScheme;
  final bool hasFile = msg.localPath != null && File(msg.localPath!).existsSync();
  final bool isDownloading = msg.status == 'sending' && !hasFile;
  final bool isPlaying = msg.isPlaying ?? false;
  
  final videoController = _videoNoteControllers[msg.id];
  final bool isControllerInitialized = videoController?.value.isInitialized ?? false;
  
  return Align(
    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
      child: GestureDetector(
        onTap: () {
          if (hasFile) {
            _toggleVideoNotePlayback(msg);
          } else if (!isDownloading) {
            _downloadMedia(msg, openAfterDownload: false);
          }
        },
        onLongPress: () => _showMessageActions(msg, isMe),
        child: ClipOval(
          child: Container(
            width: 200,
            height: 200,
            color: Colors.black,
            child: hasFile
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      // === ИСПРАВЛЕННОЕ ВИДЕО ===
                      if (isPlaying && isControllerInitialized)
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: videoController!.value.size.width,
                            height: videoController.value.size.height,
                            child: VideoPlayer(videoController),
                          ),
                        )
                      else if (msg.thumbnail != null && File(msg.thumbnail!).existsSync())
                        // Показываем thumbnail когда на паузе
                        Image.file(
                          File(msg.thumbnail!),
                          fit: BoxFit.cover,
                        )
                      else if (isControllerInitialized && !isPlaying)
                        // Если нет thumbnail но контроллер есть - берем кадр из видео
                        FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: videoController!.value.size.width,
                            height: videoController.value.size.height,
                            child: VideoPlayer(videoController),
                          ),
                        )
                      else
                        Container(color: Colors.grey.shade900),
                      
                      // === ИКОНКА PLAY КОГДИ НА ПАУЗЕ ===
                      if (!isPlaying)
                        Center(
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.black54, 
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow, 
                              color: Colors.white, 
                              size: 32,
                            ),
                          ),
                        ),
                      
                      // === ИНДИКАТОР ЗАГРУЗКИ ===
                      if (isPlaying && !isControllerInitialized)
                        Center(
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: Colors.black54, 
                              shape: BoxShape.circle,
                            ),
                            child: const CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          ),
                        ),
                      
                      // Длительность
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10, 
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54, 
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${(msg.duration ?? 0) ~/ 60}:${((msg.duration ?? 0) % 60).toString().padLeft(2, '0')}',
                            style: const TextStyle(
                              color: Colors.white, 
                              fontSize: 13, 
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : Container(
                    color: Colors.grey.shade900,
                    child: isDownloading
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                SizedBox(
                                  width: 48,
                                  height: 48,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: Colors.white54,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Downloading...',
                                  style: TextStyle(
                                    color: Colors.grey.shade400, 
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.download, 
                                color: Colors.white54, 
                                size: 48,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Tap to download',
                                style: TextStyle(
                                  color: Colors.grey.shade500, 
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                  ),
          ),
        ),
      ),
    ),
  );
}

void _openVideoNotePlayer(MessageModel msg) {
  if (msg.localPath == null || !File(msg.localPath!).existsSync()) {
    _downloadMedia(msg);
    return;
  }
  showDialog(
    context: context,
    barrierColor: Colors.black87,
    barrierDismissible: true,
    builder: (context) => _VideoNoteInlinePlayer(
      filePath: msg.localPath!,
      duration: msg.duration ?? 0,
      onClose: () => Navigator.pop(context),
    ),
  );
}




Future<void> _seekVoiceMessage(MessageModel msg, double percent) async {
  final player = _voicePlayers[msg.id];
  if (player == null) return;
  
  final duration = msg.duration ?? 0;
  final seekMs = (duration * percent * 1000).toInt();
  
  await player.seekTo(seekMs);
  
  setState(() {
    final index = _messages.indexWhere((m) => m.id == msg.id);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(playbackPosition: (duration * percent).toDouble());
    }
  });
}

Future<void> _playVoiceMessage(MessageModel msg) async {
  // Если уже играет - останавливаем
  if (msg.isPlaying ?? false) {
    final player = _voicePlayers[msg.id];
    if (player != null) {
      await player.pausePlayer();
      setState(() {
        final i = _messages.indexWhere((m) => m.id == msg.id);
        if (i != -1) {
          _messages[i] = _messages[i].copyWith(isPlaying: false);
        }
      });
    }
    return;
  }

  // Останавливаем все другие голосовые
  for (var entry in _voicePlayers.entries) {
    if (entry.key != msg.id) {
      await entry.value.stopPlayer();
      final i = _messages.indexWhere((m) => m.id == entry.key);
      if (i != -1) {
        setState(() {
          _messages[i] = _messages[i].copyWith(isPlaying: false, playbackPosition: 0);
        });
      }
    }
  }

  // Проверяем файл
  if (msg.localPath == null || !File(msg.localPath!).existsSync()) {
    await _downloadMedia(msg);
    return;
  }

  aw.PlayerController? player = _voicePlayers[msg.id];
  
  // Если плеер уже существует - используем его
  if (player != null) {
    try {
      await player.seekTo(0);
      await player.startPlayer();
      
      setState(() {
        final i = _messages.indexWhere((m) => m.id == msg.id);
        if (i != -1) {
          _messages[i] = _messages[i].copyWith(isPlaying: true);
        }
      });
      return;
    } catch (e) {
      _voicePlayers.remove(msg.id);
    }
  }

  // Создаём новый плеер
  player = aw.PlayerController();
  
  try {
    await player.preparePlayer(
      path: msg.localPath!, 
      shouldExtractWaveform: false,
    );
    
    // Слушаем позицию
    player.onCurrentDurationChanged.listen((ms) {
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == msg.id);
        if (i != -1) {
          _messages[i] = _messages[i].copyWith(playbackPosition: (ms / 1000).toDouble());
        }
      });
    });
    
    // Слушаем завершение
    player.onCompletion.listen((_) {
      if (!mounted) return;
      setState(() {
        final i = _messages.indexWhere((m) => m.id == msg.id);
        if (i != -1) {
          _messages[i] = _messages[i].copyWith(
            isPlaying: false, 
            playbackPosition: 0.0,
          );
        }
      });
    });
    
    _voicePlayers[msg.id] = player;
    
    await player.startPlayer();
    
    setState(() {
      final i = _messages.indexWhere((m) => m.id == msg.id);
      if (i != -1) {
        _messages[i] = _messages[i].copyWith(isPlaying: true);
      }
    });
  } catch (e) {
    print('❌ Error playing voice: $e');
    _voicePlayers.remove(msg.id);
    _showError('Failed to play voice message');
  }
}
  Widget _buildMessage(MessageModel msg) {
  final l10n = context.l10n;
  final isMe = msg.senderId == _currentUserId;
  final time = DateTime.fromMillisecondsSinceEpoch(msg.timestamp);
  final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  final bool isForwarded = msg.forwardedFrom != null;
  final String? forwardedFrom = msg.forwardedFrom;
  final String? originalSenderUsername = msg.originalSenderUsername ?? 
      (forwardedFrom != null && forwardedFrom != 'hidden' 
          ? forwardedFrom.substring(1) 
          : null);

  final colorScheme = Theme.of(context).colorScheme;
  
  final Color bubbleColor = isMe
      ? colorScheme.primary
      : colorScheme.surfaceContainerHighest;
  
  final Color textColor = isMe
      ? Colors.white
      : colorScheme.onSurface;
  
  final Color secondaryTextColor = isMe
      ? Colors.white70
      : colorScheme.onSurfaceVariant;

  if (msg.type == 'sticker') {
    return _buildStickerMessage(msg, isMe, timeStr);
  }

  if (msg.type == 'voice') {
      return _buildVoiceMessage(msg, isMe, timeStr);
    }
    
    if (msg.type == 'video_note') {
      return _buildVideoNoteMessage(msg, isMe, timeStr);
    }

  Widget? replyWidget;
  if (msg.replyToMessageId != null && msg.replyToContent != null) {
    final isReplyToMe = msg.replyToSenderId == _currentUserId;
    
    replyWidget = Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withOpacity(0.15)
            : colorScheme.surfaceContainerHighest.withOpacity(0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: isReplyToMe 
                ? (isMe ? Colors.white : colorScheme.primary)
                : Colors.grey,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isReplyToMe ? 'You' : (widget.chat.displayName ?? widget.chat.username),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: secondaryTextColor,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            msg.replyToContent!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: textColor.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  return Align(
    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onLongPress: () => _showMessageActions(msg, isMe),
            onTap: msg.isMedia ? () => _openMediaViewer(msg) : null,
            child: Container(
              padding: msg.isMedia ? const EdgeInsets.all(4) : const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(18).copyWith(
                  bottomRight: isMe ? const Radius.circular(4) : null,
                  bottomLeft: !isMe ? const Radius.circular(4) : null,
                ),
              ),
              child: msg.isMedia
                  ? _buildMediaContent(
                      msg, 
                      isMe, 
                      isForwarded, 
                      forwardedFrom, 
                      originalSenderUsername,
                      textColor,
                      secondaryTextColor,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (replyWidget != null) replyWidget,
                        if (isForwarded)
                          _buildForwardedBadge(
                            isMe: isMe, 
                            forwardedFrom: forwardedFrom,
                            originalSenderUsername: originalSenderUsername,
                            textColor: secondaryTextColor,
                          ),
                        
                        if (msg.isEdited)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              l10n.messageEdited,
                              style: TextStyle(
                                fontSize: 10,
                                color: secondaryTextColor,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        
                        RichText(
                          text: TextSpan(
                            children: _parseMessageText(msg.content, textColor),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              timeStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: secondaryTextColor,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 4),
                              _buildStatusIcon(msg.status, isMe: isMe),
                            ],
                          ],
                        ),
                      ],
                    ),
            ),
          ),
          _buildReactionsRow(msg),
          if (msg.status == 'failed' && isMe)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: GestureDetector(
                onTap: () => _retrySend(msg),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, size: 14, color: Colors.red.shade400),
                    const SizedBox(width: 4),
                    Text(
                      l10n.actionRetry,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

Widget _buildStickerMessage(MessageModel msg, bool isMe, String timeStr) {
  return Align(
    alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // === ОБЁРТКА GestureDetector для long press ===
          GestureDetector(
            onLongPress: () => _showMessageActions(msg, isMe), // <-- ВЫЗЫВАЕМ СУЩЕСТВУЮЩУЮ ПАНЕЛЬ
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: msg.localPath != null && File(msg.localPath!).existsSync()
                    ? Image.file(
                        File(msg.localPath!),
                        fit: BoxFit.contain,
                      )
                    : Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.image, color: Colors.grey),
                      ),
              ),
            ),
          ),
          // Время и статус
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: 4),
                  // Используем существующий _buildStatusIcon но с тёмным цветом
                  _buildStatusIconForSticker(msg.status),
                ],
              ],
            ),
          ),
          // Реакции (уже есть _buildReactionsRow)
          _buildReactionsRow(msg),
          // Retry (уже есть логика)
          if (msg.status == 'failed' && isMe)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: GestureDetector(
                onTap: () => _retrySend(msg),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.refresh, size: 14, color: Colors.red.shade400),
                    const SizedBox(width: 4),
                    Text(
                      'Retry',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.red.shade400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

// === НОВЫЙ МЕТОД: статус для стикера (тёмные цвета) ===
Widget _buildStatusIconForSticker(String? status) {
  // Копируем логику _buildStatusIcon но меняем цвета
  IconData icon;
  Color color;
  
  switch (status) {
    case 'sending':
      icon = Icons.access_time;
      color = Colors.grey.shade500;
      break;
    case 'sent':
      icon = Icons.check;
      color = Colors.grey.shade500;
      break;
    case 'delivered':
      icon = Icons.done_all;
      color = Colors.grey.shade500;
      break;
    case 'read':
      icon = Icons.done_all;
      color = Colors.blue.shade600; // Яркий синий для read
      break;
    default:
      icon = Icons.check;
      color = Colors.grey.shade500;
  }
  
  if (status == 'delivered' || status == 'read') {
    return Stack(
      children: [
        Icon(Icons.check, size: 14, color: color),
        Positioned(
          left: 3,
          child: Icon(Icons.check, size: 14, color: color),
        ),
      ],
    );
  }
  
  return Icon(icon, size: 14, color: color);
}

  Widget _buildForwardedBadge({
  required bool isMe,
  required String? forwardedFrom,
  required String? originalSenderUsername,
  required Color textColor,
}) {
  final l10n = context.l10n;
  final bool isHidden = forwardedFrom == 'hidden';
  
  return Container(
    margin: const EdgeInsets.only(bottom: 4),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: isMe 
          ? Colors.white.withOpacity(0.15) 
          : Colors.grey.shade300,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: isMe 
            ? Colors.white.withOpacity(0.3) 
            : Colors.grey.shade400,
        width: 0.5,
      ),
    ),
    child: isHidden
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.forward,
                size: 12,
                color: textColor,
              ),
              const SizedBox(width: 4),
              Text(
                l10n.messageForwardedHidden,
                style: TextStyle(
                  fontSize: 11,
                  color: textColor,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          )
        : GestureDetector(
            onTap: originalSenderUsername != null 
                ? () => _onForwardedUsernameTap(originalSenderUsername)
                : null,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.forward,
                  size: 12,
                  color: textColor,
                ),
                const SizedBox(width: 4),
                Text(
                  '${l10n.messageForwardedFrom} ',
                  style: TextStyle(
                    fontSize: 11,
                    color: textColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                Text(
                  forwardedFrom!,
                  style: TextStyle(
                    fontSize: 11,
                    color: isMe ? Colors.yellow.shade200 : Colors.blue.shade700,
                    fontWeight: FontWeight.bold,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ],
            ),
          ),
  );
}

  Future<void> _onForwardedUsernameTap(String username) async {
    print('👤 Tapped on forwarded username: $username');
    
    final cleanUsername = username.startsWith('@') ? username.substring(1) : username;
    
    final users = await ApiService().searchUsers(cleanUsername);
    final exactMatch = users.firstWhere(
      (u) => u['username'].toString().toLowerCase() == cleanUsername.toLowerCase(),
      orElse: () => {},
    );
    
    if (exactMatch.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User @$cleanUsername not found')),
      );
      return;
    }
    
    final userId = exactMatch['id'];
    
    final existingChat = await LocalDatabase().getChatByUserId(userId);
    
    if (existingChat != null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(chat: existingChat)),
      );
    } else {
      final tempChat = ChatModel(
        id: 'temp_${DateTime.now().millisecondsSinceEpoch}_$userId',
        userId: userId,
        username: exactMatch['username'],
        displayName: exactMatch['display_name'],
        avatarUrl: exactMatch['avatar_url'],
        encryptionKey: null,
      );
      
      await LocalDatabase().insertChat(tempChat);
      
      Navigator.push(
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
  }

  Widget _buildMediaContent(
  MessageModel msg, 
  bool isMe, 
  bool isForwarded, 
  String? forwardedFrom,
  String? originalSenderUsername,
  Color textColor,
  Color secondaryTextColor,
) {
  if (msg.type == 'album') {
    return _buildAlbumContent(
      msg, 
      isMe, 
      isForwarded, 
      forwardedFrom, 
      originalSenderUsername,
      textColor,
      secondaryTextColor,
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (isForwarded)
        _buildForwardedBadge(
          isMe: isMe, 
          forwardedFrom: forwardedFrom,
          originalSenderUsername: originalSenderUsername,
          textColor: secondaryTextColor,
        ),
      
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.65,
            maxHeight: 300,
          ),
          child: msg.isVideo
              ? _buildVideoThumbnail(msg, isMe)
              : _buildImagePreview(msg),
        ),
      ),
      
      if (msg.content.isNotEmpty) ...[
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: RichText(
            text: TextSpan(
              children: _parseMessageText(msg.content, textColor),
            ),
          ),
        ),
      ],
      
      Padding(
        padding: const EdgeInsets.only(top: 4, right: 10, bottom: 6, left: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${DateTime.fromMillisecondsSinceEpoch(msg.timestamp).hour.toString().padLeft(2, '0')}:'
              '${DateTime.fromMillisecondsSinceEpoch(msg.timestamp).minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 11,
                color: isMe ? Colors.white70 : Colors.grey.shade600,
              ),
            ),
            if (isMe) ...[
              const SizedBox(width: 4),
              _buildStatusIcon(msg.status, isMe: isMe),
            ],
          ],
        ),
      ),
    ],
  );
}

  Widget _buildImagePreview(MessageModel msg) {
    final file = msg.localPath != null ? File(msg.localPath!) : null;
    
    if (file != null && file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildMediaError(),
      );
    }
    
    return Container(
      width: 200,
      height: 200,
      color: Colors.grey.shade300,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image, size: 48, color: Colors.grey.shade600),
          const SizedBox(height: 8),
          Text(
            'Tap to download',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumContent(
  MessageModel msg,
  bool isMe,
  bool isForwarded,
  String? forwardedFrom,
  String? originalSenderUsername,
  Color textColor,
  Color secondaryTextColor,
) {
  List<dynamic> mediaItems = [];
  try {
    if (msg.encryptedContent != null) {
      mediaItems = jsonDecode(msg.encryptedContent!);
    }
  } catch (e) {
    print('Error parsing album: $e');
  }

  if (mediaItems.isEmpty && msg.localPath != null) {
    final paths = msg.localPath!.split(',');
    mediaItems = paths.map((p) => {
      'type': p.contains('.mp4') || p.contains('.mov') ? 'video' : 'image',
      'file_name': p,
    }).toList();
  }

  final int itemCount = mediaItems.length;
  final crossAxisCount = itemCount == 1 ? 1 : itemCount == 2 ? 2 : 3;
  final maxDisplay = itemCount > 9 ? 9 : itemCount;

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      if (isForwarded)
        _buildForwardedBadge(
          isMe: isMe,
          forwardedFrom: forwardedFrom,
          originalSenderUsername: originalSenderUsername,
          textColor: secondaryTextColor,
        ),

      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.65,
            maxHeight: 400,
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: 2,
              mainAxisSpacing: 2,
              childAspectRatio: 1,
            ),
            itemCount: maxDisplay,
            itemBuilder: (context, index) {
              final item = mediaItems[index];
              final isVideo = item['type'] == 'video';
              final bool showMoreOverlay = index == 8 && itemCount > 9;

              return GestureDetector(
                onTap: () => _openAlbumViewer(msg, index),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildAlbumItemPreview(item, msg),
                    
                    if (isVideo)
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          color: Colors.white70,
                          size: 32,
                        ),
                      ),

                    if (showMoreOverlay)
                      Container(
                        color: Colors.black54,
                        child: Center(
                          child: Text(
                            '+${itemCount - 9}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),

      if (msg.content.isNotEmpty) ...[
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: RichText(
            text: TextSpan(
              children: _parseMessageText(msg.content, textColor),
            ),
          ),
        ),
      ],

      Padding(
        padding: const EdgeInsets.only(top: 4, right: 10, bottom: 6, left: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${DateTime.fromMillisecondsSinceEpoch(msg.timestamp).hour.toString().padLeft(2, '0')}:'
              '${DateTime.fromMillisecondsSinceEpoch(msg.timestamp).minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 11,
                color: isMe ? Colors.white70 : Colors.grey.shade600,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '• $itemCount',
              style: TextStyle(
                fontSize: 11,
                color: isMe ? Colors.white70 : Colors.grey.shade600,
              ),
            ),
            if (isMe) ...[
              const SizedBox(width: 4),
              _buildStatusIcon(msg.status, isMe: isMe),
            ],
          ],
        ),
      ),
    ],
  );
}

  Widget _buildAlbumItemPreview(dynamic item, MessageModel msg) {
    if (msg.localPath == null || msg.localPath!.isEmpty) {
      return Container(
        color: Colors.grey.shade300,
        child: const Icon(Icons.image, color: Colors.white54),
      );
    }
    
    final paths = msg.localPath!.split(',');
    final index = item['index'] as int? ?? 0;
    
    if (index < paths.length && File(paths[index]).existsSync()) {
      return Image.file(
        File(paths[index]),
        fit: BoxFit.cover,
      );
    }

    return Container(
      color: Colors.grey.shade300,
      child: const Icon(Icons.image, color: Colors.white54),
    );
  }

  void _openAlbumViewer(MessageModel msg, int initialIndex) {
  // Проверяем ключ перед использованием
  final key = _encryptionKey;
  if (key == null || key.isEmpty) {
    _showError('Encryption key not available');
    return;
  }
  
  if (msg.localPath == null || msg.localPath!.isEmpty) {
    _downloadMedia(msg).then((_) {
      if (mounted) {
        final updatedMsg = _messages.firstWhere((m) => m.id == msg.id, orElse: () => msg);
        if (updatedMsg.localPath != null && updatedMsg.localPath!.isNotEmpty) {
          _openAlbumViewer(updatedMsg, initialIndex);
        }
      }
    });
    return;
  }
  
  final paths = msg.localPath!.split(',');
  
  final existingPaths = paths.where((p) => File(p).existsSync()).toList();
  if (existingPaths.isEmpty) {
    _downloadMedia(msg);
    return;
  }
  
  final List<MessageModel> albumMessages = [];
  
  for (int i = 0; i < existingPaths.length; i++) {
    final path = existingPaths[i];
    final ext = path.split('.').last.toLowerCase();
    final isVideo = ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext);
    
    albumMessages.add(MessageModel(
      id: '${msg.id}_$i',
      chatId: msg.chatId,
      senderId: msg.senderId,
      content: i == 0 ? msg.content : '',
      encryptedContent: null,
      type: isVideo ? 'video' : 'image',
      timestamp: msg.timestamp,
      status: msg.status,
      localPath: path,
      fileName: path.split('/').last,
      fileSize: 0,
      width: msg.width,
      height: msg.height,
      duration: isVideo ? msg.duration : null,
      isRead: msg.isRead,
      isDelivered: msg.isDelivered,
      reactions: {},
      forwardedFrom: msg.forwardedFrom,
      originalSenderUsername: msg.originalSenderUsername,
    ));
  }
  
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MediaViewerScreen(
        messages: albumMessages,
        initialIndex: initialIndex.clamp(0, albumMessages.length - 1),
        encryptionKey: key, // Используем локальную переменную
      ),
    ),
  );
}

  Widget _buildVideoThumbnail(MessageModel msg, bool isMe) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: 200,
          height: 200,
          color: Colors.black,
          child: msg.localPath != null
              ? const Icon(Icons.videocam, size: 48, color: Colors.white54)
              : Icon(Icons.videocam_off, size: 48, color: Colors.grey.shade600),
        ),
        Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: isMe ? Colors.white.withOpacity(0.9) : Colors.black.withOpacity(0.7),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.play_arrow,
            size: 36,
            color: isMe ? Colors.black : Colors.white,
          ),
        ),
        if (msg.duration != null)
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.7),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                _formatDuration(msg.duration!),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMediaError() {
    return Container(
      width: 200,
      height: 200,
      color: Colors.grey.shade300,
      child: Icon(Icons.broken_image, size: 48, color: Colors.grey.shade600),
    );
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  void _openMediaViewer(MessageModel msg) {
  // Проверяем ключ перед использованием
  final key = _encryptionKey;
  if (key == null || key.isEmpty) {
    _showError('Encryption key not available');
    return;
  }
  
  if (msg.type == 'album') {
    _openAlbumViewer(msg, 0);
    return;
  }
  
  if (msg.localPath == null || !File(msg.localPath!).existsSync()) {
    _downloadMedia(msg);
    return;
  }

  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => MediaViewerScreen(
        messages: [msg],
        initialIndex: 0,
        encryptionKey: key, // Используем локальную переменную
      ),
    ),
  );
}


  Future<void> _downloadMedia(MessageModel msg, {bool openAfterDownload = true}) async {
  try {
    final key = _encryptionKey;
    if (key == null || key.isEmpty) {
      _showError('Encryption key not available');
      return;
    }
    
    // Показываем индикатор загрузки
    setState(() {
      final index = _messages.indexWhere((m) => m.id == msg.id);
      if (index != -1) {
        _messages[index] = _messages[index].copyWith(status: 'sending');
      }
    });
    
    print('📥 Downloading ${msg.type} for message: ${msg.id}');
    
    final encryptedBase64 = await ApiService().downloadMedia(msg.id);
    print('📊 Encrypted content length: ${encryptedBase64.length}');
    
    final fileName = msg.fileName ?? '${msg.type}_${msg.id}';
    final localPath = await MediaService().decryptAndSave(
      encryptedBase64, 
      key, 
      fileName,
    );
    
    print('✅ Saved to: $localPath');
    
    // Обновляем сообщение в списке и БД
    final index = _messages.indexWhere((m) => m.id == msg.id);
    if (index != -1) {
      setState(() {
        _messages[index] = _messages[index].copyWith(
          localPath: localPath,
          status: _messages[index].status == 'sending' ? 'sent' : _messages[index].status,
        );
      });
      
      await LocalDatabase().updateMessage(
        msg.id,
        {'local_path': localPath},
      );
      
      // === КЛЮЧЕВОЕ: Только если openAfterDownload = true открываем viewer ===
      if (openAfterDownload) {
        if (msg.type == 'voice') {
          _playVoiceMessage(_messages[index]);
        } else if (msg.type == 'video_note') {
          // Для video_note НЕ открываем MediaViewerScreen, 
          // просто обновляем UI - кружок сам станет кликабельным для воспроизведения
          // Можно опционально сразу открыть inline player:
          // _openVideoNotePlayer(_messages[index]);
        } else {
          // Для обычного media открываем viewer
          _openMediaViewer(_messages[index]);
        }
      }
    }
    
  } catch (e, stackTrace) {
    print('❌ Download error: $e');
    print(stackTrace);
    
    final index = _messages.indexWhere((m) => m.id == msg.id);
    if (index != -1) {
      setState(() {
        _messages[index] = _messages[index].copyWith(status: 'failed');
      });
    }
    
    _showError('Failed to download: $e');
  }
}

  Future<void> _updateMessageAfterDownload(MessageModel msg, String localPath) async {
    print('✅ Media saved to: $localPath');
    
    final index = _messages.indexWhere((m) => m.id == msg.id);
    if (index != -1) {
      setState(() {
        _messages[index] = _messages[index].copyWith(localPath: localPath);
      });
    }
    
    await LocalDatabase().updateMessage(
      msg.id,
      {'local_path': localPath},
    );
    
    _openMediaViewer(_messages[_messages.indexWhere((m) => m.id == msg.id)]);
  }

  Widget _buildStatusIcon(String? status, {required bool isMe}) {
  IconData icon;
  Color color;
  
  switch (status) {
    case 'sending':
      icon = Icons.access_time;
      color = isMe ? Colors.white70 : Colors.grey;
      break;
    case 'sent':
      icon = Icons.check;
      color = isMe ? Colors.white70 : Colors.grey;
      break;
    case 'delivered':
      icon = Icons.done_all;
      color = isMe ? Colors.white70 : Colors.grey;
      break;
    case 'read':
      icon = Icons.done_all;
      color = isMe ? Colors.blue.shade200 : Colors.blue;
      break;
    default:
      icon = Icons.check;
      color = isMe ? Colors.white70 : Colors.grey;
  }
  
  if (status == 'delivered' || status == 'read') {
    return Stack(
      children: [
        Icon(Icons.check, size: 12, color: color),
        Positioned(
          left: 4,
          child: Icon(Icons.check, size: 12, color: color),
        ),
      ],
    );
  }
  
  return Icon(icon, size: 14, color: color);
}

    // === ИСПРАВЛЕННЫЙ МЕТОД: панель прикрепления с рабочей кнопкой "Без сжатия" ===
  Widget _buildAttachmentPanel() {
    final l10n = context.l10n;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                _buildAttachmentButton(
                  icon: Icons.photo_library,
                    label: l10n.mediaGallery, // Используем локализацию
                  color: Colors.purple,
                  onTap: _pickMultipleImages,
                ),
                _buildAttachmentButton(
                  icon: Icons.camera_alt,
                  label: l10n.mediaCamera,
                  color: Colors.blue,
                  onTap: _takePhoto,
                ),
                _buildAttachmentButton(
                  icon: Icons.videocam,
                  label: l10n.mediaVideo,
                  color: Colors.red,
                  onTap: _pickVideo,
                ),
                _buildAttachmentButton(
                  icon: Icons.videocam_off,
                  label: l10n.mediaRecord,
                  color: Colors.orange,
                  onTap: _recordVideo,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // === ИСПРАВЛЕНИЕ: StatefulBuilder для обновления состояния внутри BottomSheet ===
                StatefulBuilder(
                  builder: (context, setSheetState) {
                    return Checkbox(
                      value: _disableCompression,
                      onChanged: (v) {
                        // Обновляем состояние в родительском виджете
                        setState(() {
                          _disableCompression = v ?? false;
                        });
                        // Обновляем состояние внутри BottomSheet
                        setSheetState(() {
                          _disableCompression = v ?? false;
                        });
                      },
                    );
                  },
                ),
                Text(l10n.mediaNoCompression),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachedMediaPreview() {
    if (_attachedMediaList.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_attachedMediaList.length} ${_attachedMediaList.length == 1 ? 'file' : 'files'} selected',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 80,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _attachedMediaList.length,
              itemBuilder: (context, index) {
                final media = _attachedMediaList[index];
                return Stack(
                  children: [
                    Container(
                      width: 80,
                      height: 80,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.grey.shade300,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: media.type == MediaType.video
                            ? (media.thumbnail != null
                                ? Image.file(File(media.thumbnail!), fit: BoxFit.cover)
                                : const Icon(Icons.videocam, color: Colors.white))
                            : Image.file(media.file, fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 4,
                      right: 12,
                      child: GestureDetector(
                        onTap: () => _removeAttachedMedia(index),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                    if (media.type == MediaType.video)
                      const Positioned(
                        bottom: 4,
                        left: 4,
                        child: Icon(Icons.videocam, size: 16, color: Colors.white70),
                      ),
                  ],
                );
              },
            ),
          ),
          if (_isCompressing)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _compressingProgress ?? 'Processing...',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
        ],
      ),
    );
  }

 // ЗАМЕНИТЕ полностью этот метод в ChatScreen
Widget _buildInputBar({required bool hasWallpaper}) {
  final l10n = context.l10n;
  final isEditing = _editingMessage != null;
  final isReplying = _replyingToMessage != null;
  final colorScheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  
  final backgroundColor = hasWallpaper 
      ? Colors.transparent
      : (isDark ? Colors.black : colorScheme.surface);
  
  final surfaceColor = hasWallpaper
      ? Colors.white.withOpacity(0.15)
      : (isDark ? Colors.grey.shade900 : colorScheme.surfaceContainerHighest);
  
  final textColor = hasWallpaper 
      ? Colors.white 
      : (isDark ? Colors.white : colorScheme.onSurface);
  
  final hintColor = hasWallpaper
      ? Colors.white70
      : (isDark ? Colors.grey.shade500 : colorScheme.onSurfaceVariant);

  final bool hasText = _messageCtrl.text.trim().isNotEmpty;
  final bool canSend = !_isCompressing && (hasText || _attachedMediaList.isNotEmpty);

  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (isEditing || isReplying)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: hasWallpaper 
                ? Colors.black.withOpacity(0.3)
                : (isDark ? Colors.grey.shade900 : colorScheme.surfaceContainerHighest),
            border: Border(
              top: BorderSide(
                color: hasWallpaper 
                    ? Colors.white24 
                    : (isDark ? Colors.grey.shade800 : colorScheme.outlineVariant.withOpacity(0.5)),
              ),
            ),
          ),
          child: Row(
            children: [
              Icon(
                isEditing ? Icons.edit : Icons.reply,
                color: hasWallpaper ? Colors.white : colorScheme.primary,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isEditing ? l10n.actionEdit : l10n.actionReply,
                      style: TextStyle(
                        fontSize: 12,
                        color: hasWallpaper ? Colors.white : colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      isEditing 
                          ? _editingMessage!.content 
                          : _replyingToMessage!.content,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: hasWallpaper ? Colors.white70 : (isDark ? Colors.grey.shade400 : colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  Icons.close, 
                  size: 20,
                  color: hasWallpaper ? Colors.white70 : (isDark ? Colors.grey.shade400 : colorScheme.onSurfaceVariant),
                ),
                onPressed: isEditing ? _cancelEditing : _cancelReply,
              ),
            ],
          ),
        ),
      
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border(
            top: BorderSide(
              color: hasWallpaper 
                  ? Colors.white24 
                  : (isDark ? Colors.grey.shade900 : colorScheme.outlineVariant.withOpacity(0.5)), 
              width: 1,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          bottom: true,
          minimum: const EdgeInsets.only(bottom: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              IconButton(
                icon: Icon(
                  _attachedMediaList.isNotEmpty ? Icons.close : Icons.add_circle_outline,
                  color: hasWallpaper ? Colors.white : colorScheme.primary,
                ),
                onPressed: () {
                  if (_attachedMediaList.isNotEmpty) {
                    _clearAttachedMedia();
                  } else {
                    _showAttachmentSheet();
                  }
                },
              ),
              
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(
                    maxHeight: 120,
                    minHeight: 40,
                  ),
                  decoration: BoxDecoration(
                    color: surfaceColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          _showEmojiPicker ? Icons.keyboard : Icons.emoji_emotions,
                          color: _showEmojiPicker 
                              ? (hasWallpaper ? Colors.white : colorScheme.primary)
                              : (hasWallpaper ? Colors.white70 : (isDark ? Colors.grey.shade400 : colorScheme.onSurfaceVariant)),
                        ),
                        onPressed: () {
                          setState(() {
                            _showEmojiPicker = !_showEmojiPicker;
                            if (_showEmojiPicker) {
                              _focusNode.unfocus();
                            } else {
                              _focusNode.requestFocus();
                            }
                          });
                        },
                      ),
                      
                      Expanded(
                        child: TextField(
                          controller: _messageCtrl,
                          focusNode: _focusNode,
                          onChanged: (text) {
                            _onTextChanged(text);
                            setState(() {});
                          },
                          maxLines: null,
                          minLines: 1,
                          textCapitalization: TextCapitalization.sentences,
                          style: TextStyle(color: textColor),
                          decoration: InputDecoration(
                            hintText: _attachedMediaList.isNotEmpty 
                                ? l10n.messagePlaceholder
                                : isEditing 
                                    ? l10n.actionEdit
                                    : l10n.messagePlaceholder,
                            hintStyle: TextStyle(
                              color: hintColor,
                              fontSize: 16,
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 8),
              
              if (canSend)
                GestureDetector(
                  onTap: _sendMessage,
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: hasWallpaper ? Colors.white : colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isEditing ? Icons.check : Icons.send,
                      color: hasWallpaper ? Colors.black : Colors.white,
                      size: 20,
                    ),
                  ),
                )
              else
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // КНОПКА ВИДЕО-КРУЖКА - просто onTap
                    GestureDetector(
                      onTap: _startVideoNoteRecording,
                      child: Container(
                        width: 40,
                        height: 40,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: hasWallpaper 
                              ? Colors.white.withOpacity(0.2)
                              : (isDark ? Colors.grey.shade800 : colorScheme.surfaceContainerHighest),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.videocam,
                          color: hasWallpaper ? Colors.white70 : (isDark ? Colors.grey.shade500 : colorScheme.onSurfaceVariant),
                          size: 20,
                        ),
                      ),
                    ),
                    
                    // КНОПКА ГОЛОСОВОГО - просто onTap
                    GestureDetector(
                      onTap: _startVoiceRecording,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: hasWallpaper 
                              ? Colors.white.withOpacity(0.2)
                              : (isDark ? Colors.grey.shade800 : colorScheme.surfaceContainerHighest),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.mic,
                          color: hasWallpaper ? Colors.white : (isDark ? Colors.grey.shade500 : colorScheme.onSurfaceVariant),
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    ],
  );
}
  // === ИНТЕРФЕЙС ЗАПИСИ ГОЛОСА ===

  

  
  Future<void> _startVideoNoteRecording() async {
    try {
      final result = await MediaService().startVideoNoteRecording();
      
      // Показываем fullscreen запись
      if (mounted) {
        _showVideoNoteRecordingScreen(result);
      }
    } catch (e) {
      _showError('Failed to start video note: $e');
    }
  }

  void _showVideoNoteRecordingScreen(VideoNoteRecordingResult recording) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (context) => _VideoNoteRecordingScreen(
          recording: recording,
          onStop: (result) {
            Navigator.pop(context);
            _showVideoNotePreview(result);
          },
          onCancel: () {
            Navigator.pop(context);
            MediaService().cancelVideoNoteRecording(recording.controller);
          },
        ),
      ),
    );
  }


  // === ИНТЕРФЕЙС ЗАПИСИ ВИДЕО-КРУЖКА ===

 

  @override
Widget build(BuildContext context) {
  final l10n = context.l10n;
  final colorScheme = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final backgroundColor = isDark ? Colors.black : colorScheme.surface;
  final displayName = widget.chat.displayName ?? widget.chat.username;
  
  return Scaffold(
    backgroundColor: backgroundColor,
    body: FutureBuilder<Widget?>(
      future: _getWallpaperBackground(),
      builder: (context, snapshot) {
        final hasWallpaper = snapshot.hasData && snapshot.data != null;
        final statusBorderColor = backgroundColor;
        
        // === ОСНОВНОЙ КОНТЕНТ ===
        final mainContent = Column(
          children: [
            // === ВЕРХНЯЯ ПАНЕЛЬ (прозрачная когда есть обои) ===
            AppBar(
              elevation: 0,
              backgroundColor: Colors.transparent,
              foregroundColor: hasWallpaper ? Colors.white : null,
              leading: IconButton(
                icon: Icon(
                  Icons.arrow_back, 
                  color: hasWallpaper ? Colors.white : (isDark ? Colors.white : colorScheme.onSurface),
                ),
                onPressed: () => Navigator.pop(context),
              ),
              title: Row(
                children: [
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: colorScheme.primaryContainer,
                        backgroundImage: widget.chat.avatarUrl?.isNotEmpty == true
                            ? NetworkImage('http://45.132.255.167:8080${widget.chat.avatarUrl}')
                            : null,
                        child: widget.chat.avatarUrl?.isNotEmpty != true
                            ? Text(
                                displayName[0].toUpperCase(),
                                style: TextStyle(
                                  fontSize: 16,
                                  color: colorScheme.onPrimaryContainer,
                                ),
                              )
                            : null,
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: _otherUserStatus == 'online' 
                                ? Colors.green 
                                : Colors.grey,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: statusBorderColor,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: TextStyle(
                            fontSize: 16, 
                            fontWeight: FontWeight.w600,
                            color: hasWallpaper ? Colors.white : (isDark ? Colors.white : colorScheme.onSurface),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _isOtherTyping 
                              ? l10n.statusTyping
                              : _formatLastSeen(_otherUserLastSeen),
                          style: TextStyle(
                            fontSize: 12,
                            color: _isOtherTyping 
                                ? Colors.green 
                                : (hasWallpaper ? Colors.white70 : (isDark ? Colors.white70 : colorScheme.onSurfaceVariant)),
                            fontStyle: _isOtherTyping ? FontStyle.italic : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            // === СПИСОК СООБЩЕНИЙ ===
            Expanded(
              child: _isLoading && _messages.isEmpty
                  ? Center(
                      child: CircularProgressIndicator(
                        color: hasWallpaper ? Colors.white : (isDark ? Colors.white : colorScheme.primary),
                      ),
                    )
                  : _messages.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          controller: _scrollController,
                          reverse: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, index) => _buildMessage(_messages[index]),
                        ),
            ),
            
            // === ИНДИКАТОР ПЕЧАТИ ===
            if (_isOtherTyping)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                alignment: Alignment.centerLeft,
                child: Text(
                  '$displayName ${l10n.statusTyping}',
                  style: TextStyle(
                    fontSize: 12,
                    color: hasWallpaper ? Colors.white70 : (isDark ? Colors.white70 : colorScheme.onSurfaceVariant),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            
            // === ПРЕВЬЮ ПРИКРЕПЛЕННЫХ ФАЙЛОВ ===
            _buildAttachedMediaPreview(),
            
            // === НИЖНЯЯ ПАНЕЛЬ (ИСПРАВЛЕНО: прозрачный фон когда есть обои) ===
            _buildInputBar(hasWallpaper: hasWallpaper),
            
            // === EMOJI ПИКЕР ===
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              height: _showEmojiPicker ? 250 : 0,
              child: _showEmojiPicker ? _buildEmojiPicker() : null,
            ),
          ],
        );

        if (hasWallpaper) {
          return Stack(
            fit: StackFit.expand,
            children: [
              snapshot.data!,
              mainContent,
            ],
          );
        }
        
        return mainContent;
      },
    ),
  );
}
// Исправленный метод получения обоев
// ЗАМЕНИТЕ полностью этот метод в ChatScreen
Future<Widget?> _getWallpaperBackground() async {
  try {
    final wallpaperService = WallpaperService();
    final type = await wallpaperService.getWallpaperType();
    
    Widget background;
    
    if (type == WallpaperType.gradient) {
      final colors = await wallpaperService.getGradientColors();
      final begin = await wallpaperService.getGradientBegin();
      final end = await wallpaperService.getGradientEnd();
      
      if (colors != null && colors.length >= 2) {
        background = Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: colors,
              begin: begin,
              end: end,
            ),
          ),
        );
      } else {
        return null;
      }
    } else {
      final path = await wallpaperService.getWallpaperPath();
      if (path == null || path.isEmpty) return null;
      
      final file = File(path);
      if (!await file.exists()) return null;
      
      background = Image.file(
        file,
        fit: BoxFit.cover,
        width: double.infinity,
        height: double.infinity,
      );
    }
    
    final opacity = await wallpaperService.getWallpaperOpacity();
    final blur = await wallpaperService.getWallpaperBlur();
    
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          background,
          Container(
            color: Colors.black.withOpacity(1.0 - opacity),
          ),
          if (blur > 0)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              child: Container(color: Colors.transparent),
            ),
        ],
      ),
    );
  } catch (e) {
    print('❌ _getWallpaperBackground error: $e');
    return null;
  }
}




  void _showAttachmentSheet() {
    showModalBottomSheet(
      context: context,
      builder: (_) => _buildAttachmentPanel(),
    );
  }

  Widget _buildEmptyState() {
  final l10n = context.l10n;
  final colorScheme = Theme.of(context).colorScheme;
  
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.chat_bubble_outline, 
          size: 64, 
          color: colorScheme.onSurfaceVariant.withOpacity(0.3),
        ),
        const SizedBox(height: 16),
        Text(
          widget.isNewChat ? l10n.chatEmptyTitle : l10n.messageNoMessages,
          style: TextStyle(
            fontSize: 16, 
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        if (widget.isNewChat) ...[
          const SizedBox(height: 8),
          Text(
            l10n.chatEmptySubtitle,
            style: TextStyle(
              fontSize: 14,
              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ],
      ],
    ),
  );
 
}
}

class _VideoNoteInlinePlayer extends StatefulWidget {
  final String filePath;
  final int duration;
  final VoidCallback onClose;

  const _VideoNoteInlinePlayer({required this.filePath, required this.duration, required this.onClose});

  @override
  State<_VideoNoteInlinePlayer> createState() => _VideoNoteInlinePlayerState();
}

class _VideoNoteInlinePlayerState extends State<_VideoNoteInlinePlayer> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    _controller = VideoPlayerController.file(File(widget.filePath));
    await _controller.initialize();
    await _controller.setLooping(true);
    if (mounted) {
      setState(() => _isInitialized = true);
      _controller.play();
      setState(() => _isPlaying = true);
    }
    _controller.addListener(() {
      if (mounted) setState(() => _isPlaying = _controller.value.isPlaying);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlay() {
    if (_isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final circleSize = MediaQuery.of(context).size.width * 0.85;
    
    return GestureDetector(
      onTap: widget.onClose,
      child: Scaffold(
        backgroundColor: Colors.black87,
        body: Center(
          child: GestureDetector(
            onTap: _togglePlay,
            child: ClipOval(
              child: Container(
                width: circleSize,
                height: circleSize,
                color: Colors.black,
                child: _isInitialized
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width: _controller.value.size.width,
                              height: _controller.value.size.height,
                              child: VideoPlayer(_controller),
                            ),
                          ),
                          if (!_isPlaying)
                            Container(color: Colors.black54, child: const Icon(Icons.play_arrow, color: Colors.white, size: 64)),
                          Positioned(
                            top: 16,
                            right: 16,
                            child: GestureDetector(
                              onTap: widget.onClose,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                                child: const Icon(Icons.close, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Center(child: CircularProgressIndicator(color: Colors.white)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _VoiceRecordingPanel extends StatefulWidget {
  final VoiceRecordingResult recording;
  final Function(VoiceRecordingResult) onStop;
  final VoidCallback onCancel;

  const _VoiceRecordingPanel({
    required this.recording,
    required this.onStop,
    required this.onCancel,
  });

  @override
  State<_VoiceRecordingPanel> createState() => _VoiceRecordingPanelState();
}

class _VoiceRecordingPanelState extends State<_VoiceRecordingPanel> {
  List<double> _waveform = [];
  int _duration = 0;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _waveform = widget.recording.waveform ?? [];
    _duration = widget.recording.duration ?? 0;
    
    // === РЕАЛЬНЫЕ ДАННЫЕ С МИКРОФОНА ===
    MediaService().onWaveformUpdate = (waveform) {
      if (mounted) {
        setState(() {
          _waveform = waveform;
        });
        
        // Автоскролл к концу
        if (_scrollController.hasClients && waveform.length > 50) {
          Future.delayed(const Duration(milliseconds: 50), () {
            _scrollController.animateTo(
              _scrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 100),
              curve: Curves.easeOut,
            );
          });
        }
      }
    };
    
    MediaService().onDurationUpdate = (seconds) {
      if (mounted) {
        setState(() => _duration = seconds);
      }
    };
    
    MediaService().onMaxDurationReached = () {
      _stopRecording();
    };
  }

  Future<void> _stopRecording() async {
    final result = await MediaService().stopVoiceRecording();
    widget.onStop(result);
  }

  String _formatTime(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _scrollController.dispose();
    // Очищаем callbacks
    MediaService().onWaveformUpdate = null;
    MediaService().onDurationUpdate = null;
    MediaService().onMaxDurationReached = null;
    super.dispose();
  }

    @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.4,
      ),
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Индикатор сверху
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),
              
              // Таймер
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _formatTime(_duration),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 48,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              
              // === ИСПРАВЛЕННЫЙ WAVEFORM С РЕАЛЬНЫМИ ДАННЫМИ ===
              Container(
                height: 60,
                margin: const EdgeInsets.symmetric(horizontal: 8),
                child: _waveform.isEmpty
                    ? Center(
                        child: Container(
                          width: 100,
                          height: 2,
                          color: Colors.white24,
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        itemCount: _waveform.length,
                        itemBuilder: (context, index) {
                          final amp = _waveform[index];
                          final isRecent = index > _waveform.length - 20;
                          
                          return Container(
                            width: 4,
                            height: 8 + (amp * 44).clamp(4.0, 52.0),
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: isRecent ? Colors.blue : Colors.white,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          );
                        },
                      ),
              ),
              const SizedBox(height: 32),
              
              // Кнопки управления
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Отмена
                  GestureDetector(
                    onTap: widget.onCancel,
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close, color: Colors.white, size: 28),
                    ),
                  ),
                  const SizedBox(width: 48),
                  // Стоп
                  GestureDetector(
                    onTap: _stopRecording,
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: Colors.blue,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                      ),
                      child: const Icon(Icons.stop, color: Colors.white, size: 32),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}


class _VideoNotePlayerDialog extends StatefulWidget {
  final String filePath;
  final int duration;

  const _VideoNotePlayerDialog({
    required this.filePath,
    required this.duration,
  });

  @override
  State<_VideoNotePlayerDialog> createState() => _VideoNotePlayerDialogState();
}

class _VideoNotePlayerDialogState extends State<_VideoNotePlayerDialog> {
  late VideoPlayerController _controller;
  bool _isPlaying = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..initialize().then((_) {
        setState(() {});
        _controller.play();
        _controller.setLooping(true);
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.pop(context),
      child: Scaffold(
        backgroundColor: Colors.black87,
        body: Center(
          child: GestureDetector(
            onTap: () {
              setState(() {
                _isPlaying = !_isPlaying;
                _isPlaying ? _controller.play() : _controller.pause();
              });
            },
            child: ClipOval(
              child: Container(
                width: 300,
                height: 300,
                color: Colors.black,
                child: _controller.value.isInitialized
                    ? VideoPlayer(_controller)
                    : const CircularProgressIndicator(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// === ЭКРАН ЗАПИСИ ВИДЕО-КРУЖКА ===

class _VideoNoteRecordingScreen extends StatefulWidget {
  final VideoNoteRecordingResult recording;
  final Function(VideoNoteResult) onStop;
  final VoidCallback onCancel;

  const _VideoNoteRecordingScreen({
    required this.recording,
    required this.onStop,
    required this.onCancel,
  });

  @override
  State<_VideoNoteRecordingScreen> createState() => _VideoNoteRecordingScreenState();
}

class _VideoNoteRecordingScreenState extends State<_VideoNoteRecordingScreen> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _startRecording();
  }

  Future<void> _startRecording() async {
    await widget.recording.controller.startVideoRecording();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() => _seconds++);
        if (_seconds >= 60) _stopRecording();
      }
    });
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    final result = await MediaService().stopVideoNoteRecording(widget.recording.controller);
    widget.onStop(result);
  }

  String _formatTime(int seconds) {
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

    @override
Widget build(BuildContext context) {
  final screenSize = MediaQuery.of(context).size;
  final circleSize = screenSize.width * 0.75;
  
  final cameraValue = widget.recording.controller.value;
  final previewSize = cameraValue.previewSize;
  
  // Соотношение сторон камеры
  final double aspectRatio = previewSize != null 
      ? previewSize.width / previewSize.height 
      : 1.0;
  
  return Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      fit: StackFit.expand,
      children: [
        // Blur фон
        Positioned.fill(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
            child: Container(color: Colors.black.withOpacity(0.8)),
          ),
        ),
        
        SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 40),
              
              // Таймер
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _formatTime(_seconds),
                      style: const TextStyle(
                        color: Colors.white, 
                        fontSize: 20, 
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              
              const Spacer(),
              
              // === ИСПРАВЛЕННЫЙ КРУЖОК КАМЕРЫ БЕЗ РАСТЯЖЕНИЯ ===
              ClipOval(
                child: Container(
                  width: circleSize,
                  height: circleSize,
                  color: Colors.black,
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: OverflowBox(
                      alignment: Alignment.center,
                      child: SizedBox(
                        // Исправлено: правильные размеры чтобы не растягивало
                        width: aspectRatio >= 1.0 ? circleSize * aspectRatio : circleSize,
                        height: aspectRatio >= 1.0 ? circleSize : circleSize / aspectRatio,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: previewSize?.width ?? circleSize,
                            height: previewSize?.height ?? circleSize,
                            child: CameraPreview(widget.recording.controller),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              
              const Spacer(),
              
              // Кнопки
              Padding(
                padding: const EdgeInsets.only(bottom: 48),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Отмена
                    GestureDetector(
                      onTap: widget.onCancel,
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, color: Colors.white, size: 28),
                      ),
                    ),
                    const SizedBox(width: 60),
                    // Стоп - с фиксом надежности
                    GestureDetector(
                      onTap: () async {
                        // Предотвращаем двойное нажатие
                        if (_timer == null) return;
                        
                        _timer?.cancel();
                        _timer = null;
                        
                        try {
                          final result = await MediaService().stopVideoNoteRecording(widget.recording.controller);
                          widget.onStop(result);
                        } catch (e) {
                          print('❌ Error stopping recording: $e');
                          // Если ошибка - всё равно закрываем экран
                          widget.onCancel();
                        }
                      },
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.blue,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: const Icon(Icons.stop, color: Colors.white, size: 40),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
}




