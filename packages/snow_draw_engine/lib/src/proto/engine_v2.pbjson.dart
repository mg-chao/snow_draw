// This is a generated file - do not edit.
//
// Generated from engine_v2.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports
// ignore_for_file: unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use capabilityDescriptor instead')
const Capability$json = {
  '1': 'Capability',
  '2': [
    {'1': 'CAPABILITY_UNSPECIFIED', '2': 0},
    {'1': 'CAPABILITY_EVENT_STREAM', '2': 1},
    {'1': 'CAPABILITY_FRAME_PLAN', '2': 2},
    {'1': 'CAPABILITY_DISPATCH_BATCH', '2': 3},
    {'1': 'CAPABILITY_INPUT_PIPELINE', '2': 4},
    {'1': 'CAPABILITY_TEXT_METRICS_HOST', '2': 5},
  ],
};

/// Descriptor for `Capability`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List capabilityDescriptor = $convert.base64Decode(
    'CgpDYXBhYmlsaXR5EhoKFkNBUEFCSUxJVFlfVU5TUEVDSUZJRUQQABIbChdDQVBBQklMSVRZX0'
    'VWRU5UX1NUUkVBTRABEhkKFUNBUEFCSUxJVFlfRlJBTUVfUExBThACEh0KGUNBUEFCSUxJVFlf'
    'RElTUEFUQ0hfQkFUQ0gQAxIdChlDQVBBQklMSVRZX0lOUFVUX1BJUEVMSU5FEAQSIAocQ0FQQU'
    'JJTElUWV9URVhUX01FVFJJQ1NfSE9TVBAF');

@$core.Deprecated('Use elementTypeDescriptor instead')
const ElementType$json = {
  '1': 'ElementType',
  '2': [
    {'1': 'ELEMENT_TYPE_UNKNOWN', '2': 0},
    {'1': 'ELEMENT_TYPE_RECTANGLE', '2': 1},
    {'1': 'ELEMENT_TYPE_ARROW', '2': 2},
    {'1': 'ELEMENT_TYPE_LINE', '2': 3},
    {'1': 'ELEMENT_TYPE_FREE_DRAW', '2': 4},
    {'1': 'ELEMENT_TYPE_FILTER', '2': 5},
    {'1': 'ELEMENT_TYPE_HIGHLIGHT', '2': 6},
    {'1': 'ELEMENT_TYPE_TEXT', '2': 7},
    {'1': 'ELEMENT_TYPE_SERIAL_NUMBER', '2': 8},
  ],
};

/// Descriptor for `ElementType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List elementTypeDescriptor = $convert.base64Decode(
    'CgtFbGVtZW50VHlwZRIYChRFTEVNRU5UX1RZUEVfVU5LTk9XThAAEhoKFkVMRU1FTlRfVFlQRV'
    '9SRUNUQU5HTEUQARIWChJFTEVNRU5UX1RZUEVfQVJST1cQAhIVChFFTEVNRU5UX1RZUEVfTElO'
    'RRADEhoKFkVMRU1FTlRfVFlQRV9GUkVFX0RSQVcQBBIXChNFTEVNRU5UX1RZUEVfRklMVEVSEA'
    'USGgoWRUxFTUVOVF9UWVBFX0hJR0hMSUdIVBAGEhUKEUVMRU1FTlRfVFlQRV9URVhUEAcSHgoa'
    'RUxFTUVOVF9UWVBFX1NFUklBTF9OVU1CRVIQCA==');

@$core.Deprecated('Use interactionModeDescriptor instead')
const InteractionMode$json = {
  '1': 'InteractionMode',
  '2': [
    {'1': 'INTERACTION_MODE_IDLE', '2': 0},
    {'1': 'INTERACTION_MODE_CREATING', '2': 1},
    {'1': 'INTERACTION_MODE_EDITING', '2': 2},
    {'1': 'INTERACTION_MODE_TEXT_EDITING', '2': 3},
    {'1': 'INTERACTION_MODE_BOX_SELECTING', '2': 4},
    {'1': 'INTERACTION_MODE_DRAG_PENDING', '2': 5},
  ],
};

/// Descriptor for `InteractionMode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List interactionModeDescriptor = $convert.base64Decode(
    'Cg9JbnRlcmFjdGlvbk1vZGUSGQoVSU5URVJBQ1RJT05fTU9ERV9JRExFEAASHQoZSU5URVJBQ1'
    'RJT05fTU9ERV9DUkVBVElORxABEhwKGElOVEVSQUNUSU9OX01PREVfRURJVElORxACEiEKHUlO'
    'VEVSQUNUSU9OX01PREVfVEVYVF9FRElUSU5HEAMSIgoeSU5URVJBQ1RJT05fTU9ERV9CT1hfU0'
    'VMRUNUSU5HEAQSIQodSU5URVJBQ1RJT05fTU9ERV9EUkFHX1BFTkRJTkcQBQ==');

@$core.Deprecated('Use frameTaskKindDescriptor instead')
const FrameTaskKind$json = {
  '1': 'FrameTaskKind',
  '2': [
    {'1': 'FRAME_TASK_KIND_UNKNOWN', '2': 0},
    {'1': 'FRAME_TASK_KIND_RECTANGLE', '2': 1},
    {'1': 'FRAME_TASK_KIND_LINE', '2': 2},
    {'1': 'FRAME_TASK_KIND_ARROW', '2': 3},
    {'1': 'FRAME_TASK_KIND_FREE_DRAW', '2': 4},
    {'1': 'FRAME_TASK_KIND_TEXT', '2': 5},
    {'1': 'FRAME_TASK_KIND_SERIAL_NUMBER', '2': 6},
    {'1': 'FRAME_TASK_KIND_HIGHLIGHT', '2': 7},
    {'1': 'FRAME_TASK_KIND_FILTER', '2': 8},
    {'1': 'FRAME_TASK_KIND_BACKGROUND', '2': 9},
    {'1': 'FRAME_TASK_KIND_GRID', '2': 10},
    {'1': 'FRAME_TASK_KIND_SELECTION_OUTLINE', '2': 11},
    {'1': 'FRAME_TASK_KIND_SELECTION_CONTROLS', '2': 12},
    {'1': 'FRAME_TASK_KIND_ARROW_POINT_OVERLAY', '2': 13},
    {'1': 'FRAME_TASK_KIND_ARROW_BINDING_HIGHLIGHT', '2': 14},
    {'1': 'FRAME_TASK_KIND_HOVER_OUTLINE', '2': 15},
    {'1': 'FRAME_TASK_KIND_SNAP_GUIDES', '2': 16},
    {'1': 'FRAME_TASK_KIND_BOX_SELECTION', '2': 17},
    {'1': 'FRAME_TASK_KIND_HIGHLIGHT_MASK', '2': 18},
    {'1': 'FRAME_TASK_KIND_WATERMARK', '2': 19},
  ],
};

