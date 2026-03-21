import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../data/models/sticker_pack_model.dart';
import 'api_service.dart';

class StickerService extends ChangeNotifier {
  static final StickerService _instance = StickerService._internal();
  factory StickerService() => _instance;
  StickerService._internal();
  
  final Dio _dio = Dio();
  String? _stickersDir;
  
  final Map<String, List<StickerModel>> _stickerCache = {};
  final Map<String, StickerPackModel> _packCache = {};
  
  int _version = 0;
  int get version => _version;
  
  // === НОВОЕ: Stream для уведомлений об изменениях ===
  final _changeController = StreamController<void>.broadcast();
  Stream<void> get onChange => _changeController.stream;
  
  Future<void> init() async {
    final appDir = await getApplicationDocumentsDirectory();
    _stickersDir = path.join(appDir.path, 'stickers');
    await Directory(_stickersDir!).create(recursive: true);
    
    await _loadInstalledPacksFromDisk();
  }

  String get stickersDir => _stickersDir!;
  
  void _notifyChange() {
    _version++;
    print('📢 StickerService changed, version: $_version');
    _changeController.add(null); // Уведомляем через Stream
    notifyListeners(); // И через ChangeNotifier
  }
  
  Future<List<StickerPackModel>> getStickerPacks() async {
    try {
      final response = await ApiService().dio.get('/stickers/packs');
      final List<dynamic> packsJson = response.data['packs'] ?? [];
      
      final installedIds = await _getInstalledPackIdsFromDisk();
      
      final packs = packsJson.map((json) {
        final packId = json['id'];
        final isInstalled = installedIds.contains(packId) || 
                           _packCache[packId]?.isInstalled == true;
        
        return StickerPackModel.fromJson({
          ...json,
          'installed': isInstalled,
        });
      }).toList();
      
      for (var pack in packs) {
        final existing = _packCache[pack.id];
        _packCache[pack.id] = pack.copyWith(
          isInstalled: existing?.isInstalled ?? pack.isInstalled,
        );
      }
      
      return packs;
    } catch (e) {
      print('❌ Error getting sticker packs: $e');
      return _packCache.values.where((p) => p.isInstalled).toList();
    }
  }

  Future<Set<String>> _getInstalledPackIdsFromDisk() async {
    final dir = Directory(_stickersDir!);
    if (!await dir.exists()) return {};
    
    final entities = await dir.list().toList();
    final ids = <String>{};
    
    for (var entity in entities) {
      if (entity is Directory) {
        final packId = path.basename(entity.path);
        final metaFile = File(path.join(_stickersDir!, '$packId.json'));
        if (await metaFile.exists()) {
          ids.add(packId);
        }
      }
    }
    
    return ids;
  }

  Future<void> _loadInstalledPacksFromDisk() async {
    print('📦 Loading installed packs from disk...');
    
    final dir = Directory(_stickersDir!);
    if (!await dir.exists()) {
      print('⚠️ Stickers directory not found');
      return;
    }
    
    final entities = await dir.list().toList();
    int loadedCount = 0;
    
    for (var entity in entities) {
      if (entity is Directory) {
        final packId = path.basename(entity.path);
        final metaFile = File(path.join(_stickersDir!, '$packId.json'));
        
        if (await metaFile.exists()) {
          try {
            final json = jsonDecode(await metaFile.readAsString());
            final pack = StickerPackModel.fromJson({
              ...json,
              'installed': true,
            });
            
            _packCache[packId] = pack;
            loadedCount++;
            
            final stickers = await _getLocalStickers(packId);
            _stickerCache[packId] = stickers;
            
            print('  ✅ Loaded pack: ${pack.name} (${stickers.length} stickers)');
          } catch (e) {
            print('  ❌ Failed to load pack $packId: $e');
          }
        }
      }
    }
    
    print('📦 Loaded $loadedCount installed packs from disk');
  }
  
