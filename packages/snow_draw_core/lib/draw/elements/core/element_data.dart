import 'package:meta/meta.dart';

import 'element_type_id.dart';

/// Type-specific, immutable element payload.
///
/// Each element type can define its own data class (e.g. rectangle, ellipse,
/// text). The [typeId] is used as the stable runtime identifier and lookup key
/// for render/hit-test definitions.
@immutable
abstract class ElementData {
  const ElementData();

  /// Stable runtime identifier for this element type (e.g. `"rectangle"`).
  ElementTypeId<ElementData> get typeId;

  /// Serializes the data payload.
  ///
  /// Consumers should include [typeId] (usually `typeId.value`) so that data
  /// can be deserialized via a registry dispatch in the future.
  Map<String, dynamic> toJson();
}
