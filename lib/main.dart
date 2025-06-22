import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'voice_memo_page.dart';

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
        cardTheme: CardTheme(
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
        // こちらも同様に修正
        cardTheme: CardTheme(
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
  static const MethodChannel _channel = MethodChannel('android_speech_recognition');
  final TextEditingController _textController = TextEditingController();
  
  List<Task> _tasks = [];
  bool _speechEnabled = false;
  bool _speechListening = false;
  String _lastWords = '';

  @override
  void initState() {
    super.initState();
    _initSpeech();
    _loadTasks();
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

      // Android Speech Recognition APIの初期化
      _setupMethodChannel();
      
      try {
        final result = await _channel.invokeMethod('initialize');
        _speechEnabled = result == true;
        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        print('Android Speech Recognition API初期化エラー: $e');
        _speechEnabled = false;
        if (mounted) {
          setState(() {});
        }
      }
      
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('音声認識の初期化に失敗しました: $e')),
        );
      }
    }
  }

  void _setupMethodChannel() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'onPartialResult':
          final text = call.arguments as String;
          setState(() {
            _lastWords = text;
            _textController.text = _lastWords;
          });
          break;
        case 'onFinalResult':
          final text = call.arguments as String;
          setState(() {
            _lastWords = text;
            _textController.text = _lastWords;
          });
          break;
        case 'onError':
          final error = call.arguments as String;
          print('音声認識エラー: $error');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('音声認識エラー: $error')),
            );
          }
          setState(() {
            _speechListening = false;
          });
          break;
        case 'onListeningStarted':
          print('音声認識開始');
          break;
        case 'onListeningStopped':
          print('音声認識停止');
          if (_speechListening) {
            setState(() {
              _speechListening = false;
            });
          }
          break;
      }
    });
  }

  void _startListening() async {
    try {
      print('音声認識開始');
      
      await _channel.invokeMethod('startListening', {
        'locale': 'ja-JP',
        'partialResults': true,
        'maxResults': 5,
      });
      
      setState(() {
        _speechListening = true;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音声認識開始 - 話しかけてください')),
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
      await _channel.invokeMethod('stopListening');
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
}
