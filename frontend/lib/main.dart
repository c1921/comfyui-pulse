import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/api_client.dart';
import 'services/settings_service.dart';
import 'providers/capture_provider.dart';
import 'screens/gallery_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settingsService = SettingsService();
  await settingsService.init();
  runApp(PulseApp(settingsService: settingsService));
}

class PulseApp extends StatelessWidget {
  final SettingsService settingsService;

  const PulseApp({super.key, required this.settingsService});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => CaptureProvider(
        apiClient: ApiClient(baseUrl: 'http://127.0.0.1:8088'),
        settingsService: settingsService,
      ),
      child: MaterialApp(
        title: 'ComfyUI Pulse',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(Brightness.dark),
        home: const GalleryScreen(),
      ),
    );
  }

  ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      brightness: brightness,
      colorSchemeSeed: Colors.teal,
      useMaterial3: true,
      scaffoldBackgroundColor: isDark ? const Color(0xFF09090B) : Colors.white,
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF09090B) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
      ),
      cardTheme: CardThemeData(
        color: isDark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: isDark ? Colors.white : Colors.black,
          foregroundColor: isDark ? Colors.black : Colors.white,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: isDark ? Colors.white : Colors.black,
          side: BorderSide(
            color: isDark ? Colors.white24 : Colors.black26,
          ),
        ),
      ),
    );
  }
}
