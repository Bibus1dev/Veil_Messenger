import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../data/models/sticker_pack_model.dart';
import '../../services/sticker_service.dart';

class StickerStoreSheet extends StatefulWidget {
  final VoidCallback onPackInstalled;
  
  const StickerStoreSheet({
    super.key,
    required this.onPackInstalled,
  });

  @override
  State<StickerStoreSheet> createState() => _StickerStoreSheetState();
}

class _StickerStoreSheetState extends State<StickerStoreSheet> 
    with SingleTickerProviderStateMixin {
  final StickerService _stickerService = StickerService();
  List<StickerPackModel> _allPacks = [];
  List<StickerPackModel> _officialPacks = [];
  List<StickerPackModel> _communityPacks = [];
  List<StickerPackModel> _myPacks = [];
  bool _isLoading = true;
  
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // === НОВОЕ: Подписываемся на изменения StickerService ===
    _stickerService.addListener(_onStickerServiceChanged);
    
    _loadPacks();
  }

  @override
  void dispose() {
    // === НОВОЕ: Отписываемся при уничтожении ===
    _stickerService.removeListener(_onStickerServiceChanged);
    _tabController.dispose();
    super.dispose();
  }

  // === НОВЫЙ МЕТОД: Обработчик изменений StickerService ===
  void _onStickerServiceChanged() {
    if (mounted) {
      print('🔄 StickerStoreSheet: service changed, reloading...');
      _loadPacks();
    }
  }

  Future<void> _loadPacks() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);
    
    try {
      final packs = await _stickerService.getStickerPacks();
      
      if (!mounted) return;
      
      setState(() {
        _allPacks = packs;
        _officialPacks = packs.where((p) => p.isOfficial).toList();
        _communityPacks = packs.where((p) => !p.isOfficial && !p.isMine).toList();
        _myPacks = packs.where((p) => p.isMine).toList();
        _isLoading = false;
      });
    } catch (e) {
      print('❌ Error loading packs: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Sticker Store',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showCreateDialog,
                icon: const Icon(Icons.add),
                label: const Text('Create My Pack'),
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: 'Official'),
              Tab(text: 'Community'),
              Tab(text: 'My Packs'),
            ],
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey,
            indicatorColor: Theme.of(context).colorScheme.primary,
          ),
          
          const Divider(height: 1),
          
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPackList(_officialPacks, 'No official packs yet'),
                      _buildPackList(_communityPacks, 'No community packs yet'),
                      _buildPackList(_myPacks, 'You have no packs. Create one!'),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPackList(List<StickerPackModel> packs, String emptyMessage) {
    if (packs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.emoji_emotions_outlined, 
              size: 48, 
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: TextStyle(color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadPacks,
      child: ListView.builder(
        padding: const EdgeInsets.all(8),
        itemCount: packs.length,
        itemBuilder: (context, index) => _buildPackCard(packs[index]),
      ),
    );
  }

  Widget _buildPackCard(StickerPackModel pack) {
    final isInstalled = pack.isInstalled;
    
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: InkWell(
        onTap: () => _showPackDetails(pack),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.grey.shade100,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: _buildPackPreview(pack),
                ),
              ),
              
              const SizedBox(width: 12),
              
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            pack.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (pack.isOfficial)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'OFFICIAL',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.blue.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (pack.isMine)
                          Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.shade100,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'MY',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green.shade800,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${pack.stickerCount} stickers',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    if (pack.plannedCount != null && pack.plannedCount! > pack.stickerCount)
                      Text(
                        '${pack.plannedCount! - pack.stickerCount} more coming',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade600,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                  ],
                ),
              ),
              
              const SizedBox(width: 8),
              if (isInstalled)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check,
                    color: Colors.green.shade600,
                    size: 20,
                  ),
                )
              else
                ElevatedButton(
                  onPressed: () => _installPack(pack),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(80, 36),
                  ),
                  child: const Text('Add'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPackPreview(StickerPackModel pack) {
    if (pack.cover != null && pack.cover!.isNotEmpty) {
      final coverUrl = pack.cover!.startsWith('http') 
          ? pack.cover!
          : 'http://45.132.255.167:8080${pack.cover}';
      
      return Image.network(
        coverUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFirstStickerPreview(pack),
      );
    }
    
    return _buildFirstStickerPreview(pack);
  }

  Widget _buildFirstStickerPreview(StickerPackModel pack) {
    return FutureBuilder<List<StickerModel>>(
      future: _stickerService.getPackStickers(pack.id),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data!.isNotEmpty) {
          final firstSticker = snapshot.data!.first;
          
          if (firstSticker.localPath != null) {
            return Image.file(
              File(firstSticker.localPath!),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildDefaultPreview(pack),
            );
          }
          
          if (firstSticker.url != null) {
            final url = firstSticker.url!.startsWith('http')
                ? firstSticker.url!
                : 'http://45.132.255.167:8080${firstSticker.url}';
            
            return Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildDefaultPreview(pack),
            );
          }
        }
        
        return _buildDefaultPreview(pack);
      },
    );
  }

  Widget _buildDefaultPreview(StickerPackModel pack) {
    return Center(
      child: Text(
        pack.name[0].toUpperCase(),
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Future<void> _installPack(StickerPackModel pack) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Downloading...', style: TextStyle(color: Colors.white)),
          ],
        ),
      ),
    );

    final success = await _stickerService.installPack(pack);

    if (mounted) {
      Navigator.pop(context);
      
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${pack.name} installed!')),
        );
        widget.onPackInstalled();
        // === НОВОЕ: Не нужно вызывать _loadPacks() — сервис уведомит сам ===
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to install pack'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showPackDetails(StickerPackModel pack) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                pack.name,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                '${pack.stickerCount} stickers',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: FutureBuilder<List<StickerModel>>(
                  future: _stickerService.getPackStickers(pack.id),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    
                    final stickers = snapshot.data!;
                    return GridView.builder(
                      controller: controller,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        childAspectRatio: 1,
                      ),
                      itemCount: stickers.length,
                      itemBuilder: (context, index) {
                        return Container(
                          margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            color: Colors.grey.shade100,
                          ),
                          child: stickers[index].localPath != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(
                                    File(stickers[index].localPath!),
                                    fit: BoxFit.contain,
                                  ),
                                )
                              : stickers[index].url != null
                                  ? Image.network(
                                      'http://45.132.255.167:8080${stickers[index].url}',
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => 
                                        const Center(child: Icon(Icons.emoji_emotions)),
                                    )
                                  : const Center(child: Icon(Icons.emoji_emotions)),
                        );
                      },
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: pack.isInstalled
                      ? null
                      : () {
                          Navigator.pop(context);
                          _installPack(pack);
                        },
                  child: Text(pack.isInstalled ? 'Installed' : 'Add to My Stickers'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showCreateDialog() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => _CreatePackDialog(
        onCreated: () {
          // === НОВОЕ: Не нужно вызывать _loadPacks() — сервис уведомит сам ===
          widget.onPackInstalled();
        },
      ),
    );
  }
}