/// Descriptor for `FrameTaskKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List frameTaskKindDescriptor = $convert.base64Decode(
    'Cg1GcmFtZVRhc2tLaW5kEhsKF0ZSQU1FX1RBU0tfS0lORF9VTktOT1dOEAASHQoZRlJBTUVfVE'
    'FTS19LSU5EX1JFQ1RBTkdMRRABEhgKFEZSQU1FX1RBU0tfS0lORF9MSU5FEAISGQoVRlJBTUVf'
    'VEFTS19LSU5EX0FSUk9XEAMSHQoZRlJBTUVfVEFTS19LSU5EX0ZSRUVfRFJBVxAEEhgKFEZSQU'
    '1FX1RBU0tfS0lORF9URVhUEAUSIQodRlJBTUVfVEFTS19LSU5EX1NFUklBTF9OVU1CRVIQBhId'
    'ChlGUkFNRV9UQVNLX0tJTkRfSElHSExJR0hUEAcSGgoWRlJBTUVfVEFTS19LSU5EX0ZJTFRFUh'
    'AIEh4KGkZSQU1FX1RBU0tfS0lORF9CQUNLR1JPVU5EEAkSGAoURlJBTUVfVEFTS19LSU5EX0dS'
    'SUQQChIlCiFGUkFNRV9UQVNLX0tJTkRfU0VMRUNUSU9OX09VVExJTkUQCxImCiJGUkFNRV9UQV'
    'NLX0tJTkRfU0VMRUNUSU9OX0NPTlRST0xTEAwSJwojRlJBTUVfVEFTS19LSU5EX0FSUk9XX1BP'
    'SU5UX09WRVJMQVkQDRIrCidGUkFNRV9UQVNLX0tJTkRfQVJST1dfQklORElOR19ISUdITElHSF'
    'QQDhIhCh1GUkFNRV9UQVNLX0tJTkRfSE9WRVJfT1VUTElORRAPEh8KG0ZSQU1FX1RBU0tfS0lO'
    'RF9TTkFQX0dVSURFUxAQEiEKHUZSQU1FX1RBU0tfS0lORF9CT1hfU0VMRUNUSU9OEBESIgoeRl'
    'JBTUVfVEFTS19LSU5EX0hJR0hMSUdIVF9NQVNLEBISHQoZRlJBTUVfVEFTS19LSU5EX1dBVEVS'
    'TUFSSxAT');

@$core.Deprecated('Use engineEventKindDescriptor instead')
const EngineEventKind$json = {
  '1': 'EngineEventKind',
  '2': [
    {'1': 'ENGINE_EVENT_KIND_UNKNOWN', '2': 0},
    {'1': 'ENGINE_EVENT_KIND_STATE_CHANGED', '2': 1},
    {'1': 'ENGINE_EVENT_KIND_VALIDATION_FAILED', '2': 2},
    {'1': 'ENGINE_EVENT_KIND_ERROR', '2': 3},
    {'1': 'ENGINE_EVENT_KIND_HISTORY_CHANGED', '2': 4},
    {'1': 'ENGINE_EVENT_KIND_DEBUG', '2': 5},
  ],
};

/// Descriptor for `EngineEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List engineEventKindDescriptor = $convert.base64Decode(
    'Cg9FbmdpbmVFdmVudEtpbmQSHQoZRU5HSU5FX0VWRU5UX0tJTkRfVU5LTk9XThAAEiMKH0VOR0'
    'lORV9FVkVOVF9LSU5EX1NUQVRFX0NIQU5HRUQQARInCiNFTkdJTkVfRVZFTlRfS0lORF9WQUxJ'
    'REFUSU9OX0ZBSUxFRBACEhsKF0VOR0lORV9FVkVOVF9LSU5EX0VSUk9SEAMSJQohRU5HSU5FX0'
    'VWRU5UX0tJTkRfSElTVE9SWV9DSEFOR0VEEAQSGwoXRU5HSU5FX0VWRU5UX0tJTkRfREVCVUcQ'
    'BQ==');

@$core.Deprecated('Use pointerPhaseDescriptor instead')
const PointerPhase$json = {
  '1': 'PointerPhase',
  '2': [
    {'1': 'POINTER_PHASE_UNSPECIFIED', '2': 0},
    {'1': 'POINTER_PHASE_DOWN', '2': 1},
    {'1': 'POINTER_PHASE_MOVE', '2': 2},
    {'1': 'POINTER_PHASE_UP', '2': 3},
    {'1': 'POINTER_PHASE_CANCEL', '2': 4},
    {'1': 'POINTER_PHASE_HOVER', '2': 5},
  ],
};

/// Descriptor for `PointerPhase`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List pointerPhaseDescriptor = $convert.base64Decode(
    'CgxQb2ludGVyUGhhc2USHQoZUE9JTlRFUl9QSEFTRV9VTlNQRUNJRklFRBAAEhYKElBPSU5URV'
    'JfUEhBU0VfRE9XThABEhYKElBPSU5URVJfUEhBU0VfTU9WRRACEhQKEFBPSU5URVJfUEhBU0Vf'
    'VVAQAxIYChRQT0lOVEVSX1BIQVNFX0NBTkNFTBAEEhcKE1BPSU5URVJfUEhBU0VfSE9WRVIQBQ'
    '==');

@$core.Deprecated('Use drawPointDescriptor instead')
const DrawPoint$json = {
  '1': 'DrawPoint',
  '2': [
    {'1': 'x', '3': 1, '4': 1, '5': 1, '10': 'x'},
    {'1': 'y', '3': 2, '4': 1, '5': 1, '10': 'y'},
    {'1': 'pressure', '3': 3, '4': 1, '5': 1, '10': 'pressure'},
    {'1': 'timestamp_us', '3': 4, '4': 1, '5': 4, '10': 'timestampUs'},
  ],
};

/// Descriptor for `DrawPoint`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List drawPointDescriptor = $convert.base64Decode(
    'CglEcmF3UG9pbnQSDAoBeBgBIAEoAVIBeBIMCgF5GAIgASgBUgF5EhoKCHByZXNzdXJlGAMgAS'
    'gBUghwcmVzc3VyZRIhCgx0aW1lc3RhbXBfdXMYBCABKARSC3RpbWVzdGFtcFVz');

@$core.Deprecated('Use drawRectDescriptor instead')
const DrawRect$json = {
  '1': 'DrawRect',
  '2': [
    {'1': 'min_x', '3': 1, '4': 1, '5': 1, '10': 'minX'},
    {'1': 'min_y', '3': 2, '4': 1, '5': 1, '10': 'minY'},
    {'1': 'max_x', '3': 3, '4': 1, '5': 1, '10': 'maxX'},
    {'1': 'max_y', '3': 4, '4': 1, '5': 1, '10': 'maxY'},
  ],
};

/// Descriptor for `DrawRect`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List drawRectDescriptor = $convert.base64Decode(
    'CghEcmF3UmVjdBITCgVtaW5feBgBIAEoAVIEbWluWBITCgVtaW5feRgCIAEoAVIEbWluWRITCg'
    'VtYXhfeBgDIAEoAVIEbWF4WBITCgVtYXhfeRgEIAEoAVIEbWF4WQ==');

@$core.Deprecated('Use cameraStateDescriptor instead')
const CameraState$json = {
  '1': 'CameraState',
  '2': [
    {
      '1': 'position',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.DrawPoint',
      '10': 'position'
    },
    {'1': 'zoom', '3': 2, '4': 1, '5': 1, '10': 'zoom'},
  ],
};

