# Dynamic Inflection Point Behavior

## Overview

When an elbow arrow connects two elements that are positioned diagonally (not directly above/below or left/right of each other), Excalidraw uses a **dynamic inflection point** calculation. The first turn point (inflection point) is not at a fixed distance from the start element, but rather calculated based on the **relative positions of both elements**.

This creates more aesthetically pleasing paths that adapt to the spatial relationship between connected elements.

---

## The Problem This Solves

### Without Dynamic Calculation (Fixed Offset)

```
    Start ●
          │
          │  ← Fixed distance (e.g., 40px)
          │
          └─────────────────────┐
                                │
                                ▼
                         ┌──────────────┐
                         │    End       │
                         └──────────────┘

When start is far above end, the fixed offset creates
an awkwardly long first segment before the turn.
```

### With Dynamic Calculation (Excalidraw's Approach)

```
    Start ●
          │
          │  ← Dynamic: midpoint between elements
          └─────────────────────┐
                                │
                                │
                                ▼
                         ┌──────────────┐
                         │    End       │
                         └──────────────┘

The turn happens at the midpoint, creating a balanced path.
```

---

## How It Works

### Key Insight: Midpoint Calculation

When the start element is **above and to the side** of the end element (diagonal positioning), the AABB boundary that determines the inflection point is calculated as the **midpoint** between the two elements:

```typescript
// From generateDynamicAABBs function
// When start (a) is above end (b): a[1] > b[3]
// And they don't overlap horizontally: a[0] > b[2] || a[2] < b[0]

const dynamicY = (startElement[1] + endElement[3]) / 2;
// startElement[1] = top of start element (minY)
// endElement[3] = bottom of end element (maxY)
// Result: Y coordinate at the midpoint between them
```

### The Decision Tree

The `generateDynamicAABBs` function uses this logic for the top edge (minY) of the start AABB:

```typescript
first[1] = // Top edge of start AABB
  a[1] > b[3]  // Is start above end?
    ? a[0] > b[2] || a[2] < b[0]  // Are they diagonally positioned (no horizontal overlap)?
      ? Math.min((startEl[1] + endEl[3]) / 2, a[1] - startUp)  // Use midpoint (clamped)
      : (startEl[1] + endEl[3]) / 2  // Use exact midpoint
    : a[1] > b[1]  // Is start partially above end?
      ? a[1] - startUp  // Use fixed offset from start
      : common[1] - startUp;  // Use common bounds with offset
```

### Visual Explanation

```
Case 1: Diagonal positioning (dynamic midpoint)
═══════════════════════════════════════════════

        a[1] (start top)
          ┌─────┐ Start
          │     │
          └─────┘ a[3]
              │
    midpoint ─┼─ = (a[1] + b[3]) / 2  ← Inflection happens here
              │
          ┌─────┐ b[1]
          │     │ End
          └─────┘ b[3] (end bottom)


Case 2: Vertically aligned (fixed offset)
═══════════════════════════════════════════════

          ┌─────┐ Start
          │     │
          └──┬──┘
             │
             │ ← Fixed padding offset
             │
          ┌──┴──┐
          │     │ End (directly below)
          └─────┘
```

---

## Implementation Details

### Complete AABB Boundary Calculation

For all four edges of the dynamic AABB, similar logic applies:

```typescript
function generateDynamicAABBs(
  a: Bounds,        // Start element/point bounds
  b: Bounds,        // End element/point bounds
  common: Bounds,   // Common bounding box
  startDifference,  // [top, right, bottom, left] padding for start
  endDifference,    // [top, right, bottom, left] padding for end
  startElementBounds,  // Original start element bounds
  endElementBounds     // Original end element bounds
): [Bounds, Bounds] {
  
  const startEl = startElementBounds ?? a;
  const endEl = endElementBounds ?? b;
  const [startUp, startRight, startDown, startLeft] = startDifference;
  
  const first: Bounds = [
    // Left edge (minX)
    a[0] > b[2]  // Start is to the right of end?
      ? a[1] > b[3] || a[3] < b[1]  // Diagonal?
        ? Math.min((startEl[0] + endEl[2]) / 2, a[0] - startLeft)  // Midpoint
        : (startEl[0] + endEl[2]) / 2
      : a[0] > b[0]
        ? a[0] - startLeft
        : common[0] - startLeft,
    
    // Top edge (minY)
    a[1] > b[3]  // Start is above end?
      ? a[0] > b[2] || a[2] < b[0]  // Diagonal?
        ? Math.min((startEl[1] + endEl[3]) / 2, a[1] - startUp)  // Midpoint
        : (startEl[1] + endEl[3]) / 2
      : a[1] > b[1]
        ? a[1] - startUp
        : common[1] - startUp,
    
    // Right edge (maxX)
    a[2] < b[0]  // Start is to the left of end?
      ? a[1] > b[3] || a[3] < b[1]  // Diagonal?
        ? Math.max((startEl[2] + endEl[0]) / 2, a[2] + startRight)  // Midpoint
        : (startEl[2] + endEl[0]) / 2
      : a[2] < b[2]
        ? a[2] + startRight
        : common[2] + startRight,
    
    // Bottom edge (maxY)
    a[3] < b[1]  // Start is below end?
      ? a[0] > b[2] || a[2] < b[0]  // Diagonal?
        ? Math.max((startEl[3] + endEl[1]) / 2, a[3] + startDown)  // Midpoint
        : (startEl[3] + endEl[1]) / 2
      : a[3] < b[3]
        ? a[3] + startDown
        : common[3] + startDown,
  ];
  
  // Similar logic for 'second' (end AABB)...
  
  return [first, second];
}
```

