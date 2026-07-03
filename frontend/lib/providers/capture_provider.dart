import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../models/capture_file.dart';
import '../services/api_client.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';

enum _ConnStatus { disconnected, connecting, connected, error }

class CaptureProvider extends ChangeNotifier {
  final ApiClient _apiClient;
  final SettingsService _settingsService;
  final StorageService _storageService;

  final List<CaptureFile> _captures = [];
  final Set<String> _newNames = {};
  final Set<String> _savingFiles = {};
  final List<Timer> _highlightTimers = [];
  String? _selectedDirPath;
  String? _saveError;
  bool _loading = true;
  _ConnStatus _connectionStatus = _ConnStatus.disconnected;
  String _errorMessage = '';

  bool get isConnected => _connectionStatus == _ConnStatus.connected;
  bool get isConnecting => _connectionStatus == _ConnStatus.connecting;
  bool get hasError => _connectionStatus == _ConnStatus.error;

  // Getters
  List<CaptureFile> get captures => _captures;
  Set<String> get newNames => _newNames;
  Set<String> get savingFiles => _savingFiles;
  String? get selectedDirPath => _selectedDirPath;
  String? get saveError => _saveError;
  bool get loading => _loading;
  String get errorMessage => _errorMessage;
  List<CaptureFile> get imageCaptures =>
      _captures.where((f) => f.isImage).toList();
  int get captureCount => _captures.length;

  StreamSubscription? _sseSubscription;
  Timer? _notifyDebounceTimer;

  /// Initialize: load persisted settings, then load captures and subscribe to SSE.
  Future<void> initialize() async {
    try {
      // Load persisted backend URL and update ApiClient if needed
      final savedUrl = _settingsService.getBackendUrl();
      if (savedUrl != _apiClient.baseUrl) {
        _apiClient.baseUrl = savedUrl;
      }

      // Load persisted save directory
      final savedDir = _settingsService.getSaveDirectory();
      if (savedDir != null) {
        _selectedDirPath = savedDir;
      }

      await _loadCaptures();
      _subscribeToSSE();
    } catch (e) {
      _connectionStatus = _ConnStatus.error;
      _errorMessage = '初始化失败：$e';
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadCaptures() async {
    try {
      _loading = true;
      _connectionStatus = _ConnStatus.disconnected;
      notifyListeners();

      final list = await _apiClient.fetchCaptures();
      _connectionStatus = _ConnStatus.connected;
      for (final file in list) {
        _addCapture(file, isNew: false);
      }
    } catch (e) {
      _connectionStatus = _ConnStatus.error;
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
      onConnected: () {
        _connectionStatus = _ConnStatus.connected;
        notifyListeners();
      },
      onError: (error) {
        _connectionStatus = _ConnStatus.disconnected;
        notifyListeners();
      },
    );
  }

  void _addCapture(CaptureFile file, {required bool isNew}) {
    // Avoid duplicates
    if (_captures.any((c) => c.name == file.name)) return;

    _captures.insert(0, file);

    /// Auto-save to selected directory for all image captures
    if (_selectedDirPath != null && file.isImage) {
      _trySaveFile(file);
    }

    if (isNew) {
      _newNames.add(file.name);

      // Remove highlight after 3 seconds
      final timer = Timer(const Duration(seconds: 3), () {
        _newNames.remove(file.name);
        _highlightTimers.remove(timer);
        notifyListeners();
      });
      _highlightTimers.add(timer);
    }
    _debouncedNotify();
  }

  void _debouncedNotify() {
    _notifyDebounceTimer?.cancel();
    _notifyDebounceTimer = Timer(const Duration(milliseconds: 50), () {
      notifyListeners();
    });
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
        _settingsService.setSaveDirectory(result);
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

  Future<void> _trySaveFile(CaptureFile file) async {
    if (_selectedDirPath == null || _savingFiles.contains(file.name)) return;

    _savingFiles.add(file.name);
    notifyListeners();

    try {
      final saveDir = Directory(_selectedDirPath!);
      final localPath = await _storageService.saveFile(file, saveDir);
      file.markSaved(localPath);
    } catch (e) {
      _saveError = '保存 ${file.name} 失败：$e';
      debugPrint('Failed to save ${file.name}: $e');
    } finally {
      _savingFiles.remove(file.name);
      notifyListeners();
    }
  }

  /// Get the current backend URL.
  String get backendUrl => _settingsService.getBackendUrl();

  /// Update the backend URL and re-initialize.
  Future<void> updateBackendUrl(String url) async {
    await _settingsService.setBackendUrl(url);
    _connectionStatus = _ConnStatus.disconnected;
    _apiClient.updateBaseUrl(
      url,
      onNewCapture: (file) {
        _addCapture(file, isNew: true);
      },
      onConnected: () {
        _connectionStatus = _ConnStatus.connected;
        notifyListeners();
      },
      onError: (error) {
        _connectionStatus = _ConnStatus.disconnected;
        debugPrint('SSE error after URL change: $error');
      },
    );
    // Clear captures from the old server before fetching new ones
    _captures.clear();
    _newNames.clear();
    // Re-fetch captures from the new server
    await _loadCaptures();
  }

  /// Manually reconnect to the backend.
  Future<void> reconnect() async {
    if (_connectionStatus == _ConnStatus.connecting) return;
    _connectionStatus = _ConnStatus.connecting;
    notifyListeners();

    // Cancel old SSE
    _sseSubscription?.cancel();
    _apiClient.dispose();

    await _loadCaptures();
    _subscribeToSSE();
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
    _notifyDebounceTimer?.cancel();
    for (final timer in _highlightTimers) {
      timer.cancel();
    }
    _highlightTimers.clear();
    _apiClient.dispose();
    super.dispose();
  }
}
