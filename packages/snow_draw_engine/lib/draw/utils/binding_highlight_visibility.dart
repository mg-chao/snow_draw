import '../elements/types/connector/connector_points.dart';

String? resolveHoverBindingHighlightId({
  required String? hoveredBindingElementId,
  required ConnectorPointHandle? hoveredArrowHandle,
}) => hoveredArrowHandle == null ? hoveredBindingElementId : null;
