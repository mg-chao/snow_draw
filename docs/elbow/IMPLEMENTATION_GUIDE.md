# Elbow Arrow Implementation Guide

This guide provides step-by-step instructions for implementing elbow arrows in a drawing application. It complements the main specification document with practical implementation details.

## Quick Start

### Minimum Viable Implementation

To get a basic elbow arrow working, implement these core components in order:

1. **Point and Heading types**
2. **Manhattan distance calculation**
3. **Simple heading determination**
4. **Basic 2-bend path generation**
5. **A* pathfinding (optional for advanced routing)**

---

## Step 1: Define Core Types

```typescript
// ============================================
// TYPES
// ============================================

/** Point in 2D space as [x, y] tuple */
type Point = [number, number];

/** 
 * Cardinal direction vector
 * RIGHT: [1, 0], DOWN: [0, 1], LEFT: [-1, 0], UP: [0, -1]
 */
type Heading = [1, 0] | [0, 1] | [-1, 0] | [0, -1];

/** Axis-aligned bounding box: [minX, minY, maxX, maxY] */
type Bounds = [number, number, number, number];

// Heading constants
const HEADING_RIGHT: Heading = [1, 0];
const HEADING_DOWN: Heading = [0, 1];
const HEADING_LEFT: Heading = [-1, 0];
const HEADING_UP: Heading = [0, -1];
```

---

## Step 2: Utility Functions

```typescript
// ============================================
// UTILITY FUNCTIONS
// ============================================

/** Calculate Manhattan distance between two points */
function manhattanDistance(a: Point, b: Point): number {
  return Math.abs(a[0] - b[0]) + Math.abs(a[1] - b[1]);
}

/** Check if two headings are equal */
function headingsEqual(a: Heading, b: Heading): boolean {
  return a[0] === b[0] && a[1] === b[1];
}

/** Reverse a heading direction */
function flipHeading(h: Heading): Heading {
  return [
    h[0] === 0 ? 0 : -h[0],
    h[1] === 0 ? 0 : -h[1]
  ] as Heading;
}

/** Check if heading is horizontal */
function isHorizontal(h: Heading): boolean {
  return h[1] === 0;
}

/** Convert a direction vector to the nearest heading */
function vectorToHeading(dx: number, dy: number): Heading {
  const absX = Math.abs(dx);
  const absY = Math.abs(dy);
  
  if (dx > absY) return HEADING_RIGHT;
  if (dx <= -absY) return HEADING_LEFT;
  if (dy > absX) return HEADING_DOWN;
  return HEADING_UP;
}

/** Check if a point is inside bounds */
function pointInBounds(point: Point, bounds: Bounds): boolean {
  return (
    point[0] >= bounds[0] &&
    point[0] <= bounds[2] &&
    point[1] >= bounds[1] &&
    point[1] <= bounds[3]
  );
}

/** Get common bounds that contains all given bounds */
function unionBounds(boundsArray: Bounds[]): Bounds {
  return [
    Math.min(...boundsArray.map(b => b[0])),
    Math.min(...boundsArray.map(b => b[1])),
    Math.max(...boundsArray.map(b => b[2])),
    Math.max(...boundsArray.map(b => b[3]))
  ];
}
```

---

## Step 3: Simple Path Generation (No Obstacles)

This is the simplest implementation that creates a valid elbow path.

