import '../../config/draw_config.dart';
import 'element_data.dart';

/// Capability for element data that can apply a default [ElementStyleConfig].
mixin ElementStyleConfigurableData {
  ElementData withElementStyle(ElementStyleConfig style);
}
