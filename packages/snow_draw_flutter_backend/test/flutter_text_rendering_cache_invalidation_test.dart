import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_engine.dart';
import 'package:snow_draw_flutter_backend/services/text/flutter_text_layout.dart';
import 'package:snow_draw_flutter_backend/services/text/flutter_text_rendering_cache_invalidation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('invalidateTextRenderingCaches clears Flutter text layout caches', () {
    ensureFlutterTextRenderingCacheInvalidatorInstalled();
    clearTextLayoutCaches();

    const textData = TextData(text: 'cache key', fontSize: 20);
    final firstLayout = layoutText(data: textData, maxWidth: 200);
    final secondLayout = layoutText(data: textData, maxWidth: 200);
    expect(identical(firstLayout, secondLayout), isTrue);

    invalidateTextRenderingCaches();

    final thirdLayout = layoutText(data: textData, maxWidth: 200);
    expect(identical(firstLayout, thirdLayout), isFalse);
  });
}
