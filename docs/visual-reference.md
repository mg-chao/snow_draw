# Elbow Arrow Fixed Segments - Visual Reference

This document provides visual diagrams to supplement the main PRD.

---

## 1. Arrow Structure

### 1.1 Basic Elbow Arrow (3 segments)

```
    Start                                              End
      ●━━━━━━━━━━━━━━━●                                 
      P0   Segment 1   P1                               
           (idx=1)      │                               
                        │ Segment 2                     
                        │ (idx=2)                       
                        │                               
                        ●━━━━━━━━━━━━━━━●               
                       P2   Segment 3   P3              
                            (idx=3)                     
```

### 1.2 Complex Elbow Arrow (5 segments)

```
    ●━━━━━●
    P0    P1
          │
          ●━━━━━━━━━●
          P2        P3
                    │
                    ●━━━━━●
                    P4    P5
```

---

## 2. Fixed vs Free Segments

### 2.1 Arrow with One Fixed Segment

```
    ●━━━━━━━━━━●                    
    P0  FREE   P1                    
               │                     
               ■━━━━━━━━━■  ← FIXED (idx=2)
               P2        P3          
                         │           
                    ●━━━━●           
                    P4   P5          
                    FREE             

Legend:
  ━━━  Free segment (auto-routed)
  ■━■  Fixed segment (user-controlled)
```

### 2.2 Arrow with Multiple Fixed Segments

```
    ●━━━━●                
    FREE  │               
          ■━━━━━━■  ← FIXED (idx=2)
                 │        
          ■━━━━━━■  ← FIXED (idx=3)
          │               
          ●━━━━━●         
            FREE          
```

---

## 3. Fixing a Segment

### 3.1 Before Drag

```
    ●━━━━━━━━━●           
              │           
              ●━━━━━━━●   
              │           
              ●           
              
    User hovers over segment 2 midpoint
                 ↓
              ●━━━━[◆]━━━●   ← Midpoint handle appears
```

### 3.2 During Drag (Vertical Segment)

```
    Original position          Dragged position
    
    ●━━━━━━━━━●               ●━━━━━━━━━━━━━━━━●
              │                                │
              ●━━━━━━━●       ●━━━━━━━━━━━━━━━━●
              │               │
              ●               ●
              
    User drags midpoint to the right →
    Segment moves along its perpendicular axis (X)
```

### 3.3 After Drag

```
    ●━━━━━━━━━━━━━━━━●
                     │
    ■━━━━━━━━━━━━━━━━■  ← Now FIXED
    │
    ●
```

---

## 4. Path Consistency When Fixing

### 4.1 The Consistency Problem

```
    Original segment:           User clicks slightly off-center:
    
    ●━━━━━━━━━●                 ●━━━━━━━━━●
              │                           │
              ●━━━━━●                     │  ← Segment could "jump" here!
                                          ●━━━━━●
              ↑
    User clicks here (within tolerance but not exactly on line)
```

### 4.2 Coordinate Preservation Strategy

For HORIZONTAL segments (Y is the "moving" axis):

```
    Existing points:
    P0━━━━━━P1 (horizontal, Y=100)
            │
           P2 (Y=150)
    
    User clicks at (x=75, y=103) to fix segment 1:
    
    Fixed Segment Result:
    start.x = P0.x (PRESERVED from existing)
    start.y = 103  (from click - could cause jump!)
    end.x   = P1.x (PRESERVED from existing)
    end.y   = 103  (from click)
    
    Better approach - use true segment Y:
    start.y = 100  (from true segment position)
    end.y   = 100  (from true segment position)
```

### 4.3 Recommended: Two-Phase Fixing

```
    Phase 1: Click (no movement yet)
    ●━━━━━━━━━● ← Use TRUE segment position
              │    Segment marked as "fixed" but doesn't move
              ●
    
    Phase 2: Drag (movement begins)
    ●━━━━━━━━━━━━━● ← NOW apply drag delta
                  │    from original position
                  ●
    
    Result: No "jump" on initial click
```

### 4.4 Current Behavior Analysis

