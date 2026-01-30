# Elbow Arrow Segment Length Bug Fix - Technical Solution

## Problem Statement

When migrating Excalidraw's elbow arrow implementation to another project, the vertical/horizontal segment immediately after the binding point (the "exit segment") is longer than expected, resulting in a less aesthetically pleasing path compared to the original Excalidraw implementation.

### Visual Comparison

**Expected (Excalidraw):**
```
    ┌─────────────┐
    │             │
    │   Element   │
    │             │
    └──────┬──────┘
           │  ← Short exit segment
           └────────────────┐
                            │
                            ▼
                     ┌──────────────┐
                     │   Target     │
                     └──────────────┘
```

**Actual (Bug):**
```
    ┌─────────────┐
    │             │
    │   Element   │
    │             │
    └──────┬──────┘
           │
           │  ← Too long exit segment
           │
           │
           └────────────────┐
                            │
                            ▼
                     ┌──────────────┐
                     │   Target     │
                     └──────────────┘
```

---

## Root Cause Analysis

The exit segment length is controlled by the **dongle position**, which is calculated based on the **dynamic AABB boundaries**. The issue typically stems from one or more of the following:

### 1. Incorrect AABB Padding Calculation

The most common cause is using `BASE_PADDING` directly instead of applying the binding gap adjustment.

**Incorrect:**
```typescript
const headPadding = BASE_PADDING; // 40px - too much!
```

**Correct:**
```typescript
const headPadding = BASE_PADDING - (hasArrowhead 
  ? BASE_BINDING_GAP_ELBOW * 6 
  : BASE_BINDING_GAP_ELBOW * 2);
// With arrowhead: 40 - 30 = 10px
// Without arrowhead: 40 - 10 = 30px
```

### 2. Symmetric Padding Instead of Asymmetric

The AABB padding should be **asymmetric** - smaller in the exit direction (head) and larger on other sides.

**Incorrect:**
```typescript
// Same padding on all sides
const padding = [BASE_PADDING, BASE_PADDING, BASE_PADDING, BASE_PADDING];
```

**Correct:**
```typescript
// Different padding based on heading direction
function offsetFromHeading(heading, head, side) {
  switch (heading) {
    case HEADING_UP:    return [head, side, side, side]; // top, right, bottom, left
    case HEADING_RIGHT: return [side, head, side, side];
    case HEADING_DOWN:  return [side, side, head, side];
    case HEADING_LEFT:  return [side, side, side, head];
  }
}
```

### 3. Missing Bounds Overlap Handling

When start and end elements' expanded bounds overlap, different padding rules apply.

### 4. Incorrect Element Bounds vs AABB Bounds

There are two different bounds used in the algorithm:
- **Element bounds**: Used for collision detection (expanded by binding gap)
- **Dynamic AABB bounds**: Used for dongle positioning (adjusted padding)

Mixing these up causes incorrect segment lengths.

---

## Solution Implementation

### Step 1: Define Constants Correctly

```typescript
// Base padding for AABB expansion
const BASE_PADDING = 40;

// Binding gap for elbow arrows (smaller than regular arrows)
const BASE_BINDING_GAP_ELBOW = 5;

// Threshold for removing short segments
const DEDUP_THRESHOLD = 1;
```

### Step 2: Implement Asymmetric Padding Function

```typescript
/**
 * Calculate padding offsets based on arrow exit direction.
 * Applies smaller padding in the exit direction (head) and 
 * standard padding on other sides.
 * 
 * @param heading - The exit direction (UP, RIGHT, DOWN, LEFT)
 * @param head - Padding in the exit direction
 * @param side - Padding on other sides
 * @returns [top, right, bottom, left] padding values
 */
function offsetFromHeading(
  heading: Heading,
  head: number,
  side: number
): [number, number, number, number] {
  switch (heading) {
    case HEADING_UP:
      return [head, side, side, side];
    case HEADING_RIGHT:
      return [side, head, side, side];
    case HEADING_DOWN:
      return [side, side, head, side];
    case HEADING_LEFT:
      return [side, side, side, head];
    default:
      return [side, side, side, side];
  }
}
```

