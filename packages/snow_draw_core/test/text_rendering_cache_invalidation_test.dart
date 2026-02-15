import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/text_rendering_cache_invalidation.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_layout.dart';

void main() {
  setUp(clearTextLayoutCaches);
  tearDown(clearTextLayoutCaches);

  test('invalidateTextRenderingCaches clears cached paragraphs '
      'and notifies repaint listeners', () {
    const data = TextData(text: 'font cache probe', fontSize: 20);
    final first = layoutText(data: data, maxWidth: 320);
    final second = layoutText(data: data, maxWidth: 320);

    expect(
      identical(first.paragraph, second.paragraph),
      isTrue,
      reason: 'Expected baseline cache hit before invalidation.',
    );

    final previousRevision = textRenderingCacheRevisionListenable.value;
    var listenerCalls = 0;
    void onRevision() {
      listenerCalls += 1;
    }

    textRenderingCacheRevisionListenable.addListener(onRevision);
    addTearDown(
      () => textRenderingCacheRevisionListenable.removeListener(onRevision),
    );

    invalidateTextRenderingCaches();

    expect(textRenderingCacheRevisionListenable.value, previousRevision + 1);
    expect(listenerCalls, 1);

    final afterInvalidation = layoutText(data: data, maxWidth: 320);
    expect(
      identical(afterInvalidation.paragraph, second.paragraph),
      isFalse,
      reason: 'Expected cache miss after invalidation.',
    );
  });
}
