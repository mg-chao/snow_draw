import '../elements/types/arrow/arrow_points.dart';

String? resolveHoverBindingHighlightId({
  required String? hoveredBindingElementId,
  required ArrowPointHandle? hoveredArrowHandle,
}) => hoveredArrowHandle == null ? hoveredBindingElementId : null;
