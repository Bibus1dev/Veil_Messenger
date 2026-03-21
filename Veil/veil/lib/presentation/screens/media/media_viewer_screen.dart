import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../../data/models/message_model.dart';

class MediaViewerScreen extends StatefulWidget {
  final List<MessageModel> messages; // Все сообщения альбома
  final int initialIndex; // С какого фото начинаем
  final String encryptionKey;

  const MediaViewerScreen({
    super.key,
    required this.messages,
    required this.initialIndex,
    required this.encryptionKey,
  });

  @override
  State<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<MediaViewerScreen> {
  late PageController _pageController;
  late int _currentIndex;
  final Map<int, VideoPlayerController> _videoControllers = {};
  final Map<int, bool> _showControlsMap = {};
  Timer? _controlsTimer;
  bool _isUIVisible = true;
  double _dragStartY = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    
    // Инициализируем видео для текущей страницы и соседних
    _preloadVideos();
    
    // Скрываем системный UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _preloadVideos() {
    // Инициализируем текущее и соседние видео
    for (int i = _currentIndex - 1; i <= _currentIndex + 1; i++) {
      if (i >= 0 && i < widget.messages.length) {
        _initVideoIfNeeded(i);
      }
    }
  }

  Future<void> _initVideoIfNeeded(int index) async {
    final msg = widget.messages[index];
    if (!msg.isVideo || msg.localPath == null) return;
    if (_videoControllers.containsKey(index)) return;

    try {
      final controller = VideoPlayerController.file(File(msg.localPath!));
      await controller.initialize();
      controller.setLooping(false);
      
      if (mounted) {
        setState(() {
          _videoControllers[index] = controller;
          _showControlsMap[index] = true;
        });
        
        controller.addListener(() {
          if (mounted) setState(() {});
        });
      }
    } catch (e) {
      print('❌ Failed to init video $index: $e');
    }
  }

