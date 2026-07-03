import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/capture_provider.dart';
import '../screens/settings_dialog.dart';
import '../widgets/capture_card.dart';
import '../widgets/empty_state.dart';
import '../widgets/lightbox.dart';

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CaptureProvider>().initialize();
    });
  }

  void _openLightbox(BuildContext context, int index) {
    final provider = context.read<CaptureProvider>();
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black,
        pageBuilder: (context, animation, secondaryAnimation) {
          return FadeTransition(
            opacity: animation,
            child: Lightbox(
              images: provider.imageCaptures,
              initialIndex: index,
              onClose: () => Navigator.of(context).pop(),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              // Header: captureCount, loading, isConnected, selectedDirPath
              SliverToBoxAdapter(
                child: Selector<CaptureProvider, _HeaderData>(
                  selector: (_, p) => _HeaderData(
                    captureCount: p.captureCount,
                    loading: p.loading,
                    isConnected: p.isConnected,
                    isConnecting: p.isConnecting,
                    selectedDirPath: p.selectedDirPath,
                  ),
                  builder: (context, data, _) =>
                      _buildHeader(context, data),
                ),
              ),
              // Connection error banner (visible when disconnected with captures)
              Selector<CaptureProvider, _ConnectionStatus>(
                shouldRebuild: (prev, next) =>
                    prev.isConnected != next.isConnected ||
                    prev.loading != next.loading ||
                    prev.isConnecting != next.isConnecting ||
                    prev.errorMessage != next.errorMessage,
                selector: (_, p) => _ConnectionStatus(
                  isConnected: p.isConnected,
                  loading: p.loading,
                  isConnecting: p.isConnecting,
                  errorMessage: p.errorMessage,
                ),
                builder: (context, status, _) {
                  if (!status.isConnected &&
                      !status.loading &&
                      !status.isConnecting) {
                    return SliverToBoxAdapter(
                      child: _buildConnectionErrorBanner(
                          context, status.errorMessage, () {
                        context
                            .read<CaptureProvider>()
                            .reconnect();
                      }),
                    );
                  }
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                },
              ),
              // Save error banner
              Selector<CaptureProvider, String?>(
                selector: (_, p) => p.saveError,
                builder: (context, saveError, _) {
                  if (saveError != null && saveError.isNotEmpty) {
                    final theme = Theme.of(context);
                    return SliverToBoxAdapter(
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(24, 0, 24, 8),
                        child: Text(
                          saveError,
                          style:
                              TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    );
                  }
                  return const SliverToBoxAdapter(child: SizedBox.shrink());
                },
              ),
              // Content: loading / empty / grid
              Selector<CaptureProvider, _ContentState>(
                shouldRebuild: (prev, next) =>
                    prev.loading != next.loading ||
                    prev.capturesLength != next.capturesLength ||
                    prev.newNames != next.newNames,
                selector: (_, p) => _ContentState(
                  loading: p.loading,
                  capturesLength: p.captures.length,
                  newNames: p.newNames,
                ),
                builder: (context, contentState, _) {
                  if (contentState.loading) {
                    return const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (contentState.capturesLength == 0) {
                    return const SliverFillRemaining(
                        child: EmptyState());
                  }
                  return Consumer<CaptureProvider>(
                    builder: (context, provider, _) =>
                        _buildGrid(context, provider),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, _HeaderData data) {
    final theme = Theme.of(context);
    final provider = context.read<CaptureProvider>();
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 24,
        right: 24,
        bottom: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Capture Gallery',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${data.captureCount} file${data.captureCount != 1 ? 's' : ''} received',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        if (data.loading)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                        const SizedBox(width: 12),
                        _buildConnectionStatus(
                            theme, data),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (data.selectedDirPath == null)
                FilledButton.tonalIcon(
                  onPressed: () => provider.pickDirectory(),
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text('选择保存目录'),
                )
              else
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle,
                          size: 16, color: Colors.green.shade400),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          data.selectedDirPath!.split('\\').last,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.green.shade300,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.settings, size: 20),
                tooltip: '设置',
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (_) => const SettingsDialog(),
                  );
                },
              ),
              const SizedBox(width: 4),
              OutlinedButton(
                onPressed: () => provider.clearAll(),
                child: const Text('Clear'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionStatus(
      ThemeData theme, _HeaderData data) {
    if (data.isConnecting) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '连接中…',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      );
    }

    if (data.isConnected) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Colors.green.shade400,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '已连接',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.green.shade300,
            ),
          ),
        ],
      );
    }

    // Disconnected
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: Colors.red.shade400,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '连接断开',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.red.shade300,
          ),
        ),
      ],
    );
  }

  Widget _buildConnectionErrorBanner(
      BuildContext context, String errorMessage, VoidCallback onReconnect) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.cloud_off, size: 18, color: Colors.red.shade300),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                errorMessage.isNotEmpty
                    ? errorMessage
                    : '无法连接到后端服务器',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.red.shade200,
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onReconnect,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重连', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: Colors.red.shade300,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, CaptureProvider provider) {
    final imageCaptures = provider.imageCaptures;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 320,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          childAspectRatio: 0.85,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final file = provider.captures[index];
            final isNew = provider.newNames.contains(file.name);
            return CaptureCard(
              file: file,
              isNew: isNew,
              onTap: file.isImage
                  ? () {
                      final imageIndex =
                          imageCaptures.indexOf(file);
                      if (imageIndex >= 0) {
                        _openLightbox(context, imageIndex);
                      }
                    }
                  : null,
            );
          },
          childCount: provider.captures.length,
        ),
      ),
    );
  }
}

/// Selector data: header portion of CaptureProvider state.
class _HeaderData {
  final int captureCount;
  final bool loading;
  final bool isConnected;
  final bool isConnecting;
  final String? selectedDirPath;

  const _HeaderData({
    required this.captureCount,
    required this.loading,
    required this.isConnected,
    required this.isConnecting,
    required this.selectedDirPath,
  });
}

/// Selector data: connection status portion.
class _ConnectionStatus {
  final bool isConnected;
  final bool loading;
  final bool isConnecting;
  final String errorMessage;

  const _ConnectionStatus({
    required this.isConnected,
    required this.loading,
    required this.isConnecting,
    required this.errorMessage,
  });
}

/// Selector data: content (loading / grid) portion.
class _ContentState {
  final bool loading;
  final int capturesLength;
  final Set<String> newNames;

  const _ContentState({
    required this.loading,
    required this.capturesLength,
    required this.newNames,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _ContentState &&
          loading == other.loading &&
          capturesLength == other.capturesLength &&
          newNames == other.newNames;

  @override
  int get hashCode =>
      loading.hashCode ^ capturesLength.hashCode ^ newNames.hashCode;
}
