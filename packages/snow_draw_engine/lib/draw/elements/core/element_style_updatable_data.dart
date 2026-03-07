import '../../types/element_style.dart';
import 'element_data.dart';

/// Optional capability for element data payloads that can update style fields.
mixin ElementStyleUpdatableData {
  ElementData withStyleUpdate(ElementStyleUpdate update);
}
