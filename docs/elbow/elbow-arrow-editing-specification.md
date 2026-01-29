# Elbow Arrow Editing Function Specification

## Document Purpose

This document provides a complete specification for implementing elbow arrow editing functionality in a drawing application. It assumes that basic elbow arrow generation (creating arrows with orthogonal segments) is already implemented. This guide focuses on the interactive editing experience, including endpoint manipulation, segment adjustment, and automatic rerouting.

---

## Table of Contents

1. [Product Requirements](#1-product-requirements)
2. [Data Structures](#2-data-structures)
3. [Core Editing Behaviors](#3-core-editing-behaviors)
4. [A* Routing Algorithm](#4-a-routing-algorithm)
5. [Fixed Segments System](#5-fixed-segments-system)
6. [Editing Scenario Handlers](#6-editing-scenario-handlers)
7. [UI Interaction Patterns](#7-ui-interaction-patterns)
8. [Validation Rules](#8-validation-rules)
9. [Edge Cases and Constraints](#9-edge-cases-and-constraints)
10. [Implementation Checklist](#10-implementation-checklist)

---

## 1. Product Requirements

### 1.1 Overview

Elbow arrows are connectors with orthogonal (horizontal/vertical only) segments that automatically route around obstacles. Unlike freeform arrows, elbow arrows maintain strict 90-degree angles and provide intelligent path calculation.

### 1.2 User Stories

#### US-1: Automatic Path Calculation
**As a user**, I want the elbow arrow to automatically calculate the best path between two points, so that I don't need to manually position each segment.

**Acceptance Criteria:**
- When I create an elbow arrow between two elements, the path is automatically calculated
- The path avoids overlapping with the connected elements
- The path uses the minimum necessary number of turns
- Direction changes are penalized to prefer straighter routes

#### US-2: Endpoint Dragging
**As a user**, I want to drag the start or end point of an elbow arrow, so that I can reposition the connection.

**Acceptance Criteria:**
- When I drag an endpoint, the entire path recalculates automatically
- If binding to an element is enabled, the endpoint snaps to the element's outline
- The arrow maintains orthogonal constraints during dragging
- Visual feedback shows the new path in real-time

#### US-3: Segment Adjustment
**As a user**, I want to manually adjust the position of intermediate segments, so that I can fine-tune the arrow's path.

**Acceptance Criteria:**
- Midpoint handles appear on each segment when the arrow is selected
- Dragging a midpoint handle moves the entire segment (not individual points)
- Horizontal segments can only be moved vertically
- Vertical segments can only be moved horizontally
- The adjusted segment becomes "fixed" and won't be automatically recalculated

#### US-4: Segment Release
**As a user**, I want to release a fixed segment back to automatic routing, so that I can reset manual adjustments.

**Acceptance Criteria:**
- Double-clicking on a fixed segment's midpoint releases it
- The released segment and its neighbors recalculate automatically
- Other fixed segments remain unchanged

#### US-5: Element Binding
**As a user**, I want elbow arrows to connect to elements and stay connected when elements move, so that my diagrams remain connected.

**Acceptance Criteria:**
- Arrow endpoints can bind to any bindable element (shapes, text, images, etc.)
- When a bound element moves, the arrow automatically reroutes
- The binding point can be on any side of the element (top, right, bottom, left)
- Adequate padding is maintained between the arrow and bound elements

### 1.3 Functional Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| FR-1 | All segments must be either horizontal or vertical | Must Have |
| FR-2 | Automatic path calculation using pathfinding algorithm | Must Have |
| FR-3 | Endpoint dragging with automatic rerouting | Must Have |
| FR-4 | Segment adjustment via midpoint handles | Must Have |
| FR-5 | Fixed segment persistence across edits | Must Have |
| FR-6 | Segment release functionality | Must Have |
| FR-7 | Element binding support | Must Have |
| FR-8 | Minimum padding from bound elements (configurable) | Should Have |
| FR-9 | Path optimization to minimize turns | Should Have |
| FR-10 | Visual feedback during editing | Should Have |

### 1.4 Non-Functional Requirements

| ID | Requirement | Target |
|----|-------------|--------|
| NFR-1 | Path calculation time | < 50ms for typical cases |
| NFR-2 | Smooth drag feedback | 60 FPS during editing |
| NFR-3 | Memory efficiency | O(n) where n = grid nodes |

---

## 2. Data Structures

### 2.1 Elbow Arrow Element

```typescript
interface ElbowArrowElement {
  // Basic properties (inherited from arrow/linear element)
  id: string;
  type: "arrow";
  x: number;           // X coordinate of first point (global)
  y: number;           // Y coordinate of first point (global)
  points: LocalPoint[]; // Array of points relative to (x, y)
  
  // Elbow-specific properties
  elbowed: true;       // Discriminator for elbow arrows
  fixedSegments: FixedSegment[] | null;  // User-locked segments
  
  // Binding properties
  startBinding: FixedPointBinding | null;
  endBinding: FixedPointBinding | null;
  
  // Special flags for complex routing scenarios
  startIsSpecial: boolean | null;
  endIsSpecial: boolean | null;
}

// Point relative to element's (x, y) origin
type LocalPoint = [number, number];

// Point in canvas/scene coordinates
type GlobalPoint = [number, number];
```

### 2.2 Fixed Segment

```typescript
interface FixedSegment {
  index: number;      // Segment index (1-based, refers to ending point index)
  start: LocalPoint;  // Start point of segment (local coordinates)
  end: LocalPoint;    // End point of segment (local coordinates)
}
```

**Important Notes:**
- Segment index refers to the ending point's index in the points array
- A segment at index `i` connects `points[i-1]` to `points[i]`
- First segment (index 1) and last segment (index = points.length - 1) cannot be fixed

### 2.3 Binding Information

```typescript
interface FixedPointBinding {
  elementId: string;           // ID of the bound element
  fixedPoint: [number, number]; // Ratio (0-1) within element bounds
  mode: "inside" | "orbit" | "skip";
}
```

**Binding Modes:**
- `inside`: Arrow endpoint is inside the element
- `orbit`: Arrow endpoint orbits around the element outline
- `skip`: Skip binding for this endpoint

### 2.4 Heading/Direction

```typescript
type Heading = "up" | "down" | "left" | "right";

// Numerical representation for calculations
const HEADING_UP = [0, -1];
const HEADING_DOWN = [0, 1];
const HEADING_LEFT = [-1, 0];
const HEADING_RIGHT = [1, 0];
```

### 2.5 Grid Node (for A* Algorithm)

```typescript
interface GridNode {
  pos: GlobalPoint;      // Position in global coordinates
  addr: [col, row];      // Grid address
  f: number;             // Total cost (g + h)
  g: number;             // Cost from start
  h: number;             // Heuristic to end
  parent: GridNode | null;
  closed: boolean;       // Already processed
  visited: boolean;      // In open list
}

interface Grid {
  row: number;
  col: number;
  data: (GridNode | null)[];
}
```

---

## 3. Core Editing Behaviors

### 3.1 Behavior Matrix

| Action | Fixed Segments = 0 | Fixed Segments > 0 |
|--------|-------------------|-------------------|
| Drag endpoint | Full reroute via A* | Preserve fixed, adjust neighbors |
| Drag midpoint | Create fixed segment | Update fixed segment position |
| Double-click midpoint | N/A | Release fixed segment |
| Bound element moves | Full reroute via A* | Preserve fixed, adjust ends |
| Resize element | Full reroute via A* | Scale fixed segments proportionally |

### 3.2 Editing State Machine

```
                    ┌─────────────────┐
                    │     IDLE        │
                    └────────┬────────┘
                             │ select arrow
                             ▼
                    ┌─────────────────┐
          ┌─────────│    SELECTED     │─────────┐
          │         └────────┬────────┘         │
          │                  │                  │
    drag endpoint      drag midpoint      double-click midpoint
          │                  │                  │
          ▼                  ▼                  ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│ DRAGGING_POINT  │ │ DRAGGING_SEGMENT│ │ RELEASE_SEGMENT │
└────────┬────────┘ └────────┬────────┘ └────────┬────────┘
         │                   │                   │
    pointer up          pointer up          immediate
         │                   │                   │
         └───────────────────┴───────────────────┘
                             │
                             ▼
                    ┌─────────────────┐
                    │    SELECTED     │
                    └─────────────────┘
```

### 3.3 Coordinate System

**Local vs Global Coordinates:**
- **Local**: Relative to the element's `(x, y)` position. First point is always `[0, 0]`.
- **Global**: Absolute canvas/scene coordinates.

**Conversion:**
```typescript
function localToGlobal(element: ElbowArrowElement, local: LocalPoint): GlobalPoint {
  return [element.x + local[0], element.y + local[1]];
}

function globalToLocal(element: ElbowArrowElement, global: GlobalPoint): LocalPoint {
  return [global[0] - element.x, global[1] - element.y];
}
```

**Normalization Rule:**
The first point in `points` array must always be `[0, 0]`. When editing moves the start point, normalize by:
1. Calculate offset from new start point
2. Subtract offset from all points
3. Add offset to element's `(x, y)`

---

## 4. A* Routing Algorithm

### 4.1 Algorithm Overview

The routing uses a modified A* pathfinding algorithm optimized for orthogonal connections:

```
┌─────────────────────────────────────────────────────────┐
│                     ROUTING PIPELINE                     │
├─────────────────────────────────────────────────────────┤
│  1. Calculate dynamic bounding boxes (AABBs)            │
│  2. Determine start/end headings                        │
│  3. Calculate dongle positions (exit points)            │
│  4. Generate non-uniform grid                           │
│  5. Run A* pathfinding                                  │
│  6. Post-process path (remove collinear, short segments)│
│  7. Normalize to local coordinates                      │
└─────────────────────────────────────────────────────────┘
```

### 4.2 Grid Generation

Unlike traditional A* with uniform grids, elbow arrow routing uses a **non-uniform grid** built from bounding box edges:

```typescript
function calculateGrid(
  aabbs: Bounds[],           // Bounding boxes to avoid
  start: GlobalPoint,
  startHeading: Heading,
  end: GlobalPoint,
  endHeading: Heading,
  commonBounds: Bounds
): Grid {
  const horizontal = new Set<number>(); // X coordinates
  const vertical = new Set<number>();   // Y coordinates
  
  // Add start/end positions based on heading
  if (startHeading === "left" || startHeading === "right") {
    vertical.add(start[1]);
  } else {
    horizontal.add(start[0]);
  }
  
  if (endHeading === "left" || endHeading === "right") {
    vertical.add(end[1]);
  } else {
    horizontal.add(end[0]);
  }
  
  // Add all AABB edges
  for (const aabb of aabbs) {
    horizontal.add(aabb[0]); // left
    horizontal.add(aabb[2]); // right
    vertical.add(aabb[1]);   // top
    vertical.add(aabb[3]);   // bottom
  }
  
  // Add common bounds edges
  horizontal.add(commonBounds[0]);
  horizontal.add(commonBounds[2]);
  vertical.add(commonBounds[1]);
  vertical.add(commonBounds[3]);
  
  // Sort and create grid nodes at intersections
  const sortedX = Array.from(horizontal).sort((a, b) => a - b);
  const sortedY = Array.from(vertical).sort((a, b) => a - b);
  
  return {
    col: sortedX.length,
    row: sortedY.length,
    data: sortedY.flatMap((y, row) =>
      sortedX.map((x, col) => createGridNode(x, y, col, row))
    )
  };
}
```

**Visual Example:**
```
      x1    x2    x3    x4
  y1  ●─────●─────●─────●
      │     │░░░░░│     │
  y2  ●─────●░░░░░●─────●
      │     │░░░░░│     │
  y3  ●─────●─────●─────●
      │           │     │
  y4  ●───────────●─────●

░ = Obstacle (bound element)
● = Grid node (potential path point)
```

### 4.3 A* Implementation

```typescript
function astar(
  start: GridNode,
  end: GridNode,
  grid: Grid,
  startHeading: Heading,
  endHeading: Heading,
  obstacles: Bounds[]
): GridNode[] | null {
  const bendMultiplier = manhattanDistance(start.pos, end.pos);
  const openHeap = new BinaryHeap<GridNode>(node => node.f);
  
  openHeap.push(start);
  
  while (openHeap.size() > 0) {
    const current = openHeap.pop();
    
    if (!current || current.closed) continue;
    
    // Goal reached
    if (current === end) {
      return reconstructPath(start, current);
    }
    
    current.closed = true;
    
    // Check all 4 neighbors (up, right, down, left)
    const neighbors = getNeighbors(current.addr, grid);
    
    for (let i = 0; i < 4; i++) {
      const neighbor = neighbors[i];
      if (!neighbor || neighbor.closed) continue;
      
      // Check obstacle collision
      const midpoint = midpointBetween(current.pos, neighbor.pos);
      if (isInsideAnyObstacle(midpoint, obstacles)) continue;
      
      // Prevent reverse movement
      const neighborHeading = indexToHeading(i);
      const previousHeading = current.parent
        ? headingFromVector(current.pos, current.parent.pos)
        : startHeading;
      
      if (isReverseHeading(previousHeading, neighborHeading)) continue;
      if (current === start && neighborHeading === startHeading) continue;
      if (neighbor === end && neighborHeading === endHeading) continue;
      
      // Calculate costs
      const directionChange = previousHeading !== neighborHeading;
      const gScore = current.g 
        + manhattanDistance(neighbor.pos, current.pos)
        + (directionChange ? Math.pow(bendMultiplier, 3) : 0);
      
      if (!neighbor.visited || gScore < neighbor.g) {
        const estimatedBends = estimateSegmentCount(
          neighbor, end, neighborHeading, endHeading
        );
        
        neighbor.visited = true;
        neighbor.parent = current;
        neighbor.g = gScore;
        neighbor.h = manhattanDistance(end.pos, neighbor.pos) 
          + estimatedBends * Math.pow(bendMultiplier, 2);
        neighbor.f = neighbor.g + neighbor.h;
        
        if (!neighbor.visited) {
          openHeap.push(neighbor);
        } else {
          openHeap.rescoreElement(neighbor);
        }
      }
    }
  }
  
  return null; // No path found
}
```

### 4.4 Key Algorithm Modifications

**1. Direction Change Penalty:**
```typescript
// Penalize turns heavily to prefer straighter paths
const turnPenalty = Math.pow(bendMultiplier, 3);
```

**2. No Reverse Movement:**
```typescript
// Arrow cannot backtrack over its previous segment
if (isReverseHeading(previousHeading, neighborHeading)) continue;
```

**3. Segment Count Heuristic:**
```typescript
// Estimate remaining bends for better path selection
function estimateSegmentCount(
  current: GridNode,
  end: GridNode,
  currentHeading: Heading,
  endHeading: Heading
): number {
  // Returns 0, 1, 2, 3, or 4 based on relative positions and headings
  // ... implementation based on position analysis
}
```

### 4.5 Dynamic AABB Generation

Dynamic bounding boxes expand from the connected elements to create obstacle zones:

```typescript
function generateDynamicAABBs(
  startElementBounds: Bounds,
  endElementBounds: Bounds,
  commonBounds: Bounds,
  startPadding: [top, right, bottom, left],
  endPadding: [top, right, bottom, left]
): [Bounds, Bounds] {
  // Generate two AABBs that:
  // 1. Expand from element bounds by heading-based padding
  // 2. Meet in the middle when elements are far apart
  // 3. Handle overlapping elements gracefully
  // ... implementation
}
```

### 4.6 Post-Processing

After A* finds a path, post-process to clean up:

```typescript
function postProcessPath(points: GlobalPoint[]): GlobalPoint[] {
  // 1. Remove collinear points
  points = removeCollinearPoints(points);
  
  // 2. Remove segments shorter than threshold (e.g., 1px)
  points = removeShortSegments(points, DEDUP_THRESHOLD);
  
  return points;
}

function removeCollinearPoints(points: GlobalPoint[]): GlobalPoint[] {
  return points.filter((p, idx) => {
    if (idx === 0 || idx === points.length - 1) return true;
    
    const prev = points[idx - 1];
    const next = points[idx + 1];
    const prevIsHorizontal = isHorizontalSegment(prev, p);
    const nextIsHorizontal = isHorizontalSegment(p, next);
    
    return prevIsHorizontal !== nextIsHorizontal;
  });
}
```

---

## 5. Fixed Segments System

### 5.1 Concept

Fixed segments are user-locked portions of the arrow path that resist automatic rerouting. They allow manual fine-tuning while preserving the overall automatic routing behavior.

```
Before fixing:                After fixing segment 2:
                              
    ●───────●                     ●───────●
            │                             │
            ●───────●             ●───────● (fixed)
                    │             │
                    ●             ●───────●
                                          │
                                          ●
```

### 5.2 Fixed Segment Rules

| Rule | Description |
|------|-------------|
| R1 | First segment (index 1) cannot be fixed |
| R2 | Last segment (index = points.length - 1) cannot be fixed |
| R3 | Fixed segments must remain horizontal or vertical |
| R4 | Moving a fixed segment updates its neighbors automatically |
| R5 | Fixed segments are stored in local coordinates |
| R6 | Minimum segment length is enforced (BASE_PADDING) |

### 5.3 Creating a Fixed Segment

When user drags a midpoint handle:

```typescript
function createFixedSegment(
  element: ElbowArrowElement,
  segmentIndex: number,
  dragX: number,
  dragY: number
): FixedSegment {
  const isHorizontal = isHorizontalSegment(
    element.points[segmentIndex - 1],
    element.points[segmentIndex]
  );
  
  return {
    index: segmentIndex,
    start: [
      !isHorizontal ? dragX - element.x : element.points[segmentIndex - 1][0],
      isHorizontal ? dragY - element.y : element.points[segmentIndex - 1][1]
    ],
    end: [
      !isHorizontal ? dragX - element.x : element.points[segmentIndex][0],
      isHorizontal ? dragY - element.y : element.points[segmentIndex][1]
    ]
  };
}
```

### 5.4 Moving a Fixed Segment

```typescript
function handleSegmentMove(
  element: ElbowArrowElement,
  fixedSegments: FixedSegment[],
  activeSegmentIndex: number,
  newPosition: GlobalPoint
): ElementUpdate {
  const segment = fixedSegments.find(s => s.index === activeSegmentIndex);
  const isHorizontal = isHorizontalSegment(segment.start, segment.end);
  
  // Calculate constrained movement
  const delta = isHorizontal
    ? [0, newPosition[1] - (element.y + segment.start[1])]
    : [newPosition[0] - (element.x + segment.start[0]), 0];
  
  // Update this segment
  segment.start = [segment.start[0] + delta[0], segment.start[1] + delta[1]];
  segment.end = [segment.end[0] + delta[0], segment.end[1] + delta[1]];
  
  // Update adjacent segments
  const prevSegment = fixedSegments.find(s => s.index === activeSegmentIndex - 1);
  const nextSegment = fixedSegments.find(s => s.index === activeSegmentIndex + 1);
  
  if (prevSegment) {
    // Align previous segment's end to this segment's start
    const dir = isHorizontal ? 1 : 0;
    prevSegment.end[dir] = segment.start[dir];
  }
  
  if (nextSegment) {
    // Align next segment's start to this segment's end
    const dir = isHorizontal ? 1 : 0;
    nextSegment.start[dir] = segment.end[dir];
  }
  
  // Rebuild points array from fixed segments
  return rebuildPointsFromFixedSegments(element, fixedSegments);
}
```

### 5.5 Releasing a Fixed Segment

```typescript
function handleSegmentRelease(
  element: ElbowArrowElement,
  fixedSegments: FixedSegment[],
  releasedIndex: number
): ElementUpdate {
  // Remove the segment from fixed list
  const newFixedSegments = fixedSegments.filter(s => s.index !== releasedIndex);
  
  // Find boundaries (prev and next fixed segments)
  const prevFixed = newFixedSegments
    .filter(s => s.index < releasedIndex)
    .sort((a, b) => b.index - a.index)[0];
  const nextFixed = newFixedSegments
    .filter(s => s.index > releasedIndex)
    .sort((a, b) => a.index - b.index)[0];
  
  // Calculate new path between boundaries using A*
  const startPoint = prevFixed ? prevFixed.end : element.points[0];
  const endPoint = nextFixed ? nextFixed.start : element.points[element.points.length - 1];
  
  const newPath = routeElbowArrow(startPoint, endPoint, /* ... */);
  
  // Merge new path with existing fixed portions
  return mergePathWithFixedSegments(element, newPath, prevFixed, nextFixed);
}
```

---

## 6. Editing Scenario Handlers

### 6.1 Scenario Overview

The update function must handle 6 distinct scenarios:

```typescript
function updateElbowArrowPoints(
  element: ElbowArrowElement,
  updates: {
    points?: LocalPoint[];
    fixedSegments?: FixedSegment[] | null;
    startBinding?: FixedPointBinding | null;
    endBinding?: FixedPointBinding | null;
  },
  options?: { isDragging?: boolean }
): ElementUpdate {
  
  // Scenario 1: Renormalization
  if (!updates.points && !updates.fixedSegments && 
      !updates.startBinding && !updates.endBinding) {
    return handleRenormalization(element);
  }
  
  // Scenario 2: Normal routing (no fixed segments)
  if ((element.fixedSegments?.length ?? 0) === 0 && 
      (updates.fixedSegments?.length ?? 0) === 0) {
    return handleNormalRouting(element, updates);
  }
  
  // Scenario 3: Segment release
  if ((element.fixedSegments?.length ?? 0) > (updates.fixedSegments?.length ?? 0)) {
    return handleSegmentRelease(element, updates.fixedSegments);
  }
  
  // Scenario 4: Segment move
  if (!updates.points && updates.fixedSegments) {
    return handleSegmentMove(element, updates.fixedSegments);
  }
  
  // Scenario 5: Resize with fixed segments
  if (updates.points && updates.fixedSegments) {
    return handleResize(element, updates);
  }
  
  // Scenario 6: Endpoint drag with fixed segments
  return handleEndpointDrag(element, updates);
}
```

### 6.2 Scenario 1: Renormalization

Remove redundant points and merge collinear segments:

```typescript
function handleRenormalization(element: ElbowArrowElement): ElementUpdate {
  const points = [...element.points];
  const fixedSegments = element.fixedSegments ? [...element.fixedSegments] : null;
  
  // Pass 1: Remove collinear points
  const cleaned = removeCollinearPoints(points, fixedSegments);
  
  // Pass 2: Remove segments shorter than threshold
  const final = removeShortSegments(cleaned.points, cleaned.fixedSegments);
  
  // If no fixed segments remain, reroute entirely
  if (!final.fixedSegments || final.fixedSegments.length === 0) {
    return handleNormalRouting(element, {});
  }
  
  return normalizeUpdate(final.points, final.fixedSegments);
}
```

### 6.3 Scenario 2: Normal Routing

Full A* rerouting when no fixed segments exist:

```typescript
function handleNormalRouting(
  element: ElbowArrowElement,
  updates: Partial<ElementUpdate>
): ElementUpdate {
  const data = calculateRoutingData(element, updates);
  
  const path = routeElbowArrow({
    startPoint: data.startGlobalPoint,
    endPoint: data.endGlobalPoint,
    startHeading: data.startHeading,
    endHeading: data.endHeading,
    obstacles: data.dynamicAABBs
  });
  
  if (!path) {
    // Fallback: direct connection
    return { points: [element.points[0], element.points[element.points.length - 1]] };
  }
  
  const processed = postProcessPath(path);
  return normalizeUpdate(processed, null);
}
```

### 6.4 Scenario 3: Segment Release

Restore automatic routing for a released segment:

```typescript
function handleSegmentRelease(
  element: ElbowArrowElement,
  newFixedSegments: FixedSegment[]
): ElementUpdate {
  // Find which segment was released
  const releasedIndex = findReleasedSegmentIndex(
    element.fixedSegments,
    newFixedSegments
  );
  
  // Find boundary fixed segments
  const prev = findPreviousFixedSegment(newFixedSegments, releasedIndex);
  const next = findNextFixedSegment(newFixedSegments, releasedIndex);
  
  // Route the released portion
  const startPoint = prev ? toGlobal(element, prev.end) : toGlobal(element, [0, 0]);
  const endPoint = next 
    ? toGlobal(element, next.start) 
    : toGlobal(element, element.points[element.points.length - 1]);
  
  const subPath = routeElbowArrow({ startPoint, endPoint, /* ... */ });
  
  // Merge subpath with fixed portions
  return mergeSubPath(element, subPath, prev, next, newFixedSegments);
}
```

### 6.5 Scenario 4: Segment Move

Move a fixed segment while maintaining orthogonal constraints:

```typescript
function handleSegmentMove(
  element: ElbowArrowElement,
  fixedSegments: FixedSegment[]
): ElementUpdate {
  // Find which segment changed
  const movedIndex = findModifiedSegmentIndex(element.fixedSegments, fixedSegments);
  const movedSegment = fixedSegments.find(s => s.index === movedIndex);
  
  // Clone points array
  const newPoints = element.points.map((p, i) => 
    toGlobal(element, p)
  );
  
  // Update segment endpoints
  const startIdx = movedSegment.index - 1;
  const endIdx = movedSegment.index;
  
  newPoints[startIdx] = toGlobal(element, movedSegment.start);
  newPoints[endIdx] = toGlobal(element, movedSegment.end);
  
  // Update adjacent non-fixed segments
  updateAdjacentSegments(newPoints, movedSegment, fixedSegments);
  
  // Handle first/last segment special cases
  if (movedSegment.index === 1) {
    newPoints.unshift(/* add start point */);
    // Update all fixed segment indices
  }
  
  if (movedSegment.index === element.points.length - 1) {
    newPoints.push(/* add end point */);
  }
  
  return normalizeUpdate(newPoints, fixedSegments);
}
```

### 6.6 Scenario 5: Resize

Handle resize when both points and fixed segments change:

```typescript
function handleResize(
  element: ElbowArrowElement,
  updates: { points: LocalPoint[], fixedSegments: FixedSegment[] }
): ElementUpdate {
  // Direct update - resize logic handles scaling
  return {
    points: updates.points,
    fixedSegments: updates.fixedSegments,
    ...calculateDimensions(updates.points)
  };
}
```

### 6.7 Scenario 6: Endpoint Drag with Fixed Segments

Most complex scenario - preserve fixed segments while moving endpoints:

```typescript
function handleEndpointDrag(
  element: ElbowArrowElement,
  updates: { points: LocalPoint[] }
): ElementUpdate {
  const fixedSegments = element.fixedSegments || [];
  
  // Extract which endpoint moved
  const startMoved = !pointsEqual(updates.points[0], element.points[0]);
  const endMoved = !pointsEqual(
    updates.points[updates.points.length - 1],
    element.points[element.points.length - 1]
  );
  
  // Calculate new headings
  const startHeading = calculateHeading(/* ... */);
  const endHeading = calculateHeading(/* ... */);
  
  // Build new points preserving fixed segments
  const newPoints: GlobalPoint[] = [];
  
  // Add start section
  newPoints.push(toGlobal(element, updates.points[0]));
  addStartTransition(newPoints, startHeading, fixedSegments);
  
  // Add middle (fixed) sections
  addFixedSections(newPoints, element, fixedSegments);
  
  // Add end section
  addEndTransition(newPoints, endHeading, fixedSegments);
  newPoints.push(toGlobal(element, updates.points[updates.points.length - 1]));
  
  return normalizeUpdate(newPoints, updateFixedSegmentIndices(fixedSegments));
}
```

---

## 7. UI Interaction Patterns

### 7.1 Selection and Handles

When an elbow arrow is selected, display:

```
                  ○ endpoint handle
                  │
    ●─────────────●
                  │
            □─────● midpoint handle (segment 2)
            │
    □───────●─────●
    │             │
    ●             ○ endpoint handle
    
● = Regular point (not directly editable for elbow)
○ = Endpoint handle (draggable)
□ = Midpoint handle (drags segment)
```

**Handle Types:**

| Handle | Appearance | Interaction |
|--------|------------|-------------|
| Endpoint | Circle, larger | Drag to move endpoint |
| Midpoint | Square or circle | Drag to fix/move segment |
| Fixed midpoint | Filled/different color | Indicates locked segment |

### 7.2 Midpoint Handle Positioning

Calculate midpoint for each segment:

```typescript
function getSegmentMidpoint(
  element: ElbowArrowElement,
  segmentIndex: number // 1-based
): GlobalPoint {
  const p1 = element.points[segmentIndex - 1];
  const p2 = element.points[segmentIndex];
  
  return [
    element.x + (p1[0] + p2[0]) / 2,
    element.y + (p1[1] + p2[1]) / 2
  ];
}
```

### 7.3 Hit Testing

```typescript
function getHitTestResult(
  element: ElbowArrowElement,
  pointerX: number,
  pointerY: number,
  zoom: number
): HitTestResult {
  const threshold = HANDLE_SIZE / zoom;
  
  // Check endpoint handles first (higher priority)
  const startPoint = toGlobal(element, element.points[0]);
  if (distance([pointerX, pointerY], startPoint) < threshold) {
    return { type: "endpoint", index: 0 };
  }
  
  const endPoint = toGlobal(element, element.points[element.points.length - 1]);
  if (distance([pointerX, pointerY], endPoint) < threshold) {
    return { type: "endpoint", index: element.points.length - 1 };
  }
  
  // Check midpoint handles
  for (let i = 1; i < element.points.length; i++) {
    const midpoint = getSegmentMidpoint(element, i);
    if (distance([pointerX, pointerY], midpoint) < threshold) {
      return { type: "midpoint", segmentIndex: i };
    }
  }
  
  // Check line body
  if (isPointOnPath(element, [pointerX, pointerY], threshold)) {
    return { type: "body" };
  }
  
  return { type: "none" };
}
```

### 7.4 Cursor Feedback

| Context | Cursor |
|---------|--------|
| Hovering endpoint | `move` or `grab` |
| Hovering horizontal segment midpoint | `ns-resize` |
| Hovering vertical segment midpoint | `ew-resize` |
| Hovering fixed segment midpoint | Different color + same resize cursor |
| Dragging | `grabbing` |

### 7.5 Segment Too Short

Don't show midpoint handle if segment is too short:

```typescript
function isSegmentTooShort(
  element: ElbowArrowElement,
  segmentIndex: number,
  zoom: number
): boolean {
  const p1 = element.points[segmentIndex - 1];
  const p2 = element.points[segmentIndex];
  const length = distance(p1, p2);
  
  return length * zoom < HANDLE_SIZE / 2;
}
```

---

## 8. Validation Rules

### 8.1 Orthogonal Constraint

Every segment must be either horizontal or vertical:

```typescript
function validateElbowPoints(
  points: LocalPoint[],
  tolerance: number = 1 // pixels
): boolean {
  for (let i = 1; i < points.length; i++) {
    const dx = Math.abs(points[i][0] - points[i - 1][0]);
    const dy = Math.abs(points[i][1] - points[i - 1][1]);
    
    // One of dx or dy must be nearly zero
    if (dx > tolerance && dy > tolerance) {
      return false;
    }
  }
  return true;
}
```

### 8.2 Fixed Segment Validation

```typescript
function validateFixedSegments(
  points: LocalPoint[],
  fixedSegments: FixedSegment[]
): boolean {
  for (const segment of fixedSegments) {
    // Rule: Cannot fix first or last segment
    if (segment.index === 1 || segment.index === points.length - 1) {
      return false;
    }
    
    // Rule: Segment must be orthogonal
    const dx = Math.abs(segment.end[0] - segment.start[0]);
    const dy = Math.abs(segment.end[1] - segment.start[1]);
    if (dx > 1 && dy > 1) {
      return false;
    }
    
    // Rule: Index must be valid
    if (segment.index < 1 || segment.index >= points.length) {
      return false;
    }
  }
  return true;
}
```

### 8.3 Points Normalization

```typescript
function normalizeArrowPoints(
  globalPoints: GlobalPoint[]
): { x: number, y: number, points: LocalPoint[] } {
  const offsetX = globalPoints[0][0];
  const offsetY = globalPoints[0][1];
  
  const localPoints = globalPoints.map(p => [
    p[0] - offsetX,
    p[1] - offsetY
  ] as LocalPoint);
  
  // First point must be [0, 0]
  assert(localPoints[0][0] === 0 && localPoints[0][1] === 0);
  
  return {
    x: offsetX,
    y: offsetY,
    points: localPoints
  };
}
```

### 8.4 Bounds Validation

Prevent extremely large arrows:

```typescript
const MAX_COORDINATE = 1e6;

function validateBounds(points: LocalPoint[], x: number, y: number): boolean {
  if (Math.abs(x) > MAX_COORDINATE || Math.abs(y) > MAX_COORDINATE) {
    return false;
  }
  
  for (const p of points) {
    if (Math.abs(x + p[0]) > MAX_COORDINATE || 
        Math.abs(y + p[1]) > MAX_COORDINATE) {
      return false;
    }
  }
  return true;
}
```

---

## 9. Edge Cases and Constraints

### 9.1 Overlapping Elements

When start and end elements overlap or are very close:

```typescript
function handleOverlappingElements(
  startBounds: Bounds,
  endBounds: Bounds,
  startPoint: GlobalPoint,
  endPoint: GlobalPoint
): RoutingConfig {
  const boundsOverlap = 
    isPointInsideBounds(startPoint, expandBounds(endBounds, BASE_PADDING)) ||
    isPointInsideBounds(endPoint, expandBounds(startBounds, BASE_PADDING));
  
  if (boundsOverlap) {
    // Use point bounds instead of element bounds
    return {
      startAABB: pointToBounds(startPoint, 2),
      endAABB: pointToBounds(endPoint, 2),
      disableSideHack: true
    };
  }
  
  return { startAABB: startBounds, endAABB: endBounds };
}
```

### 9.2 Self-Connecting Arrow

When an arrow connects an element to itself:

```typescript
function handleSelfConnection(
  element: ElbowArrowElement,
  boundElement: BoundElement
): RoutingConfig {
  // Force different sides for start and end
  const startSide = determineBindingSide(element.startBinding);
  const endSide = getOppositeSide(startSide); // or perpendicular
  
  // Increase padding to create visible loop
  return {
    padding: BASE_PADDING * 2,
    forcedStartHeading: sideToHeading(startSide),
    forcedEndHeading: sideToHeading(endSide)
  };
}
```

### 9.3 Minimum Segment Length

Enforce minimum segment length near bound elements:

```typescript
const BASE_PADDING = 40; // pixels

function enforceMinimumSegmentLength(
  segment: FixedSegment,
  boundElement: BoundElement | null,
  heading: Heading
): FixedSegment {
  const length = segmentLength(segment);
  
  if (boundElement && length < BASE_PADDING) {
    // Extend segment to minimum length
    const extension = BASE_PADDING - length;
    // ... extend in heading direction
  }
  
  return segment;
}
```

### 9.4 Dongle Points

"Dongle" points are virtual points at the edge of the element's padded bounding box:

```typescript
function getDonglePosition(
  bounds: Bounds,
  heading: Heading,
  attachPoint: GlobalPoint
): GlobalPoint {
  switch (heading) {
    case "up":    return [attachPoint[0], bounds[1]]; // top edge
    case "right": return [bounds[2], attachPoint[1]]; // right edge
    case "down":  return [attachPoint[0], bounds[3]]; // bottom edge
    case "left":  return [bounds[0], attachPoint[1]]; // left edge
  }
}
```

### 9.5 Special Start/End Flags

The `startIsSpecial` and `endIsSpecial` flags handle transitions when moving a bound arrow between horizontal and vertical sides:

```typescript
// When arrow moves from horizontal to vertical binding:
// - Extra segment is added to maintain fixed segments
// - Flag marks that actual visual start is at index 2 instead of 1
// - Prevents loss of fixed segment data during transition
```

---

## 10. Implementation Checklist

### Phase 1: Core Data Structures
- [ ] Define `ElbowArrowElement` type
- [ ] Define `FixedSegment` type
- [ ] Define `FixedPointBinding` type
- [ ] Implement coordinate conversion (local/global)
- [ ] Implement points normalization

### Phase 2: A* Routing
- [ ] Implement non-uniform grid generation
- [ ] Implement A* algorithm with:
  - [ ] Binary heap for open list
  - [ ] Direction change penalty
  - [ ] Reverse movement prevention
  - [ ] Segment count heuristic
- [ ] Implement dynamic AABB generation
- [ ] Implement path post-processing
- [ ] Add fallback for no-path scenarios

### Phase 3: Basic Editing
- [ ] Implement endpoint dragging
- [ ] Implement automatic rerouting on drag
- [ ] Add visual feedback during drag
- [ ] Implement binding detection during drag

### Phase 4: Fixed Segments
- [ ] Implement fixed segment creation (midpoint drag)
- [ ] Implement fixed segment movement
- [ ] Implement fixed segment release (double-click)
- [ ] Implement fixed segment index management
- [ ] Add validation rules

### Phase 5: UI/UX
- [ ] Implement endpoint handles
- [ ] Implement midpoint handles
- [ ] Implement hit testing
- [ ] Add cursor feedback
- [ ] Handle segment-too-short case
- [ ] Add visual distinction for fixed segments

### Phase 6: Edge Cases
- [ ] Handle overlapping elements
- [ ] Handle self-connecting arrows
- [ ] Handle bound element movement
- [ ] Handle resize scenarios
- [ ] Add bounds validation

### Phase 7: Testing
- [ ] Unit tests for A* algorithm
- [ ] Unit tests for fixed segment logic
- [ ] Unit tests for validation
- [ ] Integration tests for editing scenarios
- [ ] Performance tests for large grids

---

## Appendix A: Constants

```typescript
// Routing
const BASE_PADDING = 40;           // Minimum distance from bound elements
const DEDUP_THRESHOLD = 1;         // Minimum segment length (pixels)
const MAX_COORDINATE = 1e6;        // Maximum coordinate value

// UI
const HANDLE_SIZE = 10;            // Handle size in pixels
const DRAGGING_THRESHOLD = 5;      // Pixels before drag starts

// Algorithm
const BEND_MULTIPLIER_POWER = 3;   // Exponent for turn penalty
const HEURISTIC_BEND_POWER = 2;    // Exponent for heuristic bend estimate
```

## Appendix B: Helper Functions

```typescript
// Distance calculations
function manhattanDistance(a: Point, b: Point): number {
  return Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]);
}

function euclideanDistance(a: Point, b: Point): number {
  return Math.sqrt(Math.pow(a[0] - b[0], 2) + Math.pow(a[1] - b[1], 2));
}

// Heading utilities
function isHorizontalHeading(h: Heading): boolean {
  return h === "left" || h === "right";
}

function flipHeading(h: Heading): Heading {
  const map = { up: "down", down: "up", left: "right", right: "left" };
  return map[h];
}

function isReverseHeading(a: Heading, b: Heading): boolean {
  return flipHeading(a) === b;
}

// Segment utilities
function isHorizontalSegment(p1: Point, p2: Point): boolean {
  return Math.abs(p1[1] - p2[1]) < Math.abs(p1[0] - p2[0]);
}

function segmentLength(segment: FixedSegment): number {
  return manhattanDistance(segment.start, segment.end);
}

// Bounds utilities
function expandBounds(bounds: Bounds, padding: number): Bounds {
  return [
    bounds[0] - padding,
    bounds[1] - padding,
    bounds[2] + padding,
    bounds[3] + padding
  ];
}

function isPointInsideBounds(point: Point, bounds: Bounds): boolean {
  return point[0] >= bounds[0] && point[0] <= bounds[2] &&
         point[1] >= bounds[1] && point[1] <= bounds[3];
}

function pointToBounds(point: Point, padding: number): Bounds {
  return [
    point[0] - padding,
    point[1] - padding,
    point[0] + padding,
    point[1] + padding
  ];
}
```

---

## Document Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-29 | Initial specification |
