import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/message_model.dart';
import '../models/chat_model.dart';
import '../../../core/encryption/encryption_service.dart';

class LocalDatabase {
  static final LocalDatabase _instance = LocalDatabase._internal();
  factory LocalDatabase() => _instance;
  LocalDatabase._internal();

  Database? _database;
  String? _currentUserId;
  static Database? _metaDB;


static const int _databaseVersion = 12;

  Future<void> init() async {
    final metaPath = join(await getDatabasesPath(), 'veil_meta.db');
    _metaDB = await openDatabase(
      metaPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE current_user (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            user_id TEXT NOT NULL,
            saved_at INTEGER DEFAULT (strftime('%s', 'now'))
          )
        ''');
      },
    );
    
    final result = await _metaDB!.query('current_user', where: 'id = 1');
    if (result.isNotEmpty) {
      _currentUserId = result.first['user_id'] as String?;
      print('✅ Loaded current user from meta DB: $_currentUserId');
    }
    
    
    if (_currentUserId != null) {
      try {
        await fixExistingChats();
      } catch (e) {
        print('⚠️ fixExistingChats error: $e');
      }
    }
  }

  Future<void> setCurrentUser(String userId) async {
    _currentUserId = userId;
    _database = null;
    
    if (_metaDB != null) {
      await _metaDB!.insert(
        'current_user',
        {'id': 1, 'user_id': userId, 'saved_at': DateTime.now().millisecondsSinceEpoch ~/ 1000},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    print('✅ Current user set: $userId');
  }

  Future<String?> getCurrentUserId() async {
    if (_currentUserId == null && _metaDB != null) {
      final result = await _metaDB!.query('current_user', where: 'id = 1');
      if (result.isNotEmpty) {
        _currentUserId = result.first['user_id'] as String?;
      }
    }
    return _currentUserId;
  }

  Future<void> clearUserData() async {
    _currentUserId = null;
    _database = null;
    
    if (_metaDB != null) {
      await _metaDB!.delete('current_user', where: 'id = 1');
    }
    
    print('🗑️ User data cleared');
  }

  Future<void> deleteUserDatabase() async {
    if (_currentUserId != null) {
      final dbName = 'veil_${_currentUserId}.db';
      final path = join(await getDatabasesPath(), dbName);
      await databaseFactory.deleteDatabase(path);
      _database = null;
    }
  }

  Future<Database> get database async {
    if (_currentUserId == null) {
      throw Exception('User not authenticated');
    }
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbName = 'veil_${_currentUserId}.db';
    final path = join(await getDatabasesPath(), dbName);
    
    return openDatabase(
      path, 
      version: _databaseVersion,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  // === СОЗДАНИЕ ТАБЛИЦ (актуальная схема v8) ===
  Future<void> _createDB(Database db, int version) async {
    // Таблица пользователей
    await db.execute('''
      CREATE TABLE users (
        id TEXT PRIMARY KEY,
        username TEXT NOT NULL,
        display_name TEXT,
        avatar_url TEXT,
        bio TEXT,
        status TEXT DEFAULT 'offline',
        last_seen INTEGER,
        token TEXT,
        cached_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');
    
    // Таблица чатов
    await db.execute('''
      CREATE TABLE chats (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        user1_id TEXT,
        user2_id TEXT,
        username TEXT NOT NULL,
        display_name TEXT,
        avatar_url TEXT,
        last_message TEXT,
        last_message_time INTEGER,
        last_message_sender_id TEXT,
        last_message_status TEXT DEFAULT 'sent',
        unread_count INTEGER DEFAULT 0,
        encryption_key TEXT,
        created_at INTEGER DEFAULT (strftime('%s', 'now')),
        FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE,
        FOREIGN KEY (user1_id) REFERENCES users (id) ON DELETE CASCADE,
        FOREIGN KEY (user2_id) REFERENCES users (id) ON DELETE CASCADE
      )
    ''');
    
    // Таблица сообщений (без огромных JSON в encrypted_content)
    await db.execute('''
    CREATE TABLE messages (
      id TEXT PRIMARY KEY,
      chat_id TEXT NOT NULL,
      sender_id TEXT NOT NULL,
      content TEXT NOT NULL,
      encrypted_content TEXT,
      type TEXT DEFAULT 'text',
      status TEXT DEFAULT 'sent',
      timestamp INTEGER NOT NULL,
      is_read INTEGER DEFAULT 0,
      is_delivered INTEGER DEFAULT 0,
      edited_at INTEGER,
      reactions TEXT DEFAULT '{}',
      file_name TEXT,
      file_size INTEGER,
      local_path TEXT,
      media_url TEXT,
      thumbnail TEXT,
      width INTEGER DEFAULT 0,      
      height INTEGER DEFAULT 0,     
      duration INTEGER,
      forwarded_from TEXT,
      waveform TEXT,
      original_chat_id TEXT,
      original_message_id TEXT,
      original_sender_username TEXT,
      reply_to_message_id TEXT,        
      reply_to_content TEXT,           
      reply_to_sender_id TEXT,         
      FOREIGN KEY (chat_id) REFERENCES chats (id) ON DELETE CASCADE,
      FOREIGN KEY (sender_id) REFERENCES users (id) ON DELETE CASCADE
    )
  ''');

    // === НОВАЯ ТАБЛИЦА: медиа файлы альбомов отдельно ===
    await db.execute('''
      CREATE TABLE message_media_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id TEXT NOT NULL,
        file_index INTEGER NOT NULL,
        type TEXT NOT NULL,
        encrypted_content TEXT NOT NULL,
        file_name TEXT,
        file_size INTEGER DEFAULT 0,
        width INTEGER DEFAULT 0,
        height INTEGER DEFAULT 0,
        duration INTEGER DEFAULT 0,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
        UNIQUE(message_id, file_index)
      )
    ''');

    // Таблица скрытых сообщений
    await db.execute('''
      CREATE TABLE hidden_messages (
        message_id TEXT PRIMARY KEY,
        hidden_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');
    
    // Индексы для производительности
    await db.execute('CREATE INDEX idx_messages_chat_id ON messages(chat_id);');
    await db.execute('CREATE INDEX idx_messages_timestamp ON messages(timestamp);');
    await db.execute('CREATE INDEX idx_messages_type ON messages(type);');
    await db.execute('CREATE INDEX idx_chats_last_message ON chats(last_message_time DESC);');
    await db.execute('CREATE INDEX idx_messages_forwarded ON messages(forwarded_from);');
    await db.execute('CREATE INDEX idx_media_files_message ON message_media_files(message_id);');
  }

  // === МИГРАЦИЯ БАЗЫ ДАННЫХ ===
  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
  print('🔄 Upgrading database from v$oldVersion to v$newVersion');
  
  if (oldVersion < 2) await _migrateToV2(db);
  if (oldVersion < 3) await _migrateToV3(db);
  if (oldVersion < 4) await _migrateToV4(db);
  if (oldVersion < 5) await _migrateToV5(db);
  if (oldVersion < 6) await _migrateToV6(db);
  if (oldVersion < 7) await _migrateToV7(db);
  if (oldVersion < 8) await _migrateToV8(db);
  if (oldVersion < 9) await _migrateToV9(db); // ← ДОБАВЬ
  if (oldVersion < 10) await _migrateToV10(db); // ← НОВАЯ
  if (oldVersion < 11) await _migrateToV11(db);
  if (oldVersion < 12) await _migrateToV12(db);  // ← ДОБАВЬ
}

// === Миграция v10 → v11: добавляем waveform для голосовых ===
Future<void> _migrateToV11(Database db) async {
  print('📦 Migrating to v11: Adding waveform column...');
  
  await _addColumnIfNotExists(db, 'messages', 'waveform', 'TEXT');
  
  print('✅ Migration to v11 completed');
}

Future<void> _migrateToV12(Database db) async {
  print('📦 Migrating to v12: Adding thumbnail column...');
  
  await _addColumnIfNotExists(db, 'messages', 'thumbnail', 'TEXT');
  
  print('✅ Migration to v12 completed');
}

  // === Миграция v9 → v10: добавляем reply поля ===
  Future<void> _migrateToV10(Database db) async {
    print('📦 Migrating to v10: Adding reply fields...');
    
    await _addColumnIfNotExists(db, 'messages', 'reply_to_message_id', 'TEXT');
    await _addColumnIfNotExists(db, 'messages', 'reply_to_content', 'TEXT');
    await _addColumnIfNotExists(db, 'messages', 'reply_to_sender_id', 'TEXT');
    
    print('✅ Migration to v10 completed');
  }

  // Миграция v1 → v2: добавляем медиа-колонки
  Future<void> _migrateToV2(Database db) async {
    print('📦 Migrating to v2: Adding media columns...');
    
    final columnsToAdd = [
      {'name': 'file_name', 'type': 'TEXT'},
      {'name': 'file_size', 'type': 'INTEGER'},
      {'name': 'local_path', 'type': 'TEXT'},
      {'name': 'media_url', 'type': 'TEXT'},
      {'name': 'width', 'type': 'INTEGER'},
      {'name': 'height', 'type': 'INTEGER'},
      {'name': 'duration', 'type': 'INTEGER'},
    ];

    for (final col in columnsToAdd) {
      await _addColumnIfNotExists(db, 'messages', col['name']!, col['type']!);
    }
  }

  // Миграция v2 → v3: добавляем edited_at и reactions
  Future<void> _migrateToV3(Database db) async {
    print('📦 Migrating to v3: Adding edited_at and reactions...');
    
    await _addColumnIfNotExists(db, 'messages', 'edited_at', 'INTEGER');
    await _addColumnIfNotExists(db, 'messages', 'reactions', 'TEXT DEFAULT "{}"');
  }

  // Миграция v3 → v4: добавляем user1_id и user2_id
  Future<void> _migrateToV4(Database db) async {
    print('📦 Migrating to v4: Adding user1_id and user2_id...');
    
    await _addColumnIfNotExists(db, 'chats', 'user1_id', 'TEXT');
    await _addColumnIfNotExists(db, 'chats', 'user2_id', 'TEXT');
  }

  // Миграция v4 → v5: добавляем таблицу hidden_messages
  Future<void> _migrateToV5(Database db) async {
    print('📦 Migrating to v5: Adding hidden_messages table...');
    
    await db.execute('''
      CREATE TABLE IF NOT EXISTS hidden_messages (
        message_id TEXT PRIMARY KEY,
        hidden_at INTEGER DEFAULT (strftime('%s', 'now'))
      )
    ''');
  }

  // Миграция v5 → v6: добавляем поля пересылки
  Future<void> _migrateToV6(Database db) async {
    print('📦 Migrating to v6: Adding forwarding columns...');
    
    await _addColumnIfNotExists(db, 'messages', 'forwarded_from', 'TEXT');
    await _addColumnIfNotExists(db, 'messages', 'original_chat_id', 'TEXT');
    await _addColumnIfNotExists(db, 'messages', 'original_message_id', 'TEXT');
    
    try {
      await db.execute('CREATE INDEX idx_messages_forwarded ON messages(forwarded_from);');
    } catch (e) {
      print('⏭️ Index already exists or error: $e');
    }
  }

  // Миграция v6 → v7: добавляем original_sender_username
  Future<void> _migrateToV7(Database db) async {
    print('📦 Migrating to v7: Adding original_sender_username...');
    
    await _addColumnIfNotExists(db, 'messages', 'original_sender_username', 'TEXT');
  }

  // === КРИТИЧЕСКАЯ МИГРАЦИЯ v7 → v8: разделение альбомов ===
  Future<void> _migrateToV8(Database db) async {
    print('📦 Migrating to v8: Splitting album media to separate table...');
    
    // Создаём таблицу для медиа файлов
    await db.execute('''
      CREATE TABLE IF NOT EXISTS message_media_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id TEXT NOT NULL,
        file_index INTEGER NOT NULL,
        type TEXT NOT NULL,
        encrypted_content TEXT NOT NULL,
        file_name TEXT,
        file_size INTEGER DEFAULT 0,
        width INTEGER DEFAULT 0,
        height INTEGER DEFAULT 0,
        duration INTEGER DEFAULT 0,
        FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
        UNIQUE(message_id, file_index)
      )
    ''');
    
    await db.execute('CREATE INDEX IF NOT EXISTS idx_media_files_message ON message_media_files(message_id);');
    
    // Переносим существующие альбомы
    final albums = await db.query(
      'messages',
      where: 'type = ?',
      whereArgs: ['album'],
    );
    
    print('📁 Found ${albums.length} albums to migrate');
    
    for (final album in albums) {
      final messageId = album['id'] as String;
      final encryptedContent = album['encrypted_content'] as String?;
      
      if (encryptedContent == null || encryptedContent.isEmpty) continue;
      
      // Пропускаем если уже мигрировано (короткая строка "[N]")
      if (encryptedContent.startsWith('[') && 
          encryptedContent.length < 10 &&
          !encryptedContent.contains('"')) {
        print('⏭️ Album $messageId already migrated');
        continue;
      }
      
      try {
        final List<dynamic> mediaItems = jsonDecode(encryptedContent);
        
        for (int i = 0; i < mediaItems.length; i++) {
          final item = mediaItems[i];
          await db.insert('message_media_files', {
            'message_id': messageId,
            'file_index': i,
            'type': item['type'] ?? 'image',
            'encrypted_content': item['encrypted_content'],
            'file_name': item['file_name'],
            'file_size': item['file_size'] ?? 0,
            'width': item['width'] ?? 0,
            'height': item['height'] ?? 0,
            'duration': item['duration'] ?? 0,
          });
        }
        
        // Заменяем огромный JSON на короткую метку
        await db.update(
          'messages',
          {
            'encrypted_content': '[${mediaItems.length}]',
            'file_size': mediaItems.length,
          },
          where: 'id = ?',
          whereArgs: [messageId],
        );
        
        print('✅ Migrated album $messageId: ${mediaItems.length} files');
      } catch (e) {
        print('❌ Failed to migrate album $messageId: $e');
      }
    }
    
    print('✅ Migration to v8 completed');
  }

  // === Миграция v8 → v9: добавляем колонки для стикеров ===
Future<void> _migrateToV9(Database db) async {
  print('📦 Migrating to v9: Adding sticker columns...');
  
  await _addColumnIfNotExists(db, 'messages', 'width', 'INTEGER DEFAULT 0');
  await _addColumnIfNotExists(db, 'messages', 'height', 'INTEGER DEFAULT 0');
}



// Обнови _databaseVersion:


  // Вспомогательный метод для безопасного добавления колонок
  Future<void> _addColumnIfNotExists(
    Database db, 
    String table, 
    String column, 
    String type
  ) async {
    try {
      final checkResult = await db.rawQuery("PRAGMA table_info($table)");
      final exists = checkResult.any((row) => row['name'] == column);
      
      if (!exists) {
        await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
        print('✅ Added column: $column');
      }
    } catch (e) {
      print('❌ Error adding column $column: $e');
      rethrow;
    }
  }

  // === МЕТОДЫ ДЛЯ АЛЬБОМОВ ===

  /// Сохраняет медиа файлы альбома отдельно
  Future<void> insertAlbumMediaFiles(String messageId, List<Map<String, dynamic>> mediaItems) async {
    final db = await database;
    final batch = db.batch();
    
    for (int i = 0; i < mediaItems.length; i++) {
      final item = mediaItems[i];
      batch.insert(
        'message_media_files',
        {
          'message_id': messageId,
          'file_index': i,
          'type': item['type'] ?? 'image',
          'encrypted_content': item['encrypted_content'],
          'file_name': item['file_name'],
          'file_size': item['file_size'] ?? 0,
          'width': item['width'] ?? 0,
          'height': item['height'] ?? 0,
          'duration': item['duration'] ?? 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    
    await batch.commit();
    print('💾 Saved ${mediaItems.length} media files for album $messageId');
  }

  /// Получает медиа файлы альбома
  Future<List<Map<String, dynamic>>> getAlbumMediaFiles(String messageId) async {
    final db = await database;
    final result = await db.query(
      'message_media_files',
      where: 'message_id = ?',
      whereArgs: [messageId],
      orderBy: 'file_index ASC',
    );
    
    return result.map((row) => {
      'index': row['file_index'],
      'type': row['type'],
      'encrypted_content': row['encrypted_content'],
      'file_name': row['file_name'],
      'file_size': row['file_size'],
      'width': row['width'],
      'height': row['height'],
      'duration': row['duration'],
    }).toList();
  }

  /// Удаляет медиа файлы сообщения
  Future<void> deleteAlbumMediaFiles(String messageId) async {
    final db = await database;
    await db.delete(
      'message_media_files',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
  }

  // === ОСНОВНЫЕ МЕТОДЫ ===

  Future<void> updateMessageLocalPath(String messageId, String localPath) async {
    final db = await database;
    await db.update(
      'messages',
      {'local_path': localPath},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> updateMessageMediaUrl(String messageId, String mediaUrl) async {
    final db = await database;
    await db.update(
      'messages',
      {'media_url': mediaUrl},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> updateMessage(String messageId, Map<String, dynamic> updates) async {
    final db = await database;
    await db.update(
      'messages',
      updates,
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> updateMessageFlags(String messageId, {bool? isRead, bool? isDelivered}) async {
    final db = await database;
    
    final updates = <String, dynamic>{};
    if (isRead != null) updates['is_read'] = isRead ? 1 : 0;
    if (isDelivered != null) updates['is_delivered'] = isDelivered ? 1 : 0;
    
    if (updates.isEmpty) return;
    
    await db.update(
      'messages',
      updates,
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<MessageModel?> getMessage(String messageId) async {
  final db = await database;
  final maps = await db.query(
    'messages',
    where: 'id = ?',
    whereArgs: [messageId],
  );
  
  if (maps.isEmpty) return null;
  
  final map = Map<String, dynamic>.from(maps.first);
  
  // Для альбомов подгружаем файлы
  if (map['type'] == 'album') {
    final encryptedContent = map['encrypted_content'] as String?;
    if (encryptedContent != null && 
        encryptedContent.startsWith('[') && 
        encryptedContent.length < 10) {
      final mediaFiles = await getAlbumMediaFiles(map['id'] as String);
      if (mediaFiles.isNotEmpty) {
        map['encrypted_content'] = jsonEncode(mediaFiles);
        map['file_size'] = mediaFiles.length;
      }
    }
  }
  
  return MessageModel.fromMap(map);
}

  Future<void> saveUserWithToken(String userId, Map<String, dynamic> userData, String token) async {
    final db = await database;
    await db.insert(
      'users',
      {
        'id': userId,
        'username': userData['username'],
        'display_name': userData['display_name'],
        'avatar_url': userData['avatar_url'],
        'bio': userData['bio'],
        'status': userData['status'] ?? 'offline',
        'last_seen': userData['last_seen'] ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'token': token,
        'cached_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> getUserToken(String userId) async {
    final db = await database;
    final maps = await db.query(
      'users',
      columns: ['token'],
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (maps.isNotEmpty) {
      return maps.first['token'] as String?;
    }
    return null;
  }

  Future<void> insertUser(Map<String, dynamic> userData) async {
    final db = await database;
    await db.insert(
      'users',
      {
        'id': userData['id'],
        'username': userData['username'],
        'display_name': userData['display_name'],
        'avatar_url': userData['avatar_url'],
        'status': userData['status'] ?? 'offline',
        'last_seen': userData['last_seen'] ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'bio': userData['bio'],
        'token': userData['token'],
        'cached_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateUserStatus(String userId, String status, int lastSeen) async {
    final db = await database;
    await db.update(
      'users',
      {
        'status': status,
        'last_seen': lastSeen,
        'cached_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      },
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

  Future<Map<String, dynamic>?> getUser(String userId) async {
    final db = await database;
    final maps = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }

  Future<String?> getUserStatus(String userId) async {
    final db = await database;
    final maps = await db.query(
      'users',
      columns: ['status'],
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (maps.isNotEmpty) {
      return maps.first['status'] as String?;
    }
    return null;
  }

  Future<int?> getUserLastSeen(String userId) async {
    final db = await database;
    final maps = await db.query(
      'users',
      columns: ['last_seen'],
      where: 'id = ?',
      whereArgs: [userId],
    );
    if (maps.isNotEmpty) {
      return maps.first['last_seen'] as int?;
    }
    return null;
  }

  Future<void> deleteUser(String userId) async {
    final db = await database;
    await db.delete(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
    );
  }

 Future<void> insertChat(ChatModel chat) async {
  final db = await database;
  final currentUserId = await getCurrentUserId();
  
  await insertUser({
    'id': chat.userId,
    'username': chat.username,
    'display_name': chat.displayName,
    'avatar_url': chat.avatarUrl,
  });
  
  final userIds = [currentUserId, chat.userId]..sort();
  
  // === ФИКС: Не перезаписываем last_message если он уже есть и новый пустой ===
  // Проверяем существующий чат
  final existing = await getChat(chat.id);
  
  // Определяем финальное значение last_message
  String? finalLastMessage = chat.lastMessage;
  
  // Если новый last_message пустой, но в БД есть старый — сохраняем старый
  if ((finalLastMessage == null || finalLastMessage.isEmpty) && existing != null) {
    finalLastMessage = existing.lastMessage;
  }
  
  // Очищаем last_message если он слишком большой (JSON альбома)
  if (finalLastMessage != null) {
    if (finalLastMessage.length > 500) {
      // Если это JSON (альбом или зашифрованные данные)
      if (finalLastMessage.startsWith('[') || finalLastMessage.startsWith('{')) {
        finalLastMessage = '[Медиа]';
      } else {
        finalLastMessage = finalLastMessage.substring(0, 500);
      }
    }
  }
  
  await db.insert(
    'chats', 
    {
      'id': chat.id,
      'user_id': chat.userId,
      'user1_id': userIds[0],
      'user2_id': userIds[1],
      'username': chat.username,
      'display_name': chat.displayName,
      'avatar_url': chat.avatarUrl,
      'last_message': finalLastMessage,
      'last_message_time': chat.lastMessageTime,
      'last_message_sender_id': chat.lastMessageSenderId,
      'last_message_status': chat.lastMessageStatus ?? 'sent',
      'unread_count': chat.unreadCount,
      'encryption_key': chat.encryptionKey,
      'created_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    }, 
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
}

  // === ИСПРАВЛЕННЫЙ МЕТОД: обновление last_message с расшифровкой ===
  Future<void> updateChatLastMessage(
  String chatId,
  String? lastMessage,
  int? timestamp, {
  String? senderId,
  String? status = 'sent',
  String? messageType,
  String? encryptionKey,
}) async {
  final db = await database;
  
  String? displayMessage = lastMessage;
  
  // === ИСПРАВЛЕНИЕ: проверяем messageType ДО попытки расшифровки ===
  if (messageType == 'text' && lastMessage != null && encryptionKey != null && encryptionKey.isNotEmpty) {
    try {
      displayMessage = EncryptionService.decryptMessage(lastMessage, encryptionKey);
    } catch (e) {
      print('⚠️ Failed to decrypt last_message: $e');
      displayMessage = 'Message';
    }
  } else if (messageType == 'image' || messageType == 'video') {
    displayMessage = 'Media';
  } else if (messageType == 'album') {
    // Для альбома не расшифровываем - там зашифрованный массив
    displayMessage = 'Media';
  }
  
  // Ограничиваем размер для БД
  if (displayMessage != null && displayMessage.length > 1000) {
    displayMessage = displayMessage.substring(0, 1000);
  }
  
  await db.update(
    'chats',
    {
      'last_message': displayMessage,
      'last_message_time': timestamp,
      'last_message_sender_id': senderId,
      'last_message_status': status,
    },
    where: 'id = ?',
    whereArgs: [chatId],
  );
}

  Future<void> updateChatLastMessageStatus(String chatId, String status) async {
    final db = await database;
    await db.update(
      'chats',
      {'last_message_status': status},
      where: 'id = ?',
      whereArgs: [chatId],
    );
  }

  Future<void> incrementUnreadCount(String chatId) async {
    final db = await database;
    await db.execute(
      'UPDATE chats SET unread_count = unread_count + 1 WHERE id = ?',
      [chatId],
    );
  }

  Future<void> resetUnreadCount(String chatId) async {
    final db = await database;
    await db.update(
      'chats',
      {'unread_count': 0},
      where: 'id = ?',
      whereArgs: [chatId],
    );
  }

  Future<List<ChatModel>> getChats() async {
    final db = await database;
    try {
      final maps = await db.query(
        'chats',
        orderBy: 'last_message_time DESC, created_at DESC',
      );
      return maps.map((m) => ChatModel.fromMap(m)).toList();
    } catch (e) {
      print('Error getting chats: $e');
      return [];
    }
  }

  Future<ChatModel?> getChat(String chatId) async {
    final db = await database;
    final maps = await db.query(
      'chats',
      where: 'id = ?',
      whereArgs: [chatId],
    );
    if (maps.isNotEmpty) {
      return ChatModel.fromMap(maps.first);
    }
    return null;
  }

  Future<ChatModel?> getChatByUserId(String userId) async {
    final db = await database;
    final currentUserId = await getCurrentUserId();
    
    final result = await db.query(
      'chats',
      where: '(user1_id = ? AND user2_id = ?) OR (user1_id = ? AND user2_id = ?)',
      whereArgs: [currentUserId, userId, userId, currentUserId],
      limit: 1,
    );
    
    if (result.isEmpty) return null;
    return ChatModel.fromMap(result.first);
  }

  Future<void> deleteChat(String chatId) async {
    final db = await database;
    await db.delete(
      'chats',
      where: 'id = ?',
      whereArgs: [chatId],
    );
  }

  // === ИСПРАВЛЕННЫЙ МЕТОД: сохранение сообщения с обновлением last_message ===
 // === ИСПРАВЛЕННЫЙ МЕТОД: сохранение сообщения с обновлением last_message ===
Future<void> insertMessage(MessageModel msg, {String? encryptionKey}) async {
  final db = await database;
  try {
    // Для альбомов — сохраняем файлы отдельно!
    if (msg.type == 'album' && msg.encryptedContent != null) {
      String contentToSave = msg.encryptedContent!;
      
      // Если это полный JSON массив — разделяем
      if (contentToSave.startsWith('[') && contentToSave.length > 10) {
        try {
          final List<dynamic> mediaItems = jsonDecode(contentToSave);
          
          // Сохраняем файлы отдельно
          await insertAlbumMediaFiles(msg.id, mediaItems.cast<Map<String, dynamic>>());
          
          // В сообщении оставляем только метку
          contentToSave = '[${mediaItems.length}]';
          
          print('✅ Album ${msg.id} split: ${mediaItems.length} files saved separately');
        } catch (e) {
          print('⚠️ Failed to split album, saving as-is: $e');
        }
      }
      
      final map = msg.toMap();
      map['encrypted_content'] = contentToSave;
      
      await db.insert(
        'messages',
        map,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      // Обновляем last_message чата — для альбома показываем [Медиа]
      String? caption = msg.content.isNotEmpty ? msg.content : null;
      await updateChatLastMessage(
        msg.chatId,
        caption,
        msg.timestamp,
        senderId: msg.senderId,
        status: msg.status,
        messageType: 'album',
      );
      
    } else if (msg.type == 'sticker') {
      // === СТИКЕР: специальная обработка ===
      print('🎨 Saving STICKER: ${msg.id}');
      
      await db.insert(
        'messages',
        msg.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      // Для стикера в last_message показываем [Стикер]
      await updateChatLastMessage(
        msg.chatId,
        '[Стикер]',
        msg.timestamp,
        senderId: msg.senderId,
        status: msg.status,
        messageType: 'sticker',
      );
      
    } else {
      // Обычное сообщение (текст или одиночное медиа)
      await db.insert(
        'messages',
        msg.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      
      // Определяем что показывать в last_message
      String? displayContent;
      String? msgType = msg.type;
      
      if (msgType == 'text') {
        // Для текста — зашифрованный контент (расшифруем в updateChatLastMessage)
        displayContent = msg.encryptedContent;
      } else if (msgType == 'image' || msgType == 'video') {
        // Для одиночного медиа — [Медиа] или caption
        displayContent = msg.content.isNotEmpty ? msg.content : '[Медиа]';
        msgType = 'image';
      } else {
        displayContent = msg.content;
      }
      
      await updateChatLastMessage(
        msg.chatId,
        displayContent,
        msg.timestamp,
        senderId: msg.senderId,
        status: msg.status,
        messageType: msgType,
        encryptionKey: encryptionKey,
      );
    }
    
    print('✅ Message ${msg.id} saved (type: ${msg.type})');
    
  } catch (e, stack) {
    print('❌ FAILED to save message ${msg.id}: $e');
    rethrow;
  }
}

  Future<void> updateChat(ChatModel chat) async {
    final db = await database;
    await db.update(
      'chats',
      {
        'last_message': chat.lastMessage,
        'last_message_time': chat.lastMessageTime,
        'last_message_sender': chat.lastMessageSenderId,
        'unread_count': chat.unreadCount,
      },
      where: 'id = ?',
      whereArgs: [chat.id],
    );
  }

  Future<void> insertMessages(List<MessageModel> messages, {String? encryptionKey}) async {
    for (var msg in messages) {
      await insertMessage(msg, encryptionKey: encryptionKey);
    }
  }

  // === ИСПРАВЛЕННЫЙ МЕТОД: получение сообщений ===
  Future<List<MessageModel>> getMessages(String chatId) async {
    final db = await database;
    try {
      print('🔍 DB Query: getMessages for chat $chatId');
      
      // ИСПРАВЛЕНО: не выбираем огромные поля напрямую
      final maps = await db.query(
        'messages',
        where: 'chat_id = ?',
        whereArgs: [chatId],
        orderBy: 'timestamp DESC',
        limit: 100,
      );
      
      print('🔍 DB returned ${maps.length} rows');
      
      final messages = <MessageModel>[];
      for (int i = 0; i < maps.length; i++) {
        try {
          final map = Map<String, dynamic>.from(maps[i]);
          
          // Для альбомов — подгружаем файлы отдельно!
          if (map['type'] == 'album') {
            final encryptedContent = map['encrypted_content'] as String?;
            
            // Если это метка "[N]" — подгружаем файлы
            if (encryptedContent != null && 
                encryptedContent.startsWith('[') && 
                encryptedContent.length < 10) {
              final mediaFiles = await getAlbumMediaFiles(map['id'] as String);
              if (mediaFiles.isNotEmpty) {
                map['encrypted_content'] = jsonEncode(mediaFiles);
                map['file_size'] = mediaFiles.length;
              }
            }
          }
          
          final msg = MessageModel.fromMap(map);
          messages.add(msg);
        } catch (e) {
          print('❌ Failed to parse message at index $i: $e');
        }
      }
      
      print('🔍 Parsed ${messages.length} messages successfully');
      return messages;
      
    } catch (e, stack) {
      print('❌ DB query failed: $e');
      return [];
    }
  }

  Future<List<MessageModel>> getUnreadMessages(String chatId) async {
    final db = await database;
    try {
      final maps = await db.query(
        'messages',
        where: 'chat_id = ? AND is_read = 0',
        whereArgs: [chatId],
        orderBy: 'timestamp ASC',
      );
      
      final messages = <MessageModel>[];
      for (final map in maps) {
        final m = Map<String, dynamic>.from(map);
        
        if (m['type'] == 'album') {
          final mediaFiles = await getAlbumMediaFiles(m['id'] as String);
          if (mediaFiles.isNotEmpty) {
            m['encrypted_content'] = jsonEncode(mediaFiles);
          }
        }
        
        messages.add(MessageModel.fromMap(m));
      }
      
      return messages;
    } catch (e) {
      print('Error getting unread messages: $e');
      return [];
    }
  }

  Future<bool> messageExists(String messageId) async {
    final db = await database;
    final result = await db.query(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
    return result.isNotEmpty;
  }

  Future<void> updateMessageStatus(String messageId, String status) async {
    final db = await database;
    await db.update(
      'messages',
      {'status': status},
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> updateMessageId(String oldId, String newId) async {
    final db = await database;
    
    // Обновляем и в messages, и в media_files
    await db.update(
      'messages',
      {'id': newId},
      where: 'id = ?',
      whereArgs: [oldId],
    );
    
    await db.update(
      'message_media_files',
      {'message_id': newId},
      where: 'message_id = ?',
      whereArgs: [oldId],
    );
  }

  Future<void> markMessageAsRead(String messageId) async {
    final db = await database;
    await db.update(
      'messages',
      {
        'is_read': 1,
        'status': 'read',
      },
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> markAllMessagesAsRead(String chatId) async {
    final db = await database;
    await db.update(
      'messages',
      {
        'is_read': 1,
        'status': 'read',
      },
      where: 'chat_id = ? AND is_read = 0',
      whereArgs: [chatId],
    );
    await resetUnreadCount(chatId);
    await updateChatLastMessageStatus(chatId, 'read');
  }

  Future<void> markChatMessagesAsRead(String chatId, String readerId) async {
    final db = await database;
    final result = await db.update(
      'messages',
      {
        'is_read': 1,
        'status': 'read',
      },
      where: 'chat_id = ? AND sender_id != ? AND is_read = 0',
      whereArgs: [chatId, readerId],
    );
    
    if (result > 0) {
      await db.update(
        'chats',
        {'last_message_status': 'read'},
        where: 'id = ?',
        whereArgs: [chatId],
      );
      
      await resetUnreadCount(chatId);
    }
  }

  Future<void> deleteMessage(String messageId) async {
    final db = await database;
    
    // Удаляем файлы альбома
    await deleteAlbumMediaFiles(messageId);
    
    // Удаляем сообщение
    await db.delete(
      'messages',
      where: 'id = ?',
      whereArgs: [messageId],
    );
  }

  Future<void> deleteChatMessages(String chatId) async {
    final db = await database;
    
    // Удаляем файлы альбомов этого чата
    final messages = await db.query(
      'messages',
      where: 'chat_id = ? AND type = ?',
      whereArgs: [chatId, 'album'],
    );
    
    for (final msg in messages) {
      await deleteAlbumMediaFiles(msg['id'] as String);
    }
    
    // Удаляем сообщения
    await db.delete(
      'messages',
      where: 'chat_id = ?',
      whereArgs: [chatId],
    );
  }

  Future<void> syncUserProfile(Map<String, dynamic> userData) async {
    await insertUser(userData);
  }

  Future<void> syncChatAndUser(Map<String, dynamic> chatData, Map<String, dynamic> userData) async {
    await insertUser(userData);
    await insertChat(ChatModel.fromMap({
      ...chatData,
      'user_id': userData['id'],
      'username': userData['username'],
      'display_name': userData['display_name'],
      'avatar_url': userData['avatar_url'],
    }));
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('message_media_files');
    await db.delete('messages');
    await db.delete('chats');
    await db.delete('users');
  }

  Future<void> clearOldCache() async {
    final db = await database;
    final weekAgo = (DateTime.now().millisecondsSinceEpoch ~/ 1000) - 604800;
    
    await db.delete(
      'users',
      where: 'cached_at < ? AND id != ?',
      whereArgs: [weekAgo, _currentUserId],
    );
  }

  Future<Map<String, dynamic>?> getUserWithStatus(String userId) async {
    final db = await database;
    final maps = await db.query(
      'users',
      where: 'id = ?',
      whereArgs: [userId],
    );
    
    if (maps.isNotEmpty) {
      return maps.first;
    }
    return null;
  }

  Future<void> updateChatWithUserStatus(String chatId, String status, int lastSeen) async {
    final chat = await getChat(chatId);
    if (chat != null) {
      await updateUserStatus(chat.userId, status, lastSeen);
    }
  }

  Future<void> batchInsertMessages(List<MessageModel> messages, {String? encryptionKey}) async {
    for (var message in messages) {
      await insertMessage(message, encryptionKey: encryptionKey);
    }
  }

  Future<void> batchUpdateMessageStatuses(Map<String, String> messageStatuses) async {
    final db = await database;
    final batch = db.batch();
    
    messageStatuses.forEach((messageId, status) {
      batch.update(
        'messages',
        {'status': status},
        where: 'id = ?',
        whereArgs: [messageId],
      );
    });
    
    await batch.commit();
  }

  // === МЕТОДЫ ДЛЯ СКРЫТЫХ СООБЩЕНИЙ ===

  Future<void> hideMessageLocally(String messageId) async {
    final db = await database;
    await db.insert(
      'hidden_messages',
      {'message_id': messageId},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    print('🙈 Message $messageId hidden locally');
  }

  Future<bool> isMessageHidden(String messageId) async {
    final db = await database;
    final result = await db.query(
      'hidden_messages',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    return result.isNotEmpty;
  }

  Future<Set<String>> getAllHiddenMessageIds() async {
    final db = await database;
    final result = await db.query('hidden_messages');
    return result.map((row) => row['message_id'] as String).toSet();
  }

  Future<void> unhideMessage(String messageId) async {
    final db = await database;
    await db.delete(
      'hidden_messages',
      where: 'message_id = ?',
      whereArgs: [messageId],
    );
    print('👁️ Message $messageId unhidden');
  }

  // === ВРЕМЕННЫЙ МЕТОД: починка существующих чатов ===
  Future<void> fixExistingChats() async {
    final db = await database;
    final chats = await db.query('chats');
    
    int fixedCount = 0;
    
    for (final chat in chats) {
      final lastMessage = chat['last_message'] as String?;
      if (lastMessage == null) continue;
      
      String fixedMessage = lastMessage;
      bool needsFix = false;
      
      // Если это огромный JSON — заменяем на [Медиа]
      if (lastMessage.length > 200 && (lastMessage.startsWith('[') || lastMessage.startsWith('{'))) {
        fixedMessage = '[Медиа]';
        needsFix = true;
      }
      // Если это зашифрованный контент альбома (начинается с [ и содержит encrypted_content)
      else if (lastMessage.length > 50 && lastMessage.startsWith('[') && lastMessage.contains('"encrypted_content"')) {
        fixedMessage = '[Медиа]';
        needsFix = true;
      }
      
      if (needsFix) {
        await db.update(
          'chats',
          {'last_message': fixedMessage},
          where: 'id = ?',
          whereArgs: [chat['id']],
        );
        fixedCount++;
        print('🩹 Fixed chat ${chat['id']}: ${lastMessage.length} chars → "$fixedMessage"');
      }
    }
    
    if (fixedCount > 0) {
      print('✅ Fixed $fixedCount chats with oversized last_message');
    }
  }
}