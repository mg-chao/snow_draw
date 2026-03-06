import '../elements/types/arrow/arrow_points.dart';

String? resolveHoverBindingHighlightId({
  required String? hoveredBindingElementId,
  required ConnectorPointHandle? hoveredArrowHandle,
}) => hoveredArrowHandle == null ? hoveredBindingElementId : null;
