import '../types/draw_rect.dart';

/// Returns true when [a] and [b] overlap in world-space.
bool rectsIntersect(DrawRect a, DrawRect b) =>
    a.minX <= b.maxX &&
    a.maxX >= b.minX &&
    a.minY <= b.maxY &&
    a.maxY >= b.minY;