/// Descriptor for `CameraState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List cameraStateDescriptor = $convert.base64Decode(
    'CgtDYW1lcmFTdGF0ZRI5Cghwb3NpdGlvbhgBIAEoCzIdLnNub3dkcmF3LmVuZ2luZS52Mi5Ecm'
    'F3UG9pbnRSCHBvc2l0aW9uEhIKBHpvb20YAiABKAFSBHpvb20=');

@$core.Deprecated('Use rectanglePayloadDescriptor instead')
const RectanglePayload$json = {
  '1': 'RectanglePayload',
  '2': [
    {'1': 'color_argb32', '3': 1, '4': 1, '5': 4, '10': 'colorArgb32'},
    {'1': 'fill_color_argb32', '3': 2, '4': 1, '5': 4, '10': 'fillColorArgb32'},
    {'1': 'stroke_width', '3': 3, '4': 1, '5': 1, '10': 'strokeWidth'},
  ],
};

/// Descriptor for `RectanglePayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List rectanglePayloadDescriptor = $convert.base64Decode(
    'ChBSZWN0YW5nbGVQYXlsb2FkEiEKDGNvbG9yX2FyZ2IzMhgBIAEoBFILY29sb3JBcmdiMzISKg'
    'oRZmlsbF9jb2xvcl9hcmdiMzIYAiABKARSD2ZpbGxDb2xvckFyZ2IzMhIhCgxzdHJva2Vfd2lk'
    'dGgYAyABKAFSC3N0cm9rZVdpZHRo');

@$core.Deprecated('Use arrowPayloadDescriptor instead')
const ArrowPayload$json = {
  '1': 'ArrowPayload',
  '2': [
    {
      '1': 'points',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.snowdraw.engine.v2.DrawPoint',
      '10': 'points'
    },
    {'1': 'arrow_type', '3': 2, '4': 1, '5': 9, '10': 'arrowType'},
  ],
};

/// Descriptor for `ArrowPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List arrowPayloadDescriptor = $convert.base64Decode(
    'CgxBcnJvd1BheWxvYWQSNQoGcG9pbnRzGAEgAygLMh0uc25vd2RyYXcuZW5naW5lLnYyLkRyYX'
    'dQb2ludFIGcG9pbnRzEh0KCmFycm93X3R5cGUYAiABKAlSCWFycm93VHlwZQ==');

@$core.Deprecated('Use linePayloadDescriptor instead')
const LinePayload$json = {
  '1': 'LinePayload',
  '2': [
    {
      '1': 'points',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.snowdraw.engine.v2.DrawPoint',
      '10': 'points'
    },
    {'1': 'line_type', '3': 2, '4': 1, '5': 9, '10': 'lineType'},
  ],
};

/// Descriptor for `LinePayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List linePayloadDescriptor = $convert.base64Decode(
    'CgtMaW5lUGF5bG9hZBI1CgZwb2ludHMYASADKAsyHS5zbm93ZHJhdy5lbmdpbmUudjIuRHJhd1'
    'BvaW50UgZwb2ludHMSGwoJbGluZV90eXBlGAIgASgJUghsaW5lVHlwZQ==');

@$core.Deprecated('Use freeDrawPayloadDescriptor instead')
const FreeDrawPayload$json = {
  '1': 'FreeDrawPayload',
  '2': [
    {
      '1': 'points',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.snowdraw.engine.v2.DrawPoint',
      '10': 'points'
    },
  ],
};

/// Descriptor for `FreeDrawPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List freeDrawPayloadDescriptor = $convert.base64Decode(
    'Cg9GcmVlRHJhd1BheWxvYWQSNQoGcG9pbnRzGAEgAygLMh0uc25vd2RyYXcuZW5naW5lLnYyLk'
    'RyYXdQb2ludFIGcG9pbnRz');

@$core.Deprecated('Use filterPayloadDescriptor instead')
const FilterPayload$json = {
  '1': 'FilterPayload',
  '2': [
    {'1': 'filter_type', '3': 1, '4': 1, '5': 9, '10': 'filterType'},
    {'1': 'strength', '3': 2, '4': 1, '5': 1, '10': 'strength'},
  ],
};

/// Descriptor for `FilterPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List filterPayloadDescriptor = $convert.base64Decode(
    'Cg1GaWx0ZXJQYXlsb2FkEh8KC2ZpbHRlcl90eXBlGAEgASgJUgpmaWx0ZXJUeXBlEhoKCHN0cm'
    'VuZ3RoGAIgASgBUghzdHJlbmd0aA==');

@$core.Deprecated('Use highlightPayloadDescriptor instead')
const HighlightPayload$json = {
  '1': 'HighlightPayload',
  '2': [
    {'1': 'shape', '3': 1, '4': 1, '5': 9, '10': 'shape'},
    {'1': 'color_argb32', '3': 2, '4': 1, '5': 4, '10': 'colorArgb32'},
  ],
};

/// Descriptor for `HighlightPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List highlightPayloadDescriptor = $convert.base64Decode(
    'ChBIaWdobGlnaHRQYXlsb2FkEhQKBXNoYXBlGAEgASgJUgVzaGFwZRIhCgxjb2xvcl9hcmdiMz'
    'IYAiABKARSC2NvbG9yQXJnYjMy');

@$core.Deprecated('Use textPayloadDescriptor instead')
const TextPayload$json = {
  '1': 'TextPayload',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'font_size', '3': 2, '4': 1, '5': 1, '10': 'fontSize'},
    {'1': 'font_family', '3': 3, '4': 1, '5': 9, '10': 'fontFamily'},
  ],
};

/// Descriptor for `TextPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List textPayloadDescriptor = $convert.base64Decode(
    'CgtUZXh0UGF5bG9hZBISCgR0ZXh0GAEgASgJUgR0ZXh0EhsKCWZvbnRfc2l6ZRgCIAEoAVIIZm'
    '9udFNpemUSHwoLZm9udF9mYW1pbHkYAyABKAlSCmZvbnRGYW1pbHk=');

@$core.Deprecated('Use serialNumberPayloadDescriptor instead')
const SerialNumberPayload$json = {
  '1': 'SerialNumberPayload',
  '2': [
    {'1': 'number', '3': 1, '4': 1, '5': 5, '10': 'number'},
    {'1': 'text_element_id', '3': 2, '4': 1, '5': 9, '10': 'textElementId'},
  ],
};

/// Descriptor for `SerialNumberPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List serialNumberPayloadDescriptor = $convert.base64Decode(
    'ChNTZXJpYWxOdW1iZXJQYXlsb2FkEhYKBm51bWJlchgBIAEoBVIGbnVtYmVyEiYKD3RleHRfZW'
    'xlbWVudF9pZBgCIAEoCVINdGV4dEVsZW1lbnRJZA==');

