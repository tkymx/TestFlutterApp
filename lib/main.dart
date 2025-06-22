import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'voice_memo_page.dart';

// 音声認識の停止モード
enum SpeechStopMode {
  gradual,   // 段階入力（一定時間後に自動停止）
  manual,    // 手動入力（手動で停止ボタンを押す必要がある）
  unlimited  // 無制限（非常に長い時間自動停止しない）
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '音声アプリ',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 2,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          elevation: 4,
        ),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          centerTitle: true,
          elevation: 2,
        ),
        cardTheme: CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          elevation: 4,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const MainPage(),
    );
  }
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  
  final List<Widget> _pages = [
    const TaskListPage(title: '音声タスクリスト'),
    const VoiceMemoPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.task_alt),
            label: 'タスクリスト',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mic),
            label: 'ボイスメモ',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
      ),
    );
  }
}

class Task {
  String id;
  String content;
  bool isCompleted;
  DateTime createdAt;

  Task({
    required this.id,
    required this.content,
    this.isCompleted = false,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'content': content,
      'isCompleted': isCompleted,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Task.fromJson(Map<String, dynamic> json) {
    return Task(
      id: json['id'],
      content: json['content'],
      isCompleted: json['isCompleted'],
      createdAt: DateTime.parse(json['createdAt']),
    );
  }
}

class TaskListPage extends StatefulWidget {
  const TaskListPage({super.key, required this.title});

  final String title;

  @override
  State<TaskListPage> createState() => _TaskListPageState();
}

class _TaskListPageState extends State<TaskListPage> {
  final SpeechToText _speechToText = SpeechToText();
  final TextEditingController _textController = TextEditingController();
  
  List<Task> _tasks = [];
  bool _speechEnabled = false;
  bool _speechListening = false;
  String _lastWords = '';
  
  // 音声認識の停止モード設定
  SpeechStopMode _speechStopMode = SpeechStopMode.gradual;
  
  // 各モードの設定値
  final Map<SpeechStopMode, Duration> _pauseForDurations = {
    SpeechStopMode.gradual: const Duration(seconds: 10),       // 段階入力: 10秒
    SpeechStopMode.manual: const Duration(seconds: 0),         // 手動入力: 自動停止なし
    SpeechStopMode.unlimited: const Duration(hours: 1),        // 無制限: 1時間（事実上無制限）
  };
  
  // 自動再開機能の設定
  bool _autoRestart = false;

  @override
  void initState() {
    super.initState();
    _loadSpeechSettings();
    _initSpeech();
    _loadTasks();
  }
  
  // 音声認識設定の読み込み
  Future<void> _loadSpeechSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final stopModeIndex = prefs.getInt('speech_stop_mode') ?? SpeechStopMode.gradual.index;
    final autoRestart = prefs.getBool('speech_auto_restart') ?? false;
    setState(() {
      _speechStopMode = SpeechStopMode.values[stopModeIndex];
      _autoRestart = autoRestart;
    });
  }
  
  // 音声認識設定の保存
  Future<void> _saveSpeechSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('speech_stop_mode', _speechStopMode.index);
    await prefs.setBool('speech_auto_restart', _autoRestart);
  }

