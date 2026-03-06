import '../elements/types/arrow/arrow_like_data.dart';
import '../elements/types/text/text_data.dart';
import '../models/element_state.dart';
import '../types/element_style.dart';

/// Describes the effective element state for a single current selection.
///
/// The profile exposes normalized flags used by selection hit-testing and
/// overlay rendering so those paths share identical branch logic.
class SingleSelectionProfile {
  const SingleSelectionProfile._({
    this.element,
    this.arrowData,
    this.isText = false,
  });

  /// Profile used when selection is empty or has multiple ids.
  static const none = SingleSelectionProfile._();

  /// Builds a profile for [element].
  factory SingleSelectionProfile.fromElement(ElementState? element) {
    if (element == null) {
      return none;
    }

    final data = element.data;
    return switch (data) {
      final ConnectorData arrow => SingleSelectionProfile._(
        element: element,
        arrowData: arrow,
      ),
      TextData _ => SingleSelectionProfile._(element: element, isText: true),
      _ => SingleSelectionProfile._(element: element),
    };
  }

  /// Selected element after preview overrides are applied.
  final ElementState? element;

  /// Arrow payload for a selected arrow/line element.
  final ConnectorData? arrowData;

  /// Whether the selected element is text.
  final bool isText;

  /// Whether the selected element is arrow-like.
  bool get isArrow => arrowData != null;

  /// True for line/arrow elements with exactly two control points.
  bool get isTwoPointArrow => arrowData?.points.length == 2;

  /// True for elbow arrows.
  bool get isElbowArrow => arrowData?.arrowType == ArrowType.elbow;

  /// Additional corner-handle offset used by arrow selection controls.
  double get cornerHandleOffset => isArrow ? 8.0 : 0.0;
}

/// Resolves a normalized profile for the current selected ids.
SingleSelectionProfile resolveSingleSelectionProfile({
  required Set<String> selectedIds,
  required ElementState? Function(String id) resolveElementById,
}) {
  if (selectedIds.length != 1) {
    return SingleSelectionProfile.none;
  }
  return SingleSelectionProfile.fromElement(
    resolveElementById(selectedIds.first),
  );
}
