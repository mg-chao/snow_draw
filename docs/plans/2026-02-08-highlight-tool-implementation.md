# Highlight Tool Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a Highlight tool with rectangle/ellipse shapes, highlight styles, and a global mask rendered as topmost canvas content.

**Architecture:** Add a new Highlight element type in `packages/snow_draw_core`, extend DrawConfig with highlight defaults + mask config, and wire a new tool + style controls in `apps/snow_draw`. Mask rendering lives in static/dynamic painters based on whether dynamic content is active.

**Tech Stack:** Flutter, Dart, melos workspace, `flutter_test`

---

### Task 1: Add failing tests for highlight config defaults

**Files:**
- Create: `packages/snow_draw_core/test/highlight_config_test.dart`

**Step 1: Write the failing test**

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  test('draw config provides highlight defaults', () {
    final config = DrawConfig();

    expect(config.highlightStyle.color, ConfigDefaults.defaultHighlightColor);
    expect(
      config.highlightStyle.textStrokeColor,
      ConfigDefaults.defaultHighlightColor,
    );
    expect(config.highlightStyle.textStrokeWidth, 0);
    expect(config.highlightStyle.highlightShape, HighlightShape.rectangle);

    expect(config.highlight.maskColor, ConfigDefaults.defaultMaskColor);
    expect(config.highlight.maskOpacity, 0);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/highlight_config_test.dart`
Expected: FAIL because highlight config/types do not exist.

**Step 3: Implement minimal code**

- Add `HighlightShape` enum (see Task 2).
- Add highlight defaults and mask config to DrawConfig (Task 2).

**Step 4: Run test to verify it passes**

Run: `flutter test test/highlight_config_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/snow_draw_core/lib/draw/config/draw_config.dart \
  packages/snow_draw_core/lib/draw/types/element_style.dart \
  packages/snow_draw_core/test/highlight_config_test.dart

git commit -m "feat(core): add highlight config defaults"
```

---

### Task 2: Implement highlight config + style fields

**Files:**
- Modify: `packages/snow_draw_core/lib/draw/types/element_style.dart`
- Modify: `packages/snow_draw_core/lib/draw/config/draw_config.dart`
- Create: `packages/snow_draw_core/lib/draw/config/highlight_config.dart` (or add as `part`)

**Step 1: Write the failing test**

(Already done in Task 1.)

**Step 2: Implement minimal code**

- Add `HighlightShape { rectangle, ellipse }` to `element_style.dart`.
- Extend `ElementStyleConfig` with `highlightShape`:
  - Default: `ConfigDefaults.defaultHighlightShape` (rectangle).
  - Add to `copyWith`, `==`, `hashCode`, `toString`.
- Add new defaults in `ConfigDefaults`:
  - `defaultHighlightColor = Color(0xFFF5222D)`
  - `defaultHighlightShape = HighlightShape.rectangle`
  - `defaultMaskColor = Color(0xFF000000)`
- Add `HighlightMaskConfig` (maskColor, maskOpacity) and include in `DrawConfig`:
  - `highlightStyle` (ElementStyleConfig) with `color` and `textStrokeColor` = `defaultHighlightColor`, `textStrokeWidth` = 0.
  - `highlight` (HighlightMaskConfig) with `maskColor` default black, `maskOpacity` default 0.
  - Update `copyWith`, equality, hashCode, `toString`.

**Step 3: Run test to verify it passes**

Run: `flutter test test/highlight_config_test.dart`
Expected: PASS

**Step 4: Commit**

```bash
git add packages/snow_draw_core/lib/draw/types/element_style.dart \
  packages/snow_draw_core/lib/draw/config/draw_config.dart

git commit -m "feat(core): add highlight config fields"
```

---

### Task 3: Add failing tests for HighlightData

**Files:**
- Create: `packages/snow_draw_core/test/highlight_data_test.dart`

**Step 1: Write the failing tests**

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  test('HighlightData.fromJson uses defaults', () {
    final data = HighlightData.fromJson(const {});

    expect(data.shape, ConfigDefaults.defaultHighlightShape);
    expect(data.color, ConfigDefaults.defaultHighlightColor);
    expect(data.strokeColor, ConfigDefaults.defaultHighlightColor);
    expect(data.strokeWidth, 0);
  });

  test('HighlightData.withElementStyle applies highlight style fields', () {
    const style = ElementStyleConfig(
      color: Color(0xFF00FF00),
      textStrokeColor: Color(0xFF0000FF),
      textStrokeWidth: 3,
      highlightShape: HighlightShape.ellipse,
    );

    const data = HighlightData();
    final updated = data.withElementStyle(style) as HighlightData;

    expect(updated.color, style.color);
    expect(updated.strokeColor, style.textStrokeColor);
    expect(updated.strokeWidth, style.textStrokeWidth);
    expect(updated.shape, style.highlightShape);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/highlight_data_test.dart`
Expected: FAIL because HighlightData is missing.

**Step 3: Implement minimal code**

- Add `HighlightData` class with:
  - `shape`, `color`, `strokeColor`, `strokeWidth`.
  - `fromJson`/`toJson` mapping.
  - `withElementStyle` using `ElementStyleConfig`.

**Step 4: Run test to verify it passes**

Run: `flutter test test/highlight_data_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/snow_draw_core/lib/draw/elements/types/highlight/highlight_data.dart \
  packages/snow_draw_core/test/highlight_data_test.dart

git commit -m "feat(core): add highlight data"
```

---

### Task 4: Add failing tests for Highlight style updates

**Files:**
- Modify: `packages/snow_draw_core/test/highlight_data_test.dart`

**Step 1: Write the failing test**

```dart
  test('HighlightData.withStyleUpdate applies highlight shape and strokes', () {
  const data = HighlightData();
  const update = ElementStyleUpdate(
    color: Color(0xFF112233),
    textStrokeColor: Color(0xFF445566),
    textStrokeWidth: 4,
    highlightShape: HighlightShape.ellipse,
  );

  final updated = data.withStyleUpdate(update) as HighlightData;

  expect(updated.color, update.color);
  expect(updated.strokeColor, update.textStrokeColor);
  expect(updated.strokeWidth, update.textStrokeWidth);
  expect(updated.shape, update.highlightShape);
});
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/highlight_data_test.dart`
Expected: FAIL because ElementStyleUpdate doesn’t include highlightShape / HighlightData update not implemented.

**Step 3: Implement minimal code**

- Add `highlightShape` to `ElementStyleUpdate` (fields, constructor, `copyWith`, `isEmpty`).
- Update reducer style handler to pass `highlightShape` into `ElementStyleUpdate`.
- Update `HighlightData.withStyleUpdate` to use `update.highlightShape`.

**Step 4: Run test to verify it passes**

Run: `flutter test test/highlight_data_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/snow_draw_core/lib/draw/types/element_style.dart \
  packages/snow_draw_core/lib/draw/reducers/element/style_handler.dart \
  packages/snow_draw_core/lib/draw/elements/types/highlight/highlight_data.dart \
  packages/snow_draw_core/test/highlight_data_test.dart

git commit -m "feat(core): support highlight style updates"
```

---

### Task 5: Add failing tests for Highlight hit testing

**Files:**
- Create: `packages/snow_draw_core/test/highlight_hit_tester_test.dart`

**Step 1: Write the failing tests**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_hit_tester.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  const rect = DrawRect(minX: 0, minY: 0, maxX: 100, maxY: 100);
  const element = ElementState(
    id: 'h1',
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: HighlightData(shape: HighlightShape.rectangle),
  );

  test('rectangle highlight hits inside', () {
    const tester = HighlightHitTester();
    final hit = tester.hitTest(
      element: element,
      position: const DrawPoint(x: 50, y: 50),
    );
    expect(hit, isTrue);
  });

  test('ellipse highlight misses outside', () {
    const tester = HighlightHitTester();
    const ellipseElement = ElementState(
      id: 'h2',
      rect: rect,
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: HighlightData(shape: HighlightShape.ellipse),
    );
    final hit = tester.hitTest(
      element: ellipseElement,
      position: const DrawPoint(x: 100, y: 0),
    );
    expect(hit, isFalse);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/highlight_hit_tester_test.dart`
Expected: FAIL because hit tester does not exist.

**Step 3: Implement minimal code**

- Add `HighlightHitTester`:
  - Rectangle: similar to `RectangleHitTester` (stroke first, fill next).
  - Ellipse: use ellipse equation for stroke + fill.

**Step 4: Run test to verify it passes**

Run: `flutter test test/highlight_hit_tester_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/snow_draw_core/lib/draw/elements/types/highlight/highlight_hit_tester.dart \
  packages/snow_draw_core/test/highlight_hit_tester_test.dart

git commit -m "feat(core): add highlight hit tester"
```

---

### Task 6: Add failing test for multiply rendering

**Files:**
- Create: `packages/snow_draw_core/test/highlight_renderer_test.dart`

**Step 1: Write the failing test**

```dart
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_renderer.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('highlight renderer uses multiply blend', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const size = ui.Size(10, 10);

    // Background: mid gray.
    final bgPaint = ui.Paint()..color = const ui.Color(0xFF808080);
    canvas.drawRect(ui.Rect.fromLTWH(0, 0, size.width, size.height), bgPaint);

    const element = ElementState(
      id: 'h1',
      rect: DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: HighlightData(
        shape: HighlightShape.rectangle,
        color: ui.Color(0xFFFF0000),
        strokeWidth: 0,
      ),
    );

    const renderer = HighlightRenderer();
    renderer.render(canvas: canvas, element: element, scaleFactor: 1);

    final picture = recorder.endRecording();
    final image = await picture.toImage(10, 10);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(bytes, isNotNull);

    final data = bytes!;
    // Sample center pixel.
    final offset = ((5 * 10) + 5) * 4;
    final r = data.getUint8(offset);
    final g = data.getUint8(offset + 1);
    final b = data.getUint8(offset + 2);

    // Multiply of red (255,0,0) over 128 gray -> (128,0,0).
    expect(r, 128);
    expect(g, 0);
    expect(b, 0);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/highlight_renderer_test.dart`
Expected: FAIL because renderer does not exist.

**Step 3: Implement minimal code**

- Add `HighlightRenderer`:
  - Use `BlendMode.multiply` for fill and stroke.
  - Draw rectangle or oval based on shape.
  - Respect rotation and element opacity.

**Step 4: Run test to verify it passes**

Run: `flutter test test/highlight_renderer_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/snow_draw_core/lib/draw/elements/types/highlight/highlight_renderer.dart \
  packages/snow_draw_core/test/highlight_renderer_test.dart

git commit -m "feat(core): add highlight renderer"
```

---

### Task 7: Register highlight element

**Files:**
- Create: `packages/snow_draw_core/test/highlight_registration_test.dart`
- Modify: `packages/snow_draw_core/lib/draw/elements/registration.dart`
- Modify: `packages/snow_draw_core/lib/draw/elements/elements.dart`
- Create: `packages/snow_draw_core/lib/draw/elements/types/highlight/highlight_definition.dart`
- Create: `packages/snow_draw_core/lib/draw/elements/types/highlight/highlight.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';

void main() {
  test('highlight is registered as a built-in element', () {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);

    expect(registry.get(HighlightData.typeIdToken), isNotNull);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/highlight_registration_test.dart`
Expected: FAIL because highlight definition is not registered.

**Step 3: Implement minimal code**

- Add highlight definition using `RectCreationStrategy`.
- Export highlight elements in `elements.dart`.
- Register in `registerBuiltInElements`.

**Step 4: Run test to verify it passes**

Run: `flutter test test/highlight_registration_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/snow_draw_core/lib/draw/elements/registration.dart \
  packages/snow_draw_core/lib/draw/elements/elements.dart \
  packages/snow_draw_core/lib/draw/elements/types/highlight \
  packages/snow_draw_core/test/highlight_registration_test.dart

git commit -m "feat(core): register highlight element"
```

---

### Task 8: Ensure highlight creation uses highlight defaults

**Files:**
- Create: `packages/snow_draw_core/test/highlight_create_element_test.dart`
- Modify: `packages/snow_draw_core/lib/draw/reducers/interaction/create/create_element_reducer.dart`

**Step 1: Write the failing test**

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/core/dependency_interfaces.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/reducers/interaction/create/create_element_reducer.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/utils/id_generator.dart';

class _Deps implements CreateElementReducerDeps {
  _Deps({
    required this.config,
    required this.elementRegistry,
    required this.idGenerator,
  });

  @override
  final DrawConfig config;

  @override
  final ElementRegistry elementRegistry;

  @override
  final IdGenerator idGenerator;
}

void main() {
  test('create element uses highlight defaults', () {
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);

    final config = DrawConfig(
      highlightStyle: const ElementStyleConfig(
        color: Color(0xFF00FF00),
        textStrokeColor: Color(0xFF0000FF),
        textStrokeWidth: 3,
        highlightShape: HighlightShape.ellipse,
        opacity: 0.4,
      ),
    );

    final deps = _Deps(
      config: config,
      elementRegistry: registry,
      idGenerator: SequentialIdGenerator().call,
    );

    final reducer = CreateElementReducer();
    final next = reducer.reduce(
      DrawState.initial(),
      const CreateElement(
        typeId: HighlightData.typeIdToken,
        position: DrawPoint(x: 10, y: 10),
      ),
      deps,
    );

    expect(next, isNotNull);
    final interaction = next!.application.interaction;
    expect(interaction, isA<CreatingState>());

    final creating = interaction as CreatingState;
    final data = creating.element.data as HighlightData;
    expect(data.color, const Color(0xFF00FF00));
    expect(data.strokeColor, const Color(0xFF0000FF));
    expect(data.strokeWidth, 3);
    expect(data.shape, HighlightShape.ellipse);
    expect(creating.element.opacity, 0.4);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/highlight_create_element_test.dart`
Expected: FAIL because highlight defaults are not used for creation.

**Step 3: Implement minimal code**

- Update `_resolveStyleDefaults` in `create_element_reducer.dart` to return
  `config.highlightStyle` when `typeId` is `HighlightData.typeIdToken`.

**Step 4: Run test to verify it passes**

Run: `flutter test test/highlight_create_element_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/snow_draw_core/lib/draw/reducers/interaction/create/create_element_reducer.dart \
  packages/snow_draw_core/test/highlight_create_element_test.dart

git commit -m "feat(core): apply highlight defaults on create"
```

---

### Task 9: Add highlight mask layer resolver

**Files:**
- Create: `packages/snow_draw_core/lib/ui/canvas/highlight_mask_visibility.dart`
- Create: `packages/snow_draw_core/test/highlight_mask_visibility_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/ui/canvas/highlight_mask_visibility.dart';

void main() {
  test('mask layer resolves to none when no highlights', () {
    final layer = resolveHighlightMaskLayer(
      hasHighlights: false,
      hasDynamicContent: false,
      config: const HighlightMaskConfig(maskOpacity: 1),
    );
    expect(layer, HighlightMaskLayer.none);
  });

  test('mask layer resolves to none when opacity is zero', () {
    final layer = resolveHighlightMaskLayer(
      hasHighlights: true,
      hasDynamicContent: false,
      config: const HighlightMaskConfig(maskOpacity: 0),
    );
    expect(layer, HighlightMaskLayer.none);
  });

  test('mask layer resolves to static when no dynamic content', () {
    final layer = resolveHighlightMaskLayer(
      hasHighlights: true,
      hasDynamicContent: false,
      config: const HighlightMaskConfig(maskOpacity: 0.5),
    );
    expect(layer, HighlightMaskLayer.staticLayer);
  });

  test('mask layer resolves to dynamic when dynamic content exists', () {
    final layer = resolveHighlightMaskLayer(
      hasHighlights: true,
      hasDynamicContent: true,
      config: const HighlightMaskConfig(maskOpacity: 0.5),
    );
    expect(layer, HighlightMaskLayer.dynamicLayer);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/highlight_mask_visibility_test.dart`
Expected: FAIL because resolver does not exist.

**Step 3: Implement minimal code**

- Add `HighlightMaskLayer` enum (`none`, `staticLayer`, `dynamicLayer`).
- Add `resolveHighlightMaskLayer` that returns:
  - `none` when `!hasHighlights` or `config.maskOpacity <= 0`
  - `dynamicLayer` when `hasDynamicContent` is true
  - `staticLayer` otherwise

**Step 4: Run test to verify it passes**

Run: `flutter test test/highlight_mask_visibility_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/snow_draw_core/lib/ui/canvas/highlight_mask_visibility.dart \
  packages/snow_draw_core/test/highlight_mask_visibility_test.dart

git commit -m "feat(core): add highlight mask layer resolver"
```

---

### Task 10: Render the highlight mask on the correct canvas layer

**Files:**
- Create: `packages/snow_draw_core/lib/ui/canvas/highlight_mask_painter.dart`
- Create: `packages/snow_draw_core/test/highlight_mask_painter_test.dart`
- Modify: `packages/snow_draw_core/lib/ui/canvas/render_keys.dart`
- Modify: `packages/snow_draw_core/lib/ui/canvas/plugin_draw_canvas.dart`
- Modify: `packages/snow_draw_core/lib/ui/canvas/static_canvas_painter.dart`
- Modify: `packages/snow_draw_core/lib/ui/canvas/dynamic_canvas_painter.dart`

**Step 1: Write the failing test**

```dart
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/draw_state_view.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/ui/canvas/highlight_mask_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('highlight mask clears holes for highlight shapes', () async {
    const element = ElementState(
      id: 'h1',
      rect: DrawRect(minX: 5, minY: 5, maxX: 15, maxY: 15),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: HighlightData(shape: HighlightShape.rectangle),
    );

    final state = DrawState(
      domain: DrawState.initial().domain.copyWith(
        document: DrawState.initial().domain.document.copyWith(
          elements: [element],
        ),
      ),
      application: DrawState.initial().application.copyWith(
        interaction: const IdleState(),
      ),
    );
    final view = DrawStateView.fromState(state);
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);

    paintHighlightMask(
      canvas: canvas,
      stateView: view,
      viewportRect: const DrawRect(minX: 0, minY: 0, maxX: 20, maxY: 20),
      maskConfig: const HighlightMaskConfig(
        maskColor: ui.Color(0xFF000000),
        maskOpacity: 1,
      ),
      creatingElement: null,
    );

    final image = await recorder.endRecording().toImage(20, 20);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(bytes, isNotNull);

    final data = bytes!;
    int pixelAt(int x, int y, int channel) =>
        data.getUint8(((y * 20) + x) * 4 + channel);

    // Outside highlight: mask is opaque black.
    expect(pixelAt(1, 1, 3), 255);

    // Inside highlight: cleared (alpha == 0).
    expect(pixelAt(10, 10, 3), 0);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/highlight_mask_painter_test.dart`
Expected: FAIL because mask painter does not exist.

**Step 3: Implement minimal code**

- Create `highlight_mask_painter.dart`:
  - Collect highlight elements from `stateView.elements`, applying
    `stateView.effectiveElement` for previews.
  - Include `creatingElement` if it is a highlight.
  - Skip if no highlights or `maskOpacity <= 0`.
  - Draw a saveLayer over `viewportRect` and fill with mask color
    (`maskColor` alpha multiplied by `maskOpacity`).
  - Clear highlight holes using `BlendMode.clear` and the expanded highlight
    bounds (inflate by `strokeWidth / 2`), with rotation applied.
- Update `render_keys.dart`:
  - Add `highlightMaskLayer` and `highlightMaskConfig` to
    `StaticCanvasRenderKey` and `DynamicCanvasRenderKey`, and include them in
    equality/hashCode.
- Update `plugin_draw_canvas.dart`:
  - Compute `hasHighlights` (document + preview + creating).
  - Compute `hasDynamicContent` (`dynamicLayerStartIndex != null` or
    `creatingElement != null`).
  - Use `resolveHighlightMaskLayer` from Task 9 to decide layer.
  - Pass `highlightMaskLayer` and `config.highlight` into render keys.
- Update `static_canvas_painter.dart`:
  - After rendering elements, call `paintHighlightMask` when
    `renderKey.highlightMaskLayer == HighlightMaskLayer.staticLayer`.
- Update `dynamic_canvas_painter.dart`:
  - After dynamic elements and creating element, call `paintHighlightMask` when
    `renderKey.highlightMaskLayer == HighlightMaskLayer.dynamicLayer`, before
    overlays.

**Step 4: Run test to verify it passes**

Run: `flutter test test/highlight_mask_painter_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add packages/snow_draw_core/lib/ui/canvas/highlight_mask_painter.dart \
  packages/snow_draw_core/lib/ui/canvas/render_keys.dart \
  packages/snow_draw_core/lib/ui/canvas/plugin_draw_canvas.dart \
  packages/snow_draw_core/lib/ui/canvas/static_canvas_painter.dart \
  packages/snow_draw_core/lib/ui/canvas/dynamic_canvas_painter.dart \
  packages/snow_draw_core/test/highlight_mask_painter_test.dart

git commit -m "feat(core): render highlight mask"
```

---

### Task 11: Add Highlight tool to the app toolbar and canvas mapping

**Files:**
- Modify: `apps/snow_draw/lib/tool_controller.dart`
- Modify: `apps/snow_draw/lib/widgets/canvas_layer.dart`
- Modify: `apps/snow_draw/lib/widgets/main_toolbar.dart`
- Modify: `apps/snow_draw/lib/l10n/app_localizations.dart`
- Create: `apps/snow_draw/test/main_toolbar_highlight_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/l10n/app_localizations.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/widgets/main_toolbar.dart';

void main() {
  testWidgets('main toolbar shows highlight tool button', (tester) async {
    final controller = ToolController();
    final strings = AppLocalizations(const Locale('en'));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MainToolbar(strings: strings, toolController: controller),
        ),
      ),
    );

    expect(find.byTooltip('Highlight'), findsOneWidget);

    await tester.tap(find.byTooltip('Highlight'));
    await tester.pumpAndSettle();

    expect(controller.value, ToolType.highlight);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/main_toolbar_highlight_test.dart`
Expected: FAIL because the highlight tool is not wired in.

**Step 3: Implement minimal code**

- Add `highlight` to `ToolType` enum in `tool_controller.dart`.
- Map `ToolType.highlight` to `HighlightData.typeIdToken` in
  `canvas_layer.dart`.
- Add highlight button in `main_toolbar.dart` with a Material icon (e.g.
  `Icons.highlight`) and `strings.toolHighlight` tooltip.
- Add `toolHighlight` string to `app_localizations.dart`.

**Step 4: Run test to verify it passes**

Run: `flutter test test/main_toolbar_highlight_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/snow_draw/lib/tool_controller.dart \
  apps/snow_draw/lib/widgets/canvas_layer.dart \
  apps/snow_draw/lib/widgets/main_toolbar.dart \
  apps/snow_draw/lib/l10n/app_localizations.dart \
  apps/snow_draw/test/main_toolbar_highlight_test.dart

git commit -m "feat(app): add highlight tool entry"
```

---

### Task 12: Add highlight style + mask state and property descriptors

**Files:**
- Modify: `apps/snow_draw/lib/style_toolbar_state.dart`
- Modify: `apps/snow_draw/lib/toolbar_adapter.dart`
- Modify: `apps/snow_draw/lib/property_descriptor.dart`
- Modify: `apps/snow_draw/lib/property_descriptors.dart`
- Modify: `apps/snow_draw/lib/property_initialization.dart`
- Create: `apps/snow_draw/test/highlight_property_descriptors_test.dart`

**Step 1: Write the failing test**

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/property_descriptor.dart';
import 'package:snow_draw/property_initialization.dart';
import 'package:snow_draw/property_registry.dart';
import 'package:snow_draw/style_toolbar_state.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  test('highlight properties appear in the expected order', () {
    initializePropertyRegistry();

    const highlightValues = HighlightStyleValues(
      color: MixedValue(value: Color(0xFFF5222D), isMixed: false),
      highlightShape: MixedValue(
        value: HighlightShape.rectangle,
        isMixed: false,
      ),
      textStrokeColor: MixedValue(value: Color(0xFFF5222D), isMixed: false),
      textStrokeWidth: MixedValue(value: 0, isMixed: false),
      opacity: MixedValue(value: 1, isMixed: false),
    );

    const context = StylePropertyContext(
      rectangleStyleValues: RectangleStyleValues(
        color: MixedValue(value: Color(0xFF000000), isMixed: false),
        fillColor: MixedValue(value: Color(0x00000000), isMixed: false),
        strokeStyle: MixedValue(value: StrokeStyle.solid, isMixed: false),
        fillStyle: MixedValue(value: FillStyle.solid, isMixed: false),
        strokeWidth: MixedValue(value: 2, isMixed: false),
        cornerRadius: MixedValue(value: 4, isMixed: false),
        opacity: MixedValue(value: 1, isMixed: false),
      ),
      arrowStyleValues: ArrowStyleValues(
        color: MixedValue(value: Color(0xFF000000), isMixed: false),
        strokeWidth: MixedValue(value: 2, isMixed: false),
        strokeStyle: MixedValue(value: StrokeStyle.solid, isMixed: false),
        arrowType: MixedValue(value: ArrowType.straight, isMixed: false),
        startArrowhead: MixedValue(
          value: ArrowheadStyle.none,
          isMixed: false,
        ),
        endArrowhead: MixedValue(
          value: ArrowheadStyle.standard,
          isMixed: false,
        ),
        opacity: MixedValue(value: 1, isMixed: false),
      ),
      lineStyleValues: LineStyleValues(
        color: MixedValue(value: Color(0xFF000000), isMixed: false),
        fillColor: MixedValue(value: Color(0x00000000), isMixed: false),
        fillStyle: MixedValue(value: FillStyle.solid, isMixed: false),
        strokeWidth: MixedValue(value: 2, isMixed: false),
        strokeStyle: MixedValue(value: StrokeStyle.solid, isMixed: false),
        opacity: MixedValue(value: 1, isMixed: false),
      ),
      freeDrawStyleValues: LineStyleValues(
        color: MixedValue(value: Color(0xFF000000), isMixed: false),
        fillColor: MixedValue(value: Color(0x00000000), isMixed: false),
        fillStyle: MixedValue(value: FillStyle.solid, isMixed: false),
        strokeWidth: MixedValue(value: 2, isMixed: false),
        strokeStyle: MixedValue(value: StrokeStyle.solid, isMixed: false),
        opacity: MixedValue(value: 1, isMixed: false),
      ),
      textStyleValues: TextStyleValues(
        color: MixedValue(value: Color(0xFF000000), isMixed: false),
        fontSize: MixedValue(value: 16, isMixed: false),
        fontFamily: MixedValue(value: '', isMixed: false),
        horizontalAlign: MixedValue(
          value: TextHorizontalAlign.left,
          isMixed: false,
        ),
        verticalAlign: MixedValue(
          value: TextVerticalAlign.center,
          isMixed: false,
        ),
        fillColor: MixedValue(value: Color(0x00000000), isMixed: false),
        fillStyle: MixedValue(value: FillStyle.solid, isMixed: false),
        textStrokeColor: MixedValue(value: Color(0xFFF8F4EC), isMixed: false),
        textStrokeWidth: MixedValue(value: 0, isMixed: false),
        cornerRadius: MixedValue(value: 0, isMixed: false),
        opacity: MixedValue(value: 1, isMixed: false),
      ),
      serialNumberStyleValues: SerialNumberStyleValues(
        color: MixedValue(value: Color(0xFF000000), isMixed: false),
        fillColor: MixedValue(value: Color(0x00000000), isMixed: false),
        fillStyle: MixedValue(value: FillStyle.solid, isMixed: false),
        fontSize: MixedValue(value: 16, isMixed: false),
        fontFamily: MixedValue(value: '', isMixed: false),
        number: MixedValue(value: 1, isMixed: false),
        opacity: MixedValue(value: 1, isMixed: false),
      ),
      highlightStyleValues: highlightValues,
      rectangleDefaults: ElementStyleConfig(),
      arrowDefaults: ElementStyleConfig(),
      lineDefaults: ElementStyleConfig(),
      freeDrawDefaults: ElementStyleConfig(),
      textDefaults: ElementStyleConfig(),
      serialNumberDefaults: ElementStyleConfig(),
      highlightDefaults: ElementStyleConfig(
        color: Color(0xFFF5222D),
        textStrokeColor: Color(0xFFF5222D),
        textStrokeWidth: 0,
        highlightShape: HighlightShape.rectangle,
      ),
      highlightMask: HighlightMaskConfig(
        maskColor: Color(0xFF000000),
        maskOpacity: 0.4,
      ),
      selectedElementTypes: {ElementType.highlight},
      currentTool: ToolType.highlight,
    );

    final properties = PropertyRegistry.instance.getApplicableProperties(
      context,
    );
    final ids = properties.map((p) => p.id).toList();

    expect(
      ids,
      [
        'color',
        'highlightShape',
        'highlightTextStrokeWidth',
        'highlightTextStrokeColor',
        'opacity',
        'maskColor',
        'maskOpacity',
      ],
    );
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/highlight_property_descriptors_test.dart`
Expected: FAIL because highlight properties and context fields do not exist.

**Step 3: Implement minimal code**

- `style_toolbar_state.dart`:
  - Add `HighlightStyleValues` with `color`, `highlightShape`,
    `textStrokeColor`, `textStrokeWidth`, and `opacity`.
  - Extend `StyleToolbarState` with `highlightStyle`,
    `highlightStyleValues`, `highlightMask`, and `hasSelectedHighlights`.
- `property_descriptor.dart`:
  - Add `ElementType.highlight`.
  - Extend `StylePropertyContext` with `highlightStyleValues`,
    `highlightDefaults`, and `highlightMask`.
- `toolbar_adapter.dart`:
  - Track selected highlight elements and add `_resolveHighlightStyles()`.
  - Update `_buildState` and `_handleConfigChange` to include highlight
    values and mask config.
  - Extend `applyStyleUpdate` to accept `highlightShape`, `maskColor`, and
    `maskOpacity`, dispatching `UpdateElementsStyle` with `highlightShape`
    but updating mask config only via `UpdateConfig`.
  - Update `_updateStyleConfig` to update `highlightStyle` and
    `highlight` (mask config) when highlight tool/selection is active.
- `property_descriptors.dart`:
  - Include highlight in `ColorPropertyDescriptor` and
    `OpacityPropertyDescriptor` extracts/defaults.
  - Add `HighlightShapePropertyDescriptor`, `HighlightTextStrokeWidth`,
    `HighlightTextStrokeColor`, `MaskColorPropertyDescriptor`,
    `MaskOpacityPropertyDescriptor`.
- `property_initialization.dart`:
  - Register highlight properties right after `ColorPropertyDescriptor`,
    and `maskColor`/`maskOpacity` immediately after `OpacityPropertyDescriptor`.

**Step 4: Run test to verify it passes**

Run: `flutter test test/highlight_property_descriptors_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/snow_draw/lib/style_toolbar_state.dart \
  apps/snow_draw/lib/toolbar_adapter.dart \
  apps/snow_draw/lib/property_descriptor.dart \
  apps/snow_draw/lib/property_descriptors.dart \
  apps/snow_draw/lib/property_initialization.dart \
  apps/snow_draw/test/highlight_property_descriptors_test.dart

git commit -m "feat(app): add highlight style and mask properties"
```

---

### Task 13: Show highlight controls in the style toolbar

**Files:**
- Modify: `apps/snow_draw/lib/widgets/style_toolbar.dart`
- Modify: `apps/snow_draw/lib/l10n/app_localizations.dart`
- Create: `apps/snow_draw/test/style_toolbar_highlight_test.dart`

**Step 1: Write the failing test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/l10n/app_localizations.dart';
import 'package:snow_draw/property_initialization.dart';
import 'package:snow_draw/tool_controller.dart';
import 'package:snow_draw/toolbar_adapter.dart';
import 'package:snow_draw/widgets/style_toolbar.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';

void main() {
  testWidgets('style toolbar shows highlight controls', (tester) async {
    initializePropertyRegistry();

    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final context = DrawContext.withDefaults(elementRegistry: registry);
    final store = DefaultDrawStore(context: context);
    final adapter = StyleToolbarAdapter(store: store);
    final toolController = ToolController(ToolType.highlight);

    addTearDown(adapter.dispose);
    addTearDown(store.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StyleToolbar(
            strings: AppLocalizations(const Locale('en')),
            adapter: adapter,
            toolController: toolController,
            size: const Size(800, 600),
            width: 280,
            topInset: 0,
            bottomInset: 0,
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Highlight Shape'), findsOneWidget);
    expect(find.text('Highlight Text Stroke Width'), findsOneWidget);
    expect(find.text('Highlight Text Stroke Color'), findsOneWidget);
    expect(find.text('Mask Color'), findsOneWidget);
    expect(find.text('Mask Opacity'), findsOneWidget);
  });
}
```

**Step 2: Run test to verify it fails**

Run: `flutter test test/style_toolbar_highlight_test.dart`
Expected: FAIL because highlight labels/controls are missing.

**Step 3: Implement minimal code**

- `app_localizations.dart`:
  - Add strings: `highlightShape`, `highlightShapeRectangle`,
    `highlightShapeEllipse`, `highlightTextStrokeWidth`,
    `highlightTextStrokeColor`, `maskColor`, `maskOpacity`.
- `style_toolbar.dart`:
  - Include highlight in `show*Controls` and toolbar visibility logic.
  - Add switch cases for:
    - `highlightShape` (rectangle/ellipse options).
    - `highlightTextStrokeWidth` (None/Small/Medium/Large; values 0/2/3/5).
    - `highlightTextStrokeColor` (use `_defaultColorPalette`).
    - `maskColor` (use `_defaultColorPalette`).
    - `maskOpacity` (slider 0..1).
  - Hide `highlightTextStrokeColor` when highlight stroke width is 0 (match
    existing text-stroke behavior).
  - Extend `_applyStyleUpdate` to accept `highlightShape`, `maskColor`,
    `maskOpacity` and forward them to the adapter.

**Step 4: Run test to verify it passes**

Run: `flutter test test/style_toolbar_highlight_test.dart`
Expected: PASS

**Step 5: Commit**

```bash
git add apps/snow_draw/lib/widgets/style_toolbar.dart \
  apps/snow_draw/lib/l10n/app_localizations.dart \
  apps/snow_draw/test/style_toolbar_highlight_test.dart

git commit -m "feat(app): show highlight style controls"
```

---

### Task 14: Verification

**Files:**
- None (verification only)

**Step 1: Run core tests**

Run: `melos exec --scope snow_draw_core -- flutter test`
Expected: PASS

**Step 2: Run app tests**

Run: `melos exec --scope snow_draw -- flutter test`
Expected: PASS

**Step 3: Run lint**

Run: `melos run lint`
Expected: PASS
