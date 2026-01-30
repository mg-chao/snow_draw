# Fix Guide: Elbow Arrow Perpendicular Binding

## Problem Statement

When an elbow arrow (composed of three or more axis-aligned line segments) has:
- A **fixed middle segment** (user-positioned or constrained)
- An **endpoint bound to another element**

The endpoint segment may fail to be perpendicular to the binding surface. This results in arrows that approach the bound element at awkward angles rather than cleanly entering/exiting perpendicular to the element's edge.

## Root Cause

The issue typically occurs when:
1. The routing algorithm does not account for the **required exit/entry heading** when bound to an element
2. The middle segment constraint prevents natural re-routing
3. No mechanism exists to **insert additional segments** to achieve perpendicularity

## Solution Overview

The fix requires implementing a **heading-constrained routing system** with the ability to insert transition segments when the fixed middle segment conflicts with perpendicular binding requirements.

---

## Algorithm: Perpendicular Heading Calculation

### Step 1: Determine the Perpendicular Heading

For any point `P` near a bindable element, calculate which edge of the element `P` is closest to. This determines the **required heading** (direction) for the arrow to approach/exit that element perpendicularly.

#### Algorithm: Triangle Inclusion Method

Divide the space around the element into 4 triangular zones emanating from the element's center:

```
                    TOP ZONE
                   /        \
                  /    UP    \
                 /            \
    LEFT ZONE   +-----[  ]-----+   RIGHT ZONE
                 \            /
                  \   DOWN   /
                   \        /
                   BOTTOM ZONE
```

**Pseudocode:**

```plaintext
function getPerpendicularHeading(element, point):
    bounds = getAxisAlignedBoundingBox(element)
    center = getCenterOfBounds(bounds)
    
    // Scale corners outward to create search cones
    SCALE_FACTOR = 2.0  // Extend beyond element bounds
    
    topLeft = scalePointFromOrigin(bounds.topLeft, center, SCALE_FACTOR)
    topRight = scalePointFromOrigin(bounds.topRight, center, SCALE_FACTOR)
    bottomLeft = scalePointFromOrigin(bounds.bottomLeft, center, SCALE_FACTOR)
    bottomRight = scalePointFromOrigin(bounds.bottomRight, center, SCALE_FACTOR)
    
    // Determine which triangle contains the point
    if triangleContainsPoint([topLeft, topRight, center], point):
        return HEADING_UP      // Arrow should exit upward (perpendicular to top edge)
    else if triangleContainsPoint([topRight, bottomRight, center], point):
        return HEADING_RIGHT   // Arrow should exit rightward (perpendicular to right edge)
    else if triangleContainsPoint([bottomRight, bottomLeft, center], point):
        return HEADING_DOWN    // Arrow should exit downward (perpendicular to bottom edge)
    else:
        return HEADING_LEFT    // Arrow should exit leftward (perpendicular to left edge)
```

**Heading Constants:**

```plaintext
HEADING_UP    = (0, -1)   // Points upward
HEADING_DOWN  = (0, 1)    // Points downward  
HEADING_LEFT  = (-1, 0)   // Points leftward
HEADING_RIGHT = (1, 0)    // Points rightward
```

### Step 2: Triangle Containment Test

```plaintext
function triangleContainsPoint(triangle[A, B, C], point P):
    // Using barycentric coordinates or cross product method
    d1 = sign(crossProduct(P - A, B - A))
    d2 = sign(crossProduct(P - B, C - B))
    d3 = sign(crossProduct(P - C, A - C))
    
    hasNeg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    hasPos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    
    return not (hasNeg and hasPos)
```

---

## Algorithm: Segment Insertion for Perpendicularity

When the fixed middle segment's direction conflicts with the required perpendicular heading, **insert additional segments** to create a valid path.

### Step 3: Detect Heading Conflict

```plaintext
function hasHeadingConflict(middleSegmentDirection, requiredHeading):
    // A conflict exists if the middle segment direction is parallel to 
    // the required heading (cannot turn 90° to meet it)
    return isParallel(middleSegmentDirection, requiredHeading)
```

**Example Conflict:**
- Middle segment runs horizontally (LEFT-RIGHT)
- Required heading is LEFT or RIGHT (horizontal)
- Conflict: Cannot turn to meet the element perpendicularly

**No Conflict:**
- Middle segment runs horizontally (LEFT-RIGHT)
- Required heading is UP or DOWN (vertical)
- No conflict: Can connect with a vertical final segment

### Step 4: Insert Transition Segment

When a conflict is detected, insert a **transition segment** to bridge the gap:

