import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../models/capture_file.dart';
import '../services/api_client.dart';
import '../services/settings_service.dart';

class CaptureProvider extends ChangeNotifier {
  final ApiClient _apiClient;
  final SettingsService _settingsService;

  final List<CaptureFile> _captures = [];
  final Set<String> _newNames = {};
  final Set<String> _savingFiles = {};
  String? _selectedDirPath;
  String? _saveError;
  bool _loading = true;
  bool _hasError = false;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _errorMessage = '';

  CaptureProvider({
    required ApiClient apiClient,
    required SettingsService settingsService,
  })  : _apiClient = apiClient,
        _settingsService = settingsService;

  // Getters
  List<CaptureFile> get captures => _captures;
  Set<String> get newNames => _newNames;
  Set<String> get savingFiles => _savingFiles;
  String? get selectedDirPath => _selectedDirPath;
  String? get saveError => _saveError;
  bool get loading => _loading;
  bool get hasError => _hasError;
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;
  String get errorMessage => _errorMessage;
  List<CaptureFile> get imageCaptures =>
      _captures.where((f) => f.isImage).toList();
  int get captureCount => _captures.length;

  StreamSubscription? _sseSubscription;

  /// Initialize: load persisted settings, then load captures and subscribe to SSE.
  Future<void> initialize() async {
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
  }

  Future<void> _loadCaptures() async {
    try {
      _loading = true;
      _hasError = false;
      notifyListeners();

      final list = await _apiClient.fetchCaptures();
      _isConnected = true;
      for (final file in list) {
        _addCapture(file, isNew: false);
      }
    } catch (e) {
      _hasError = true;
      _errorMessage = e.toString();
      _isConnected = false;
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
        _isConnected = true;
        _isConnecting = false;
        notifyListeners();
      },
      onError: (error) {
        _isConnected = false;
        _isConnecting = false;
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
      final response = await http.get(
          Uri.parse(file.downloadUrl(_apiClient.baseUrl)));
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
      file.localPath = saveFile.path;
    } catch (e) {
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
    _isConnected = false;
    _apiClient.updateBaseUrl(
      url,
      onNewCapture: (file) {
        _addCapture(file, isNew: true);
      },
      onConnected: () {
        _isConnected = true;
        _isConnecting = false;
        notifyListeners();
      },
      onError: (error) {
        _isConnected = false;
        _isConnecting = false;
        debugPrint('SSE error after URL change: $error');
      },
    );
    // Re-fetch captures from the new server
    await _loadCaptures();
  }

  /// Manually reconnect to the backend.
  Future<void> reconnect() async {
    if (_isConnecting) return;
    _isConnecting = true;
    _isConnected = false;
    _hasError = false;
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
    _apiClient.dispose();
    super.dispose();
  }
}
