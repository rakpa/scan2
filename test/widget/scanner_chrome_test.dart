import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/core/theme/app_theme.dart';
import 'package:scan2/core/theme/brand.dart';
import 'package:scan2/features/camera/domain/scan_mode.dart';
import 'package:scan2/features/camera/presentation/widgets/scanner_chrome.dart';

void main() {
  testWidgets('scanner chrome matches Screen 9', (tester) async {
    var flashTaps = 0;
    var closed = false;
    var gallery = false;
    var auto = false;
    var detect = false;
    var mode = ScanMode.document;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Column(
            children: [
              ScannerTopBar(
                flash: ScannerFlash.off,
                onClose: () => closed = true,
                onToggleFlash: () => flashTaps++,
              ),
              AutoDetectPill(enabled: true, onToggle: () => detect = true),
              const AlignHint(visible: true),
              ScannerBottomBar(
                mode: mode,
                autoCapture: true,
                capturing: false,
                holdProgress: 0,
                onModeSelected: (m) => mode = m,
                onGallery: () => gallery = true,
                onShutter: () {},
                onToggleAuto: () => auto = true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Scan Document'), findsOneWidget);
    expect(find.text('Auto-detect'), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('Align document within the frame'), findsOneWidget);
    expect(find.text('ID Card'), findsOneWidget);
    expect(find.text('Document'), findsOneWidget);
    expect(find.text('Book'), findsOneWidget);
    expect(find.text('Whiteboard'), findsOneWidget);
    expect(find.text('Gallery'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);

    final document = tester.widget<Text>(find.text('Document'));
    expect(document.style?.color, Brand.blue);

    await tester.tap(find.byTooltip('Close'));
    await tester.tap(find.byTooltip('Flash off'));
    await tester.tap(find.text('Auto-detect'));
    await tester.tap(find.text('Gallery'));
    await tester.tap(find.text('Auto'));
    await tester.tap(find.text('Book'));
    await tester.pump();

    expect(closed, isTrue);
    expect(flashTaps, 1);
    expect(detect, isTrue);
    expect(gallery, isTrue);
    expect(auto, isTrue);
    expect(mode, ScanMode.book);
  });

  test('flash cycles Off, On, Auto', () {
    expect(ScannerFlash.off.next, ScannerFlash.on);
    expect(ScannerFlash.on.next, ScannerFlash.auto);
    expect(ScannerFlash.auto.next, ScannerFlash.off);
  });

  test('document is the default scan mode', () {
    expect(ScanMode.document.label, 'Document');
    expect(
      ScanMode.idCard.minAutoCaptureArea,
      lessThan(ScanMode.document.minAutoCaptureArea),
    );
  });
}