  Future<StickerPackModel?> getStickerPack(String packId) async {
    if (_packCache.containsKey(packId)) {
      return _packCache[packId];
    }
    
    try {
      final response = await ApiService().dio.get('/stickers/pack/$packId');
      final pack = StickerPackModel.fromJson(response.data);
      _packCache[packId] = pack;
      return pack;
    } catch (e) {
      print('❌ Error getting pack $packId: $e');
      return null;
    }
  }
  
  // === ИСПРАВЛЕННЫЙ МЕТОД: принудительно перезагружаем с сервера ===
  Future<List<StickerModel>> getPackStickers(String packId, {bool forceRefresh = false}) async {
    // Если не forceRefresh — пробуем локальный кэш
    if (!forceRefresh) {
      final localStickers = await _getLocalStickers(packId);
      if (localStickers.isNotEmpty) {
        print('📁 Found ${localStickers.length} local stickers for pack $packId');
        _stickerCache[packId] = localStickers;
        return localStickers;
      }
      
      if (_stickerCache.containsKey(packId) && _stickerCache[packId]!.isNotEmpty) {
        print('💾 Using cached stickers for pack $packId');
        return _stickerCache[packId]!;
      }
    }
    
    // Загружаем с сервера
    try {
      print('🌐 Loading stickers from server for pack $packId');
      final response = await ApiService().dio.get('/stickers/pack/$packId');
      final List<dynamic> stickersJson = response.data['stickers'] ?? [];
      
      final stickers = stickersJson.map((json) => 
        StickerModel.fromJson(json, packId)
      ).toList();
      
      // Если пак установлен — скачиваем файлы
      if (await isPackInstalled(packId)) {
        await _downloadStickersFiles(packId, stickers);
      }
      
      _stickerCache[packId] = stickers;
      return stickers;
    } catch (e) {
      print('❌ Error getting pack stickers: $e');
      return [];
    }
  }
  
  Future<void> _downloadStickersFiles(String packId, List<StickerModel> stickers) async {
    final packDir = Directory(path.join(_stickersDir!, packId));
    await packDir.create(recursive: true);
    
    for (var sticker in stickers) {
      if (sticker.url != null && sticker.localPath == null) {
        final fileName = path.basename(sticker.url!);
        final targetPath = File(path.join(packDir.path, fileName));
        
        if (!await targetPath.exists()) {
          try {
            final response = await _dio.download(
              'http://45.132.255.167:8080${sticker.url}',
              targetPath.path,
              options: Options(
                headers: await ApiService().getHeaders(),
              ),
            );
            
            if (response.statusCode == 200) {
              sticker.localPath = targetPath.path;
              print('  💾 Downloaded: $fileName');
            }
          } catch (e) {
            print('  ❌ Failed to download ${sticker.url}: $e');
          }
        } else {
          sticker.localPath = targetPath.path;
        }
      }
    }
  }
  
  Future<bool> installPack(StickerPackModel pack) async {
    try {
      print('📥 Installing pack: ${pack.name}');
      
      final stickers = await getPackStickers(pack.id, forceRefresh: true);
      if (stickers.isEmpty) {
        print('❌ No stickers in pack');
        return false;
      }
      
      final packDir = Directory(path.join(_stickersDir!, pack.id));
      await packDir.create(recursive: true);
      
      int downloaded = 0;
      for (var sticker in stickers) {
        if (sticker.url != null) {
          final success = await _downloadSticker(sticker, packDir.path);
          if (success) downloaded++;
        }
      }
      
      print('✅ Downloaded $downloaded/${stickers.length} stickers');
      
      final packToSave = pack.copyWith(isInstalled: true);
      await _savePackMetadata(packToSave);
      
      _packCache[pack.id] = packToSave;
      _stickerCache[pack.id] = await _getLocalStickers(pack.id);
      
      try {
        await ApiService().dio.post('/stickers/install', data: {
          'pack_id': pack.id,
          'install': true,
        });
      } catch (e) {
        print('⚠️ Server install notification failed: $e');
      }
      
      _notifyChange();
      
      return downloaded > 0;
    } catch (e) {
      print('❌ Error installing pack: $e');
      return false;
    }
  }
  
