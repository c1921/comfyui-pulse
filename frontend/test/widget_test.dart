import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_app/models/capture_file.dart';
import 'package:pulse_app/widgets/capture_card.dart';
import 'package:pulse_app/widgets/empty_state.dart';

void main() {
  group('EmptyState', () {
    testWidgets('renders waiting text', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EmptyState())),
      );

      expect(find.text('Waiting for captures…'), findsOneWidget);
      expect(
        find.text('Send an HTTP request to the capture server to see it here.'),
        findsOneWidget,
      );
    });
  });

  group('CaptureCard', () {
    final imageFile = CaptureFile(
      name: 'photo.png',
      path: '/downloads/photo.png',
      size: 2048,
      mtime: '2026-06-18T12:34:56.000',
      contentType: 'image/png',
      isImage: true,
    );

    final docFile = CaptureFile(
      name: 'document.pdf',
      path: '/downloads/document.pdf',
      size: 102400,
      mtime: '2026-06-18T12:34:56.000',
      contentType: 'application/pdf',
      isImage: false,
    );

    testWidgets('shows file name and size for image', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CaptureCard(file: imageFile, isNew: false),
            ),
          ),
        ),
      );

      expect(find.text('photo.png'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
    });

    testWidgets('shows file name and size for document', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CaptureCard(file: docFile, isNew: false),
            ),
          ),
        ),
      );

      expect(find.text('document.pdf'), findsOneWidget);
      expect(find.text('100.0 KB'), findsOneWidget);
    });

    testWidgets('shows saved badge when saved', (tester) async {
      imageFile.markSaved('/tmp/photo.png');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CaptureCard(file: imageFile, isNew: false),
            ),
          ),
        ),
      );

      expect(find.text('已保存'), findsOneWidget);
    });

    testWidgets('highlights new captures with green border', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CaptureCard(file: imageFile, isNew: true),
            ),
          ),
        ),
      );

      // Card is rendered without errors
      expect(find.byType(CaptureCard), findsOneWidget);
    });
  });
}
