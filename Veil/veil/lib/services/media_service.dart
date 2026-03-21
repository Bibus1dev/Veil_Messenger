import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart' hide Image;
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:mime/mime.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:audio_waveforms/audio_waveforms.dart';
import 'package:camera/camera.dart';
import '../../core/encryption/encryption_service.dart';

class MediaService {
  static final MediaService _instance = MediaService._internal();
  factory MediaService() => _instance;
  MediaService._internal();

  static const int _maxImageWidth = 1920;
  static const int _maxImageHeight = 1920;
  static const int _maxVideoNoteDuration = 60; // 1 минута
  static const int _maxVoiceDuration = 170; // 2:50
  static const int _videoNoteResolution = 480;

  RecorderController? _recorderController;
  PlayerController? _playerController;
  
  bool _isRecording = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  
  // === РЕАЛЬНЫЕ ДАННЫЕ WAVEFORM ===
  final List<double> _currentWaveformData = [];
  StreamSubscription? _waveformSubscription;
  
  // Callbacks для UI
  Function(List<double>)? onWaveformUpdate;
  Function(int)? onDurationUpdate;
  Function()? onMaxDurationReached;

  MediaType getMediaType(String filePath) {
    final mimeType = lookupMimeType(filePath) ?? '';
    final ext = path.extension(filePath).toLowerCase();
    
    if (mimeType.startsWith('image/') || ['.webp', '.png', '.jpg', '.jpeg'].contains(ext)) {
      return MediaType.image;
    }
    if (mimeType.startsWith('video/') || ext == '.mp4') {
      return MediaType.video;
    }
    if (mimeType.startsWith('audio/') || ['.aac', '.m4a', '.mp3'].contains(ext)) {
      return MediaType.audio;
    }
    return MediaType.unknown;
  }

  // ==================== ГОЛОСОВЫЕ ====================

  Future<bool> hasAudioPermission() async {
    _recorderController ??= RecorderController();
    return await _recorderController!.checkPermission();
  }

  Future<void> requestAudioPermission() async {
    _recorderController ??= RecorderController();
    await _recorderController!.checkPermission();
  }

  Future<VoiceRecordingResult> startVoiceRecording() async {
    if (_isRecording) throw Exception('Already recording');

    final hasPermission = await hasAudioPermission();
    if (!hasPermission) throw Exception('No audio permission');

    // Очищаем предыдущие данные
    _currentWaveformData.clear();
    
    // Создаём новый контроллер с правильными настройками
    _recorderController = RecorderController()
      ..androidEncoder = AndroidEncoder.aac
      ..androidOutputFormat = AndroidOutputFormat.mpeg4
      ..iosEncoder = IosEncoder.kAudioFormatMPEG4AAC
      ..sampleRate = 44100
      ..bitRate = 256000;

    final dir = await getTemporaryDirectory();
    final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final filePath = path.join(dir.path, fileName);

    // === КЛЮЧЕВОЕ: Подписываемся на waveform ДО начала записи ===
    _waveformSubscription = _recorderController!.onCurrentDuration.listen((duration) {
      // Получаем текущие данные waveform
      final waveData = _recorderController!.waveData;
      
      if (waveData.isNotEmpty) {
        // Нормализуем данные (0.0 - 1.0)
        final normalized = _normalizeWaveform(waveData);
        _currentWaveformData.addAll(normalized);
        
        // Отправляем обновление в UI
        onWaveformUpdate?.call(List<double>.from(_currentWaveformData));
        
        // Обновляем длительность
        final seconds = duration.inSeconds;
        onDurationUpdate?.call(seconds);
        
        // Проверяем лимит
        if (seconds >= _maxVoiceDuration) {
          onMaxDurationReached?.call();
        }
      }
    });

    // Начинаем запись
    await _recorderController!.record(path: filePath);

    _isRecording = true;
    _currentRecordingPath = filePath;
    _recordingStartTime = DateTime.now();

    return VoiceRecordingResult(
      filePath: filePath,
      startTime: _recordingStartTime!,
      waveform: [],
      durationSeconds: 0,
    );
  }