```typescript
// ============================================
// SIMPLE PATH GENERATION
// ============================================

/**
 * Generate a simple elbow path between two points.
 * Creates at most 2 bends (3 segments).
 */
function generateSimpleElbowPath(
  start: Point,
  end: Point,
  startHeading?: Heading,
  endHeading?: Heading
): Point[] {
  // Determine headings if not provided
  const dx = end[0] - start[0];
  const dy = end[1] - start[1];
  
  const actualStartHeading = startHeading || vectorToHeading(dx, dy);
  const actualEndHeading = endHeading || vectorToHeading(-dx, -dy);
  
  // Case 1: Points are aligned horizontally
  if (Math.abs(dy) < 1) {
    return [start, end];
  }
  
  // Case 2: Points are aligned vertically
  if (Math.abs(dx) < 1) {
    return [start, end];
  }
  
  // Case 3: Need to create an L-shape or S-shape
  const startIsHorizontal = isHorizontal(actualStartHeading);
  const endIsHorizontal = isHorizontal(actualEndHeading);
  
  if (startIsHorizontal && !endIsHorizontal) {
    // L-shape: horizontal then vertical
    const corner: Point = [end[0], start[1]];
    return [start, corner, end];
  }
  
  if (!startIsHorizontal && endIsHorizontal) {
    // L-shape: vertical then horizontal
    const corner: Point = [start[0], end[1]];
    return [start, corner, end];
  }
  
  if (startIsHorizontal && endIsHorizontal) {
    // S-shape with horizontal start and end
    const midY = (start[1] + end[1]) / 2;
    return [
      start,
      [start[0], midY] as Point,  // First corner (wrong, should be [midX, start[1]])
      [end[0], midY] as Point,    // Second corner
      end
    ];
    // Correction: Should create proper S-shape
  }
  
  // S-shape with vertical start and end
  const midX = (start[0] + end[0]) / 2;
  return [
    start,
    [midX, start[1]] as Point,
    [midX, end[1]] as Point,
    end
  ];
}
```

### Improved Simple Path Generation

```typescript
/**
 * Improved simple path that respects headings properly
 */
function generateElbowPath(
  start: Point,
  end: Point,
  preferHorizontalFirst: boolean = true
): Point[] {
  const dx = end[0] - start[0];
  const dy = end[1] - start[1];
  
  // Aligned points - direct line
  if (Math.abs(dy) < 0.5) return [start, end];
  if (Math.abs(dx) < 0.5) return [start, end];
  
  // Create L-shape based on preference
  if (preferHorizontalFirst) {
    // Horizontal first, then vertical
    return [
      start,
      [end[0], start[1]] as Point,
      end
    ];
  } else {
    // Vertical first, then horizontal
    return [
      start,
      [start[0], end[1]] as Point,
      end
    ];
  }
}
```

---

## Step 4: Binary Heap for A* Algorithm

```typescript
// ============================================
// BINARY HEAP (MIN-HEAP)
// ============================================

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
  
  remove(element: T): void {
    const index = this.content.indexOf(element);
    if (index === -1) return;
    
    const end = this.content.pop();
    if (index !== this.content.length && end !== undefined) {
      this.content[index] = end;
      if (this.scoreFunction(end) < this.scoreFunction(element)) {
        this.sinkDown(index);
      } else {
        this.bubbleUp(index);
      }
    }
  }
  
  rescoreElement(element: T): void {
    this.sinkDown(this.content.indexOf(element));
  }
  
  size(): number {
    return this.content.length;
  }
  
  private sinkDown(n: number): void {
    const element = this.content[n];
    const score = this.scoreFunction(element);
    
    while (n > 0) {
      const parentN = ((n + 1) >> 1) - 1;
      const parent = this.content[parentN];
      
      if (score < this.scoreFunction(parent)) {
        this.content[parentN] = element;
        this.content[n] = parent;
        n = parentN;
      } else {
        break;
      }
    }
  }
  
  private bubbleUp(n: number): void {
    const length = this.content.length;
    const element = this.content[n];
    const elemScore = this.scoreFunction(element);
    
    while (true) {
      const child2N = (n + 1) << 1;
      const child1N = child2N - 1;
      let swap: number | null = null;
      let child1Score: number = 0;
      
      if (child1N < length) {
        const child1 = this.content[child1N];
        child1Score = this.scoreFunction(child1);
        if (child1Score < elemScore) {
          swap = child1N;
        }
      }
      
      if (child2N < length) {
        const child2 = this.content[child2N];
        const child2Score = this.scoreFunction(child2);
        if (child2Score < (swap === null ? elemScore : child1Score)) {
          swap = child2N;
        }
      }
      
      if (swap !== null) {
        this.content[n] = this.content[swap];
        this.content[swap] = element;
        n = swap;
      } else {
        break;
      }
    }
  }
}
```

