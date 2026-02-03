import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import '../../core/element_data.dart';
import 'arrow_binding.dart';
import 'elbow/elbow_fixed_segment.dart';

/// Shared interface for arrow-like path elements (arrows, curved lines).
abstract class ArrowLikeData extends ElementData {
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

  ArrowLikeData copyWith({
    List<DrawPoint>? points,
    double? strokeWidth,
    StrokeStyle? strokeStyle,
    ArrowType? arrowType,
    ArrowheadStyle? startArrowhead,
    ArrowheadStyle? endArrowhead,
    Object? startBinding,
    Object? endBinding,
    Object? fixedSegments,
    Object? startIsSpecial,
    Object? endIsSpecial,
  });
}
