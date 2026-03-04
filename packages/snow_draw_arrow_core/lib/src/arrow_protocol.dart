import 'adapters.dart';
import 'arrow_binding_core.dart' as binding_core;
import 'arrow_binding_lifecycle.dart' as binding_lifecycle;
import 'arrow_elbow_core.dart';
import 'arrow_engine.dart';
import 'arrow_focus_core.dart';
import 'arrow_geom.dart';
import 'arrow_hit_test.dart';
import 'arrow_order_core.dart';
import 'arrow_relation_core.dart';
import 'arrow_render_core.dart';
import 'arrow_resize_core.dart';
import 'arrow_state_core.dart';
import 'arrow_types.dart';

const int arrowProtocolVersion = 16;

class ArrowCoreConstants {
  const ArrowCoreConstants({
    required this.baseBindingGap,
    required this.baseBindingGapElbow,
    required this.baseArrowMinLength,
    required this.focusPointSize,
    required this.basePadding,
  });

  final double baseBindingGap;
  final double baseBindingGapElbow;
  final double baseArrowMinLength;
  final double focusPointSize;
  final double basePadding;
}

const ArrowCoreConstants arrowCoreConstants = ArrowCoreConstants(
  baseBindingGap: binding_core.baseBindingGap,
  baseBindingGapElbow: binding_core.baseBindingGapElbow,
  baseArrowMinLength: binding_core.baseArrowMinLength,
  focusPointSize: FOCUS_POINT_SIZE,
  basePadding: basePadding,
);

class ArrowOperationManifestEntry {
  const ArrowOperationManifestEntry({
    required this.type,
    required this.responseType,
    required this.inputKind,
    required this.requiredInputFields,
    required this.usesShapeValidation,
  });

  final String type;
  final String responseType;
  final String inputKind;
  final List<String> requiredInputFields;
  final bool usesShapeValidation;
}

class ArrowProtocolManifest {
  const ArrowProtocolManifest({
    required this.version,
    required this.operations,
  });

  final int version;
  final List<ArrowOperationManifestEntry> operations;
}

class ArrowOperationEnvelopeValidation {
  const ArrowOperationEnvelopeValidation({
    required this.valid,
    required this.operationType,
    required this.violations,
  });

  final bool valid;
  final String operationType;
  final List<String> violations;
}

typedef ArrowOperationResponse = Map<String, dynamic>;

const Map<String, String> _operationResponseTypeMap = <String, String>{
  'compute-endpoint-drag': 'engine-result',
  'get-endpoint-binding-strategy': 'endpoint-binding-strategies',
  'compute-simple-binding-patch': 'engine-result',
  'finalize-endpoint-drag': 'engine-result',
  'compute-focus-point-drag': 'engine-result',
  'finalize-focus-point-drag': 'engine-result',
  'resolve-visible-focus-points': 'focus-points',
  'resolve-focus-point-hit': 'focus-point-edge',
  'resolve-focus-point-hit-with-offset': 'focus-point-hit',
  'recompute-after-bindable-change': 'engine-result',
  'recompute-bindings-for-changed-bindables': 'binding-lifecycle-sync',
  'refresh-endpoint-binding': 'engine-result',
  'prune-arrow-bindings': 'engine-result',
  'recompute-bindings-after-bindable-change': 'engine-result',
  'recompute-elbow': 'arrow-patch',
  'update-elbow-arrow': 'arrow-patch',
  'compute-elbow-resize-patch': 'arrow-patch',
  'move-fixed-segment': 'arrow-patch',
  'move-fixed-segment-to-point': 'fixed-segment-drag',
  'release-fixed-segment': 'arrow-patch',
  'apply-arrow-patch': 'arrow-state',
  'reorder-arrow-above-elements': 'arrow-layer-reorder',
  'reorder-arrow-above-hovered-bindable': 'arrow-layer-reorder-hovered',
  'reduce-arrow-engine-events-to-order': 'order-reduction',
  'get-resize-arrow-direction': 'arrow-resize-direction',
  'get-binding-gap': 'number',
  'max-binding-distance': 'number',
  'create-directional-link-arrow': 'directional-link-arrow',
  'offset-arrow-endpoints-for-binding-overlap': 'points',
  'get-arrowhead-size': 'number',
  'get-arrowhead-angle': 'number',
  'get-arrowhead-points': 'arrowhead-points',
  'get-arrowhead-render-primitives': 'arrowhead-render-primitives',
  'generate-elbow-arrow-path': 'string',
  'avoid-rectangular-corner': 'point',
  'snap-to-mid': 'optional-point',
  'get-snap-outline-mid-point': 'optional-point',
  'project-fixed-point-onto-diagonal': 'optional-point',
  'bind-point-to-outline': 'point',
  'calculate-fixed-point-for-binding': 'point',
  'calculate-fixed-point-for-elbow-binding': 'point',
  'update-bound-point': 'optional-point',
  'distance-to-bindable-outline': 'number',
  'is-point-in-bindable': 'boolean',
  'is-bindable-inside-other-bindable': 'boolean',
  'get-hovered-bindable': 'bindable',
  'get-bindables-over-point': 'bindables',
  'list-hovered-bindables': 'bindables',
  'pick-hovered-bindable-for-focus': 'bindable',
  'get-binding-side-mid-point': 'point',
  'get-global-fixed-points': 'point-pair',
  'get-arrow-local-fixed-points': 'point-pair',
  'get-global-fixed-point': 'point',
  'normalize-fixed-point': 'point',
  'is-fixed-point': 'boolean',
  'normalize-arrow-from-global-points': 'normalized-arrow',
  'normalize-bindable-state': 'bindable',
  'normalize-bindable-states': 'bindables',
  'normalize-engine-context': 'engine-context',
  'validate-elbow-points': 'boolean',
  'repair-binding-on-restore': 'binding',
  'repair-invalid-unbound-elbow-arrow-on-restore': 'optional-arrow-patch',
  'repair-self-bound-extreme-elbow-arrow-on-restore': 'optional-arrow-patch',
  'validate-arrow-invariant': 'validation-report',
  'validate-elbow-invariant': 'validation-report',
  'is-focus-point-visible': 'boolean',
  'is-point-near-bindable-for-focus': 'boolean',
  'get-heading-for-elbow-snap': 'heading',
  'bind-arrow-endpoint': 'engine-result',
  'unbind-arrow-endpoint': 'engine-result',
  'derive-bindable-patches-for-binding-change': 'bindable-patches',
  'derive-bindable-relation-patches-for-binding-change':
      'bindable-relation-patches',
  'reconcile-bindable-patches-for-arrow': 'bindable-patches',
  'resolve-bindable-relation-patches': 'resolved-bindable-relations',
  'remap-arrow-bindings-after-duplication': 'arrow-binding-state-patches',
  'remap-bindable-relations-after-duplication': 'bindable-relation-patches',
  'repair-arrow-bindings-after-bindable-deletion':
      'arrow-binding-state-patches',
  'repair-bindable-relations-after-arrow-deletion': 'bindable-relation-patches',
  'sync-bindings-after-duplication': 'binding-lifecycle-sync',
  'sync-bindings-after-bindable-prune': 'binding-lifecycle-sync',
  'sync-bindings-after-deletion': 'binding-lifecycle-sync',
  'apply-arrow-binding-state-patch': 'arrow-binding-state',
  'apply-arrow-binding-state-patches': 'arrow-binding-states',
  'reduce-bindable-patches-to-relation-patches': 'bindable-relation-patches',
  'apply-bindable-relation-patch': 'bindable-relation-state',
  'apply-bindable-relation-patches': 'bindable-relation-states',
  'merge-arrow-bound-relations': 'bound-relations',
  'are-bound-relations-equal': 'boolean',
  'apply-engine-result': 'applied-engine-result',
  'get-core-constants': 'core-constants',
  'get-default-engine-context': 'engine-context',
  'get-protocol-manifest': 'protocol-manifest',
};

const Set<String> _nullInputOperations = <String>{
  'get-core-constants',
  'get-default-engine-context',
  'get-protocol-manifest',
};

const List<String> _requiredFieldSpecs = <String>[
  'compute-endpoint-drag|arrow,draggedPoints,pointer,bindables,context',
  'get-endpoint-binding-strategy|arrow,draggedPoints,pointer,bindables,context',
  'compute-simple-binding-patch|arrow,draggedPoints,pointer,bindables,context',
  'finalize-endpoint-drag|arrow,draggedPoints,pointer,bindables,context',
  'compute-focus-point-drag|arrow,draggedEdge,pointer,bindables,context',
  'resolve-visible-focus-points|arrow,bindables,context',
  'resolve-focus-point-hit|arrow,pointer,bindables,context',
  'resolve-focus-point-hit-with-offset|arrow,pointer,bindables,context',
  'finalize-focus-point-drag|arrow,bindables',
  'recompute-after-bindable-change|arrow,bindables,context',
  'recompute-bindings-for-changed-bindables|arrows,bindables,relations,context',
  'refresh-endpoint-binding|arrow,edge,bindables,context',
  'prune-arrow-bindings|arrow,retainedBindableIds',
  'recompute-bindings-after-bindable-change|arrow,bindables,context',
  'recompute-elbow|arrow,bindables,context',
  'update-elbow-arrow|arrow,updates,bindables,context',
  'compute-elbow-resize-patch|arrow,flipX,flipY',
  'move-fixed-segment|arrow,segmentIndex,delta',
  'move-fixed-segment-to-point|arrow,segmentIndex,pointer',
  'release-fixed-segment|arrow,segmentIndex',
  'apply-arrow-patch|arrow,patch',
  'reorder-arrow-above-elements|orderedElementIds,arrowId,anchorElementIds',
  'reorder-arrow-above-hovered-bindable|orderedElementIds,arrowId',
  'reduce-arrow-engine-events-to-order|orderedElementIds,events',
  'get-resize-arrow-direction|transformHandleType,arrow',
  'get-binding-gap|bindable,elbowed',
  'max-binding-distance|zoom',
  'create-directional-link-arrow|startBounds,endBounds,direction',
  'offset-arrow-endpoints-for-binding-overlap|points',
  'get-arrowhead-size|arrowhead',
  'get-arrowhead-angle|arrowhead',
  'get-arrowhead-points|arrowPoints,strokeWidth,curveOps,position,arrowhead',
  'get-arrowhead-render-primitives|arrowPoints,strokeWidth,curveOps,position,arrowhead,strokeStyle',
  'generate-elbow-arrow-path|points,radius',
  'avoid-rectangular-corner|arrow,bindable,point',
  'snap-to-mid|bindable,point',
  'get-snap-outline-mid-point|point,bindable,zoom',
  'project-fixed-point-onto-diagonal|arrow,point,bindable,edge,bindables,zoom',
  'bind-point-to-outline|arrow,bindable,edge',
  'calculate-fixed-point-for-binding|point,bindable',
  'calculate-fixed-point-for-elbow-binding|arrow,bindable,edge',
  'update-bound-point|arrow,edge,binding,bindable,bindables',
  'distance-to-bindable-outline|point,bindable',
  'is-point-in-bindable|point,bindable',
  'is-bindable-inside-other-bindable|inner,outer',
  'get-hovered-bindable|point,bindables,tolerance',
  'get-bindables-over-point|point,bindables,tolerance',
  'list-hovered-bindables|point,bindables,tolerance',
  'pick-hovered-bindable-for-focus|point,arrow,bindables',
  'get-binding-side-mid-point|binding,bindable',
  'get-global-fixed-points|arrow,bindables',
  'get-arrow-local-fixed-points|arrow,bindables',
  'get-global-fixed-point|binding,bindable',
  'normalize-fixed-point|point',
  'is-fixed-point|point',
  'normalize-arrow-from-global-points|points,maxCoordinate',
  'normalize-bindable-state|bindable',
  'normalize-bindable-states|bindables',
  'normalize-engine-context|context',
  'validate-elbow-points|points',
  'repair-binding-on-restore|binding,bindables',
  'repair-invalid-unbound-elbow-arrow-on-restore|arrow,bindables,context',
  'repair-self-bound-extreme-elbow-arrow-on-restore|arrow,bindable',
  'validate-arrow-invariant|arrow',
  'validate-elbow-invariant|arrow',
  'is-focus-point-visible|arrow,edge,binding,bindable,context',
  'is-point-near-bindable-for-focus|point,bindable,zoom',
  'get-heading-for-elbow-snap|point,otherPoint,bindable',
  'bind-arrow-endpoint|arrow,edge,bindable',
  'unbind-arrow-endpoint|arrow,edge',
  'derive-bindable-patches-for-binding-change|arrowId,previous,next',
  'derive-bindable-relation-patches-for-binding-change|arrowId,previous,next,bindables',
  'reconcile-bindable-patches-for-arrow|arrow,bindables',
  'resolve-bindable-relation-patches|arrow,bindables',
  'remap-arrow-bindings-after-duplication|arrows,bindableIdMap',
  'remap-bindable-relations-after-duplication|bindables,arrowIdMap',
  'repair-arrow-bindings-after-bindable-deletion|arrows,deletedBindableIds',
  'repair-bindable-relations-after-arrow-deletion|bindables,deletedArrowIds',
  'sync-bindings-after-duplication|arrows,bindables,bindableIdMap,arrowIdMap',
  'sync-bindings-after-bindable-prune|arrows,bindables,retainedBindableIds',
  'sync-bindings-after-deletion|arrows,bindables,deletedBindableIds,deletedArrowIds',
  'apply-arrow-binding-state-patch|arrow,patch',
  'apply-arrow-binding-state-patches|arrows,patches',
  'reduce-bindable-patches-to-relation-patches|bindables,patches',
  'apply-bindable-relation-patch|bindable,patch',
  'apply-bindable-relation-patches|bindables,patches',
  'merge-arrow-bound-relations|relations,boundArrowIds',
  'are-bound-relations-equal|left,right',
  'apply-engine-result|arrow,bindables,result',
];

const List<String> _missingFieldValidationOrderSpecs = <String>[
  'compute-endpoint-drag|arrow,bindables,draggedPoints,pointer,context',
  'get-endpoint-binding-strategy|arrow,bindables,draggedPoints,pointer,context',
  'compute-simple-binding-patch|arrow,bindables,draggedPoints,pointer,context',
  'finalize-endpoint-drag|arrow,bindables,draggedPoints,pointer,context',
  'compute-focus-point-drag|arrow,bindables,draggedEdge,pointer,context',
  'resolve-focus-point-hit|arrow,bindables,pointer,context',
  'resolve-focus-point-hit-with-offset|arrow,bindables,pointer,context',
  'refresh-endpoint-binding|arrow,bindables,context,edge',
  'avoid-rectangular-corner|bindable,point,arrow',
  'get-snap-outline-mid-point|bindable,point,zoom',
  'project-fixed-point-onto-diagonal|arrow,bindable,bindables,point,edge,zoom',
  'update-bound-point|arrow,bindable,bindables,edge,binding',
  'pick-hovered-bindable-for-focus|bindables,point,arrow',
  'get-binding-side-mid-point|bindable,binding',
  'get-global-fixed-point|bindable,binding',
  'is-focus-point-visible|arrow,bindable,edge,binding,context',
  'bind-arrow-endpoint|arrow,bindable,edge',
  'derive-bindable-patches-for-binding-change|previous,next,arrowId',
  'derive-bindable-relation-patches-for-binding-change|previous,next,arrowId,bindables',
];

Map<String, List<String>> _buildRequiredFieldsMap() {
  final out = <String, List<String>>{};
  for (final spec in _requiredFieldSpecs) {
    final parts = spec.split('|');
    if (parts.isEmpty) {
      continue;
    }
    final operation = parts.first;
    final fieldList = parts.length < 2 || parts[1].trim().isEmpty
        ? const <String>[]
        : parts[1].split(',');
    out[operation] = fieldList;
  }
  return Map<String, List<String>>.unmodifiable(out);
}

final Map<String, List<String>> _operationRequiredFields =
    _buildRequiredFieldsMap();

Map<String, List<String>> _buildMissingFieldValidationOrderMap() {
  final out = <String, List<String>>{};
  for (final spec in _missingFieldValidationOrderSpecs) {
    final parts = spec.split('|');
    if (parts.isEmpty) {
      continue;
    }
    final operation = parts.first;
    final fieldList = parts.length < 2 || parts[1].trim().isEmpty
        ? const <String>[]
        : parts[1].split(',');
    out[operation] = fieldList;
  }
  return Map<String, List<String>>.unmodifiable(out);
}

final Map<String, List<String>> _operationMissingFieldValidationOrder =
    _buildMissingFieldValidationOrderMap();