    Future<VoiceRecordingResult> stopVoiceRecording() async {
    if (!_isRecording || _recorderController == null) {
      throw Exception('Not recording');
    }

    // Отписываемся от стрима
    await _waveformSubscription?.cancel();
    _waveformSubscription = null;

    // Останавливаем запись
    final filePath = await _recorderController!.stop();
    _isRecording = false;

    if (filePath == null || filePath.isEmpty) {
      throw Exception('Recording failed');
    }

    // Получаем финальные данные waveform
    final finalWaveData = _recorderController!.waveData;
    final normalizedWaveform = _normalizeWaveform(finalWaveData);
    
    // Получаем длительность через запись
    final duration = _currentWaveformData.length ~/ 10; // Примерно 10 точек в секунду
    
    // Или через файл
    final file = File(filePath);
    final fileSize = await file.length();

    // Очищаем контроллер
    _recorderController?.dispose();
    _recorderController = null;

    return VoiceRecordingResult(
      filePath: filePath,
      startTime: _recordingStartTime!,
      duration: duration > 0 ? duration : 1,
      fileSize: fileSize,
      waveform: normalizedWaveform,
      isFinal: true,
    );
  }

  Future<void> cancelVoiceRecording() async {
    await _waveformSubscription?.cancel();
    _waveformSubscription = null;
    
    if (_isRecording && _recorderController != null) {
      await _recorderController!.stop();
      _isRecording = false;
      _currentWaveformData.clear();
      
      if (_currentRecordingPath != null) {
        try {
          await File(_currentRecordingPath!).delete();
        } catch (e) {}
      }
      
      _recorderController?.dispose();
      _recorderController = null;
    }
  }

  // ==================== НОРМАЛИЗАЦИЯ WAVEFORM ====================

  List<double> _normalizeWaveform(List<double> data) {
    if (data.isEmpty) return [];
    
    // Находим максимальное значение
    double max = 0;
    for (final v in data) {
      if (v.abs() > max) max = v.abs();
    }
    
    if (max == 0) return data.map((_) => 0.0).toList();
    
    // Нормализуем в диапазон 0.0 - 1.0
    return data.map((v) => (v.abs() / max).clamp(0.0, 1.0)).toList();
  }

  List<double> getCurrentWaveform() {
    return List<double>.from(_currentWaveformData);
  }

  // ==================== ПЛЕЕР ====================

  Future<PlayerController> prepareVoicePlayer(String filePath) async {
    _playerController?.dispose();
    _playerController = PlayerController();
    
    await _playerController!.preparePlayer(
      path: filePath,
      shouldExtractWaveform: true, // Извлекаем waveform для отображения
    );
    
    return _playerController!;
  }

  Future<List<double>> extractWaveformFromFile(String filePath) async {
    final tempController = PlayerController();
    try {
      await tempController.preparePlayer(
        path: filePath,
        shouldExtractWaveform: true,
      );
      
      // Ждём немного чтобы waveform извлёкся
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Получаем данные waveform
      final waveData = tempController.waveformData;
      tempController.dispose();
      
      return _normalizeWaveform(waveData);
    } catch (e) {
      tempController.dispose();
      return [];
    }
  }

  // ==================== ВИДЕО-КРУЖКИ ====================

