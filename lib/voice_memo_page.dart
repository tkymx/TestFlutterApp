import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'unified_voice_service.dart';
import 'dart:io';

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
  
  // 録音状態管理
  bool _isRecordingInProgress = false;

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
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
      
      // 既存のボイスメモを読み込み
      _loadVoiceMemos();
      
    } catch (e) {
      print('サービス初期化中の例外: $e');
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        
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
      if (mounted) {
        setState(() {
          _voiceMemos.insert(0, voiceMemo);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('新しいボイスメモが作成されました')),
        );
      }
    };

    _voiceService.onVoiceMemoUpdated = (voiceMemo) {
      if (mounted) {
        setState(() {
          // 既存のメモを更新
          int index = _voiceMemos.indexWhere((memo) => memo.id == voiceMemo.id);
          if (index != -1) {
            _voiceMemos[index] = voiceMemo;
          }
        });
        if (voiceMemo.status == VoiceMemoStatus.completed && 
            voiceMemo.transcription != null && 
            voiceMemo.transcription!.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文字起こしが完了しました')),
          );
        }
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
  }

  void _setupAudioPlayer() {
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
        });
      }
    });

    _audioPlayer.onPositionChanged.listen((position) {
      if (mounted) {
        setState(() {
          _currentPosition = position;
        });
      }
    });

    _audioPlayer.onDurationChanged.listen((duration) {
      if (mounted) {
        setState(() {
          _totalDuration = duration;
        });
      }
    });

    _audioPlayer.onPlayerComplete.listen((event) {
      if (mounted) {
        setState(() {
          _currentPlayingId = null;
          _isPlaying = false;
          _currentPosition = Duration.zero;
          _totalDuration = Duration.zero;
        });
      }
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
    
    if (mounted) {
      setState(() {
        _voiceMemos = validatedMemos;
      });
    }
  }

  void _startMenuRecording() async {
    if (_isRecordingInProgress) return;
    
    setState(() {
      _isRecordingInProgress = true;
    });
    
    await _voiceService.startVoiceMemoRecording();
  }

  void _stopMenuRecording() async {
    if (!_isRecordingInProgress) return;
    
    setState(() {
      _isRecordingInProgress = false;
    });
    
    await _voiceService.stopVoiceMemoRecording();
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
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('再生できません: 音声ファイルが空です')),
            );
          }
          return;
        }
        
        print('再生開始: ${voiceMemo.filePath} (サイズ: ${fileSize}バイト)');
      } else if (voiceMemo.transcription == null || voiceMemo.transcription!.isEmpty) {
        // ファイルパスが空で、書き起こしもない場合はエラー
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('再生できません: 音声ファイルが見つかりません')),
          );
        }
        return;
      } else {
        // ファイルパスが空だが書き起こしがある場合（Manual音声メモ）
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('このメモは音声ファイルがありません。書き起こしテキストのみです。')),
          );
        }
        return;
      }
      
      if (_currentPlayingId == voiceMemo.id && _isPlaying) {
        await _audioPlayer.pause();
      } else {
        if (_currentPlayingId != voiceMemo.id) {
          await _audioPlayer.stop();
          
          // 音声ファイルがある場合のみ再生
          if (voiceMemo.filePath.isNotEmpty) {
            try {
              await _audioPlayer.play(DeviceFileSource(voiceMemo.filePath));
              if (mounted) {
                setState(() {
                  _currentPlayingId = voiceMemo.id;
                });
                
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('再生開始: ${voiceMemo.title}'),
                    duration: const Duration(seconds: 1),
                  ),
                );
              }
            } catch (playError) {
              print('音声ファイル再生エラー: $playError');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('音声ファイルの再生に失敗しました: $playError')),
                );
              }
            }
          }
        } else {
          await _audioPlayer.resume();
        }
      }
    } catch (e) {
      print('再生エラー詳細: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('再生エラー: $e')),
        );
      }
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
      if (mounted) {
        setState(() {
          _voiceMemos.removeWhere((memo) => memo.id == voiceMemo.id);
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ボイスメモを削除しました')),
        );
      }
    }
  }

  void _stopPlayback() async {
    await _audioPlayer.stop();
    if (mounted) {
      setState(() {
        _currentPlayingId = null;
        _isPlaying = false;
        _currentPosition = Duration.zero;
        _totalDuration = Duration.zero;
      });
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
                            backgroundColor: memo.status == VoiceMemoStatus.processing
                              ? Colors.orange
                              : isCurrentMemo 
                                ? (isPlaying ? Colors.green : Colors.orange)
                                : hasAudioFile ? Colors.blue : Colors.grey,
                            child: memo.status == VoiceMemoStatus.processing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Icon(
                                  hasAudioFile 
                                    ? (isPlaying ? Icons.pause : Icons.play_arrow)
                                    : Icons.text_snippet,
                                  color: Colors.white,
                                ),
                          ),
                          title: Text(
                            memo.status == VoiceMemoStatus.processing
                              ? '文字起こし中...'
                              : memo.title,
                            style: TextStyle(
                              color: memo.status == VoiceMemoStatus.processing
                                ? Colors.orange[700]
                                : null,
                            ),
                          ),
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
                              // 書き起こしテキストのプレビュー表示
                              if (hasTranscription && memo.status != VoiceMemoStatus.processing)
                                Padding(
                                  padding: const EdgeInsets.only(top: 6.0),
                                  child: Container(
                                    padding: const EdgeInsets.all(8.0),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.withOpacity(0.05),
                                      borderRadius: BorderRadius.circular(4.0),
                                      border: Border.all(color: Colors.blue.withOpacity(0.2)),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.transcribe,
                                              size: 12,
                                              color: Colors.blue,
                                            ),
                                            const SizedBox(width: 4),
                                            const Text(
                                              '書き起こし:',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          memo.transcription!.length > 80 
                                            ? '${memo.transcription!.substring(0, 80)}...'
                                            : memo.transcription!,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Colors.black87,
                                            height: 1.3,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              // メモの種類を表示
                              Padding(
                                padding: const EdgeInsets.only(top: 4.0),
                                child: Row(
                                  children: [
                                    Icon(
                                      memo.status == VoiceMemoStatus.processing
                                        ? Icons.hourglass_empty
                                        : hasAudioFile ? Icons.audiotrack : Icons.text_snippet, 
                                      size: 12, 
                                      color: memo.status == VoiceMemoStatus.processing
                                        ? Colors.orange
                                        : Colors.grey
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      memo.status == VoiceMemoStatus.processing
                                        ? '処理中...'
                                        : hasAudioFile 
                                          ? (hasTranscription ? '音声+書き起こし' : '音声のみ')
                                          : '書き起こしのみ',
                                      style: TextStyle(
                                        fontSize: 12, 
                                        color: memo.status == VoiceMemoStatus.processing
                                          ? Colors.orange[700]
                                          : Colors.grey
                                      ),
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
                              if (hasTranscription && memo.status != VoiceMemoStatus.processing)
                                IconButton(
                                  icon: const Icon(Icons.text_snippet, color: Colors.blue),
                                  tooltip: '書き起こしを表示',
                                  onPressed: () => _showTranscriptionDialog(memo),
                                ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete, 
                                  color: memo.status == VoiceMemoStatus.processing 
                                    ? Colors.grey 
                                    : Colors.red
                                ),
                                onPressed: memo.status == VoiceMemoStatus.processing 
                                  ? null 
                                  : () => _deleteVoiceMemo(memo),
                              ),
                            ],
                          ),
                          onTap: memo.status == VoiceMemoStatus.processing
                            ? null
                            : () {
                                if (hasAudioFile) {
                                  _playVoiceMemo(memo);
                                } else if (hasTranscription) {
                                  _showTranscriptionDialog(memo);
                                }
                              },
                          onLongPress: memo.status == VoiceMemoStatus.processing 
                            ? null 
                            : () => _deleteVoiceMemo(memo),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      // 右下の録音ボタン
      floatingActionButton: _buildFloatingActionButton(),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildFloatingActionButton() {
    if (_isRecordingInProgress) {
      // 録音中は停止と取り消しボタンを表示
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 取り消しボタン
          FloatingActionButton(
            heroTag: "cancel",
            onPressed: () async {
              await _voiceService.stopVoiceMemoRecording();
              setState(() {
                _isRecordingInProgress = false;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('録音を取り消しました')),
              );
            },
            backgroundColor: Colors.red,
            child: const Icon(Icons.cancel, color: Colors.white),
          ),
          const SizedBox(height: 16),
          // 停止ボタン
          FloatingActionButton(
            heroTag: "stop",
            onPressed: _stopMenuRecording,
            backgroundColor: Colors.orange,
            child: const Icon(Icons.stop, color: Colors.white),
          ),
        ],
      );
    } else {
      // 通常時は録音ボタンのみ表示
      return FloatingActionButton(
        heroTag: "record",
        onPressed: _startMenuRecording,
        backgroundColor: Colors.blue,
        child: const Icon(Icons.mic, color: Colors.white),
      );
    }
  }
  @override
  void dispose() {
    _audioPlayer.dispose();
    _voiceService.dispose();
    super.dispose();
  }

  // 書き起こしテキストを表示するダイアログ（録音後の書き起こし表示用）
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
        content: SingleChildScrollView(
          child: Text(voiceMemo.transcription!),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('閉じる'),
          ),
        ],
      ),
    );
  }
}