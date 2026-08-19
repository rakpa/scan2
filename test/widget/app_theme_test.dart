import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scan2/core/theme/app_theme.dart';
import 'package:scan2/core/theme/brand.dart';

void main() {
  testWidgets('splash and post-scan share the BrandType scale', (tester) async {
    late TextTheme text;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Builder(
          builder: (context) {
            text = Theme.of(context).textTheme;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(text.displaySmall?.fontSize, BrandType.display.fontSize);
    expect(text.headlineMedium?.fontSize, BrandType.headline.fontSize);
    expect(text.titleLarge?.fontSize, BrandType.title.fontSize);
    expect(text.bodyMedium?.fontSize, BrandType.body.fontSize);
    expect(text.bodySmall?.fontSize, BrandType.caption.fontSize);
    expect(text.bodyMedium?.fontFamily, text.titleLarge?.fontFamily);
    expect(text.bodyMedium?.fontFamily, text.headlineMedium?.fontFamily);
  });
}
