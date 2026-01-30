# Elbow Arrow Bug Diagnostic Checklist

Use this checklist to quickly identify the root cause of elbow arrow segment length issues.

## Quick Diagnosis

### Step 1: Identify the Problem

**Q1: Which segment is too long?**
- [ ] First segment after start binding point (exit segment)
- [ ] Last segment before end binding point (entry segment)
- [ ] Middle segments

**Q2: Is the issue consistent?**
- [ ] Always happens regardless of arrow direction
- [ ] Only happens with specific heading (UP/DOWN/LEFT/RIGHT)
- [ ] Only happens when elements are close together (bounds overlap)
- [ ] Only happens with/without arrowheads

---

## Step 2: Check Your Implementation

### 2.1 Constants Check

Verify these constants exist and have correct values:

```typescript
// Check these values in your code:
BASE_PADDING = ?         // Should be: 40
BASE_BINDING_GAP_ELBOW = ? // Should be: 5
```

**Status:**
- [ ] `BASE_PADDING` is 40
- [ ] `BASE_BINDING_GAP_ELBOW` is 5
- [ ] Both constants are used in AABB calculation

---

### 2.2 Head Padding Formula Check

Search your code for where dynamic AABB padding is calculated.

**Expected formula:**
```typescript
headPadding = BASE_PADDING - (BASE_BINDING_GAP_ELBOW * multiplier)
// multiplier = 6 if arrowhead present
// multiplier = 2 if no arrowhead
```

**Actual values:**
- With arrowhead: `40 - (5 * 6) = 10`
- Without arrowhead: `40 - (5 * 2) = 30`

**Status:**
- [ ] Head padding is reduced by binding gap
- [ ] Multiplier is 6 for arrowhead endpoints
- [ ] Multiplier is 2 for non-arrowhead endpoints

**Common Bug:** Using `BASE_PADDING` directly (40px) instead of adjusted value (10-30px)

---

### 2.3 Asymmetric Padding Check

Find your `offsetFromHeading` function (or equivalent).

**Expected behavior:**
```
HEADING_UP:    [head, side, side, side]  // head=top
HEADING_RIGHT: [side, head, side, side]  // head=right
HEADING_DOWN:  [side, side, head, side]  // head=bottom
HEADING_LEFT:  [side, side, side, head]  // head=left
```

**Status:**
- [ ] Function exists and is called during AABB generation
- [ ] Head padding only applies to exit direction
- [ ] Side padding applies to other three directions

**Common Bug:** Using same padding value for all four sides

---

### 2.4 Dongle Position Check

Find your `getDonglePosition` function (or equivalent).

**Expected behavior:**
- Uses **dynamic AABB bounds** (not element bounds)
- Returns point at edge of AABB in heading direction

**Status:**
- [ ] Function receives dynamic AABB bounds (not raw element bounds)
- [ ] Correctly selects AABB edge based on heading
- [ ] Preserves the other coordinate from binding point

**Common Bug:** Passing element bounds instead of expanded dynamic AABB bounds

---

### 2.5 Bounds Overlap Handling Check

Search for "overlap" in your elbow arrow code.

**Expected behavior when bounds overlap:**
- Use point bounds instead of element bounds
- Apply different padding (often `BASE_PADDING` for head, 0 for sides)

**Status:**
- [ ] Bounds overlap is detected
- [ ] Different code path for overlap case
- [ ] Padding values change when overlap detected

**Common Bug:** No special handling for overlap case

---

## Step 3: Debug Output Points

Add these debug logs to identify the exact issue:

```typescript
function getElbowArrowData(...) {
  // ... existing code ...
  
  // DEBUG: Log padding values
  console.log('=== Elbow Arrow Debug ===');
  console.log('hasStartArrowhead:', !!arrow.startArrowhead);
  console.log('hasEndArrowhead:', !!arrow.endArrowhead);
  console.log('boundsOverlap:', boundsOverlap);
  
  // DEBUG: Log calculated head padding
  const startHeadPadding = calculateHeadPadding(!!arrow.startArrowhead);
  const endHeadPadding = calculateHeadPadding(!!arrow.endArrowhead);
  console.log('startHeadPadding:', startHeadPadding); // Should be 10 or 30
  console.log('endHeadPadding:', endHeadPadding);     // Should be 10 or 30
  
  // DEBUG: Log dynamic AABBs
  console.log('dynamicAABBs[0]:', dynamicAABBs[0]);
  console.log('dynamicAABBs[1]:', dynamicAABBs[1]);
  
  // DEBUG: Log dongle positions
  console.log('startDonglePosition:', startDonglePosition);
  console.log('endDonglePosition:', endDonglePosition);
  
  // DEBUG: Calculate exit segment length
  if (startDonglePosition && hoveredStartElement) {
    const exitSegmentLength = Math.abs(
      startHeading === HEADING_UP || startHeading === HEADING_DOWN
        ? startDonglePosition[1] - startGlobalPoint[1]
        : startDonglePosition[0] - startGlobalPoint[0]
    );
    console.log('Exit segment length:', exitSegmentLength);
    // Should be approximately equal to headPadding + bindingGap
  }
  
  // ... continue with existing code ...
}
```

---

## Step 4: Expected vs Actual Comparison

Fill in this table with your debug output:

| Value | Expected | Actual | Match? |
|-------|----------|--------|--------|
| BASE_PADDING | 40 | | |
| BASE_BINDING_GAP_ELBOW | 5 | | |
| Head padding (with arrowhead) | 10 | | |
| Head padding (no arrowhead) | 30 | | |
| Exit segment length (approx) | 15-35 | | |

---

## Step 5: Common Fix Patterns

### If head padding is wrong:

```typescript
// Find this pattern (WRONG):
const padding = offsetFromHeading(heading, BASE_PADDING, BASE_PADDING);

// Replace with (CORRECT):
const headPadding = BASE_PADDING - (hasArrowhead 
  ? BASE_BINDING_GAP_ELBOW * 6 
  : BASE_BINDING_GAP_ELBOW * 2);
const padding = offsetFromHeading(heading, headPadding, BASE_PADDING);
```

### If dongle uses wrong bounds:

```typescript
// Find this pattern (WRONG):
const dongle = getDonglePosition(elementBounds, heading, point);

// Replace with (CORRECT):
const dongle = getDonglePosition(dynamicAABBs[index], heading, point);
```

### If no asymmetric padding:

```typescript
// Find this pattern (WRONG):
const aabb = expandBounds(bounds, padding);

// Replace with (CORRECT):
const [top, right, bottom, left] = offsetFromHeading(heading, head, side);
const aabb = [
  bounds[0] - left,
  bounds[1] - top,
  bounds[2] + right,
  bounds[3] + bottom
];
```

---

## Quick Reference: Correct Values

| Scenario | Head Padding | Side Padding | Exit Segment (approx) |
|----------|--------------|--------------|----------------------|
| With arrowhead | 10 | 40 | 15-20px |
| Without arrowhead | 30 | 40 | 35-40px |
| Bounds overlap | 40 | 0 | 45-50px |

---

## Need More Help?

See the full technical solution in:
- `docs/elbow/03-elbow-arrow-segment-length-fix.md`

Reference implementation in:
- `packages/element/src/elbowArrow.ts`
