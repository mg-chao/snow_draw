// Tests that verify pubspec dependency hygiene for the snow_draw app.
//
// These tests ensure that removing unused dependencies does not break
// any imports or functionality.
import 'package:flutter_test/flutter_test.dart';

// Dependencies that MUST remain importable:
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

// Internal package dependency:
import 'package:snow_draw_core/draw/utils/lru_cache.dart';

// App-level imports that exercise the dependency graph:
import 'package:snow_draw/grid_toolbar_adapter.dart';
import 'package:snow_draw/snap_toolbar_adapter.dart';

void main() {
  group('snow_draw app dependency smoke tests', () {
    test('flutter_svg is importable', () {
      // flutter_svg is used for custom SVG icons.
      expect(SvgPicture, isNotNull);
    });

    test('flutter_localizations is importable', () {
      // Used for localization delegates in MaterialApp.
      expect(GlobalMaterialLocalizations, isNotNull);
    });

    test('snow_draw_core is importable', () {
      // The core package path dependency must resolve.
      final cache = LruCache<String, int>(maxEntries: 2);
      cache.put('x', 42);
      expect(cache.get('x'), 42);
    });

    test('app adapters are importable', () {
      // Verify the app's own modules compile.
      expect(GridToolbarAdapter, isNotNull);
      expect(SnapToolbarAdapter, isNotNull);
    });
  });
}
