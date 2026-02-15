import 'package:meta/meta.dart';

import '../config/draw_config.dart';

/// Persistent global elements attached to the document.
///
/// These elements are document-level overlays (for example highlight mask and
/// watermark) and participate in undo/redo like regular elements.
@immutable
class GlobalElementsState {
  const GlobalElementsState({
    this.highlightMask = const HighlightMaskConfig(),
    this.watermark = const WatermarkConfig(),
  });

  /// Global highlight mask element data.
  final HighlightMaskConfig highlightMask;

  /// Global watermark element data.
  final WatermarkConfig watermark;

  GlobalElementsState copyWith({
    HighlightMaskConfig? highlightMask,
    WatermarkConfig? watermark,
  }) {
    final nextHighlightMask = highlightMask ?? this.highlightMask;
    final nextWatermark = watermark ?? this.watermark;
    if (nextHighlightMask == this.highlightMask &&
        nextWatermark == this.watermark) {
      return this;
    }
    return GlobalElementsState(
      highlightMask: nextHighlightMask,
      watermark: nextWatermark,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GlobalElementsState &&
          other.highlightMask == highlightMask &&
          other.watermark == watermark;

  @override
  int get hashCode => Object.hash(highlightMask, watermark);

  @override
  String toString() =>
      'GlobalElementsState('
      'highlightMask: $highlightMask, '
      'watermark: $watermark'
      ')';
}
