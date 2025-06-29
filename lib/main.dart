import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'voice_memo_page.dart';
import 'settings_page.dart';
import 'unified_voice_service.dart';

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
        // cardThemeをカスタマイズするが、直接プロパティを設定
        cardTheme: const CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
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
        // こちらも同様に修正
        cardTheme: const CardThemeData(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
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
    const SettingsPage(),
  ];

  void _onItemTapped(int index) {
    if (mounted) {
      setState(() {
        _selectedIndex = index;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.task_alt),
            label: 'タスクリスト',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.mic),
            label: 'ボイスメモ',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: '設定',
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
  final UnifiedVoiceService _voiceService = UnifiedVoiceService();
  
  List<Task> _tasks = [];
  bool _isInitialized = false;
  bool _isRecording = false;
  String _draftTaskContent = '';
  bool _showDraftCard = false;
  bool _isCompletedExpanded = false; // 完了タスクのアコーディオン表示用
  String? _swipedTaskId; // スワイプされているタスクのID
  String _initializationStatus = '音声サービスを初期化中...'; // 初期化状況表示用

  @override
  void initState() {
    super.initState();
    _initVoiceService();
    _loadTasks();
  }

  void _initVoiceService() async {
    try {
      setState(() {
        _initializationStatus = 'Voskモデルをロード中...';
      });
      
      bool success = await _voiceService.initialize();
      
      if (success) {
        setState(() {
          _initializationStatus = 'コールバックを設定中...';
        });
        
        _setupVoiceServiceCallbacks();
        
        setState(() {
          _initializationStatus = 'モデル情報を取得中...';
        });
        
        // 初期化後に現在のモデルを確認
        final currentModel = await _voiceService.getCurrentModel();
        print('現在使用中のモデル: $currentModel');
        
        // ビューコンパイル完了を待つための少し長めの遅延
        setState(() {
          _initializationStatus = 'UIの最適化中...';
        });
      }
      
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _initializationStatus = '初期化完了';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _initializationStatus = '初期化失敗';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('音声サービスの初期化に失敗しました: $e')),
        );
      }
    }
  }

  void _setupVoiceServiceCallbacks() {
    _voiceService.onTranscriptionUpdated = (text) {
      if (mounted) {
        setState(() {
          // 不要なスペースを削除して意味のある単位でスペースを保持
          _draftTaskContent = _cleanupText(text);
        });
      }
    };
    
    _voiceService.onRecordingStateChanged = (isRecording) {
      if (mounted) {
        setState(() {
          _isRecording = isRecording;
          if (!isRecording) {
            // 録音停止時の処理は特になし（ドラフトカードは表示したまま）
          }
        });
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

  String _cleanupText(String text) {
    // 連続するスペースを単一のスペースに変換
    String cleaned = text.replaceAll(RegExp(r'\s+'), ' ');
    // 先頭と末尾のスペースを削除
    cleaned = cleaned.trim();
    // 日本語の文字間の不要なスペースを削除（ひらがな、カタカナ、漢字間）
    // 正規表現のキャプチャグループを正しく使用
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'([\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF])\s+([\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF])'),
      (match) => '${match.group(1)}${match.group(2)}',
    );
    return cleaned;
  }

  void _startVoiceRecording() async {
    if (kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Webでは音声機能は利用できません')),
      );
      return;
    }

    if (!_voiceService.speechEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('音声認識機能が利用できません')),
      );
      return;
    }

    if (mounted) {
      setState(() {
        _showDraftCard = true;
        _draftTaskContent = '';
      });
    }

    await _voiceService.startContinuousListening();
  }

  void _stopVoiceRecording() async {
    await _voiceService.stopListening();
  }

  void _addDraftTask() {
    if (_draftTaskContent.trim().isEmpty) return;

    final newTask = Task(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      content: _draftTaskContent.trim(),
      createdAt: DateTime.now(),
    );

    if (mounted) {
      setState(() {
        _tasks.insert(0, newTask);
        _showDraftCard = false;
        _draftTaskContent = '';
      });
    }

    _stopVoiceRecording();
    _saveTasks();
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('タスクを追加しました')),
    );
  }

  void _cancelDraftTask() {
    if (mounted) {
      setState(() {
        _showDraftCard = false;
        _draftTaskContent = '';
      });
    }
    _stopVoiceRecording();
  }



  // タスクの順番変更
  void _onReorderTasks(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    
    final incompleteTasks = _incompleteTasks;
    final task = incompleteTasks.removeAt(oldIndex);
    incompleteTasks.insert(newIndex, task);
    
    // 元のリストを再構築
    final newTasks = <Task>[];
    newTasks.addAll(incompleteTasks);
    newTasks.addAll(_completedTasks);
    
    setState(() {
      _tasks = newTasks;
    });
    
    _saveTasks();
  }

  // タスクIDでトグル
  void _toggleTaskById(String taskId) {
    final taskIndex = _tasks.indexWhere((task) => task.id == taskId);
    if (taskIndex != -1) {
      setState(() {
        _tasks[taskIndex].isCompleted = !_tasks[taskIndex].isCompleted;
      });
      _saveTasks();
    }
  }

  // 削除確認付きタスク削除
  void _deleteTaskWithConfirm(Task task) async {
    final confirm = await showDialog<bool>(
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
    
    if (confirm == true) {
      _deleteTask(task.id);
    }
  }

  // タスク削除
  void _deleteTask(String taskId) {
    final taskIndex = _tasks.indexWhere((task) => task.id == taskId);
    if (taskIndex != -1) {
      final task = _tasks[taskIndex];
      setState(() {
        _tasks.removeAt(taskIndex);
      });
      _saveTasks();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('「${task.content}」を削除しました'),
          action: SnackBarAction(
            label: '元に戻す',
            onPressed: () {
              setState(() {
                _tasks.insert(taskIndex, task);
              });
              _saveTasks();
            },
          ),
        ),
      );
    }
  }

  // 未完了タスクと完了タスクを分離
  List<Task> get _incompleteTasks => _tasks.where((task) => !task.isCompleted).toList();
  List<Task> get _completedTasks => _tasks.where((task) => task.isCompleted).toList();

  // タスクリスト構築
  Widget _buildTaskList() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // 未完了タスク
          SizedBox(
            height: _completedTasks.isNotEmpty && _isCompletedExpanded 
                ? MediaQuery.of(context).size.height * 0.4  // 完了タスクが展開されている場合は高さを制限
                : MediaQuery.of(context).size.height * 0.7, // 未完了タスクのみの場合は大きな高さ
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(8.0),
              itemCount: _incompleteTasks.length,
              onReorder: _onReorderTasks,
              itemBuilder: (context, index) {
                final task = _incompleteTasks[index];
                return Container(
                  key: Key(task.id), // ここでキーを明示的に設定
                  child: _buildTaskCard(task, index, true),
                );
              },
            ),
          ),
          // 完了タスクアコーディオン
          if (_completedTasks.isNotEmpty) _buildCompletedTasksSection(),
        ],
      ),
    );
  }

  // 完了タスクセクション
  Widget _buildCompletedTasksSection() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        children: [
          ListTile(
            leading: Icon(
              _isCompletedExpanded ? Icons.expand_less : Icons.expand_more,
            ),
            title: Text(
              '完了済みタスク (${_completedTasks.length}件)',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            onTap: () {
              setState(() {
                _isCompletedExpanded = !_isCompletedExpanded;
              });
            },
          ),
          if (_isCompletedExpanded)
            ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.5, // 最大高さを画面の半分に制限
              ),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const AlwaysScrollableScrollPhysics(), // スクロールを有効化
                itemCount: _completedTasks.length,
                itemBuilder: (context, index) {
                  final task = _completedTasks[index];
                  return _buildTaskCard(task, index, false);
                },
              ),
            ),
        ],
      ),
    );
  }

  // タスクカード構築
  Widget _buildTaskCard(Task task, int index, bool isIncomplete) {
    final isSwipedOpen = _swipedTaskId == task.id;
    
    return GestureDetector(
      onTap: () {
        // 他のカードがスワイプされている場合は閉じる
        if (_swipedTaskId != null && _swipedTaskId != task.id) {
          setState(() {
            _swipedTaskId = null;
          });
        }
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Stack(
          children: [
            // 背景（ボタン部分）
            if (isSwipedOpen)
              Container(
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12.0),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // コピーボタン
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: task.content));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('「${task.content}」をコピーしました')),
                          );
                          setState(() {
                            _swipedTaskId = null; // スワイプ状態を閉じる
                          });
                        },
                        borderRadius: BorderRadius.circular(8.0),
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.blue,
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: const Icon(
                            Icons.copy,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // 削除ボタン
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _swipedTaskId = null; // スワイプ状態を閉じる
                          });
                          _deleteTaskWithConfirm(task);
                        },
                        borderRadius: BorderRadius.circular(8.0),
                        child: Container(
                          width: 60,
                          height: 60,
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(8.0),
                          ),
                          child: const Icon(
                            Icons.delete,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                  ],
                ),
              ),
            // 前面のカード
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              transform: Matrix4.translationValues(
                isSwipedOpen ? -152.0 : 0.0, // ボタンの幅分だけ左に移動
                0.0,
                0.0,
              ),
              child: GestureDetector(
                onPanUpdate: (details) {
                  // 右から左へのスワイプを検出
                  if (details.delta.dx < -5) {
                    setState(() {
                      _swipedTaskId = task.id;
                    });
                  }
                  // 左から右へのスワイプで閉じる
                  else if (details.delta.dx > 5 && isSwipedOpen) {
                    setState(() {
                      _swipedTaskId = null;
                    });
                  }
                },
                child: Card(
                  child: ListTile(
                    leading: SizedBox(
                      width: 24,
                      height: 24,
                      child: Checkbox(
                        value: task.isCompleted,
                        onChanged: (_) => _toggleTaskById(task.id),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    title: Text(
                      task.content,
                      style: TextStyle(
                        decoration: task.isCompleted ? TextDecoration.lineThrough : null,
                        color: task.isCompleted ? Colors.grey : null,
                      ),
                    ),
                    subtitle: Text(
                      '作成日時: ${task.createdAt.month}/${task.createdAt.day} ${task.createdAt.hour}:${task.createdAt.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: isIncomplete ? const Icon(Icons.drag_handle, color: Colors.grey) : null,
                  ),
                ),
              ),
            ),
          ],
        ),
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
      if (mounted) {
        setState(() {
          _tasks = tasksJson.map((json) => Task.fromJson(json)).toList();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: Text(widget.title),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 24),
              Text(
                _initializationStatus,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text(
                '初回起動時は時間がかかる場合があります',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Column(
        children: [
          // ドラフトタスクカード
          if (_showDraftCard)
            Container(
              margin: const EdgeInsets.all(16.0),
              child: Card(
                elevation: 4,
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _isRecording ? Icons.mic : Icons.mic_off,
                            color: _isRecording ? Colors.red : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isRecording ? '音声認識中...' : '音声認識完了',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _isRecording ? Colors.red : Colors.grey,
                            ),
                          ),
                          if (_isRecording) ...[
                            const SizedBox(width: 8),
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8.0),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text(
                          _draftTaskContent.isEmpty 
                              ? '音声を認識中です...' 
                              : _draftTaskContent,
                          style: TextStyle(
                            fontSize: 16,
                            color: _draftTaskContent.isEmpty 
                                ? Colors.grey 
                                : Colors.black,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _cancelDraftTask,
                            icon: const Icon(Icons.cancel),
                            label: const Text('キャンセル'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.grey,
                              foregroundColor: Colors.white,
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: _draftTaskContent.trim().isNotEmpty 
                                ? _addDraftTask 
                                : null,
                            icon: const Icon(Icons.add_task),
                            label: const Text('タスク追加'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          // タスクリスト
          Expanded(
            child: _tasks.isEmpty
                ? _buildEmptyMessage()
                : _buildTaskList(),
          ),
        ],
      ),
      floatingActionButton: !kIsWeb && !_showDraftCard && _isInitialized
          ? FloatingActionButton(
              onPressed: _startVoiceRecording,
              backgroundColor: _voiceService.speechEnabled ? Colors.blue : Colors.grey,
              child: const Icon(
                Icons.mic,
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
          'タスクがありません\nWebでは音声機能は利用できません',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    } else {
      return const Center(
        child: Text(
          'タスクがありません\n右下の録音ボタンでタスクを追加してください',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }
  }

  @override
  void dispose() {
    _voiceService.stopListening();
    super.dispose();
  }
}
