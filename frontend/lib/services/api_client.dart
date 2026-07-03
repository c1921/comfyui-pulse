import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/capture_file.dart';

class ApiClient {
  String baseUrl;
  HttpClient? _httpClient;
  StreamSubscription<CaptureFile>? _sseSubscription;

  ApiClient({required this.baseUrl});

  /// Update the backend base URL and re-subscribe to SSE events.
  /// Pass a [onNewCapture] callback to reconnect with the new URL.
  void updateBaseUrl(String newUrl,
      {void Function(CaptureFile file)? onNewCapture,
      void Function(Object error)? onError,
      void Function()? onConnected}) {
    if (baseUrl == newUrl) return;
    baseUrl = newUrl;

    // Reconnect SSE if it was previously subscribed and a callback is given
    if (_httpClient != null && onNewCapture != null) {
      dispose();
      subscribeEvents(
          onNewCapture: onNewCapture,
          onError: onError,
          onConnected: onConnected);
    }
  }

  /// Fetch the list of all captured files.
  Future<List<CaptureFile>> fetchCaptures() async {
    final uri = Uri.parse('$baseUrl/api/captures');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw HttpException('Failed to fetch captures: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final captures = (data['captures'] as List<dynamic>)
        .map((e) => CaptureFile.fromJson(e as Map<String, dynamic>))
        .toList();
    return captures;
  }

  /// Subscribe to real-time SSE events.
  /// Returns a [StreamSubscription] that emits [CaptureFile] for new attachments.
  /// Call [cancel] on the subscription to close the connection.
  StreamSubscription<CaptureFile> subscribeEvents({
    required void Function(CaptureFile file) onNewCapture,
    void Function(Object error)? onError,
    void Function()? onConnected,
  }) {
    final uri = Uri.parse('$baseUrl/api/events');
    _httpClient = HttpClient();
    _httpClient!.connectionTimeout = const Duration(seconds: 30);

    final controller = StreamController<CaptureFile>.broadcast();

    _connectSSE(uri, controller, onConnected);

    _sseSubscription = controller.stream.listen(
      onNewCapture,
      onError: onError,
      cancelOnError: false,
    );

    return _sseSubscription!;
  }

  void _connectSSE(
    Uri uri,
    StreamController<CaptureFile> controller,
    void Function()? onConnected,
  ) async {
    try {
      final request = await _httpClient!.getUrl(uri);
      request.headers.set('Accept', 'text/event-stream');
      request.headers.set('Cache-Control', 'no-cache');

      final response = await request.close();

      if (response.statusCode != 200) {
        controller.addError(
          HttpException('SSE connection failed: ${response.statusCode}'),
        );
        return;
      }

      onConnected?.call();

      String buffer = '';
      await for (final chunk in response.transform(utf8.decoder)) {
        buffer += chunk;
        final lines = buffer.split('\n');
        // Keep the last incomplete line in the buffer
        buffer = lines.removeLast();

        String? currentData;
        for (final line in lines) {
          if (line.startsWith('data: ')) {
            currentData = line.substring(6);
          } else if (line.isEmpty && currentData != null) {
            // Empty line signals end of an event
            try {
              final json = jsonDecode(currentData) as Map<String, dynamic>;
              if (json['type'] == 'new_attachment') {
                final file = CaptureFile.fromJson(json);
                controller.add(file);
              }
            } catch (_) {
              // Skip malformed events
            }
            currentData = null;
          }
        }
      }
    } catch (e) {
      if (!controller.isClosed) {
        controller.addError(e);
      }
    }
  }

  /// Cancel the SSE subscription and close the HTTP client.
  void dispose() {
    _sseSubscription?.cancel();
    _httpClient?.close(force: true);
  }
}