### Step 3: Calculate Adjusted Head Padding

```typescript
/**
 * Calculate the head padding for dynamic AABB generation.
 * The head padding is reduced by the binding gap to create
 * shorter exit segments.
 * 
 * @param hasArrowhead - Whether the endpoint has an arrowhead
 * @returns Adjusted head padding value
 */
function calculateHeadPadding(hasArrowhead: boolean): number {
  const bindingGapMultiplier = hasArrowhead ? 6 : 2;
  return BASE_PADDING - (BASE_BINDING_GAP_ELBOW * bindingGapMultiplier);
}

// Examples:
// With arrowhead:    40 - (5 * 6) = 10px
// Without arrowhead: 40 - (5 * 2) = 30px
```

### Step 4: Implement Dynamic AABB Generation

```typescript
/**
 * Generate dynamic AABBs for collision avoidance and dongle positioning.
 * 
 * CRITICAL: This is where segment length is determined!
 */
function generateDynamicAABBs(
  startElementBounds: Bounds,
  endElementBounds: Bounds,
  startHeading: Heading,
  endHeading: Heading,
  hasStartArrowhead: boolean,
  hasEndArrowhead: boolean,
  boundsOverlap: boolean
): [Bounds, Bounds] {
  
  // Calculate adjusted padding for each endpoint
  let startPadding: [number, number, number, number];
  let endPadding: [number, number, number, number];
  
  if (boundsOverlap) {
    // When bounds overlap, use simpler padding
    startPadding = offsetFromHeading(startHeading, BASE_PADDING, 0);
    endPadding = offsetFromHeading(endHeading, BASE_PADDING, 0);
  } else {
    // Normal case: use adjusted head padding
    const startHeadPadding = calculateHeadPadding(hasStartArrowhead);
    const endHeadPadding = calculateHeadPadding(hasEndArrowhead);
    
    startPadding = offsetFromHeading(startHeading, startHeadPadding, BASE_PADDING);
    endPadding = offsetFromHeading(endHeading, endHeadPadding, BASE_PADDING);
  }
  
  // Expand bounds with calculated padding
  // Bounds format: [minX, minY, maxX, maxY]
  // Padding format: [top, right, bottom, left]
  const startAABB: Bounds = [
    startElementBounds[0] - startPadding[3], // minX - left
    startElementBounds[1] - startPadding[0], // minY - top
    startElementBounds[2] + startPadding[1], // maxX + right
    startElementBounds[3] + startPadding[2], // maxY + bottom
  ];
  
  const endAABB: Bounds = [
    endElementBounds[0] - endPadding[3],
    endElementBounds[1] - endPadding[0],
    endElementBounds[2] + endPadding[1],
    endElementBounds[3] + endPadding[2],
  ];
  
  return [startAABB, endAABB];
}
```

### Step 5: Calculate Dongle Position

The dongle position determines where the first turn happens after leaving the element.

```typescript
/**
 * Calculate the dongle (first waypoint) position.
 * The dongle is placed at the edge of the expanded AABB
 * in the direction of the heading.
 * 
 * @param bounds - The expanded AABB bounds
 * @param heading - The exit direction
 * @param bindingPoint - The actual binding point on the element
 * @returns The dongle position
 */
function getDonglePosition(
  bounds: Bounds,
  heading: Heading,
  bindingPoint: GlobalPoint
): GlobalPoint {
  switch (heading) {
    case HEADING_UP:
      // Dongle is at top of AABB, same X as binding point
      return [bindingPoint[0], bounds[1]];
    case HEADING_RIGHT:
      // Dongle is at right of AABB, same Y as binding point
      return [bounds[2], bindingPoint[1]];
    case HEADING_DOWN:
      // Dongle is at bottom of AABB, same X as binding point
      return [bindingPoint[0], bounds[3]];
    case HEADING_LEFT:
      // Dongle is at left of AABB, same Y as binding point
      return [bounds[0], bindingPoint[1]];
  }
}
```

