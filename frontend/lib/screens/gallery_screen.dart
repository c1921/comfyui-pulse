import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/capture_provider.dart';
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
    final theme = Theme.of(context);

    return Scaffold(
      body: Consumer<CaptureProvider>(
        builder: (context, provider, child) {
          return Stack(
            children: [
              CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildHeader(context, provider),
                  ),
                  if (provider.selectedDirPath == null &&
                      provider.captures.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildSavePrompt(context),
                    ),
                  if (provider.saveError != null &&
                      provider.saveError!.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                        child: Text(
                          provider.saveError!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ),
                  if (provider.loading)
                    const SliverFillRemaining(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (provider.captures.isEmpty)
                    const SliverFillRemaining(child: EmptyState())
                  else
                    _buildGrid(context, provider),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context, CaptureProvider provider) {
    final theme = Theme.of(context);
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
                          '${provider.captureCount} file${provider.captureCount != 1 ? 's' : ''} received',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                        ),
                        if (provider.loading)
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
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (provider.selectedDirPath == null)
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
                          provider.selectedDirPath!.split('\\').last,
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

  Widget _buildSavePrompt(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.1),
          border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline,
                size: 20, color: Colors.amber.shade300),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '选择保存目录后，新图片将自动写入本地文件夹',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.amber.shade200,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(BuildContext context, CaptureProvider provider) {
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
            final isSaving = provider.savingFiles.contains(file.name);
            return CaptureCard(
              file: file,
              isNew: isNew,
              isSaving: isSaving,
              onTap: file.isImage
                  ? () {
                      final imageIndex =
                          provider.imageCaptures.indexOf(file);
                      if (imageIndex >= 0) {
                        _openLightbox(context, imageIndex);
                      }
                    }
                  : null,
              onSave: () => provider.saveFile(file),
            );
          },
          childCount: provider.captures.length,
        ),
      ),
    );
  }
}
