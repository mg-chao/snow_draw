# Elbow Arrow Implementation Quick Reference

This document provides a condensed reference for implementing elbow arrow editing. Refer to `elbow-arrow-editing-specification.md` for detailed explanations.

---

## Data Structure Quick Reference

### Minimal Type Definitions

```typescript
// Core types
type LocalPoint = [number, number];  // Relative to element (x, y)
type GlobalPoint = [number, number]; // Canvas coordinates
type Heading = "up" | "down" | "left" | "right";
type Bounds = [minX, minY, maxX, maxY];

// Elbow arrow element
interface ElbowArrowElement {
  id: string;
  type: "arrow";
  x: number;
  y: number;
  points: LocalPoint[];
  elbowed: true;
  fixedSegments: FixedSegment[] | null;
  startBinding: FixedPointBinding | null;
  endBinding: FixedPointBinding | null;
}

// Fixed segment (user-locked portion)
interface FixedSegment {
  index: number;        // Segment index (1 to points.length-2)
  start: LocalPoint;
  end: LocalPoint;
}
```

---

## Algorithm Quick Reference

### A* Routing Pseudocode

```
function routeElbowArrow(start, end, obstacles):
    grid = generateNonUniformGrid(start, end, obstacles)
    
    openHeap = BinaryHeap()
    openHeap.push(startNode)
    
    while openHeap.notEmpty():
        current = openHeap.pop()
        
        if current == endNode:
            return reconstructPath(current)
        
        current.closed = true
        
        for neighbor in getOrthogonalNeighbors(current):
            if neighbor.closed: continue
            if collidesWithObstacle(current, neighbor): continue
            if isReverseDirection(current, neighbor): continue
            
            gScore = current.g + distance(current, neighbor)
            if directionChanged(current, neighbor):
                gScore += turnPenalty
            
            if gScore < neighbor.g:
                neighbor.parent = current
                neighbor.g = gScore
                neighbor.h = heuristic(neighbor, end)
                neighbor.f = neighbor.g + neighbor.h
                openHeap.pushOrUpdate(neighbor)
    
    return null  // No path found
```

### Turn Penalty Formula

```
turnPenalty = pow(manhattanDistance(start, end), 3)
heuristicBendPenalty = estimatedBends * pow(manhattanDistance(start, end), 2)
```

---

## Editing Scenarios Decision Tree

```
updateElbowArrowPoints(element, updates):
    │
    ├─ No updates provided?
    │   └─► Scenario 1: RENORMALIZATION
    │       - Remove collinear points
    │       - Remove short segments
    │       - Re-index fixed segments
    │
    ├─ No fixed segments?
    │   └─► Scenario 2: NORMAL ROUTING
    │       - Full A* reroute
    │       - Calculate from scratch
    │
    ├─ Fixed segments decreased?
    │   └─► Scenario 3: SEGMENT RELEASE
    │       - Route released portion via A*
    │       - Preserve other fixed segments
    │       - Merge paths
    │
    ├─ Only fixedSegments updated?
    │   └─► Scenario 4: SEGMENT MOVE
    │       - Update segment position
    │       - Adjust neighbors
    │       - Maintain orthogonality
    │
    ├─ Both points and fixedSegments?
    │   └─► Scenario 5: RESIZE
    │       - Scale proportionally
    │       - Direct update
    │
    └─ Points updated with existing fixedSegments?
        └─► Scenario 6: ENDPOINT DRAG
            - Preserve fixed segments
            - Recalculate transitions
            - Update indices
```

---

## Segment Movement Rules

### Constraint Matrix

| Segment Type | Allowed Movement | Adjacent Updates |
|--------------|------------------|------------------|
| Horizontal | Vertical only (Y) | Update X of neighbors |
| Vertical | Horizontal only (X) | Update Y of neighbors |

### Movement Implementation

```typescript
function moveSegment(segment, newX, newY, element):
    isHorizontal = segment.start[1] == segment.end[1]
    
    if isHorizontal:
        delta = newY - (element.y + segment.start[1])
        segment.start[1] += delta
        segment.end[1] += delta
    else:
        delta = newX - (element.x + segment.start[0])
        segment.start[0] += delta
        segment.end[0] += delta
    
    updateAdjacentSegments(segment)
```

---

## Validation Checklist

```typescript
// Run these checks before applying updates

□ All segments are orthogonal (dx < 1 OR dy < 1)
□ First point is [0, 0]
□ Fixed segment indices are in valid range (1 < index < points.length - 1)
□ Fixed segments don't include first or last segment
□ All coordinates are within bounds (-1e6 to 1e6)
□ Fixed segments match current point structure
```

---

## UI Handle Positions

```
For element with N points:

Endpoint handles:
  - points[0] → Start handle
  - points[N-1] → End handle

Midpoint handles:
  - For i from 1 to N-1:
    position = midpoint(points[i-1], points[i])
    visible = segmentLength > HANDLE_SIZE / zoom
    style = isFixed(i) ? "fixed" : "normal"
```

---

## Common Calculations

### Coordinate Conversion

```typescript
// Local to Global
globalX = element.x + localPoint[0]
globalY = element.y + localPoint[1]

// Global to Local
localX = globalPoint[0] - element.x
localY = globalPoint[1] - element.y
```

### Segment Direction

```typescript
function isHorizontal(p1, p2):
    return abs(p1[1] - p2[1]) < abs(p1[0] - p2[0])

function getHeading(from, to):
    if isHorizontal(from, to):
        return to[0] > from[0] ? "right" : "left"
    else:
        return to[1] > from[1] ? "down" : "up"
```

### Grid Node Neighbors

```typescript
// Neighbors in order: up, right, down, left
function getNeighbors(col, row, grid):
    return [
        grid[row - 1]?[col],  // up
        grid[row]?[col + 1],  // right
        grid[row + 1]?[col],  // down
        grid[row]?[col - 1]   // left
    ]

function neighborIndexToHeading(index):
    return ["up", "right", "down", "left"][index]
```

---

## Constants Reference

```typescript
const BASE_PADDING = 40;        // Min distance from bound elements
const DEDUP_THRESHOLD = 1;      // Min segment length (px)
const HANDLE_SIZE = 10;         // UI handle size (px)
const MAX_COORDINATE = 1e6;     // Coordinate bounds
```

---

## Error Handling

| Error | Cause | Recovery |
|-------|-------|----------|
| No path found | Obstacles block all routes | Return direct line between endpoints |
| Invalid points | Non-orthogonal segment | Re-route entire arrow |
| Out of bounds | Coordinates exceed limit | Clamp to valid range |
| Missing segment | Index mismatch | Re-index fixed segments |

---

## Testing Scenarios

### Minimum Test Cases

1. **Create** - Draw arrow between two shapes
2. **Drag endpoint** - Move start/end, verify rerouting
3. **Fix segment** - Drag midpoint, verify locking
4. **Move fixed** - Drag locked segment, verify constraints
5. **Release segment** - Double-click, verify unlock
6. **Move bound element** - Verify arrow follows
7. **Overlapping elements** - Verify routing around
8. **Self-connection** - Arrow from element to itself

### Edge Cases

- Very short segments (< 1px)
- Many fixed segments
- Bound element deleted
- Arrow crosses itself
- Zoom in/out handle visibility