@$core.Deprecated('Use elementPayloadDescriptor instead')
const ElementPayload$json = {
  '1': 'ElementPayload',
  '2': [
    {
      '1': 'rectangle',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.RectanglePayload',
      '9': 0,
      '10': 'rectangle'
    },
    {
      '1': 'arrow',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.ArrowPayload',
      '9': 0,
      '10': 'arrow'
    },
    {
      '1': 'line',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.LinePayload',
      '9': 0,
      '10': 'line'
    },
    {
      '1': 'free_draw',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.FreeDrawPayload',
      '9': 0,
      '10': 'freeDraw'
    },
    {
      '1': 'filter',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.FilterPayload',
      '9': 0,
      '10': 'filter'
    },
    {
      '1': 'highlight',
      '3': 6,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.HighlightPayload',
      '9': 0,
      '10': 'highlight'
    },
    {
      '1': 'text',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.TextPayload',
      '9': 0,
      '10': 'text'
    },
    {
      '1': 'serial_number',
      '3': 8,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.SerialNumberPayload',
      '9': 0,
      '10': 'serialNumber'
    },
    {
      '1': 'raw_json_payload',
      '3': 100,
      '4': 1,
      '5': 12,
      '9': 0,
      '10': 'rawJsonPayload'
    },
    {
      '1': 'raw_binary_payload',
      '3': 101,
      '4': 1,
      '5': 12,
      '9': 0,
      '10': 'rawBinaryPayload'
    },
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `ElementPayload`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List elementPayloadDescriptor = $convert.base64Decode(
    'Cg5FbGVtZW50UGF5bG9hZBJECglyZWN0YW5nbGUYASABKAsyJC5zbm93ZHJhdy5lbmdpbmUudj'
    'IuUmVjdGFuZ2xlUGF5bG9hZEgAUglyZWN0YW5nbGUSOAoFYXJyb3cYAiABKAsyIC5zbm93ZHJh'
    'dy5lbmdpbmUudjIuQXJyb3dQYXlsb2FkSABSBWFycm93EjUKBGxpbmUYAyABKAsyHy5zbm93ZH'
    'Jhdy5lbmdpbmUudjIuTGluZVBheWxvYWRIAFIEbGluZRJCCglmcmVlX2RyYXcYBCABKAsyIy5z'
    'bm93ZHJhdy5lbmdpbmUudjIuRnJlZURyYXdQYXlsb2FkSABSCGZyZWVEcmF3EjsKBmZpbHRlch'
    'gFIAEoCzIhLnNub3dkcmF3LmVuZ2luZS52Mi5GaWx0ZXJQYXlsb2FkSABSBmZpbHRlchJECglo'
    'aWdobGlnaHQYBiABKAsyJC5zbm93ZHJhdy5lbmdpbmUudjIuSGlnaGxpZ2h0UGF5bG9hZEgAUg'
    'loaWdobGlnaHQSNQoEdGV4dBgHIAEoCzIfLnNub3dkcmF3LmVuZ2luZS52Mi5UZXh0UGF5bG9h'
    'ZEgAUgR0ZXh0Ek4KDXNlcmlhbF9udW1iZXIYCCABKAsyJy5zbm93ZHJhdy5lbmdpbmUudjIuU2'
    'VyaWFsTnVtYmVyUGF5bG9hZEgAUgxzZXJpYWxOdW1iZXISKgoQcmF3X2pzb25fcGF5bG9hZBhk'
    'IAEoDEgAUg5yYXdKc29uUGF5bG9hZBIuChJyYXdfYmluYXJ5X3BheWxvYWQYZSABKAxIAFIQcm'
    'F3QmluYXJ5UGF5bG9hZEIJCgdwYXlsb2Fk');

@$core.Deprecated('Use elementDescriptor instead')
const Element$json = {
  '1': 'Element',
  '2': [
    {'1': 'id', '3': 1, '4': 1, '5': 9, '10': 'id'},
    {
      '1': 'element_type',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.snowdraw.engine.v2.ElementType',
      '10': 'elementType'
    },
    {
      '1': 'rect',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.DrawRect',
      '10': 'rect'
    },
    {'1': 'rotation', '3': 4, '4': 1, '5': 1, '10': 'rotation'},
    {'1': 'opacity', '3': 5, '4': 1, '5': 1, '10': 'opacity'},
    {'1': 'z_index', '3': 6, '4': 1, '5': 5, '10': 'zIndex'},
    {
      '1': 'payload',
      '3': 7,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.ElementPayload',
      '10': 'payload'
    },
  ],
};

/// Descriptor for `Element`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List elementDescriptor = $convert.base64Decode(
    'CgdFbGVtZW50Eg4KAmlkGAEgASgJUgJpZBJCCgxlbGVtZW50X3R5cGUYAiABKA4yHy5zbm93ZH'
    'Jhdy5lbmdpbmUudjIuRWxlbWVudFR5cGVSC2VsZW1lbnRUeXBlEjAKBHJlY3QYAyABKAsyHC5z'
    'bm93ZHJhdy5lbmdpbmUudjIuRHJhd1JlY3RSBHJlY3QSGgoIcm90YXRpb24YBCABKAFSCHJvdG'
    'F0aW9uEhgKB29wYWNpdHkYBSABKAFSB29wYWNpdHkSFwoHel9pbmRleBgGIAEoBVIGekluZGV4'
    'EjwKB3BheWxvYWQYByABKAsyIi5zbm93ZHJhdy5lbmdpbmUudjIuRWxlbWVudFBheWxvYWRSB3'
    'BheWxvYWQ=');

@$core.Deprecated('Use engineSnapshotDescriptor instead')
const EngineSnapshot$json = {
  '1': 'EngineSnapshot',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'document_version', '3': 2, '4': 1, '5': 4, '10': 'documentVersion'},
    {
      '1': 'selection_version',
      '3': 3,
      '4': 1,
      '5': 4,
      '10': 'selectionVersion'
    },
    {
      '1': 'interaction_mode',
      '3': 4,
      '4': 1,
      '5': 14,
      '6': '.snowdraw.engine.v2.InteractionMode',
      '10': 'interactionMode'
    },
    {
      '1': 'camera',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.CameraState',
      '10': 'camera'
    },
    {
      '1': 'elements',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.snowdraw.engine.v2.Element',
      '10': 'elements'
    },
    {'1': 'selected_ids', '3': 7, '4': 3, '5': 9, '10': 'selectedIds'},
    {'1': 'history_undo_len', '3': 8, '4': 1, '5': 4, '10': 'historyUndoLen'},
    {'1': 'history_redo_len', '3': 9, '4': 1, '5': 4, '10': 'historyRedoLen'},
    {
      '1': 'global_elements_payload',
      '3': 10,
      '4': 1,
      '5': 12,
      '10': 'globalElementsPayload'
    },
  ],
};

/// Descriptor for `EngineSnapshot`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineSnapshotDescriptor = $convert.base64Decode(
    'Cg5FbmdpbmVTbmFwc2hvdBIlCg5zY2hlbWFfdmVyc2lvbhgBIAEoDVINc2NoZW1hVmVyc2lvbh'
    'IpChBkb2N1bWVudF92ZXJzaW9uGAIgASgEUg9kb2N1bWVudFZlcnNpb24SKwoRc2VsZWN0aW9u'
    'X3ZlcnNpb24YAyABKARSEHNlbGVjdGlvblZlcnNpb24STgoQaW50ZXJhY3Rpb25fbW9kZRgEIA'
    'EoDjIjLnNub3dkcmF3LmVuZ2luZS52Mi5JbnRlcmFjdGlvbk1vZGVSD2ludGVyYWN0aW9uTW9k'
    'ZRI3CgZjYW1lcmEYBSABKAsyHy5zbm93ZHJhdy5lbmdpbmUudjIuQ2FtZXJhU3RhdGVSBmNhbW'
    'VyYRI3CghlbGVtZW50cxgGIAMoCzIbLnNub3dkcmF3LmVuZ2luZS52Mi5FbGVtZW50UghlbGVt'
    'ZW50cxIhCgxzZWxlY3RlZF9pZHMYByADKAlSC3NlbGVjdGVkSWRzEigKEGhpc3RvcnlfdW5kb1'
    '9sZW4YCCABKARSDmhpc3RvcnlVbmRvTGVuEigKEGhpc3RvcnlfcmVkb19sZW4YCSABKARSDmhp'
    'c3RvcnlSZWRvTGVuEjYKF2dsb2JhbF9lbGVtZW50c19wYXlsb2FkGAogASgMUhVnbG9iYWxFbG'
    'VtZW50c1BheWxvYWQ=');