class _CreatePackDialog extends StatefulWidget {
  final VoidCallback onCreated;
  
  const _CreatePackDialog({required this.onCreated});

  @override
  State<_CreatePackDialog> createState() => _CreatePackDialogState();
}

class _CreatePackDialogState extends State<_CreatePackDialog> {
  final _nameController = TextEditingController();
  final _countController = TextEditingController();
  final List<File> _selectedImages = [];
  final StickerService _stickerService = StickerService();
  bool _isCreating = false;
  int? _selectedCoverIndex;

  @override
  void dispose() {
    _nameController.dispose();
    _countController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Create Sticker Pack',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Pack Name',
                hintText: 'My Awesome Stickers',
                prefixIcon: Icon(Icons.edit),
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _countController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Planned Count (optional)',
                hintText: 'How many stickers you plan to add',
                prefixIcon: Icon(Icons.format_list_numbered),
              ),
            ),
            const SizedBox(height: 20),
            
            if (_selectedImages.isNotEmpty) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Selected Images (${_selectedImages.length}):',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (_selectedImages.length > 1)
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          _selectedCoverIndex = null;
                        });
                      },
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Reset cover'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectedImages.length,
                  itemBuilder: (context, index) {
                    final isCover = _selectedCoverIndex == index;
                    
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedCoverIndex = index;
                        });
                      },
                      child: Stack(
                        children: [
                          Container(
                            width: 100,
                            height: 100,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: isCover
                                  ? Border.all(
                                      color: Theme.of(context).colorScheme.primary,
                                      width: 3,
                                    )
                                  : null,
                              image: DecorationImage(
                                image: FileImage(_selectedImages[index]),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          if (isCover)
                            Positioned(
                              top: 4,
                              left: 4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.photo,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      'COVER',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          Positioned(
                            top: 4,
                            right: 12,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _selectedImages.removeAt(index);
                                  if (_selectedCoverIndex == index) {
                                    _selectedCoverIndex = null;
                                  } else if (_selectedCoverIndex != null && 
                                             _selectedCoverIndex! > index) {
                                    _selectedCoverIndex = _selectedCoverIndex! - 1;
                                  }
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 16,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            bottom: 4,
                            left: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '#${index + 1}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
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
              if (_selectedImages.length > 1) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, 
                        color: Colors.blue.shade700, 
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _selectedCoverIndex == null
                              ? 'Tap on any image to set it as pack cover'
                              : 'Image #${_selectedCoverIndex! + 1} will be used as cover',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
            ],
            
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _pickImages,
                icon: const Icon(Icons.add_photo_alternate),
                label: Text(_selectedImages.isEmpty
                    ? 'Select Stickers'
                    : 'Add More Stickers'),
              ),
            ),
            const SizedBox(height: 20),
            
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isCreating || _nameController.text.isEmpty
                    ? null
                    : _createPack,
                child: _isCreating
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create Pack'),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage();
    
    if (picked.isNotEmpty) {
      setState(() {
        _selectedImages.addAll(picked.map((x) => File(x.path)));
        if (_selectedCoverIndex == null && _selectedImages.length == picked.length) {
          _selectedCoverIndex = 0;
        }
      });
    }
  }

  Future<void> _createPack() async {
    setState(() => _isCreating = true);
    
    final plannedCount = int.tryParse(_countController.text);
    
    final pack = await _stickerService.createPack(
      name: _nameController.text.trim(),
      plannedCount: plannedCount,
      stickerFiles: _selectedImages.isEmpty ? null : _selectedImages,
      coverStickerIndex: _selectedCoverIndex ?? 0,
    );
    
    setState(() => _isCreating = false);
    
    if (pack != null && mounted) {
      Navigator.pop(context);
      widget.onCreated();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${pack.name}" created!')),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to create pack'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}