const List<String> _optionalFieldSpecs = <String>[
  'compute-endpoint-drag|options',
  'get-endpoint-binding-strategy|options',
  'compute-simple-binding-patch|options',
  'finalize-endpoint-drag|options',
  'compute-focus-point-drag|options',
  'recompute-after-bindable-change|changedBindableIds,options',
  'recompute-bindings-for-changed-bindables|changedBindableIds,options',
  'prune-arrow-bindings|options',
  'recompute-bindings-after-bindable-change|changedBindableIds,options',
  'update-elbow-arrow|options',
  'compute-elbow-resize-patch|points',
  'create-directional-link-arrow|arrowheadSize',
  'offset-arrow-endpoints-for-binding-overlap|minimumLength',
  'snap-to-mid|tolerance,elbowed',
  'bind-point-to-outline|customIntersector',
  'update-bound-point|dragging',
  'list-hovered-bindables|stopAtOpaque',
  'reorder-arrow-above-hovered-bindable|hoveredBindableId,point,bindables,tolerance,anchorElementIdsByBindableId',
  'reduce-arrow-engine-events-to-order|anchorElementIdsByBindableId',
  'validate-elbow-points|tolerance',
  'repair-binding-on-restore|arrow,edge,existingBindables',
  'repair-self-bound-extreme-elbow-arrow-on-restore|maxCoordinate',
  'is-focus-point-visible|ignoreOverlap',
  'get-heading-for-elbow-snap|aabb,originPoint,zoom',
  'bind-arrow-endpoint|mode,focusPoint',
  'resolve-bindable-relation-patches|arrowPatch,bindablePatches',
  'remap-arrow-bindings-after-duplication|preserveUnmapped',
  'remap-bindable-relations-after-duplication|preserveUnmapped',
  'sync-bindings-after-duplication|preserveUnmapped,geometryBindables,context',
  'sync-bindings-after-bindable-prune|geometryBindables,context,options',
  'sync-bindings-after-deletion|geometryBindables,context',
  'apply-engine-result|orderedElementIds,anchorElementIdsByBindableId',
];

Map<String, Set<String>> _buildOptionalFieldsMap() {
  final out = <String, Set<String>>{};
  for (final spec in _optionalFieldSpecs) {
    final parts = spec.split('|');
    if (parts.isEmpty) {
      continue;
    }
    final operation = parts.first;
    final fieldSet = parts.length < 2 || parts[1].trim().isEmpty
        ? <String>{}
        : parts[1].split(',').toSet();
    out[operation] = fieldSet;
  }
  return Map<String, Set<String>>.unmodifiable(out);
}

final Map<String, Set<String>> _operationOptionalFields =
    _buildOptionalFieldsMap();

Map<String, Set<String>> _buildValidatedFieldsMap() {
  final out = <String, Set<String>>{};
  for (final operation in _operationResponseTypeMap.keys) {
    final fieldSet = <String>{};
    fieldSet.addAll(_operationRequiredFields[operation] ?? const <String>[]);
    fieldSet.addAll(_operationOptionalFields[operation] ?? const <String>{});
    out[operation] = fieldSet;
  }
  return Map<String, Set<String>>.unmodifiable(out);
}

final Map<String, Set<String>> _operationValidatedFields =
    _buildValidatedFieldsMap();

typedef _OperationInputShapeValidator =
    List<String> Function(Map<String, dynamic> input, String operationType);

const Set<String> _operationsWithoutShapeValidation = <String>{
  'is-fixed-point',
};

const Set<String> _operationsWithArrowBindingStateArrowField = <String>{
  'finalize-focus-point-drag',
  'reconcile-bindable-patches-for-arrow',
  'resolve-bindable-relation-patches',
  'apply-arrow-binding-state-patch',
};

const Set<String> _operationsWithArrowBindingStateArrowsField = <String>{
  'remap-arrow-bindings-after-duplication',
  'repair-arrow-bindings-after-bindable-deletion',
  'apply-arrow-binding-state-patches',
};

const Set<String> _operationsWithArrowElbowOnlyField = <String>{
  'avoid-rectangular-corner',
  'pick-hovered-bindable-for-focus',
};

const Set<String> _operationsWithArrowPointsOnlyField = <String>{
  'get-resize-arrow-direction',
};

const Set<String> _operationsWithRelationBindablesField = <String>{
  'finalize-focus-point-drag',
  'derive-bindable-relation-patches-for-binding-change',
  'reconcile-bindable-patches-for-arrow',
  'resolve-bindable-relation-patches',
  'remap-bindable-relations-after-duplication',
  'repair-bindable-relations-after-arrow-deletion',
  'sync-bindings-after-duplication',
  'sync-bindings-after-bindable-prune',
  'sync-bindings-after-deletion',
  'reduce-bindable-patches-to-relation-patches',
  'apply-bindable-relation-patches',
  'apply-engine-result',
};

const Set<String> _operationsWithRelationBindableField = <String>{
  'apply-bindable-relation-patch',
};

const Set<String> _missingFieldShapeValidationSkips = <String>{
  'get-resize-arrow-direction|transformHandleType',
  'are-bound-relations-equal|left',
  'are-bound-relations-equal|right',
};

const Set<String> _operationsAllowNullBindingField = <String>{
  'update-bound-point',
  'repair-binding-on-restore',
};

const Set<String> _operationsRequireBindingMode = <String>{
  'repair-binding-on-restore',
};

const Set<String> _operationsAllowNullBindableField = <String>{
  'get-heading-for-elbow-snap',
};

const Set<String> _operationsContextRequireBindModeAndMaxCoordinate = <String>{
  'compute-endpoint-drag',
  'get-endpoint-binding-strategy',
  'compute-simple-binding-patch',
  'finalize-endpoint-drag',
  'compute-focus-point-drag',
  'recompute-after-bindable-change',
  'recompute-bindings-for-changed-bindables',
  'refresh-endpoint-binding',
  'recompute-bindings-after-bindable-change',
  'recompute-elbow',
  'update-elbow-arrow',
  'repair-invalid-unbound-elbow-arrow-on-restore',
  'sync-bindings-after-duplication',
  'sync-bindings-after-bindable-prune',
  'sync-bindings-after-deletion',
};

const Set<String> _arrowheadValues = <String>{
  'arrow',
  'bar',
  'dot',
  'circle',
  'circle_outline',
  'triangle',
  'triangle_outline',
  'diamond',
  'diamond_outline',
  'crowfoot_one',
  'crowfoot_many',
  'crowfoot_one_or_many',
};

const Set<String> _bindableShapeValues = <String>{
  'rectangle',
  'ellipse',
  'diamond',
  'rect',
  'circle',
  'rhombus',
};

bool _isFiniteNumber(Object? value) => value is num && value.isFinite;

bool _isPositiveInteger(Object? value) =>
    value is num && value.isFinite && value > 0 && value.toInt() == value;

bool _isPointTuple(Object? value) =>
    value is List &&
    value.length == 2 &&
    _isFiniteNumber(value[0]) &&
    _isFiniteNumber(value[1]);

bool _isPointTupleArray(Object? value) =>
    value is List && value.every(_isPointTuple);

bool _isBoundsTuple(Object? value) =>
    value is List &&
    value.length == 4 &&
    _isFiniteNumber(value[0]) &&
    _isFiniteNumber(value[1]) &&
    _isFiniteNumber(value[2]) &&
    _isFiniteNumber(value[3]);

bool _isStringArray(Object? value) =>
    value is List && value.every((entry) => entry is String);

bool _isListWhere(Object? value, bool Function(Object? entry) predicate) =>
    value is List && value.every(predicate);

bool _isBindableStateArray(Object? value) =>
    _isListWhere(value, (entry) => _asBindableState(entry) != null);

bool _isBindableRelationStateArray(Object? value) =>
    _isListWhere(value, (entry) => _asBindableRelationState(entry) != null);

bool _isArrowStateArray(Object? value) =>
    _isListWhere(value, (entry) => _asArrowState(entry) != null);

bool _isArrowBindingStateArray(Object? value) =>
    _isListWhere(value, (entry) => _asArrowBindingState(entry) != null);

bool _isBindablePatchArray(Object? value) =>
    _isListWhere(value, (entry) => _asBindablePatch(entry) != null);

bool _isBindableRelationPatchArray(Object? value) =>
    _isListWhere(value, (entry) => _asBindableRelationPatch(entry) != null);

bool _isArrowEngineEventArray(Object? value) =>
    _isListWhere(value, (entry) => _asArrowEngineEvent(entry) != null);

bool _isCurvePathOpArray(Object? value) =>
    _isListWhere(value, (entry) => _asCurvePathOp(entry) != null);

bool _isDirectionalLinkBoundsShape(Object? value) =>
    value is Map &&
    _isFiniteNumber(value['x']) &&
    _isFiniteNumber(value['y']) &&
    _isFiniteNumber(value['width']) &&
    _isFiniteNumber(value['height']);

bool _isArrowEndpointEdgeValue(Object? value) =>
    value == arrowEndpointStart || value == arrowEndpointEnd;

bool _isArrowEndpointSelectorValue(Object? value) =>
    value == arrowEndpointStart ||
    value == arrowEndpointEnd ||
    value == 'startBinding' ||
    value == 'endBinding';

bool _isBindModeValue(Object? value) =>
    value == bindModeInside || value == bindModeOrbit || value == bindModeSkip;

bool _isDirectionValue(Object? value) =>
    value == 'up' || value == 'right' || value == 'down' || value == 'left';

bool _isArrowEndpointPositionValue(Object? value) =>
    value == arrowEndpointStart || value == arrowEndpointEnd;

bool _isArrowheadValue(Object? value) =>
    value is String && _arrowheadValues.contains(value);

bool _isBindableShapeValue(Object? value) =>
    value is String && _bindableShapeValues.contains(value);

bool _isBindableRoundnessTypeValue(Object? value) =>
    value == 1 ||
    value == 2 ||
    value == 3 ||
    value == 'legacy' ||
    value == 'proportional' ||
    value == 'adaptive';

bool _isResizeHandleDirectionValue(Object? value) =>
    value == 'n' ||
    value == 's' ||
    value == 'e' ||
    value == 'w' ||
    value == 'nw' ||
    value == 'ne' ||
    value == 'sw' ||
    value == 'se' ||
    value == 'rotation' ||
    value == false ||
    value == null;

List<String> _validateStrictFixedPointBinding(
  Object? value, {
  required String path,
  required bool allowNull,
  required bool requireMode,
}) {
  if (value is FixedPointBinding) {
    return _isBindModeValue(value.mode)
        ? const <String>[]
        : <String>['$path.mode must be "inside", "orbit", or "skip"'];
  }
  if (value == null) {
    return allowNull ? const <String>[] : <String>['$path must be an object'];
  }
  if (value is! Map) {
    return <String>['$path must be an object${allowNull ? ' or null' : ''}'];
  }

  final violations = <String>[];
  if (value['elementId'] is! String) {
    violations.add('$path.elementId must be a string');
  }
  if (!_isPointTuple(value['fixedPoint'])) {
    violations.add('$path.fixedPoint must be a [number, number] tuple');
  }
  if (requireMode) {
    if (!_isBindModeValue(value['mode'])) {
      violations.add('$path.mode must be "inside", "orbit", or "skip"');
    }
  } else if (value.containsKey('mode') && !_isBindModeValue(value['mode'])) {
    violations.add('$path.mode must be "inside", "orbit", or "skip"');
  }
  return violations;
}

List<String> _validateStrictFixedSegments(
  Object? value, {
  required String path,
  required bool allowNull,
}) {
  if (value is List<FixedSegment>) {
    final violations = <String>[];
    for (var index = 0; index < value.length; index += 1) {
      final segment = value[index];
      final indexValue = segment.index;
      final isPositiveInteger =
          indexValue > 0 && indexValue.toDouble() == indexValue;
      if (!isPositiveInteger) {
        violations.add('$path[$index].index must be a positive integer');
      }
    }
    return violations;
  }
  if (value == null) {
    return allowNull ? const <String>[] : <String>['$path must be an array'];
  }
  if (value is! List) {
    return <String>['$path must be an array of objects or null'];
  }

  final violations = <String>[];
  for (var index = 0; index < value.length; index += 1) {
    final segment = value[index];
    if (segment is! Map) {
      violations.add('$path[$index] must be an object');
      continue;
    }
    final indexValue = segment['index'];
    final isPositiveInteger =
        indexValue is num &&
        indexValue.isFinite &&
        indexValue > 0 &&
        indexValue.toInt() == indexValue;
    if (!isPositiveInteger) {
      violations.add('$path[$index].index must be a positive integer');
    }
    if (!_isPointTuple(segment['start'])) {
      violations.add('$path[$index].start must be a [number, number] tuple');
    }
    if (!_isPointTuple(segment['end'])) {
      violations.add('$path[$index].end must be a [number, number] tuple');
    }
  }
  return violations;
}

List<String> _validateStrictBindableState(
  Object? value, {
  required String path,
}) {
  if (value is BindableState) {
    return const <String>[];
  }
  if (value is! Map) {
    return <String>['$path must be an object'];
  }
  final violations = <String>[];
  if (value['id'] is! String) {
    violations.add('$path.id must be a string');
  }
  if (!_isBindableShapeValue(value['shape'])) {
    violations.add(
      '$path.shape must be one of "rectangle", "ellipse", "diamond", "rect", "circle", or "rhombus"',
    );
  }
  if (!_isFiniteNumber(value['x'])) {
    violations.add('$path.x must be a finite number');
  }
  if (!_isFiniteNumber(value['y'])) {
    violations.add('$path.y must be a finite number');
  }
  if (!_isFiniteNumber(value['width'])) {
    violations.add('$path.width must be a finite number');
  }
  if (!_isFiniteNumber(value['height'])) {
    violations.add('$path.height must be a finite number');
  }
  if (!_isFiniteNumber(value['angle'])) {
    violations.add('$path.angle must be a finite number');
  }
  if (!_isFiniteNumber(value['strokeWidth'])) {
    violations.add('$path.strokeWidth must be a finite number');
  }
  final roundness = value['roundness'];
  if (roundness != null) {
    if (roundness is! Map) {
      violations.add('$path.roundness must be an object or null');
    } else {
      if (!_isBindableRoundnessTypeValue(roundness['type'])) {
        violations.add(
          '$path.roundness.type must be one of 1, 2, 3, "legacy", "proportional", or "adaptive"',
        );
      }
      if (roundness.containsKey('value') &&
          roundness['value'] != null &&
          !_isFiniteNumber(roundness['value'])) {
        violations.add(
          '$path.roundness.value must be a finite number when provided',
        );
      }
    }
  }
  if (value.containsKey('zIndex') && !_isFiniteNumber(value['zIndex'])) {
    violations.add('$path.zIndex must be a finite number when provided');
  }
  if (value.containsKey('backgroundOpaque') &&
      value['backgroundOpaque'] is! bool) {
    violations.add('$path.backgroundOpaque must be a boolean when provided');
  }
  if (value.containsKey('bindingEnabled') && value['bindingEnabled'] is! bool) {
    violations.add('$path.bindingEnabled must be a boolean when provided');
  }
  if (value.containsKey('interiorHitEnabled') &&
      value['interiorHitEnabled'] is! bool) {
    violations.add('$path.interiorHitEnabled must be a boolean when provided');
  }
  if (value.containsKey('visibilityBounds') &&
      value['visibilityBounds'] != null &&
      !_isBoundsTuple(value['visibilityBounds'])) {
    violations.add(
      '$path.visibilityBounds must be a [number, number, number, number] tuple when provided',
    );
  }
  return violations;
}

List<String> _validateStrictBindableStateArray(
  Object? value, {
  required String path,
}) {
  if (value is! List) {
    return <String>['$path must be an array of objects'];
  }
  final violations = <String>[];
  for (var index = 0; index < value.length; index += 1) {
    violations.addAll(
      _validateStrictBindableState(value[index], path: '$path[$index]'),
    );
  }
  return violations;
}

