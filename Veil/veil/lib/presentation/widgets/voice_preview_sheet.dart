import 'dart:io';
import 'package:flutter/material.dart';
import 'package:audio_waveforms/audio_waveforms.dart';
import '../../../services/media_service.dart';

class VoicePreviewSheet extends StatefulWidget {
  final VoiceRecordingResult recording;
  final Function(int? trimStart, int? trimEnd) onSend;
  final VoidCallback onCancel;

  const VoicePreviewSheet({
    super.key,
    required this.recording,
    required this.onSend,
    required this.onCancel,
  });

  @override
  State<VoicePreviewSheet> createState() => _VoicePreviewSheetState();
}

class _VoicePreviewSheetState extends State<VoicePreviewSheet> {
  PlayerController? _playerController;
  bool _isPlaying = false;
  int _currentPosition = 0;
  int _totalDuration = 0;
  bool _isLoadingWaveform = true;
  List<double> _waveformData = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    _totalDuration = widget.recording.duration ?? 0;
    
    // Используем waveform из записи если есть (реальные данные!)
    if (widget.recording.waveform != null && widget.recording.waveform!.isNotEmpty) {
      print('🎵 Using real waveform from recording: ${widget.recording.waveform!.length} points');
      setState(() {
        _waveformData = widget.recording.waveform!;
        _isLoadingWaveform = false;
      });
    } else {
      // Если нет - извлекаем из файла
      print('🎵 Extracting waveform from file...');
      await _extractWaveformFromFile();
    }

    // Инициализируем плеер
    _playerController = PlayerController();
    await _playerController!.preparePlayer(
      path: widget.recording.filePath,
      shouldExtractWaveform: false, // Уже извлекли выше
    );

    // Слушаем позицию воспроизведения
    _playerController!.onCurrentDurationChanged.listen((ms) {
      if (mounted) {
        setState(() => _currentPosition = ms ~/ 1000);
      }
    });

    _playerController!.onCompletion.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _currentPosition = 0;
        });
      }
    });
  }

  Future<void> _extractWaveformFromFile() async {
    try {
      final waveform = await MediaService().extractWaveformFromFile(widget.recording.filePath);
      if (mounted) {
        setState(() {
          _waveformData = waveform;
          _isLoadingWaveform = false;
        });
        print('🎵 Extracted ${waveform.length} points from file');
      }
    } catch (e) {
      print('❌ Error extracting waveform: $e');
      if (mounted) {
        setState(() => _isLoadingWaveform = false);
      }
    }
  }

  Future<void> _togglePlay() async {
    if (_playerController == null) return;
    
    if (_isPlaying) {
      await _playerController!.pausePlayer();
      setState(() => _isPlaying = false);
    } else {
      // Если дошли до конца - начинаем сначала
      if (_currentPosition >= _totalDuration - 1) {
        await _playerController!.seekTo(0);
      }
      await _playerController!.startPlayer();
      setState(() => _isPlaying = true);
    }
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _playerController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 400,
      decoration: BoxDecoration(
        color: Colors.grey.shade900,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                  'Voice Message', 
                  style: TextStyle(color: Colors.white, fontSize: 18),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white), 
                  onPressed: widget.onCancel,
                ),
              ],
            ),
          ),
          
          const Spacer(),
          
          // === РЕАЛЬНЫЙ WAVEFORM ===
          Container(
            height: 100,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _isLoadingWaveform
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _waveformData.isEmpty
                    ? Center(
                        child: Container(
                          width: double.infinity, 
                          height: 2, 
                          color: Colors.white24,
                        ),
                      )
                    : AudioFileWaveforms(
                        size: Size(MediaQuery.of(context).size.width - 48, 100),
                        playerController: _playerController!,
                        enableSeekGesture: true,
                        waveformType: WaveformType.fitWidth,
                        waveformData: _waveformData,
                        playerWaveStyle: const PlayerWaveStyle(
                          fixedWaveColor: Colors.white24,
                          liveWaveColor: Colors.blue,
                          spacing: 4,
                          waveThickness: 3,
                          showSeekLine: true,
                          seekLineColor: Colors.white,
                          seekLineThickness: 2,
                        ),
                      ),
          ),
          
          const SizedBox(height: 16),
          
          // Время
          Text(
            '${_formatDuration(_currentPosition)} / ${_formatDuration(_totalDuration)}',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          
          const Spacer(),
          
          // Кнопки управления
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Play/Pause
              GestureDetector(
                onTap: _togglePlay,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: Colors.blue, 
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isPlaying ? Icons.pause : Icons.play_arrow, 
                    color: Colors.white, 
                    size: 36,
                  ),
                ),
              ),
              
              const SizedBox(width: 32),
              
              // Delete
              IconButton(
                onPressed: widget.onCancel, 
                icon: const Icon(Icons.delete, color: Colors.red), 
                iconSize: 32,
              ),
              
              const SizedBox(width: 16),
              
              // Send
              ElevatedButton.icon(
                onPressed: () => widget.onSend(null, null),
                icon: const Icon(Icons.send),
                label: const Text('Send'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  backgroundColor: Colors.green,
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