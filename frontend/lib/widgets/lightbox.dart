import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/capture_file.dart';

class Lightbox extends StatefulWidget {
  final List<CaptureFile> images;
  final int initialIndex;
  final VoidCallback onClose;

  const Lightbox({
    super.key,
    required this.images,
    required this.initialIndex,
    required this.onClose,
  });

  @override
  State<Lightbox> createState() => _LightboxState();
}

class _LightboxState extends State<Lightbox> {
  late int _currentIndex;
  late PageController _pageController;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _prevImage() {
    if (_currentIndex > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _nextImage() {
    if (_currentIndex < widget.images.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            widget.onClose();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _prevImage();
          } else if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _nextImage();
          }
        }
      },
      child: Stack(
        children: [
          // Image page view
          PageView.builder(
            controller: _pageController,
            itemCount: widget.images.length,
            onPageChanged: (index) {
              setState(() => _currentIndex = index);
            },
            itemBuilder: (context, index) {
              final file = widget.images[index];
              return InteractiveViewer(
                maxScale: 5.0,
                child: Center(
                  child: Image.network(
                    file.downloadUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Center(
                        child: CircularProgressIndicator(
                          value: loadingProgress.expectedTotalBytes != null
                              ? loadingProgress.cumulativeBytesLoaded /
                                  loadingProgress.expectedTotalBytes!
                              : null,
                          color: Colors.white70,
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) => Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.broken_image,
                            size: 64, color: Colors.white54),
                        const SizedBox(height: 8),
                        Text(
                          file.name,
                          style: const TextStyle(color: Colors.white54),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          // Close button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: IconButton(
              icon: const Icon(Icons.close, color: Colors.white70, size: 32),
              onPressed: widget.onClose,
            ),
          ),

          // Left arrow
          if (_currentIndex > 0)
            Positioned(
              left: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.chevron_left,
                      color: Colors.white70, size: 48),
                  onPressed: _prevImage,
                ),
              ),
            ),

          // Right arrow
          if (_currentIndex < widget.images.length - 1)
            Positioned(
              right: 8,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: const Icon(Icons.chevron_right,
                      color: Colors.white70, size: 48),
                  onPressed: _nextImage,
                ),
              ),
            ),

          // Page indicator
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${widget.images.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