@$core.Deprecated('Use frameTaskDescriptor instead')
const FrameTask$json = {
  '1': 'FrameTask',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.snowdraw.engine.v2.FrameTaskKind',
      '10': 'kind'
    },
    {'1': 'element_id', '3': 2, '4': 1, '5': 9, '10': 'elementId'},
    {
      '1': 'element_type',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.snowdraw.engine.v2.ElementType',
      '10': 'elementType'
    },
    {
      '1': 'payload',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.ElementPayload',
      '10': 'payload'
    },
  ],
};

/// Descriptor for `FrameTask`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List frameTaskDescriptor = $convert.base64Decode(
    'CglGcmFtZVRhc2sSNQoEa2luZBgBIAEoDjIhLnNub3dkcmF3LmVuZ2luZS52Mi5GcmFtZVRhc2'
    'tLaW5kUgRraW5kEh0KCmVsZW1lbnRfaWQYAiABKAlSCWVsZW1lbnRJZBJCCgxlbGVtZW50X3R5'
    'cGUYAyABKA4yHy5zbm93ZHJhdy5lbmdpbmUudjIuRWxlbWVudFR5cGVSC2VsZW1lbnRUeXBlEj'
    'wKB3BheWxvYWQYBCABKAsyIi5zbm93ZHJhdy5lbmdpbmUudjIuRWxlbWVudFBheWxvYWRSB3Bh'
    'eWxvYWQ=');

@$core.Deprecated('Use frameRenderPlanDescriptor instead')
const FrameRenderPlan$json = {
  '1': 'FrameRenderPlan',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {
      '1': 'camera',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.CameraState',
      '10': 'camera'
    },
    {'1': 'scale_factor', '3': 3, '4': 1, '5': 1, '10': 'scaleFactor'},
    {'1': 'locale_tag', '3': 4, '4': 1, '5': 9, '10': 'localeTag'},
    {
      '1': 'tasks',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.snowdraw.engine.v2.FrameTask',
      '10': 'tasks'
    },
  ],
};

/// Descriptor for `FrameRenderPlan`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List frameRenderPlanDescriptor = $convert.base64Decode(
    'Cg9GcmFtZVJlbmRlclBsYW4SJQoOc2NoZW1hX3ZlcnNpb24YASABKA1SDXNjaGVtYVZlcnNpb2'
    '4SNwoGY2FtZXJhGAIgASgLMh8uc25vd2RyYXcuZW5naW5lLnYyLkNhbWVyYVN0YXRlUgZjYW1l'
    'cmESIQoMc2NhbGVfZmFjdG9yGAMgASgBUgtzY2FsZUZhY3RvchIdCgpsb2NhbGVfdGFnGAQgAS'
    'gJUglsb2NhbGVUYWcSMwoFdGFza3MYBSADKAsyHS5zbm93ZHJhdy5lbmdpbmUudjIuRnJhbWVU'
    'YXNrUgV0YXNrcw==');

@$core.Deprecated('Use engineErrorDescriptor instead')
const EngineError$json = {
  '1': 'EngineError',
  '2': [
    {'1': 'code', '3': 1, '4': 1, '5': 13, '10': 'code'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    {'1': 'details', '3': 3, '4': 1, '5': 9, '10': 'details'},
  ],
};

/// Descriptor for `EngineError`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineErrorDescriptor = $convert.base64Decode(
    'CgtFbmdpbmVFcnJvchISCgRjb2RlGAEgASgNUgRjb2RlEhgKB21lc3NhZ2UYAiABKAlSB21lc3'
    'NhZ2USGAoHZGV0YWlscxgDIAEoCVIHZGV0YWlscw==');

@$core.Deprecated('Use engineEventDescriptor instead')
const EngineEvent$json = {
  '1': 'EngineEvent',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.snowdraw.engine.v2.EngineEventKind',
      '10': 'kind'
    },
    {'1': 'sequence', '3': 2, '4': 1, '5': 4, '10': 'sequence'},
    {
      '1': 'error',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.EngineError',
      '9': 0,
      '10': 'error'
    },
    {'1': 'blob', '3': 11, '4': 1, '5': 12, '9': 0, '10': 'blob'},
    {'1': 'message', '3': 12, '4': 1, '5': 9, '9': 0, '10': 'message'},
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `EngineEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineEventDescriptor = $convert.base64Decode(
    'CgtFbmdpbmVFdmVudBI3CgRraW5kGAEgASgOMiMuc25vd2RyYXcuZW5naW5lLnYyLkVuZ2luZU'
    'V2ZW50S2luZFIEa2luZBIaCghzZXF1ZW5jZRgCIAEoBFIIc2VxdWVuY2USNwoFZXJyb3IYCiAB'
    'KAsyHy5zbm93ZHJhdy5lbmdpbmUudjIuRW5naW5lRXJyb3JIAFIFZXJyb3ISFAoEYmxvYhgLIA'
    'EoDEgAUgRibG9iEhoKB21lc3NhZ2UYDCABKAlIAFIHbWVzc2FnZUIJCgdwYXlsb2Fk');

@$core.Deprecated('Use engineInitRequestDescriptor instead')
const EngineInitRequest$json = {
  '1': 'EngineInitRequest',
  '2': [
    {
      '1': 'requested_abi_version',
      '3': 1,
      '4': 1,
      '5': 13,
      '10': 'requestedAbiVersion'
    },
    {'1': 'schema_version', '3': 2, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'locale_tag', '3': 3, '4': 1, '5': 9, '10': 'localeTag'},
    {'1': 'scale_factor', '3': 4, '4': 1, '5': 1, '10': 'scaleFactor'},
    {
      '1': 'requested_capabilities_mask',
      '3': 5,
      '4': 1,
      '5': 4,
      '10': 'requestedCapabilitiesMask'
    },
    {
      '1': 'deterministic_seed',
      '3': 6,
      '4': 1,
      '5': 4,
      '10': 'deterministicSeed'
    },
  ],
};

/// Descriptor for `EngineInitRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineInitRequestDescriptor = $convert.base64Decode(
    'ChFFbmdpbmVJbml0UmVxdWVzdBIyChVyZXF1ZXN0ZWRfYWJpX3ZlcnNpb24YASABKA1SE3JlcX'
    'Vlc3RlZEFiaVZlcnNpb24SJQoOc2NoZW1hX3ZlcnNpb24YAiABKA1SDXNjaGVtYVZlcnNpb24S'
    'HQoKbG9jYWxlX3RhZxgDIAEoCVIJbG9jYWxlVGFnEiEKDHNjYWxlX2ZhY3RvchgEIAEoAVILc2'
    'NhbGVGYWN0b3ISPgobcmVxdWVzdGVkX2NhcGFiaWxpdGllc19tYXNrGAUgASgEUhlyZXF1ZXN0'
    'ZWRDYXBhYmlsaXRpZXNNYXNrEi0KEmRldGVybWluaXN0aWNfc2VlZBgGIAEoBFIRZGV0ZXJtaW'
    '5pc3RpY1NlZWQ=');

