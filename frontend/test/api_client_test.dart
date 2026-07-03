import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_app/services/api_client.dart';

void main() {
  group('ApiClient', () {
    test('constructor sets baseUrl', () {
      final client = ApiClient(baseUrl: 'http://localhost:8088');
      expect(client.baseUrl, 'http://localhost:8088');
    });

    test('updateBaseUrl does nothing for same URL', () {
      final client = ApiClient(baseUrl: 'http://localhost:8088');
      client.updateBaseUrl('http://localhost:8088');
      expect(client.baseUrl, 'http://localhost:8088');
    });

    test('updateBaseUrl updates baseUrl', () {
      final client = ApiClient(baseUrl: 'http://localhost:8088');
      client.updateBaseUrl('http://localhost:9090');
      expect(client.baseUrl, 'http://localhost:9090');
    });

    test('dispose can be called multiple times without error', () {
      final client = ApiClient(baseUrl: 'http://localhost:8088');
      client.dispose();
      // Second dispose should not throw
      client.dispose();
    });

    test('downloadFile throws on invalid URL', () async {
      final client = ApiClient(baseUrl: 'http://localhost:8088');
      expect(
        () => client.downloadFile('http://nonexistent.example/file.png'),
        throwsA(isA<Exception>()),
      );
    }, skip: 'Requires network — add integration test');
  });
}
