import 'package:meta/meta.dart';

import 'element_type_id.dart';

/// Type-specific, immutable element payload.
@immutable
abstract class ElementData {
  const ElementData();

  /// Stable runtime identifier for this element type.
  ElementTypeId<ElementData> get typeId;

  /// Serializes the data payload.
  Map<String, dynamic> toJson();
}
