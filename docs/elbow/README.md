# Elbow Arrow Editing Documentation

This documentation provides a complete specification for implementing elbow arrow editing functionality in a drawing application.

## Document Overview

| Document | Description | Use Case |
|----------|-------------|----------|
| [elbow-arrow-editing-specification.md](./elbow-arrow-editing-specification.md) | Complete technical specification | Primary implementation reference |
| [implementation-quick-reference.md](./implementation-quick-reference.md) | Condensed reference guide | Quick lookup during development |
| [visual-concepts-guide.md](./visual-concepts-guide.md) | Visual explanations with ASCII diagrams | Understanding concepts |

## Quick Start

### Prerequisites

Before implementing elbow arrow editing, ensure you have:

1. **Basic elbow arrow rendering** - Ability to draw orthogonal polylines
2. **Element selection system** - Click to select, handles for interaction
3. **Binding system** - Connecting arrows to other elements (optional but recommended)

### Implementation Order

```
Phase 1: Data Structures
├── Define ElbowArrowElement type
├── Define FixedSegment type
└── Implement coordinate helpers

Phase 2: A* Routing
├── Grid generation
├── A* algorithm
└── Path post-processing

Phase 3: Basic Editing
├── Endpoint dragging
└── Auto-rerouting

Phase 4: Fixed Segments
├── Segment fixing (midpoint drag)
├── Segment moving
└── Segment releasing

Phase 5: Polish
├── UI handles
├── Edge cases
└── Validation
```

## Key Concepts

### What Makes Elbow Arrows Special?

1. **Orthogonal Only** - All segments must be horizontal or vertical
2. **Auto-Routing** - Path calculated automatically using A* algorithm
3. **Fixed Segments** - User can lock segments to prevent auto-routing
4. **Smart Padding** - Maintains distance from connected elements

### Core Algorithm Summary

```
User Action → Determine Scenario → Route/Adjust → Validate → Apply
```

**Six Scenarios:**
1. Renormalization (cleanup)
2. Normal routing (no fixed segments)
3. Segment release
4. Segment move
5. Resize
6. Endpoint drag with fixed segments

## Common Questions

### Why A* instead of simple routing?

A* provides:
- Obstacle avoidance
- Optimized path (fewer turns)
- Predictable results

### Why use a non-uniform grid?

- More efficient than uniform grid
- Grid lines at meaningful positions (element edges)
- Fewer nodes to process

### Why can't first/last segments be fixed?

These segments must adapt to:
- Binding position changes
- Element movement
- Heading (direction) changes

## File Structure Suggestion

```
your-project/
├── src/
│   ├── elements/
│   │   ├── elbow-arrow/
│   │   │   ├── types.ts           # Type definitions
│   │   │   ├── routing.ts         # A* algorithm
│   │   │   ├── editing.ts         # Edit handlers
│   │   │   ├── fixed-segments.ts  # Fixed segment logic
│   │   │   ├── validation.ts      # Validation helpers
│   │   │   └── utils.ts           # Coordinate helpers
│   │   └── ...
│   └── ...
└── ...
```

## Testing Strategy

### Unit Tests
- A* algorithm correctness
- Grid generation
- Coordinate conversion
- Validation functions

### Integration Tests
- End-to-end editing flows
- Binding with elements
- Undo/redo compatibility

### Visual Tests
- Render comparison
- Handle positioning
- Edge case rendering

## Performance Considerations

- **Grid size**: Keep manageable (typically < 100 nodes)
- **Path caching**: Cache routes until element changes
- **Throttle updates**: During drag, limit recalculations
- **Early termination**: Stop A* when path found

## Version History

| Version | Date | Notes |
|---------|------|-------|
| 1.0 | 2026-01-29 | Initial documentation |
