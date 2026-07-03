import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/api_client.dart';
import 'services/settings_service.dart';
import 'providers/capture_provider.dart';
import 'screens/gallery_screen.dart';
import 'screens/setup_screen.dart';

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
        apiClient: ApiClient(baseUrl: SettingsService.defaultBackendUrl),
        settingsService: settingsService,
      ),
      child: MaterialApp(
        title: 'ComfyUI Pulse',
        debugShowCheckedModeBanner: false,
        theme: _buildTheme(),
        home: const _AppShell(),
      ),
    );
  }

  ThemeData _buildTheme() {
    return ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: Colors.teal,
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF09090B),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF09090B),
        foregroundColor: Colors.white,
      ),
      cardTheme: const CardThemeData(
        color: Color(0xFF18181B),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: BorderSide(
            color: Colors.white24,
          ),
        ),
      ),
    );
  }
}

/// Root shell: shows loading, setup, or gallery depending on provider state.
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CaptureProvider>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CaptureProvider>();

    // Still loading — show a centered spinner
    if (provider.loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // First launch — setup not yet completed by the user
    if (!provider.firstSetupDone) {
      return const SetupScreen();
    }

    // Normal operation
    return const GalleryScreen();
  }
}
