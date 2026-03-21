import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../services/media_service.dart';

class VideoNotePreviewSheet extends StatefulWidget {
  final VideoNoteResult result;
  final VoidCallback onSend;
  final VoidCallback onCancel;

  const VideoNotePreviewSheet({
    super.key,
    required this.result,
    required this.onSend,
    required this.onCancel,
  });

  @override
  State<VideoNotePreviewSheet> createState() => _VideoNotePreviewSheetState();
}

class _VideoNotePreviewSheetState extends State<VideoNotePreviewSheet> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    _controller = VideoPlayerController.file(File(widget.result.filePath));
    await _controller!.initialize();
    await _controller!.setLooping(true);
    await _controller!.play();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Заголовок
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Video Note',
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: widget.onCancel,
                ),
              ],
            ),
          ),
          
          // Видео - fullscreen круг с размытием по краям
          Expanded(
            child: Center(
              child: ClipOval(
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.9,
                  height: MediaQuery.of(context).size.width * 0.9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: _controller != null && _controller!.value.isInitialized
                      ? FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: _controller!.value.size.width,
                            height: _controller!.value.size.height,
                            child: VideoPlayer(_controller!),
                          ),
                        )
                      : const CircularProgressIndicator(color: Colors.white),
                ),
              ),
            ),
          ),
          
          // Длительность
          Text(
            '${widget.result.duration} sec',
            style: const TextStyle(color: Colors.white70, fontSize: 16),
          ),
          
          const SizedBox(height: 24),
          
          // Кнопки
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Перезаписать
              TextButton.icon(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.refresh, color: Colors.white, size: 28),
                label: const Text(
                  'Retake', 
                  style: TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
              
              const SizedBox(width: 48),
              
              // Отправить
              ElevatedButton.icon(
                onPressed: widget.onSend,
                icon: const Icon(Icons.send, size: 28),
                label: const Text('Send', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}