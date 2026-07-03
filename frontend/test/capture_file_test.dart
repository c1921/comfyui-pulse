import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_app/models/capture_file.dart';

void main() {
  group('CaptureFile', () {
    final validJson = {
      'name': 'test.png',
      'path': '/downloads/test.png',
      'size': 1024,
      'mtime': '2026-06-18T12:34:56.789000',
      'content_type': 'image/png',
      'is_image': true,
    };

    test('fromJson creates CaptureFile from valid JSON', () {
      final file = CaptureFile.fromJson(validJson);

      expect(file.name, 'test.png');
      expect(file.path, '/downloads/test.png');
      expect(file.size, 1024);
      expect(file.mtime, '2026-06-18T12:34:56.789000');
      expect(file.contentType, 'image/png');
      expect(file.isImage, true);
      expect(file.saved, false);
      expect(file.localPath, isNull);
    });

    test('fromJson handles missing fields with defaults', () {
      final file = CaptureFile.fromJson({});

      expect(file.name, '');
      expect(file.path, '');
      expect(file.size, 0);
      expect(file.mtime, '');
      expect(file.contentType, '');
      expect(file.isImage, false);
      expect(file.saved, false);
      expect(file.localPath, isNull);
    });

    test('formattedSize returns human-readable sizes', () {
      final small = CaptureFile.fromJson({...validJson, 'size': 512});
      expect(small.formattedSize, '512 B');

      final kb = CaptureFile.fromJson({...validJson, 'size': 2048});
      expect(kb.formattedSize, '2.0 KB');

      final mb = CaptureFile.fromJson({...validJson, 'size': 3 * 1024 * 1024});
      expect(mb.formattedSize, '3.0 MB');
    });

    test('downloadUrl resolves path against baseUrl', () {
      final file = CaptureFile.fromJson(validJson);

      expect(file.downloadUrl('http://127.0.0.1:8088'),
          'http://127.0.0.1:8088/downloads/test.png');

      // No double slash when baseUrl ends with /
      expect(file.downloadUrl('http://127.0.0.1:8088/'),
          'http://127.0.0.1:8088/downloads/test.png');
    });

    test('markSaved updates saved and localPath', () {
      final file = CaptureFile.fromJson(validJson);

      expect(file.saved, false);
      expect(file.localPath, isNull);

      file.markSaved('/data/test.png');

      expect(file.saved, true);
      expect(file.localPath, '/data/test.png');
    });
  });
}
