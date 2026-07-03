import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/capture_provider.dart';
import '../services/settings_service.dart';
import 'gallery_screen.dart';

/// Full-screen first-launch setup that requires the user to pick a save
/// directory and confirm (or change) the backend URL before proceeding.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    final provider = context.read<CaptureProvider>();
    _urlController = TextEditingController(text: provider.backendUrl);
  }

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    await context.read<CaptureProvider>().pickDirectory();
    // rebuild will be triggered by context.watch
  }

  Future<void> _saveAndStart() async {
    final provider = context.read<CaptureProvider>();
    final url = _urlController.text.trim();

    if (url.isNotEmpty && url != provider.backendUrl) {
      // Validate URL format
      final parsed = Uri.tryParse(url);
      if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('请输入有效的 URL'),
              backgroundColor: Colors.red.shade300,
            ),
          );
        }
        return;
      }
      await provider.updateBackendUrl(url);
    }

    provider.markSetupDone();

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const GalleryScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<CaptureProvider>();
    final hasDir = provider.selectedDirPath != null;

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // App icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    Icons.wifi_tethering,
                    size: 44,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  'ComfyUI Pulse',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '首次使用请先配置后端地址和保存目录',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 40),

                // --- Backend URL ---
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '后端地址',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _urlController,
                  decoration: InputDecoration(
                    hintText: SettingsService.defaultBackendUrl,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 24),

                // --- Save directory ---
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '保存目录',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          provider.selectedDirPath ?? '未选择保存目录',
                          style: TextStyle(
                            fontSize: 13,
                            color: hasDir
                                ? theme.colorScheme.onSurface
                                : theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      TextButton.icon(
                        onPressed: _pickDirectory,
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: Text(
                          hasDir ? '更改' : '选择',
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // --- Start button ---
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    onPressed: hasDir ? _saveAndStart : null,
                    child: const Text(
                      '开始使用',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
