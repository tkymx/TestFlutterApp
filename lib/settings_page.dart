import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:archive/archive.dart';
import 'unified_voice_service.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final UnifiedVoiceService _voiceService = UnifiedVoiceService();
  
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  String _currentModel = 'small';
  Map<String, ModelInfo> _availableModels = {};
  Map<String, bool> _installedModels = {};
  
  @override
  void initState() {
    super.initState();
    _initializeModels();
    _checkInstalledModels();
    _loadCurrentModel();
  }

  void _initializeModels() {
    _availableModels = {
      'small': ModelInfo(
        id: 'small',
        name: '最小版モデル',
        description: '軽量で高速。基本的な音声認識に適している。',
        size: '40MB',
        url: 'https://alphacephei.com/vosk/models/vosk-model-small-ja-0.22.zip',
        fileName: 'vosk-model-small-ja-0.22',
        accuracy: '標準',
      ),
      'large': ModelInfo(
        id: 'large',
        name: '高精度版モデル',
        description: '高精度の音声認識。専門用語や複雑な文章に対応。',
        size: '1000MB',
        url: 'https://alphacephei.com/vosk/models/vosk-model-ja-0.22.zip',
        fileName: 'vosk-model-ja-0.22',
        accuracy: '高精度',
      ),
    };
  }

  Future<void> _checkInstalledModels() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      
      for (String modelId in _availableModels.keys) {
        final modelInfo = _availableModels[modelId]!;
        final modelDir = Directory('${directory.path}/${modelInfo.fileName}');
        _installedModels[modelId] = await modelDir.exists();
      }
      
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('インストール済みモデルチェックエラー: $e');
    }
  }

  Future<void> _loadCurrentModel() async {
    try {
      // 音声サービスから現在のモデルを取得
      _currentModel = await _voiceService.getCurrentModel();
      print('現在のモデル: $_currentModel');
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      print('現在のモデル読み込みエラー: $e');
      _currentModel = 'small'; // デフォルト値
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _setCurrentModel(String modelId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('current_vosk_model', modelId);
      
      // モデル情報を取得
      final modelInfo = _availableModels[modelId]!;
      print('モデル切り替え: ${modelInfo.name} (ID: $modelId)');
      
      // モデルがインストールされているかチェック
      final directory = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${directory.path}/${modelInfo.fileName}');
      final modelPath = '${directory.path}/${modelInfo.fileName}';
      
      print('モデルパス確認: $modelPath');
      print('ディレクトリ存在: ${await modelDir.exists()}');
      
      if (!await modelDir.exists()) {
        print('エラー: モデルディレクトリが存在しません: $modelPath');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('モデルがインストールされていません。先にダウンロードしてください。'),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }
      
      // ディレクトリ内のファイルをチェック
      try {
        final files = await modelDir.list().toList();
        print('モデルディレクトリ内のファイル数: ${files.length}');
        for (var file in files.take(5)) { // 最初の5ファイルをログ出力
          print('  - ${file.path}');
        }
      } catch (e) {
        print('ディレクトリ内容確認エラー: $e');
      }
      
      // モデルパスも保存
      await prefs.setString('current_vosk_model_path', modelPath);
      print('モデルパスを保存: $modelPath');
      
      // 音声認識サービスに新しいモデルを通知（パスも含める）
      print('音声認識サービスにモデル設定を通知: $modelId, $modelPath');
      final success = await _voiceService.setModel(modelId);
      print('モデル設定結果: $success');
      
      if (success) {
        if (mounted) {
          setState(() {
            _currentModel = modelId;
          });
        }
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('モデルを${_availableModels[modelId]!.name}に変更しました'),
              backgroundColor: Colors.green,
            ),
          );
        }
        print('モデル切り替え成功: ${modelInfo.name}');
      } else {
        print('エラー: 音声認識サービスでのモデル設定に失敗');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('モデルの変更に失敗しました。音声認識サービスでの設定でエラーが発生しました。'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      print('モデル変更エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('モデルの変更に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _downloadModel(String modelId) async {
    if (_isDownloading) return;
    
    final modelInfo = _availableModels[modelId]!;
    
    // ダウンロード確認ダイアログ
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${modelInfo.name}をダウンロード'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('サイズ: ${modelInfo.size}'),
            const SizedBox(height: 8),
            Text('説明: ${modelInfo.description}'),
            const SizedBox(height: 16),
            const Text(
              'ダウンロードには時間がかかる場合があります。続行しますか？',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '注意: 大きなファイルの場合、メモリ不足によりダウンロードや展開に失敗する可能性があります。',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('ダウンロード'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    if (mounted) {
      setState(() {
        _isDownloading = true;
        _downloadProgress = 0.0;
      });
    }
    
    try {
      await _performDownload(modelInfo);
      
      // ダウンロード完了後、インストール状態を更新
      await _checkInstalledModels();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${modelInfo.name}のダウンロードが完了しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('ダウンロードエラー: $e');
      
      // エラーの種類に応じて詳細なメッセージを表示
      String userMessage = _getDetailedErrorMessage(e.toString());
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('ダウンロードに失敗しました'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userMessage,
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '対処方法:',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '• デバイスの空きメモリを増やしてから再試行\n'
                    '• 他のアプリを終了してメモリを解放\n'
                    '• より小さなモデル（最小版）の使用を検討\n'
                    '• デバイスの再起動後に再試行',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
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
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadProgress = 0.0;
        });
      }
    }
  }

  String _getDetailedErrorMessage(String error) {
    if (error.contains('メモリ不足') || error.contains('Out of Memory') || error.contains('Exhausted heap')) {
      return 'メモリ不足のため処理に失敗しました。このモデルはファイルサイズが非常に大きく、'
          'デバイスの利用可能メモリを超えています。';
    } else if (error.contains('HTTP')) {
      return 'ネットワークエラーが発生しました。インターネット接続を確認してください。';
    } else if (error.contains('ZIP') || error.contains('FormatException')) {
      return 'ダウンロードしたファイルの展開に失敗しました。ファイルが破損している可能性があります。';
    } else if (error.contains('FileSystemException') || error.contains('容量')) {
      return 'ストレージの容量不足です。デバイスの空き容量を確保してください。';
    } else if (error.contains('非常に大きなファイル')) {
      return 'ファイルサイズが大きすぎるため、このデバイスでは処理できません。';
    } else {
      return '予期しないエラーが発生しました: $error';
    }
  }

  Future<void> _performDownload(ModelInfo modelInfo) async {
    try {
      // ダウンロード先ディレクトリの準備
      final directory = await getApplicationDocumentsDirectory();
      final zipFile = File('${directory.path}/${modelInfo.fileName}.zip');
      final extractDir = Directory('${directory.path}/${modelInfo.fileName}');
      
      // 既存のファイルを削除
      if (await zipFile.exists()) {
        await zipFile.delete();
      }
      if (await extractDir.exists()) {
        await extractDir.delete(recursive: true);
      }
      
      // 実際のHTTPダウンロード実装
      await _downloadWithProgress(modelInfo.url, zipFile);
      
      // ZIPファイルを展開
      await _extractZipFile(zipFile, extractDir);
      
      // ZIPファイルを削除
      if (await zipFile.exists()) {
        await zipFile.delete();
      }
      
      print('モデル ${modelInfo.name} のダウンロードが完了しました');
      
    } catch (e) {
      print('ダウンロード処理エラー: $e');
      throw e;
    }
  }

  Future<void> _downloadWithProgress(String url, File targetFile) async {
    IOSink? sink;
    
    try {
      print('ダウンロード開始: $url');
      
      final request = http.Request('GET', Uri.parse(url));
      final response = await request.send();
      
      if (response.statusCode != 200) {
        throw Exception('ダウンロードに失敗しました: HTTP ${response.statusCode}');
      }
      
      final contentLength = response.contentLength ?? 0;
      var downloadedBytes = 0;
      
      // 大きなファイルサイズの警告
      if (contentLength > 500 * 1024 * 1024) { // 500MB以上
        print('警告: 大きなファイルです ($contentLength bytes). メモリ不足の可能性があります。');
      }
      
      sink = targetFile.openWrite();
      
      await for (final chunk in response.stream) {
        sink.add(chunk);
        downloadedBytes += chunk.length;
        
        if (contentLength > 0) {
          final progress = downloadedBytes / contentLength;
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
            });
          }
        }
        
        // メモリ圧迫を避けるため定期的にflush
        if (downloadedBytes % (10 * 1024 * 1024) == 0) { // 10MBごと
          await sink.flush();
        }
      }
      
      await sink.flush();
      await sink.close();
      sink = null;
      
      print('ダウンロード完了: ${targetFile.path} (${downloadedBytes} bytes)');
      
      // ファイルサイズの検証
      final actualSize = await targetFile.length();
      if (actualSize != downloadedBytes) {
        throw Exception('ファイルサイズが一致しません: expected=$downloadedBytes, actual=$actualSize');
      }
      
    } catch (e) {
      print('ダウンロードエラー: $e');
      
      // クリーンアップ
      if (sink != null) {
        try {
          await sink.close();
        } catch (closeError) {
          print('ファイルクローズエラー: $closeError');
        }
      }
      
      // 破損したファイルを削除
      if (await targetFile.exists()) {
        try {
          await targetFile.delete();
          print('破損したファイルを削除しました: ${targetFile.path}');
        } catch (deleteError) {
          print('ファイル削除エラー: $deleteError');
        }
      }
      
      // エラーを再投げ（デモファイルは作成しない）
      throw e;
    }
  }



















  Future<void> _extractZipFile(File zipFile, Directory extractDir) async {
    try {
      print('ZIP展開開始: ${zipFile.path}');
      final fileSize = await zipFile.length();
      print('ファイルサイズ: $fileSize bytes (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB)');
      
      await extractDir.create(recursive: true);
      
      // メモリ使用量の事前チェック
      if (fileSize > 1000 * 1024 * 1024) { // 1GB以上
        final errorMessage = '非常に大きなファイルです (${(fileSize / 1024 / 1024).toStringAsFixed(1)} MB)。'
            'このサイズのファイルは展開時にメモリ不足エラーが発生する可能性が高いです。'
            'より小さなモデルの使用をお勧めします。';
        print('エラー: $errorMessage');
        throw Exception(errorMessage);
      }
      
      try {
        // メモリ効率を考慮した展開処理
        print('ZIPファイルの展開を開始します...');
        
        final bytes = await zipFile.readAsBytes();
        print('ZIPファイルをメモリに読み込みました: ${bytes.length} bytes');
        
        final archive = ZipDecoder().decodeBytes(bytes);
        print('ZIP内のファイル数: ${archive.length}');
        
        int extractedFiles = 0;
        int totalBytes = 0;
        
        for (final file in archive) {
          final filename = file.name;
          final targetFile = File('${extractDir.path}/$filename');
          
          if (file.isFile) {
            await targetFile.parent.create(recursive: true);
            
            try {
              await targetFile.writeAsBytes(file.content as List<int>);
              extractedFiles++;
              totalBytes += file.size;
              
              if (extractedFiles % 20 == 0) {
                print('展開進捗: $extractedFiles ファイル (${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB)');
              }
            } catch (e) {
              throw Exception('ファイル展開エラー ($filename): $e');
            }
          } else {
            await Directory('${extractDir.path}/$filename').create(recursive: true);
          }
        }
        
        print('ZIP展開完了: $extractedFiles ファイル, ${(totalBytes / 1024 / 1024).toStringAsFixed(1)} MB');
        
        // 展開結果の検証
        if (extractedFiles == 0) {
          throw Exception('ZIPファイルが空であるか、有効なファイルが含まれていません。');
        }
        
      } catch (e) {
        // 詳細なエラー分析
        String detailedError;
        
        if (e.toString().contains('Out of Memory') || e.toString().contains('Exhausted heap')) {
          detailedError = 'メモリ不足エラー: ファイルサイズが大きすぎて展開できません。\n\n'
              '対処方法:\n'
              '• デバイスの空きメモリを増やしてください\n'
              '• より小さなモデルをお試しください\n'
              '• 他のアプリを終了してからもう一度お試しください\n'
              '• デバイスを再起動してからお試しください';
        } else if (e.toString().contains('FormatException') || e.toString().contains('Invalid zip')) {
          detailedError = 'ZIPファイル形式エラー: ダウンロードしたファイルが破損しているか、正しいZIPファイルではありません。\n\n'
              '対処方法:\n'
              '• モデルを再ダウンロードしてください\n'
              '• ネットワーク接続を確認してください\n'
              '• 別のモデルをお試しください\n'
              '• Wi-Fi接続でダウンロードを再実行してください';
        } else if (e.toString().contains('FileSystemException') || e.toString().contains('No space left')) {
          detailedError = 'ファイルシステムエラー: ストレージの容量不足または権限の問題です。\n\n'
              '対処方法:\n'
              '• デバイスの空き容量を確認してください\n'
              '• 不要なファイルを削除してください\n'
              '• アプリの権限設定を確認してください\n'
              '• デバイスを再起動してからお試しください';
        } else if (e.toString().contains('非常に大きなファイル')) {
          detailedError = e.toString();
        } else {
          detailedError = 'ZIP展開エラー: $e\n\n'
              '対処方法:\n'
              '• モデルを再ダウンロードしてください\n'
              '• デバイスの空き容量を確認してください\n'
              '• より小さなモデルをお試しください';
        }
        
        print('詳細エラー: $detailedError');
        
        // 既存のファイルをクリア
        if (await extractDir.exists()) {
          try {
            await extractDir.delete(recursive: true);
            print('展開に失敗したファイルを削除しました');
          } catch (deleteError) {
            print('クリーンアップエラー: $deleteError');
          }
        }
        
        throw Exception(detailedError);
      }
      
    } catch (e) {
      print('ZIP展開処理エラー: $e');
      throw e; // エラーを再投げ（デモファイルは作成しない）
    }
  }

  Future<void> _deleteModel(String modelId) async {
    if (modelId == _currentModel) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('現在使用中のモデルは削除できません'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    
    final modelInfo = _availableModels[modelId]!;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${modelInfo.name}を削除'),
        content: const Text('このモデルを削除しますか？削除後は再ダウンロードが必要になります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      final modelDir = Directory('${directory.path}/${modelInfo.fileName}');
      
      if (await modelDir.exists()) {
        await modelDir.delete(recursive: true);
      }
      
      await _checkInstalledModels();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${modelInfo.name}を削除しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('モデル削除エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('モデルの削除に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _clearAllCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('全キャッシュを削除'),
        content: const Text('すべてのモデルファイルとキャッシュを削除しますか？\n現在使用中のモデル以外がすべて削除されます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    try {
      final directory = await getApplicationDocumentsDirectory();
      
      for (String modelId in _availableModels.keys) {
        if (modelId != _currentModel) {
          final modelInfo = _availableModels[modelId]!;
          final modelDir = Directory('${directory.path}/${modelInfo.fileName}');
          
          if (await modelDir.exists()) {
            await modelDir.delete(recursive: true);
          }
        }
      }
      
      await _checkInstalledModels();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('キャッシュを削除しました'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('キャッシュ削除エラー: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('キャッシュの削除に失敗しました: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          // 音声認識モデル設定
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '音声認識モデル',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '音声認識の精度とパフォーマンスを調整できます。高精度版は最小版より高い精度を提供します。',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  
                  // モデル一覧
                  ..._availableModels.entries.map((entry) {
                    final modelId = entry.key;
                    final modelInfo = entry.value;
                    final isInstalled = _installedModels[modelId] ?? false;
                    final isCurrent = modelId == _currentModel;
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      elevation: isCurrent ? 4 : 1,
                      color: isCurrent ? Theme.of(context).colorScheme.primaryContainer : null,
                      child: ListTile(
                        title: Text(
                          modelInfo.name,
                          style: TextStyle(
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(modelInfo.description),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Text('サイズ: ${modelInfo.size}'),
                                const SizedBox(width: 16),
                                Text('精度: ${modelInfo.accuracy}'),
                              ],
                            ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isCurrent)
                              const Chip(
                                label: Text('使用中'),
                                backgroundColor: Colors.green,
                                labelStyle: TextStyle(color: Colors.white),
                              )
                            else if (isInstalled)
                              TextButton(
                                onPressed: () => _setCurrentModel(modelId),
                                child: const Text('使用する'),
                              )
                            else
                              ElevatedButton(
                                onPressed: _isDownloading ? null : () => _downloadModel(modelId),
                                child: const Text('ダウンロード'),
                              ),
                            const SizedBox(width: 8),
                            if (isInstalled && !isCurrent)
                              IconButton(
                                onPressed: () => _deleteModel(modelId),
                                icon: const Icon(Icons.delete),
                                color: Colors.red,
                              ),
                          ],
                        ),
                        isThreeLine: true,
                      ),
                    );
                  }).toList(),
                  
                  // ダウンロード進捗
                  if (_isDownloading) ...[
                    const SizedBox(height: 16),
                    const Text('ダウンロード中...'),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(value: _downloadProgress),
                    const SizedBox(height: 8),
                    Text('${(_downloadProgress * 100).toInt()}%'),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // 録音品質設定
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '録音品質設定',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '音声認識の精度を向上させるため、録音品質を最適化します。',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  
                  const ListTile(
                    leading: Icon(Icons.high_quality, color: Colors.green),
                    title: Text('高品質録音'),
                    subtitle: Text('192kbps AAC-LC、44.1kHz モノラル'),
                    trailing: Icon(Icons.check_circle, color: Colors.green),
                  ),
                  
                  const ListTile(
                    leading: Icon(Icons.noise_control_off, color: Colors.blue),
                    title: Text('ノイズリダクション'),
                    subtitle: Text('背景ノイズを自動的に軽減'),
                    trailing: Icon(Icons.check_circle, color: Colors.green),
                  ),
                  
                  const ListTile(
                    leading: Icon(Icons.volume_up, color: Colors.orange),
                    title: Text('自動音声レベル調整'),
                    subtitle: Text('音声が小さい場合に自動で増幅'),
                    trailing: Icon(Icons.check_circle, color: Colors.green),
                  ),
                  
                  const ListTile(
                    leading: Icon(Icons.monitor, color: Colors.purple),
                    title: Text('リアルタイム品質監視'),
                    subtitle: Text('録音中の品質を監視してアドバイス表示'),
                    trailing: Icon(Icons.check_circle, color: Colors.green),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // デバッグ情報
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'デバッグ情報',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('現在のモデル: $_currentModel'),
                  Text('音声認識可能: ${_voiceService.speechEnabled ? "はい" : "いいえ"}'),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final installedModels = await _voiceService.getInstalledModels();
                      final currentModel = await _voiceService.getCurrentModel();
                      
                      // モデルパス情報も取得
                      final directory = await getApplicationDocumentsDirectory();
                      final smallModelPath = '${directory.path}/vosk-model-small-ja-0.22';
                      final largeModelPath = '${directory.path}/vosk-model-ja-0.22';
                      final smallExists = await Directory(smallModelPath).exists();
                      final largeExists = await Directory(largeModelPath).exists();
                      
                      if (mounted) {
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('詳細デバッグ情報'),
                            content: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('現在のモデル: $currentModel'),
                                  Text('インストール済みモデル: ${installedModels?.toString() ?? "取得エラー"}'),
                                  Text('音声認識状態: ${_voiceService.speechEnabled}'),
                                  Text('初期化状態: ${_voiceService.isInitialized}'),
                                  const SizedBox(height: 16),
                                  const Text('ファイルパス情報:', style: TextStyle(fontWeight: FontWeight.bold)),
                                  Text('小モデルパス: $smallModelPath'),
                                  Text('小モデル存在: $smallExists'),
                                  Text('大モデルパス: $largeModelPath'),
                                  Text('大モデル存在: $largeExists'),
                                  const SizedBox(height: 16),
                                  Text('インストール状態: ${_installedModels.toString()}'),
                                ],
                              ),
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
                    },
                    child: const Text('詳細デバッグ情報を表示'),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // キャッシュ管理
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'キャッシュ管理',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'ストレージ容量を節約するためにキャッシュを削除できます。',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _clearAllCache,
                      icon: const Icon(Icons.clear_all),
                      label: const Text('全キャッシュを削除'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // アプリ情報
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'アプリ情報',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const ListTile(
                    leading: Icon(Icons.info),
                    title: Text('バージョン'),
                    subtitle: Text('1.0.0'),
                  ),
                  const ListTile(
                    leading: Icon(Icons.mic),
                    title: Text('音声認識エンジン'),
                    subtitle: Text('Vosk Speech Recognition'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ModelInfo {
  final String id;
  final String name;
  final String description;
  final String size;
  final String url;
  final String fileName;
  final String accuracy;

  ModelInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.size,
    required this.url,
    required this.fileName,
    required this.accuracy,
  });
}