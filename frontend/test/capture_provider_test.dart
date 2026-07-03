import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_app/providers/capture_provider.dart';
import 'package:pulse_app/services/api_client.dart';
import 'package:pulse_app/services/settings_service.dart';

void main() {
  group('CaptureProvider', () {
    late ApiClient apiClient;
    late SettingsService settingsService;
    late CaptureProvider provider;

    setUp(() {
      apiClient = ApiClient(baseUrl: 'http://localhost:8088');
      settingsService = SettingsService();
      provider = CaptureProvider(
        apiClient: apiClient,
        settingsService: settingsService,
      );
    });

    tearDown(() {
      provider.dispose();
    });

    test('initial state is correct', () {
      expect(provider.loading, true);
      expect(provider.hasError, false);
      expect(provider.isConnected, false);
      expect(provider.isConnecting, false);
      expect(provider.captures, isEmpty);
      expect(provider.captureCount, 0);
      expect(provider.newNames, isEmpty);
      expect(provider.savingFiles, isEmpty);
      expect(provider.selectedDirPath, isNull);
      expect(provider.saveError, isNull);
      expect(provider.errorMessage, '');
      expect(provider.backendUrl, 'http://localhost:8088');
    });

    test('clearAll clears captures and newNames', () async {
      // Access internal list through getter (it starts empty)
      expect(provider.captures, isEmpty);

      provider.clearAll();
      expect(provider.captures, isEmpty);
      expect(provider.newNames, isEmpty);
    });

    test('backendUrl returns from SettingsService', () {
      expect(provider.backendUrl, 'http://localhost:8088');
    });
  });
}
