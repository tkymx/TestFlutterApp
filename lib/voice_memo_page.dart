import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'unified_voice_service.dart';
import 'dart:io';
import 'dart:async';

class VoiceMemoPage extends StatefulWidget {
  const VoiceMemoPage({super.key});

  @override
  State<VoiceMemoPage> createState() => _VoiceMemoPageState();
}

class _VoiceMemoPageState extends State<VoiceMemoPage> {
  final UnifiedVoiceService _voiceService = UnifiedVoiceService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  
  List<VoiceMemo> _voiceMemos = [];
  bool _isInitialized = false;
  String? _currentPlayingId;
  bool _isPlaying = false;
  Duration _currentPosition = Duration.zero;
  Duration _totalDuration = Duration.zero;
  String _currentTranscription = '';
  String _currentStatus = '';
  double _soundLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _initializeService();
    _setupAudioPlayer();
  }

  void _initializeService() async {
    try {
      print('統合音声サービスの初期化を開始します...');
      
      bool success = await _voiceService.initialize();
      
      if (success) {
        print('統合音声サービスの初期化に成功しました');
        _setupServiceCallbacks();
      } else {
        print('統合音声サービスの初期化に失敗しました');
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

  void _setupServiceCallbacks() {
    _voiceService.onVoiceMemoCreated = (voiceMemo) {
      setState(() {
        _voiceMemos.insert(0, voiceMemo);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('新しいボイスメモが作成されました')),
        );
      }
    };
    
    _voiceService.onRecordingStateChanged = (isRecording) {
      if (mounted) {
        setState(() {});
      }
    };
    
    _voiceService.onError = (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error)),
        );
      }
    };
    
    _voiceService.onTranscriptionUpdated = (text) {
      if (mounted) {
        setState(() {
          _currentTranscription = text;
        });
      }
    };
    
    _voiceService.onStatusChanged = (status) {
      if (mounted) {
        setState(() {
          _currentStatus = status;
        });
      }
    };
    
    // 音声レベルの更新
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_voiceService.isContinuousListening || _voiceService.isRecording) {
        setState(() {
          _soundLevel = _voiceService.soundLevel;
        });
      }
    });
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
    List<VoiceMemo> voiceMemos = await _voiceService.getVoiceMemos();
    
    // ファイルの存在確認
    List<VoiceMemo> validatedMemos = [];
    List<VoiceMemo> invalidMemos = [];
    
    for (var memo in voiceMemos) {
      if (memo.filePath.isEmpty) {
        // ファイルパスが空の場合（書き起こしのみのメモ）
        validatedMemos.add(memo);
        continue;
      }
      
      try {
        final file = File(memo.filePath);
        final exists = await file.exists();
        
        if (exists) {
          // ファイルサイズの確認
          final fileSize = await file.length();
          if (fileSize > 0) {
            validatedMemos.add(memo);
          } else {
            print('警告: 空のファイル検出: ${memo.filePath}');
            // 書き起こしがある場合は保持
            if (memo.transcription != null && memo.transcription!.isNotEmpty) {
              validatedMemos.add(memo);
            } else {
              invalidMemos.add(memo);
            }
          }
        } else {
          print('警告: ファイルが見つかりません: ${memo.filePath}');
          // 書き起こしがある場合は保持
          if (memo.transcription != null && memo.transcription!.isNotEmpty) {
            validatedMemos.add(memo);
          } else {
            invalidMemos.add(memo);
          }
        }
      } catch (e) {
        print('ファイル確認エラー: ${memo.filePath} - $e');
        // エラーが発生した場合も、書き起こしがあれば保持
        if (memo.transcription != null && memo.transcription!.isNotEmpty) {
          validatedMemos.add(memo);
        } else {
          invalidMemos.add(memo);
        }
      }
    }
    
    // 無効なメモが見つかった場合、メタデータから削除
    if (invalidMemos.isNotEmpty) {
      print('無効なボイスメモを ${invalidMemos.length} 件検出しました');
      
      // 無効なメモをメタデータから削除
      for (var memo in invalidMemos) {
        await _voiceService.deleteVoiceMemo(memo);
      }
      
      // 無効なメモが多い場合のみ通知
      if (invalidMemos.length > 2 && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${invalidMemos.length}件の無効なボイスメモを削除しました'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
    
    setState(() {
      _voiceMemos = validatedMemos;
    });
  }

  void _startManualRecording() async {
    await _voiceService.startRecording();
  }

  void _stopManualRecording() async {
    await _voiceService.stopRecording();
  }

  void _startContinuousListening() async {
    await _voiceService.startContinuousListening();
  }

  void _stopContinuousListening() async {
    await _voiceService.stopListening();
    // 連続音声認識で認識されたテキストからボイスメモを作成
    await _createManualVoiceMemo();
  }

  Future<void> _createManualVoiceMemo() async {
    final voiceMemo = await _voiceService.createManualVoiceMemo();
    if (voiceMemo != null) {
      setState(() {
        _voiceMemos.insert(0, voiceMemo);
      });
    }
  }

  void _pauseContinuousListening() async {
    await _voiceService.pauseListening();
  }

  void _resumeContinuousListening() async {
    await _voiceService.resumeListening();
  }

  void _playVoiceMemo(VoiceMemo voiceMemo) async {
    try {
      // ファイルの存在確認
      if (voiceMemo.filePath.isNotEmpty) {
        final file = File(voiceMemo.filePath);
        final exists = await file.exists();
        
        if (!exists) {
          // ファイルが存在しない場合、ユーザーに通知して削除オプションを提供
          _showFileNotFoundDialog(voiceMemo);
          return;
        }
        
        // ファイルサイズの確認
        final fileSize = await file.length();
        if (fileSize <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('再生できません: 音声ファイルが空です')),
          );
          return;
        }
        
        print('再生開始: ${voiceMemo.filePath} (サイズ: ${fileSize}バイト)');
      } else if (voiceMemo.transcription == null || voiceMemo.transcription!.isEmpty) {
        // ファイルパスが空で、書き起こしもない場合はエラー
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('再生できません: 音声ファイルが見つかりません')),
        );
        return;
      } else {
        // ファイルパスが空だが書き起こしがある場合（Manual音声メモ）
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('このメモは音声ファイルがありません。書き起こしテキストのみです。')),
        );
        return;
      }
      
      if (_currentPlayingId == voiceMemo.id && _isPlaying) {
        await _audioPlayer.pause();
      } else {
        if (_currentPlayingId != voiceMemo.id) {
          await _audioPlayer.stop();
          
          // 音声ファイルがある場合のみ再生
          if (voiceMemo.filePath.isNotEmpty) {
            // 再生前にファイルの読み取り権限を確認
            try {
              await _audioPlayer.play(DeviceFileSource(voiceMemo.filePath));
              setState(() {
                _currentPlayingId = voiceMemo.id;
                // 録音中でない場合は、現在の書き起こしテキストをリセット
                if (!_voiceService.isRecording && !_voiceService.isContinuousListening) {
                  _currentTranscription = '';
                }
              });
              
              // 再生成功の通知
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('再生開始: ${voiceMemo.title}'),
                  duration: const Duration(seconds: 1),
                ),
              );
            } catch (playError) {
              print('音声ファイル再生エラー: $playError');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('音声ファイルの再生に失敗しました: $playError')),
              );
            }
          }
        } else {
          await _audioPlayer.resume();
        }
      }
    } catch (e) {
      print('再生エラー詳細: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('再生エラー: $e')),
      );
    }
  }
  
  // ファイルが見つからない場合のダイアログ
  void _showFileNotFoundDialog(VoiceMemo voiceMemo) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('音声ファイルが見つかりません'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('「${voiceMemo.title}」の音声ファイルが見つかりませんでした。'),
            const SizedBox(height: 8),
            const Text('ファイルが削除されたか、移動された可能性があります。'),
            if (voiceMemo.transcription != null && voiceMemo.transcription!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: const Text('※書き起こしテキストは保存されています'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteVoiceMemo(voiceMemo);
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
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
      if (!_voiceService.isRecording && !_voiceService.isContinuousListening) {
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
      
      await _voiceService.deleteVoiceMemo(voiceMemo);
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
                    color: _getRecordingState() != '停止中'
                      ? Colors.red.withOpacity(0.1)
                      : Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(
                      color: _getRecordingState() != '停止中'
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
                            _getRecordingState() != '停止中'
                              ? Icons.fiber_manual_record
                              : Icons.pause_circle_outline,
                            color: _getRecordingState() != '停止中'
                              ? Colors.red
                              : Colors.grey,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Column(
                            children: [
                              Text(
                                _getRecordingState(),
                                style: TextStyle(
                                  color: _getRecordingState() != '停止中'
                                    ? Colors.red
                                    : Colors.grey,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (_currentStatus.isNotEmpty)
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
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              '統合版',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // 録音中の書き起こしテキスト表示
                      if ((_voiceService.isRecording || _voiceService.isContinuousListening) && _currentTranscription.isNotEmpty)
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
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 通常の録音ボタン
                    ElevatedButton.icon(
                      onPressed: _voiceService.isRecording
                        ? _stopManualRecording
                        : _startManualRecording,
                      icon: Icon(_voiceService.isRecording ? Icons.stop : Icons.mic),
                      label: Text(_voiceService.isRecording ? '録音停止' : '録音開始'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _voiceService.isRecording ? Colors.red : Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                    // 連続音声認識ボタン
                    ElevatedButton.icon(
                      onPressed: _voiceService.isContinuousListening
                        ? _stopContinuousListening
                        : _startContinuousListening,
                      icon: Icon(_voiceService.isContinuousListening ? Icons.stop : Icons.hearing),
                      label: Text(_voiceService.isContinuousListening ? '認識停止' : '連続認識'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _voiceService.isContinuousListening ? Colors.red : Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      ),
                    ),
                  ],
                ),
                // 一時停止/再開ボタン（連続音声認識中のみ表示）
                if (_voiceService.isContinuousListening) ...[
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: _voiceService.isPaused ? _resumeContinuousListening : _pauseContinuousListening,
                    icon: Icon(_voiceService.isPaused ? Icons.play_arrow : Icons.pause),
                    label: Text(_voiceService.isPaused ? '再開' : '一時停止'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _voiceService.isPaused ? Colors.blue : Colors.orange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
                // 音声レベル表示
                if (_voiceService.isContinuousListening || _voiceService.isRecording) ...[
                  const SizedBox(height: 12),
                  Column(
                    children: [
                      const Text('音声レベル', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 4),
                      LinearProgressIndicator(
                        value: _soundLevel,
                        backgroundColor: Colors.grey[300],
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _soundLevel > 0.5 ? Colors.green : Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ],
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
                      
                      // 音声ファイルの有無を確認
                      final hasAudioFile = memo.filePath.isNotEmpty;
                      final hasTranscription = memo.transcription != null && memo.transcription!.isNotEmpty;
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 4.0,
                        ),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isCurrentMemo 
                              ? (isPlaying ? Colors.green : Colors.orange)
                              : hasAudioFile ? Colors.blue : Colors.grey,
                            child: Icon(
                              hasAudioFile 
                                ? (isPlaying ? Icons.pause : Icons.play_arrow)
                                : Icons.text_snippet,
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
                              if (hasAudioFile)
                                Text(
                                  '長さ: ${_formatDuration(memo.duration)}',
                                  style: const TextStyle(fontSize: 12),
                                )
                              else
                                const Text(
                                  '長さ: 00:00',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              // メモの種類を表示
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Row(
                                  children: [
                                    Icon(
                                      hasAudioFile ? Icons.audiotrack : Icons.text_snippet, 
                                      size: 12, 
                                      color: Colors.grey
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      hasAudioFile 
                                        ? (hasTranscription ? '書き起こしあり' : '音声のみ')
                                        : '書き起こしのみ',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
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
                              if (hasTranscription)
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
                          onTap: () {
                            if (hasAudioFile) {
                              _playVoiceMemo(memo);
                            } else if (hasTranscription) {
                              _showTranscriptionDialog(memo);
                            }
                          },
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

  String _getRecordingState() {
    if (_voiceService.isRecording) {
      return '録音中...';
    } else if (_voiceService.isContinuousListening) {
      if (_voiceService.isPaused) {
        return '一時停止中';
      } else {
        return '連続音声認識中...';
      }
    } else {
      return '停止中';
    }
  }

  bool _isCurrentlyRecording() {
    return _voiceService.isRecording || _voiceService.isContinuousListening;
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _voiceService.dispose();
    super.dispose();
  }
}