### Step 6: Integrate in Routing Data Preparation

```typescript
function getElbowArrowData(
  arrow: ElbowArrowState,
  elementsMap: ElementsMap,
  nextPoints: LocalPoint[],
  options?: { isDragging?: boolean }
): ElbowArrowData {
  
  // ... get hoveredStartElement, hoveredEndElement ...
  // ... calculate startGlobalPoint, endGlobalPoint ...
  // ... calculate startHeading, endHeading ...
  
  // Step A: Calculate element bounds with binding gap offset
  const startElementBounds = hoveredStartElement
    ? aabbForElement(
        hoveredStartElement,
        elementsMap,
        offsetFromHeading(
          startHeading,
          arrow.startArrowhead
            ? getBindingGap(hoveredStartElement) * 6
            : getBindingGap(hoveredStartElement) * 2,
          1  // minimal side expansion
        )
      )
    : pointToBounds(startGlobalPoint, 2);
  
  const endElementBounds = hoveredEndElement
    ? aabbForElement(
        hoveredEndElement,
        elementsMap,
        offsetFromHeading(
          endHeading,
          arrow.endArrowhead
            ? getBindingGap(hoveredEndElement) * 6
            : getBindingGap(hoveredEndElement) * 2,
          1
        )
      )
    : pointToBounds(endGlobalPoint, 2);
  
  // Step B: Check for bounds overlap
  const boundsOverlap = checkBoundsOverlap(
    startGlobalPoint,
    endGlobalPoint,
    hoveredStartElement,
    hoveredEndElement,
    startHeading,
    endHeading
  );
  
  // Step C: Generate dynamic AABBs with ADJUSTED padding
  const dynamicAABBs = generateDynamicAABBs(
    boundsOverlap ? pointToBounds(startGlobalPoint, 2) : startElementBounds,
    boundsOverlap ? pointToBounds(endGlobalPoint, 2) : endElementBounds,
    startHeading,
    endHeading,
    !!arrow.startArrowhead,
    !!arrow.endArrowhead,
    boundsOverlap
  );
  
  // Step D: Calculate dongle positions from dynamic AABBs
  const startDonglePosition = hoveredStartElement
    ? getDonglePosition(dynamicAABBs[0], startHeading, startGlobalPoint)
    : null;
  
  const endDonglePosition = hoveredEndElement
    ? getDonglePosition(dynamicAABBs[1], endHeading, endGlobalPoint)
    : null;
  
  return {
    dynamicAABBs,
    startDonglePosition,
    startGlobalPoint,
    startHeading,
    endDonglePosition,
    endGlobalPoint,
    endHeading,
    // ... other fields
  };
}
```

---

## Verification Checklist

Use this checklist to verify your implementation:

### Constants
- [ ] `BASE_PADDING = 40`
- [ ] `BASE_BINDING_GAP_ELBOW = 5`
- [ ] Arrowhead multiplier = 6
- [ ] No-arrowhead multiplier = 2

### Padding Calculation
- [ ] Head padding is calculated as `BASE_PADDING - (BASE_BINDING_GAP_ELBOW * multiplier)`
- [ ] `offsetFromHeading` applies head padding only in exit direction
- [ ] Side padding uses `BASE_PADDING` (or 0 in overlap case)

### Dynamic AABB
- [ ] Uses adjusted head padding (not raw `BASE_PADDING`)
- [ ] Handles bounds overlap case differently
- [ ] Element bounds and AABB bounds are calculated separately

### Dongle Position
- [ ] Calculated from dynamic AABB bounds (not element bounds)
- [ ] Only calculated when element is bound
- [ ] Uses correct AABB edge based on heading

### Path Construction
- [ ] Dongle position is used as start/end node for A* algorithm
- [ ] Actual binding point is prepended/appended to final path
- [ ] Short segments are removed after path generation