The current implementation:
1. **Non-moving axis**: Always preserved from existing points ✓
2. **Moving axis**: Uses interaction position (may cause micro-jump)

```
    For vertical segment:
    
    Interaction at X=153      Existing segment at X=150
    
              ↓                       │
    ●━━━━━━━━━━●            ●━━━━━━━━━●
              │                       │
              │ ← Segment created     │ ← Original position
              │    at X=153           │
              ●                       ●
    
    3px difference - may be noticeable!
```

**Recommendation**: For production quality, consider snapping to original position when the delta is below a threshold (e.g., 5px).

### 4.5 Path Consistency for Bound Arrows

When an arrow is bound to elements, only MIDDLE segments can be fixed:

```
    Element A                                Element B
    ┌─────────┐                             ┌─────────┐
    │         ●━━━━━●━━━━━━━●━━━━━●         │         │
    │         │ P0   P1     P2    P3       │         │
    └─────────┘  ↑                    ↑     └─────────┘
              [✗ Cannot fix]    [✗ Cannot fix]
                        ↑
                   [✓ Can fix]
    
    Only segment 2 (P1→P2) can be fixed in this example.
```

**Why bound arrows have implicit consistency**:

```
    The middle segment's position is already determined by:
    
    ┌─────────┐
    │         ●━━━━━● ← Exit direction determines P1 position
    │ Element │      │
    └─────────┘      │
                     ● ← Routing placed P2 here
                     │
                     ●━━━━━● ← Entry direction determines last segment
                           │
                     ┌─────┴─────┐
                     │  Element  │
                     └───────────┘
    
    When you fix segment P1→P2, you capture its CURRENT position.
    This is already consistent with the bound structure.
```

**Fixing a middle segment on bound arrow**:

```
    Step 1: Arrow bound to two elements
    
    ┌───┐                    ┌───┐
    │ A ●━━━━●━━━━━━●━━━━●   │ B │
    └───┘         ↑         └───┘
              User clicks here
    
    Step 2: Middle segment becomes fixed
    
    ┌───┐                    ┌───┐
    │ A ●━━━━●━━━━━━●━━━━●   │ B │
    └───┘    │      ↑    │   └───┘
             │   FIXED   │
             │           │
         Exit segment    Entry segment
         UNCHANGED       UNCHANGED
```

**Edge case - Element moves after fixing**:

```
    Before:                      After element A moves down:
    
    ┌───┐                        
    │ A ●━━━━●                        ┌───┐
    └───┘    │                        │ A │
       ■━━━━━■ FIXED                  └─●─┘
             │                          │
             ●━━━━●                     ●━━━●
                  │                         │
             ┌────┴────┐               ■━━━━■ FIXED (same Y position!)
             │    B    │                    │
             └─────────┘                    ●━━━━●
                                                 │
                                           ┌─────┴─────┐
                                           │     B     │
                                           └───────────┘
    
    The fixed segment's perpendicular position (Y) is preserved.
    Exit/entry segments recalculate to connect to the fixed segment.
```

---

## 5. Endpoint Drag with Fixed Segment

### 5.1 Initial State

```
    Start●━━━━━━━━●A
                  │
                  ■━━━━━━■B  ← FIXED (idx=2)
                         │
                    ●━━━━●End
```

### 5.2 Drag Start Point Right

```
              NewStart●━━━━━●A'     ← A' recalculated
                            │
                      ■━━━━━■B'     ← B' coordinates updated!
                            │
                       ●━━━━●End
    
    Key insight:
    - Fixed segment's Y position preserved
    - But start/end points (A', B') recalculated from new points
    - Length has CHANGED
```

### 5.3 Coordinate Recalculation Logic

```
    Before:
    A = (100, 50)     B = (100, 150)    Fixed length = 100
    
    After start drag (+50 on X):
    A' = (150, 50)    B' = (150, 150)   Fixed length = 100 ✓ (same)
    
    After start drag (+50 on X, -30 on Y):
    A' = (150, 20)    B' = (150, 150)   Fixed length = 130 ✗ (changed!)
    
    The perpendicular position (X=150) is preserved,
    but endpoint connection changes the length.
```