@$core.Deprecated('Use engineInitAckDescriptor instead')
const EngineInitAck$json = {
  '1': 'EngineInitAck',
  '2': [
    {'1': 'abi_version', '3': 1, '4': 1, '5': 13, '10': 'abiVersion'},
    {'1': 'schema_version', '3': 2, '4': 1, '5': 13, '10': 'schemaVersion'},
    {
      '1': 'granted_capabilities_mask',
      '3': 3,
      '4': 1,
      '5': 4,
      '10': 'grantedCapabilitiesMask'
    },
    {'1': 'message', '3': 4, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `EngineInitAck`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineInitAckDescriptor = $convert.base64Decode(
    'Cg1FbmdpbmVJbml0QWNrEh8KC2FiaV92ZXJzaW9uGAEgASgNUgphYmlWZXJzaW9uEiUKDnNjaG'
    'VtYV92ZXJzaW9uGAIgASgNUg1zY2hlbWFWZXJzaW9uEjoKGWdyYW50ZWRfY2FwYWJpbGl0aWVz'
    'X21hc2sYAyABKARSF2dyYW50ZWRDYXBhYmlsaXRpZXNNYXNrEhgKB21lc3NhZ2UYBCABKAlSB2'
    '1lc3NhZ2U=');

@$core.Deprecated('Use commandEventDescriptor instead')
const CommandEvent$json = {
  '1': 'CommandEvent',
  '2': [
    {'1': 'command_bytes', '3': 1, '4': 1, '5': 12, '10': 'commandBytes'},
  ],
};

/// Descriptor for `CommandEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List commandEventDescriptor = $convert.base64Decode(
    'CgxDb21tYW5kRXZlbnQSIwoNY29tbWFuZF9ieXRlcxgBIAEoDFIMY29tbWFuZEJ5dGVz');

@$core.Deprecated('Use pointerEventDescriptor instead')
const PointerEvent$json = {
  '1': 'PointerEvent',
  '2': [
    {'1': 'pointer_id', '3': 1, '4': 1, '5': 4, '10': 'pointerId'},
    {
      '1': 'phase',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.snowdraw.engine.v2.PointerPhase',
      '10': 'phase'
    },
    {
      '1': 'position',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.DrawPoint',
      '10': 'position'
    },
    {'1': 'buttons', '3': 4, '4': 1, '5': 13, '10': 'buttons'},
    {'1': 'modifiers', '3': 5, '4': 1, '5': 13, '10': 'modifiers'},
  ],
};

/// Descriptor for `PointerEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pointerEventDescriptor = $convert.base64Decode(
    'CgxQb2ludGVyRXZlbnQSHQoKcG9pbnRlcl9pZBgBIAEoBFIJcG9pbnRlcklkEjYKBXBoYXNlGA'
    'IgASgOMiAuc25vd2RyYXcuZW5naW5lLnYyLlBvaW50ZXJQaGFzZVIFcGhhc2USOQoIcG9zaXRp'
    'b24YAyABKAsyHS5zbm93ZHJhdy5lbmdpbmUudjIuRHJhd1BvaW50Ughwb3NpdGlvbhIYCgdidX'
    'R0b25zGAQgASgNUgdidXR0b25zEhwKCW1vZGlmaWVycxgFIAEoDVIJbW9kaWZpZXJz');

@$core.Deprecated('Use keyboardEventDescriptor instead')
const KeyboardEvent$json = {
  '1': 'KeyboardEvent',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'down', '3': 2, '4': 1, '5': 8, '10': 'down'},
    {'1': 'modifiers', '3': 3, '4': 1, '5': 13, '10': 'modifiers'},
  ],
};

/// Descriptor for `KeyboardEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List keyboardEventDescriptor = $convert.base64Decode(
    'Cg1LZXlib2FyZEV2ZW50EhAKA2tleRgBIAEoCVIDa2V5EhIKBGRvd24YAiABKAhSBGRvd24SHA'
    'oJbW9kaWZpZXJzGAMgASgNUgltb2RpZmllcnM=');

@$core.Deprecated('Use toolEventDescriptor instead')
const ToolEvent$json = {
  '1': 'ToolEvent',
  '2': [
    {'1': 'tool_id', '3': 1, '4': 1, '5': 9, '10': 'toolId'},
    {'1': 'payload', '3': 2, '4': 1, '5': 12, '10': 'payload'},
  ],
};

/// Descriptor for `ToolEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolEventDescriptor = $convert.base64Decode(
    'CglUb29sRXZlbnQSFwoHdG9vbF9pZBgBIAEoCVIGdG9vbElkEhgKB3BheWxvYWQYAiABKAxSB3'
    'BheWxvYWQ=');

@$core.Deprecated('Use configEventDescriptor instead')
const ConfigEvent$json = {
  '1': 'ConfigEvent',
  '2': [
    {'1': 'locale_tag', '3': 1, '4': 1, '5': 9, '10': 'localeTag'},
    {'1': 'scale_factor', '3': 2, '4': 1, '5': 1, '10': 'scaleFactor'},
    {'1': 'config_payload', '3': 3, '4': 1, '5': 12, '10': 'configPayload'},
  ],
};

/// Descriptor for `ConfigEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List configEventDescriptor = $convert.base64Decode(
    'CgtDb25maWdFdmVudBIdCgpsb2NhbGVfdGFnGAEgASgJUglsb2NhbGVUYWcSIQoMc2NhbGVfZm'
    'FjdG9yGAIgASgBUgtzY2FsZUZhY3RvchIlCg5jb25maWdfcGF5bG9hZBgDIAEoDFINY29uZmln'
    'UGF5bG9hZA==');

@$core.Deprecated('Use textMetricsRequestDescriptor instead')
const TextMetricsRequest$json = {
  '1': 'TextMetricsRequest',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'font_size', '3': 2, '4': 1, '5': 1, '10': 'fontSize'},
    {'1': 'font_family', '3': 3, '4': 1, '5': 9, '10': 'fontFamily'},
    {'1': 'max_width', '3': 4, '4': 1, '5': 1, '10': 'maxWidth'},
    {'1': 'min_width', '3': 5, '4': 1, '5': 1, '10': 'minWidth'},
    {'1': 'locale_tag', '3': 6, '4': 1, '5': 9, '10': 'localeTag'},
    {'1': 'is_resizing', '3': 7, '4': 1, '5': 8, '10': 'isResizing'},
  ],
};

