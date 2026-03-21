import 'dart:convert';

class MessageModel {
  final String id;
  final String chatId;
  final String senderId;
  final String content;
  final String? encryptedContent;
  final String type;
  final String status;
  final int timestamp;
  final bool isRead;
  final bool isDelivered;
  final int? editedAt;
  final Map<String, String> reactions;
  final String? fileName;
  final int? fileSize;
  final String? localPath;
  final String? mediaUrl;
  final String? thumbnail;
  final int? width;
  final int? height;
  final int? duration;
  final String? forwardedFrom;
  final String? originalChatId;
  final String? originalMessageId;
  final String? originalSenderUsername;
  final String? replyToMessageId;
  final String? replyToContent;
  final String? replyToSenderId;
  final List<double>? waveform;
  
  // Runtime-only поля (не сохраняются в БД)
  final double? playbackPosition;
  final bool? isPlaying;

  MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.content,
    this.encryptedContent,
    required this.type,
    required this.timestamp,
    this.status = 'sent',
    this.isRead = false,
    this.isDelivered = false,
    this.editedAt,
    this.reactions = const {},
    this.fileName,
    this.fileSize,
    this.localPath,
    this.mediaUrl,
    this.thumbnail,
    this.width,
    this.height,
    this.duration,
    this.forwardedFrom,
    this.originalChatId,
    this.originalMessageId,
    this.originalSenderUsername,
    this.replyToMessageId,
    this.replyToContent,
    this.replyToSenderId,
    this.waveform,
    // Runtime-only
    this.playbackPosition,
    this.isPlaying,
  });

  bool get isMedia => type == 'image' || type == 'video' || type == 'album' || type == 'sticker' || type == 'voice' || type == 'video_note';
  bool get isImage => type == 'image';
  bool get isVideo => type == 'video' || type == 'video_note';
  bool get isEdited => editedAt != null;

  factory MessageModel.fromMap(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      senderId: map['sender_id'] as String,
      content: map['content'] as String,
      encryptedContent: map['encrypted_content'] as String?,
      type: map['type'] as String? ?? 'text',
      timestamp: map['timestamp'] as int,
      status: map['status'] as String? ?? 'sent',
      isRead: (map['is_read'] as int?) == 1,
      isDelivered: (map['is_delivered'] as int?) == 1,
      editedAt: map['edited_at'] as int?,
      reactions: map['reactions'] != null 
          ? Map<String, String>.from(jsonDecode(map['reactions'] as String))
          : {},
      fileName: map['file_name'] as String?,
      fileSize: map['file_size'] as int?,
      localPath: map['local_path'] as String?,
      mediaUrl: map['media_url'] as String?,
      thumbnail: map['thumbnail'] as String?,
      width: map['width'] as int?,
      height: map['height'] as int?,
      duration: map['duration'] as int?,
      forwardedFrom: map['forwarded_from'] as String?,
      originalChatId: map['original_chat_id'] as String?,
      originalMessageId: map['original_message_id'] as String?,
      originalSenderUsername: map['original_sender_username'] as String?,
      replyToMessageId: map['reply_to_message_id'] as String?,
      replyToContent: map['reply_to_content'] as String?,
      replyToSenderId: map['reply_to_sender_id'] as String?,
      waveform: map['waveform'] != null 
          ? List<double>.from(jsonDecode(map['waveform'] as String))
          : null,
      // Runtime-only поля не читаем из БД
      playbackPosition: null,
      isPlaying: null,
    );
  }

  factory MessageModel.fromServer(Map<String, dynamic> map) {
    return MessageModel(
      id: map['id'] as String,
      chatId: map['chat_id'] as String,
      senderId: map['sender_id'] as String,
      content: map['content'] as String? ?? '',
      encryptedContent: map['encrypted_content'] as String?,
      type: map['type'] as String? ?? 'text',
      timestamp: map['timestamp'] is int 
          ? map['timestamp'] as int 
          : int.parse(map['timestamp'].toString()),
      status: map['status'] as String? ?? 'delivered',
      isRead: map['is_read'] == true || (map['is_read'] as int?) == 1,
      isDelivered: map['is_delivered'] == true || (map['is_delivered'] as int?) == 1,
      editedAt: map['edited_at'] as int?,
      reactions: map['reactions'] is Map 
          ? Map<String, String>.from(map['reactions'] as Map)
          : (map['reactions'] != null 
              ? Map<String, String>.from(jsonDecode(map['reactions'] as String))
              : {}),
      fileName: map['file_name'] as String?,
      fileSize: map['file_size'] as int?,
      localPath: map['local_path'] as String?,
      mediaUrl: map['media_url'] as String?,
      thumbnail: map['thumbnail'] as String?,
      width: map['width'] as int?,
      height: map['height'] as int?,
      duration: map['duration'] as int?,
      forwardedFrom: map['forwarded_from'] as String?,
      originalChatId: map['original_chat_id'] as String?,
      originalMessageId: map['original_message_id'] as String?,
      originalSenderUsername: map['original_sender_username'] as String?,
      replyToMessageId: map['reply_to_message_id'] as String?,
      replyToContent: map['reply_to_content'] as String?,
      replyToSenderId: map['reply_to_sender_id'] as String?,
      waveform: map['waveform'] is List 
          ? List<double>.from(map['waveform'] as List)
          : (map['waveform'] != null 
              ? List<double>.from(jsonDecode(map['waveform'] as String))
              : null),
      // Runtime-only поля не читаем из ответа сервера
      playbackPosition: null,
      isPlaying: null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'chat_id': chatId,
      'sender_id': senderId,
      'content': content,
      'encrypted_content': encryptedContent,
      'type': type,
      'timestamp': timestamp,
      'status': status,
      'is_read': isRead ? 1 : 0,
      'is_delivered': isDelivered ? 1 : 0,
      'edited_at': editedAt,
      'reactions': jsonEncode(reactions),
      'file_name': fileName,
      'file_size': fileSize,
      'local_path': localPath,
      'media_url': mediaUrl,
      'thumbnail': thumbnail,
      'width': width,
      'height': height,
      'duration': duration,
      'forwarded_from': forwardedFrom,
      'original_chat_id': originalChatId,
      'original_message_id': originalMessageId,
      'original_sender_username': originalSenderUsername,
      'reply_to_message_id': replyToMessageId,
      'reply_to_content': replyToContent,
      'reply_to_sender_id': replyToSenderId,
      'waveform': waveform != null ? jsonEncode(waveform) : null,
      // НЕ ВКЛЮЧАЕМ playback_position и is_playing - они runtime-only!
    };
  }

  MessageModel copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? content,
    String? encryptedContent,
    String? type,
    int? timestamp,
    String? status,
    bool? isRead,
    bool? isDelivered,
    int? editedAt,
    Map<String, String>? reactions,
    String? fileName,
    int? fileSize,
    String? localPath,
    String? mediaUrl,
    String? thumbnail,
    int? width,
    int? height,
    int? duration,
    String? forwardedFrom,
    String? originalChatId,
    String? originalMessageId,
    String? originalSenderUsername,
    String? replyToMessageId,
    String? replyToContent,
    String? replyToSenderId,
    List<double>? waveform,
    double? playbackPosition,
    bool? isPlaying,
  }) {
    return MessageModel(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      encryptedContent: encryptedContent ?? this.encryptedContent,
      type: type ?? this.type,
      timestamp: timestamp ?? this.timestamp,
      status: status ?? this.status,
      isRead: isRead ?? this.isRead,
      isDelivered: isDelivered ?? this.isDelivered,
      editedAt: editedAt ?? this.editedAt,
      reactions: reactions ?? this.reactions,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      localPath: localPath ?? this.localPath,
      mediaUrl: mediaUrl ?? this.mediaUrl,
      thumbnail: thumbnail ?? this.thumbnail,
      width: width ?? this.width,
      height: height ?? this.height,
      duration: duration ?? this.duration,
      forwardedFrom: forwardedFrom ?? this.forwardedFrom,
      originalChatId: originalChatId ?? this.originalChatId,
      originalMessageId: originalMessageId ?? this.originalMessageId,
      originalSenderUsername: originalSenderUsername ?? this.originalSenderUsername,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToSenderId: replyToSenderId ?? this.replyToSenderId,
      waveform: waveform ?? this.waveform,
      playbackPosition: playbackPosition ?? this.playbackPosition,
      isPlaying: isPlaying ?? this.isPlaying,
    );
  }

  @override
  String toString() {
    return 'MessageModel(id: $id, type: $type, status: $status, isPlaying: $isPlaying)';
  }
}