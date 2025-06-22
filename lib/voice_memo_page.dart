import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'voice_memo_service.dart';
import 'enhanced_voice_service.dart';
import 'dart:io';

class VoiceMemoPage extends StatefulWidget {
  const VoiceMemoPage({super.key});

  @override
  State<VoiceMemoPage> createState() => _VoiceMemoPageState();
}

class _VoiceMemoPageState extends State<VoiceMemoPage> {
  final VoiceMemoService _voiceMemoService = VoiceMemoService();
  final EnhancedVoiceService _enhancedVoiceService = EnhancedVoiceService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  List<VoiceMemo> _voiceMemos = [];
  bool _isInitialized = false;
  String? _currentPlayingId;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  String _currentTranscription = '';
  String _currentStatus = '';
  bool _useEnhancedService = false;

  @override
  void initState() {
    super.initState();
    _initializeService();
    _setupAudioPlayer();
  }

  void _initializeService() async {
    try {
      // 拡張サービスの初期化を試行
      bool enhancedSuccess = await _enhancedVoiceService.initialize();
      
      if (enhancedSuccess) {
        print('拡張音声サービスの初期化に成功しました');
        _useEnhancedService = true;
        _setupEnhancedServiceCallbacks();
      } else {
        print('拡張音声サービスの初期化に失敗しました。標準サービスを使用します。');
        // 標準サービスの初期化
        bool standardSuccess = await _voiceMemoService.initialize();
        if (standardSuccess) {
          _setupStandardServiceCallbacks();
        }
      }
      
      setState(() {
        _isInitialized = true;
      });
      
      // 既存のボイスメモを読み込み
      _loadVoiceMemos();
      
    } catch (e) {
      print('サービス初期化中の例外: $e');
      
      setState(() {
        _isInitialized = true;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('初期化エラー: $e'),
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  void _setupEnhancedServiceCallbacks() {
    _enhancedVoiceService.onVoiceMemoCreated = (voiceMemo) {
      setState(() {
        _voiceMemos.insert(0, voiceMemo);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('新しいボイスメモが作成されました（拡張版）')),
        );
      }
    };
    
    _enhancedVoiceService.onRecordingStateChanged = (isRecording) {
      if (mounted) {
        setState(() {});
      }
    };
    
    _enhancedVoiceService.onError = (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    };
    
    _enhancedVoiceService.onTranscriptionUpdated = (text) {
      if (mounted) {
        setState(() {
          _currentTranscription = text;
        });
      }
    };
    
    _enhancedVoiceService.onStatusChanged = (status) {
      if (mounted) {
        setState(() {
          _currentStatus = status;
        });
      }
    };
  }

  void _setupStandardServiceCallbacks() {
    _voiceMemoService.onVoiceMemoCreated = (voiceMemo) {
      setState(() {
        _voiceMemos.insert(0, voiceMemo);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('新しいボイスメモが作成されました')),
        );
      }
    };
    
    _voiceMemoService.onRecordingStateChanged = (isRecording) {
      if (mounted) {
        setState(() {});
      }
    };
    
    _voiceMemoService.onError = (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    };
    
    _voiceMemoService.onTranscriptionUpdated = (text) {
      if (mounted) {
        setState(() {
          _currentTranscription = text;
        });
      }
    };
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
    List<VoiceMemo> voiceMemos;
    if (_useEnhancedService) {
      voiceMemos = await _enhancedVoiceService.getVoiceMemos();
    } else {
      voiceMemos = await _voiceMemoService.getVoiceMemos();
    }
    setState(() {
      _voiceMemos = voiceMemos;
    });
  }



  void _startManualRecording() async {
    if (_useEnhancedService) {
      await _enhancedVoiceService.startRecording();
    } else {
      await _voiceMemoService.startRecording();
    }
  }

  void _stopManualRecording() async {
    if (_useEnhancedService) {
      await _enhancedVoiceService.stopRecording();
    } else {
      await _voiceMemoService.stopRecording();
    }
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
            // 録音中でない場合は、現在の書き起こしテキストをリセット
            bool isRecording = _useEnhancedService ? 
              _enhancedVoiceService.isRecording : 
              _voiceMemoService.isRecording;
            if (!isRecording) {
              _currentTranscription = '';
            }
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
  
  // 書き起こしテキストを表示するダイアログを表示
  void _showTranscriptionDialog(VoiceMemo voiceMemo) {
    if (voiceMemo.transcription == null || voiceMemo.transcription!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('書き起こしテキストがありません')),
      );
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(voiceMemo.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '書き起こしテキスト:',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.grey.withOpacity(0.3)),
              ),
              child: SelectableText(
                voiceMemo.transcription!,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              // テキストをクリップボードにコピー
              Clipboard.setData(ClipboardData(text: voiceMemo.transcription!));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('テキストをコピーしました')),
              );
            },
            child: const Text('コピー'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }

  void _stopPlayback() async {
    await _audioPlayer.stop();
    setState(() {
      _currentPlayingId = null;
      _isPlaying = false;
      _currentPosition = Duration.zero;
      _totalDuration = Duration.zero;
      // 録音中でない場合は、現在の書き起こしテキストをリセット
      bool isRecording = _useEnhancedService ? 
        _enhancedVoiceService.isRecording : 
        _voiceMemoService.isRecording;
      if (!isRecording) {
        _currentTranscription = '';
      }
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
      
      if (_useEnhancedService) {
        await _enhancedVoiceService.deleteVoiceMemo(voiceMemo);
      } else {
        await _voiceMemoService.deleteVoiceMemo(voiceMemo);
      }
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
                      const Text('使い方:'),
                      const Text('• 録音ボタンで録音開始/停止'),
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
                    color: (_useEnhancedService ? _enhancedVoiceService.isRecording : _voiceMemoService.isRecording)
                      ? Colors.red.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(
                      color: (_useEnhancedService ? _enhancedVoiceService.isRecording : _voiceMemoService.isRecording)
                        ? Colors.red.withOpacity(0.3)
                        : Colors.grey.withOpacity(0.3),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            (_useEnhancedService ? _enhancedVoiceService.isRecording : _voiceMemoService.isRecording)
                              ? Icons.fiber_manual_record
                              : Icons.pause_circle_outline,
                            color: (_useEnhancedService ? _enhancedVoiceService.isRecording : _voiceMemoService.isRecording)
                              ? Colors.red
                              : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            children: [
                              Text(
                                (_useEnhancedService ? _enhancedVoiceService.isRecording : _voiceMemoService.isRecording)
                                  ? '録音中...'
                                  : '停止中',
                                style: TextStyle(
                                  color: (_useEnhancedService ? _enhancedVoiceService.isRecording : _voiceMemoService.isRecording)
                                    ? Colors.red
                                    : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_useEnhancedService && _currentStatus.isNotEmpty)
                                Text(
                                  _currentStatus,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(width: 8),
                          if (_useEnhancedService)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '拡張版',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.blue,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                      // 録音中の書き起こしテキスト表示
                      if ((_useEnhancedService ? _enhancedVoiceService.isRecording : _voiceMemoService.isRecording) && _currentTranscription.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Container(
                            padding: const EdgeInsets.all(8.0),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(4.0),
                              border: Border.all(color: Colors.grey.withOpacity(0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  '書き起こし:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _currentTranscription,
                                  style: const TextStyle(fontSize: 14),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // 録音ボタン
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      onPressed: (_useEnhancedService ? _enhancedVoiceService.isRecording : _voiceMemoService.isRecording)
                        ? _stopManualRecording 
                        : _startManualRecording,
                      icon: Icon((_useEnhancedService ? _enhancedVoiceService.isRecording : _voiceMemoService.isRecording) ? Icons.stop : Icons.mic),
                      label: Text((_useEnhancedService ? _enhancedVoiceService.isRecording : _voiceMemoService.isRecording) ? '録音停止' : '録音開始'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: (_useEnhancedService ? _enhancedVoiceService.isRecording : _voiceMemoService.isRecording) ? Colors.red : (_useEnhancedService ? Colors.green : Colors.blue),
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
                              // 書き起こしの有無を表示
                              if (memo.transcription != null && memo.transcription!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.text_snippet, size: 12, color: Colors.grey),
                                      const SizedBox(width: 4),
                                      const Text(
                                        '書き起こしあり',
                                        style: TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 書き起こしがある場合は表示ボタンを追加
                              if (memo.transcription != null && memo.transcription!.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.text_snippet, color: Colors.blue),
                                  tooltip: '書き起こしを表示',
                                  onPressed: () => _showTranscriptionDialog(memo),
                                ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.red),
                                onPressed: () => _deleteVoiceMemo(memo),
                              ),
                            ],
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