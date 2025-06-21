import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'voice_memo_service.dart';
import 'dart:io';

class VoiceMemoPage extends StatefulWidget {
  const VoiceMemoPage({super.key});

  @override
  State<VoiceMemoPage> createState() => _VoiceMemoPageState();
}

class _VoiceMemoPageState extends State<VoiceMemoPage> {
  final VoiceMemoService _voiceMemoService = VoiceMemoService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  List<VoiceMemo> _voiceMemos = [];
  bool _isInitialized = false;
  String? _currentPlayingId;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initializeService();
    _setupAudioPlayer();
  }

  void _initializeService() async {
    final success = await _voiceMemoService.initialize();
    if (success) {
      setState(() {
        _isInitialized = true;
      });
      
      // コールバック設定
      _voiceMemoService.onVoiceMemoCreated = (voiceMemo) {
        setState(() {
          _voiceMemos.insert(0, voiceMemo);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('新しいボイスメモが作成されました')),
        );
      };
      
      _voiceMemoService.onRecordingStateChanged = (isRecording) {
        setState(() {});
      };
      
      _voiceMemoService.onError = (error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      };
      
      // 既存のボイスメモを読み込み
      _loadVoiceMemos();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ボイスメモサービスの初期化に失敗しました')),
      );
    }
  }

  void _setupAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      setState(() {
        _isPlaying = state == PlayerState.playing;
      });
    });

    _audioPlayer.onPositionChanged.listen((position) {
      setState(() {
        _currentPosition = position;
      });
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      setState(() {
        _totalDuration = duration;
      });
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      setState(() {
        _currentPlayingId = null;
        _isPlaying = false;
        _currentPosition = Duration.zero;
        _totalDuration = Duration.zero;
      });
    });
  }

  void _loadVoiceMemos() async {
    final voiceMemos = await _voiceMemoService.getVoiceMemos();
    setState(() {
      _voiceMemos = voiceMemos;
    });
  }

  void _toggleShakeDetection() async {
    if (_voiceMemoService.shakeDetectionEnabled) {
      await _voiceMemoService.stopShakeDetection();
    } else {
      await _voiceMemoService.startShakeDetection();
    }
    setState(() {});
  }

  void _startManualRecording() async {
    await _voiceMemoService.startRecording();
  }

  void _stopManualRecording() async {
    await _voiceMemoService.stopRecording();
  }

  void _playVoiceMemo(VoiceMemo voiceMemo) async {
    try {
      if (_currentPlayingId == voiceMemo.id && _isPlaying) {
        await _audioPlayer.pause();
      } else {
        if (_currentPlayingId != voiceMemo.id) {
          await _audioPlayer.stop();
          await _audioPlayer.play(DeviceFileSource(voiceMemo.filePath));
          setState(() {
            _currentPlayingId = voiceMemo.id;
          });
        } else {
          await _audioPlayer.resume();
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('再生エラー: $e')),
      );
    }
  }

  void _stopPlayback() async {
    await _audioPlayer.stop();
    setState(() {
      _currentPlayingId = null;
      _isPlaying = false;
      _currentPosition = Duration.zero;
      _totalDuration = Duration.zero;
    });
  }

  void _deleteVoiceMemo(VoiceMemo voiceMemo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ボイスメモを削除'),
        content: Text('「${voiceMemo.title}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (_currentPlayingId == voiceMemo.id) {
        _stopPlayback();
      }
      
      await _voiceMemoService.deleteVoiceMemo(voiceMemo);
      setState(() {
        _voiceMemos.removeWhere((memo) => memo.id == voiceMemo.id);
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ボイスメモを削除しました')),
      );
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: const Text('ボイスメモ'),
        ),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.web,
                size: 64,
                color: Colors.grey,
              ),
              SizedBox(height: 16),
              Text(
                'ボイスメモ機能はWebでは利用できません',
                style: TextStyle(fontSize: 18, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'モバイルアプリでご利用ください',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('ボイスメモ'),
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('ボイスメモ'),
        actions: [
          IconButton(
            icon: Icon(
              _voiceMemoService.shakeDetectionEnabled 
                ? Icons.vibration 
                : Icons.vibration_outlined
            ),
            onPressed: _toggleShakeDetection,
            tooltip: _voiceMemoService.shakeDetectionEnabled 
              ? '振動検知を停止' 
              : '振動検知を開始',
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('ボイスメモについて'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('ボイスメモ v1.0'),
                      const SizedBox(height: 8),
                      Text('メモ数: ${_voiceMemos.length}'),
                      const SizedBox(height: 8),
                      Text('振動検知: ${_voiceMemoService.shakeDetectionEnabled ? "有効" : "無効"}'),
                      Text('バックグラウンド: ${_voiceMemoService.isBackgroundServiceRunning ? "実行中" : "停止中"}'),
                      const SizedBox(height: 8),
                      const Text('使い方:'),
                      const Text('• 端末を振ると録音開始/停止'),
                      const Text('• 手動録音ボタンでも操作可能'),
                      const Text('• タップで再生/一時停止'),
                      const Text('• 長押しで削除'),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('閉じる'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // 録音コントロール
          Container(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                // 状態表示
                Container(
                  padding: const EdgeInsets.all(12.0),
                  decoration: BoxDecoration(
                    color: _voiceMemoService.isRecording 
                      ? Colors.red.withOpacity(0.1)
                      : (_voiceMemoService.shakeDetectionEnabled 
                        ? Colors.green.withOpacity(0.1)
                        : Colors.grey.withOpacity(0.1)),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(
                      color: _voiceMemoService.isRecording 
                        ? Colors.red.withOpacity(0.3)
                        : (_voiceMemoService.shakeDetectionEnabled 
                          ? Colors.green.withOpacity(0.3)
                          : Colors.grey.withOpacity(0.3)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _voiceMemoService.isRecording 
                          ? Icons.fiber_manual_record
                          : (_voiceMemoService.shakeDetectionEnabled 
                            ? Icons.vibration
                            : Icons.pause_circle_outline),
                        color: _voiceMemoService.isRecording 
                          ? Colors.red
                          : (_voiceMemoService.shakeDetectionEnabled 
                            ? Colors.green
                            : Colors.grey),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _voiceMemoService.isRecording 
                          ? '録音中...'
                          : (_voiceMemoService.shakeDetectionEnabled 
                            ? '振動検知待機中'
                            : '停止中'),
                        style: TextStyle(
                          color: _voiceMemoService.isRecording 
                            ? Colors.red
                            : (_voiceMemoService.shakeDetectionEnabled 
                              ? Colors.green
                              : Colors.grey),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 手動録音ボタン
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _voiceMemoService.isRecording 
                        ? _stopManualRecording 
                        : _startManualRecording,
                      icon: Icon(_voiceMemoService.isRecording ? Icons.stop : Icons.mic),
                      label: Text(_voiceMemoService.isRecording ? '録音停止' : '手動録音'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _voiceMemoService.isRecording ? Colors.red : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _toggleShakeDetection,
                      icon: Icon(_voiceMemoService.shakeDetectionEnabled 
                        ? Icons.vibration 
                        : Icons.vibration_outlined),
                      label: Text(_voiceMemoService.shakeDetectionEnabled 
                        ? '振動検知停止' 
                        : '振動検知開始'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _voiceMemoService.shakeDetectionEnabled 
                          ? Colors.orange 
                          : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(),
          // 再生コントロール（再生中のみ表示）
          if (_currentPlayingId != null)
            Container(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        onPressed: _stopPlayback,
                        icon: const Icon(Icons.stop),
                      ),
                      Expanded(
                        child: Slider(
                          value: _currentPosition.inMilliseconds.toDouble(),
                          max: _totalDuration.inMilliseconds.toDouble(),
                          onChanged: (value) async {
                            await _audioPlayer.seek(Duration(milliseconds: value.toInt()));
                          },
                        ),
                      ),
                      Text('${_formatDuration(_currentPosition)} / ${_formatDuration(_totalDuration)}'),
                    ],
                  ),
                ],
              ),
            ),
          // ボイスメモ一覧
          Expanded(
            child: _voiceMemos.isEmpty
                ? const Center(
                    child: Text(
                      'ボイスメモがありません\n端末を振るか手動録音ボタンで録音してください',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _voiceMemos.length,
                    itemBuilder: (context, index) {
                      final memo = _voiceMemos[index];
                      final isPlaying = _currentPlayingId == memo.id && _isPlaying;
                      final isCurrentMemo = _currentPlayingId == memo.id;
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 4.0,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isCurrentMemo 
                              ? (isPlaying ? Colors.green : Colors.orange)
                              : Colors.blue,
                            child: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                            ),
                          ),
                          title: Text(memo.title),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '作成日時: ${memo.createdAt.month}/${memo.createdAt.day} ${memo.createdAt.hour}:${memo.createdAt.minute.toString().padLeft(2, '0')}',
                                style: const TextStyle(fontSize: 12),
                              ),
                              Text(
                                '長さ: ${_formatDuration(memo.duration)}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () => _deleteVoiceMemo(memo),
                          ),
                          onTap: () => _playVoiceMemo(memo),
                          onLongPress: () => _deleteVoiceMemo(memo),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _voiceMemoService.dispose();
    super.dispose();
  }
}