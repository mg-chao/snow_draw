import '../edit/connector/connector_point_operation.dart';
import '../elements/types/arrow/arrow_binding.dart';
import '../elements/types/connector/connector_data.dart';
import '../elements/types/connector/connector_points.dart';
import '../types/edit_transform.dart';

enum _ArrowEndpoint { start, end }

/// Resolves the binding to highlight during arrow point editing.
ArrowBinding? resolveConnectorPointEditHighlightBinding({
  required ConnectorPointEditContext context,
  required ConnectorData data,
  required EditTransform? transform,
}) {
  final endpoint = _resolveEndpointForContext(context);
  if (endpoint == null) {
    return null;
  }
  final transformBinding = _bindingFromTransform(endpoint, transform);
  if (transformBinding != null) {
    return transformBinding;
  }
  return endpoint == _ArrowEndpoint.start ? data.startBinding : data.endBinding;
}

_ArrowEndpoint? _resolveEndpointForContext(ConnectorPointEditContext context) =>
    switch (context.pointKind) {
      ConnectorPointKind.loopStart => _ArrowEndpoint.start,
      ConnectorPointKind.loopEnd => _ArrowEndpoint.end,
      ConnectorPointKind.focusStart => _ArrowEndpoint.start,
      ConnectorPointKind.focusEnd => _ArrowEndpoint.end,
      ConnectorPointKind.turning =>
        context.pointIndex == 0
            ? _ArrowEndpoint.start
            : context.pointIndex == context.initialPoints.length - 1
            ? _ArrowEndpoint.end
            : null,
      _ => null,
    };

ArrowBinding? _bindingFromTransform(
  _ArrowEndpoint endpoint,
  EditTransform? transform,
) {
  if (transform is! ConnectorPointTransform) {
    return null;
  }
  return endpoint == _ArrowEndpoint.start
      ? transform.startBinding
      : transform.endBinding;
}