List<String> _validateStrictArrowState(Object? value, {required String path}) {
  if (value is ArrowState) {
    return const <String>[];
  }
  if (value is! Map) {
    return <String>['$path must be an object'];
  }
  final violations = <String>[];
  if (value['id'] is! String) {
    violations.add('$path.id must be a string');
  }
  if (!_isFiniteNumber(value['x'])) {
    violations.add('$path.x must be a finite number');
  }
  if (!_isFiniteNumber(value['y'])) {
    violations.add('$path.y must be a finite number');
  }
  if (!_isFiniteNumber(value['width'])) {
    violations.add('$path.width must be a finite number');
  }
  if (!_isFiniteNumber(value['height'])) {
    violations.add('$path.height must be a finite number');
  }
  if (!_isPointTupleArray(value['points'])) {
    violations.add('$path.points must be an array of points');
  }
  if (!value.containsKey('startArrowhead')) {
    violations.add('$path.startArrowhead is required');
  }
  if (!value.containsKey('endArrowhead')) {
    violations.add('$path.endArrowhead is required');
  }
  if (!value.containsKey('fixedSegments')) {
    violations.add('$path.fixedSegments is required');
  }
  if (!value.containsKey('startIsSpecial')) {
    violations.add('$path.startIsSpecial is required');
  }
  if (!value.containsKey('endIsSpecial')) {
    violations.add('$path.endIsSpecial is required');
  }
  if (!value.containsKey('startBinding')) {
    violations.add('$path.startBinding must be an object or null');
  } else {
    violations.addAll(
      _validateStrictFixedPointBinding(
        value['startBinding'],
        path: '$path.startBinding',
        allowNull: true,
        requireMode: true,
      ),
    );
  }
  if (!value.containsKey('endBinding')) {
    violations.add('$path.endBinding must be an object or null');
  } else {
    violations.addAll(
      _validateStrictFixedPointBinding(
        value['endBinding'],
        path: '$path.endBinding',
        allowNull: true,
        requireMode: true,
      ),
    );
  }
  final startArrowhead = value['startArrowhead'];
  if (startArrowhead != null && !_isArrowheadValue(startArrowhead)) {
    violations.add('$path.startArrowhead must be a valid arrowhead or null');
  }
  final endArrowhead = value['endArrowhead'];
  if (endArrowhead != null && !_isArrowheadValue(endArrowhead)) {
    violations.add('$path.endArrowhead must be a valid arrowhead or null');
  }
  if (value['elbowed'] is! bool) {
    violations.add('$path.elbowed must be a boolean');
  }
  violations.addAll(
    _validateStrictFixedSegments(
      value['fixedSegments'],
      path: '$path.fixedSegments',
      allowNull: true,
    ),
  );
  if (value.containsKey('startIsSpecial') &&
      value['startIsSpecial'] != null &&
      value['startIsSpecial'] is! bool) {
    violations.add('$path.startIsSpecial must be a boolean or null');
  }
  if (value.containsKey('endIsSpecial') &&
      value['endIsSpecial'] != null &&
      value['endIsSpecial'] is! bool) {
    violations.add('$path.endIsSpecial must be a boolean or null');
  }
  return violations;
}

List<String> _validateStrictArrowStateArray(
  Object? value, {
  required String path,
}) {
  if (value is! List) {
    return <String>['$path must be an array of objects'];
  }
  final violations = <String>[];
  for (var index = 0; index < value.length; index += 1) {
    violations.addAll(
      _validateStrictArrowState(value[index], path: '$path[$index]'),
    );
  }
  return violations;
}

List<String> _validateStrictArrowBindingState(
  Object? value, {
  required String path,
}) {
  if (value is ArrowBindingState) {
    return const <String>[];
  }
  if (value is! Map) {
    return <String>['$path must be an object'];
  }

  final violations = <String>[];
  if (value['id'] is! String) {
    violations.add('$path.id must be a string');
  }
  if (!value.containsKey('startBinding')) {
    violations.add('$path.startBinding is required');
  }
  if (!value.containsKey('endBinding')) {
    violations.add('$path.endBinding is required');
  }
  violations.addAll(
    _validateStrictFixedPointBinding(
      value['startBinding'],
      path: '$path.startBinding',
      allowNull: true,
      requireMode: true,
    ),
  );
  violations.addAll(
    _validateStrictFixedPointBinding(
      value['endBinding'],
      path: '$path.endBinding',
      allowNull: true,
      requireMode: true,
    ),
  );
  return violations;
}

List<String> _validateStrictArrowBindingStateArray(
  Object? value, {
  required String path,
}) {
  if (value is! List) {
    return <String>['$path must be an array of objects'];
  }
  final violations = <String>[];
  for (var index = 0; index < value.length; index += 1) {
    violations.addAll(
      _validateStrictArrowBindingState(value[index], path: '$path[$index]'),
    );
  }
  return violations;
}

List<String> _validateStrictBindableRelationState(
  Object? value, {
  required String path,
}) {
  if (value is BindableRelationState) {
    return const <String>[];
  }
  if (value is! Map) {
    return <String>['$path must be an object'];
  }

  final violations = <String>[];
  if (value['id'] is! String) {
    violations.add('$path.id must be a string');
  }
  if (!_isStringArray(value['boundArrowIds'])) {
    violations.add('$path.boundArrowIds must be an array of strings');
  }
  return violations;
}

List<String> _validateStrictBindableRelationStateArray(
  Object? value, {
  required String path,
}) {
  if (value is! List) {
    return <String>['$path must be an array of objects'];
  }
  final violations = <String>[];
  for (var index = 0; index < value.length; index += 1) {
    violations.addAll(
      _validateStrictBindableRelationState(value[index], path: '$path[$index]'),
    );
  }
  return violations;
}

List<String> _validateStrictBindablePatch(
  Object? value, {
  required String path,
}) {
  if (value is BindablePatch) {
    return const <String>[];
  }
  if (value is! Map) {
    return <String>['$path must be an object'];
  }
  final violations = <String>[];
  if (value['id'] is! String) {
    violations.add('$path.id must be a string');
  }
  if (value.containsKey('addBoundArrowId') &&
      value['addBoundArrowId'] is! String) {
    violations.add('$path.addBoundArrowId must be a string when provided');
  }
  if (value.containsKey('removeBoundArrowId') &&
      value['removeBoundArrowId'] is! String) {
    violations.add('$path.removeBoundArrowId must be a string when provided');
  }
  return violations;
}

List<String> _validateStrictBindablePatchArray(
  Object? value, {
  required String path,
}) {
  if (value is! List) {
    return <String>['$path must be an array of objects'];
  }
  final violations = <String>[];
  for (var index = 0; index < value.length; index += 1) {
    violations.addAll(
      _validateStrictBindablePatch(value[index], path: '$path[$index]'),
    );
  }
  return violations;
}

List<String> _validateStrictBindableRelationPatch(
  Object? value, {
  required String path,
}) {
  if (value is BindableRelationPatch) {
    return const <String>[];
  }
  if (value is! Map) {
    return <String>['$path must be an object'];
  }
  final violations = <String>[];
  if (value['id'] is! String) {
    violations.add('$path.id must be a string');
  }
  if (!_isStringArray(value['boundArrowIds'])) {
    violations.add('$path.boundArrowIds must be an array of strings');
  }
  return violations;
}

List<String> _validateStrictBindableRelationPatchArray(
  Object? value, {
  required String path,
}) {
  if (value is! List) {
    return <String>['$path must be an array of objects'];
  }
  final violations = <String>[];
  for (var index = 0; index < value.length; index += 1) {
    violations.addAll(
      _validateStrictBindableRelationPatch(value[index], path: '$path[$index]'),
    );
  }
  return violations;
}

List<String> _validateStrictCurvePathOp(Object? value, {required String path}) {
  if (value is CurvePathOp) {
    return value.data.every(_isFiniteNumber)
        ? const <String>[]
        : <String>['$path.data must be an array of finite numbers'];
  }
  if (value is! Map) {
    return <String>['$path must be an object'];
  }
  final violations = <String>[];
  if (value['op'] is! String) {
    violations.add('$path.op must be a string');
  }
  if (value['data'] is! List ||
      !(value['data'] as List).every((entry) => _isFiniteNumber(entry))) {
    violations.add('$path.data must be an array of finite numbers');
  }
  return violations;
}

List<String> _validateStrictCurvePathOpArray(
  Object? value, {
  required String path,
}) {
  if (value is! List) {
    return <String>['$path must be an array of objects'];
  }
  final violations = <String>[];
  for (var index = 0; index < value.length; index += 1) {
    violations.addAll(
      _validateStrictCurvePathOp(value[index], path: '$path[$index]'),
    );
  }
  return violations;
}

List<String> _validateArrowPatchShape(Object? value, {required String path}) {
  if (value is! Map) {
    return <String>['$path must be an object'];
  }
  final violations = <String>[];
  if (value.containsKey('x') && !_isFiniteNumber(value['x'])) {
    violations.add('$path.x must be a finite number when provided');
  }
  if (value.containsKey('y') && !_isFiniteNumber(value['y'])) {
    violations.add('$path.y must be a finite number when provided');
  }
  if (value.containsKey('width') && !_isFiniteNumber(value['width'])) {
    violations.add('$path.width must be a finite number when provided');
  }
  if (value.containsKey('height') && !_isFiniteNumber(value['height'])) {
    violations.add('$path.height must be a finite number when provided');
  }
  if (value.containsKey('points') && !_isPointTupleArray(value['points'])) {
    violations.add('$path.points must be an array of points when provided');
  }
  if (value.containsKey('startBinding')) {
    violations.addAll(
      _validateStrictFixedPointBinding(
        value['startBinding'],
        path: '$path.startBinding',
        allowNull: true,
        requireMode: true,
      ),
    );
  }
  if (value.containsKey('endBinding')) {
    violations.addAll(
      _validateStrictFixedPointBinding(
        value['endBinding'],
        path: '$path.endBinding',
        allowNull: true,
        requireMode: true,
      ),
    );
  }
  if (value.containsKey('fixedSegments')) {
    violations.addAll(
      _validateStrictFixedSegments(
        value['fixedSegments'],
        path: '$path.fixedSegments',
        allowNull: true,
      ),
    );
  }
  if (value.containsKey('startIsSpecial') &&
      value['startIsSpecial'] != null &&
      value['startIsSpecial'] is! bool) {
    violations.add('$path.startIsSpecial must be a boolean or null');
  }
  if (value.containsKey('endIsSpecial') &&
      value['endIsSpecial'] != null &&
      value['endIsSpecial'] is! bool) {
    violations.add('$path.endIsSpecial must be a boolean or null');
  }
  return violations;
}

List<String> _validateArrowEngineEventsShape(
  Object? value, {
  required String path,
}) {
  if (value is! List) {
    return <String>['$path must be an array'];
  }

  final violations = <String>[];
  for (var index = 0; index < value.length; index += 1) {
    final entry = value[index];
    final entryPath = '$path[$index]';
    if (entry is ReorderArrowEvent) {
      if (entry.arrowId.isEmpty) {
        violations.add('$entryPath.arrowId must be a string');
      }
      if (entry.bindableId.isEmpty) {
        violations.add('$entryPath.bindableId must be a string');
      }
      continue;
    }
    if (entry is BindingBrokenEvent) {
      if (entry.arrowId.isEmpty) {
        violations.add('$entryPath.arrowId must be a string');
      }
      if (!_isArrowEndpointEdgeValue(entry.edge)) {
        violations.add('$entryPath.edge must be "start" or "end"');
      }
      continue;
    }
    if (entry is! Map) {
      violations.add('$entryPath must be an object');
      continue;
    }

    final type = entry['type'];
    if (type == 'reorder-arrow') {
      if (entry['arrowId'] is! String) {
        violations.add('$entryPath.arrowId must be a string');
      }
      if (entry['bindableId'] is! String) {
        violations.add('$entryPath.bindableId must be a string');
      }
      continue;
    }
    if (type == 'binding-broken') {
      if (entry['arrowId'] is! String) {
        violations.add('$entryPath.arrowId must be a string');
      }
      if (!_isArrowEndpointEdgeValue(entry['edge'])) {
        violations.add('$entryPath.edge must be "start" or "end"');
      }
      continue;
    }
    violations.add(
      '$entryPath.type must be "reorder-arrow" or "binding-broken"',
    );
  }
  return violations;
}

List<String> _validateSuggestedBindingShape(
  Object? value, {
  required String path,
}) {
  if (value == null) {
    return const <String>[];
  }
  if (value is SuggestedBinding) {
    final violations = <String>[];
    if (value.bindableId != null && value.bindableId is! String) {
      violations.add('$path.bindableId must be a string when provided');
    }
    violations.addAll(
      _validateStrictBindableState(value.element, path: '$path.element'),
    );
    if (value.midPoint != null && !_isPointTuple(value.midPoint)) {
      violations.add(
        '$path.midPoint must be a [number, number] tuple when provided',
      );
    }
    return violations;
  }
  if (value is! Map) {
    return <String>['$path must be an object or null'];
  }

  final violations = <String>[];
  if (value.containsKey('bindableId') && value['bindableId'] is! String) {
    violations.add('$path.bindableId must be a string when provided');
  }
  if (!value.containsKey('element')) {
    violations.add('$path.element is required');
  } else {
    violations.addAll(
      _validateStrictBindableState(value['element'], path: '$path.element'),
    );
  }
  if (value.containsKey('midPoint') &&
      value['midPoint'] != null &&
      !_isPointTuple(value['midPoint'])) {
    violations.add(
      '$path.midPoint must be a [number, number] tuple when provided',
    );
  }
  return violations;
}

List<String> _validateEngineResultShape(Object? value, {required String path}) {
  if (value is EngineResult) {
    final violations = <String>[];
    violations.addAll(
      _validateArrowPatchShape(value.arrowPatch, path: '$path.arrowPatch'),
    );
    violations.addAll(
      _validateStrictBindablePatchArray(
        value.bindablePatches,
        path: '$path.bindablePatches',
      ),
    );
    violations.addAll(
      _validateSuggestedBindingShape(
        value.suggestedBinding,
        path: '$path.suggestedBinding',
      ),
    );
    violations.addAll(
      _validateArrowEngineEventsShape(value.events, path: '$path.events'),
    );
    return violations;
  }
  if (value is! Map) {
    return <String>['$path must be an object'];
  }
  final violations = <String>[];
  violations.addAll(
    _validateArrowPatchShape(value['arrowPatch'], path: '$path.arrowPatch'),
  );
  violations.addAll(
    _validateStrictBindablePatchArray(
      value['bindablePatches'],
      path: '$path.bindablePatches',
    ),
  );
  violations.addAll(
    _validateSuggestedBindingShape(
      value['suggestedBinding'],
      path: '$path.suggestedBinding',
    ),
  );
  violations.addAll(
    _validateArrowEngineEventsShape(value['events'], path: '$path.events'),
  );
  return violations;
}

List<String> _validateUpdateElbowPatchShape(
  Object? value, {
  required String path,
}) {
  if (value is! Map) {
    return <String>['$path must be an object'];
  }
  final violations = <String>[];
  if (value.containsKey('points') && !_isPointTupleArray(value['points'])) {
    violations.add('$path.points must be an array of points when provided');
  }
  if (value.containsKey('fixedSegments')) {
    violations.addAll(
      _validateStrictFixedSegments(
        value['fixedSegments'],
        path: '$path.fixedSegments',
        allowNull: true,
      ),
    );
  }
  if (value.containsKey('startBinding')) {
    violations.addAll(
      _validateStrictFixedPointBinding(
        value['startBinding'],
        path: '$path.startBinding',
        allowNull: true,
        requireMode: true,
      ),
    );
  }
  if (value.containsKey('endBinding')) {
    violations.addAll(
      _validateStrictFixedPointBinding(
        value['endBinding'],
        path: '$path.endBinding',
        allowNull: true,
        requireMode: true,
      ),
    );
  }
  return violations;
}

List<String> _validateOptionalBooleanFields(
  Map value, {
  required String path,
  required List<String> fields,
}) {
  final violations = <String>[];
  for (final field in fields) {
    if (value.containsKey(field) && value[field] is! bool) {
      violations.add('$path.$field must be a boolean');
    }
  }
  return violations;
}

List<String> _validateOptionsShape(
  String operationType,
  Object? value, {
  required String path,
}) {
  const endpointDragOps = <String>{
    'compute-endpoint-drag',
    'get-endpoint-binding-strategy',
    'compute-simple-binding-patch',
    'finalize-endpoint-drag',
  };
  const recomputeOps = <String>{
    'recompute-after-bindable-change',
    'recompute-bindings-for-changed-bindables',
    'recompute-bindings-after-bindable-change',
  };
  const pruneOps = <String>{
    'prune-arrow-bindings',
    'sync-bindings-after-bindable-prune',
  };

  if (endpointDragOps.contains(operationType)) {
    if (value is! Map) {
      return <String>['$path must be an object'];
    }
    final violations = <String>[];
    violations.addAll(
      _validateOptionalBooleanFields(
        value,
        path: path,
        fields: const <String>[
          'newArrow',
          'altKey',
          'angleLocked',
          'finalize',
          'complexBindings',
          'initialBinding',
          'preserveOppositeInsideBinding',
        ],
      ),
    );
    if (value.containsKey('oppositeOrbitFocusPoint') &&
        !_isPointTuple(value['oppositeOrbitFocusPoint'])) {
      violations.add(
        '$path.oppositeOrbitFocusPoint must be a [number, number] tuple',
      );
    }
    return violations;
  }

  if (operationType == 'compute-focus-point-drag') {
    if (value is! Map) {
      return <String>['$path must be an object'];
    }
    final violations = <String>[];
    violations.addAll(
      _validateOptionalBooleanFields(
        value,
        path: path,
        fields: const <String>['switchToInsideBinding'],
      ),
    );
    if (value.containsKey('gridSize') &&
        value['gridSize'] != null &&
        !_isFiniteNumber(value['gridSize'])) {
      violations.add('$path.gridSize must be a finite number when provided');
    }
    return violations;
  }

  if (operationType == 'update-elbow-arrow') {
    if (value is! Map) {
      return <String>['$path must be an object'];
    }
    return _validateOptionalBooleanFields(
      value,
      path: path,
      fields: const <String>['isDragging', 'validateInvariants'],
    );
  }

  if (pruneOps.contains(operationType)) {
    if (value is! Map) {
      return <String>['$path must be an object'];
    }
    if (operationType == 'sync-bindings-after-bindable-prune') {
      return _validateOptionalBooleanFields(
        value,
        path: path,
        fields: const <String>['pruneStart', 'pruneEnd', 'recomputeElbows'],
      );
    }
    return _validateOptionalBooleanFields(
      value,
      path: path,
      fields: const <String>['pruneStart', 'pruneEnd'],
    );
  }

  if (recomputeOps.contains(operationType)) {
    if (value is! Map) {
      return <String>['$path must be an object'];
    }
    if (value.containsKey('moveMidPointsWithElement') &&
        value['moveMidPointsWithElement'] is! bool) {
      return <String>[
        '$path.moveMidPointsWithElement must be a boolean when provided',
      ];
    }
    return const <String>[];
  }

  return const <String>[];
}