  Future<StickerPackModel?> createPack({
    required String name,
    int? plannedCount,
    List<File>? stickerFiles,
    int coverStickerIndex = 0,
  }) async {
    try {
      print('📤 Creating pack: $name, coverIndex: $coverStickerIndex');
      
      FormData formData = FormData.fromMap({
        'name': name,
        if (plannedCount != null) 'planned_count': plannedCount.toString(),
        'cover_sticker_index': coverStickerIndex.toString(),
      });
      
      if (stickerFiles != null && stickerFiles.isNotEmpty) {
        for (int i = 0; i < stickerFiles.length; i++) {
          formData.files.add(MapEntry(
            'sticker_$i',
            await MultipartFile.fromFile(
              stickerFiles[i].path,
              filename: path.basename(stickerFiles[i].path),
            ),
          ));
        }
      }
      
      final response = await ApiService().dio.post(
        '/stickers/packs',
        data: formData,
      );
      
      final packId = response.data['pack_id'];
      final added = response.data['stickers_added'] ?? 0;
      final coverUrl = response.data['cover_url'];
      
      print('✅ Created pack: $packId with $added stickers, cover: $coverUrl');
      
      final pack = StickerPackModel(
        id: packId,
        name: name,
        author: 'me',
        isOfficial: false,
        stickerCount: added,
        isMine: true,
        plannedCount: plannedCount,
        cover: coverUrl,
        isInstalled: true,
      );
      
      _packCache[packId] = pack;
      
      if (added > 0) {
        await _downloadPackFiles(pack);
      }
      
      _notifyChange();
      
      return pack;
    } catch (e) {
      print('❌ Error creating pack: $e');
      return null;
    }
  }

  Future<void> _downloadPackFiles(StickerPackModel pack) async {
    try {
      final stickers = await getPackStickers(pack.id, forceRefresh: true);
      final packDir = Directory(path.join(_stickersDir!, pack.id));
      await packDir.create(recursive: true);
      
      for (var sticker in stickers) {
        if (sticker.url != null) {
          await _downloadSticker(sticker, packDir.path);
        }
      }
      
      await _savePackMetadata(pack);
      _stickerCache[pack.id] = stickers;
    } catch (e) {
      print('❌ Error downloading pack files: $e');
    }
  }
  
  // === ИСПРАВЛЕННЫЙ МЕТОД: добавление стикеров ===
  Future<bool> addStickersToPack(String packId, List<File> stickerFiles) async {
    try {
      print('📤 Adding ${stickerFiles.length} stickers to pack $packId');
      
      if (stickerFiles.isEmpty) {
        print('⚠️ No files to add');
        return false;
      }
      
      FormData formData = FormData();
      
      for (int i = 0; i < stickerFiles.length; i++) {
        formData.files.add(MapEntry(
          'sticker_$i',
          await MultipartFile.fromFile(
            stickerFiles[i].path,
            filename: path.basename(stickerFiles[i].path),
          ),
        ));
      }
      
      final response = await ApiService().dio.post(
        '/stickers/pack/$packId/stickers',
        data: formData,
      );
      
      final added = response.data['added'] ?? 0;
      final total = response.data['total_stickers'] ?? 0;
      
      print('✅ Added $added stickers, total: $total');
      
      // === КЛЮЧЕВОЕ ИСПРАВЛЕНИЕ: Очищаем кэш и перезагружаем ===
      _stickerCache.remove(packId);
      
      // Обновляем количество в кэше пака
      if (_packCache.containsKey(packId)) {
        _packCache[packId] = _packCache[packId]!.copyWith(stickerCount: total);
      }
      
      // Перезагружаем стикеры с сервера (forceRefresh!)
      final freshStickers = await getPackStickers(packId, forceRefresh: true);
      print('🔄 Refreshed stickers: ${freshStickers.length} in cache');
      
      // Сохраняем новые файлы локально
      final packDir = Directory(path.join(_stickersDir!, packId));
      for (var sticker in freshStickers) {
        if (sticker.localPath == null && sticker.url != null) {
          await _downloadSticker(sticker, packDir.path);
        }
      }
      
      _notifyChange();
      
      return added > 0;
    } catch (e) {
      print('❌ Error adding stickers: $e');
      return false;
    }
  }
  
