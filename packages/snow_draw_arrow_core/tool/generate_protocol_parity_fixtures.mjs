import fs from "node:fs";
import path from "node:path";
import {
  DEFAULT_ENGINE_CONTEXT,
  executeArrowOperationSafe,
  getArrowProtocolManifest,
} from "file:///E:/excalidraw-arrow/excalidraw-write/packages/arrow-core/dist/prod/index.js";

const bindable1 = {
  id: "b1",
  shape: "rectangle",
  x: 0,
  y: 0,
  width: 100,
  height: 80,
  angle: 0,
  strokeWidth: 2,
  roundness: null,
  zIndex: 1,
  backgroundOpaque: true,
  bindingEnabled: true,
  interiorHitEnabled: true,
};

const bindable2 = {
  id: "b2",
  shape: "ellipse",
  x: 240,
  y: 40,
  width: 120,
  height: 90,
  angle: 0,
  strokeWidth: 2,
  roundness: null,
  zIndex: 2,
  backgroundOpaque: true,
  bindingEnabled: true,
  interiorHitEnabled: true,
};

const arrowBase = {
  id: "a1",
  x: 100,
  y: 100,
  width: 200,
  height: 120,
  points: [
    [0, 0],
    [200, 0],
    [200, 120],
  ],
  startBinding: null,
  endBinding: null,
  startArrowhead: null,
  endArrowhead: "arrow",
  elbowed: false,
  fixedSegments: null,
  startIsSpecial: null,
  endIsSpecial: null,
};

const elbowArrow = {
  ...arrowBase,
  id: "a2",
  elbowed: true,
  points: [
    [0, 0],
    [120, 0],
    [120, 140],
    [220, 140],
  ],
  fixedSegments: [{ index: 2, start: [120, 0], end: [120, 140] }],
};

const arrowBindingState = {
  id: "a1",
  startBinding: null,
  endBinding: null,
};

const relationState = [
  { id: "b1", boundArrowIds: ["a1"] },
  { id: "b2", boundArrowIds: [] },
];

const baseEngineResult = {
  arrowPatch: {},
  bindablePatches: [],
  suggestedBinding: null,
  events: [],
};

const defaults = {
  arrow: arrowBase,
  arrows: [arrowBase],
  bindable: bindable1,
  bindables: [bindable1, bindable2],
  relations: relationState,
  left: [{ id: "a1", type: "arrow" }],
  right: [
    { id: "a1", type: "arrow" },
    { id: "a2", type: "arrow" },
  ],
  previous: {
    startBinding: null,
    endBinding: null,
  },
  next: {
    startBinding: {
      elementId: "b1",
      fixedPoint: [0.5, 0.5],
      mode: "orbit",
    },
    endBinding: null,
  },
  binding: {
    elementId: "b1",
    fixedPoint: [0.5, 0.5],
    mode: "orbit",
  },
  edge: "start",
  draggedEdge: "start",
  inner: bindable1,
  outer: {
    ...bindable1,
    id: "b3",
    x: -10,
    y: -10,
    width: 200,
    height: 160,
  },
  point: [10, 10],
  pointer: [110, 110],
  otherPoint: [200, 110],
  delta: [8, 0],
  originPoint: [0, 0],
  focusPoint: [20, 20],
  points: [
    [0, 0],
    [100, 0],
    [100, 80],
  ],
  arrowPoints: [
    [0, 0],
    [100, 0],
  ],
  customIntersector: [
    [0, 0],
    [100, 0],
  ],
  aabb: [0, 0, 120, 90],
  context: DEFAULT_ENGINE_CONTEXT,
  result: baseEngineResult,
  events: [],
  orderedElementIds: ["b1", "b2", "a1", "a2"],
  anchorElementIds: ["b1"],
  deletedBindableIds: ["b2"],
  deletedArrowIds: ["a2"],
  retainedBindableIds: ["b1"],
  boundArrowIds: ["a1"],
  changedBindableIds: ["b1"],
  bindableIdMap: { b1: "b1-copy" },
  arrowIdMap: { a1: "a1-copy" },
  anchorElementIdsByBindableId: { b1: ["b1"] },
  zoom: 1,
  tolerance: 24,
  strokeWidth: 2,
  radius: 10,
  arrowheadSize: 8,
  minimumLength: 0.5,
  maxCoordinate: 1_000_000,
  flipX: false,
  flipY: false,
  elbowed: true,
  dragging: true,
  preserveUnmapped: true,
  ignoreOverlap: false,
  direction: "right",
  position: "end",
  mode: "orbit",
  transformHandleType: "se",
  arrowId: "a1",
  hoveredBindableId: "b1",
  arrowhead: "arrow",
  strokeStyle: "solid",
  segmentIndex: 2,
  draggedPoints: [{ index: 0, point: [0, 0] }],
  startBounds: { x: 0, y: 0, width: 100, height: 100 },
  endBounds: { x: 260, y: 0, width: 120, height: 100 },
  updates: {
    points: [
      [0, 0],
      [220, 140],
    ],
  },
  options: { isDragging: false },
  patch: {
    points: [
      [0, 0],
      [120, 0],
    ],
  },
  patches: [{ id: "a1", patch: { startBinding: null } }],
  curveOps: [],
  fixedSegments: [{ index: 2, start: [120, 0], end: [120, 140] }],
  arrowPatch: {
    points: [
      [0, 0],
      [200, 0],
    ],
  },
  bindablePatches: [{ id: "b1", addBoundArrowId: "a1" }],
  geometryBindables: [bindable1, bindable2],
  existingBindables: [bindable1, bindable2],
};

