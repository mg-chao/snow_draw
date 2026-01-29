import 'package:meta/meta.dart';

import '../../types/edit_transform.dart';
import '../../types/snap_guides.dart';

/// Result returned by an edit operation's `update` call.
///
/// In the preview/commit architecture, `update` must not mutate persistent
/// `elements`. Only the edit session's [EditTransform] is updated.
@immutable
class EditUpdateResult<T extends EditTransform> {
  const EditUpdateResult({required this.transform, this.snapGuides = const []});
  final T transform;
  final List<SnapGuide> snapGuides;
}
