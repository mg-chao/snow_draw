/// Cardinal directions used by elbow routing and editing logic.
enum ElbowHeading { right, down, left, up }

extension ElbowHeadingX on ElbowHeading {
  /// Unit step along the X axis for this heading.
  int get dx => switch (this) {
    ElbowHeading.right => 1,
    ElbowHeading.down => 0,
    ElbowHeading.left => -1,
    ElbowHeading.up => 0,
  };

  /// Unit step along the Y axis for this heading.
  int get dy => switch (this) {
    ElbowHeading.right => 0,
    ElbowHeading.down => 1,
    ElbowHeading.left => 0,
    ElbowHeading.up => -1,
  };

  /// Whether the heading moves along the X axis.
  bool get isHorizontal => switch (this) {
    ElbowHeading.right || ElbowHeading.left => true,
    ElbowHeading.down || ElbowHeading.up => false,
  };

  /// The opposite heading (used for backtracking checks).
  ElbowHeading get opposite => switch (this) {
    ElbowHeading.right => ElbowHeading.left,
    ElbowHeading.left => ElbowHeading.right,
    ElbowHeading.up => ElbowHeading.down,
    ElbowHeading.down => ElbowHeading.up,
  };
}
