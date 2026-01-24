import '../../config/draw_config.dart';
import 'element_data.dart';

/// Optional capability for element data payloads that can accept default style.
///
/// This enables the reducer layer to apply [ElementStyleConfig] when creating
/// new elements, without depending on concrete element types.
mixin ElementStyleConfigurableData {
  ElementData withElementStyle(ElementStyleConfig style);
}