/// Descriptor for `TextMetricsRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List textMetricsRequestDescriptor = $convert.base64Decode(
    'ChJUZXh0TWV0cmljc1JlcXVlc3QSEgoEdGV4dBgBIAEoCVIEdGV4dBIbCglmb250X3NpemUYAi'
    'ABKAFSCGZvbnRTaXplEh8KC2ZvbnRfZmFtaWx5GAMgASgJUgpmb250RmFtaWx5EhsKCW1heF93'
    'aWR0aBgEIAEoAVIIbWF4V2lkdGgSGwoJbWluX3dpZHRoGAUgASgBUghtaW5XaWR0aBIdCgpsb2'
    'NhbGVfdGFnGAYgASgJUglsb2NhbGVUYWcSHwoLaXNfcmVzaXppbmcYByABKAhSCmlzUmVzaXpp'
    'bmc=');

@$core.Deprecated('Use textMetricsLineDescriptor instead')
const TextMetricsLine$json = {
  '1': 'TextMetricsLine',
  '2': [
    {'1': 'width', '3': 1, '4': 1, '5': 1, '10': 'width'},
    {'1': 'height', '3': 2, '4': 1, '5': 1, '10': 'height'},
  ],
};

/// Descriptor for `TextMetricsLine`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List textMetricsLineDescriptor = $convert.base64Decode(
    'Cg9UZXh0TWV0cmljc0xpbmUSFAoFd2lkdGgYASABKAFSBXdpZHRoEhYKBmhlaWdodBgCIAEoAV'
    'IGaGVpZ2h0');

@$core.Deprecated('Use textMetricsResultDescriptor instead')
const TextMetricsResult$json = {
  '1': 'TextMetricsResult',
  '2': [
    {'1': 'width', '3': 1, '4': 1, '5': 1, '10': 'width'},
    {'1': 'height', '3': 2, '4': 1, '5': 1, '10': 'height'},
    {'1': 'line_height', '3': 3, '4': 1, '5': 1, '10': 'lineHeight'},
    {
      '1': 'lines',
      '3': 4,
      '4': 3,
      '5': 11,
      '6': '.snowdraw.engine.v2.TextMetricsLine',
      '10': 'lines'
    },
  ],
};

/// Descriptor for `TextMetricsResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List textMetricsResultDescriptor = $convert.base64Decode(
    'ChFUZXh0TWV0cmljc1Jlc3VsdBIUCgV3aWR0aBgBIAEoAVIFd2lkdGgSFgoGaGVpZ2h0GAIgAS'
    'gBUgZoZWlnaHQSHwoLbGluZV9oZWlnaHQYAyABKAFSCmxpbmVIZWlnaHQSOQoFbGluZXMYBCAD'
    'KAsyIy5zbm93ZHJhdy5lbmdpbmUudjIuVGV4dE1ldHJpY3NMaW5lUgVsaW5lcw==');

@$core.Deprecated('Use textMetricsResponseDescriptor instead')
const TextMetricsResponse$json = {
  '1': 'TextMetricsResponse',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 4, '10': 'requestId'},
    {'1': 'ok', '3': 2, '4': 1, '5': 8, '10': 'ok'},
    {
      '1': 'metrics',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.TextMetricsResult',
      '10': 'metrics'
    },
    {
      '1': 'error',
      '3': 4,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.EngineError',
      '10': 'error'
    },
  ],
};

/// Descriptor for `TextMetricsResponse`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List textMetricsResponseDescriptor = $convert.base64Decode(
    'ChNUZXh0TWV0cmljc1Jlc3BvbnNlEh0KCnJlcXVlc3RfaWQYASABKARSCXJlcXVlc3RJZBIOCg'
    'JvaxgCIAEoCFICb2sSPwoHbWV0cmljcxgDIAEoCzIlLnNub3dkcmF3LmVuZ2luZS52Mi5UZXh0'
    'TWV0cmljc1Jlc3VsdFIHbWV0cmljcxI1CgVlcnJvchgEIAEoCzIfLnNub3dkcmF3LmVuZ2luZS'
    '52Mi5FbmdpbmVFcnJvclIFZXJyb3I=');

@$core.Deprecated('Use engineInputDescriptor instead')
const EngineInput$json = {
  '1': 'EngineInput',
  '2': [
    {'1': 'sequence', '3': 1, '4': 1, '5': 4, '10': 'sequence'},
    {
      '1': 'command_event',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.CommandEvent',
      '9': 0,
      '10': 'commandEvent'
    },
    {
      '1': 'pointer_event',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.PointerEvent',
      '9': 0,
      '10': 'pointerEvent'
    },
    {
      '1': 'keyboard_event',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.KeyboardEvent',
      '9': 0,
      '10': 'keyboardEvent'
    },
    {
      '1': 'tool_event',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.ToolEvent',
      '9': 0,
      '10': 'toolEvent'
    },
    {
      '1': 'config_event',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.ConfigEvent',
      '9': 0,
      '10': 'configEvent'
    },
    {
      '1': 'text_metrics_response',
      '3': 15,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.TextMetricsResponse',
      '9': 0,
      '10': 'textMetricsResponse'
    },
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `EngineInput`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineInputDescriptor = $convert.base64Decode(
    'CgtFbmdpbmVJbnB1dBIaCghzZXF1ZW5jZRgBIAEoBFIIc2VxdWVuY2USRwoNY29tbWFuZF9ldm'
    'VudBgKIAEoCzIgLnNub3dkcmF3LmVuZ2luZS52Mi5Db21tYW5kRXZlbnRIAFIMY29tbWFuZEV2'
    'ZW50EkcKDXBvaW50ZXJfZXZlbnQYCyABKAsyIC5zbm93ZHJhdy5lbmdpbmUudjIuUG9pbnRlck'
    'V2ZW50SABSDHBvaW50ZXJFdmVudBJKCg5rZXlib2FyZF9ldmVudBgMIAEoCzIhLnNub3dkcmF3'
    'LmVuZ2luZS52Mi5LZXlib2FyZEV2ZW50SABSDWtleWJvYXJkRXZlbnQSPgoKdG9vbF9ldmVudB'
    'gNIAEoCzIdLnNub3dkcmF3LmVuZ2luZS52Mi5Ub29sRXZlbnRIAFIJdG9vbEV2ZW50EkQKDGNv'
    'bmZpZ19ldmVudBgOIAEoCzIfLnNub3dkcmF3LmVuZ2luZS52Mi5Db25maWdFdmVudEgAUgtjb2'
    '5maWdFdmVudBJdChV0ZXh0X21ldHJpY3NfcmVzcG9uc2UYDyABKAsyJy5zbm93ZHJhdy5lbmdp'
    'bmUudjIuVGV4dE1ldHJpY3NSZXNwb25zZUgAUhN0ZXh0TWV0cmljc1Jlc3BvbnNlQgkKB3BheW'
    'xvYWQ=');

@$core.Deprecated('Use pointerHostRequestDescriptor instead')
const PointerHostRequest$json = {
  '1': 'PointerHostRequest',
  '2': [
    {
      '1': 'event',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.PointerEvent',
      '10': 'event'
    },
  ],
};

/// Descriptor for `PointerHostRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List pointerHostRequestDescriptor = $convert.base64Decode(
    'ChJQb2ludGVySG9zdFJlcXVlc3QSNgoFZXZlbnQYASABKAsyIC5zbm93ZHJhdy5lbmdpbmUudj'
    'IuUG9pbnRlckV2ZW50UgVldmVudA==');

@$core.Deprecated('Use keyboardHostRequestDescriptor instead')
const KeyboardHostRequest$json = {
  '1': 'KeyboardHostRequest',
  '2': [
    {
      '1': 'event',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.KeyboardEvent',
      '10': 'event'
    },
  ],
};

/// Descriptor for `KeyboardHostRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List keyboardHostRequestDescriptor = $convert.base64Decode(
    'ChNLZXlib2FyZEhvc3RSZXF1ZXN0EjcKBWV2ZW50GAEgASgLMiEuc25vd2RyYXcuZW5naW5lLn'
    'YyLktleWJvYXJkRXZlbnRSBWV2ZW50');

