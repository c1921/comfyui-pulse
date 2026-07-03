class CaptureFile {
  final String name;
  final String path;
  final int size;
  final String mtime;
  final String contentType;
  final bool isImage;
  bool _saved;
  String? _localPath;

  bool get saved => _saved;
  String? get localPath => _localPath;

  CaptureFile({
    required this.name,
    required this.path,
    required this.size,
    required this.mtime,
    required this.contentType,
    required this.isImage,
    bool saved = false,
    String? localPath,
  })  : _saved = saved,
        _localPath = localPath;

  /// Mark this file as saved to disk at [path].
  void markSaved(String path) {
    _saved = true;
    _localPath = path;
  }

  factory CaptureFile.fromJson(Map<String, dynamic> json) {
    return CaptureFile(
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      size: json['size'] as int? ?? 0,
      mtime: json['mtime'] as String? ?? '',
      contentType: json['content_type'] as String? ?? '',
      isImage: json['is_image'] as bool? ?? false,
    );
  }

  String get formattedSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// Build a full download URL by resolving [path] against [baseUrl].
  String downloadUrl(String baseUrl) =>
      Uri.parse(baseUrl).resolve(path).toString();
}
