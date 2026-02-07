import '../edit/arrow/arrow_point_operation.dart';
import '../elements/types/arrow/arrow_binding.dart';
import '../elements/types/arrow/arrow_like_data.dart';
import '../elements/types/arrow/arrow_points.dart';
import '../types/edit_transform.dart';

enum _ArrowEndpoint { start, end }

/// Resolves the binding to highlight during arrow point editing.
ArrowBinding? resolveArrowPointEditHighlightBinding({
  required ArrowPointEditContext context,
  required ArrowLikeData data,
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

_ArrowEndpoint? _resolveEndpointForContext(ArrowPointEditContext context) {
  return switch (context.pointKind) {
    ArrowPointKind.loopStart => _ArrowEndpoint.start,
    ArrowPointKind.loopEnd => _ArrowEndpoint.end,
    ArrowPointKind.turning =>
      context.pointIndex == 0
          ? _ArrowEndpoint.start
          : context.pointIndex == context.initialPoints.length - 1
          ? _ArrowEndpoint.end
          : null,
    _ => null,
  };
}

ArrowBinding? _bindingFromTransform(
  _ArrowEndpoint endpoint,
  EditTransform? transform,
) {
  if (transform is! ArrowPointTransform) {
    return null;
  }
  return endpoint == _ArrowEndpoint.start
      ? transform.startBinding
      : transform.endBinding;
}