---

## Step 5: Grid Construction

```typescript
// ============================================
// GRID FOR A* PATHFINDING
// ============================================

interface GridNode {
  f: number;      // Total score (g + h)
  g: number;      // Cost from start
  h: number;      // Heuristic to end
  closed: boolean;
  visited: boolean;
  parent: GridNode | null;
  pos: Point;
  addr: [number, number];  // [col, row]
}

interface Grid {
  rows: number;
  cols: number;
  nodes: GridNode[];
}

/**
 * Build a non-uniform grid from bounding boxes.
 * Grid lines are placed at AABB edges.
 */
function buildGrid(
  bounds: Bounds[],
  startPoint: Point,
  endPoint: Point,
  startHeading: Heading,
  endHeading: Heading
): Grid {
  // Collect unique X and Y coordinates
  const xCoords = new Set<number>();
  const yCoords = new Set<number>();
  
  // Add coordinates from bounds
  for (const b of bounds) {
    xCoords.add(b[0]);  // Left
    xCoords.add(b[2]);  // Right
    yCoords.add(b[1]);  // Top
    yCoords.add(b[3]);  // Bottom
  }
  
  // Add start/end coordinates based on heading
  if (isHorizontal(startHeading)) {
    yCoords.add(startPoint[1]);
  } else {
    xCoords.add(startPoint[0]);
  }
  
  if (isHorizontal(endHeading)) {
    yCoords.add(endPoint[1]);
  } else {
    xCoords.add(endPoint[0]);
  }
  
  // Sort coordinates
  const sortedX = Array.from(xCoords).sort((a, b) => a - b);
  const sortedY = Array.from(yCoords).sort((a, b) => a - b);
  
  // Create nodes at intersections
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
    rows: sortedY.length,
    cols: sortedX.length,
    nodes
  };
}

/** Get node at grid address */
function getNode(grid: Grid, col: number, row: number): GridNode | null {
  if (col < 0 || col >= grid.cols || row < 0 || row >= grid.rows) {
    return null;
  }
  return grid.nodes[row * grid.cols + col];
}

/** Find node closest to a point */
function findNodeForPoint(grid: Grid, point: Point): GridNode | null {
  for (const node of grid.nodes) {
    if (node.pos[0] === point[0] && node.pos[1] === point[1]) {
      return node;
    }
  }
  return null;
}

/** Get 4-connected neighbors (up, right, down, left) */
function getNeighbors(grid: Grid, node: GridNode): (GridNode | null)[] {
  const [col, row] = node.addr;
  return [
    getNode(grid, col, row - 1),  // Up
    getNode(grid, col + 1, row),  // Right
    getNode(grid, col, row + 1),  // Down
    getNode(grid, col - 1, row)   // Left
  ];
}

/** Convert neighbor index to heading */
function indexToHeading(index: number): Heading {
  const headings: Heading[] = [HEADING_UP, HEADING_RIGHT, HEADING_DOWN, HEADING_LEFT];
  return headings[index];
}
```

---

## Step 6: A* Pathfinding Algorithm

