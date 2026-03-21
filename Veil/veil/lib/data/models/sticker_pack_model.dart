// lib/data/models/sticker_pack_model.dart

class StickerPackModel {
  final String id;
  final String name;
  final String author;
  final bool isOfficial;
  final int stickerCount;
  final String? cover;
  final bool isInstalled;
  final bool isMine;
  final int? plannedCount;
  final int? createdAt;
  
  StickerPackModel({
    required this.id,
    required this.name,
    required this.author,
    required this.isOfficial,
    required this.stickerCount,
    this.cover,
    this.isInstalled = false,
    this.isMine = false,
    this.plannedCount,
    this.createdAt,
  });
  
  factory StickerPackModel.fromJson(Map<String, dynamic> json) {
    return StickerPackModel(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      author: json['author'] ?? '',
      isOfficial: json['is_official'] ?? false,
      stickerCount: json['sticker_count'] ?? 0,
      cover: json['cover'],
      isInstalled: json['installed'] ?? false,
      isMine: json['is_mine'] ?? false,
      plannedCount: json['planned_count'],
      createdAt: json['created_at'],
    );
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'author': author,
    'is_official': isOfficial,
    'sticker_count': stickerCount,
    'cover': cover,
    'installed': isInstalled,
    'is_mine': isMine,
    'planned_count': plannedCount,
    'created_at': createdAt,
  };
  
  StickerPackModel copyWith({
    String? id,
    String? name,
    String? author,
    bool? isOfficial,
    int? stickerCount,
    String? cover,
    bool? isInstalled,
    bool? isMine,
    int? plannedCount,
    int? createdAt,
  }) {
    return StickerPackModel(
      id: id ?? this.id,
      name: name ?? this.name,
      author: author ?? this.author,
      isOfficial: isOfficial ?? this.isOfficial,
      stickerCount: stickerCount ?? this.stickerCount,
      cover: cover ?? this.cover,
      isInstalled: isInstalled ?? this.isInstalled,
      isMine: isMine ?? this.isMine,
      plannedCount: plannedCount ?? this.plannedCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class StickerModel {
  final String id;
  final String packId;
  final String fileName;
  final String? emoji;
  String? localPath;
  final String? url;
  
  StickerModel({
    required this.id,
    required this.packId,
    required this.fileName,
    this.emoji,
    this.localPath,
    this.url,
  });
  
  factory StickerModel.fromJson(Map<String, dynamic> json, String packId) {
    return StickerModel(
      id: json['id'] ?? '',
      packId: packId,
      fileName: json['file'] ?? json['file_name'] ?? '',
      emoji: json['emoji'],
      url: json['url'],
      localPath: json['local_path'],
    );
  }
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'pack_id': packId,
    'file_name': fileName,
    'emoji': emoji,
    'local_path': localPath,
    'url': url,
  };
  
  StickerModel copyWith({
    String? id,
    String? packId,
    String? fileName,
    String? emoji,
    String? localPath,
    String? url,
  }) {
    return StickerModel(
      id: id ?? this.id,
      packId: packId ?? this.packId,
      fileName: fileName ?? this.fileName,
      emoji: emoji ?? this.emoji,
      localPath: localPath ?? this.localPath,
      url: url ?? this.url,
    );
  }
}