  Future<bool> deletePack(StickerPackModel pack) async {
    try {
      print('🗑️ Deleting pack: ${pack.name}');
      
      final packDir = Directory(path.join(_stickersDir!, pack.id));
      if (await packDir.exists()) {
        await packDir.delete(recursive: true);
      }
      
      await _removePackMetadata(pack.id);
      
      _stickerCache.remove(pack.id);
      _packCache.remove(pack.id);
      
      if (pack.isMine && !pack.isOfficial) {
        try {
          await ApiService().dio.delete('/stickers/pack/${pack.id}');
        } catch (e) {
          print('⚠️ Server delete error: $e');
        }
      }
      
      _notifyChange();
      
      print('✅ Pack deleted');
      return true;
    } catch (e) {
      print('❌ Error deleting pack: $e');
      return false;
    }
  }
  
  Future<bool> isPackInstalled(String packId) async {
    final packDir = Directory(path.join(_stickersDir!, packId));
    final metaFile = File(path.join(_stickersDir!, '$packId.json'));
    return await packDir.exists() && await metaFile.exists();
  }

  Future<String?> getStickerLocalPath(String packId, String fileName) async {
    final filePath = path.join(_stickersDir!, packId, fileName);
    final file = File(filePath);
    if (await file.exists()) {
      return filePath;
    }
    return null;
  }

  Future<bool> _downloadSticker(StickerModel sticker, String packDir) async {
    try {
      if (sticker.url == null) return false;
      
      final fileName = path.basename(sticker.url!);
      final filePath = path.join(packDir, fileName);
      final file = File(filePath);
      
      if (await file.exists()) {
        sticker.localPath = filePath;
        return true;
      }
      
      final response = await _dio.download(
        'http://45.132.255.167:8080${sticker.url}',
        filePath,
        options: Options(
          headers: await ApiService().getHeaders(),
        ),
      );
      
      if (response.statusCode == 200) {
        sticker.localPath = filePath;
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error downloading sticker ${sticker.id}: $e');
      return false;
    }
  }
  
  Future<List<StickerModel>> _getLocalStickers(String packId) async {
    final packDir = Directory(path.join(_stickersDir!, packId));
    if (!await packDir.exists()) return [];
    
    final files = await packDir.list().toList();
    final stickers = <StickerModel>[];
    
    for (var file in files) {
      if (file is File) {
        final ext = path.extension(file.path).toLowerCase();
        if (['.webp', '.png', '.jpg', '.jpeg', '.gif'].contains(ext)) {
          final fileName = path.basename(file.path);
          
          stickers.add(StickerModel(
            id: path.basenameWithoutExtension(file.path),
            packId: packId,
            fileName: fileName,
            localPath: file.path,
          ));
        }
      }
    }
    
    print('  📁 Found ${stickers.length} local files in $packId');
    return stickers;
  }
  
  Future<void> _savePackMetadata(StickerPackModel pack) async {
    final metaFile = File(path.join(_stickersDir!, '${pack.id}.json'));
    await metaFile.writeAsString(jsonEncode(pack.toJson()));
  }
  
  Future<void> _removePackMetadata(String packId) async {
    final metaFile = File(path.join(_stickersDir!, '$packId.json'));
    if (await metaFile.exists()) {
      await metaFile.delete();
    }
  }
  
  // === НОВЫЙ МЕТОД: принудительное обновление пака ===
  Future<void> refreshPack(String packId) async {
    _stickerCache.remove(packId);
    await getPackStickers(packId, forceRefresh: true);
    _notifyChange();
  }
  
  // === НОВЫЙ МЕТОД: получить стикер по ID ===
  Future<StickerModel?> getStickerById(String packId, String stickerId) async {
    final stickers = await getPackStickers(packId);
    try {
      return stickers.firstWhere((s) => s.id == stickerId);
    } catch (e) {
      return null;
    }
  }
  
  void dispose() {
    _changeController.close();
    super.dispose();
  }
}