### The Clamping with Math.min/Math.max

Notice the use of `Math.min` and `Math.max`:

```typescript
Math.min((startEl[1] + endEl[3]) / 2, a[1] - startUp)
```

This ensures the dynamic midpoint doesn't exceed the fixed padding boundary. The inflection point is at:
- The midpoint between elements, OR
- The fixed padding distance from start
- **Whichever is closer to the start element**

This prevents the inflection point from being too far away when elements are very close together.

---

## Diagonal Position Detection

The condition `a[0] > b[2] || a[2] < b[0]` checks if elements have **no horizontal overlap**:

```typescript
a[0] > b[2]  // Start's left edge is to the right of end's right edge
||           // OR
a[2] < b[0]  // Start's right edge is to the left of end's left edge
```

Similarly for vertical: `a[1] > b[3] || a[3] < b[1]`

When both conditions are true, elements are **diagonally positioned**.

---

## Impact on Your Implementation

### If You're Missing This Behavior

Your implementation might be using fixed offsets everywhere:

```typescript
// ❌ WRONG - Always uses fixed padding
const aabbTop = startBounds[1] - padding;
```

### The Correct Approach

Check the relative positions and use midpoint when appropriate:

```typescript
// ✅ CORRECT - Dynamic based on element positions
const aabbTop = 
  startBounds[1] > endBounds[3]  // Start above end?
    ? startBounds[0] > endBounds[2] || startBounds[2] < endBounds[0]  // Diagonal?
      ? Math.min(
          (startElement[1] + endElement[3]) / 2,  // Midpoint
          startBounds[1] - padding                 // Clamped by padding
        )
      : (startElement[1] + endElement[3]) / 2     // Exact midpoint
    : startBounds[1] - padding;                   // Fixed padding
```

---

## Testing This Behavior

### Test Case: Varying Start Height

1. Create a rectangle element
2. Create an elbow arrow starting from a free point above and to the left of the rectangle
3. Move the start point higher
4. **Expected**: The first inflection point should move up proportionally, staying at roughly the midpoint between start and end

### Debug Logging

Add this to verify the behavior:

```typescript
function generateDynamicAABBs(...) {
  // ... existing code ...
  
  // Debug: Check if diagonal positioning is detected
  const isDiagonal = (a[1] > b[3] || a[3] < b[1]) && (a[0] > b[2] || a[2] < b[0]);
  console.log('Diagonal positioning:', isDiagonal);
  
  if (isDiagonal && a[1] > b[3]) {
    const midpoint = (startEl[1] + endEl[3]) / 2;
    const fixedOffset = a[1] - startUp;
    console.log('Midpoint Y:', midpoint);
    console.log('Fixed offset Y:', fixedOffset);
    console.log('Using:', Math.min(midpoint, fixedOffset));
  }
  
  // ... continue ...
}
```

---

## Summary

The dynamic inflection point behavior is a key refinement that makes Excalidraw's elbow arrows look natural:

1. **When elements are diagonally positioned**: Use the midpoint between elements
2. **When elements are aligned**: Use fixed padding offset
3. **Always clamp**: Ensure the midpoint doesn't exceed the fixed padding boundary

This creates arrows that adapt to the spatial layout rather than having rigid, fixed-distance turns.

---

## Related Documentation

- `03-elbow-arrow-segment-length-fix.md` - Base padding and segment length
- `04-diagnostic-checklist.md` - Debugging checklist
- Source: `packages/element/src/elbowArrow.ts`, function `generateDynamicAABBs` (lines 1660-1836)
