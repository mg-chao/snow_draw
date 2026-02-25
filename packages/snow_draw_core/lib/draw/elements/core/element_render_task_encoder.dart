import 'element_data.dart';
import 'typed_element_render_task_encoder.dart';

/// Alias kept for public API readability.
///
/// Render task encoding now uses the typed base directly.
typedef ElementRenderTaskEncoder<T extends ElementData> =
    TypedElementRenderTaskEncoder<T>;
