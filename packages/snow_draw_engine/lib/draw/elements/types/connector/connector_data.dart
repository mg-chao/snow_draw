import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import '../../core/element_data.dart';
import '../arrow/arrow_binding.dart';
import '../arrow/elbow/elbow_fixed_segment.dart';

/// Shared interface for connector-style path elements.
///
/// Snow Draw uses this for both arrow elements and editable line paths.
abstract class ConnectorData extends ElementData {
  /// Sentinel used by [copyWith] to represent "keep current nullable field".
  static const unset = Object();

  List<DrawPoint> get points;
  double get strokeWidth;
  StrokeStyle get strokeStyle;
  ArrowType get arrowType;
  ArrowheadStyle get startArrowhead;
  ArrowheadStyle get endArrowhead;
  ArrowBinding? get startBinding;
  ArrowBinding? get endBinding;
  List<ElbowFixedSegment>? get fixedSegments;
  bool? get startIsSpecial;
  bool? get endIsSpecial;

  ConnectorData copyWith({
    List<DrawPoint>? points,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    ArrowType? arrowType,
    ArrowheadStyle? startArrowhead,
    ArrowheadStyle? endArrowhead,
    Object? startBinding = unset,
    Object? endBinding = unset,
    Object? fixedSegments = unset,
    Object? startIsSpecial = unset,
    Object? endIsSpecial = unset,
  });
}