  void _initSpeech() async {
    // Webプラットフォームでは音声入力を無効にする
    if (kIsWeb) {
      _speechEnabled = false;
      setState(() {});
      return;
    }

    try {
      // マイクの権限をリクエスト
      var status = await Permission.microphone.request();
      if (status != PermissionStatus.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('マイクの権限が必要です')),
          );
        }
        return;
      }

      // 音声認識の初期化
      _speechEnabled = await _speechToText.initialize(
        onError: (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('音声認識エラー: ${error.errorMsg}')),
            );
          }
        },
        onStatus: (status) {
          print('音声認識ステータス変更: $status');
          if (status == 'notListening' && _speechListening) {
            // 音声認識が自動的に停止した場合
            setState(() {
              _speechListening = false;
            });
            
            // 無制限モードまたは手動モードで自動再開が有効な場合は再開する
            if (mounted && (_speechStopMode == SpeechStopMode.unlimited || 
                (_speechStopMode == SpeechStopMode.manual && _autoRestart))) {
              print('音声認識を自動的に再開します');
              // 少し遅延を入れてから再開
              Future.delayed(const Duration(milliseconds: 500), () {
                if (mounted) {
                  _startListening();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('音声認識を自動的に再開しました'),
                      duration: Duration(seconds: 1),
                    ),
                  );
                }
              });
            }
          }
        },
      );
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('音声認識の初期化に失敗しました: $e')),
        );
      }
    }
  }

  void _startListening() async {
    try {
      // 選択された停止モードに基づいてpauseForを設定
      final pauseFor = _pauseForDurations[_speechStopMode]!;
      
      // 手動モードの場合はpauseForを無効にする特別な処理
      final effectivePauseFor = _speechStopMode == SpeechStopMode.manual ? null : pauseFor;
      
      // listenForの時間を設定（無制限モードの場合は非常に長い時間に設定）
      final listenFor = _speechStopMode == SpeechStopMode.unlimited 
          ? const Duration(hours: 1)  // 1時間（事実上無制限）
          : const Duration(seconds: 60);  // 通常モード
      
      print('音声認識開始: モード=${_speechStopMode.toString()}, pauseFor=${effectivePauseFor?.inSeconds ?? "null"}秒, listenFor=${listenFor.inSeconds}秒');
      
      await _speechToText.listen(
        onResult: _onSpeechResult,
        listenFor: listenFor,
        pauseFor: effectivePauseFor,
        localeId: 'ja_JP',
        listenOptions: SpeechListenOptions(
          partialResults: true,
          cancelOnError: true,
          listenMode: ListenMode.dictation,
        ),
      );
      setState(() {
        _speechListening = true;
      });
      
      // モードに応じたユーザー通知
      if (mounted) {
        String message = '';
        switch (_speechStopMode) {
          case SpeechStopMode.gradual:
            message = '段階入力モード: 10秒間話さないと自動停止します';
            break;
          case SpeechStopMode.manual:
            message = '手動入力モード: 停止ボタンを押して終了してください';
            break;
          case SpeechStopMode.unlimited:
            message = '無制限モード: 非常に長い間隔で自動停止します';
            break;
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('音声認識の開始に失敗しました: $e')),
        );
      }
    }
  }

  void _stopListening() async {
    try {
      await _speechToText.stop();
      setState(() {
        _speechListening = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('音声認識の停止に失敗しました: $e')),
        );
      }
    }
  }

  void _onSpeechResult(result) {
    setState(() {
      _lastWords = result.recognizedWords;
      _textController.text = _lastWords;
    });
  }

  void _addTask() {
    if (_textController.text.trim().isEmpty) return;

    final newTask = Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: _textController.text.trim(),
      createdAt: DateTime.now(),
    );

    setState(() {
      _tasks.insert(0, newTask);
      _textController.clear();
      _lastWords = '';
    });

    _saveTasks();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('タスクを追加しました')),
    );
  }

  void _toggleTask(int index) {
    setState(() {
      _tasks[index].isCompleted = !_tasks[index].isCompleted;
    });
    _saveTasks();
  }

  void _deleteTask(int index) {
    final task = _tasks[index];
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('タスクを削除'),
        content: Text('「${task.content}」を削除しますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _tasks.removeAt(index);
              });
              _saveTasks();
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('タスクを削除しました')),
              );
            },
            child: const Text('削除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _saveTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final tasksJson = _tasks.map((task) => task.toJson()).toList();
    await prefs.setString('tasks', jsonEncode(tasksJson));
  }

  void _loadTasks() async {
    final prefs = await SharedPreferences.getInstance();
    final tasksString = prefs.getString('tasks');
    if (tasksString != null) {
      final tasksJson = jsonDecode(tasksString) as List;
      setState(() {
        _tasks = tasksJson.map((json) => Task.fromJson(json)).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
        actions: [
          // 音声認識設定ボタン
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '音声認識設定',
            onPressed: _showSpeechSettingsDialog,
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('アプリについて'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('音声タスクリスト v1.0'),
                      const SizedBox(height: 8),
                      Text('タスク数: ${_tasks.length}'),
                      Text('完了済み: ${_tasks.where((t) => t.isCompleted).length}'),
                      const SizedBox(height: 8),
                      Text('音声認識: ${_speechEnabled ? "有効" : "無効"}'),
                      Text('停止モード: ${_getSpeechStopModeText()}'),
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
          // 音声入力エリア
          Container(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _textController,
                  decoration: InputDecoration(
                    hintText: kIsWeb ? 'タスクを入力してください' : 'タスクを入力するか音声入力ボタンをタップ',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.task_alt),
                    suffixIcon: _textController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _textController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                  ),
                  maxLines: 2,
                  onChanged: (value) {
                    setState(() {});
                  },
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      _addTask();
                    }
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 音声入力ボタン（Webでは無効）
                    if (!kIsWeb)
                      ElevatedButton.icon(
                        onPressed: _speechEnabled
                            ? (_speechListening ? _stopListening : _startListening)
                            : null,
                        icon: Icon(_speechListening ? Icons.mic : (_speechEnabled ? Icons.mic_none : Icons.mic_off)),
                        label: Text(_speechListening 
                            ? '録音停止' 
                            : (_speechEnabled ? '音声入力' : '音声認識無効')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _speechListening 
                              ? Colors.red 
                              : (_speechEnabled ? Colors.blue : Colors.grey),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        ),
                      ),
                    // 追加ボタン
                    ElevatedButton.icon(
                      onPressed: _addTask,
                      icon: const Icon(Icons.add),
                      label: const Text('追加'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      ),
                    ),
                  ],
                ),
                if (_speechListening && !kIsWeb)
                  Container(
                    margin: const EdgeInsets.only(top: 16.0),
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: Colors.red.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8.0),
                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.mic, color: Colors.red, size: 20),
                        SizedBox(width: 8),
                        Text(
                          '音声を認識中...',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                        SizedBox(width: 8),
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const Divider(),
          // タスクリスト
          Expanded(
            child: _tasks.isEmpty
                ? _buildEmptyMessage()
                  
                : ListView.builder(
                    padding: const EdgeInsets.all(8.0),
                    itemCount: _tasks.length,
                    itemBuilder: (context, index) {
                      final task = _tasks[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: 8.0,
                          vertical: 4.0,
                        ),
                        child: Dismissible(
                          key: Key(task.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 20.0),
                            color: Colors.red,
                            child: const Icon(
                              Icons.delete,
                              color: Colors.white,
                            ),
                          ),
                          confirmDismiss: (direction) async {
                            return await showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('タスクを削除'),
                                content: Text('「${task.content}」を削除しますか？'),
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
                          },
                          onDismissed: (direction) {
                            setState(() {
                              _tasks.removeAt(index);
                            });
                            _saveTasks();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('「${task.content}」を削除しました'),
                                action: SnackBarAction(
                                  label: '元に戻す',
                                  onPressed: () {
                                    setState(() {
                                      _tasks.insert(index, task);
                                    });
                                    _saveTasks();
                                  },
                                ),
                              ),
                            );
                          },
                          child: ListTile(
                            leading: Checkbox(
                              value: task.isCompleted,
                              onChanged: (_) => _toggleTask(index),
                            ),
                            title: Text(
                              task.content,
                              style: TextStyle(
                                decoration: task.isCompleted
                                    ? TextDecoration.lineThrough
                                    : null,
                                color: task.isCompleted
                                    ? Colors.grey
                                    : null,
                              ),
                            ),
                            subtitle: Text(
                              '作成日時: ${task.createdAt.month}/${task.createdAt.day} ${task.createdAt.hour}:${task.createdAt.minute.toString().padLeft(2, '0')}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.swipe_left, color: Colors.grey, size: 16),
                                const SizedBox(width: 4),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _deleteTask(index),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: !kIsWeb && _speechEnabled
          ? FloatingActionButton(
              onPressed: _speechListening ? _stopListening : _startListening,
              backgroundColor: _speechListening ? Colors.red : Colors.blue,
              child: Icon(
                _speechListening ? Icons.stop : Icons.mic,
                color: Colors.white,
              ),
            )
          : null,
    );
  }

  // 空のメッセージを構築
  Widget _buildEmptyMessage() {
    if (kIsWeb) {
      return const Center(
        child: Text(
          'タスクがありません\nテキスト入力でタスクを追加してください',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    } else {
      return const Center(
        child: Text(
          'タスクがありません\n音声入力またはテキスト入力でタスクを追加してください',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }
  
  // 音声認識停止モードの設定ダイアログを表示
  void _showSpeechSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) {
        // ダイアログ内で一時的に使用する変数
        SpeechStopMode tempMode = _speechStopMode;
        bool tempAutoRestart = _autoRestart;
        
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('音声認識設定'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('停止モード:'),
                  const SizedBox(height: 8),
                  
                  // 段階入力オプション
                  RadioListTile<SpeechStopMode>(
                    title: const Text('段階入力'),
                    subtitle: const Text('10秒間話さないと自動停止'),
                    value: SpeechStopMode.gradual,
                    groupValue: tempMode,
                    onChanged: (value) {
                      setState(() {
                        tempMode = value!;
                      });
                    },
                  ),
                  
                  // 手動入力オプション
                  RadioListTile<SpeechStopMode>(
                    title: const Text('手動入力'),
                    subtitle: const Text('停止ボタンを押すまで継続'),
                    value: SpeechStopMode.manual,
                    groupValue: tempMode,
                    onChanged: (value) {
                      setState(() {
                        tempMode = value!;
                      });
                    },
                  ),
                  
                  // 無制限オプション
                  RadioListTile<SpeechStopMode>(
                    title: const Text('無制限'),
                    subtitle: const Text('非常に長い間隔（1時間）で自動停止'),
                    value: SpeechStopMode.unlimited,
                    groupValue: tempMode,
                    onChanged: (value) {
                      setState(() {
                        tempMode = value!;
                      });
                    },
                  ),
                  
                  const Divider(),
                  
                  // 自動再開オプション
                  CheckboxListTile(
                    title: const Text('自動再開'),
                    subtitle: const Text('音声認識が停止した場合に自動的に再開する'),
                    value: tempAutoRestart,
                    onChanged: (value) {
                      setState(() {
                        tempAutoRestart = value!;
                      });
                    },
                  ),
                  
                  // 注意書き
                  if (tempMode == SpeechStopMode.unlimited || tempAutoRestart)
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.yellow.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        '注意: 無制限モードや自動再開を使用すると、バッテリー消費が増加する可能性があります。',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('キャンセル'),
                ),
                TextButton(
                  onPressed: () {
                    // 設定を保存して適用
                    this.setState(() {
                      _speechStopMode = tempMode;
                      _autoRestart = tempAutoRestart;
                    });
                    _saveSpeechSettings();
                    Navigator.of(context).pop();
                    
                    // 設定変更を通知
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('音声認識モードを「${_getSpeechStopModeText()}」に設定しました')),
                    );
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          }
        );
      },
    );
  }
  
  // 停止モードのテキスト表示を取得
  String _getSpeechStopModeText() {
    switch (_speechStopMode) {
      case SpeechStopMode.gradual:
        return '段階入力';
      case SpeechStopMode.manual:
        return '手動入力';
      case SpeechStopMode.unlimited:
        return '無制限';
      default:
        return '不明';
    }
  }
}
