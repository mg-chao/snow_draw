import '../../types/edit_transform.dart';
import '../../types/snap_guides.dart';

/// Result returned by an edit operation's `update` call.
class EditUpdateResult<T extends EditTransform> {
  const EditUpdateResult({
    required this.transform,
    this.snapGuides = const <SnapGuide>[],
  });

  final T transform;
  final List<SnapGuide> snapGuides;
}
