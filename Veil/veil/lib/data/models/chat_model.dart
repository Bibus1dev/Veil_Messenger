class ChatModel {
  final String id;
  final String userId;
  final String username;
  final String? displayName;
  final String? avatarUrl;
  final String? lastMessage;
  final int? lastMessageTime;
  final int unreadCount;
  final String? encryptionKey;
  final String? lastMessageSenderId;
  final String? lastMessageStatus;
  // УДАЛИТЬ: final bool isLocallyDeleted;

  ChatModel({
    required this.id,
    required this.userId,
    required this.username,
    this.displayName,
    this.avatarUrl,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
    this.encryptionKey,
    this.lastMessageSenderId,
    this.lastMessageStatus,
    // УДАЛИТЬ: this.isLocallyDeleted = false,
  });

  ChatModel copyWith({
    String? id,
    String? userId,
    String? username,
    String? displayName,
    String? avatarUrl,
    String? lastMessage,
    int? lastMessageTime,
    int? unreadCount,
    String? encryptionKey,
    String? lastMessageSenderId,
    String? lastMessageStatus,
    // УДАЛИТЬ: bool? isLocallyDeleted,
  }) {
    return ChatModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      encryptionKey: encryptionKey ?? this.encryptionKey,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageStatus: lastMessageStatus ?? this.lastMessageStatus,
      // УДАЛИТЬ: isLocallyDeleted: isLocallyDeleted ?? this.isLocallyDeleted,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'user_id': userId,
    'username': username,
    'display_name': displayName,
    'avatar_url': avatarUrl,
    'last_message': lastMessage,
    'last_message_time': lastMessageTime,
    'unread_count': unreadCount,
    'encryption_key': encryptionKey,
    'last_message_sender_id': lastMessageSenderId,
    'last_message_status': lastMessageStatus,
    // УДАЛИТЬ: 'is_locally_deleted': isLocallyDeleted ? 1 : 0,
  };

  factory ChatModel.fromMap(Map<String, dynamic> map) => ChatModel(
    id: map['id'],
    userId: map['user_id'],
    username: map['username'],
    displayName: map['display_name'],
    avatarUrl: map['avatar_url'],
    lastMessage: map['last_message'],
    lastMessageTime: map['last_message_time'],
    unreadCount: map['unread_count'] ?? 0,
    encryptionKey: map['encryption_key'],
    lastMessageSenderId: map['last_message_sender_id'],
    lastMessageStatus: map['last_message_status'],
    // УДАЛИТЬ: isLocallyDeleted: (map['is_locally_deleted'] ?? 0) == 1,
  );
}