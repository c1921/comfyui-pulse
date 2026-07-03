import 'dart:io';
import '../models/capture_file.dart';
import 'api_client.dart';

/// Handles file I/O for saving captured files to disk.
class StorageService {
  final ApiClient _apiClient;

  StorageService({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Download a file and save it to [saveDir]. Returns the local file path
  /// on success, or throws on failure.
  Future<String> saveFile(
      CaptureFile file, Directory saveDir) async {
    final bytes = await _apiClient.downloadFile(
        file.downloadUrl(_apiClient.baseUrl));

    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
    }

    final saveFile = File('${saveDir.path}/${file.name}');
    await saveFile.writeAsBytes(bytes);
    return saveFile.path;
  }
}
