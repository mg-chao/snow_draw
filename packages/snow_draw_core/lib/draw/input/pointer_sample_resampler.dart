import '../types/draw_point.dart';

/// Returns a capped, order-preserving sample list for batched pointer updates.
///
/// When pointer dispatch falls behind frame production, a coalesced move event
/// can accumulate hundreds of samples. Passing all of them through reducers in
/// one synchronous batch causes input latency spikes. This helper keeps the
/// first/last samples and uniformly subsamples the interior points so each
/// reducer pass stays bounded while preserving stroke continuity.
List<DrawPoint> resamplePointerSamples({
  required List<DrawPoint> sampledPoints,
  required int maxSamples,
}) {
  if (sampledPoints.isEmpty || maxSamples <= 0) {
    return const <DrawPoint>[];
  }
  if (maxSamples == 1) {
    return List<DrawPoint>.unmodifiable(<DrawPoint>[sampledPoints.last]);
  }
  if (sampledPoints.length <= maxSamples) {
    return sampledPoints;
  }

  final stride = (sampledPoints.length - 1) / (maxSamples - 1);
  final reduced = <DrawPoint>[];

  for (var i = 0; i < maxSamples - 1; i++) {
    final index = (i * stride).round().clamp(0, sampledPoints.length - 1);
    final point = sampledPoints[index];
    if (reduced.isEmpty || reduced.last != point) {
      reduced.add(point);
    }
  }

  final tail = sampledPoints.last;
  if (reduced.isEmpty || reduced.last != tail) {
    reduced.add(tail);
  }

  return List<DrawPoint>.unmodifiable(reduced);
}