---

## 6. Connection Point Calculation

### 6.1 Free Segment Regeneration

When endpoint moves, the connection point keeps one coordinate from the old position:

```
    Old:                          New:
    
    ●A━━━━━━●B                    ●A'━━━━━━━━━━●B'
            │                                   │
            ●C━━━━●D                     ●━━━━━━●D
    
    B' calculation:
    - If segment A-B was horizontal:
      B'.x = B.x (preserved from old point)
      B'.y = A'.y (from new endpoint)
    
    - If segment A-B was vertical:
      B'.x = A'.x (from new endpoint)
      B'.y = B.y (preserved from old point)
```

---

## 7. Special Point Handling

### 7.1 Without Special Point (startIsSpecial = false)

```
    Element
    ┌─────────┐
    │         ●━━━━━●━━━━━●━━━━━●
    │         │ P0   P1    P2    P3
    └─────────┘
    
    Visual path: P0 → P1 → P2 → P3
```

### 7.2 With Special Point (startIsSpecial = true)

```
    Element
    ┌─────────┐
    │         ●━━●━━━━━●━━━━━●━━━━━●
    │         │ P0  P1  P2    P3    P4
    └─────────┘      ↑
                     Hidden (special point)
    
    Visual path: P0 → P2 → P3 → P4
    P1 data is preserved but not rendered
```

### 7.3 Why Special Points Exist

```
    Scenario: Arrow bound horizontally, element moves to require vertical exit
    
    Before (horizontal exit):
    ┌─────┐
    │     ●━━━━━●
    └─────┘     │
                ●
    
    After (needs vertical exit):
    ┌─────┐
    │  ●  │      Without special point: would lose segment structure
    └──│──┘      With special point: structure preserved, extra point hidden
       │
       ●━━━━━●
```

---

## 8. Segment Move Effects on Neighbors

### 8.1 Moving Middle Fixed Segment

```
    Before:                After moving segment 3 right:
    
    ●━━━●                  ●━━━━━━━━━●
        │                            │
        ■━━━■  (idx=2)               ■━━━■  ← Adjusted!
            │                            │
        ■━━━■  (idx=3)           ■━━━━━━━■  ← Moved
            │                            │
        ●━━━●                        ●━━━●
    
    Segment 2's end point follows segment 3's start point
```

### 8.2 Adjacent Fixed Segments

```
    Before:                After moving segment 2 down:
    
    ●━━━━━━●               ●━━━━━━━━━━●
           │                          │
    ■━━━━━━■  (idx=2)                 │
           │                          │
    ■━━━━━━■  (idx=3)      ■━━━━━━━━━━■  ← Segment 2 moved
           │               │             
           ●               ■━━━━━━━━━━■  ← Segment 3 adjusted
                           │
                           ●
```

---

## 9. Segment Release and Re-routing

### 9.1 Before Release

```
    ●━━━━━●
          │
    ■━━━━━■  (idx=2, FIXED)
          │
    ■━━━━━■  (idx=3, FIXED)
          │
          ●━━━━━●
```

### 9.2 After Releasing Segment 2

```
    Region to re-route
    ┌─────────────┐
    │ ●━━━━━●     │
    │       │     │
    │       ●━━━━━│━━┐  ← New routed path
    └─────────────┘  │
    ■━━━━━━━━━━━━━━━━■  (idx=3, still FIXED)
                     │
                     ●━━━━━●
    
    Only the region between Start and next fixed segment is re-routed
```

---

## 10. First/Last Segment Restrictions

### 10.1 Cannot Fix First Segment When Bound

```
    Element
    ┌─────────┐
    │         ●━━━━[✗]━━━●━━━━●━━━━●
    │         │          ↑
    └─────────┘    Cannot fix - controlled by binding
    
    But if unbound:
    
    ●━━━━[✓]━━━●━━━━●━━━━●
          ↑
    Can fix when not bound to element
```

### 10.2 Cannot Fix Last Segment When Bound

