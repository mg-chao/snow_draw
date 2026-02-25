import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_engine.dart';
import 'package:snow_draw_flutter_backend/services/text/flutter_text_layout.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('layoutText paragraph cache respects paint attributes', () {
    const data = TextData(
      text: 'layout-cache-color-regression',
      color: DrawColor(0xFF000000),
    );

    final redLayout = layoutText(
      data: data,
      maxWidth: 320,
      minWidth: 320,
      colorOverride: Colors.red,
      widthBasis: TextWidthBasis.parent,
    );
    final blueLayout = layoutText(
      data: data,
      maxWidth: 320,
      minWidth: 320,
      colorOverride: Colors.blue,
      widthBasis: TextWidthBasis.parent,
    );
    final redLayoutAgain = layoutText(
      data: data,
      maxWidth: 320,
      minWidth: 320,
      colorOverride: Colors.red,
      widthBasis: TextWidthBasis.parent,
    );

    expect(identical(redLayout.paragraph, blueLayout.paragraph), isFalse);
    expect(identical(redLayout.paragraph, redLayoutAgain.paragraph), isTrue);
  });
}
