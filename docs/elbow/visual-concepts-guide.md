# Elbow Arrow Visual Concepts Guide

This document provides visual explanations of key concepts in elbow arrow editing.

---

## 1. Elbow Arrow vs Regular Arrow

### Regular Arrow
```
    Start ●────────────────────● End
           \                  /
            Allows any angle
```

### Elbow Arrow
```
    Start ●────────┐
                   │  Only 90° angles
                   │
                   └──────────● End
```

---

## 2. Points Array Structure

```
points[0]     points[1]     points[2]     points[3]
    ●────────────●             ●────────────●
    [0,0]        [100,0]       [100,80]     [200,80]
                               │
                               │  Each point connects to next
                               │  with orthogonal segment
```

**Key Rules:**
- `points[0]` is ALWAYS `[0, 0]` (local origin)
- Element's `(x, y)` is the global position of `points[0]`
- All other points are relative to `points[0]`

---

## 3. Fixed Segments

### Before Fixing (Auto-routed)
```
         Segment 1    Segment 2    Segment 3
    ●─────────────●─────────────●─────────────●
    │             │             │             │
  index 0      index 1      index 2      index 3
```

### After Fixing Segment 2
```
    ●─────────────●══════════════●─────────────●
                  │              │
               Fixed segment   Locked position
              (index: 2)       Won't auto-reroute
```

### FixedSegment Data Structure
```
{
  index: 2,                    // Points to ending point
  start: [100, 0],             // Local coords of segment start
  end: [100, 80]               // Local coords of segment end
}
```

---

## 4. Non-Uniform Grid Generation

### Input: Two Elements with Bounds
```
    ┌──────────────┐
    │   Element A  │
    └──────────────┘
                            ┌──────────────┐
                            │   Element B  │
                            └──────────────┘
```

### Generated Grid (not uniform!)
```
    x1   x2        x3   x4   x5   x6
y1  ●────●─────────●────●────●────●
    │    │         │    │    │    │
y2  ●────●─────────●────●────●────●
    │    │▓▓▓▓▓▓▓▓▓│    │    │    │
y3  ●────●▓▓▓▓▓▓▓▓▓●────●────●────●
    │    │         │    │▓▓▓▓│    │
y4  ●────●─────────●────●▓▓▓▓●────●
    │    │         │    │▓▓▓▓│    │
y5  ●────●─────────●────●────●────●

▓ = Element bounds (obstacles)
● = Grid node (potential path point)

Grid lines are placed at:
- Element left/right edges
- Element top/bottom edges  
- Common bounding box edges
- Start/end point positions
```

---

## 5. A* Pathfinding

### Step-by-Step Visualization

**Initial State:**
```
    S = Start node
    E = End node
    ▓ = Obstacle
    
    S────●────●────●
    │    │    │    │
    ●────●────▓────●
    │    │    ▓    │
    ●────●────▓────E
```

**After A* Completes:**
```
    S════●    ●    ●      ═ = Final path
         ║    │    │
    ●    ●────▓────●
    │    ║    ▓    │
    ●    ●════▓════E
         
    Turn penalty makes straighter paths preferred
```

### Cost Calculation
```
g(node) = cost from start
        = distance + turn_penalty

h(node) = heuristic to end
        = manhattan_distance + estimated_bends * bend_factor

f(node) = g(node) + h(node)
```

---

## 6. Dynamic AABB (Bounding Boxes)

### Single Element AABB
```
    padding
    ◄──────►
    ┌──────────────────────┐ ▲
    │  ┌──────────────┐    │ │ padding
    │  │   Element    │    │ ▼
    │  └──────────────┘    │
    │        AABB          │
    └──────────────────────┘
```

### Two Elements - AABBs Meet in Middle
```
    ┌─────────────────┐     ┌─────────────────┐
    │  ┌───────────┐  │     │  ┌───────────┐  │
    │  │  Elem A   │  │     │  │  Elem B   │  │
    │  └───────────┘  │     │  └───────────┘  │
    │    AABB A       │     │    AABB B       │
    └─────────────────┴─────┴─────────────────┘
                      ▲
                      │
              AABBs touch here
```

---

## 7. Heading Directions

```
              HEADING_UP
                  ▲
                  │
                  │
    HEADING_LEFT ◄─●─► HEADING_RIGHT
                  │
                  │
                  ▼
              HEADING_DOWN
```

### Heading from Element Side
```
    ┌──────────────────┐
    │        ▲         │
    │   up   │         │
    │◄───────●───────► │
    │ left   │   right │
    │        ▼         │
    │      down        │
    └──────────────────┘
```

---

## 8. Dongle Points

Dongles are exit points from the element's padded AABB:

```
              dongle (up)
                  ●
                  │
                  │ padding
    ┌─────────────┼─────────────┐
    │             │             │
    │       ┌─────┴─────┐       │
    │       │  Element  │       │
    │       └───────────┘       │
    │            AABB           │
    └───────────────────────────┘
```

The arrow path goes: **Endpoint → Dongle → A* Path → Dongle → Endpoint**

---

## 9. Segment Movement Constraints

### Horizontal Segment (moves vertically)
```
    Before:                After dragging:
    
    ●═══════════●          ●───────────●
                           │           │
                           │     ▼     │ drag direction
                           │           │
                           ●═══════════●
```

### Vertical Segment (moves horizontally)
```
    Before:        After dragging:
    
        ●              ●           ●
        ║              │     ►     ║
        ║              │   drag    ║
        ║              │           ║
        ●              ●           ●
```

---

## 10. First/Last Segment Restriction

### Cannot Fix First or Last Segment
```
    ●═══════════●───────────●───────────●
    │           │           │           │
  segment 1  segment 2  segment 3  segment 4
  (CANNOT   (CAN fix)  (CAN fix)  (CANNOT
   fix)                             fix)
```

**Reason:** First and last segments need to adapt to binding positions.

---

## 11. Segment Release Flow

### Before Release (segment 2 is fixed)
```
    ●───────────●═══════════●───────────●
                │           │
              fixed       fixed
```

### During Release (double-click on segment 2)
```
    ●───────────●     ?     ●───────────●
                │           │
              released portion
              gets re-routed via A*
```

### After Release
```
    ●───────────●───┐
                    │   New auto-routed
                    │   path
    ●───────────────┴───────────────────●
```

---

## 12. UI Handle States

```
Legend:
  ○ = Endpoint handle (hollow circle)
  ● = Regular point
  □ = Midpoint handle (square)
  ■ = Fixed segment midpoint (filled square)

Arrow with 4 points:

    ○───────────□───────────●───────────○
    │           │           │           │
  endpoint   midpoint    midpoint   endpoint
  handle    (can fix)   (can fix)   handle
  (draggable)                      (draggable)

Arrow with fixed segment 2:

    ○───────────■───────────□───────────○
                │
             fixed
           (different color/style)
```

---

## 13. Coordinate System

```
    Global Canvas Coordinates
    ═════════════════════════
    
    (0,0) ─────────────────────────────► X
      │
      │    element.x = 100
      │    element.y = 50
      │         │
      │         ▼
      │       (100,50) ●───────●
      │                │       │  points[0] = [0,0]
      │                │       │  points[1] = [80,0]
      │                ●───────●  points[2] = [80,60]
      │                           points[3] = [150,60]
      │
      ▼
      Y
    
    To convert points[2] to global:
    global = [100 + 80, 50 + 60] = [180, 110]
```

---

## 14. Normalization After Edit

### Before Normalization (start point moved)
```
    Global coords:
    
    points[0] = [50, 30]    ← No longer at [0,0]!
    points[1] = [100, 30]
    points[2] = [100, 80]
    element.x = 100
    element.y = 50
```

### After Normalization
```
    offset = points[0] = [50, 30]
    
    New values:
    points[0] = [0, 0]           ← Subtract offset
    points[1] = [50, 0]
    points[2] = [50, 50]
    element.x = 150              ← Add offset
    element.y = 80
```

---

## 15. Path Post-Processing

### Remove Collinear Points
```
    Before:        After:
    
    ●──●──●──●     ●────────●
    │           →  │
    ●──●──●        ●────────●
```

### Remove Short Segments
```
    Before:           After:
    
    ●────●            ●────┐
         │      →          │
         ●──●              ●
         │   (< 1px)
         ●
```

---

## Summary: Complete Editing Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    USER INTERACTION                          │
├─────────────────────────────────────────────────────────────┤
│  1. User drags endpoint/midpoint                            │
│                    │                                         │
│                    ▼                                         │
│  2. Calculate new positions                                  │
│                    │                                         │
│                    ▼                                         │
│  3. Determine scenario (1-6)                                │
│                    │                                         │
│         ┌─────────┴─────────┐                               │
│         ▼                   ▼                               │
│    Has fixed            No fixed                            │
│    segments?            segments                            │
│         │                   │                               │
│         ▼                   ▼                               │
│    Preserve &          Full A*                              │
│    adjust              reroute                              │
│         │                   │                               │
│         └─────────┬─────────┘                               │
│                   ▼                                         │
│  4. Post-process path                                       │
│                   │                                         │
│                   ▼                                         │
│  5. Normalize to local coords                               │
│                   │                                         │
│                   ▼                                         │
│  6. Validate & apply update                                 │
│                   │                                         │
│                   ▼                                         │
│  7. Render updated arrow                                    │
└─────────────────────────────────────────────────────────────┘
```