List<String> _validateIdMapShape(Object? value, {required String path}) {
  if (value is Map) {
    final violations = <String>[];
    for (final entry in value.entries) {
      if (entry.key is! String) {
        violations.add('$path map keys must be strings');
      } else if ((entry.key as String).trim().isEmpty) {
        violations.add('$path keys must be non-empty strings');
      }
      if (entry.value is! String) {
        violations.add('$path map values must be strings');
      }
    }
    return violations;
  }
  if (value is List) {
    final violations = <String>[];
    for (var index = 0; index < value.length; index += 1) {
      final entry = value[index];
      final entryPath = '$path[$index]';
      if (entry is! Map) {
        violations.add('$entryPath must be an object');
        continue;
      }
      if (entry['from'] is! String) {
        violations.add('$entryPath.from must be a string');
      }
      if (entry['to'] is! String) {
        violations.add('$entryPath.to must be a string');
      }
    }
    return violations;
  }
  return <String>[
    '$path must be a readonly map, an array of { from, to } entries, or an object record',
  ];
}

List<String> _validateAnchorElementIdsLookupShape(
  Object? value, {
  required String path,
}) {
  if (value is! Map) {
    return <String>['$path must be an object map'];
  }
  final violations = <String>[];
  for (final entry in value.entries) {
    if (entry.key is! String || (entry.key as String).trim().isEmpty) {
      violations.add('$path keys must be non-empty strings');
      continue;
    }
    if (!_isStringArray(entry.value)) {
      violations.add('$path.${entry.key} must be an array of strings');
    }
  }
  return violations;
}

List<String> _validateFixedPointBindingShape(
  Object? value, {
  required String path,
  required bool allowNull,
  required bool requireMode,
}) {
  if (value == null) {
    return allowNull ? const <String>[] : <String>['$path must be an object'];
  }
  if (value is! Map) {
    return <String>['$path must be an object${allowNull ? ' or null' : ''}'];
  }
  final violations = <String>[];
  if (value['elementId'] is! String) {
    violations.add('$path.elementId must be a string');
  }
  if (!_isPointTuple(value['fixedPoint'])) {
    violations.add('$path.fixedPoint must be a [number, number] tuple');
  }
  if (requireMode) {
    if (!_isBindModeValue(value['mode'])) {
      violations.add('$path.mode must be "inside", "orbit", or "skip"');
    }
  } else if (value.containsKey('mode') && !_isBindModeValue(value['mode'])) {
    violations.add('$path.mode must be "inside", "orbit", or "skip"');
  }
  return violations;
}

List<String> _validateArrowBindingStatePatchShape(
  Object? value, {
  required String path,
}) {
  if (value is! Map) {
    return <String>['$path must be an object'];
  }
  final violations = <String>[];
  if (value['id'] is! String) {
    violations.add('$path.id must be a string');
  }
  if (value.containsKey('startBinding')) {
    violations.addAll(
      _validateFixedPointBindingShape(
        value['startBinding'],
        path: '$path.startBinding',
        allowNull: true,
        requireMode: true,
      ),
    );
  }
  if (value.containsKey('endBinding')) {
    violations.addAll(
      _validateFixedPointBindingShape(
        value['endBinding'],
        path: '$path.endBinding',
        allowNull: true,
        requireMode: true,
      ),
    );
  }
  return violations;
}

List<String> _validateArrowBindingStatePatchArrayShape(
  Object? value, {
  required String path,
}) {
  if (value is! List) {
    return <String>['$path must be an array of objects'];
  }
  final violations = <String>[];
  for (var index = 0; index < value.length; index += 1) {
    violations.addAll(
      _validateArrowBindingStatePatchShape(value[index], path: '$path[$index]'),
    );
  }
  return violations;
}

List<String> _validateEngineContextShape(
  Object? value, {
  required String path,
  required bool allowNull,
  bool requireBindMode = false,
  bool requireMaxCoordinate = false,
}) {
  if (value == null) {
    return allowNull ? const <String>[] : <String>['$path must be an object'];
  }
  if (value is! Map) {
    return <String>['$path must be an object${allowNull ? ' or null' : ''}'];
  }
  final violations = <String>[];
  if (!_isFiniteNumber(value['zoom'])) {
    violations.add('$path.zoom must be a finite number');
  }
  if (value['isBindingEnabled'] is! bool) {
    violations.add('$path.isBindingEnabled must be a boolean');
  }
  if (requireBindMode && !_isBindModeValue(value['bindMode'])) {
    violations.add('$path.bindMode must be "inside", "orbit", or "skip"');
  }
  if (requireMaxCoordinate && !_isFiniteNumber(value['maxCoordinate'])) {
    violations.add('$path.maxCoordinate must be a finite number');
  }
  return violations;
}

List<String> _validateNormalizeEngineContextShape(
  Object? value, {
  required String path,
}) {
  if (value == null) {
    return const <String>[];
  }
  if (value is! Map) {
    return <String>['$path must be an object or null'];
  }
  final violations = <String>[];
  if (value.containsKey('zoom') && !_isFiniteNumber(value['zoom'])) {
    violations.add('$path.zoom must be a finite number when provided');
  }
  if (value.containsKey('isBindingEnabled') &&
      value['isBindingEnabled'] is! bool) {
    violations.add('$path.isBindingEnabled must be a boolean when provided');
  }
  if (value.containsKey('bindMode') && !_isBindModeValue(value['bindMode'])) {
    violations.add(
      '$path.bindMode must be "inside", "orbit", or "skip" when provided',
    );
  }
  if (value.containsKey('maxCoordinate') &&
      !_isFiniteNumber(value['maxCoordinate'])) {
    violations.add('$path.maxCoordinate must be a finite number when provided');
  }
  return violations;
}

List<String> _validateBoundRelationEntriesShape(
  Object? value, {
  required String path,
}) {
  if (value == null) {
    return const <String>[];
  }
  if (value is! List) {
    return <String>['$path must be an array of objects or null'];
  }
  final violations = <String>[];
  for (var index = 0; index < value.length; index += 1) {
    final entry = value[index];
    if (entry is! Map) {
      violations.add('$path[$index] must be an object');
      continue;
    }
    if (entry['id'] is! String) {
      violations.add('$path[$index].id must be a string');
    }
    if (entry['type'] is! String) {
      violations.add('$path[$index].type must be a string');
    }
  }
  return violations;
}

class _MissingRequiredField {
  const _MissingRequiredField();
}

const _MissingRequiredField _missingRequiredField = _MissingRequiredField();

bool _isOptionalFieldForOperation(String operationType, String field) =>
    _operationOptionalFields[operationType]?.contains(field) ?? false;

String _optionalFieldSuffix(String operationType, String field) =>
    _isOptionalFieldForOperation(operationType, field) ? ' when provided' : '';

bool _shouldSkipMissingFieldShapeValidation(
  String operationType,
  String field,
) => _missingFieldShapeValidationSkips.contains('$operationType|$field');

List<String> _validateOperationFieldShape(
  String operationType,
  String field,
  Object? value,
) {
  final path = 'request.input.$field';
  switch (field) {
    case 'arrow':
      if (_operationsWithArrowBindingStateArrowField.contains(operationType)) {
        return _validateStrictArrowBindingState(value, path: path);
      }
      if (_operationsWithArrowPointsOnlyField.contains(operationType)) {
        if (value is! Map) {
          return <String>['$path must be an object'];
        }
        return _isPointTupleArray(value['points'])
            ? const <String>[]
            : <String>['$path.points must be an array of points'];
      }
      if (_operationsWithArrowElbowOnlyField.contains(operationType)) {
        if (value is! Map) {
          return <String>['$path must be an object'];
        }
        return value['elbowed'] is bool
            ? const <String>[]
            : <String>['$path.elbowed must be a boolean'];
      }
      return _validateStrictArrowState(value, path: path);
    case 'arrows':
      if (_operationsWithArrowBindingStateArrowsField.contains(operationType)) {
        return _validateStrictArrowBindingStateArray(value, path: path);
      }
      return _validateStrictArrowStateArray(value, path: path);
    case 'bindable':
      if (_operationsAllowNullBindableField.contains(operationType)) {
        if (value == null) {
          return const <String>[];
        }
        if (value is _MissingRequiredField) {
          return <String>['$path must be an object or null'];
        }
      }
      if (_operationsWithRelationBindableField.contains(operationType)) {
        return _validateStrictBindableRelationState(value, path: path);
      }
      return _validateStrictBindableState(value, path: path);
    case 'bindables':
      if (_operationsWithRelationBindablesField.contains(operationType)) {
        return _validateStrictBindableRelationStateArray(value, path: path);
      }
      return _validateStrictBindableStateArray(value, path: path);
    case 'relations':
      if (operationType == 'recompute-bindings-for-changed-bindables') {
        return _validateStrictBindableRelationStateArray(value, path: path);
      }
    case 'left':
    case 'right':
      return _validateBoundRelationEntriesShape(value, path: path);
    case 'previous':
    case 'next':
      if (operationType == 'derive-bindable-patches-for-binding-change' ||
          operationType ==
              'derive-bindable-relation-patches-for-binding-change') {
        if (value is! Map) {
          return <String>['$path must be an object'];
        }
        final violations = <String>[];
        if (!value.containsKey('startBinding')) {
          violations.add('$path.startBinding is required');
        } else {
          violations.addAll(
            _validateStrictFixedPointBinding(
              value['startBinding'],
              path: '$path.startBinding',
              allowNull: true,
              requireMode: true,
            ),
          );
        }
        if (!value.containsKey('endBinding')) {
          violations.add('$path.endBinding is required');
        } else {
          violations.addAll(
            _validateStrictFixedPointBinding(
              value['endBinding'],
              path: '$path.endBinding',
              allowNull: true,
              requireMode: true,
            ),
          );
        }
        return violations;
      }
      return _asArrowBindingState(value) == null
          ? <String>[
              '$path must be an ArrowBindingState for operation "$operationType"',
            ]
          : const <String>[];
    case 'binding':
      return _validateFixedPointBindingShape(
        value,
        path: path,
        allowNull: _operationsAllowNullBindingField.contains(operationType),
        requireMode: _operationsRequireBindingMode.contains(operationType),
      );
    case 'edge':
      if (operationType == 'update-bound-point') {
        return _isArrowEndpointSelectorValue(value)
            ? const <String>[]
            : <String>[
                '$path must be "start", "end", "startBinding", or "endBinding"',
              ];
      }
      return _isArrowEndpointEdgeValue(value)
          ? const <String>[]
          : <String>['$path must be "start" or "end"'];
    case 'draggedEdge':
      return _isArrowEndpointEdgeValue(value)
          ? const <String>[]
          : <String>['$path must be "start" or "end"'];
    case 'inner':
    case 'outer':
      return _validateStrictBindableState(value, path: path);
    case 'point':
    case 'pointer':
    case 'otherPoint':
    case 'delta':
    case 'originPoint':
    case 'focusPoint':
      return _isPointTuple(value)
          ? const <String>[]
          : <String>['$path must be a [number, number] tuple'];
    case 'points':
    case 'arrowPoints':
      if (field == 'points' &&
          operationType == 'compute-elbow-resize-patch' &&
          value == null) {
        return const <String>[];
      }
      return _isPointTupleArray(value)
          ? const <String>[]
          : <String>['$path must be an array of points'];
    case 'customIntersector':
      return value is List &&
              value.length == 2 &&
              _isPointTuple(value[0]) &&
              _isPointTuple(value[1])
          ? const <String>[]
          : <String>['$path must be a tuple of two points'];
    case 'aabb':
      if (value == null) {
        return const <String>[];
      }
      return _isBoundsTuple(value)
          ? const <String>[]
          : <String>[
              '$path must be null or a [number, number, number, number] tuple',
            ];
    case 'context':
      if (operationType == 'normalize-engine-context') {
        return _validateNormalizeEngineContextShape(value, path: path);
      }
      return _validateEngineContextShape(
        value,
        path: path,
        allowNull: false,
        requireBindMode: _operationsContextRequireBindModeAndMaxCoordinate
            .contains(operationType),
        requireMaxCoordinate: _operationsContextRequireBindModeAndMaxCoordinate
            .contains(operationType),
      );
    case 'result':
      return _validateEngineResultShape(value, path: path);
    case 'events':
      return _validateArrowEngineEventsShape(value, path: path);
    case 'orderedElementIds':
    case 'anchorElementIds':
    case 'deletedBindableIds':
    case 'deletedArrowIds':
    case 'retainedBindableIds':
    case 'boundArrowIds':
      return _isStringArray(value)
          ? const <String>[]
          : <String>['$path must be an array of strings'];
    case 'changedBindableIds':
      return _isStringArray(value)
          ? const <String>[]
          : <String>['$path must be an array of strings'];
    case 'bindableIdMap':
    case 'arrowIdMap':
      return _validateIdMapShape(value, path: path);
    case 'anchorElementIdsByBindableId':
      return _validateAnchorElementIdsLookupShape(value, path: path);
    case 'zoom':
    case 'tolerance':
    case 'strokeWidth':
    case 'radius':
    case 'arrowheadSize':
    case 'minimumLength':
    case 'maxCoordinate':
      return _isFiniteNumber(value)
          ? const <String>[]
          : <String>[
              '$path must be a finite number${_optionalFieldSuffix(operationType, field)}',
            ];
    case 'flipX':
    case 'flipY':
    case 'elbowed':
    case 'dragging':
    case 'preserveUnmapped':
    case 'ignoreOverlap':
      return value is bool
          ? const <String>[]
          : <String>[
              '$path must be a boolean${_optionalFieldSuffix(operationType, field)}',
            ];
    case 'direction':
      return _isDirectionValue(value)
          ? const <String>[]
          : <String>['$path must be "up", "right", "down", or "left"'];
    case 'position':
      return _isArrowEndpointPositionValue(value)
          ? const <String>[]
          : <String>['$path must be "start" or "end"'];
    case 'mode':
      return _isBindModeValue(value)
          ? const <String>[]
          : <String>['$path must be "inside", "orbit", or "skip"'];
    case 'transformHandleType':
      return _isResizeHandleDirectionValue(value)
          ? const <String>[]
          : <String>[
              '$path must be one of "n", "s", "e", "w", "nw", "ne", "sw", "se", "rotation", false, null, or undefined',
            ];
    case 'arrowId':
      return value is String
          ? const <String>[]
          : <String>['$path must be a string'];
    case 'hoveredBindableId':
      return value == null || value is String
          ? const <String>[]
          : <String>['$path must be a string or null when provided'];
    case 'arrowhead':
      return _isArrowheadValue(value)
          ? const <String>[]
          : <String>['$path must be a valid arrowhead'];
    case 'strokeStyle':
      return value == 'solid' || value == 'dashed' || value == 'dotted'
          ? const <String>[]
          : <String>['$path must be "solid", "dashed", or "dotted"'];
    case 'segmentIndex':
      return _isPositiveInteger(value)
          ? const <String>[]
          : <String>['$path must be a positive integer'];
    case 'draggedPoints':
      if (value is! List) {
        return <String>['$path must be an array'];
      }
      final violations = <String>[];
      for (var index = 0; index < value.length; index += 1) {
        final entry = value[index];
        if (entry is! Map) {
          violations.add('$path[$index] must be an object');
          continue;
        }
        final indexValue = entry['index'];
        final isNonNegativeInteger =
            indexValue is num &&
            indexValue.isFinite &&
            indexValue >= 0 &&
            indexValue.toInt() == indexValue;
        if (!isNonNegativeInteger) {
          violations.add('$path[$index].index must be a non-negative integer');
        }
        if (!_isPointTuple(entry['point'])) {
          violations.add(
            '$path[$index].point must be a [number, number] tuple',
          );
        }
      }
      return violations;
    case 'startBounds':
    case 'endBounds':
      return _isDirectionalLinkBoundsShape(value)
          ? const <String>[]
          : <String>['$path must be an object'];
    case 'updates':
      if (operationType == 'update-elbow-arrow') {
        return _validateUpdateElbowPatchShape(value, path: path);
      }
      return const <String>[];
    case 'options':
      return _validateOptionsShape(operationType, value, path: path);
    case 'patch':
      if (operationType == 'apply-arrow-patch') {
        return _validateArrowPatchShape(value, path: path);
      }
      if (operationType == 'apply-bindable-relation-patch') {
        return _validateStrictBindableRelationPatch(value, path: path);
      }
      if (operationType == 'apply-arrow-binding-state-patch') {
        return _validateArrowBindingStatePatchShape(value, path: path);
      }
      return const <String>[];
    case 'patches':
      if (operationType == 'apply-arrow-binding-state-patches') {
        return _validateArrowBindingStatePatchArrayShape(value, path: path);
      }
      if (operationType == 'reduce-bindable-patches-to-relation-patches') {
        return _validateStrictBindablePatchArray(value, path: path);
      }
      if (operationType == 'apply-bindable-relation-patches') {
        return _validateStrictBindableRelationPatchArray(value, path: path);
      }
      return const <String>[];
    case 'curveOps':
      return _validateStrictCurvePathOpArray(value, path: path);
    case 'fixedSegments':
      return _validateStrictFixedSegments(value, path: path, allowNull: true);
    case 'arrowPatch':
      return _validateArrowPatchShape(value, path: path);
    case 'bindablePatches':
      return _validateStrictBindablePatchArray(value, path: path);
    case 'geometryBindables':
      return _validateStrictBindableStateArray(value, path: path);
    case 'existingBindables':
      return _validateStrictBindableStateArray(value, path: path);
  }

  return const <String>[];
}