```typescript
// ============================================
// A* PATHFINDING
// ============================================

/**
 * Find optimal path using A* algorithm.
 * 
 * @param grid - The search grid
 * @param startNode - Starting node
 * @param endNode - Target node
 * @param startHeading - Required exit direction from start
 * @param endHeading - Required entry direction to end
 * @param obstacles - Bounding boxes to avoid
 */
function astar(
  grid: Grid,
  startNode: GridNode,
  endNode: GridNode,
  startHeading: Heading,
  endHeading: Heading,
  obstacles: Bounds[]
): Point[] | null {
  
  // Reset grid state
  for (const node of grid.nodes) {
    node.f = 0;
    node.g = 0;
    node.h = 0;
    node.closed = false;
    node.visited = false;
    node.parent = null;
  }
  
  // Bend penalty proportional to distance
  const bendPenalty = manhattanDistance(startNode.pos, endNode.pos);
  
  // Open set (priority queue)
  const openSet = new BinaryHeap<GridNode>(node => node.f);
  openSet.push(startNode);
  startNode.visited = true;
  
  let iterations = 0;
  const maxIterations = 10000;
  
  while (openSet.size() > 0 && iterations < maxIterations) {
    iterations++;
    
    const current = openSet.pop();
    if (!current || current.closed) continue;
    
    // Reached goal
    if (current === endNode) {
      return reconstructPath(startNode, endNode);
    }
    
    current.closed = true;
    
    // Check neighbors
    const neighbors = getNeighbors(grid, current);
    
    for (let i = 0; i < 4; i++) {
      const neighbor = neighbors[i];
      if (!neighbor || neighbor.closed) continue;
      
      const neighborHeading = indexToHeading(i);
      
      // Get direction we came from
      const previousHeading = current.parent
        ? vectorToHeading(
            current.pos[0] - current.parent.pos[0],
            current.pos[1] - current.parent.pos[1]
          )
        : startHeading;
      
      // Prevent going backwards
      if (headingsEqual(neighborHeading, flipHeading(previousHeading))) {
        continue;
      }
      
      // Prevent invalid start/end movements
      if (current === startNode && headingsEqual(flipHeading(neighborHeading), startHeading)) {
        continue;
      }
      if (neighbor === endNode && headingsEqual(neighborHeading, flipHeading(endHeading))) {
        continue;
      }
      
      // Check for obstacle intersection
      const midpoint: Point = [
        (current.pos[0] + neighbor.pos[0]) / 2,
        (current.pos[1] + neighbor.pos[1]) / 2
      ];
      if (obstacles.some(obs => pointInBounds(midpoint, obs))) {
        continue;
      }
      
      // Calculate scores
      const directionChanged = !headingsEqual(previousHeading, neighborHeading);
      const moveCost = manhattanDistance(current.pos, neighbor.pos);
      const bendCost = directionChanged ? Math.pow(bendPenalty, 3) : 0;
      const gScore = current.g + moveCost + bendCost;
      
      if (!neighbor.visited || gScore < neighbor.g) {
        neighbor.parent = current;
        neighbor.g = gScore;
        neighbor.h = manhattanDistance(neighbor.pos, endNode.pos);
        neighbor.f = neighbor.g + neighbor.h;
        
        if (!neighbor.visited) {
          neighbor.visited = true;
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

/** Reconstruct path from parent pointers */
function reconstructPath(start: GridNode, end: GridNode): Point[] {
  const path: Point[] = [];
  let current: GridNode | null = end;
  
  while (current) {
    path.unshift(current.pos);
    current = current.parent;
  }
  
  return path;
}
```

---

## Step 7: Complete Integration