```plaintext
function insertTransitionSegment(points[], fixedMiddleEnd, boundEndpoint, requiredHeading):
    // Calculate insertion point
    if requiredHeading is HORIZONTAL (LEFT or RIGHT):
        // Insert vertical transition segment
        transitionPoint = (fixedMiddleEnd.x, boundEndpoint.y)
    else:  // requiredHeading is VERTICAL (UP or DOWN)
        // Insert horizontal transition segment
        transitionPoint = (boundEndpoint.x, fixedMiddleEnd.y)
    
    // Insert the transition point before the endpoint
    insertPointBefore(points, boundEndpoint, transitionPoint)
    
    return points
```

### Step 5: Complete Algorithm

```plaintext
function ensurePerpendicularBinding(arrow, boundElement):
    endpoint = arrow.getBoundEndpoint()
    
    // Step 1: Calculate required perpendicular heading
    requiredHeading = getPerpendicularHeading(boundElement, endpoint)
    
    // Step 2: Get the direction of the segment leading to endpoint
    lastSegmentDirection = getSegmentDirection(arrow.getSecondLastPoint(), endpoint)
    
    // Step 3: Check if already perpendicular
    if isOppositeHeading(lastSegmentDirection, requiredHeading):
        return  // Already perpendicular, no fix needed
    
    // Step 4: Check for conflict with fixed middle segment
    middleSegment = arrow.getFixedMiddleSegment()
    
    if hasHeadingConflict(middleSegment.direction, requiredHeading):
        // Step 5: Insert transition segment
        transitionPoint = calculateTransitionPoint(
            middleSegment.end, 
            endpoint, 
            requiredHeading
        )
        arrow.insertPoint(transitionPoint)
    
    // Step 6: Snap endpoint to element outline along heading
    snappedEndpoint = snapToElementOutline(boundElement, endpoint, requiredHeading)
    arrow.updateEndpoint(snappedEndpoint)
```

---

## Algorithm: Snap Endpoint to Element Outline

Ensure the endpoint lies exactly on the element's edge, along the perpendicular heading.

### Step 6: Ray-Element Intersection

```plaintext
function snapToElementOutline(element, point, heading):
    // Cast a ray from the point in the opposite direction of heading
    rayDirection = flipHeading(heading)
    ray = createRay(point, rayDirection)
    
    // Find intersection with element boundary
    outline = getElementOutline(element)  // Polygon or rectangle
    intersection = rayIntersectPolygon(ray, outline)
    
    if intersection exists:
        return intersection
    else:
        // Fallback: find closest point on outline
        return closestPointOnOutline(outline, point)
```

---

## Routing Algorithm Integration

### Option A: Pre-routing Constraint

Before routing, establish heading constraints for both endpoints:

```plaintext
function routeElbowArrow(startPoint, endPoint, startElement, endElement, fixedMiddle):
    startHeading = null
    endHeading = null
    
    // Calculate required headings if bound
    if startElement exists:
        startHeading = getPerpendicularHeading(startElement, startPoint)
    if endElement exists:
        endHeading = getPerpendicularHeading(endElement, endPoint)
    
    // Route with heading constraints
    path = routeWithConstraints(
        startPoint, 
        endPoint,
        startHeading,   // First segment must exit in this direction
        endHeading,     // Last segment must approach in this direction
        fixedMiddle
    )
    
    return path
```

### Option B: Post-routing Correction

After routing with fixed middle segment, correct endpoints:

```plaintext
function correctEndpointPerpendicularity(path[], boundElement, isStartBound):
    if isStartBound:
        idx = 0
        neighborIdx = 1
    else:
        idx = path.length - 1
        neighborIdx = path.length - 2
    
    endpoint = path[idx]
    neighbor = path[neighborIdx]
    
    requiredHeading = getPerpendicularHeading(boundElement, endpoint)
    currentDirection = normalize(endpoint - neighbor)
    
    // Check if perpendicular
    if not isOppositeHeading(currentDirection, requiredHeading):
        // Insert correction point
        correctionPoint = calculateCorrectionPoint(neighbor, endpoint, requiredHeading)
        path.insert(neighborIdx + (1 if not isStartBound else 0), correctionPoint)
    
    // Snap endpoint
    path[idx] = snapToElementOutline(boundElement, endpoint, requiredHeading)
    
    return path
```

---

## A* Pathfinding with Heading Constraints

If using A* or similar pathfinding for routing, enforce heading constraints:

### Constraint: Prevent Reverse Movement at Endpoints