List<String> _validateOperationInputShapeByHeuristics(
  Map<String, dynamic> input,
  String operationType,
) {
  final validatedFields = _operationValidatedFields[operationType];
  if (validatedFields == null || validatedFields.isEmpty) {
    return const <String>[];
  }
  final violations = <String>[];
  for (final entry in input.entries) {
    if (!validatedFields.contains(entry.key)) {
      continue;
    }
    violations.addAll(
      _validateOperationFieldShape(operationType, entry.key, entry.value),
    );
  }
  final requiredFields =
      _operationRequiredFields[operationType] ?? const <String>[];
  final missingFieldOrder =
      _operationMissingFieldValidationOrder[operationType] ?? requiredFields;
  for (final field in missingFieldOrder) {
    if (!requiredFields.contains(field)) {
      continue;
    }
    if (!validatedFields.contains(field) || input.containsKey(field)) {
      continue;
    }
    if (_shouldSkipMissingFieldShapeValidation(operationType, field)) {
      continue;
    }
    violations.addAll(
      _validateOperationFieldShape(operationType, field, _missingRequiredField),
    );
  }
  return violations;
}

Map<String, _OperationInputShapeValidator>
_buildOperationInputShapeValidators() {
  final out = <String, _OperationInputShapeValidator>{};
  for (final operationType in _operationResponseTypeMap.keys) {
    if (_isNullInputOperation(operationType) ||
        _operationsWithoutShapeValidation.contains(operationType)) {
      continue;
    }
    out[operationType] = _validateOperationInputShapeByHeuristics;
  }
  return Map<String, _OperationInputShapeValidator>.unmodifiable(out);
}

final Map<String, _OperationInputShapeValidator>
_operationInputShapeValidators = _buildOperationInputShapeValidators();

ArrowProtocolManifest getArrowProtocolManifest() {
  final operations = _operationResponseTypeMap.entries
      .map(
        (entry) => ArrowOperationManifestEntry(
          type: entry.key,
          responseType: entry.value,
          inputKind: _isNullInputOperation(entry.key) ? 'null' : 'object',
          requiredInputFields:
              _operationRequiredFields[entry.key] ?? const <String>[],
          usesShapeValidation: _operationInputShapeValidators.containsKey(
            entry.key,
          ),
        ),
      )
      .toList(growable: false);
  return ArrowProtocolManifest(
    version: arrowProtocolVersion,
    operations: operations,
  );
}

Map<String, dynamic> _toArrowCoreConstantsValue(ArrowCoreConstants constants) =>
    <String, dynamic>{
      'baseBindingGap': constants.baseBindingGap,
      'baseBindingGapElbow': constants.baseBindingGapElbow,
      'baseArrowMinLength': constants.baseArrowMinLength,
      'focusPointSize': constants.focusPointSize,
      'basePadding': constants.basePadding,
    };

Map<String, dynamic> _toArrowManifestEntryValue(
  ArrowOperationManifestEntry entry,
) => <String, dynamic>{
  'type': entry.type,
  'responseType': entry.responseType,
  'inputKind': entry.inputKind,
  'requiredInputFields': entry.requiredInputFields,
  'usesShapeValidation': entry.usesShapeValidation,
};

Map<String, dynamic> _toArrowProtocolManifestValue(
  ArrowProtocolManifest manifest,
) => <String, dynamic>{
  'version': manifest.version,
  'operations': manifest.operations
      .map(_toArrowManifestEntryValue)
      .toList(growable: false),
};

Map<String, dynamic> _toEngineContextValue(EngineContext context) =>
    <String, dynamic>{
      'zoom': context.zoom,
      'isBindingEnabled': context.isBindingEnabled,
      'bindMode': context.bindMode,
      'maxCoordinate': context.maxCoordinate,
    };

Map<String, dynamic> _toValidationReportValue(ValidationReport report) =>
    <String, dynamic>{'valid': report.valid, 'violations': report.violations};

bool isArrowOperationError(ArrowOperationResponse response) =>
    response['type'] == 'error';

bool isArrowOperationSuccess(ArrowOperationResponse response) =>
    response['type'] != 'error';

ArrowOperationResponse unwrapArrowOperationResponse(
  ArrowOperationResponse response,
) {
  if (isArrowOperationError(response)) {
    final error = _asStringDynamicMap(response['error']);
    throw StateError(
      _asString(error?['message'], fallback: 'Arrow operation failed'),
    );
  }
  return response;
}

String _resolveOperationType(Object? request) {
  if (request is Map && request['type'] is String) {
    return request['type'] as String;
  }
  return 'unknown';
}

bool _isArrowOperationType(String type) =>
    _operationResponseTypeMap.containsKey(type);

bool _isNullInputOperation(String type) => _nullInputOperations.contains(type);

String _toInvalidRequestMessage(List<String> violations) {
  if (violations.isEmpty) {
    return 'Invalid arrow operation request';
  }
  return 'Invalid arrow operation request: ${violations.join('; ')}';
}

String _toOperationFailureMessage(String operationType, Object error) {
  final message = error.toString().trim();
  if (message.isEmpty) {
    return 'Arrow operation "$operationType" failed';
  }
  return 'Arrow operation "$operationType" failed: $message';
}

List<String> validateArrowOperationInputShape(
  String operationType,
  Object? input,
) {
  if (_isNullInputOperation(operationType)) {
    return input == null
        ? const <String>[]
        : <String>['request.input must be null for operation "$operationType"'];
  }
  if (input is! Map) {
    return <String>[
      'request.input must be an object for operation "$operationType"',
    ];
  }

  final inputMap = _asStringDynamicMap(input);
  if (inputMap == null) {
    return <String>[
      'request.input must be an object for operation "$operationType"',
    ];
  }

  final requiredFields =
      _operationRequiredFields[operationType] ?? const <String>[];
  final violations = <String>[];
  final validator = _operationInputShapeValidators[operationType];
  if (validator != null) {
    violations.addAll(validator(inputMap, operationType));
  }

  for (final field in requiredFields) {
    if (!inputMap.containsKey(field)) {
      violations.add(
        'request.input.$field is required for operation "$operationType"',
      );
    }
  }
  return violations;
}

ArrowOperationEnvelopeValidation validateArrowOperationEnvelope(
  Object? request,
) {
  final operationType = _resolveOperationType(request);
  final violations = <String>[];

  if (request is! Map) {
    violations.add('request must be an object');
  } else {
    final requestType = request['type'];
    if (requestType is! String || requestType.trim().isEmpty) {
      violations.add('request.type must be a non-empty string');
    } else if (!_isArrowOperationType(requestType)) {
      violations.add(
        'request.type must be a supported arrow operation, received "$requestType"',
      );
    }
    if (!request.containsKey('input')) {
      violations.add('request.input is required');
    } else if (requestType is String && _isArrowOperationType(requestType)) {
      violations.addAll(
        validateArrowOperationInputShape(requestType, request['input']),
      );
    }
  }

  return ArrowOperationEnvelopeValidation(
    valid: violations.isEmpty,
    operationType: operationType,
    violations: violations,
  );
}

Map<String, dynamic>? _asStringDynamicMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    final out = <String, dynamic>{};
    value.forEach((key, entryValue) {
      if (key is String) {
        out[key] = entryValue;
      }
    });
    return out;
  }
  return null;
}

Map<String, dynamic> _requireInput(Object? value, String operationType) {
  final map = _asStringDynamicMap(value);
  if (map == null) {
    throw ArgumentError(
      'request.input must be an object for operation "$operationType"',
    );
  }
  return map;
}

String _asString(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num && value.isFinite) {
    return value.toDouble();
  }
  return fallback;
}

int _asInt(Object? value, {int fallback = 0}) {
  if (value is num && value.isFinite) {
    return value.toInt();
  }
  return fallback;
}

int _requirePositiveInt(Object? value, String path) {
  if (_isPositiveInteger(value)) {
    return (value as num).toInt();
  }
  throw StateError('$path must be a positive integer');
}

bool _asBool(Object? value, {bool fallback = false}) =>
    value is bool ? value : fallback;

List<String> _asStringList(Object? value) {
  if (value is List<String>) {
    return value;
  }
  if (value is List) {
    return value.whereType<String>().toList(growable: false);
  }
  return const <String>[];
}

Point _asPoint(Object? value) {
  if (value is List && value.length >= 2) {
    final x = value[0];
    final y = value[1];
    if (x is num && y is num && x.isFinite && y.isFinite) {
      return <double>[x.toDouble(), y.toDouble()];
    }
  }
  return <double>[0, 0];
}

List<Point> _asPoints(Object? value) {
  if (value is! List) {
    return const <Point>[];
  }
  return value.map(_asPoint).toList(growable: false);
}

Point? _asNullablePoint(Object? value) {
  if (value is! List || value.length < 2) {
    return null;
  }
  final x = value[0];
  final y = value[1];
  if (x is num && y is num && x.isFinite && y.isFinite) {
    return <double>[x.toDouble(), y.toDouble()];
  }
  return null;
}

Bounds? _asBounds(Object? value) {
  if (value is! List || value.length < 4) {
    return null;
  }
  final bounds = <double>[];
  for (var index = 0; index < 4; index += 1) {
    final item = value[index];
    if (item is! num || !item.isFinite) {
      return null;
    }
    bounds.add(item.toDouble());
  }
  return bounds;
}

BindableRoundness? _asBindableRoundness(Object? value) {
  if (value is BindableRoundness) {
    return value;
  }
  final map = _asStringDynamicMap(value);
  if (map == null || !map.containsKey('type')) {
    return null;
  }
  return BindableRoundness(
    type: (map['type'] ?? 'LEGACY') as Object,
    value: map['value'] is num ? (map['value'] as num).toDouble() : null,
  );
}

FixedPointBinding? _asFixedPointBinding(Object? value) {
  if (value is FixedPointBinding) {
    return value;
  }
  final map = _asStringDynamicMap(value);
  if (map == null) {
    return null;
  }
  final elementId = _asString(map['elementId']);
  final mode = _asString(map['mode'], fallback: bindModeOrbit);
  final fixedPoint = _asNullablePoint(map['fixedPoint']);
  if (elementId.isEmpty || fixedPoint == null) {
    return null;
  }
  return FixedPointBinding(
    elementId: elementId,
    fixedPoint: fixedPoint,
    mode: mode,
  );
}

FixedSegment? _asFixedSegment(Object? value) {
  if (value is FixedSegment) {
    return value;
  }
  final map = _asStringDynamicMap(value);
  if (map == null) {
    return null;
  }
  final start = _asNullablePoint(map['start']);
  final end = _asNullablePoint(map['end']);
  final indexValue = map['index'];
  final index = indexValue is num ? indexValue.toInt() : null;
  if (start == null || end == null || index == null) {
    return null;
  }
  return FixedSegment(start: start, end: end, index: index);
}

List<FixedSegment>? _asFixedSegments(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is List<FixedSegment>) {
    return value;
  }
  if (value is! List) {
    return null;
  }
  return value
      .map(_asFixedSegment)
      .whereType<FixedSegment>()
      .toList(growable: false);
}

ArrowState? _asArrowState(Object? value) {
  if (value is ArrowState) {
    return value;
  }
  final map = _asStringDynamicMap(value);
  if (map == null) {
    return null;
  }
  final id = _asString(map['id']);
  final points = _asPoints(map['points']);
  if (id.isEmpty || points.isEmpty) {
    return null;
  }
  return ArrowState(
    id: id,
    x: _asDouble(map['x']),
    y: _asDouble(map['y']),
    width: _asDouble(map['width']),
    height: _asDouble(map['height']),
    points: points,
    startBinding: _asFixedPointBinding(map['startBinding']),
    endBinding: _asFixedPointBinding(map['endBinding']),
    startArrowhead: map['startArrowhead'] is String
        ? map['startArrowhead'] as String
        : null,
    endArrowhead: map['endArrowhead'] is String
        ? map['endArrowhead'] as String
        : null,
    elbowed: _asBool(map['elbowed']),
    fixedSegments: _asFixedSegments(map['fixedSegments']),
    startIsSpecial: map['startIsSpecial'] is bool
        ? map['startIsSpecial'] as bool
        : null,
    endIsSpecial: map['endIsSpecial'] is bool
        ? map['endIsSpecial'] as bool
        : null,
  );
}

ArrowState _requireArrowState(
  Object? value,
  String operationType, [
  String field = 'arrow',
]) {
  final arrow = _asArrowState(value);
  if (arrow == null) {
    throw ArgumentError(
      'request.input.$field must be an ArrowState for operation "$operationType"',
    );
  }
  return arrow;
}

List<ArrowState> _asArrowStates(Object? value) {
  if (value is List<ArrowState>) {
    return value;
  }
  if (value is! List) {
    return const <ArrowState>[];
  }
  return value
      .map(_asArrowState)
      .whereType<ArrowState>()
      .toList(growable: false);
}

BindableState? _asBindableState(Object? value) {
  if (value is BindableState) {
    return value;
  }
  final map = _asStringDynamicMap(value);
  if (map == null) {
    return null;
  }
  final id = _asString(map['id']);
  final shape = _asString(map['shape'], fallback: 'rectangle');
  if (id.isEmpty) {
    return null;
  }
  return BindableState(
    id: id,
    shape: shape,
    x: _asDouble(map['x']),
    y: _asDouble(map['y']),
    width: _asDouble(map['width']),
    height: _asDouble(map['height']),
    angle: _asDouble(map['angle']),
    strokeWidth: _asDouble(map['strokeWidth']),
    roundness: _asBindableRoundness(map['roundness']),
    zIndex: map['zIndex'] is num ? (map['zIndex'] as num).toDouble() : null,
    backgroundOpaque: map['backgroundOpaque'] is bool
        ? map['backgroundOpaque'] as bool
        : null,
    bindingEnabled: map['bindingEnabled'] is bool
        ? map['bindingEnabled'] as bool
        : null,
    interiorHitEnabled: map['interiorHitEnabled'] is bool
        ? map['interiorHitEnabled'] as bool
        : null,
    visibilityBounds: _asBounds(map['visibilityBounds']),
  );
}

BindableState _requireBindableState(
  Object? value,
  String operationType, [
  String field = 'bindable',
]) {
  final bindable = _asBindableState(value);
  if (bindable == null) {
    throw ArgumentError(
      'request.input.$field must be a BindableState for operation "$operationType"',
    );
  }
  return bindable;
}

List<BindableState> _asBindableStates(Object? value) {
  if (value is List<BindableState>) {
    return value;
  }
  if (value is! List) {
    return const <BindableState>[];
  }
  return value
      .map(_asBindableState)
      .whereType<BindableState>()
      .toList(growable: false);
}