  Future<VideoNoteRecordingResult> startVideoNoteRecording() async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      frontCamera,
      ResolutionPreset.medium,
      enableAudio: true,
    );

    await controller.initialize();

    return VideoNoteRecordingResult(
      controller: controller,
      startTime: DateTime.now(),
    );
  }

  Future<VideoNoteResult> stopVideoNoteRecording(CameraController controller) async {
    if (!controller.value.isRecordingVideo) {
      throw Exception('Not recording video');
    }

    final file = await controller.stopVideoRecording();
    final now = DateTime.now();
    final duration = now.difference(_recordingStartTime ?? now).inSeconds.abs();

    final processed = await _processVideoNote(file.path);

    return VideoNoteResult(
      filePath: processed.path,
      duration: duration.clamp(0, _maxVideoNoteDuration),
      width: _videoNoteResolution,
      height: _videoNoteResolution,
      thumbnail: processed.thumbnail,
    );
  }

  Future<void> cancelVideoNoteRecording(CameraController? controller) async {
    if (controller != null) {
      if (controller.value.isRecordingVideo) {
        await controller.stopVideoRecording();
      }
      await controller.dispose();
    }
  }

  Future<ProcessedVideoNote> _processVideoNote(String sourcePath) async {
    final dir = await getTemporaryDirectory();
    final outputName = 'videonote_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final outputPath = path.join(dir.path, outputName);

    final info = await VideoCompress.compressVideo(
      sourcePath,
      quality: VideoQuality.MediumQuality,
      deleteOrigin: false,
      includeAudio: true,
    );

    if (info?.file == null) throw Exception('Video compression failed');

    final thumbBytes = await vt.VideoThumbnail.thumbnailData(
      video: info!.path!,
      imageFormat: vt.ImageFormat.JPEG,
      maxWidth: _videoNoteResolution,
      quality: 75,
    );

    String? thumbnailPath;
    if (thumbBytes != null) {
      final thumbName = 'videonote_thumb_${DateTime.now().millisecondsSinceEpoch}.jpg';
      thumbnailPath = path.join(dir.path, thumbName);
      await File(thumbnailPath).writeAsBytes(thumbBytes);
    }

    return ProcessedVideoNote(
      path: info.path!,
      thumbnail: thumbnailPath,
    );
  }

  // ==================== ИЗОБРАЖЕНИЯ И ВИДЕО ====================

  Future<MediaProcessingResult> compressImage(
    String sourcePath, {
    bool disableCompression = false,
  }) async {
    final file = File(sourcePath);
    final originalSize = await file.length();
    
    if (disableCompression) {
      return MediaProcessingResult(
        path: sourcePath,
        originalSize: originalSize,
        processedSize: originalSize,
        width: null,
        height: null,
        wasCompressed: false,
      );
    }

    final dir = await getTemporaryDirectory();
    final targetPath = path.join(dir.path, 'compressed_${DateTime.now().millisecondsSinceEpoch}.jpg');

    try {
      final result = await FlutterImageCompress.compressWithFile(
        sourcePath,
        minWidth: _maxImageWidth,
        minHeight: _maxImageHeight,
        quality: 85,
        format: CompressFormat.jpeg,
      );

      if (result == null) throw Exception('Compression failed');

      await File(targetPath).writeAsBytes(result);
      
      final decodedImage = await decodeImageFromList(result);
      
      return MediaProcessingResult(
        path: targetPath,
        originalSize: originalSize,
        processedSize: result.length,
        width: decodedImage.width,
        height: decodedImage.height,
        wasCompressed: true,
      );
    } catch (e) {
      return MediaProcessingResult(
        path: sourcePath,
        originalSize: originalSize,
        processedSize: originalSize,
        width: null,
        height: null,
        wasCompressed: false,
        error: e.toString(),
      );
    }
  }

  Future<MediaProcessingResult> compressVideo(
    String sourcePath, {
    bool disableCompression = false,
  }) async {
    final file = File(sourcePath);
    final originalSize = await file.length();

    if (disableCompression) {
      final info = await VideoCompress.getMediaInfo(sourcePath);
      return MediaProcessingResult(
        path: sourcePath,
        originalSize: originalSize,
        processedSize: originalSize,
        width: info.width,
        height: info.height,
        duration: info.duration?.toInt(),
        wasCompressed: false,
      );
    }

    try {
      final info = await VideoCompress.compressVideo(
        sourcePath,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );

      if (info?.file == null) throw Exception('Video compression failed');

      return MediaProcessingResult(
        path: info!.path!,
        originalSize: originalSize,
        processedSize: await info.file!.length(),
        width: info.width,
        height: info.height,
        duration: info.duration?.toInt(),
        wasCompressed: true,
      );
    } catch (e) {
      final info = await VideoCompress.getMediaInfo(sourcePath);
      return MediaProcessingResult(
        path: sourcePath,
        originalSize: originalSize,
        processedSize: originalSize,
        width: info.width,
        height: info.height,
        duration: info.duration?.toInt(),
        wasCompressed: false,
        error: e.toString(),
      );
    }
  }

  // ==================== ШИФРОВАНИЕ ====================

  Future<EncryptedMedia> encryptFile(
    String filePath,
    String encryptionKey, {
    String? fileName,
  }) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    
    print('🔐 Encrypting ${bytes.length} bytes...');
    
    final encryptedBase64 = EncryptionService.encryptFile(bytes, encryptionKey);
    
    print('🔐 Encrypted to ${encryptedBase64.length} chars base64');
    
    final dir = await getTemporaryDirectory();
    final encryptedFileName = '${DateTime.now().millisecondsSinceEpoch}.enc';
    final encryptedPath = path.join(dir.path, encryptedFileName);
    
    await File(encryptedPath).writeAsString(encryptedBase64);
    
    return EncryptedMedia(
      encryptedFilePath: encryptedPath,
      encryptedBase64: encryptedBase64,
      originalSize: bytes.length,
      encryptedSize: encryptedBase64.length,
      fileName: fileName ?? path.basename(filePath),
    );
  }

  Future<String> decryptAndSave(
    String encryptedBase64,
    String encryptionKey,
    String fileName,
  ) async {
    print('🔓 Decrypting ${encryptedBase64.length} chars...');
    
    final decryptedBytes = EncryptionService.decryptFile(encryptedBase64, encryptionKey);
    
    print('🔓 Decrypted to ${decryptedBytes.length} bytes');
    
    final dir = await getApplicationDocumentsDirectory();
    final chatDir = Directory(path.join(dir.path, 'media'))..createSync(recursive: true);
    final filePath = path.join(chatDir.path, '${DateTime.now().millisecondsSinceEpoch}_$fileName');
    
    await File(filePath).writeAsBytes(decryptedBytes);
    return filePath;
  }

  Future<String?> generateVideoThumbnail(String videoPath) async {
    try {
      final bytes = await vt.VideoThumbnail.thumbnailData(
        video: videoPath,
        imageFormat: vt.ImageFormat.JPEG,
        maxWidth: 512,
        quality: 75,
      );
      if (bytes == null) return null;
      
      final dir = await getTemporaryDirectory();
      final thumbPath = path.join(dir.path, 'thumb_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(thumbPath).writeAsBytes(bytes);
      return thumbPath;
    } catch (e) {
      print('Thumbnail error: $e');
      return null;
    }
  }

  Future<void> cleanupTempFiles() async {
    final dir = await getTemporaryDirectory();
    final files = dir.listSync();
    final now = DateTime.now();
    
    for (var file in files) {
      if (file is File) {
        final stat = await file.stat();
        if (now.difference(stat.modified).inHours > 24) {
          await file.delete();
        }
      }
    }
  }

  bool get isRecording => _isRecording;
  
  RecorderController? get recorderController => _recorderController;
  
  PlayerController? get playerController => _playerController;

  void dispose() {
    _waveformSubscription?.cancel();
    _recorderController?.dispose();
    _playerController?.dispose();
    _recorderController = null;
    _playerController = null;
  }
}