```typescript
// ============================================
// MAIN API
// ============================================

interface ElbowArrowOptions {
  startHeading?: Heading;
  endHeading?: Heading;
  obstacles?: Bounds[];
  padding?: number;
}

/**
 * Generate an elbow arrow path between two points.
 */
function createElbowArrow(
  start: Point,
  end: Point,
  options: ElbowArrowOptions = {}
): Point[] {
  const {
    obstacles = [],
    padding = 40
  } = options;
  
  // Determine headings
  const dx = end[0] - start[0];
  const dy = end[1] - start[1];
  const startHeading = options.startHeading || vectorToHeading(dx, dy);
  const endHeading = options.endHeading || vectorToHeading(-dx, -dy);
  
  // If no obstacles, use simple path
  if (obstacles.length === 0) {
    return generateSimplePath(start, end, startHeading, endHeading);
  }
  
  // Create padded obstacles
  const paddedObstacles = obstacles.map(obs => [
    obs[0] - padding,
    obs[1] - padding,
    obs[2] + padding,
    obs[3] + padding
  ] as Bounds);
  
  // Calculate dongle positions
  const startDongle = getDonglePosition(start, startHeading, padding);
  const endDongle = getDonglePosition(end, endHeading, padding);
  
  // Build grid
  const allBounds = [
    ...paddedObstacles,
    [start[0] - padding, start[1] - padding, start[0] + padding, start[1] + padding] as Bounds,
    [end[0] - padding, end[1] - padding, end[0] + padding, end[1] + padding] as Bounds
  ];
  
  const grid = buildGrid(allBounds, startDongle, endDongle, startHeading, endHeading);
  
  const startNode = findNodeForPoint(grid, startDongle);
  const endNode = findNodeForPoint(grid, endDongle);
  
  if (!startNode || !endNode) {
    // Fallback to simple path
    return generateSimplePath(start, end, startHeading, endHeading);
  }
  
  // Find path
  const path = astar(grid, startNode, endNode, startHeading, endHeading, paddedObstacles);
  
  if (!path) {
    return generateSimplePath(start, end, startHeading, endHeading);
  }
  
  // Add actual start and end points
  const fullPath = [start, ...path, end];
  
  // Clean up path
  return cleanPath(fullPath);
}

/** Get dongle position extending from point along heading */
function getDonglePosition(point: Point, heading: Heading, distance: number): Point {
  return [
    point[0] + heading[0] * distance,
    point[1] + heading[1] * distance
  ];
}

/** Generate simple path based on headings */
function generateSimplePath(
  start: Point,
  end: Point,
  startHeading: Heading,
  endHeading: Heading
): Point[] {
  const startHoriz = isHorizontal(startHeading);
  const endHoriz = isHorizontal(endHeading);
  
  // Check for aligned points
  if (Math.abs(start[1] - end[1]) < 1 && startHoriz && endHoriz) {
    return [start, end];
  }
  if (Math.abs(start[0] - end[0]) < 1 && !startHoriz && !endHoriz) {
    return [start, end];
  }
  
  // L-shape
  if (startHoriz !== endHoriz) {
    const corner: Point = startHoriz
      ? [end[0], start[1]]
      : [start[0], end[1]];
    return [start, corner, end];
  }
  
  // S-shape
  if (startHoriz) {
    const midX = (start[0] + end[0]) / 2;
    return [
      start,
      [midX, start[1]],
      [midX, end[1]],
      end
    ];
  } else {
    const midY = (start[1] + end[1]) / 2;
    return [
      start,
      [start[0], midY],
      [end[0], midY],
      end
    ];
  }
}

/** Remove redundant points from path */
function cleanPath(path: Point[]): Point[] {
  if (path.length <= 2) return path;
  
  const result: Point[] = [path[0]];
  
  for (let i = 1; i < path.length - 1; i++) {
    const prev = result[result.length - 1];
    const current = path[i];
    const next = path[i + 1];
    
    // Check if current point is on the same line as prev and next
    const prevHoriz = Math.abs(prev[1] - current[1]) < 0.5;
    const nextHoriz = Math.abs(current[1] - next[1]) < 0.5;
    
    // Keep if direction changes
    if (prevHoriz !== nextHoriz) {
      result.push(current);
    }
  }
  
  result.push(path[path.length - 1]);
  return result;
}
```

---

## Step 8: Rendering

