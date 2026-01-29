# Elbow Arrow: Product Requirements & Technical Specification

## Table of Contents

1. [Introduction](#1-introduction)
2. [Product Requirements](#2-product-requirements)
3. [Core Concepts](#3-core-concepts)
4. [Data Structures](#4-data-structures)
5. [Algorithm Overview](#5-algorithm-overview)
6. [Detailed Algorithm Implementation](#6-detailed-algorithm-implementation)
7. [Heading Determination](#7-heading-determination)
8. [Grid Construction](#8-grid-construction)
9. [A* Pathfinding Algorithm](#9-a-pathfinding-algorithm)
10. [Post-Processing](#10-post-processing)
11. [Element Binding](#11-element-binding)
12. [Fixed Segments (Manual Adjustment)](#12-fixed-segments-manual-adjustment)
13. [Edge Cases & Error Handling](#13-edge-cases--error-handling)
14. [Performance Considerations](#14-performance-considerations)
15. [Testing Strategy](#15-testing-strategy)

---

## 1. Introduction

### 1.1 What is an Elbow Arrow?

An **elbow arrow** (also known as an orthogonal connector or rectilinear arrow) is a type of connector line that consists only of horizontal and vertical segments, forming 90-degree angles at each bend. Unlike straight arrows or curved arrows, elbow arrows route around obstacles and always maintain perpendicular segment orientations.

### 1.2 Use Cases

- **Flowcharts**: Connecting process boxes with clean, readable connectors
- **Diagrams**: UML diagrams, ER diagrams, architecture diagrams
- **Wireframes**: Connecting UI elements
- **Mind Maps**: Structured hierarchical connections

### 1.3 Document Purpose

This document provides a complete specification for implementing elbow arrows in any drawing or diagramming application. The implementation details are presented in a technology-agnostic manner, allowing adaptation to various frameworks and rendering systems.

---

## 2. Product Requirements

### 2.1 Functional Requirements

#### FR-1: Basic Path Generation
- **FR-1.1**: The system SHALL generate a path consisting only of horizontal and vertical line segments
- **FR-1.2**: The system SHALL connect any two points on the canvas with a valid elbow path
- **FR-1.3**: The system SHALL minimize the number of bends (direction changes) in the path
- **FR-1.4**: The system SHALL ensure the path does not overlap with itself

#### FR-2: Heading/Direction Control
- **FR-2.1**: The arrow SHALL exit from the start point in a logical direction based on the relative position of the end point
- **FR-2.2**: The arrow SHALL enter the end point from a logical direction
- **FR-2.3**: When bound to an element, the arrow SHALL exit/enter perpendicular to the element's edge

#### FR-3: Element Binding
- **FR-3.1**: The arrow SHALL be able to bind to shapes (rectangles, ellipses, diamonds, etc.)
- **FR-3.2**: When bound, the arrow endpoint SHALL stay attached to the element when the element moves
- **FR-3.3**: The binding point SHALL be calculated based on where the arrow intersects the element's boundary
- **FR-3.4**: The arrow SHALL automatically reroute when bound elements move

#### FR-4: Obstacle Avoidance
- **FR-4.1**: The arrow path SHALL avoid passing through bound elements
- **FR-4.2**: The arrow SHALL maintain a minimum padding distance from bound elements

#### FR-5: Manual Segment Adjustment
- **FR-5.1**: Users SHALL be able to manually drag individual segments of the arrow
- **FR-5.2**: Manual adjustments SHALL be preserved when endpoints move (within constraints)
- **FR-5.3**: Users SHALL be able to release manual adjustments to return to automatic routing

#### FR-6: Arrowheads
- **FR-6.1**: The system SHALL support arrowheads at both start and end points
- **FR-6.2**: Arrowhead presence SHALL affect the padding/routing near endpoints

### 2.2 Non-Functional Requirements

#### NFR-1: Performance
- **NFR-1.1**: Path calculation SHALL complete within 16ms for typical use cases (60fps)
- **NFR-1.2**: The algorithm SHALL handle arrows up to 10,000 pixels in length
- **NFR-1.3**: The system SHALL efficiently handle scenes with 100+ elbow arrows

#### NFR-2: Visual Quality
- **NFR-2.1**: Paths SHALL appear clean and professional
- **NFR-2.2**: Very short segments (< 1 pixel) SHALL be eliminated
- **NFR-2.3**: The number of segments SHALL be minimized for visual clarity

#### NFR-3: Consistency
- **NFR-3.1**: Given the same inputs, the algorithm SHALL produce the same output
- **NFR-3.2**: Small movements of endpoints SHALL result in small changes to the path (stability)

---

## 3. Core Concepts

### 3.1 Coordinate System

The implementation assumes a standard 2D coordinate system:
- **Origin**: Top-left corner of the canvas
- **X-axis**: Positive values increase to the right
- **Y-axis**: Positive values increase downward (screen coordinates)

### 3.2 Points

Points are represented as tuples of two numbers: `[x, y]`

Two types of points are used:
- **Global Points**: Absolute positions on the canvas
- **Local Points**: Positions relative to an element's origin (typically the first point of an arrow)

### 3.3 Headings

A **heading** represents one of four cardinal directions:

| Heading | Vector | Description |
|---------|--------|-------------|
| RIGHT   | [1, 0] | Moving in positive X direction |
| DOWN    | [0, 1] | Moving in positive Y direction |
| LEFT    | [-1, 0] | Moving in negative X direction |
| UP      | [0, -1] | Moving in negative Y direction |

### 3.4 Bounding Boxes (AABB)

Axis-Aligned Bounding Boxes are represented as: `[minX, minY, maxX, maxY]`

They define rectangular regions used for:
- Element boundaries
- Obstacle regions
- Search space boundaries

### 3.5 Segments

A segment is a straight line between two consecutive points. In elbow arrows:
- Every segment is either perfectly horizontal OR perfectly vertical
- Consecutive segments are always perpendicular to each other

### 3.6 Dongles

**Dongles** are intermediate connection points placed at a fixed distance from the start/end points along their heading direction. They ensure the arrow exits/enters in the correct direction before routing begins.

---

## 4. Data Structures

### 4.1 Elbow Arrow Element

```typescript
interface ElbowArrowElement {
  // Position of the first point in global coordinates
  x: number;
  y: number;
  
  // Array of points relative to (x, y)
  // First point is always [0, 0]
  points: LocalPoint[];
  
  // Width and height derived from points bounding box
  width: number;
  height: number;
  
  // Binding information (optional)
  startBinding: PointBinding | null;
  endBinding: PointBinding | null;
  
  // Arrowhead types (optional)
  startArrowhead: ArrowheadType | null;
  endArrowhead: ArrowheadType | null;
  
  // Fixed segments for manual adjustments (optional)
  fixedSegments: FixedSegment[] | null;
}
```

### 4.2 Point Types

```typescript
// Global point: absolute canvas coordinates
type GlobalPoint = [number, number];

// Local point: relative to element origin
type LocalPoint = [number, number];
```

### 4.3 Binding Information

```typescript
interface PointBinding {
  // ID of the element this endpoint is bound to
  elementId: string;
  
  // Fixed point on the element's boundary [0-1, 0-1]
  // (0,0) = top-left, (1,1) = bottom-right
  fixedPoint: [number, number];
  
  // Additional binding metadata
  focus?: number;
  gap?: number;
}
```

### 4.4 Fixed Segment

```typescript
interface FixedSegment {
  // Index of the segment in the points array
  // Segment i goes from points[i-1] to points[i]
  index: number;
  
  // Start and end points of the fixed segment
  start: LocalPoint;
  end: LocalPoint;
}
```

### 4.5 Grid Node (for A* algorithm)

```typescript
interface GridNode {
  // A* algorithm scores
  f: number;  // Total cost (g + h)
  g: number;  // Cost from start
  h: number;  // Heuristic (estimated cost to end)
  
  // Node state
  closed: boolean;
  visited: boolean;
  
  // Path tracking
  parent: GridNode | null;
  
  // Position
  pos: GlobalPoint;
  addr: [col: number, row: number];
}
```

### 4.6 Grid Structure

```typescript
interface Grid {
  row: number;      // Number of rows
  col: number;      // Number of columns
  data: GridNode[]; // Flat array of nodes (row-major order)
}
```

### 4.7 Heading Type

```typescript
type Heading = [1, 0] | [0, 1] | [-1, 0] | [0, -1];

const HEADING_RIGHT: Heading = [1, 0];
const HEADING_DOWN: Heading = [0, 1];
const HEADING_LEFT: Heading = [-1, 0];
const HEADING_UP: Heading = [0, -1];
```

---

## 5. Algorithm Overview

### 5.1 High-Level Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    ELBOW ARROW GENERATION                       │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. INPUT: Start Point, End Point, [Bound Elements]            │
│                           │                                     │
│                           ▼                                     │
│  2. DETERMINE HEADINGS                                         │
│     - Calculate start heading (exit direction)                 │
│     - Calculate end heading (entry direction)                  │
│                           │                                     │
│                           ▼                                     │
│  3. GENERATE BOUNDING BOXES                                    │
│     - Create AABBs around start/end (with padding)             │
│     - These serve as obstacles to route around                 │
│                           │                                     │
│                           ▼                                     │
│  4. CALCULATE DONGLE POSITIONS                                 │
│     - Start dongle: extends from start along start heading     │
│     - End dongle: extends from end along end heading           │
│                           │                                     │
│                           ▼                                     │
│  5. BUILD ROUTING GRID                                         │
│     - Create non-uniform grid based on AABB edges              │
│     - Grid nodes at line intersections                         │
│                           │                                     │
│                           ▼                                     │
│  6. A* PATHFINDING                                             │
│     - Find path from start dongle to end dongle                │
│     - Penalize direction changes                               │
│     - Avoid obstacles                                          │
│                           │                                     │
│                           ▼                                     │
│  7. POST-PROCESSING                                            │
│     - Add actual start/end points                              │
│     - Remove very short segments                               │
│     - Remove collinear points (keep corners only)              │
│     - Convert to local coordinates                             │
│                           │                                     │
│                           ▼                                     │
│  8. OUTPUT: Array of LocalPoints                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### 5.2 Key Constants

```typescript
// Minimum padding from bound elements
const BASE_PADDING = 40;

// Threshold for considering segments as "too short"
const DEDUP_THRESHOLD = 1;

// Maximum coordinate value (prevents infinite paths)
const MAX_POSITION = 1_000_000;
```

---

## 6. Detailed Algorithm Implementation

### 6.1 Main Entry Point

```typescript
function updateElbowArrowPoints(
  arrow: ElbowArrowElement,
  elementsMap: Map<string, Element>,
  updates: {
    points?: LocalPoint[];
    startBinding?: PointBinding | null;
    endBinding?: PointBinding | null;
    fixedSegments?: FixedSegment[] | null;
  }
): ElementUpdate {
  
  // 1. Handle special cases
  if (arrow.points.length < 2) {
    return { points: updates.points ?? arrow.points };
  }
  
  // 2. Gather all necessary data
  const data = getElbowArrowData(arrow, elementsMap, updates.points);
  
  // 3. If no fixed segments, generate fresh path
  if (!fixedSegments || fixedSegments.length === 0) {
    const rawPath = routeElbowArrow(arrow, data);
    const cleanedPath = removeShortSegments(rawPath);
    const cornerPoints = getCornerPoints(cleanedPath);
    return normalizeToLocalCoordinates(cornerPoints);
  }
  
  // 4. Handle fixed segments (manual adjustments)
  // ... (see Section 12)
}
```

### 6.2 Data Gathering

```typescript
function getElbowArrowData(
  arrow: ElbowArrowElement,
  elementsMap: Map<string, Element>,
  nextPoints: LocalPoint[]
): ElbowArrowData {
  
  // Convert to global coordinates
  const startGlobal = toGlobalPoint(nextPoints[0], arrow.x, arrow.y);
  const endGlobal = toGlobalPoint(nextPoints[nextPoints.length - 1], arrow.x, arrow.y);
  
  // Find bound elements
  const startElement = arrow.startBinding 
    ? elementsMap.get(arrow.startBinding.elementId) 
    : null;
  const endElement = arrow.endBinding 
    ? elementsMap.get(arrow.endBinding.elementId) 
    : null;
  
  // Calculate actual binding points
  const startPoint = calculateBindingPoint(startGlobal, startElement);
  const endPoint = calculateBindingPoint(endGlobal, endElement);
  
  // Determine headings
  const startHeading = getBindPointHeading(startPoint, endPoint, startElement);
  const endHeading = getBindPointHeading(endPoint, startPoint, endElement);
  
  // Generate bounding boxes
  const startBounds = createBoundingBox(startPoint, startElement, startHeading);
  const endBounds = createBoundingBox(endPoint, endElement, endHeading);
  const commonBounds = getCommonBounds([startBounds, endBounds]);
  
  // Generate dynamic AABBs (obstacle regions)
  const dynamicAABBs = generateDynamicAABBs(startBounds, endBounds, commonBounds);
  
  // Calculate dongle positions
  const startDongle = getDonglePosition(dynamicAABBs[0], startHeading, startPoint);
  const endDongle = getDonglePosition(dynamicAABBs[1], endHeading, endPoint);
  
  return {
    startGlobalPoint: startPoint,
    endGlobalPoint: endPoint,
    startHeading,
    endHeading,
    dynamicAABBs,
    startDonglePosition: startDongle,
    endDonglePosition: endDongle,
    commonBounds,
    hoveredStartElement: startElement,
    hoveredEndElement: endElement
  };
}
```

---

## 7. Heading Determination

### 7.1 Basic Heading (No Element Binding)

When the arrow endpoint is not bound to any element, the heading is determined by the relative position of the other endpoint.

```typescript
function vectorToHeading(vector: [number, number]): Heading {
  const [x, y] = vector;
  const absX = Math.abs(x);
  const absY = Math.abs(y);
  
  if (x > absY) {
    return HEADING_RIGHT;
  } else if (x <= -absY) {
    return HEADING_LEFT;
  } else if (y > absX) {
    return HEADING_DOWN;
  }
  return HEADING_UP;
}

function getHeadingFromPoints(
  fromPoint: GlobalPoint, 
  toPoint: GlobalPoint
): Heading {
  const vector = [
    toPoint[0] - fromPoint[0],
    toPoint[1] - fromPoint[1]
  ];
  return vectorToHeading(vector);
}
```

### 7.2 Heading with Element Binding

When bound to an element, the heading is determined by which side of the element the binding point is on.

```typescript
function headingForPointFromElement(
  element: BindableElement,
  boundingBox: Bounds,
  point: GlobalPoint
): Heading {
  // Get the center of the element
  const centerX = (boundingBox[0] + boundingBox[2]) / 2;
  const centerY = (boundingBox[1] + boundingBox[3]) / 2;
  const center: GlobalPoint = [centerX, centerY];
  
  // Create search cones from the center
  const SEARCH_CONE_MULTIPLIER = 2;
  
  const topLeft = scaleFromOrigin([boundingBox[0], boundingBox[1]], center, SEARCH_CONE_MULTIPLIER);
  const topRight = scaleFromOrigin([boundingBox[2], boundingBox[1]], center, SEARCH_CONE_MULTIPLIER);
  const bottomLeft = scaleFromOrigin([boundingBox[0], boundingBox[3]], center, SEARCH_CONE_MULTIPLIER);
  const bottomRight = scaleFromOrigin([boundingBox[2], boundingBox[3]], center, SEARCH_CONE_MULTIPLIER);
  
  // Check which triangular region contains the point
  if (triangleContainsPoint([topLeft, topRight, center], point)) {
    return HEADING_UP;
  } else if (triangleContainsPoint([topRight, bottomRight, center], point)) {
    return HEADING_RIGHT;
  } else if (triangleContainsPoint([bottomRight, bottomLeft, center], point)) {
    return HEADING_DOWN;
  }
  return HEADING_LEFT;
}
```

### 7.3 Diamond Element Special Case

Diamond shapes require special handling because their edges are diagonal:

```typescript
function headingForDiamondElement(
  element: DiamondElement,
  boundingBox: Bounds,
  point: GlobalPoint
): Heading {
  const center = getCenterOfBounds(boundingBox);
  
  // Calculate the four vertices of the diamond
  const top = [center[0], boundingBox[1]];
  const right = [boundingBox[2], center[1]];
  const bottom = [center[0], boundingBox[3]];
  const left = [boundingBox[0], center[1]];
  
  // Use cross product to determine which edge the point is closest to
  // ... (detailed geometry calculations)
  
  // Return heading based on which edge region contains the point
}
```

---

## 8. Grid Construction

### 8.1 Non-Uniform Grid Concept

The routing grid is NOT a uniform grid. Instead, grid lines are placed at significant boundaries:
- Edges of bounding boxes
- Start and end point coordinates (aligned with their headings)
- Common bounds edges

This approach ensures:
- Exact paths along element boundaries
- Efficient memory usage (only needed positions)
- Faster pathfinding (fewer nodes)

### 8.2 Grid Calculation Algorithm

```typescript
function calculateGrid(
  aabbs: Bounds[],           // Dynamic bounding boxes
  start: GlobalPoint,        // Start dongle position
  startHeading: Heading,
  end: GlobalPoint,          // End dongle position
  endHeading: Heading,
  commonBounds: Bounds       // Overall bounds
): Grid {
  
  // Collect unique X coordinates (vertical lines)
  const verticalLines = new Set<number>();
  
  // Collect unique Y coordinates (horizontal lines)
  const horizontalLines = new Set<number>();
  
  // Add start position line based on heading
  if (startHeading === HEADING_LEFT || startHeading === HEADING_RIGHT) {
    horizontalLines.add(start[1]);  // Horizontal heading -> add Y
  } else {
    verticalLines.add(start[0]);    // Vertical heading -> add X
  }
  
  // Add end position line based on heading
  if (endHeading === HEADING_LEFT || endHeading === HEADING_RIGHT) {
    horizontalLines.add(end[1]);
  } else {
    verticalLines.add(end[0]);
  }
  
  // Add all AABB edges
  for (const aabb of aabbs) {
    verticalLines.add(aabb[0]);   // Left edge
    verticalLines.add(aabb[2]);   // Right edge
    horizontalLines.add(aabb[1]); // Top edge
    horizontalLines.add(aabb[3]); // Bottom edge
  }
  
  // Add common bounds edges
  verticalLines.add(commonBounds[0]);
  verticalLines.add(commonBounds[2]);
  horizontalLines.add(commonBounds[1]);
  horizontalLines.add(commonBounds[3]);
  
  // Sort the coordinates
  const sortedX = Array.from(verticalLines).sort((a, b) => a - b);
  const sortedY = Array.from(horizontalLines).sort((a, b) => a - b);
  
  // Create grid nodes at intersections
  const nodes: GridNode[] = [];
  for (let row = 0; row < sortedY.length; row++) {
    for (let col = 0; col < sortedX.length; col++) {
      nodes.push({
        f: 0,
        g: 0,
        h: 0,
        closed: false,
        visited: false,
        parent: null,
        pos: [sortedX[col], sortedY[row]],
        addr: [col, row]
      });
    }
  }
  
  return {
    row: sortedY.length,
    col: sortedX.length,
    data: nodes
  };
}
```

### 8.3 Grid Node Access

```typescript
function getNodeFromAddress(
  col: number, 
  row: number, 
  grid: Grid
): GridNode | null {
  if (col < 0 || col >= grid.col || row < 0 || row >= grid.row) {
    return null;
  }
  return grid.data[row * grid.col + col] ?? null;
}

function getNodeFromPoint(point: GlobalPoint, grid: Grid): GridNode | null {
  for (let col = 0; col < grid.col; col++) {
    for (let row = 0; row < grid.row; row++) {
      const node = getNodeFromAddress(col, row, grid);
      if (node && node.pos[0] === point[0] && node.pos[1] === point[1]) {
        return node;
      }
    }
  }
  return null;
}
```

---

## 9. A* Pathfinding Algorithm

### 9.1 Algorithm Overview

The A* algorithm finds the optimal path through the grid while:
1. Minimizing total distance
2. Penalizing direction changes (bends)
3. Avoiding obstacles (bounding boxes)
4. Preventing reverse movement

### 9.2 Core Implementation

```typescript
function astar(
  start: GridNode,
  end: GridNode,
  grid: Grid,
  startHeading: Heading,
  endHeading: Heading,
  obstacles: Bounds[]
): GridNode[] | null {
  
  // Bend penalty is proportional to total distance
  const bendMultiplier = manhattanDistance(start.pos, end.pos);
  
  // Priority queue (min-heap) ordered by f-score
  const openSet = new BinaryHeap<GridNode>((node) => node.f);
  openSet.push(start);
  
  while (openSet.size() > 0) {
    // Get node with lowest f-score
    const current = openSet.pop();
    
    if (!current || current.closed) {
      continue;
    }
    
    // Goal reached
    if (current === end) {
      return reconstructPath(start, current);
    }
    
    // Mark as processed
    current.closed = true;
    
    // Process neighbors (up, right, down, left)
    const neighbors = getNeighbors(current.addr, grid);
    
    for (let i = 0; i < 4; i++) {
      const neighbor = neighbors[i];
      
      if (!neighbor || neighbor.closed) {
        continue;
      }
      
      // Check obstacle intersection
      const midpoint = [
        (current.pos[0] + neighbor.pos[0]) / 2,
        (current.pos[1] + neighbor.pos[1]) / 2
      ];
      if (obstacles.some(aabb => pointInsideBounds(midpoint, aabb))) {
        continue;
      }
      
      // Determine direction of movement
      const neighborHeading = indexToHeading(i);
      const previousHeading = current.parent
        ? getHeading(current.pos, current.parent.pos)
        : startHeading;
      
      // Prevent reverse movement
      const reverseHeading = flipHeading(previousHeading);
      if (headingsEqual(reverseHeading, neighborHeading)) {
        continue;
      }
      
      // Prevent invalid start/end movements
      if (addressesEqual(start.addr, neighbor.addr) && 
          headingsEqual(neighborHeading, startHeading)) {
        continue;
      }
      if (addressesEqual(end.addr, neighbor.addr) && 
          headingsEqual(neighborHeading, endHeading)) {
        continue;
      }
      
      // Calculate cost
      const directionChanged = !headingsEqual(previousHeading, neighborHeading);
      const gScore = current.g 
        + manhattanDistance(neighbor.pos, current.pos)
        + (directionChanged ? Math.pow(bendMultiplier, 3) : 0);
      
      const beenVisited = neighbor.visited;
      
      if (!beenVisited || gScore < neighbor.g) {
        // Estimate remaining bends
        const estimatedBends = estimateBendCount(
          neighbor, end, neighborHeading, endHeading
        );
        
        // Update scores
        neighbor.visited = true;
        neighbor.parent = current;
        neighbor.g = gScore;
        neighbor.h = manhattanDistance(end.pos, neighbor.pos) 
                   + estimatedBends * Math.pow(bendMultiplier, 2);
        neighbor.f = neighbor.g + neighbor.h;
        
        if (!beenVisited) {
          openSet.push(neighbor);
        } else {
          openSet.rescoreElement(neighbor);
        }
      }
    }
  }
  
  // No path found
  return null;
}
```

### 9.3 Helper Functions

```typescript
function manhattanDistance(a: GlobalPoint, b: GlobalPoint): number {
  return Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]);
}

function getNeighbors(
  [col, row]: [number, number], 
  grid: Grid
): [GridNode | null, GridNode | null, GridNode | null, GridNode | null] {
  return [
    getNodeFromAddress(col, row - 1, grid),  // Up
    getNodeFromAddress(col + 1, row, grid),  // Right
    getNodeFromAddress(col, row + 1, grid),  // Down
    getNodeFromAddress(col - 1, row, grid)   // Left
  ];
}

function indexToHeading(index: number): Heading {
  switch (index) {
    case 0: return HEADING_UP;
    case 1: return HEADING_RIGHT;
    case 2: return HEADING_DOWN;
    default: return HEADING_LEFT;
  }
}

function flipHeading(heading: Heading): Heading {
  return [
    heading[0] === 0 ? 0 : -heading[0],
    heading[1] === 0 ? 0 : -heading[1]
  ] as Heading;
}

function reconstructPath(start: GridNode, end: GridNode): GridNode[] {
  const path: GridNode[] = [];
  let current: GridNode | null = end;
  
  while (current && current.parent) {
    path.unshift(current);
    current = current.parent;
  }
  path.unshift(start);
  
  return path;
}
```

### 9.4 Bend Count Estimation

The heuristic includes an estimate of how many bends are needed based on the relative positions and headings:

```typescript
function estimateBendCount(
  start: GridNode,
  end: GridNode,
  startHeading: Heading,
  endHeading: Heading
): number {
  const [sx, sy] = start.pos;
  const [ex, ey] = end.pos;
  
  // Example: End heading is RIGHT
  if (headingsEqual(endHeading, HEADING_RIGHT)) {
    if (headingsEqual(startHeading, HEADING_RIGHT)) {
      if (sx >= ex) return 4;        // Need to go around
      if (sy === ey) return 0;       // Direct horizontal line
      return 2;                       // One turn up/down, one back
    }
    if (headingsEqual(startHeading, HEADING_UP)) {
      if (sy > ey && sx < ex) return 1;
      return 3;
    }
    if (headingsEqual(startHeading, HEADING_DOWN)) {
      if (sy < ey && sx < ex) return 1;
      return 3;
    }
    // HEADING_LEFT
    if (sy === ey) return 4;
    return 2;
  }
  
  // Similar logic for other end headings...
  // (Full implementation covers all 16 combinations)
  
  return 0;
}
```

---

## 10. Post-Processing

### 10.1 Adding Start and End Points

After A* finds a path between dongles, the actual start and end points must be added:

```typescript
function addEndpoints(
  path: GridNode[],
  startPoint: GlobalPoint,
  endPoint: GlobalPoint,
  startDongle: GlobalPoint | null,
  endDongle: GlobalPoint | null
): GlobalPoint[] {
  const points = path.map(node => node.pos);
  
  // Add start point if there's a dongle
  if (startDongle) {
    points.unshift(startPoint);
  }
  
  // Add end point if there's a dongle
  if (endDongle) {
    points.push(endPoint);
  }
  
  return points;
}
```

### 10.2 Removing Short Segments

Very short segments (less than threshold) are removed for cleaner output:

```typescript
function removeShortSegments(
  points: GlobalPoint[],
  threshold: number = 1
): GlobalPoint[] {
  if (points.length < 4) {
    return points;
  }
  
  return points.filter((point, index) => {
    // Always keep first and last points
    if (index === 0 || index === points.length - 1) {
      return true;
    }
    
    const prevPoint = points[index - 1];
    const distance = manhattanDistance(prevPoint, point);
    return distance > threshold;
  });
}
```

### 10.3 Extracting Corner Points

Remove intermediate points that lie on the same line (keep only corners):

```typescript
function getCornerPoints(points: GlobalPoint[]): GlobalPoint[] {
  if (points.length <= 2) {
    return points;
  }
  
  let previousIsHorizontal = 
    Math.abs(points[0][1] - points[1][1]) < 
    Math.abs(points[0][0] - points[1][0]);
  
  return points.filter((point, index) => {
    // Always keep first and last
    if (index === 0 || index === points.length - 1) {
      return true;
    }
    
    const nextPoint = points[index + 1];
    const nextIsHorizontal = 
      Math.abs(point[1] - nextPoint[1]) < 
      Math.abs(point[0] - nextPoint[0]);
    
    // Keep if direction changes
    if (previousIsHorizontal !== nextIsHorizontal) {
      previousIsHorizontal = nextIsHorizontal;
      return true;
    }
    
    previousIsHorizontal = nextIsHorizontal;
    return false;
  });
}
```

### 10.4 Normalizing to Local Coordinates

Convert global points to local points relative to the first point:

```typescript
function normalizeToLocalCoordinates(
  globalPoints: GlobalPoint[]
): { x: number; y: number; points: LocalPoint[]; width: number; height: number } {
  const offsetX = globalPoints[0][0];
  const offsetY = globalPoints[0][1];
  
  const localPoints = globalPoints.map(([gx, gy]) => [
    gx - offsetX,
    gy - offsetY
  ] as LocalPoint);
  
  // Calculate dimensions
  const xs = localPoints.map(p => p[0]);
  const ys = localPoints.map(p => p[1]);
  const width = Math.max(...xs) - Math.min(...xs);
  const height = Math.max(...ys) - Math.min(...ys);
  
  return {
    x: offsetX,
    y: offsetY,
    points: localPoints,
    width,
    height
  };
}
```

---

## 11. Element Binding

### 11.1 Binding Point Calculation

When an arrow endpoint is bound to an element, calculate the exact position on the element's boundary:

```typescript
function calculateBindingPoint(
  desiredPoint: GlobalPoint,
  element: BindableElement | null,
  fixedPointRatio?: [number, number]
): GlobalPoint {
  if (!element) {
    return desiredPoint;
  }
  
  if (fixedPointRatio) {
    // Use the fixed point ratio to calculate exact position
    return getFixedPointOnElement(element, fixedPointRatio);
  }
  
  // Snap to the element's outline
  return snapToElementOutline(element, desiredPoint);
}

function getFixedPointOnElement(
  element: BindableElement,
  ratio: [number, number]
): GlobalPoint {
  const [rx, ry] = ratio;
  const bounds = getElementBounds(element);
  
  return [
    bounds[0] + (bounds[2] - bounds[0]) * rx,
    bounds[1] + (bounds[3] - bounds[1]) * ry
  ];
}
```

### 11.2 Creating Obstacle Bounding Boxes

When bound to elements, the arrow must route around them:

```typescript
function createBoundingBox(
  point: GlobalPoint,
  element: BindableElement | null,
  heading: Heading,
  hasArrowhead: boolean = false
): Bounds {
  if (!element) {
    // Create small bounds around the point itself
    return [
      point[0] - 2,
      point[1] - 2,
      point[0] + 2,
      point[1] + 2
    ];
  }
  
  // Get element bounds with directional padding
  const baseOffset = hasArrowhead ? 12 : 4;  // More space for arrowheads
  const padding = offsetFromHeading(heading, baseOffset, 2);
  
  return getElementBoundsWithOffset(element, padding);
}

function offsetFromHeading(
  heading: Heading,
  headOffset: number,
  sideOffset: number
): [number, number, number, number] {
  // Returns [top, right, bottom, left] padding
  switch (heading) {
    case HEADING_UP:
      return [headOffset, sideOffset, sideOffset, sideOffset];
    case HEADING_RIGHT:
      return [sideOffset, headOffset, sideOffset, sideOffset];
    case HEADING_DOWN:
      return [sideOffset, sideOffset, headOffset, sideOffset];
    case HEADING_LEFT:
      return [sideOffset, sideOffset, sideOffset, headOffset];
  }
}
```

---

## 12. Fixed Segments (Manual Adjustment)

### 12.1 Concept

Users can manually drag segments of an elbow arrow. When they do:
1. The dragged segment becomes "fixed"
2. The arrow must maintain that segment's position
3. Adjacent segments adjust to accommodate

### 12.2 Data Structure

```typescript
interface FixedSegment {
  // Which segment (index of end point in points array)
  index: number;
  
  // The fixed segment endpoints (in local coordinates)
  start: LocalPoint;
  end: LocalPoint;
}
```

### 12.3 Segment Move Handling

```typescript
function handleSegmentMove(
  arrow: ElbowArrowElement,
  fixedSegments: FixedSegment[],
  startHeading: Heading,
  endHeading: Heading
): ElementUpdate {
  
  // Find which segment is being actively modified
  const activeSegmentIdx = findActivelyModifiedSegment(
    arrow.fixedSegments,
    fixedSegments
  );
  
  if (activeSegmentIdx === null) {
    return { points: arrow.points };
  }
  
  const activeSegment = fixedSegments[activeSegmentIdx];
  
  // Clone existing points
  const newPoints = arrow.points.map(p => [...p]) as LocalPoint[];
  
  // Update the segment endpoints
  const startIdx = activeSegment.index - 1;
  const endIdx = activeSegment.index;
  
  newPoints[startIdx] = activeSegment.start;
  newPoints[endIdx] = activeSegment.end;
  
  // Adjust adjacent points to maintain orthogonality
  adjustAdjacentPoints(newPoints, startIdx, endIdx);
  
  // May need to insert additional points for first/last segment moves
  handleEdgeSegmentMoves(newPoints, arrow, activeSegment, startHeading, endHeading);
  
  return normalizeToLocalCoordinates(
    newPoints.map(p => toGlobalPoint(p, arrow.x, arrow.y))
  );
}
```

### 12.4 Segment Release

When a user releases a fixed segment, recalculate that portion of the path:

```typescript
function handleSegmentRelease(
  arrow: ElbowArrowElement,
  fixedSegments: FixedSegment[],
  elementsMap: Map<string, Element>
): ElementUpdate {
  
  // Find which segment was released
  const releasedIdx = findReleasedSegment(arrow.fixedSegments, fixedSegments);
  
  if (releasedIdx === -1) {
    return { points: arrow.points };
  }
  
  // Find the surrounding fixed segments
  const prevFixed = fixedSegments.find(s => s.index < releasedIdx);
  const nextFixed = fixedSegments.find(s => s.index > releasedIdx);
  
  // Recalculate the path between prev and next fixed segments
  const subPath = routeSubPath(
    prevFixed ? prevFixed.end : arrow.points[0],
    nextFixed ? nextFixed.start : arrow.points[arrow.points.length - 1],
    elementsMap
  );
  
  // Merge the subpath with existing points
  return mergeSubPath(arrow.points, subPath, prevFixed, nextFixed);
}
```

---

## 13. Edge Cases & Error Handling

### 13.1 Overlapping Start and End

When start and end points are very close or overlapping:

```typescript
function handleOverlappingEndpoints(
  startPoint: GlobalPoint,
  endPoint: GlobalPoint
): GlobalPoint[] {
  const distance = manhattanDistance(startPoint, endPoint);
  
  if (distance < MIN_ARROW_LENGTH) {
    // Create a small S-curve or return minimal path
    const midY = (startPoint[1] + endPoint[1]) / 2;
    return [
      startPoint,
      [startPoint[0], midY],
      [endPoint[0], midY],
      endPoint
    ];
  }
  
  // Normal processing
  return null; // Continue with normal algorithm
}
```

### 13.2 No Valid Path Found

If A* cannot find a path:

```typescript
function handleNoPathFound(
  startPoint: GlobalPoint,
  endPoint: GlobalPoint,
  startHeading: Heading,
  endHeading: Heading
): GlobalPoint[] {
  // Fallback: create a simple path with minimal bends
  const midX = (startPoint[0] + endPoint[0]) / 2;
  const midY = (startPoint[1] + endPoint[1]) / 2;
  
  if (headingIsHorizontal(startHeading)) {
    return [
      startPoint,
      [midX, startPoint[1]],
      [midX, endPoint[1]],
      endPoint
    ];
  } else {
    return [
      startPoint,
      [startPoint[0], midY],
      [endPoint[0], midY],
      endPoint
    ];
  }
}
```

### 13.3 Invalid Points Validation

```typescript
function validateElbowPoints(points: LocalPoint[], tolerance: number = 1): boolean {
  return points.slice(1).every((point, i) => {
    const prevPoint = points[i];
    
    // Each segment must be either horizontal or vertical
    const isHorizontal = Math.abs(point[1] - prevPoint[1]) < tolerance;
    const isVertical = Math.abs(point[0] - prevPoint[0]) < tolerance;
    
    return isHorizontal || isVertical;
  });
}
```

### 13.4 Coordinate Bounds Clamping

Prevent infinite or extremely large coordinates:

```typescript
function clampCoordinates(points: GlobalPoint[]): GlobalPoint[] {
  const MAX = 1_000_000;
  const MIN = -1_000_000;
  
  return points.map(([x, y]) => [
    Math.max(MIN, Math.min(MAX, x)),
    Math.max(MIN, Math.min(MAX, y))
  ]);
}
```

---

## 14. Performance Considerations

### 14.1 Binary Heap for A*

Use a binary heap (min-heap) for the open set to achieve O(log n) insertion and extraction:

```typescript
class BinaryHeap<T> {
  private content: T[] = [];
  private scoreFunction: (element: T) => number;
  
  constructor(scoreFunction: (element: T) => number) {
    this.scoreFunction = scoreFunction;
  }
  
  push(element: T): void {
    this.content.push(element);
    this.sinkDown(this.content.length - 1);
  }
  
  pop(): T | undefined {
    const result = this.content[0];
    const end = this.content.pop();
    
    if (this.content.length > 0 && end !== undefined) {
      this.content[0] = end;
      this.bubbleUp(0);
    }
    
    return result;
  }
  
  rescoreElement(element: T): void {
    const index = this.content.indexOf(element);
    if (index !== -1) {
      this.sinkDown(index);
    }
  }
  
  size(): number {
    return this.content.length;
  }
  
  // ... heap operations (sinkDown, bubbleUp)
}
```

### 14.2 Grid Size Optimization

The non-uniform grid naturally limits the number of nodes. Additional optimizations:

```typescript
function optimizeGrid(grid: Grid, maxNodes: number = 1000): Grid {
  if (grid.data.length <= maxNodes) {
    return grid;
  }
  
  // If grid is too large, simplify by removing intermediate lines
  // This may reduce path quality but ensures performance
  // ...
}
```

### 14.3 Early Exit Conditions

```typescript
// In A* loop
if (iterations > MAX_ITERATIONS) {
  console.warn('A* exceeded max iterations, using fallback');
  return generateFallbackPath(start, end);
}

// Direct path check
if (canDrawDirectPath(start, end, obstacles)) {
  return [start.pos, end.pos];
}
```

---

## 15. Testing Strategy

### 15.1 Unit Tests

```typescript
describe('Elbow Arrow Path Generation', () => {
  
  describe('Basic Path Generation', () => {
    it('should generate horizontal path for horizontally aligned points', () => {
      const start = [0, 100];
      const end = [200, 100];
      const path = generateElbowPath(start, end);
      
      expect(path.length).toBe(2);
      expect(path[0]).toEqual(start);
      expect(path[1]).toEqual(end);
    });
    
    it('should generate L-shaped path for diagonal points', () => {
      const start = [0, 0];
      const end = [100, 100];
      const path = generateElbowPath(start, end);
      
      expect(path.length).toBe(3);
      expect(validateElbowPoints(path)).toBe(true);
    });
    
    it('should generate path with minimum bends', () => {
      const start = [0, 0];
      const end = [100, 50];
      const path = generateElbowPath(start, end);
      
      const bendCount = countBends(path);
      expect(bendCount).toBeLessThanOrEqual(2);
    });
  });
  
  describe('Heading Determination', () => {
    it('should return RIGHT for point to the right', () => {
      const heading = vectorToHeading([100, 10]);
      expect(heading).toEqual(HEADING_RIGHT);
    });
    
    it('should return DOWN for point below', () => {
      const heading = vectorToHeading([10, 100]);
      expect(heading).toEqual(HEADING_DOWN);
    });
  });
  
  describe('Obstacle Avoidance', () => {
    it('should route around obstacle', () => {
      const start = [0, 50];
      const end = [200, 50];
      const obstacle = [50, 0, 150, 100];
      
      const path = generateElbowPath(start, end, [obstacle]);
      
      // Path should not intersect obstacle
      expect(pathIntersectsObstacle(path, obstacle)).toBe(false);
    });
  });
  
  describe('Validation', () => {
    it('should validate correct elbow points', () => {
      const points = [[0, 0], [100, 0], [100, 100]];
      expect(validateElbowPoints(points)).toBe(true);
    });
    
    it('should reject diagonal segments', () => {
      const points = [[0, 0], [100, 100]];
      expect(validateElbowPoints(points)).toBe(false);
    });
  });
});
```

### 15.2 Visual Tests

Create visual test cases with known expected outputs:

```typescript
const visualTestCases = [
  {
    name: 'Simple horizontal',
    start: [0, 0],
    end: [100, 0],
    expectedPath: [[0, 0], [100, 0]]
  },
  {
    name: 'L-shape down-right',
    start: [0, 0],
    end: [100, 100],
    startHeading: HEADING_DOWN,
    endHeading: HEADING_LEFT,
    // Expected: vertical then horizontal
  },
  // ... more cases
];
```

### 15.3 Performance Tests

```typescript
describe('Performance', () => {
  it('should generate path within 16ms', () => {
    const start = [0, 0];
    const end = [5000, 3000];
    
    const startTime = performance.now();
    generateElbowPath(start, end);
    const duration = performance.now() - startTime;
    
    expect(duration).toBeLessThan(16);
  });
  
  it('should handle 100 arrows efficiently', () => {
    const arrows = generateRandomArrows(100);
    
    const startTime = performance.now();
    arrows.forEach(arrow => updateElbowArrowPoints(arrow, new Map(), {}));
    const duration = performance.now() - startTime;
    
    expect(duration).toBeLessThan(500); // 5ms per arrow average
  });
});
```

---

## Appendix A: Complete Type Definitions

```typescript
// Points
type GlobalPoint = [number, number];
type LocalPoint = [number, number];

// Heading
type Heading = [1, 0] | [0, 1] | [-1, 0] | [0, -1];

// Bounds (AABB)
type Bounds = [minX: number, minY: number, maxX: number, maxY: number];

// Grid
interface GridNode {
  f: number;
  g: number;
  h: number;
  closed: boolean;
  visited: boolean;
  parent: GridNode | null;
  pos: GlobalPoint;
  addr: [number, number];
}

interface Grid {
  row: number;
  col: number;
  data: GridNode[];
}

// Arrow Element
interface ElbowArrowElement {
  x: number;
  y: number;
  width: number;
  height: number;
  points: LocalPoint[];
  startBinding: PointBinding | null;
  endBinding: PointBinding | null;
  startArrowhead: string | null;
  endArrowhead: string | null;
  fixedSegments: FixedSegment[] | null;
}

// Binding
interface PointBinding {
  elementId: string;
  fixedPoint: [number, number];
  focus?: number;
  gap?: number;
}

// Fixed Segment
interface FixedSegment {
  index: number;
  start: LocalPoint;
  end: LocalPoint;
}

// Element Update
interface ElementUpdate {
  x?: number;
  y?: number;
  width?: number;
  height?: number;
  points?: LocalPoint[];
  fixedSegments?: FixedSegment[] | null;
}

// Arrow Data (intermediate calculation)
interface ElbowArrowData {
  dynamicAABBs: Bounds[];
  startDonglePosition: GlobalPoint | null;
  startGlobalPoint: GlobalPoint;
  startHeading: Heading;
  endDonglePosition: GlobalPoint | null;
  endGlobalPoint: GlobalPoint;
  endHeading: Heading;
  commonBounds: Bounds;
  hoveredStartElement: BindableElement | null;
  hoveredEndElement: BindableElement | null;
}
```

---

## Appendix B: Reference Diagrams

### B.1 Path Generation Flow

```
Start Point (100, 50)                    End Point (300, 150)
       ●──────────────────────┐                    
       │                      │                    
       │     START AABB       │                    
       │     [60,10,140,90]   │                    
       │                      │                    
       └──────────────────────┘                    
                   │                               
                   │ Start Dongle (100, 10)        
                   ▼                               
       ┌──────────────────────┐                    
       │                      │                    
       │        GRID          │     ┌─────────────┐
       │                      │     │   END AABB  │
       │    A* finds path     │────▶│[260,110,340,│
       │                      │     │    190]     │
       │                      │     └─────────────┘
       └──────────────────────┘            │       
                   │                       │       
                   ▼                       ▼       
              End Dongle (340, 150)   ────▶ ●      
                                      End Point    
```

### B.2 Heading Determination Zones

```
                    TOP (HEADING_UP)
                         ╱╲
                        ╱  ╲
                       ╱    ╲
                      ╱      ╲
                     ╱        ╲
    LEFT            ╱  CENTER  ╲           RIGHT
 (HEADING_LEFT)    ╱     ●      ╲    (HEADING_RIGHT)
                   ╲            ╱
                    ╲          ╱
                     ╲        ╱
                      ╲      ╱
                       ╲    ╱
                        ╲  ╱
                         ╲╱
                  BOTTOM (HEADING_DOWN)
```

---

## Appendix C: Glossary

| Term | Definition |
|------|------------|
| **AABB** | Axis-Aligned Bounding Box - a rectangle aligned with coordinate axes |
| **Bend** | A 90-degree turn in the elbow arrow path |
| **Binding** | Connection of an arrow endpoint to another element |
| **Dongle** | An intermediate point extending from start/end along the heading |
| **Heading** | The cardinal direction (UP/DOWN/LEFT/RIGHT) an arrow exits or enters |
| **Manhattan Distance** | Sum of absolute differences of coordinates: \|x1-x2\| + \|y1-y2\| |
| **Orthogonal** | At right angles; elbow arrows only have orthogonal segments |
| **Segment** | A straight line portion of the arrow between two consecutive points |

---

*Document Version: 1.0*  
*Last Updated: 2026-01-29*