ArrowBindingState? _asArrowBindingState(Object? value) {
  if (value is ArrowBindingState) {
    return value;
  }
  final arrow = _asArrowState(value);
  if (arrow != null) {
    return ArrowBindingState(
      id: arrow.id,
      startBinding: arrow.startBinding,
      endBinding: arrow.endBinding,
    );
  }
  final map = _asStringDynamicMap(value);
  if (map == null) {
    return null;
  }
  final id = _asString(map['id']);
  if (id.isEmpty) {
    return null;
  }
  return ArrowBindingState(
    id: id,
    startBinding: _asFixedPointBinding(map['startBinding']),
    endBinding: _asFixedPointBinding(map['endBinding']),
  );
}

ArrowBindingState _requireArrowBindingState(
  Object? value,
  String operationType, [
  String field = 'arrow',
]) {
  final arrow = _asArrowBindingState(value);
  if (arrow == null) {
    throw ArgumentError(
      'request.input.$field must be an ArrowBindingState for operation "$operationType"',
    );
  }
  return arrow;
}

ArrowBindingState _requireArrowBindingDeltaState(
  Object? value, {
  required String operationType,
  required String field,
  required String fallbackId,
}) {
  final normalized = _asArrowBindingState(value);
  if (normalized != null) {
    return normalized;
  }
  final map = _asStringDynamicMap(value);
  if (map == null) {
    throw ArgumentError(
      'request.input.$field must be an ArrowBindingState for operation "$operationType"',
    );
  }
  return ArrowBindingState(
    id: fallbackId,
    startBinding: _asFixedPointBinding(map['startBinding']),
    endBinding: _asFixedPointBinding(map['endBinding']),
  );
}

List<ArrowBindingState> _asArrowBindingStates(Object? value) {
  if (value is List<ArrowBindingState>) {
    return value;
  }
  if (value is! List) {
    return const <ArrowBindingState>[];
  }
  return value
      .map(_asArrowBindingState)
      .whereType<ArrowBindingState>()
      .toList(growable: false);
}

BindablePatch? _asBindablePatch(Object? value) {
  if (value is BindablePatch) {
    return value;
  }
  final map = _asStringDynamicMap(value);
  if (map == null) {
    return null;
  }
  final id = _asString(map['id']);
  if (id.isEmpty) {
    return null;
  }
  return BindablePatch(
    id: id,
    addBoundArrowId: map['addBoundArrowId'] is String
        ? map['addBoundArrowId'] as String
        : null,
    removeBoundArrowId: map['removeBoundArrowId'] is String
        ? map['removeBoundArrowId'] as String
        : null,
  );
}

List<BindablePatch> _asBindablePatches(Object? value) {
  if (value is List<BindablePatch>) {
    return value;
  }
  if (value is! List) {
    return const <BindablePatch>[];
  }
  return value
      .map(_asBindablePatch)
      .whereType<BindablePatch>()
      .toList(growable: false);
}

BindableRelationState? _asBindableRelationState(Object? value) {
  if (value is BindableRelationState) {
    return value;
  }
  final map = _asStringDynamicMap(value);
  if (map == null) {
    return null;
  }
  final id = _asString(map['id']);
  if (id.isEmpty) {
    return null;
  }
  return BindableRelationState(
    id: id,
    boundArrowIds: _asStringList(map['boundArrowIds']),
  );
}

List<BindableRelationState> _asBindableRelationStates(Object? value) {
  if (value is List<BindableRelationState>) {
    return value;
  }
  if (value is! List) {
    return const <BindableRelationState>[];
  }
  return value
      .map(_asBindableRelationState)
      .whereType<BindableRelationState>()
      .toList(growable: false);
}

BindableRelationPatch? _asBindableRelationPatch(Object? value) {
  if (value is BindableRelationPatch) {
    return value;
  }
  final map = _asStringDynamicMap(value);
  if (map == null) {
    return null;
  }
  final id = _asString(map['id']);
  if (id.isEmpty) {
    return null;
  }
  return BindableRelationPatch(
    id: id,
    boundArrowIds: _asStringList(map['boundArrowIds']),
  );
}

List<BindableRelationPatch> _asBindableRelationPatches(Object? value) {
  if (value is List<BindableRelationPatch>) {
    return value;
  }
  if (value is! List) {
    return const <BindableRelationPatch>[];
  }
  return value
      .map(_asBindableRelationPatch)
      .whereType<BindableRelationPatch>()
      .toList(growable: false);
}

ArrowBindingStatePatch _asArrowBindingStatePatch(Object? value) {
  if (value is Map<String, dynamic>) {
    return <String, dynamic>{
      ...value,
      if (value.containsKey('startBinding'))
        'startBinding': _asFixedPointBinding(value['startBinding']),
      if (value.containsKey('endBinding'))
        'endBinding': _asFixedPointBinding(value['endBinding']),
    };
  }
  if (value is Map) {
    final out = <String, dynamic>{};
    value.forEach((key, entryValue) {
      if (key is String) {
        out[key] = entryValue;
      }
    });
    if (out.containsKey('startBinding')) {
      out['startBinding'] = _asFixedPointBinding(out['startBinding']);
    }
    if (out.containsKey('endBinding')) {
      out['endBinding'] = _asFixedPointBinding(out['endBinding']);
    }
    return out;
  }
  return <String, dynamic>{};
}

List<ArrowBindingStatePatch> _asArrowBindingStatePatches(Object? value) {
  if (value is! List) {
    return const <ArrowBindingStatePatch>[];
  }
  return value.map(_asArrowBindingStatePatch).toList(growable: false);
}

ArrowPatch _asArrowPatch(Object? value) {
  final map = _asStringDynamicMap(value);
  if (map == null) {
    return <String, dynamic>{};
  }
  final patch = <String, dynamic>{...map};
  if (patch.containsKey('startBinding')) {
    patch['startBinding'] = _asFixedPointBinding(patch['startBinding']);
  }
  if (patch.containsKey('endBinding')) {
    patch['endBinding'] = _asFixedPointBinding(patch['endBinding']);
  }
  if (patch.containsKey('points')) {
    patch['points'] = _asPoints(patch['points']);
  }
  if (patch.containsKey('fixedSegments')) {
    patch['fixedSegments'] = _asFixedSegments(patch['fixedSegments']);
  }
  return patch;
}

ArrowEngineEvent? _asArrowEngineEvent(Object? value) {
  if (value is ArrowEngineEvent) {
    return value;
  }
  final map = _asStringDynamicMap(value);
  if (map == null) {
    return null;
  }
  final type = _asString(map['type']);
  if (type == 'reorder-arrow') {
    final arrowId = _asString(map['arrowId']);
    final bindableId = _asString(map['bindableId']);
    if (arrowId.isNotEmpty && bindableId.isNotEmpty) {
      return ReorderArrowEvent(arrowId: arrowId, bindableId: bindableId);
    }
  }
  if (type == 'binding-broken') {
    final arrowId = _asString(map['arrowId']);
    final edge = _asString(map['edge'], fallback: arrowEndpointStart);
    if (arrowId.isNotEmpty) {
      return BindingBrokenEvent(
        arrowId: arrowId,
        edge: normalizeArrowEndpointEdge(edge),
      );
    }
  }
  return null;
}

List<ArrowEngineEvent> _asArrowEngineEvents(Object? value) {
  if (value is List<ArrowEngineEvent>) {
    return value;
  }
  if (value is! List) {
    return const <ArrowEngineEvent>[];
  }
  return value
      .map(_asArrowEngineEvent)
      .whereType<ArrowEngineEvent>()
      .toList(growable: false);
}

SuggestedBinding? _asSuggestedBinding(Object? value) {
  if (value is SuggestedBinding) {
    return value;
  }
  final map = _asStringDynamicMap(value);
  if (map == null) {
    return null;
  }
  final element = _asBindableState(map['element']);
  if (element == null) {
    return null;
  }
  final bindableId = _asString(map['bindableId']);
  return SuggestedBinding(
    bindableId: bindableId.isEmpty ? null : bindableId,
    element: element,
    midPoint: _asNullablePoint(map['midPoint']),
  );
}

EngineResult? _asEngineResult(Object? value) {
  if (value is EngineResult) {
    return value;
  }
  final map = _asStringDynamicMap(value);
  if (map == null) {
    return null;
  }
  return EngineResult(
    arrowPatch: _asArrowPatch(map['arrowPatch']),
    bindablePatches: _asBindablePatches(map['bindablePatches']),
    suggestedBinding: _asSuggestedBinding(map['suggestedBinding']),
    events: _asArrowEngineEvents(map['events']),
  );
}

EngineResult _requireEngineResult(
  Object? value,
  String operationType, [
  String field = 'result',
]) {
  final result = _asEngineResult(value);
  if (result == null) {
    throw ArgumentError(
      'request.input.$field must be an EngineResult for operation "$operationType"',
    );
  }
  return result;
}

EngineContext _asEngineContext(Object? value) {
  if (value is EngineContext) {
    return value;
  }
  return normalizeEngineContext(_asStringDynamicMap(value));
}

List<String>? _asNullableStringList(Object? value) {
  if (value == null) {
    return null;
  }
  return _asStringList(value);
}

Map<String, List<String>>? _asAnchorLookup(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map<String, List<String>>) {
    return value;
  }
  if (value is Map) {
    final out = <String, List<String>>{};
    value.forEach((key, entryValue) {
      if (key is String && entryValue is List) {
        out[key] = entryValue.whereType<String>().toList(growable: false);
      }
    });
    return out;
  }
  return null;
}

binding_core.DirectionalLinkBounds? _asDirectionalLinkBounds(Object? value) {
  if (value is binding_core.DirectionalLinkBounds) {
    return value;
  }
  final map = _asStringDynamicMap(value);
  if (map == null) {
    return null;
  }
  return binding_core.DirectionalLinkBounds(
    x: _asDouble(map['x']),
    y: _asDouble(map['y']),
    width: _asDouble(map['width']),
    height: _asDouble(map['height']),
  );
}

CurvePathOp? _asCurvePathOp(Object? value) {
  if (value is CurvePathOp) {
    return value;
  }
  final map = _asStringDynamicMap(value);
  if (map == null) {
    return null;
  }
  final op = _asString(map['op']);
  if (op.isEmpty) {
    return null;
  }
  final data = map['data'] is List
      ? (map['data'] as List)
            .whereType<num>()
            .map((entry) => entry.toDouble())
            .toList(growable: false)
      : const <double>[];
  return CurvePathOp(op: op, data: data);
}

List<CurvePathOp> _asCurvePathOps(Object? value) {
  if (value is List<CurvePathOp>) {
    return value;
  }
  if (value is! List) {
    return const <CurvePathOp>[];
  }
  return value
      .map(_asCurvePathOp)
      .whereType<CurvePathOp>()
      .toList(growable: false);
}

List<Point>? _asNullablePoints(Object? value) {
  if (value == null) {
    return null;
  }
  return _asPoints(value);
}

ArrowheadPointsInput _asArrowheadPointsInput(Map<String, dynamic> input) {
  return ArrowheadPointsInput(
    arrowPoints: _asPoints(input['arrowPoints']),
    strokeWidth: _asDouble(input['strokeWidth']),
    curveOps: _asCurvePathOps(input['curveOps']),
    position: _asString(input['position'], fallback: 'end'),
    arrowhead: _asString(input['arrowhead'], fallback: 'arrow'),
  );
}

ArrowheadRenderPrimitivesInput _asArrowheadRenderPrimitivesInput(
  Map<String, dynamic> input,
) {
  return ArrowheadRenderPrimitivesInput(
    arrowPoints: _asPoints(input['arrowPoints']),
    strokeWidth: _asDouble(input['strokeWidth']),
    curveOps: _asCurvePathOps(input['curveOps']),
    position: _asString(input['position'], fallback: 'end'),
    arrowhead: _asString(input['arrowhead'], fallback: 'arrow'),
    strokeStyle: _asString(input['strokeStyle'], fallback: 'solid'),
  );
}

ArrowState _arrowForSnapToMid(bool elbowed) => ArrowState(
  id: '_snap-to-mid',
  x: 0,
  y: 0,
  width: 0,
  height: 0,
  points: const <Point>[
    <double>[0, 0],
    <double>[0, 0],
  ],
  startBinding: null,
  endBinding: null,
  startArrowhead: null,
  endArrowhead: null,
  elbowed: elbowed,
  fixedSegments: null,
  startIsSpecial: null,
  endIsSpecial: null,
);

BoundRelationEntry? _asBoundRelationEntry(Object? value) {
  if (value is BoundRelationEntry) {
    return value;
  }
  final map = _asStringDynamicMap(value);
  if (map == null) {
    return null;
  }
  final id = _asString(map['id']);
  final type = _asString(map['type']);
  if (id.isEmpty || type.isEmpty) {
    return null;
  }
  return BoundRelationEntry(id: id, type: type);
}

List<BoundRelationEntry>? _asBoundRelationEntries(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is List<BoundRelationEntry>) {
    return value;
  }
  if (value is! List) {
    return null;
  }
  return value
      .map(_asBoundRelationEntry)
      .whereType<BoundRelationEntry>()
      .toList(growable: false);
}

Map<String, dynamic> _toNormalizedArrowValue(
  NormalizedArrowFromGlobalPoints value,
) {
  return <String, dynamic>{
    'x': value.x,
    'y': value.y,
    'points': value.points,
    'width': value.width,
    'height': value.height,
  };
}

typedef ArrowOperationRequest = Map<String, dynamic>;