const elbowOps = new Set([
  "recompute-elbow",
  "update-elbow-arrow",
  "compute-elbow-resize-patch",
  "move-fixed-segment",
  "move-fixed-segment-to-point",
  "release-fixed-segment",
  "validate-elbow-points",
  "repair-invalid-unbound-elbow-arrow-on-restore",
  "repair-self-bound-extreme-elbow-arrow-on-restore",
  "validate-elbow-invariant",
]);

const bindingStateOps = new Set([
  "finalize-focus-point-drag",
  "apply-arrow-binding-state-patch",
  "apply-arrow-binding-state-patches",
]);

const buildInputForOperation = (operation) => {
  if (operation.inputKind === "null") {
    return null;
  }

  const input = {};
  for (const field of operation.requiredInputFields) {
    input[field] = defaults[field];
  }

  if ("arrow" in input) {
    input.arrow = elbowOps.has(operation.type) ? elbowArrow : arrowBase;
  }
  if (bindingStateOps.has(operation.type) && "arrow" in input) {
    input.arrow = arrowBindingState;
  }

  switch (operation.type) {
    case "apply-arrow-binding-state-patch":
      input.arrow = arrowBindingState;
      input.patch = { id: "a1", startBinding: null };
      break;
    case "apply-arrow-binding-state-patches":
      input.arrows = [arrowBindingState];
      input.patches = [{ id: "a1", startBinding: null }];
      break;
    case "finalize-focus-point-drag":
      input.arrow = arrowBindingState;
      input.bindables = relationState;
      break;
    case "recompute-bindings-for-changed-bindables":
      input.arrows = [arrowBase, elbowArrow];
      input.bindables = [bindable1, bindable2];
      input.relations = relationState;
      break;
    case "apply-engine-result":
      input.arrow = arrowBase;
      input.bindables = relationState;
      input.result = baseEngineResult;
      break;
    case "derive-bindable-relation-patches-for-binding-change":
      input.bindables = relationState;
      break;
    case "reconcile-bindable-patches-for-arrow":
      input.arrow = arrowBindingState;
      input.bindables = relationState;
      break;
    case "resolve-bindable-relation-patches":
      input.arrow = arrowBindingState;
      input.bindables = relationState;
      break;
    case "remap-bindable-relations-after-duplication":
      input.bindables = relationState;
      break;
    case "repair-bindable-relations-after-arrow-deletion":
      input.bindables = relationState;
      break;
    case "sync-bindings-after-duplication":
    case "sync-bindings-after-bindable-prune":
    case "sync-bindings-after-deletion":
      input.bindables = relationState;
      input.arrows = [arrowBase, elbowArrow];
      input.geometryBindables = [bindable1, bindable2];
      break;
    case "reduce-bindable-patches-to-relation-patches":
      input.bindables = relationState;
      break;
    case "apply-bindable-relation-patch":
      input.bindable = relationState[0];
      input.patch = { id: "b1", boundArrowIds: ["a1", "a2"] };
      break;
    case "apply-bindable-relation-patches":
      input.bindables = relationState;
      input.patches = [{ id: "b1", boundArrowIds: ["a1", "a2"] }];
      break;
    case "merge-arrow-bound-relations":
      input.relations = [{ id: "a1", type: "arrow" }];
      input.boundArrowIds = ["a1", "a2"];
      break;
    case "are-bound-relations-equal":
      input.left = [{ id: "a1", type: "arrow" }];
      input.right = [{ id: "a1", type: "arrow" }];
      break;
  }

  return input;
};

const toCaseId = (type, suffix = "default") => `${type}:${suffix}`;

const operations = getArrowProtocolManifest().operations;
const cases = [];
for (const operation of operations) {
  const input = buildInputForOperation(operation);
  const request = { type: operation.type, input };
  const expected = executeArrowOperationSafe(request);
  cases.push({
    id: toCaseId(operation.type),
    request,
    expected,
  });
}

const extraCases = [
  {
    id: "compute-endpoint-drag:endpoint-1",
    request: {
      type: "compute-endpoint-drag",
      input: {
        arrow: elbowArrow,
        draggedPoints: [{ index: elbowArrow.points.length - 1, point: [260, 180] }],
        pointer: [260, 180],
        bindables: [bindable1, bindable2],
        context: DEFAULT_ENGINE_CONTEXT,
        options: { complexBindings: true },
      },
    },
  },
  {
    id: "update-elbow-arrow:fixed-segment-only",
    request: {
      type: "update-elbow-arrow",
      input: {
        arrow: elbowArrow,
        updates: {
          fixedSegments: [{ index: 2, start: [120, 20], end: [120, 160] }],
        },
        bindables: [bindable1, bindable2],
        context: DEFAULT_ENGINE_CONTEXT,
        options: { isDragging: true },
      },
    },
  },
  {
    id: "move-fixed-segment-to-point:first-segment",
    request: {
      type: "move-fixed-segment-to-point",
      input: {
        arrow: {
          ...elbowArrow,
          fixedSegments: [{ index: 1, start: [0, 0], end: [120, 0] }],
        },
        segmentIndex: 1,
        pointer: [40, 20],
      },
    },
  },
];

for (const extraCase of extraCases) {
  cases.push({
    ...extraCase,
    expected: executeArrowOperationSafe(extraCase.request),
  });
}

const output = {
  arrowProtocolVersion: getArrowProtocolManifest().version,
  caseCount: cases.length,
  cases,
};

const outputPath = path.resolve(
  process.cwd(),
  "test",
  "fixtures",
  "protocol_parity_cases.json",
);
fs.mkdirSync(path.dirname(outputPath), { recursive: true });
fs.writeFileSync(outputPath, JSON.stringify(output, null, 2));
console.log(`Wrote ${cases.length} protocol parity cases to ${outputPath}`);
