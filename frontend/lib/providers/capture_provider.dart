import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../models/capture_file.dart';
import '../services/api_client.dart';

class CaptureProvider extends ChangeNotifier {
  final ApiClient _apiClient;

  final List<CaptureFile> _captures = [];
  final Set<String> _newNames = {};
  final Set<String> _savingFiles = {};
  String? _selectedDirPath;
  String? _saveError;
  bool _loading = true;
  bool _hasError = false;
  String _errorMessage = '';

  CaptureProvider({required ApiClient apiClient}) : _apiClient = apiClient;

  // Getters
  List<CaptureFile> get captures => _captures;
  Set<String> get newNames => _newNames;
  Set<String> get savingFiles => _savingFiles;
  String? get selectedDirPath => _selectedDirPath;
  String? get saveError => _saveError;
  bool get loading => _loading;
  bool get hasError => _hasError;
  String get errorMessage => _errorMessage;
  List<CaptureFile> get imageCaptures =>
      _captures.where((f) => f.isImage).toList();
  int get captureCount => _captures.length;

  StreamSubscription? _sseSubscription;

  /// Initialize: load captures and subscribe to SSE.
  Future<void> initialize() async {
    await _loadCaptures();
    _subscribeToSSE();
  }

  Future<void> _loadCaptures() async {
    try {
      _loading = true;
      _hasError = false;
      notifyListeners();

      final list = await _apiClient.fetchCaptures();
      for (final file in list) {
        _addCapture(file, isNew: false);
      }
    } catch (e) {
      _hasError = true;
      _errorMessage = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void _subscribeToSSE() {
    _sseSubscription = _apiClient.subscribeEvents(
      onNewCapture: (file) {
        _addCapture(file, isNew: true);
      },
      onError: (error) {
        // SSE will auto-reconnect on next event
      },
    );
  }

  void _addCapture(CaptureFile file, {required bool isNew}) {
    // Avoid duplicates
    if (_captures.any((c) => c.name == file.name)) return;

    _captures.insert(0, file);
    if (isNew) {
      _newNames.add(file.name);

      /// Auto-save to selected directory
      if (_selectedDirPath != null && file.isImage) {
        _trySaveFile(file);
      }

      // Remove highlight after 3 seconds
      Future.delayed(const Duration(seconds: 3), () {
        _newNames.remove(file.name);
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// Pick a directory for saving files.
  Future<void> pickDirectory() async {
    try {
      _saveError = null;
      final result = await FilePicker.platform.getDirectoryPath(
        dialogTitle: '选择保存目录',
      );
      if (result != null) {
        _selectedDirPath = result;
        notifyListeners();

        // Re-save any existing unsaved images
        for (final file in _captures) {
          if (file.isImage && !file.saved) {
            _trySaveFile(file);
          }
        }
      }
    } catch (e) {
      _saveError = '无法访问目录：$e';
      notifyListeners();
    }
  }

  /// Save a single file to the selected directory.
  Future<void> saveFile(CaptureFile file) async {
    if (_selectedDirPath == null) {
      await pickDirectory();
      if (_selectedDirPath == null) return;
    }
    await _trySaveFile(file);
  }

  Future<void> _trySaveFile(CaptureFile file) async {
    if (_selectedDirPath == null || _savingFiles.contains(file.name)) return;

    _savingFiles.add(file.name);
    notifyListeners();

    try {
      final response = await http.get(Uri.parse(file.downloadUrl));
      if (response.statusCode != 200) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final saveDir = Directory(_selectedDirPath!);
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final saveFile = File('${saveDir.path}/${file.name}');
      await saveFile.writeAsBytes(response.bodyBytes);
      file.saved = true;
    } catch (e) {
      debugPrint('Failed to save ${file.name}: $e');
    } finally {
      _savingFiles.remove(file.name);
      notifyListeners();
    }
  }

  /// Clear all captures.
  void clearAll() {
    _captures.clear();
    _newNames.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _sseSubscription?.cancel();
    _apiClient.dispose();
    super.dispose();
  }
}
