import '../elements/types/arrow/arrow_points.dart';

String? resolveHoverBindingHighlightId({
  required String? hoveredBindingElementId,
  required ArrowPointHandle? hoveredArrowHandle,
}) {
  if (hoveredArrowHandle != null) {
    return null;
  }
  return hoveredBindingElementId;
}