```
                                Element
                              ┌─────────┐
    ●━━━━●━━━━●━━━━[✗]━━━━●   │         │
                        ↑     └─────────┘
              Cannot fix - controlled by binding
```

---

## 11. Coordinate System

### 11.1 Local vs Global Coordinates

```
    Canvas (Global)
    ┌──────────────────────────────────┐
    │                                  │
    │     Arrow Origin (100, 200)      │
    │            ●                     │
    │            │                     │
    │            ●━━━━●                │
    │                                  │
    └──────────────────────────────────┘
    
    Arrow Data (Local):
    {
      x: 100,      // Arrow origin X (global)
      y: 200,      // Arrow origin Y (global)
      points: [
        (0, 0),    // P0 - local (global: 100, 200)
        (0, 50),   // P1 - local (global: 100, 250)
        (80, 50)   // P2 - local (global: 180, 250)
      ],
      fixedSegments: [
        {
          index: 2,
          start: (0, 50),   // Local coordinates
          end: (80, 50)     // Local coordinates
        }
      ]
    }
    
    Global = Arrow Origin + Local
    Local = Global - Arrow Origin
```

---

## 12. Operation Flow Diagrams

### 12.1 Update Decision Tree

```
                    updateElbowArrowPoints()
                            │
                            ▼
                    ┌───────────────┐
                    │ Has updates?  │
                    └───────┬───────┘
                            │
              ┌─────────────┼─────────────┐
              │ No          │             │ Yes
              ▼             │             ▼
    ┌─────────────────┐     │    ┌─────────────────┐
    │ Renormalization │     │    │ Has fixed segs? │
    └─────────────────┘     │    └────────┬────────┘
                            │             │
                            │    ┌────────┼────────┐
                            │    │ No     │        │ Yes
                            │    ▼        │        ▼
                            │   Full      │    ┌────────────┐
                            │   Route     │    │ Seg count  │
                            │             │    │ decreased? │
                            │             │    └─────┬──────┘
                            │             │          │
                            │             │    ┌─────┼─────┐
                            │             │    │ Yes │     │ No
                            │             │    ▼     │     ▼
                            │             │  Release │   Move/Drag
                            │             │  Handler │   Handler
                            │             │          │
                            └─────────────┴──────────┘
```

---

## 13. State Machine

```
    ┌──────────────────────────────────────────────────────────┐
    │                                                          │
    │    ┌─────────────┐      Fix segment      ┌────────────┐ │
    │    │             │ ───────────────────► │             │ │
    │    │  FULLY AUTO │                       │  PARTIALLY │ │
    │    │             │ ◄─────────────────── │   FIXED    │ │
    │    └─────────────┘   Release all /       └────────────┘ │
    │                      Invalidate all              │      │
    │                                                  │      │
    │                                         Fix more │      │
    │                                                  ▼      │
    │                                          ┌────────────┐ │
    │                                          │   MOSTLY   │ │
    │                                          │   FIXED    │ │
    │                                          └────────────┘ │
    │                                                         │
    └──────────────────────────────────────────────────────────┘
```

---

## 14. Common Scenarios

### 14.1 Simple Connector Between Two Boxes

```
    ┌─────────┐                     ┌─────────┐
    │   Box   ●━━━━━●━━━━━●━━━━━●   │   Box   │
    │    A    │           ↑        │    B    │
    └─────────┘     User fixes     └─────────┘
                    this segment
                    
    Result: Middle segment stays in place when boxes move
```

### 14.2 Avoiding Obstacles

```
    ┌─────────┐       ┌─────────┐
    │  Start  ●━━━━━━━│ Obstacle│━━━━━━━●  End
    └─────────┘       └─────────┘
    
    User fixes vertical segment to route around obstacle:
    
    ┌─────────┐       ┌─────────┐
    │  Start  ●━━━●   │ Obstacle│
    └─────────┘   │   └─────────┘
                  ■                    ← FIXED
                  │
                  ●━━━━━━━━━━━━━●  End
```

---

This visual reference should be used alongside the main PRD for implementation guidance.