ArrowOperationResponse executeArrowOperation(ArrowOperationRequest request) {
  try {
    final operationType = _asString(request['type'], fallback: 'unknown');
    final rawInput = request['input'];

    switch (operationType) {
      case 'get-protocol-manifest':
        return <String, dynamic>{
          'type': 'protocol-manifest',
          'manifest': _toArrowProtocolManifestValue(getArrowProtocolManifest()),
        };
      case 'get-default-engine-context':
        return <String, dynamic>{
          'type': 'engine-context',
          'context': _toEngineContextValue(defaultEngineContext),
        };
      case 'compute-endpoint-drag':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'engine-result',
            'result': computeEndpointDrag(<String, dynamic>{
              ...input,
              'arrow': _requireArrowState(input['arrow'], operationType),
              'bindables': _asBindableStates(input['bindables']),
              'context': _asEngineContext(input['context']),
            }),
          };
        }
      case 'get-endpoint-binding-strategy':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'endpoint-binding-strategies',
            'strategies': binding_core
                .getEndpointBindingStrategy(<String, dynamic>{
                  ...input,
                  'arrow': _requireArrowState(input['arrow'], operationType),
                  'bindables': _asBindableStates(input['bindables']),
                  'context': _asEngineContext(input['context']),
                }),
          };
        }
      case 'compute-simple-binding-patch':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'engine-result',
            'result': binding_core.computeSimpleBindingPatch(<String, dynamic>{
              ...input,
              'arrow': _requireArrowState(input['arrow'], operationType),
              'bindables': _asBindableStates(input['bindables']),
              'context': _asEngineContext(input['context']),
            }),
          };
        }
      case 'finalize-endpoint-drag':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'engine-result',
            'result': finalizeEndpointDrag(<String, dynamic>{
              ...input,
              'arrow': _requireArrowState(input['arrow'], operationType),
              'bindables': _asBindableStates(input['bindables']),
              'context': _asEngineContext(input['context']),
            }),
          };
        }
      case 'compute-focus-point-drag':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'engine-result',
            'result': computeFocusDrag(<String, dynamic>{
              ...input,
              'arrow': _requireArrowState(input['arrow'], operationType),
              'bindables': _asBindableStates(input['bindables']),
              'context': _asEngineContext(input['context']),
            }),
          };
        }
      case 'finalize-focus-point-drag':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'engine-result',
            'result': finalizeFocusDrag(<String, dynamic>{
              ...input,
              'arrow': _requireArrowBindingState(input['arrow'], operationType),
              'bindables': _asBindableRelationStates(input['bindables']),
            }),
          };
        }
      case 'resolve-visible-focus-points':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'focus-points',
            'points': resolveVisibleFocusPoints(<String, dynamic>{
              ...input,
              'arrow': _requireArrowState(input['arrow'], operationType),
              'bindables': _asBindableStates(input['bindables']),
              'context': _asEngineContext(input['context']),
            }),
          };
        }
      case 'resolve-focus-point-hit':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'focus-point-edge',
            'edge': resolveFocusPointHit(<String, dynamic>{
              ...input,
              'arrow': _requireArrowState(input['arrow'], operationType),
              'bindables': _asBindableStates(input['bindables']),
              'context': _asEngineContext(input['context']),
            }),
          };
        }
      case 'resolve-focus-point-hit-with-offset':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'focus-point-hit',
            'hit': resolveFocusPointHitWithOffset(<String, dynamic>{
              ...input,
              'arrow': _requireArrowState(input['arrow'], operationType),
              'bindables': _asBindableStates(input['bindables']),
              'context': _asEngineContext(input['context']),
            }),
          };
        }
      case 'recompute-after-bindable-change':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'engine-result',
            'result': recomputeAfterBindableChange(<String, dynamic>{
              ...input,
              'arrow': _requireArrowState(input['arrow'], operationType),
              'bindables': _asBindableStates(input['bindables']),
              'context': _asEngineContext(input['context']),
              if (input.containsKey('changedBindableIds'))
                'changedBindableIds': _asNullableStringList(
                  input['changedBindableIds'],
                ),
              if (input.containsKey('options'))
                'options': _asStringDynamicMap(input['options']),
            }),
          };
        }
      case 'recompute-bindings-for-changed-bindables':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'binding-lifecycle-sync',
            'value': recomputeBindingsForChangedBindables(<String, dynamic>{
              ...input,
              'arrows': _asArrowStates(input['arrows']),
              'bindables': _asBindableStates(input['bindables']),
              'relations': _asBindableRelationStates(input['relations']),
              'context': _asEngineContext(input['context']),
              if (input.containsKey('changedBindableIds'))
                'changedBindableIds': _asNullableStringList(
                  input['changedBindableIds'],
                ),
              if (input.containsKey('options'))
                'options': _asStringDynamicMap(input['options']),
            }),
          };
        }
      case 'refresh-endpoint-binding':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'engine-result',
            'result': binding_lifecycle
                .refreshEndpointBinding(<String, dynamic>{
                  ...input,
                  'arrow': _requireArrowState(input['arrow'], operationType),
                  'bindables': _asBindableStates(input['bindables']),
                  'context': _asEngineContext(input['context']),
                }),
          };
        }
      case 'prune-arrow-bindings':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'engine-result',
            'result': binding_lifecycle.pruneArrowBindings(<String, dynamic>{
              ...input,
              'arrow': _requireArrowState(input['arrow'], operationType),
              'retainedBindableIds': _asStringList(
                input['retainedBindableIds'],
              ),
            }),
          };
        }
      case 'recompute-bindings-after-bindable-change':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'engine-result',
            'result': binding_core.recomputeBindingsAfterBindableChange(
              _requireArrowState(input['arrow'], operationType),
              _asBindableStates(input['bindables']),
              _asEngineContext(input['context']),
              _asNullableStringList(input['changedBindableIds']),
              _asStringDynamicMap(input['options']),
            ),
          };
        }
      case 'recompute-elbow':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'arrow-patch',
            'patch': recomputeElbow(<String, dynamic>{
              ...input,
              'arrow': _requireArrowState(input['arrow'], operationType),
              'bindables': _asBindableStates(input['bindables']),
              'context': _asEngineContext(input['context']),
            }),
          };
        }
      case 'update-elbow-arrow':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'arrow-patch',
            'patch': updateElbowArrowPatch(<String, dynamic>{
              ...input,
              'arrow': _requireArrowState(input['arrow'], operationType),
              'bindables': _asBindableStates(input['bindables']),
              'context': _asEngineContext(input['context']),
              if (input.containsKey('options'))
                'options': _asStringDynamicMap(input['options']),
            }),
          };
        }
      case 'compute-elbow-resize-patch':
        return <String, dynamic>{
          'type': 'arrow-patch',
          'patch': computeElbowResizePatch(
            _requireInput(rawInput, operationType),
          ),
        };
      case 'move-fixed-segment':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'arrow-patch',
            'patch': moveFixedSegment(
              arrow: _requireArrowState(input['arrow'], operationType),
              segmentIndex: _requirePositiveInt(
                input['segmentIndex'],
                'request.input.segmentIndex',
              ),
              delta: _asPoint(input['delta']),
            ),
          };
        }
      case 'move-fixed-segment-to-point':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'fixed-segment-drag',
            'value': moveFixedSegmentToPoint(<String, dynamic>{
              ...input,
              'arrow': _requireArrowState(input['arrow'], operationType),
              'segmentIndex': _requirePositiveInt(
                input['segmentIndex'],
                'request.input.segmentIndex',
              ),
              'pointer': _asPoint(input['pointer']),
            }),
          };
        }
      case 'release-fixed-segment':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'arrow-patch',
            'patch': releaseFixedSegment(
              arrow: _requireArrowState(input['arrow'], operationType),
              segmentIndex: _requirePositiveInt(
                input['segmentIndex'],
                'request.input.segmentIndex',
              ),
            ),
          };
        }
      case 'apply-arrow-patch':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'arrow-state',
            'arrow': applyArrowPatch(
              _requireArrowState(input['arrow'], operationType),
              _asArrowPatch(input['patch']),
            ),
          };
        }
      case 'reorder-arrow-above-elements':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'arrow-layer-reorder',
            'value': reorderArrowAboveElements(
              ReorderArrowAboveElementsInput(
                orderedElementIds: _asStringList(input['orderedElementIds']),
                arrowId: _asString(input['arrowId']),
                anchorElementIds: _asStringList(input['anchorElementIds']),
              ),
            ),
          };
        }
      case 'reorder-arrow-above-hovered-bindable':
        {
          final input = _requireInput(rawInput, operationType);
          final hoveredBindableId = _asString(input['hoveredBindableId']);
          final tolerance = input['tolerance'];
          return <String, dynamic>{
            'type': 'arrow-layer-reorder-hovered',
            'value': reorderArrowAboveHoveredBindable(
              ReorderArrowAboveHoveredBindableInput(
                orderedElementIds: _asStringList(input['orderedElementIds']),
                arrowId: _asString(input['arrowId']),
                hoveredBindableId: hoveredBindableId.isEmpty
                    ? null
                    : hoveredBindableId,
                point: _asNullablePoint(input['point']),
                bindables: input.containsKey('bindables')
                    ? _asBindableStates(input['bindables'])
                    : null,
                tolerance: tolerance is num && tolerance.isFinite
                    ? tolerance.toDouble()
                    : null,
                anchorElementIdsByBindableId: _asAnchorLookup(
                  input['anchorElementIdsByBindableId'],
                ),
              ),
            ),
          };
        }
      case 'reduce-arrow-engine-events-to-order':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'order-reduction',
            'value': reduceArrowEngineEventsToOrder(
              ReduceArrowEngineEventsToOrderInput(
                orderedElementIds: _asStringList(input['orderedElementIds']),
                events: _asArrowEngineEvents(input['events']),
                anchorElementIdsByBindableId: _asAnchorLookup(
                  input['anchorElementIdsByBindableId'],
                ),
              ),
            ),
          };
        }
      case 'get-resize-arrow-direction':
        {
          final input = _requireInput(rawInput, operationType);
          final arrow = _asArrowState(input['arrow']);
          return <String, dynamic>{
            'type': 'arrow-resize-direction',
            'value': getResizeArrowDirection(
              input['transformHandleType'],
              arrow?.points ??
                  _asPoints(_asStringDynamicMap(input['arrow'])?['points']),
            ),
          };
        }
      case 'get-binding-gap':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'number',
            'value': binding_core.getBindingGap(
              _requireBindableState(input['bindable'], operationType),
              _asBool(input['elbowed']),
            ),
          };
        }
      case 'max-binding-distance':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'number',
            'value': binding_core.maxBindingDistance(_asDouble(input['zoom'])),
          };
        }
      case 'create-directional-link-arrow':
        {
          final input = _requireInput(rawInput, operationType);
          final startBounds =
              _asDirectionalLinkBounds(input['startBounds']) ??
              const binding_core.DirectionalLinkBounds(
                x: 0,
                y: 0,
                width: 0,
                height: 0,
              );
          final endBounds =
              _asDirectionalLinkBounds(input['endBounds']) ??
              const binding_core.DirectionalLinkBounds(
                x: 0,
                y: 0,
                width: 0,
                height: 0,
              );
          final padding = _asDouble(input['arrowheadSize'], fallback: 6);
          return <String, dynamic>{
            'type': 'directional-link-arrow',
            'value': binding_core.createDirectionalLinkArrow(
              startBounds,
              endBounds,
              _asString(input['direction'], fallback: 'down'),
              padding: padding,
            ),
          };
        }
      case 'offset-arrow-endpoints-for-binding-overlap':
        {
          final input = _requireInput(rawInput, operationType);
          final delta = _asDouble(input['minimumLength'], fallback: 0.5);
          return <String, dynamic>{
            'type': 'points',
            'points': binding_core.offsetArrowEndpointsForBindingOverlap(
              _asPoints(input['points']),
              delta: delta,
            ),
          };
        }
      case 'get-arrowhead-size':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'number',
            'value': getArrowheadSize(_asString(input['arrowhead'])),
          };
        }
      case 'get-arrowhead-angle':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'number',
            'value': getArrowheadAngle(_asString(input['arrowhead'])),
          };
        }
      case 'get-arrowhead-points':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'arrowhead-points',
            'points': getArrowheadPoints(_asArrowheadPointsInput(input)),
          };
        }
      case 'get-arrowhead-render-primitives':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'arrowhead-render-primitives',
            'primitives': getArrowheadRenderPrimitives(
              _asArrowheadRenderPrimitivesInput(input),
            ),
          };
        }
      case 'generate-elbow-arrow-path':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'string',
            'value': generateElbowArrowPath(
              _asPoints(input['points']),
              _asDouble(input['radius']),
            ),
          };
        }
      case 'avoid-rectangular-corner':
        {
          final input = _requireInput(rawInput, operationType);
          final arrowFromInput = _asArrowState(input['arrow']);
          final elbowOnlyArrow = input['arrow'] is Map
              ? _arrowForSnapToMid(_asBool((input['arrow'] as Map)['elbowed']))
              : null;
          return <String, dynamic>{
            'type': 'point',
            'point': binding_core.avoidRectangularCorner(
              arrowFromInput ?? elbowOnlyArrow ?? _arrowForSnapToMid(false),
              _requireBindableState(input['bindable'], operationType),
              _asPoint(input['point']),
            ),
          };
        }
      case 'snap-to-mid':
        {
          final input = _requireInput(rawInput, operationType);
          final arrowFromInput = _asArrowState(input['arrow']);
          final elbowed = _asBool(input['elbowed']);
          final arrow =
              arrowFromInput ??
              (input.containsKey('elbowed')
                  ? _arrowForSnapToMid(elbowed)
                  : null);
          return <String, dynamic>{
            'type': 'optional-point',
            'point': binding_core.snapToMid(
              _requireBindableState(input['bindable'], operationType),
              _asPoint(input['point']),
              tolerance: _asDouble(input['tolerance'], fallback: 0.05),
              arrow: arrow,
            ),
          };
        }
      case 'get-snap-outline-mid-point':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'optional-point',
            'point': binding_core.getSnapOutlineMidPoint(
              _asPoint(input['point']),
              _requireBindableState(input['bindable'], operationType),
              _asDouble(input['zoom'], fallback: 1),
            ),
          };
        }
      case 'project-fixed-point-onto-diagonal':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'optional-point',
            'point': binding_core.projectFixedPointOntoDiagonal(
              _requireArrowState(input['arrow'], operationType),
              _asPoint(input['point']),
              _requireBindableState(input['bindable'], operationType),
              normalizeArrowEndpointEdge(_asString(input['edge'])),
              _asBindableStates(input['bindables']),
              _asDouble(input['zoom'], fallback: 1),
            ),
          };
        }
      case 'bind-point-to-outline':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'point',
            'point': binding_core.bindPointToOutline(
              arrow: _requireArrowState(input['arrow'], operationType),
              bindable: _requireBindableState(input['bindable'], operationType),
              edge: normalizeArrowEndpointEdge(_asString(input['edge'])),
              customIntersector: _asNullablePoints(input['customIntersector']),
            ),
          };
        }
      case 'calculate-fixed-point-for-binding':
        {
          final input = _requireInput(rawInput, operationType);
          final point = binding_core.calculateFixedPointForBinding(
            point: _asPoint(input['point']),
            bindable: _requireBindableState(input['bindable'], operationType),
          );
          return <String, dynamic>{'type': 'point', 'point': point};
        }
      case 'calculate-fixed-point-for-elbow-binding':
        {
          final input = _requireInput(rawInput, operationType);
          final point = binding_core.calculateFixedPointForElbowBinding(
            arrow: _requireArrowState(input['arrow'], operationType),
            bindable: _requireBindableState(input['bindable'], operationType),
            edge: normalizeArrowEndpointEdge(_asString(input['edge'])),
          );
          return <String, dynamic>{'type': 'point', 'point': point};
        }
      case 'update-bound-point':
        {
          final input = _requireInput(rawInput, operationType);
          final binding = _asFixedPointBinding(input['binding']);
          return <String, dynamic>{
            'type': 'optional-point',
            'point': binding_core.updateBoundPoint(
              arrow: _requireArrowState(input['arrow'], operationType),
              edge: _asString(input['edge'], fallback: arrowEndpointStart),
              binding: binding,
              bindable: _requireBindableState(input['bindable'], operationType),
              bindablesById:
                  (input['bindables'] ?? const <String, dynamic>{}) as Object,
              dragging: _asBool(input['dragging']),
            ),
          };
        }
      case 'distance-to-bindable-outline':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'number',
            'value': distanceToBindableOutline(
              _asPoint(input['point']),
              _requireBindableState(input['bindable'], operationType),
            ),
          };
        }
      case 'is-point-in-bindable':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'boolean',
            'value': isPointInBindable(
              _asPoint(input['point']),
              _requireBindableState(input['bindable'], operationType),
            ),
          };
        }
      case 'is-bindable-inside-other-bindable':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'boolean',
            'value': isBindableInsideOtherBindable(
              _requireBindableState(input['inner'], operationType, 'inner'),
              _requireBindableState(input['outer'], operationType, 'outer'),
            ),
          };
        }
      case 'get-hovered-bindable':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'bindable',
            'bindable': getHoveredBindable(
              _asPoint(input['point']),
              _asBindableStates(input['bindables']),
              _asDouble(input['tolerance']),
            ),
          };
        }
      case 'get-bindables-over-point':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'bindables',
            'bindables': getBindablesOverPoint(
              _asPoint(input['point']),
              _asBindableStates(input['bindables']),
              _asDouble(input['tolerance']),
            ),
          };
        }
      case 'list-hovered-bindables':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'bindables',
            'bindables': binding_core.listHoveredBindables(
              _asPoint(input['point']),
              _asBindableStates(input['bindables']),
              _asDouble(input['tolerance']),
              stopAtOpaque: _asBool(input['stopAtOpaque']),
            ),
          };
        }
      case 'pick-hovered-bindable-for-focus':
        {
          final input = _requireInput(rawInput, operationType);
          final arrowFromInput = _asArrowState(input['arrow']);
          final elbowOnlyArrow = input['arrow'] is Map
              ? _arrowForSnapToMid(_asBool((input['arrow'] as Map)['elbowed']))
              : null;
          return <String, dynamic>{
            'type': 'bindable',
            'bindable': binding_core.pickHoveredBindableForFocus(
              _asPoint(input['point']),
              arrowFromInput ?? elbowOnlyArrow ?? _arrowForSnapToMid(false),
              _asBindableStates(input['bindables']),
              tolerance: _asDouble(input['tolerance']),
            ),
          };
        }
      case 'get-binding-side-mid-point':
        {
          final input = _requireInput(rawInput, operationType);
          final binding = _asFixedPointBinding(input['binding']);
          if (binding == null) {
            throw ArgumentError(
              'request.input.binding must be a FixedPointBinding for operation "$operationType"',
            );
          }
          return <String, dynamic>{
            'type': 'point',
            'point': getBindingSideMidPoint((
              elementId: binding.elementId,
              fixedPoint: binding.fixedPoint,
            ), _requireBindableState(input['bindable'], operationType)),
          };
        }
      case 'get-global-fixed-points':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'point-pair',
            'points': binding_core.getGlobalFixedPoints(
              _requireArrowState(input['arrow'], operationType),
              _asBindableStates(input['bindables']),
            ),
          };
        }
      case 'get-arrow-local-fixed-points':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'point-pair',
            'points': binding_core.getArrowLocalFixedPoints(
              _requireArrowState(input['arrow'], operationType),
              _asBindableStates(input['bindables']),
            ),
          };
        }
      case 'get-global-fixed-point':
        {
          final input = _requireInput(rawInput, operationType);
          final binding = _asFixedPointBinding(input['binding']);
          if (binding == null) {
            throw ArgumentError(
              'request.input.binding must be a FixedPointBinding for operation "$operationType"',
            );
          }
          return <String, dynamic>{
            'type': 'point',
            'point': getGlobalFixedPoint(
              binding,
              _requireBindableState(input['bindable'], operationType),
            ),
          };
        }
      case 'normalize-fixed-point':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'point',
            'point': normalizeFixedPoint(_asPoint(input['point'])),
          };
        }
      case 'is-fixed-point':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'boolean',
            'value': isFixedPoint(input['point']),
          };
        }
      case 'normalize-arrow-from-global-points':
        {
          final input = _requireInput(rawInput, operationType);
          final normalized = normalizeArrowFromGlobalPoints(
            _asPoints(input['points']),
            _asDouble(
              input['maxCoordinate'],
              fallback: defaultEngineContext.maxCoordinate,
            ),
          );
          return <String, dynamic>{
            'type': 'normalized-arrow',
            'value': _toNormalizedArrowValue(normalized),
          };
        }
      case 'normalize-bindable-state':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'bindable',
            'bindable': normalizeBindableState(
              _requireBindableState(input['bindable'], operationType),
            ),
          };
        }
      case 'normalize-bindable-states':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'bindables',
            'bindables': normalizeBindableStates(
              _asBindableStates(input['bindables']),
            ),
          };
        }
      case 'normalize-engine-context':
        {
          final input = _requireInput(rawInput, operationType);
          final contextInput = input['context'];
          final normalizedContext = contextInput is EngineContext
              ? contextInput
              : normalizeEngineContext(_asStringDynamicMap(contextInput));
          return <String, dynamic>{
            'type': 'engine-context',
            'context': _toEngineContextValue(normalizedContext),
          };
        }
      case 'validate-elbow-points':
        {
          final input = _requireInput(rawInput, operationType);
          final toleranceValue = input['tolerance'];
          final value = toleranceValue is num && toleranceValue.isFinite
              ? validateElbowPoints(
                  _asPoints(input['points']),
                  toleranceValue.toDouble(),
                )
              : validateElbowPoints(_asPoints(input['points']));
          return <String, dynamic>{'type': 'boolean', 'value': value};
        }
      case 'repair-binding-on-restore':
        return <String, dynamic>{
          'type': 'binding',
          'binding': repairBindingOnRestore(
            _requireInput(rawInput, operationType),
          ),
        };
      case 'repair-invalid-unbound-elbow-arrow-on-restore':
        return <String, dynamic>{
          'type': 'optional-arrow-patch',
          'patch': repairInvalidUnboundElbowArrowOnRestore(
            _requireInput(rawInput, operationType),
          ),
        };
      case 'repair-self-bound-extreme-elbow-arrow-on-restore':
        return <String, dynamic>{
          'type': 'optional-arrow-patch',
          'patch': repairSelfBoundExtremeElbowArrowOnRestore(
            _requireInput(rawInput, operationType),
          ),
        };
      case 'validate-arrow-invariant':
        {
          final input = _requireInput(rawInput, operationType);
          final report = validateArrowInvariant(
            _requireArrowState(input['arrow'], operationType),
          );
          return <String, dynamic>{
            'type': 'validation-report',
            'report': _toValidationReportValue(report),
          };
        }
      case 'validate-elbow-invariant':
        {
          final input = _requireInput(rawInput, operationType);
          final violations = validateElbowInvariant(
            _requireArrowState(input['arrow'], operationType),
          );
          return <String, dynamic>{
            'type': 'validation-report',
            'report': _toValidationReportValue(
              ValidationReport(
                valid: violations.isEmpty,
                violations: violations,
              ),
            ),
          };
        }
      case 'is-focus-point-visible':
        {
          final input = _requireInput(rawInput, operationType);
          final binding = _asFixedPointBinding(input['binding']);
          if (binding == null) {
            throw ArgumentError(
              'request.input.binding must be a FixedPointBinding for operation "$operationType"',
            );
          }
          return <String, dynamic>{
            'type': 'boolean',
            'value': isFocusPointVisible(
              arrow: _requireArrowState(input['arrow'], operationType),
              edge: normalizeArrowEndpointEdge(_asString(input['edge'])),
              binding: binding,
              bindable: _requireBindableState(input['bindable'], operationType),
              context: input['context'],
              ignoreOverlap: _asBool(input['ignoreOverlap']),
            ),
          };
        }
      case 'is-point-near-bindable-for-focus':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'boolean',
            'value': isPointNearBindableForFocus(
              _asPoint(input['point']),
              _requireBindableState(input['bindable'], operationType),
              _asDouble(input['zoom'], fallback: 1),
            ),
          };
        }
      case 'get-heading-for-elbow-snap':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'heading',
            'heading': binding_core.getHeadingForElbowSnap(
              point: _asPoint(input['point']),
              otherPoint: _asPoint(input['otherPoint']),
              bindable: _asBindableState(input['bindable']),
              aabb: _asBounds(input['aabb']),
              originPoint: _asNullablePoint(input['originPoint']),
              zoom: input['zoom'] is num && (input['zoom'] as num).isFinite
                  ? (input['zoom'] as num).toDouble()
                  : null,
            ),
          };
        }
      case 'bind-arrow-endpoint':
        {
          final input = _requireInput(rawInput, operationType);
          final mode = _asString(input['mode']);
          final mutation = binding_lifecycle.bindArrowEndpoint(
            arrow: _requireArrowState(input['arrow'], operationType),
            edge: normalizeArrowEndpointEdge(_asString(input['edge'])),
            bindable: _requireBindableState(input['bindable'], operationType),
            mode: mode.isEmpty ? null : mode,
            focusPoint: _asNullablePoint(input['focusPoint']),
          );
          return <String, dynamic>{
            'type': 'engine-result',
            'result': EngineResult(
              arrowPatch: mutation.arrowPatch,
              bindablePatches: mutation.bindablePatches,
              suggestedBinding: null,
              events: const <ArrowEngineEvent>[],
            ),
          };
        }
      case 'unbind-arrow-endpoint':
        {
          final input = _requireInput(rawInput, operationType);
          final mutation = binding_lifecycle.unbindArrowEndpoint(
            arrow: _requireArrowState(input['arrow'], operationType),
            edge: normalizeArrowEndpointEdge(_asString(input['edge'])),
          );
          return <String, dynamic>{
            'type': 'engine-result',
            'result': EngineResult(
              arrowPatch: mutation.arrowPatch,
              bindablePatches: mutation.bindablePatches,
              suggestedBinding: null,
              events: const <ArrowEngineEvent>[],
            ),
          };
        }
      case 'derive-bindable-patches-for-binding-change':
        {
          final input = _requireInput(rawInput, operationType);
          final arrowId = _asString(input['arrowId']);
          return <String, dynamic>{
            'type': 'bindable-patches',
            'patches': binding_lifecycle.deriveBindablePatchesForBindingChange(
              arrowId: arrowId,
              previous: _requireArrowBindingDeltaState(
                input['previous'],
                operationType: operationType,
                field: 'previous',
                fallbackId: arrowId,
              ),
              next: _requireArrowBindingDeltaState(
                input['next'],
                operationType: operationType,
                field: 'next',
                fallbackId: arrowId,
              ),
            ),
          };
        }
      case 'derive-bindable-relation-patches-for-binding-change':
        {
          final input = _requireInput(rawInput, operationType);
          final arrowId = _asString(input['arrowId']);
          return <String, dynamic>{
            'type': 'bindable-relation-patches',
            'patches': binding_lifecycle
                .deriveBindableRelationPatchesForBindingChange(
                  DeriveBindableRelationPatchesForBindingChangeInput(
                    arrowId: arrowId,
                    previous: _requireArrowBindingDeltaState(
                      input['previous'],
                      operationType: operationType,
                      field: 'previous',
                      fallbackId: arrowId,
                    ),
                    next: _requireArrowBindingDeltaState(
                      input['next'],
                      operationType: operationType,
                      field: 'next',
                      fallbackId: arrowId,
                    ),
                    bindables: _asBindableRelationStates(input['bindables']),
                  ),
                ),
          };
        }
      case 'reconcile-bindable-patches-for-arrow':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'bindable-patches',
            'patches': binding_lifecycle.reconcileBindablePatchesForArrow(
              arrow: _requireArrowBindingState(input['arrow'], operationType),
              bindables: _asBindableRelationStates(input['bindables']),
            ),
          };
        }
      case 'resolve-bindable-relation-patches':
        {
          final input = _requireInput(rawInput, operationType);
          final resolved = binding_lifecycle.resolveBindableRelationPatches(
            binding_lifecycle.ResolveBindableRelationPatchesInput(
              arrow: _requireArrowBindingState(input['arrow'], operationType),
              bindables: _asBindableRelationStates(input['bindables']),
              arrowPatch: input.containsKey('arrowPatch')
                  ? _asArrowPatch(input['arrowPatch'])
                  : null,
              bindablePatches: input.containsKey('bindablePatches')
                  ? _asBindablePatches(input['bindablePatches'])
                  : null,
            ),
          );
          return <String, dynamic>{
            'type': 'resolved-bindable-relations',
            'value': <String, dynamic>{
              'bindablePatches': resolved.bindablePatches,
              'relationPatches': resolved.relationPatches,
            },
          };
        }
      case 'remap-arrow-bindings-after-duplication':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'arrow-binding-state-patches',
            'patches': binding_lifecycle.remapArrowBindingsAfterDuplication(
              arrows: _asArrowBindingStates(input['arrows']),
              bindableIdMap:
                  (input['bindableIdMap'] ?? <String, String>{}) as IdMapInput,
              preserveUnmapped: _asBool(input['preserveUnmapped']),
            ),
          };
        }
      case 'remap-bindable-relations-after-duplication':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'bindable-relation-patches',
            'patches': binding_lifecycle.remapBindableRelationsAfterDuplication(
              bindables: _asBindableRelationStates(input['bindables']),
              arrowIdMap:
                  (input['arrowIdMap'] ?? <String, String>{}) as IdMapInput,
              preserveUnmapped: _asBool(input['preserveUnmapped']),
            ),
          };
        }
      case 'repair-arrow-bindings-after-bindable-deletion':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'arrow-binding-state-patches',
            'patches': binding_lifecycle
                .repairArrowBindingsAfterBindableDeletion(
                  arrows: _asArrowBindingStates(input['arrows']),
                  deletedBindableIds: _asStringList(
                    input['deletedBindableIds'],
                  ),
                ),
          };
        }
      case 'repair-bindable-relations-after-arrow-deletion':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'bindable-relation-patches',
            'patches': binding_lifecycle
                .repairBindableRelationsAfterArrowDeletion(
                  bindables: _asBindableRelationStates(input['bindables']),
                  deletedArrowIds: _asStringList(input['deletedArrowIds']),
                ),
          };
        }
      case 'sync-bindings-after-duplication':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'binding-lifecycle-sync',
            'value': binding_lifecycle
                .syncBindingsAfterDuplication(<String, dynamic>{
                  ...input,
                  'arrows': _asArrowStates(input['arrows']),
                  'bindables': _asBindableRelationStates(input['bindables']),
                  'bindableIdMap':
                      (input['bindableIdMap'] ?? <String, String>{})
                          as IdMapInput,
                  'arrowIdMap':
                      (input['arrowIdMap'] ?? <String, String>{}) as IdMapInput,
                  'preserveUnmapped': _asBool(input['preserveUnmapped']),
                  if (input.containsKey('geometryBindables'))
                    'geometryBindables': _asBindableStates(
                      input['geometryBindables'],
                    ),
                  if (input.containsKey('context'))
                    'context': _asEngineContext(input['context']),
                }),
          };
        }
      case 'sync-bindings-after-bindable-prune':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'binding-lifecycle-sync',
            'value': binding_lifecycle
                .syncBindingsAfterBindablePrune(<String, dynamic>{
                  ...input,
                  'arrows': _asArrowStates(input['arrows']),
                  'bindables': _asBindableRelationStates(input['bindables']),
                  'retainedBindableIds': _asStringList(
                    input['retainedBindableIds'],
                  ),
                  if (input.containsKey('geometryBindables'))
                    'geometryBindables': _asBindableStates(
                      input['geometryBindables'],
                    ),
                  if (input.containsKey('context'))
                    'context': _asEngineContext(input['context']),
                  if (input.containsKey('options'))
                    'options':
                        _asStringDynamicMap(input['options']) ??
                        const <String, dynamic>{},
                }),
          };
        }
      case 'sync-bindings-after-deletion':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'binding-lifecycle-sync',
            'value': binding_lifecycle
                .syncBindingsAfterDeletion(<String, dynamic>{
                  ...input,
                  'arrows': _asArrowStates(input['arrows']),
                  'bindables': _asBindableRelationStates(input['bindables']),
                  'deletedBindableIds': _asStringList(
                    input['deletedBindableIds'],
                  ),
                  'deletedArrowIds': _asStringList(input['deletedArrowIds']),
                  if (input.containsKey('geometryBindables'))
                    'geometryBindables': _asBindableStates(
                      input['geometryBindables'],
                    ),
                  if (input.containsKey('context'))
                    'context': _asEngineContext(input['context']),
                }),
          };
        }
      case 'apply-arrow-binding-state-patch':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'arrow-binding-state',
            'arrow': applyArrowBindingStatePatch(
              _requireArrowBindingState(input['arrow'], operationType),
              _asArrowBindingStatePatch(input['patch']),
            ),
          };
        }
      case 'apply-arrow-binding-state-patches':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'arrow-binding-states',
            'arrows': applyArrowBindingStatePatches(
              _asArrowBindingStates(input['arrows']),
              _asArrowBindingStatePatches(input['patches']),
            ),
          };
        }
      case 'reduce-bindable-patches-to-relation-patches':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'bindable-relation-patches',
            'patches': reduceBindablePatchesToRelationPatches(
              _asBindableRelationStates(input['bindables']),
              _asBindablePatches(input['patches']),
            ),
          };
        }
      case 'apply-bindable-relation-patch':
        {
          final input = _requireInput(rawInput, operationType);
          final patch = _asBindableRelationPatch(input['patch']);
          if (patch == null) {
            throw ArgumentError(
              'request.input.patch must be a BindableRelationPatch for operation "$operationType"',
            );
          }
          final bindable = _asBindableRelationState(input['bindable']);
          if (bindable == null) {
            throw ArgumentError(
              'request.input.bindable must be a BindableRelationState for operation "$operationType"',
            );
          }
          return <String, dynamic>{
            'type': 'bindable-relation-state',
            'bindable': applyBindableRelationPatch(bindable, patch),
          };
        }
      case 'apply-bindable-relation-patches':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'bindable-relation-states',
            'bindables': applyBindableRelationPatches(
              _asBindableRelationStates(input['bindables']),
              _asBindableRelationPatches(input['patches']),
            ),
          };
        }
      case 'merge-arrow-bound-relations':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'bound-relations',
            'relations': mergeArrowBoundRelationEntries<BoundRelationEntry>(
              entries: _asBoundRelationEntries(input['relations']),
              boundArrowIds: _asStringList(input['boundArrowIds']),
            ),
          };
        }
      case 'are-bound-relations-equal':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'boolean',
            'value': areBoundRelationEntriesEqual<BoundRelationEntry>(
              _asBoundRelationEntries(input['left']),
              _asBoundRelationEntries(input['right']),
            ),
          };
        }
      case 'apply-engine-result':
        {
          final input = _requireInput(rawInput, operationType);
          return <String, dynamic>{
            'type': 'applied-engine-result',
            'value': applyEngineResult(
              ApplyEngineResultInput(
                arrow: _requireArrowState(input['arrow'], operationType),
                bindables: _asBindableRelationStates(input['bindables']),
                result: _requireEngineResult(input['result'], operationType),
                orderedElementIds: input.containsKey('orderedElementIds')
                    ? _asStringList(input['orderedElementIds'])
                    : null,
                anchorElementIdsByBindableId: _asAnchorLookup(
                  input['anchorElementIdsByBindableId'],
                ),
              ),
            ),
          };
        }
      case 'get-core-constants':
        return <String, dynamic>{
          'type': 'core-constants',
          'constants': _toArrowCoreConstantsValue(arrowCoreConstants),
        };
    }
  } catch (error) {
    final operationType = _resolveOperationType(request);
    return <String, dynamic>{
      'type': 'error',
      'error': <String, dynamic>{
        'code': 'operation-failed',
        'message': _toOperationFailureMessage(operationType, error),
        'operationType': operationType,
      },
    };
  }

  final operationType = _resolveOperationType(request);
  return <String, dynamic>{
    'type': 'error',
    'error': <String, dynamic>{
      'code': 'unknown-operation',
      'message': 'Unsupported arrow operation: $operationType',
      'operationType': operationType,
    },
  };
}

ArrowOperationResponse executeArrowOperationSafe(Object? request) {
  final validation = validateArrowOperationEnvelope(request);
  if (!validation.valid) {
    return <String, dynamic>{
      'type': 'error',
      'error': <String, dynamic>{
        'code': 'invalid-request',
        'message': _toInvalidRequestMessage(validation.violations),
        'operationType': validation.operationType,
      },
    };
  }
  return executeArrowOperation(_asStringDynamicMap(request)!);
}