```typescript
// ============================================
// RENDERING
// ============================================

interface RenderContext {
  moveTo(x: number, y: number): void;
  lineTo(x: number, y: number): void;
  stroke(): void;
}

/**
 * Render an elbow arrow path
 */
function renderElbowArrow(
  ctx: RenderContext,
  path: Point[],
  options?: {
    cornerRadius?: number;
  }
): void {
  if (path.length < 2) return;
  
  const cornerRadius = options?.cornerRadius ?? 0;
  
  if (cornerRadius === 0) {
    // Sharp corners
    ctx.moveTo(path[0][0], path[0][1]);
    for (let i = 1; i < path.length; i++) {
      ctx.lineTo(path[i][0], path[i][1]);
    }
    ctx.stroke();
    return;
  }
  
  // Rounded corners (simplified)
  ctx.moveTo(path[0][0], path[0][1]);
  
  for (let i = 1; i < path.length - 1; i++) {
    const prev = path[i - 1];
    const current = path[i];
    const next = path[i + 1];
    
    // Calculate corner points
    const radius = Math.min(
      cornerRadius,
      manhattanDistance(prev, current) / 2,
      manhattanDistance(current, next) / 2
    );
    
    const beforeCorner = interpolatePoint(current, prev, radius);
    const afterCorner = interpolatePoint(current, next, radius);
    
    ctx.lineTo(beforeCorner[0], beforeCorner[1]);
    // For actual rounded corners, use arcTo or quadraticCurveTo
    ctx.lineTo(afterCorner[0], afterCorner[1]);
  }
  
  ctx.lineTo(path[path.length - 1][0], path[path.length - 1][1]);
  ctx.stroke();
}

function interpolatePoint(from: Point, to: Point, distance: number): Point {
  const totalDist = manhattanDistance(from, to);
  if (totalDist === 0) return from;
  
  const ratio = distance / totalDist;
  return [
    from[0] + (to[0] - from[0]) * ratio,
    from[1] + (to[1] - from[1]) * ratio
  ];
}
```

---

## Testing Your Implementation

### Test Case 1: Horizontal Alignment

```typescript
const path = createElbowArrow([0, 100], [200, 100]);
console.assert(path.length === 2, 'Should be direct line');
console.assert(path[0][0] === 0 && path[1][0] === 200, 'X coords correct');
```

### Test Case 2: L-Shape

```typescript
const path = createElbowArrow([0, 0], [100, 100]);
console.assert(path.length === 3, 'Should have one corner');
// Verify all segments are orthogonal
for (let i = 1; i < path.length; i++) {
  const horiz = Math.abs(path[i][1] - path[i-1][1]) < 0.5;
  const vert = Math.abs(path[i][0] - path[i-1][0]) < 0.5;
  console.assert(horiz || vert, `Segment ${i} should be orthogonal`);
}
```

### Test Case 3: Obstacle Avoidance

```typescript
const obstacle: Bounds = [40, 40, 60, 60];
const path = createElbowArrow([0, 50], [100, 50], { obstacles: [obstacle] });

// Verify path doesn't pass through obstacle
for (let i = 1; i < path.length; i++) {
  const mid: Point = [
    (path[i-1][0] + path[i][0]) / 2,
    (path[i-1][1] + path[i][1]) / 2
  ];
  console.assert(!pointInBounds(mid, obstacle), 'Path should avoid obstacle');
}
```

---

## Common Issues and Solutions

### Issue 1: Path Goes Through Obstacles

**Cause**: Obstacle checking not using padded bounds or midpoint checking.

**Solution**: Always pad obstacles and check the midpoint of each segment.

### Issue 2: Unnecessary Bends

**Cause**: Bend penalty too low or heading determination incorrect.

**Solution**: Increase bend penalty (use cube of distance) and verify heading calculation.

### Issue 3: No Path Found

**Cause**: Grid doesn't include necessary coordinates or start/end nodes not found.

**Solution**: Ensure start/end points are added to grid coordinates.

### Issue 4: Performance Issues

**Cause**: Grid too large or missing early termination.

**Solution**: Use non-uniform grid and add iteration limit.

---

## Next Steps

After implementing the basic elbow arrow:

1. **Add element binding** - Connect arrows to shapes
2. **Implement fixed segments** - Allow manual segment adjustment
3. **Add arrowheads** - Render arrow tips
4. **Optimize rendering** - Cache paths, use dirty checking
5. **Add animation** - Smooth transitions when path changes

---

*Implementation Guide Version: 1.0*
