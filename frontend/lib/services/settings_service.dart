import 'package:shared_preferences/shared_preferences.dart';

/// Persistent settings for the app using SharedPreferences.
class SettingsService {
  static const String _keySaveDirectory = 'save_directory_path';
  static const String _keyBackendUrl = 'backend_base_url';

  static const String defaultBackendUrl = 'http://127.0.0.1:8088';

  SharedPreferences? _prefs;

  /// Initialize the service. Must be called before any read/write.
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --- Save directory ---

  String? getSaveDirectory() {
    return _prefs?.getString(_keySaveDirectory);
  }

  Future<bool> setSaveDirectory(String path) async {
    return _prefs?.setString(_keySaveDirectory, path) ?? false;
  }

  Future<bool> removeSaveDirectory() async {
    return _prefs?.remove(_keySaveDirectory) ?? false;
  }

  // --- Backend URL ---

  String getBackendUrl() {
    return _prefs?.getString(_keyBackendUrl) ?? defaultBackendUrl;
  }

  Future<bool> setBackendUrl(String url) async {
    return _prefs?.setString(_keyBackendUrl, url) ?? false;
  }
}
