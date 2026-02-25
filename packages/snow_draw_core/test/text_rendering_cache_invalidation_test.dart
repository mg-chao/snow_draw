import 'package:snow_draw_core/draw/elements/text_rendering_cache_invalidation.dart';
import 'package:test/test.dart';

void main() {
  test('invalidateTextRenderingCaches notifies listeners and callbacks', () {
    final previousRevision = textRenderingCacheRevisionListenable.value;
    var listenerCalls = 0;
    var invalidatorCalls = 0;
    void onRevision() {
      listenerCalls += 1;
    }

    void invalidator() {
      invalidatorCalls += 1;
    }

    textRenderingCacheRevisionListenable.addListener(onRevision);
    registerTextRenderingCacheInvalidator(invalidator);
    addTearDown(
      () => textRenderingCacheRevisionListenable.removeListener(onRevision),
    );
    addTearDown(() => unregisterTextRenderingCacheInvalidator(invalidator));

    invalidateTextRenderingCaches();

    expect(textRenderingCacheRevisionListenable.value, previousRevision + 1);
    expect(listenerCalls, 1);
    expect(invalidatorCalls, 1);
  });
}