enum MediaType { image, video, audio, unknown }

class MediaProcessingResult {
  final String path;
  final int originalSize;
  final int processedSize;
  final int? width;
  final int? height;
  final int? duration;
  final bool wasCompressed;
  final String? error;

  MediaProcessingResult({
    required this.path,
    required this.originalSize,
    required this.processedSize,
    this.width,
    this.height,
    this.duration,
    required this.wasCompressed,
    this.error,
  });

  double get compressionRatio => originalSize > 0 
      ? (1 - processedSize / originalSize) * 100 
      : 0;
}

class EncryptedMedia {
  final String encryptedFilePath;
  final String encryptedBase64;
  final int originalSize;
  final int encryptedSize;
  final String fileName;

  EncryptedMedia({
    required this.encryptedFilePath,
    required this.encryptedBase64,
    required this.originalSize,
    required this.encryptedSize,
    required this.fileName,
  });
}

class VoiceRecordingResult {
  final String filePath;
  final DateTime startTime;
  final int? duration;
  final int? fileSize;
  final List<double>? waveform;
  final bool isPaused;
  final bool isFinal;
  final int durationSeconds;

  VoiceRecordingResult({
    required this.filePath,
    required this.startTime,
    this.duration,
    this.fileSize,
    this.waveform,
    this.isPaused = false,
    this.isFinal = false,
    this.durationSeconds = 0,
  });

  String get formattedDuration {
    if (duration == null) return '00:00';
    final mins = duration! ~/ 60;
    final secs = duration! % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }
}

class VideoNoteRecordingResult {
  final CameraController controller;
  final DateTime startTime;
  final bool isPaused;

  VideoNoteRecordingResult({
    required this.controller,
    required this.startTime,
    this.isPaused = false,
  });
}

class VideoNoteResult {
  final String filePath;
  final int duration;
  final int width;
  final int height;
  final String? thumbnail;

  VideoNoteResult({
    required this.filePath,
    required this.duration,
    required this.width,
    required this.height,
    this.thumbnail,
  });
}

class ProcessedVideoNote {
  final String path;
  final String? thumbnail;

  ProcessedVideoNote({
    required this.path,
    this.thumbnail,
  });
}