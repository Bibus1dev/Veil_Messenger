import 'dart:io';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart';
import 'dart:math';
import 'dart:convert';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  final Dio _dio = Dio(BaseOptions(
    baseUrl: 'http://45.132.255.167:8080',
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 30),
    headers: {
      'Content-Type': 'application/json',
    },
  ));

  String? _authToken;

  Dio get dio => _dio;

  void setAuthToken(String token) {
    _authToken = token;
    _dio.options.headers['Authorization'] = 'Bearer $token';
    
    _dio.interceptors.add(LogInterceptor(
      request: true,
      requestHeader: true,
      requestBody: true,
      responseHeader: true,
      responseBody: true,
      error: true,
    ));
  }

  String? getAuthToken() => _authToken;

  Future<Map<String, dynamic>> getHeaders() async {
    return {
      if (_authToken != null) 'Authorization': 'Bearer $_authToken',
      'Content-Type': 'application/json',
    };
  }

  Future<Response> login(String username, String password) async {
    return _dio.post('/auth/login', data: {
      'username': username,
      'password': password,
    });
  }

  Future<Response> register({
    required String email,
    required String username,
    required String displayName,
    String? bio,
    required String password,
    required String codeWord,
    String? codeWordHint,
    File? avatar,
  }) async {
    FormData formData = FormData.fromMap({
      'email': email,
      'username': username,
      'display_name': displayName,
      if (bio != null) 'bio': bio,
      'password': password,
      'code_word': codeWord,
      if (codeWordHint != null) 'code_word_hint': codeWordHint,
      if (avatar != null)
        'avatar': await MultipartFile.fromFile(
          avatar.path,
          filename: avatar.path.split('/').last,
        ),
    });

    return _dio.post('/auth/register', data: formData);
  }

      Future<Map<String, dynamic>> checkUsername(String username) async {
    try {
      final response = await _dio.get('/auth/check-username', queryParameters: {
        'username': username,
      });
      // Возвращаем весь ответ как Map для обработки banned флага
      if (response.data is Map<String, dynamic>) {
        return response.data as Map<String, dynamic>;
      }
      // Если пришёл boolean (старый формат), конвертируем
      if (response.data is bool) {
        return {'available': response.data};
      }
      return {'available': false};
    } on DioException {
      rethrow;
    } catch (e) {
      throw DioException(
        requestOptions: RequestOptions(path: '/auth/check-username'),
        error: e.toString(),
      );
    }
  }

  Future<Response> resetPassword({
    required String username,
    required String codeWord,
    required String newPassword,
  }) async {
    return _dio.post('/auth/reset-password', data: {
      'username': username,
      'code_word': codeWord,
      'new_password': newPassword,
    });
  }

  Future<Response> verifyToken() async {
    return _dio.get('/auth/verify');
  }

  Future<List<Map<String, dynamic>>> searchUsers(String query) async {
    try {
      if (query.isEmpty) return [];
      
      final response = await _dio.get('/users/search', queryParameters: {'q': query});
      
      if (response.data is Map && response.data['users'] != null) {
        final List<dynamic> usersList = response.data['users'];
        return usersList.map((user) => Map<String, dynamic>.from(user)).toList();
      }
      
      return [];
    } catch (e) {
      print('Search users error: $e');
      return [];
    }
  }

  Future<Response> getUserProfile(String userId) async {
    return _dio.get('/users/profile', queryParameters: {'user_id': userId});
  }

  Future<Response> getMyProfile() async {
    return _dio.get('/users/profile');
  }

  Future<Response> updateProfile({
    String? displayName,
    String? bio,
    File? avatar,
  }) async {
    if (avatar != null) {
      FormData formData = FormData.fromMap({
        if (displayName != null) 'display_name': displayName,
        if (bio != null) 'bio': bio,
        'avatar': await MultipartFile.fromFile(
          avatar.path,
          filename: avatar.path.split('/').last,
        ),
      });
      return _dio.put('/users/profile', data: formData);
    } else {
      return _dio.put('/users/profile', data: {
        if (displayName != null) 'display_name': displayName,
        if (bio != null) 'bio': bio,
      });
    }
  }

  Future<Response> deleteAccount(String codeWord) async {
    return _dio.delete('/users/account', data: {
      'code_word': codeWord,
    });
  }

  Future<Response> blockUser(String userId) async {
    return _dio.post('/users/block', data: {
      'user_id': userId,
    });
  }

  Future<Response> unblockUser(String userId) async {
    return _dio.post('/users/unblock', data: {
      'user_id': userId,
    });
  }

  Future<Response> reportUser(String userId, String reason) async {
    return _dio.post('/users/report', data: {
      'user_id': userId,
      'reason': reason,
    });
  }

  Future<Map<String, dynamic>?> getUserById(String userId) async {
    try {
      final response = await _dio.get('/users/profile', queryParameters: {'user_id': userId});
      
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, dynamic>.from(response.data);
      }
      
      return null;
    } catch (e) {
      print('Get user by id error: $e');
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> getMyChats() async {
    try {
      final response = await _dio.get('/chats');
      
      if (response.data is Map && response.data['chats'] != null) {
        final List<dynamic> chatsList = response.data['chats'];
        return chatsList.map((chat) => Map<String, dynamic>.from(chat)).toList();
      }
      
      return [];
    } catch (e) {
      print('Get chats error: $e');
      return [];
    }
  }

  Future<Response> createOrGetChat({
    required String chatId,
    required String otherUserId,
  }) async {
    return _dio.post('/chats/create-or-get', data: {
      'chat_id': chatId,
      'other_user_id': otherUserId,
    });
  }

  Future<Response> createChat(String userId) async {
    return _dio.post('/chats', data: {
      'user_id': userId,
    });
  }

  Future<Response> deleteChat(String chatId) async {
    return _dio.delete('/chats/$chatId');
  }

  Future<void> hideChat(String chatId) async {
    await _dio.delete('/chats/$chatId/hide');
  }

  Future<List<Map<String, dynamic>>> getAllChats() async {
    try {
      final response = await _dio.get('/chats');
      
      if (response.data is Map && response.data['chats'] != null) {
        final List<dynamic> chatsList = response.data['chats'];
        return chatsList.map((chat) => Map<String, dynamic>.from(chat)).toList();
      }
      
      return [];
    } catch (e) {
      print('Get all chats error: $e');
      return [];
    }
  }

  Future<Response> sendMessage(
  String chatId, 
  String encryptedContent, {
  String? replyToMessageId,
}) async {
  final data = {
    'chat_id': chatId,
    'content': encryptedContent,
    'type': 'text',
  };
  
  if (replyToMessageId != null) {
    data['reply_to_message_id'] = replyToMessageId;
  }
  
  return _dio.post('/messages', data: data);
}


  Future<Response> sendMediaMessage({
    required String chatId,
    required String encryptedContent,
    required String type,
    String? caption,
    String? fileName,
    int? fileSize,
    int? width,
    int? height,
    int? duration,
    bool useMultipart = false,
    String? filePath,
  }) async {
    if (useMultipart && filePath != null) {
      final formData = FormData.fromMap({
        'chat_id': chatId,
        'type': type,
        if (caption != null) 'caption': caption,
        if (fileName != null) 'file_name': fileName,
        if (fileSize != null) 'file_size': fileSize,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (duration != null) 'duration': duration,
        'encrypted_content': encryptedContent,
      });

      return _dio.post('/messages/media', data: formData);
    } else {
      return _dio.post('/messages/media', data: {
        'chat_id': chatId,
        'content': encryptedContent,
        'type': type,
        if (caption != null) 'caption': caption,
        if (fileName != null) 'file_name': fileName,
        if (fileSize != null) 'file_size': fileSize,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (duration != null) 'duration': duration,
      });
    }
  }

  Future<Response> sendMediaAlbum({
  required String chatId,
  required List<Map<String, dynamic>> mediaItems,
  String? caption,
  String? replyToMessageId,
}) async {
  final List<Map<String, dynamic>> cleanItems = mediaItems.map((item) => {
    'index': item['index'],
    'type': item['type'],
    'encrypted_content': item['encrypted_content'],
    'file_name': item['file_name'],
    'file_size': item['file_size'],
    'width': item['width'],
    'height': item['height'],
    'duration': item['duration'],
  }).toList();

  final body = {
    'chat_id': chatId,
    if (caption != null) 'caption': caption,
    'media_items': cleanItems,
  };
  
  if (replyToMessageId != null) {
    body['reply_to_message_id'] = replyToMessageId;
  }
  
  print('📤 Sending media album: ${jsonEncode(body).substring(0, min(200, jsonEncode(body).length))}...');
  
  return _dio.post(
    '/messages/media',
    data: body,
    options: Options(
      headers: {
        'Content-Type': 'application/json',
      },
    ),
  );
}

  Future<Response> getMessages(String chatId, {int limit = 50, int offset = 0}) async {
  return _dio.get(
    '/messages/$chatId',
    queryParameters: {
      'limit': limit,
      'offset': offset,
    },
  );
}

  Future<String> downloadMedia(String messageId) async {
  final response = await _dio.get(
    '/messages/$messageId/media',
    options: Options(responseType: ResponseType.json),
  );
  
  // Проверяем что пришёл JSON с encrypted_content
  if (response.data is! Map<String, dynamic>) {
    throw Exception('Invalid response format');
  }
  
  return response.data['encrypted_content'] as String;
}

  Future<Response> editMessage(String messageId, String newEncryptedContent) async {
    return _dio.put('/messages/$messageId', data: {
      'content': newEncryptedContent,
    });
  }

  Future<Response> hideMessageForMe(String messageId) async {
    return _dio.delete('/messages/$messageId/hide');
  }

  Future<Response> sendSticker({
  required String chatId,
  required String encryptedContent,
  required String fileName,
  required int fileSize,
  int width = 512,
  int height = 512,
}) async {
  return _dio.post('/messages/sticker', data: {
    'chat_id': chatId,
    'encrypted_content': encryptedContent,
    'file_name': fileName,
    'file_size': fileSize,
    'width': width,
    'height': height,
  });
}

  Future<Response> deleteMessage(String messageId, {required bool forEveryone}) async {
    return _dio.delete('/messages/$messageId', data: {
      'for_everyone': forEveryone,
    });
  }

  Future<Response> forwardMessage({
  required String messageId,
  required String targetChatId,
  required String encryptedContent,
  required bool expandUser,
  String? forwardedFrom,
  String? originalSenderUsername,
}) async {
  return _dio.post('/messages/$messageId/forward', data: {
    'target_chat_id': targetChatId,
    'targetChatId': targetChatId,
    'encrypted_content': encryptedContent,
    'expand_user': expandUser,
    'expandUser': expandUser,
    'forwarded_from': forwardedFrom,
    'original_sender_username': originalSenderUsername,
  });
}

  Future<Response> forwardMediaAlbum({
  required String messageId,
  required String targetChatId,
  required List<Map<String, dynamic>> mediaItems,
  String? caption,
  required bool expandUser,
  String? forwardedFrom,
  String? originalSenderUsername,
}) async {
  return _dio.post('/messages/$messageId/forward', data: {
    'target_chat_id': targetChatId,
    'targetChatId': targetChatId,
    'media_items': mediaItems,
    'caption': caption,
    'expand_user': expandUser,
    'expandUser': expandUser,
    'forwarded_from': forwardedFrom,
    'original_sender_username': originalSenderUsername,
  });
}

Future<Response> forwardSticker({
  required String messageId,
  required String targetChatId,
  required String encryptedContent,
  required String fileName,
  required int fileSize,
  int width = 512,
  int height = 512,
  required bool expandUser,
  String? forwardedFrom,
  String? originalSenderUsername,
}) async {
  return _dio.post('/messages/$messageId/forward', data: {
    'target_chat_id': targetChatId,
    'targetChatId': targetChatId,
    'encrypted_content': encryptedContent,
    'type': 'sticker',
    'file_name': fileName,
    'file_size': fileSize,
    'width': width,
    'height': height,
    'expand_user': expandUser,
    'expandUser': expandUser,
    'forwarded_from': forwardedFrom,
    'original_sender_username': originalSenderUsername,
  });
}

  Future<Response> sendVoiceMessage({
    required String chatId,
    required String encryptedContent,
    required String fileName,
    required int fileSize,
    required int duration,
    List<double>? waveform,
    String? replyToMessageId,
  }) async {
    final data = {
      'chat_id': chatId,
      'content': encryptedContent,
      'type': 'voice',
      'file_name': fileName,
      'file_size': fileSize,
      'duration': duration,
      'waveform': waveform,
      if (waveform != null) 'waveform': jsonEncode(waveform),
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
    };

    return _dio.post('/messages', data: data);
  }

  Future<Response> sendVideoNote({
    required String chatId,
    required String encryptedContent,
    required String fileName,
    required int fileSize,
    required int duration,
    required int width,
    required int height,
    String? replyToMessageId,
  }) async {
    final data = {
      'chat_id': chatId,
      'content': encryptedContent,
      'type': 'video_note',
      'file_name': fileName,
      'file_size': fileSize,
      'duration': duration,
      'width': width,
      'height': height,
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
    };

    return _dio.post('/messages', data: data);
  }

Future<Response> forwardMediaMessage({
  required String messageId,
  required String targetChatId,
  required String encryptedContent,
  required String type,
  String? caption,
  String? fileName,
  int? fileSize,
  int? width,
  int? height,
  int? duration,
  required bool expandUser,
  String? forwardedFrom,
  String? originalSenderUsername,
}) async {
  return _dio.post('/messages/$messageId/forward', data: {
    'target_chat_id': targetChatId,
    'targetChatId': targetChatId,
    'encrypted_content': encryptedContent,
    'type': type,
    'caption': caption,
    'file_name': fileName,
    'file_size': fileSize,
    'width': width,
    'height': height,
    'duration': duration,
    'expand_user': expandUser,
    'expandUser': expandUser,
    'forwarded_from': forwardedFrom,
    'original_sender_username': originalSenderUsername,
  });
}

  Future<Response> addReaction(String messageId, String reactionType) async {
    return _dio.post('/messages/$messageId/reactions', data: {
      'reaction': reactionType,
    });
  }

  Future<Response> removeReaction(String messageId) async {
    return _dio.delete('/messages/$messageId/reactions');
  }
}