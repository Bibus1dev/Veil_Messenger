import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt;

class EncryptionService {
  // === ТЕКСТ ===
  static String encryptMessage(String message, String key) {
    final keyBytes = _deriveKey(key);
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.cbc),
    );
    final encrypted = encrypter.encrypt(message, iv: iv);
    
    final combined = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combined.setAll(0, iv.bytes);
    combined.setAll(iv.bytes.length, encrypted.bytes);
    return base64Encode(combined);
  }

  // Добавьте если нет:

static Uint8List decryptBytes(Uint8List encryptedData, String key) {
  final encryptedBase64 = base64Encode(encryptedData);
  return decryptFile(encryptedBase64, key);
}

static Uint8List encryptBytes(Uint8List data, String key) {
  final encryptedBase64 = encryptFile(data, key);
  return base64Decode(encryptedBase64);
}

  static String decryptMessage(String encryptedMessage, String key) {
    final keyBytes = _deriveKey(key);
    final combined = base64Decode(encryptedMessage);
    final iv = encrypt.IV(Uint8List.fromList(combined.sublist(0, 16)));
    final encryptedBytes = Uint8List.fromList(combined.sublist(16));
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.cbc),
    );
    return encrypter.decrypt(encrypt.Encrypted(encryptedBytes), iv: iv);
  }

  // === ФАЙЛЫ (ПРОСТОЕ ШИФРОВАНИЕ) ===
  static String encryptFile(Uint8List fileBytes, String key) {
    final keyBytes = _deriveKey(key);
    final iv = encrypt.IV.fromSecureRandom(16);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.cbc),
    );
    
    final encrypted = encrypter.encryptBytes(fileBytes, iv: iv);
    
    // IV (16 байт) + зашифрованные данные
    final combined = Uint8List(iv.bytes.length + encrypted.bytes.length);
    combined.setAll(0, iv.bytes);
    combined.setAll(iv.bytes.length, encrypted.bytes);
    
    return base64Encode(combined);
  }

  static Uint8List decryptFile(String encryptedBase64, String key) {
    final data = base64Decode(encryptedBase64);
    final keyBytes = _deriveKey(key);
    
    print('🔓 Decoding base64: ${data.length} bytes');
    
    if (data.length < 17) {
      throw Exception('Data too short: ${data.length} bytes');
    }
    
    // Извлекаем IV (первые 16 байт)
    final iv = encrypt.IV(Uint8List.fromList(data.sublist(0, 16)));
    
    // Остальное - зашифрованные данные
    final encryptedBytes = Uint8List.fromList(data.sublist(16));
    
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(keyBytes), mode: encrypt.AESMode.cbc),
    );
    
    final decrypted = encrypter.decryptBytes(
      encrypt.Encrypted(encryptedBytes), 
      iv: iv,
    );
    
    print('🔓 Decrypted to ${decrypted.length} bytes');
    
    // FIX: преобразуем List<int> в Uint8List
    return Uint8List.fromList(decrypted);
  }

  // === УТИЛИТЫ ===
  static Uint8List _deriveKey(String password) {
    return Uint8List.fromList(sha256.convert(utf8.encode(password)).bytes);
  }

  static String generateKey() {
    final random = Random.secure();
    return base64Encode(List<int>.generate(32, (_) => random.nextInt(256)));
  }
}