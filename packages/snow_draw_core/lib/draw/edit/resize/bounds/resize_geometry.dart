import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/resize_mode.dart';
import '../../../utils/transforms/resize_anchor_point.dart' as resize_anchor;

/// Returns the opposite anchor point for a given resize handle [mode].
///
/// The returned point is in the same coordinate space as [rect] (typically the
/// selection overlay's un-rotated local frame).
DrawPoint oppositeBoundPointLocal(DrawRect rect, ResizeMode mode) =>
    resize_anchor.oppositeBoundPointLocal(rect, mode);