```plaintext
function astar(start, end, grid, startHeading, endHeading):
    // ... standard A* setup ...
    
    while openSet is not empty:
        current = getLowestFScore(openSet)
        
        if current == end:
            return reconstructPath()
        
        for neighbor in getNeighbors(current):
            neighborHeading = getDirection(current, neighbor)
            
            // CRITICAL: Enforce heading constraints
            if current == start and startHeading exists:
                // First move must match start heading
                if neighborHeading != startHeading:
                    continue  // Skip this neighbor
            
            if neighbor == end and endHeading exists:
                // Approach to end must match end heading (opposite direction)
                if neighborHeading != flipHeading(endHeading):
                    continue  // Skip this neighbor
            
            // Prevent reverse movement (180° turns)
            if isReverseDirection(previousDirection[current], neighborHeading):
                continue
            
            // ... rest of A* logic ...
```

---

## Implementation Checklist

Use this checklist to verify your fix implementation:

### Core Functions

- [ ] `getPerpendicularHeading(element, point)` - Returns UP/DOWN/LEFT/RIGHT
- [ ] `triangleContainsPoint(triangle, point)` - Point-in-triangle test
- [ ] `hasHeadingConflict(segmentDir, requiredHeading)` - Detect parallel conflict
- [ ] `calculateTransitionPoint(fromPoint, toPoint, heading)` - Compute insertion point
- [ ] `snapToElementOutline(element, point, heading)` - Snap to edge

### Integration Points

- [ ] Call heading calculation when endpoint binding is established
- [ ] Store required heading with binding information
- [ ] Check heading conflict when middle segment is fixed
- [ ] Insert transition segment when conflict detected
- [ ] Snap endpoint after segment insertion
- [ ] Update rendering to handle additional segments

### Edge Cases

- [ ] Element is rotated (transform heading calculation to element space)
- [ ] Element is ellipse/circle (use radial heading toward center)
- [ ] Multiple bindings change simultaneously
- [ ] Arrow has only 2 points (upgrade to 3+ for elbow)
- [ ] Fixed middle segment overlaps with bound element

---

## Geometry Utilities

### Heading Operations

```plaintext
function flipHeading(heading):
    return (-heading.x, -heading.y)

function isParallel(dir1, dir2):
    // Parallel if cross product is zero
    return abs(crossProduct(dir1, dir2)) < EPSILON

function isOppositeHeading(dir, heading):
    // Direction should be opposite to heading for perpendicular approach
    return dotProduct(dir, heading) < -0.99  // Nearly -1

function getSegmentDirection(p1, p2):
    delta = p2 - p1
    if abs(delta.x) > abs(delta.y):
        return delta.x > 0 ? HEADING_RIGHT : HEADING_LEFT
    else:
        return delta.y > 0 ? HEADING_DOWN : HEADING_UP
```

### Point Operations

```plaintext
function scalePointFromOrigin(point, origin, scale):
    return origin + (point - origin) * scale

function crossProduct(v1, v2):
    return v1.x * v2.y - v1.y * v2.x

function dotProduct(v1, v2):
    return v1.x * v2.x + v1.y * v2.y
```

---

## Example Scenarios

### Scenario 1: No Conflict

```
Before:                After:
    [Element]              [Element]
        |                      |
        v                      v
   -----+                 -----+
        |                      |
        |                      |
```

Middle segment horizontal, element above → required heading UP → no conflict.

### Scenario 2: Conflict Requiring Transition

```
Before (WRONG):        After (FIXED):
                       
   [Element]              [Element]
       \                      |
        \                     |
   ------+               -----+----
                              |
```

Middle segment horizontal, element to the side at different Y → required heading LEFT → conflict detected → insert vertical transition segment.

### Scenario 3: Complex Case

```
Before:                After:
                       
   ====== (fixed)         ======
        \                      |
         \                     +---[Element]
          [Element]
```

Fixed horizontal middle, element below and to right → required heading LEFT → insert vertical then horizontal transition.

---

## Testing Recommendations

1. **Unit Tests**: Test `getPerpendicularHeading` with points in all 4 quadrants
2. **Conflict Detection**: Test all combinations of segment direction vs heading
3. **Transition Insertion**: Verify correct point calculation
4. **Snap Accuracy**: Verify endpoint lies exactly on element edge
5. **Visual Tests**: Render arrows and verify perpendicularity visually
6. **Stress Tests**: Rapid binding changes, element movement during drag

---

## Summary

To fix non-perpendicular elbow arrow binding:

1. **Calculate** the required perpendicular heading using triangle inclusion
2. **Detect** conflicts between fixed segments and required heading
3. **Insert** transition segments when conflicts exist
4. **Snap** endpoints to element outline along the heading direction
5. **Constrain** pathfinding algorithms to respect heading requirements

The key insight is that perpendicularity requires **heading awareness** throughout the routing process, not just at the final connection point.