  void _disposeVideo(int index) {
    _videoControllers[index]?.removeListener(() {});
    _videoControllers[index]?.dispose();
    _videoControllers.remove(index);
    _showControlsMap.remove(index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _controlsTimer?.cancel();
    
    // Очищаем все контроллеры
    for (var controller in _videoControllers.values) {
      controller.dispose();
    }
    _videoControllers.clear();
    
    // Восстанавливаем системный UI
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
    
    // Пауза предыдущего видео
    if (_currentIndex > 0) {
      _videoControllers[_currentIndex - 1]?.pause();
    }
    if (_currentIndex < widget.messages.length - 1) {
      _videoControllers[_currentIndex + 1]?.pause();
    }
    
    // Предзагрузка соседних
    _preloadVideos();
    
    // Очистка дальних видео для экономии памяти
    for (int i = 0; i < widget.messages.length; i++) {
      if ((i - _currentIndex).abs() > 2) {
        _disposeVideo(i);
      }
    }
  }

  void _togglePlay(int index) {
    final controller = _videoControllers[index];
    if (controller == null) return;
    
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
        _hideControlsDelayed(index);
      }
    });
  }

  void _hideControlsDelayed(int index) {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _videoControllers[index]?.value.isPlaying == true) {
        setState(() => _showControlsMap[index] = false);
      }
    });
  }

  void _toggleControls(int index) {
    setState(() {
      _showControlsMap[index] = !(_showControlsMap[index] ?? true);
    });
    
    if (_showControlsMap[index] == true && _videoControllers[index]?.value.isPlaying == true) {
      _hideControlsDelayed(index);
    }
  }

  void _toggleUI() {
    setState(() => _isUIVisible = !_isUIVisible);
  }

  void _onVerticalDragStart(DragStartDetails details) {
    _dragStartY = details.globalPosition.dy;
    _isDragging = true;
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isDragging) return;
    
    final delta = details.globalPosition.dy - _dragStartY;
    if (delta > 100) {
      // Свайп вниз — закрыть
      Navigator.pop(context);
    }
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    _isDragging = false;
  }

  @override
  Widget build(BuildContext context) {
    final currentMsg = widget.messages[_currentIndex];
    final isVideo = currentMsg.isVideo;
    
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _toggleUI,
        onVerticalDragStart: _onVerticalDragStart,
        onVerticalDragUpdate: _onVerticalDragUpdate,
        onVerticalDragEnd: _onVerticalDragEnd,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // === PageView для листания ===
            PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemCount: widget.messages.length,
              physics: const BouncingScrollPhysics(),
              itemBuilder: (context, index) {
                final msg = widget.messages[index];
                final controller = _videoControllers[index];
                
                return GestureDetector(
                  onTap: msg.isVideo ? () => _toggleControls(index) : null,
                  child: Container(
                    color: Colors.black,
                    child: Center(
                      child: msg.isImage
                          ? InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 5.0,
                              boundaryMargin: const EdgeInsets.all(20),
                              child: Image.file(
                                File(msg.localPath!),
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => _buildErrorWidget(),
                              ),
                            )
                          : (controller != null && controller.value.isInitialized)
                              ? AspectRatio(
                                  aspectRatio: controller.value.aspectRatio,
                                  child: VideoPlayer(controller),
                                )
                              : _buildLoadingWidget(),
                    ),
                  ),
                );
              },
            ),
            
            // === Верхняя панель (AppBar) — ИСПРАВЛЕНО ===
            AnimatedOpacity(
              opacity: _isUIVisible ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: SafeArea(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.8),
                          Colors.black.withOpacity(0.4),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        // Кнопка назад
                        Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              child: const Icon(
                                Icons.arrow_back_ios_new,
                                color: Colors.white,
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                        
                        const SizedBox(width: 8),
                        
                        // Индикатор страницы
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${_currentIndex + 1} / ${widget.messages.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        
                        const Spacer(),
                        
                        // Имя файла (только для видео)
                        if (isVideo && currentMsg.fileName != null)
                          Expanded(
                            child: Text(
                              currentMsg.fileName!,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        
                        const Spacer(),
                        
                        // Меню действий
                        Material(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          child: PopupMenuButton<String>(
                            icon: const Icon(
                              Icons.more_vert,
                              color: Colors.white,
                              size: 24,
                            ),
                            color: Colors.grey.shade900,
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: 'share',
                                child: Row(
                                  children: [
                                    const Icon(Icons.share, color: Colors.white, size: 20),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Share',
                                      style: TextStyle(color: Colors.grey.shade100),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'save',
                                child: Row(
                                  children: [
                                    const Icon(Icons.download, color: Colors.white, size: 20),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Save to gallery',
                                      style: TextStyle(color: Colors.grey.shade100),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuItem(
                                value: 'info',
                                child: Row(
                                  children: [
                                    const Icon(Icons.info_outline, color: Colors.white, size: 20),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Details',
                                      style: TextStyle(color: Colors.grey.shade100),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            
            // === Индикатор свайпа вниз ===
            AnimatedOpacity(
              opacity: _isDragging ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 150),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.keyboard_arrow_down,
                        color: Colors.white,
                        size: 32,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Release to close',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // === Контролы видео ===
            if (isVideo && _videoControllers[_currentIndex]?.value.isInitialized == true)
              AnimatedOpacity(
                opacity: (_showControlsMap[_currentIndex] ?? true) && _isUIVisible ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Полупрозрачный фон
                    Container(
                      color: Colors.black26,
                    ),
                    
                    // Кнопка Play/Pause по центру
                    Center(
                      child: GestureDetector(
                        onTap: () => _togglePlay(_currentIndex),
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.95),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 20,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: Icon(
                            _videoControllers[_currentIndex]!.value.isPlaying
                                ? Icons.pause
                                : Icons.play_arrow,
                            size: 48,
                            color: Colors.black,
                          ),
                        ),
                      ),
                    ),
                    
                    // Нижняя панель с прогрессом
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: SafeArea(
                        child: Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withOpacity(0.9),
                                Colors.black.withOpacity(0.6),
                                Colors.transparent,
                              ],
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Прогресс бар
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: VideoProgressIndicator(
                                  _videoControllers[_currentIndex]!,
                                  allowScrubbing: true,
                                  colors: const VideoProgressColors(
                                    playedColor: Colors.white,
                                    bufferedColor: Colors.white54,
                                    backgroundColor: Colors.white24,
                                  ),
                                  padding: EdgeInsets.zero,
                                ),
                              ),
                              
                              const SizedBox(height: 12),
                              
                              // Время и кнопки
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  // Текущее время
                                  Text(
                                    _formatDuration(_videoControllers[_currentIndex]!.value.position),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  
                                  // Кнопки управления
                                  Row(
                                    children: [
                                      // Назад 10 сек
                                      IconButton(
                                        icon: const Icon(
                                          Icons.replay_10,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                        onPressed: () {
                                          final newPos = _videoControllers[_currentIndex]!.value.position - const Duration(seconds: 10);
                                          _videoControllers[_currentIndex]!.seekTo(newPos > Duration.zero ? newPos : Duration.zero);
                                        },
                                      ),
                                      
                                      const SizedBox(width: 8),
                                      
                                      // Play/Pause
                                      GestureDetector(
                                        onTap: () => _togglePlay(_currentIndex),
                                        child: Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                            _videoControllers[_currentIndex]!.value.isPlaying
                                                ? Icons.pause
                                                : Icons.play_arrow,
                                            color: Colors.white,
                                            size: 32,
                                          ),
                                        ),
                                      ),
                                      
                                      const SizedBox(width: 8),
                                      
                                      // Вперёд 10 сек
                                      IconButton(
                                        icon: const Icon(
                                          Icons.forward_10,
                                          color: Colors.white,
                                          size: 28,
                                        ),
                                        onPressed: () {
                                          final controller = _videoControllers[_currentIndex]!;
                                          final newPos = controller.value.position + const Duration(seconds: 10);
                                          final duration = controller.value.duration;
                                          controller.seekTo(newPos < duration ? newPos : duration);
                                        },
                                      ),
                                    ],
                                  ),
                                  
                                  // Общее время
                                  Text(
                                    _formatDuration(_videoControllers[_currentIndex]!.value.duration),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            
            // === Индикатор загрузки ===
            if (isVideo && _videoControllers[_currentIndex] == null)
              const Center(
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingWidget() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(
            color: Colors.white,
            strokeWidth: 3,
          ),
          SizedBox(height: 16),
          Text(
            'Loading...',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline,
            color: Colors.red,
            size: 48,
          ),
          const SizedBox(height: 12),
          const Text(
            'Failed to load media',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              // Retry
            },
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final mins = duration.inMinutes.toString().padLeft(2, '0');
    final secs = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }
}