@$core.Deprecated('Use toolHostRequestDescriptor instead')
const ToolHostRequest$json = {
  '1': 'ToolHostRequest',
  '2': [
    {
      '1': 'event',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.ToolEvent',
      '10': 'event'
    },
  ],
};

/// Descriptor for `ToolHostRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List toolHostRequestDescriptor = $convert.base64Decode(
    'Cg9Ub29sSG9zdFJlcXVlc3QSMwoFZXZlbnQYASABKAsyHS5zbm93ZHJhdy5lbmdpbmUudjIuVG'
    '9vbEV2ZW50UgVldmVudA==');

@$core.Deprecated('Use hostRequestDescriptor instead')
const HostRequest$json = {
  '1': 'HostRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 4, '10': 'requestId'},
    {
      '1': 'text_metrics_request',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.TextMetricsRequest',
      '9': 0,
      '10': 'textMetricsRequest'
    },
    {
      '1': 'pointer_host_request',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.PointerHostRequest',
      '9': 0,
      '10': 'pointerHostRequest'
    },
    {
      '1': 'keyboard_host_request',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.KeyboardHostRequest',
      '9': 0,
      '10': 'keyboardHostRequest'
    },
    {
      '1': 'tool_host_request',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.ToolHostRequest',
      '9': 0,
      '10': 'toolHostRequest'
    },
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `HostRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List hostRequestDescriptor = $convert.base64Decode(
    'CgtIb3N0UmVxdWVzdBIdCgpyZXF1ZXN0X2lkGAEgASgEUglyZXF1ZXN0SWQSWgoUdGV4dF9tZX'
    'RyaWNzX3JlcXVlc3QYCiABKAsyJi5zbm93ZHJhdy5lbmdpbmUudjIuVGV4dE1ldHJpY3NSZXF1'
    'ZXN0SABSEnRleHRNZXRyaWNzUmVxdWVzdBJaChRwb2ludGVyX2hvc3RfcmVxdWVzdBgLIAEoCz'
    'ImLnNub3dkcmF3LmVuZ2luZS52Mi5Qb2ludGVySG9zdFJlcXVlc3RIAFIScG9pbnRlckhvc3RS'
    'ZXF1ZXN0El0KFWtleWJvYXJkX2hvc3RfcmVxdWVzdBgMIAEoCzInLnNub3dkcmF3LmVuZ2luZS'
    '52Mi5LZXlib2FyZEhvc3RSZXF1ZXN0SABSE2tleWJvYXJkSG9zdFJlcXVlc3QSUQoRdG9vbF9o'
    'b3N0X3JlcXVlc3QYDSABKAsyIy5zbm93ZHJhdy5lbmdpbmUudjIuVG9vbEhvc3RSZXF1ZXN0SA'
    'BSD3Rvb2xIb3N0UmVxdWVzdEIJCgdwYXlsb2Fk');

@$core.Deprecated('Use engineStateDeltaDescriptor instead')
const EngineStateDelta$json = {
  '1': 'EngineStateDelta',
  '2': [
    {'1': 'document_version', '3': 1, '4': 1, '5': 4, '10': 'documentVersion'},
    {
      '1': 'selection_version',
      '3': 2,
      '4': 1,
      '5': 4,
      '10': 'selectionVersion'
    },
    {
      '1': 'changed_element_ids',
      '3': 3,
      '4': 3,
      '5': 9,
      '10': 'changedElementIds'
    },
  ],
};

/// Descriptor for `EngineStateDelta`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineStateDeltaDescriptor = $convert.base64Decode(
    'ChBFbmdpbmVTdGF0ZURlbHRhEikKEGRvY3VtZW50X3ZlcnNpb24YASABKARSD2RvY3VtZW50Vm'
    'Vyc2lvbhIrChFzZWxlY3Rpb25fdmVyc2lvbhgCIAEoBFIQc2VsZWN0aW9uVmVyc2lvbhIuChNj'
    'aGFuZ2VkX2VsZW1lbnRfaWRzGAMgAygJUhFjaGFuZ2VkRWxlbWVudElkcw==');

@$core.Deprecated('Use engineOutputDescriptor instead')
const EngineOutput$json = {
  '1': 'EngineOutput',
  '2': [
    {'1': 'sequence', '3': 1, '4': 1, '5': 4, '10': 'sequence'},
    {
      '1': 'init_ack',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.EngineInitAck',
      '9': 0,
      '10': 'initAck'
    },
    {
      '1': 'snapshot',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.EngineSnapshot',
      '9': 0,
      '10': 'snapshot'
    },
    {
      '1': 'state_delta',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.EngineStateDelta',
      '9': 0,
      '10': 'stateDelta'
    },
    {
      '1': 'frame_plan',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.FrameRenderPlan',
      '9': 0,
      '10': 'framePlan'
    },
    {
      '1': 'event',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.EngineEvent',
      '9': 0,
      '10': 'event'
    },
    {
      '1': 'host_request',
      '3': 15,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v2.HostRequest',
      '9': 0,
      '10': 'hostRequest'
    },
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `EngineOutput`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineOutputDescriptor = $convert.base64Decode(
    'CgxFbmdpbmVPdXRwdXQSGgoIc2VxdWVuY2UYASABKARSCHNlcXVlbmNlEj4KCGluaXRfYWNrGA'
    'ogASgLMiEuc25vd2RyYXcuZW5naW5lLnYyLkVuZ2luZUluaXRBY2tIAFIHaW5pdEFjaxJACghz'
    'bmFwc2hvdBgLIAEoCzIiLnNub3dkcmF3LmVuZ2luZS52Mi5FbmdpbmVTbmFwc2hvdEgAUghzbm'
    'Fwc2hvdBJHCgtzdGF0ZV9kZWx0YRgMIAEoCzIkLnNub3dkcmF3LmVuZ2luZS52Mi5FbmdpbmVT'
    'dGF0ZURlbHRhSABSCnN0YXRlRGVsdGESRAoKZnJhbWVfcGxhbhgNIAEoCzIjLnNub3dkcmF3Lm'
    'VuZ2luZS52Mi5GcmFtZVJlbmRlclBsYW5IAFIJZnJhbWVQbGFuEjcKBWV2ZW50GA4gASgLMh8u'
    'c25vd2RyYXcuZW5naW5lLnYyLkVuZ2luZUV2ZW50SABSBWV2ZW50EkQKDGhvc3RfcmVxdWVzdB'
    'gPIAEoCzIfLnNub3dkcmF3LmVuZ2luZS52Mi5Ib3N0UmVxdWVzdEgAUgtob3N0UmVxdWVzdEIJ'
    'CgdwYXlsb2Fk');
