/// A generic min-heap that orders elements by a caller-supplied score.
///
/// Used by the elbow A* grid router and available for reuse by other
/// subsystems that need priority-queue behavior.
class BinaryHeap<T> {
  /// Creates a heap that orders elements by the given scoring function
  /// (lowest first).
  BinaryHeap(this._score);

  final double Function(T) _score;
  final List<T> _content = [];

  /// Whether the heap contains no elements.
  bool get isEmpty => _content.isEmpty;

  /// Whether the heap contains at least one element.
  bool get isNotEmpty => _content.isNotEmpty;

  /// Adds [element] to the heap.
  void push(T element) {
    _content.add(element);
    _sinkDown(_content.length - 1);
  }

  /// Removes and returns the element with the lowest score.
  ///
  /// Returns `null` if the heap is empty.
  T? pop() {
    if (_content.isEmpty) {
      return null;
    }
    final result = _content.first;
    final end = _content.removeLast();
    if (_content.isNotEmpty) {
      _content[0] = end;
      _bubbleUp(0);
    }
    return result;
  }

  /// Whether the heap contains [element].
  bool contains(T element) => _content.contains(element);

  /// Re-positions [element] after its score has changed.
  ///
  /// If [element] is not in the heap this is a no-op.
  void rescore(T element) {
    final index = _content.indexOf(element);
    if (index >= 0) {
      _sinkDown(index);
    }
  }

  void _sinkDown(int n) {
    final element = _content[n];
    final elementScore = _score(element);
    while (n > 0) {
      final parentN = ((n + 1) >> 1) - 1;
      final parent = _content[parentN];
      if (elementScore < _score(parent)) {
        _content[parentN] = element;
        _content[n] = parent;
        n = parentN;
      } else {
        break;
      }
    }
  }

  void _bubbleUp(int n) {
    final length = _content.length;
    final element = _content[n];
    final elemScore = _score(element);

    while (true) {
      final child2N = (n + 1) << 1;
      final child1N = child2N - 1;
      int? swap;
      var child1Score = 0.0;

      if (child1N < length) {
        final child1 = _content[child1N];
        child1Score = _score(child1);
        if (child1Score < elemScore) {
          swap = child1N;
        }
      }

      if (child2N < length) {
        final child2 = _content[child2N];
        final child2Score = _score(child2);
        if (child2Score < (swap == null ? elemScore : child1Score)) {
          swap = child2N;
        }
      }

      if (swap != null) {
        _content[n] = _content[swap];
        _content[swap] = element;
        n = swap;
      } else {
        break;
      }
    }
  }
}