---

## Common Mistakes to Avoid

### Mistake 1: Using BASE_PADDING directly
```typescript
// ❌ WRONG - Creates long exit segments
const headPadding = BASE_PADDING;

// ✅ CORRECT - Adjusted for binding gap
const headPadding = BASE_PADDING - (hasArrowhead ? 30 : 10);
```

### Mistake 2: Symmetric padding
```typescript
// ❌ WRONG - Same padding everywhere
const padding = [40, 40, 40, 40];

// ✅ CORRECT - Asymmetric based on heading
const padding = offsetFromHeading(heading, headPadding, sidePadding);
```

### Mistake 3: Using element bounds for dongle calculation
```typescript
// ❌ WRONG - Using element bounds directly
const dongle = getDonglePosition(elementBounds, heading, point);

// ✅ CORRECT - Using dynamic AABB bounds
const dongle = getDonglePosition(dynamicAABBs[0], heading, point);
```

### Mistake 4: Not handling overlap case
```typescript
// ❌ WRONG - Ignoring overlap
const dynamicAABBs = generateDynamicAABBs(startBounds, endBounds, ...);

// ✅ CORRECT - Check and handle overlap
if (boundsOverlap) {
  // Use point bounds instead of element bounds
  // Use different padding values
}
```

---

## Testing Scenarios

Test these scenarios after implementing the fix:

### Scenario 1: Basic Downward Arrow
- Arrow starts from bottom of element, goes down then right to target
- **Expected**: Short downward segment (≈10-30px depending on arrowhead)

### Scenario 2: Arrow with Arrowhead
- Arrow has arrowhead at start
- **Expected**: Shorter exit segment than arrow without arrowhead

### Scenario 3: Close Elements (Bounds Overlap)
- Start and end elements are close together
- **Expected**: Path should not intersect with either element

### Scenario 4: Various Headings
- Test UP, RIGHT, DOWN, LEFT exit directions
- **Expected**: Exit segment length should be consistent across all directions

---

## Related: Dynamic Inflection Point

**Important**: The inflection point (first turn) is NOT always at a fixed distance from the element. When elements are positioned **diagonally** (not directly above/below or left/right), Excalidraw calculates the inflection point as the **midpoint between the two elements**.

See `05-dynamic-inflection-point.md` for detailed documentation on this behavior.

### Quick Check

If your implementation uses fixed offsets for all cases:

```typescript
// ❌ WRONG - Always fixed
const turnPointY = startPoint[1] + BASE_PADDING;
```

You need to add the midpoint calculation for diagonal cases:

```typescript
// ✅ CORRECT - Dynamic for diagonal positioning
const isDiagonal = (start[1] > end[3]) && (start[0] > end[2] || start[2] < end[0]);
const turnPointY = isDiagonal
  ? Math.min((startElement[1] + endElement[3]) / 2, start[1] - padding)
  : start[1] - padding;
```

---

## Reference Implementation

For the complete reference implementation, see:
- `packages/element/src/elbowArrow.ts` - Main routing logic
- `packages/element/src/binding.ts` - Binding gap calculations
- `packages/element/src/bounds.ts` - AABB calculation utilities

Key functions to study:
- `getElbowArrowData()` - Lines 1190-1420
- `generateDynamicAABBs()` - Lines 1660-1836 **(includes dynamic midpoint logic)**
- `getDonglePosition()` - Lines 1902-1916
- `offsetFromHeading()` - Lines 1501-1516

---

## Summary

The exit segment length is determined by:

1. **Dynamic AABB size** (controlled by adjusted head padding)
2. **Dongle position** (placed at AABB edge in heading direction)

The key fix is ensuring the head padding is calculated as:
```
headPadding = BASE_PADDING - (BASE_BINDING_GAP_ELBOW * multiplier)
```

Where multiplier is 6 for endpoints with arrowheads and 2 for endpoints without.

This creates the appropriate distance for the exit segment while maintaining proper collision avoidance with the bound elements.
