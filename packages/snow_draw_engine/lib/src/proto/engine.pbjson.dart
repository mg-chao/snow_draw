// This is a generated file - do not edit.
//
// Generated from engine.proto.

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

@$core.Deprecated('Use engineCommandKindDescriptor instead')
const EngineCommandKind$json = {
  '1': 'EngineCommandKind',
  '2': [
    {'1': 'ENGINE_COMMAND_KIND_UNKNOWN', '2': 0},
    {'1': 'ENGINE_COMMAND_KIND_SELECT_ELEMENT', '2': 1},
    {'1': 'ENGINE_COMMAND_KIND_CLEAR_SELECTION', '2': 2},
    {'1': 'ENGINE_COMMAND_KIND_SELECT_ALL', '2': 3},
    {'1': 'ENGINE_COMMAND_KIND_CREATE_ELEMENT', '2': 4},
    {'1': 'ENGINE_COMMAND_KIND_UPDATE_CREATING_ELEMENT', '2': 5},
    {'1': 'ENGINE_COMMAND_KIND_ADD_ARROW_POINT', '2': 6},
    {'1': 'ENGINE_COMMAND_KIND_FINISH_CREATE_ELEMENT', '2': 7},
    {'1': 'ENGINE_COMMAND_KIND_CANCEL_CREATE_ELEMENT', '2': 8},
    {'1': 'ENGINE_COMMAND_KIND_DELETE_ELEMENTS', '2': 9},
    {'1': 'ENGINE_COMMAND_KIND_DUPLICATE_ELEMENTS', '2': 10},
    {'1': 'ENGINE_COMMAND_KIND_CHANGE_ELEMENT_Z_INDEX', '2': 11},
    {'1': 'ENGINE_COMMAND_KIND_CHANGE_ELEMENTS_Z_INDEX', '2': 12},
    {'1': 'ENGINE_COMMAND_KIND_UPDATE_ELEMENTS_STYLE', '2': 13},
    {'1': 'ENGINE_COMMAND_KIND_UPDATE_GLOBAL_ELEMENTS', '2': 14},
    {'1': 'ENGINE_COMMAND_KIND_CREATE_SERIAL_NUMBER_TEXT_ELEMENTS', '2': 15},
    {'1': 'ENGINE_COMMAND_KIND_START_TEXT_EDIT', '2': 16},
    {'1': 'ENGINE_COMMAND_KIND_UPDATE_TEXT_EDIT', '2': 17},
    {
      '1':
          'ENGINE_COMMAND_KIND_REFRESH_AUTO_RESIZE_TEXT_LAYOUTS_AFTER_FONT_LOAD',
      '2': 18
    },
    {'1': 'ENGINE_COMMAND_KIND_FINISH_TEXT_EDIT', '2': 19},
    {'1': 'ENGINE_COMMAND_KIND_CANCEL_TEXT_EDIT', '2': 20},
    {'1': 'ENGINE_COMMAND_KIND_START_EDIT', '2': 21},
    {'1': 'ENGINE_COMMAND_KIND_UPDATE_EDIT', '2': 22},
    {'1': 'ENGINE_COMMAND_KIND_FINISH_EDIT', '2': 23},
    {'1': 'ENGINE_COMMAND_KIND_CANCEL_EDIT', '2': 24},
    {'1': 'ENGINE_COMMAND_KIND_SET_DRAG_PENDING', '2': 25},
    {'1': 'ENGINE_COMMAND_KIND_CLEAR_DRAG_PENDING', '2': 26},
    {'1': 'ENGINE_COMMAND_KIND_START_BOX_SELECT', '2': 27},
    {'1': 'ENGINE_COMMAND_KIND_UPDATE_BOX_SELECT', '2': 28},
    {'1': 'ENGINE_COMMAND_KIND_FINISH_BOX_SELECT', '2': 29},
    {'1': 'ENGINE_COMMAND_KIND_CANCEL_BOX_SELECT', '2': 30},
    {'1': 'ENGINE_COMMAND_KIND_MOVE_CAMERA', '2': 31},
    {'1': 'ENGINE_COMMAND_KIND_ZOOM_CAMERA', '2': 32},
    {'1': 'ENGINE_COMMAND_KIND_UNDO', '2': 33},
    {'1': 'ENGINE_COMMAND_KIND_REDO', '2': 34},
    {'1': 'ENGINE_COMMAND_KIND_CLEAR_HISTORY', '2': 35},
  ],
};

/// Descriptor for `EngineCommandKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List engineCommandKindDescriptor = $convert.base64Decode(
    'ChFFbmdpbmVDb21tYW5kS2luZBIfChtFTkdJTkVfQ09NTUFORF9LSU5EX1VOS05PV04QABImCi'
    'JFTkdJTkVfQ09NTUFORF9LSU5EX1NFTEVDVF9FTEVNRU5UEAESJwojRU5HSU5FX0NPTU1BTkRf'
    'S0lORF9DTEVBUl9TRUxFQ1RJT04QAhIiCh5FTkdJTkVfQ09NTUFORF9LSU5EX1NFTEVDVF9BTE'
    'wQAxImCiJFTkdJTkVfQ09NTUFORF9LSU5EX0NSRUFURV9FTEVNRU5UEAQSLworRU5HSU5FX0NP'
    'TU1BTkRfS0lORF9VUERBVEVfQ1JFQVRJTkdfRUxFTUVOVBAFEicKI0VOR0lORV9DT01NQU5EX0'
    'tJTkRfQUREX0FSUk9XX1BPSU5UEAYSLQopRU5HSU5FX0NPTU1BTkRfS0lORF9GSU5JU0hfQ1JF'
    'QVRFX0VMRU1FTlQQBxItCilFTkdJTkVfQ09NTUFORF9LSU5EX0NBTkNFTF9DUkVBVEVfRUxFTU'
    'VOVBAIEicKI0VOR0lORV9DT01NQU5EX0tJTkRfREVMRVRFX0VMRU1FTlRTEAkSKgomRU5HSU5F'
    'X0NPTU1BTkRfS0lORF9EVVBMSUNBVEVfRUxFTUVOVFMQChIuCipFTkdJTkVfQ09NTUFORF9LSU'
    '5EX0NIQU5HRV9FTEVNRU5UX1pfSU5ERVgQCxIvCitFTkdJTkVfQ09NTUFORF9LSU5EX0NIQU5H'
    'RV9FTEVNRU5UU19aX0lOREVYEAwSLQopRU5HSU5FX0NPTU1BTkRfS0lORF9VUERBVEVfRUxFTU'
    'VOVFNfU1RZTEUQDRIuCipFTkdJTkVfQ09NTUFORF9LSU5EX1VQREFURV9HTE9CQUxfRUxFTUVO'
    'VFMQDhI6CjZFTkdJTkVfQ09NTUFORF9LSU5EX0NSRUFURV9TRVJJQUxfTlVNQkVSX1RFWFRfRU'
    'xFTUVOVFMQDxInCiNFTkdJTkVfQ09NTUFORF9LSU5EX1NUQVJUX1RFWFRfRURJVBAQEigKJEVO'
    'R0lORV9DT01NQU5EX0tJTkRfVVBEQVRFX1RFWFRfRURJVBAREkgKREVOR0lORV9DT01NQU5EX0'
    'tJTkRfUkVGUkVTSF9BVVRPX1JFU0laRV9URVhUX0xBWU9VVFNfQUZURVJfRk9OVF9MT0FEEBIS'
    'KAokRU5HSU5FX0NPTU1BTkRfS0lORF9GSU5JU0hfVEVYVF9FRElUEBMSKAokRU5HSU5FX0NPTU'
    '1BTkRfS0lORF9DQU5DRUxfVEVYVF9FRElUEBQSIgoeRU5HSU5FX0NPTU1BTkRfS0lORF9TVEFS'
    'VF9FRElUEBUSIwofRU5HSU5FX0NPTU1BTkRfS0lORF9VUERBVEVfRURJVBAWEiMKH0VOR0lORV'
    '9DT01NQU5EX0tJTkRfRklOSVNIX0VESVQQFxIjCh9FTkdJTkVfQ09NTUFORF9LSU5EX0NBTkNF'
    'TF9FRElUEBgSKAokRU5HSU5FX0NPTU1BTkRfS0lORF9TRVRfRFJBR19QRU5ESU5HEBkSKgomRU'
    '5HSU5FX0NPTU1BTkRfS0lORF9DTEVBUl9EUkFHX1BFTkRJTkcQGhIoCiRFTkdJTkVfQ09NTUFO'
    'RF9LSU5EX1NUQVJUX0JPWF9TRUxFQ1QQGxIpCiVFTkdJTkVfQ09NTUFORF9LSU5EX1VQREFURV'
    '9CT1hfU0VMRUNUEBwSKQolRU5HSU5FX0NPTU1BTkRfS0lORF9GSU5JU0hfQk9YX1NFTEVDVBAd'
    'EikKJUVOR0lORV9DT01NQU5EX0tJTkRfQ0FOQ0VMX0JPWF9TRUxFQ1QQHhIjCh9FTkdJTkVfQ0'
    '9NTUFORF9LSU5EX01PVkVfQ0FNRVJBEB8SIwofRU5HSU5FX0NPTU1BTkRfS0lORF9aT09NX0NB'
    'TUVSQRAgEhwKGEVOR0lORV9DT01NQU5EX0tJTkRfVU5ETxAhEhwKGEVOR0lORV9DT01NQU5EX0'
    'tJTkRfUkVETxAiEiUKIUVOR0lORV9DT01NQU5EX0tJTkRfQ0xFQVJfSElTVE9SWRAj');

@$core.Deprecated('Use zIndexOperationDescriptor instead')
const ZIndexOperation$json = {
  '1': 'ZIndexOperation',
  '2': [
    {'1': 'Z_INDEX_OPERATION_BRING_TO_FRONT', '2': 0},
    {'1': 'Z_INDEX_OPERATION_SEND_TO_BACK', '2': 1},
    {'1': 'Z_INDEX_OPERATION_BRING_FORWARD', '2': 2},
    {'1': 'Z_INDEX_OPERATION_SEND_BACKWARD', '2': 3},
  ],
};

/// Descriptor for `ZIndexOperation`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List zIndexOperationDescriptor = $convert.base64Decode(
    'Cg9aSW5kZXhPcGVyYXRpb24SJAogWl9JTkRFWF9PUEVSQVRJT05fQlJJTkdfVE9fRlJPTlQQAB'
    'IiCh5aX0lOREVYX09QRVJBVElPTl9TRU5EX1RPX0JBQ0sQARIjCh9aX0lOREVYX09QRVJBVElP'
    'Tl9CUklOR19GT1JXQVJEEAISIwofWl9JTkRFWF9PUEVSQVRJT05fU0VORF9CQUNLV0FSRBAD');

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
      '6': '.snowdraw.engine.v1.DrawPoint',
      '10': 'position'
    },
    {'1': 'zoom', '3': 2, '4': 1, '5': 1, '10': 'zoom'},
  ],
};

/// Descriptor for `CameraState`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List cameraStateDescriptor = $convert.base64Decode(
    'CgtDYW1lcmFTdGF0ZRI5Cghwb3NpdGlvbhgBIAEoCzIdLnNub3dkcmF3LmVuZ2luZS52MS5Ecm'
    'F3UG9pbnRSCHBvc2l0aW9uEhIKBHpvb20YAiABKAFSBHpvb20=');

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
      '6': '.snowdraw.engine.v1.ElementType',
      '10': 'elementType'
    },
    {
      '1': 'rect',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.DrawRect',
      '10': 'rect'
    },
    {'1': 'rotation', '3': 4, '4': 1, '5': 1, '10': 'rotation'},
    {'1': 'opacity', '3': 5, '4': 1, '5': 1, '10': 'opacity'},
    {'1': 'z_index', '3': 6, '4': 1, '5': 5, '10': 'zIndex'},
    {'1': 'payload', '3': 7, '4': 1, '5': 12, '10': 'payload'},
  ],
};

/// Descriptor for `Element`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List elementDescriptor = $convert.base64Decode(
    'CgdFbGVtZW50Eg4KAmlkGAEgASgJUgJpZBJCCgxlbGVtZW50X3R5cGUYAiABKA4yHy5zbm93ZH'
    'Jhdy5lbmdpbmUudjEuRWxlbWVudFR5cGVSC2VsZW1lbnRUeXBlEjAKBHJlY3QYAyABKAsyHC5z'
    'bm93ZHJhdy5lbmdpbmUudjEuRHJhd1JlY3RSBHJlY3QSGgoIcm90YXRpb24YBCABKAFSCHJvdG'
    'F0aW9uEhgKB29wYWNpdHkYBSABKAFSB29wYWNpdHkSFwoHel9pbmRleBgGIAEoBVIGekluZGV4'
    'EhgKB3BheWxvYWQYByABKAxSB3BheWxvYWQ=');

@$core.Deprecated('Use engineConfigDescriptor instead')
const EngineConfig$json = {
  '1': 'EngineConfig',
  '2': [
    {'1': 'schema_version', '3': 1, '4': 1, '5': 13, '10': 'schemaVersion'},
    {'1': 'locale_tag', '3': 2, '4': 1, '5': 9, '10': 'localeTag'},
    {'1': 'scale_factor', '3': 3, '4': 1, '5': 1, '10': 'scaleFactor'},
    {
      '1': 'requested_capabilities',
      '3': 4,
      '4': 1,
      '5': 4,
      '10': 'requestedCapabilities'
    },
    {
      '1': 'deterministic_seed',
      '3': 5,
      '4': 1,
      '5': 4,
      '10': 'deterministicSeed'
    },
  ],
};

/// Descriptor for `EngineConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineConfigDescriptor = $convert.base64Decode(
    'CgxFbmdpbmVDb25maWcSJQoOc2NoZW1hX3ZlcnNpb24YASABKA1SDXNjaGVtYVZlcnNpb24SHQ'
    'oKbG9jYWxlX3RhZxgCIAEoCVIJbG9jYWxlVGFnEiEKDHNjYWxlX2ZhY3RvchgDIAEoAVILc2Nh'
    'bGVGYWN0b3ISNQoWcmVxdWVzdGVkX2NhcGFiaWxpdGllcxgEIAEoBFIVcmVxdWVzdGVkQ2FwYW'
    'JpbGl0aWVzEi0KEmRldGVybWluaXN0aWNfc2VlZBgFIAEoBFIRZGV0ZXJtaW5pc3RpY1NlZWQ=');

@$core.Deprecated('Use createElementCommandDescriptor instead')
const CreateElementCommand$json = {
  '1': 'CreateElementCommand',
  '2': [
    {
      '1': 'element_type',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.snowdraw.engine.v1.ElementType',
      '10': 'elementType'
    },
    {'1': 'element_id', '3': 2, '4': 1, '5': 9, '10': 'elementId'},
    {
      '1': 'position',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.DrawPoint',
      '10': 'position'
    },
    {'1': 'initial_payload', '3': 4, '4': 1, '5': 12, '10': 'initialPayload'},
    {
      '1': 'maintain_aspect_ratio',
      '3': 5,
      '4': 1,
      '5': 8,
      '10': 'maintainAspectRatio'
    },
    {
      '1': 'create_from_center',
      '3': 6,
      '4': 1,
      '5': 8,
      '10': 'createFromCenter'
    },
    {'1': 'snap_override', '3': 7, '4': 1, '5': 8, '10': 'snapOverride'},
  ],
};

/// Descriptor for `CreateElementCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createElementCommandDescriptor = $convert.base64Decode(
    'ChRDcmVhdGVFbGVtZW50Q29tbWFuZBJCCgxlbGVtZW50X3R5cGUYASABKA4yHy5zbm93ZHJhdy'
    '5lbmdpbmUudjEuRWxlbWVudFR5cGVSC2VsZW1lbnRUeXBlEh0KCmVsZW1lbnRfaWQYAiABKAlS'
    'CWVsZW1lbnRJZBI5Cghwb3NpdGlvbhgDIAEoCzIdLnNub3dkcmF3LmVuZ2luZS52MS5EcmF3UG'
    '9pbnRSCHBvc2l0aW9uEicKD2luaXRpYWxfcGF5bG9hZBgEIAEoDFIOaW5pdGlhbFBheWxvYWQS'
    'MgoVbWFpbnRhaW5fYXNwZWN0X3JhdGlvGAUgASgIUhNtYWludGFpbkFzcGVjdFJhdGlvEiwKEm'
    'NyZWF0ZV9mcm9tX2NlbnRlchgGIAEoCFIQY3JlYXRlRnJvbUNlbnRlchIjCg1zbmFwX292ZXJy'
    'aWRlGAcgASgIUgxzbmFwT3ZlcnJpZGU=');

@$core.Deprecated('Use selectElementCommandDescriptor instead')
const SelectElementCommand$json = {
  '1': 'SelectElementCommand',
  '2': [
    {'1': 'element_id', '3': 1, '4': 1, '5': 9, '10': 'elementId'},
    {'1': 'add_to_selection', '3': 2, '4': 1, '5': 8, '10': 'addToSelection'},
    {
      '1': 'position',
      '3': 3,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.DrawPoint',
      '10': 'position'
    },
  ],
};

/// Descriptor for `SelectElementCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List selectElementCommandDescriptor = $convert.base64Decode(
    'ChRTZWxlY3RFbGVtZW50Q29tbWFuZBIdCgplbGVtZW50X2lkGAEgASgJUgllbGVtZW50SWQSKA'
    'oQYWRkX3RvX3NlbGVjdGlvbhgCIAEoCFIOYWRkVG9TZWxlY3Rpb24SOQoIcG9zaXRpb24YAyAB'
    'KAsyHS5zbm93ZHJhdy5lbmdpbmUudjEuRHJhd1BvaW50Ughwb3NpdGlvbg==');

@$core.Deprecated('Use updateCreatingElementCommandDescriptor instead')
const UpdateCreatingElementCommand$json = {
  '1': 'UpdateCreatingElementCommand',
  '2': [
    {
      '1': 'positions',
      '3': 1,
      '4': 3,
      '5': 11,
      '6': '.snowdraw.engine.v1.DrawPoint',
      '10': 'positions'
    },
    {
      '1': 'maintain_aspect_ratio',
      '3': 2,
      '4': 1,
      '5': 8,
      '10': 'maintainAspectRatio'
    },
    {
      '1': 'create_from_center',
      '3': 3,
      '4': 1,
      '5': 8,
      '10': 'createFromCenter'
    },
    {'1': 'snap_override', '3': 4, '4': 1, '5': 8, '10': 'snapOverride'},
  ],
};

/// Descriptor for `UpdateCreatingElementCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateCreatingElementCommandDescriptor = $convert.base64Decode(
    'ChxVcGRhdGVDcmVhdGluZ0VsZW1lbnRDb21tYW5kEjsKCXBvc2l0aW9ucxgBIAMoCzIdLnNub3'
    'dkcmF3LmVuZ2luZS52MS5EcmF3UG9pbnRSCXBvc2l0aW9ucxIyChVtYWludGFpbl9hc3BlY3Rf'
    'cmF0aW8YAiABKAhSE21haW50YWluQXNwZWN0UmF0aW8SLAoSY3JlYXRlX2Zyb21fY2VudGVyGA'
    'MgASgIUhBjcmVhdGVGcm9tQ2VudGVyEiMKDXNuYXBfb3ZlcnJpZGUYBCABKAhSDHNuYXBPdmVy'
    'cmlkZQ==');

@$core.Deprecated('Use addArrowPointCommandDescriptor instead')
const AddArrowPointCommand$json = {
  '1': 'AddArrowPointCommand',
  '2': [
    {
      '1': 'position',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.DrawPoint',
      '10': 'position'
    },
    {'1': 'snap_override', '3': 2, '4': 1, '5': 8, '10': 'snapOverride'},
  ],
};

/// Descriptor for `AddArrowPointCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List addArrowPointCommandDescriptor = $convert.base64Decode(
    'ChRBZGRBcnJvd1BvaW50Q29tbWFuZBI5Cghwb3NpdGlvbhgBIAEoCzIdLnNub3dkcmF3LmVuZ2'
    'luZS52MS5EcmF3UG9pbnRSCHBvc2l0aW9uEiMKDXNuYXBfb3ZlcnJpZGUYAiABKAhSDHNuYXBP'
    'dmVycmlkZQ==');

@$core.Deprecated('Use deleteElementsCommandDescriptor instead')
const DeleteElementsCommand$json = {
  '1': 'DeleteElementsCommand',
  '2': [
    {'1': 'element_ids', '3': 1, '4': 3, '5': 9, '10': 'elementIds'},
  ],
};

/// Descriptor for `DeleteElementsCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deleteElementsCommandDescriptor = $convert.base64Decode(
    'ChVEZWxldGVFbGVtZW50c0NvbW1hbmQSHwoLZWxlbWVudF9pZHMYASADKAlSCmVsZW1lbnRJZH'
    'M=');

@$core.Deprecated('Use updateElementsStyleCommandDescriptor instead')
const UpdateElementsStyleCommand$json = {
  '1': 'UpdateElementsStyleCommand',
  '2': [
    {'1': 'element_ids', '3': 1, '4': 3, '5': 9, '10': 'elementIds'},
    {'1': 'style_payload', '3': 2, '4': 1, '5': 12, '10': 'stylePayload'},
  ],
};

/// Descriptor for `UpdateElementsStyleCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateElementsStyleCommandDescriptor =
    $convert.base64Decode(
        'ChpVcGRhdGVFbGVtZW50c1N0eWxlQ29tbWFuZBIfCgtlbGVtZW50X2lkcxgBIAMoCVIKZWxlbW'
        'VudElkcxIjCg1zdHlsZV9wYXlsb2FkGAIgASgMUgxzdHlsZVBheWxvYWQ=');

@$core.Deprecated('Use duplicateElementsCommandDescriptor instead')
const DuplicateElementsCommand$json = {
  '1': 'DuplicateElementsCommand',
  '2': [
    {'1': 'element_ids', '3': 1, '4': 3, '5': 9, '10': 'elementIds'},
    {'1': 'offset_x', '3': 2, '4': 1, '5': 1, '10': 'offsetX'},
    {'1': 'offset_y', '3': 3, '4': 1, '5': 1, '10': 'offsetY'},
  ],
};

/// Descriptor for `DuplicateElementsCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List duplicateElementsCommandDescriptor = $convert.base64Decode(
    'ChhEdXBsaWNhdGVFbGVtZW50c0NvbW1hbmQSHwoLZWxlbWVudF9pZHMYASADKAlSCmVsZW1lbn'
    'RJZHMSGQoIb2Zmc2V0X3gYAiABKAFSB29mZnNldFgSGQoIb2Zmc2V0X3kYAyABKAFSB29mZnNl'
    'dFk=');

@$core.Deprecated('Use changeElementZIndexCommandDescriptor instead')
const ChangeElementZIndexCommand$json = {
  '1': 'ChangeElementZIndexCommand',
  '2': [
    {'1': 'element_id', '3': 1, '4': 1, '5': 9, '10': 'elementId'},
    {
      '1': 'operation',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.snowdraw.engine.v1.ZIndexOperation',
      '10': 'operation'
    },
  ],
};

/// Descriptor for `ChangeElementZIndexCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List changeElementZIndexCommandDescriptor =
    $convert.base64Decode(
        'ChpDaGFuZ2VFbGVtZW50WkluZGV4Q29tbWFuZBIdCgplbGVtZW50X2lkGAEgASgJUgllbGVtZW'
        '50SWQSQQoJb3BlcmF0aW9uGAIgASgOMiMuc25vd2RyYXcuZW5naW5lLnYxLlpJbmRleE9wZXJh'
        'dGlvblIJb3BlcmF0aW9u');

@$core.Deprecated('Use changeElementsZIndexCommandDescriptor instead')
const ChangeElementsZIndexCommand$json = {
  '1': 'ChangeElementsZIndexCommand',
  '2': [
    {'1': 'element_ids', '3': 1, '4': 3, '5': 9, '10': 'elementIds'},
    {
      '1': 'operation',
      '3': 2,
      '4': 1,
      '5': 14,
      '6': '.snowdraw.engine.v1.ZIndexOperation',
      '10': 'operation'
    },
  ],
};

/// Descriptor for `ChangeElementsZIndexCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List changeElementsZIndexCommandDescriptor =
    $convert.base64Decode(
        'ChtDaGFuZ2VFbGVtZW50c1pJbmRleENvbW1hbmQSHwoLZWxlbWVudF9pZHMYASADKAlSCmVsZW'
        '1lbnRJZHMSQQoJb3BlcmF0aW9uGAIgASgOMiMuc25vd2RyYXcuZW5naW5lLnYxLlpJbmRleE9w'
        'ZXJhdGlvblIJb3BlcmF0aW9u');

@$core.Deprecated('Use updateGlobalElementsCommandDescriptor instead')
const UpdateGlobalElementsCommand$json = {
  '1': 'UpdateGlobalElementsCommand',
  '2': [
    {'1': 'payload', '3': 1, '4': 1, '5': 12, '10': 'payload'},
  ],
};

/// Descriptor for `UpdateGlobalElementsCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateGlobalElementsCommandDescriptor =
    $convert.base64Decode(
        'ChtVcGRhdGVHbG9iYWxFbGVtZW50c0NvbW1hbmQSGAoHcGF5bG9hZBgBIAEoDFIHcGF5bG9hZA'
        '==');

@$core.Deprecated('Use createSerialNumberTextElementsCommandDescriptor instead')
const CreateSerialNumberTextElementsCommand$json = {
  '1': 'CreateSerialNumberTextElementsCommand',
  '2': [
    {'1': 'element_ids', '3': 1, '4': 3, '5': 9, '10': 'elementIds'},
  ],
};

/// Descriptor for `CreateSerialNumberTextElementsCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List createSerialNumberTextElementsCommandDescriptor =
    $convert.base64Decode(
        'CiVDcmVhdGVTZXJpYWxOdW1iZXJUZXh0RWxlbWVudHNDb21tYW5kEh8KC2VsZW1lbnRfaWRzGA'
        'EgAygJUgplbGVtZW50SWRz');

@$core.Deprecated('Use startTextEditCommandDescriptor instead')
const StartTextEditCommand$json = {
  '1': 'StartTextEditCommand',
  '2': [
    {'1': 'element_id', '3': 1, '4': 1, '5': 9, '10': 'elementId'},
    {
      '1': 'position',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.DrawPoint',
      '10': 'position'
    },
  ],
};

/// Descriptor for `StartTextEditCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startTextEditCommandDescriptor = $convert.base64Decode(
    'ChRTdGFydFRleHRFZGl0Q29tbWFuZBIdCgplbGVtZW50X2lkGAEgASgJUgllbGVtZW50SWQSOQ'
    'oIcG9zaXRpb24YAiABKAsyHS5zbm93ZHJhdy5lbmdpbmUudjEuRHJhd1BvaW50Ughwb3NpdGlv'
    'bg==');

@$core.Deprecated('Use updateTextEditCommandDescriptor instead')
const UpdateTextEditCommand$json = {
  '1': 'UpdateTextEditCommand',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {
      '1': 'rect',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.DrawRect',
      '10': 'rect'
    },
  ],
};

/// Descriptor for `UpdateTextEditCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateTextEditCommandDescriptor = $convert.base64Decode(
    'ChVVcGRhdGVUZXh0RWRpdENvbW1hbmQSEgoEdGV4dBgBIAEoCVIEdGV4dBIwCgRyZWN0GAIgAS'
    'gLMhwuc25vd2RyYXcuZW5naW5lLnYxLkRyYXdSZWN0UgRyZWN0');

@$core.Deprecated('Use finishTextEditCommandDescriptor instead')
const FinishTextEditCommand$json = {
  '1': 'FinishTextEditCommand',
  '2': [
    {'1': 'element_id', '3': 1, '4': 1, '5': 9, '10': 'elementId'},
    {'1': 'text', '3': 2, '4': 1, '5': 9, '10': 'text'},
    {'1': 'is_new', '3': 3, '4': 1, '5': 8, '10': 'isNew'},
  ],
};

/// Descriptor for `FinishTextEditCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List finishTextEditCommandDescriptor = $convert.base64Decode(
    'ChVGaW5pc2hUZXh0RWRpdENvbW1hbmQSHQoKZWxlbWVudF9pZBgBIAEoCVIJZWxlbWVudElkEh'
    'IKBHRleHQYAiABKAlSBHRleHQSFQoGaXNfbmV3GAMgASgIUgVpc05ldw==');

@$core.Deprecated('Use startEditCommandDescriptor instead')
const StartEditCommand$json = {
  '1': 'StartEditCommand',
  '2': [
    {'1': 'operation_id', '3': 1, '4': 1, '5': 9, '10': 'operationId'},
    {
      '1': 'position',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.DrawPoint',
      '10': 'position'
    },
    {'1': 'params', '3': 3, '4': 1, '5': 12, '10': 'params'},
  ],
};

/// Descriptor for `StartEditCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startEditCommandDescriptor = $convert.base64Decode(
    'ChBTdGFydEVkaXRDb21tYW5kEiEKDG9wZXJhdGlvbl9pZBgBIAEoCVILb3BlcmF0aW9uSWQSOQ'
    'oIcG9zaXRpb24YAiABKAsyHS5zbm93ZHJhdy5lbmdpbmUudjEuRHJhd1BvaW50Ughwb3NpdGlv'
    'bhIWCgZwYXJhbXMYAyABKAxSBnBhcmFtcw==');

@$core.Deprecated('Use updateEditCommandDescriptor instead')
const UpdateEditCommand$json = {
  '1': 'UpdateEditCommand',
  '2': [
    {
      '1': 'current_position',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.DrawPoint',
      '10': 'currentPosition'
    },
    {'1': 'modifiers', '3': 2, '4': 1, '5': 12, '10': 'modifiers'},
  ],
};

/// Descriptor for `UpdateEditCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateEditCommandDescriptor = $convert.base64Decode(
    'ChFVcGRhdGVFZGl0Q29tbWFuZBJIChBjdXJyZW50X3Bvc2l0aW9uGAEgASgLMh0uc25vd2RyYX'
    'cuZW5naW5lLnYxLkRyYXdQb2ludFIPY3VycmVudFBvc2l0aW9uEhwKCW1vZGlmaWVycxgCIAEo'
    'DFIJbW9kaWZpZXJz');

@$core.Deprecated('Use setDragPendingCommandDescriptor instead')
const SetDragPendingCommand$json = {
  '1': 'SetDragPendingCommand',
  '2': [
    {
      '1': 'pointer_down_position',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.DrawPoint',
      '10': 'pointerDownPosition'
    },
    {'1': 'intent', '3': 2, '4': 1, '5': 9, '10': 'intent'},
  ],
};

/// Descriptor for `SetDragPendingCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List setDragPendingCommandDescriptor = $convert.base64Decode(
    'ChVTZXREcmFnUGVuZGluZ0NvbW1hbmQSUQoVcG9pbnRlcl9kb3duX3Bvc2l0aW9uGAEgASgLMh'
    '0uc25vd2RyYXcuZW5naW5lLnYxLkRyYXdQb2ludFITcG9pbnRlckRvd25Qb3NpdGlvbhIWCgZp'
    'bnRlbnQYAiABKAlSBmludGVudA==');

@$core.Deprecated('Use startBoxSelectCommandDescriptor instead')
const StartBoxSelectCommand$json = {
  '1': 'StartBoxSelectCommand',
  '2': [
    {
      '1': 'start_position',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.DrawPoint',
      '10': 'startPosition'
    },
  ],
};

/// Descriptor for `StartBoxSelectCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List startBoxSelectCommandDescriptor = $convert.base64Decode(
    'ChVTdGFydEJveFNlbGVjdENvbW1hbmQSRAoOc3RhcnRfcG9zaXRpb24YASABKAsyHS5zbm93ZH'
    'Jhdy5lbmdpbmUudjEuRHJhd1BvaW50Ug1zdGFydFBvc2l0aW9u');

@$core.Deprecated('Use updateBoxSelectCommandDescriptor instead')
const UpdateBoxSelectCommand$json = {
  '1': 'UpdateBoxSelectCommand',
  '2': [
    {
      '1': 'current_position',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.DrawPoint',
      '10': 'currentPosition'
    },
  ],
};

/// Descriptor for `UpdateBoxSelectCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List updateBoxSelectCommandDescriptor =
    $convert.base64Decode(
        'ChZVcGRhdGVCb3hTZWxlY3RDb21tYW5kEkgKEGN1cnJlbnRfcG9zaXRpb24YASABKAsyHS5zbm'
        '93ZHJhdy5lbmdpbmUudjEuRHJhd1BvaW50Ug9jdXJyZW50UG9zaXRpb24=');

@$core.Deprecated('Use moveCameraCommandDescriptor instead')
const MoveCameraCommand$json = {
  '1': 'MoveCameraCommand',
  '2': [
    {'1': 'dx', '3': 1, '4': 1, '5': 1, '10': 'dx'},
    {'1': 'dy', '3': 2, '4': 1, '5': 1, '10': 'dy'},
  ],
};

/// Descriptor for `MoveCameraCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List moveCameraCommandDescriptor = $convert.base64Decode(
    'ChFNb3ZlQ2FtZXJhQ29tbWFuZBIOCgJkeBgBIAEoAVICZHgSDgoCZHkYAiABKAFSAmR5');

@$core.Deprecated('Use zoomCameraCommandDescriptor instead')
const ZoomCameraCommand$json = {
  '1': 'ZoomCameraCommand',
  '2': [
    {'1': 'scale', '3': 1, '4': 1, '5': 1, '10': 'scale'},
    {
      '1': 'center',
      '3': 2,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.DrawPoint',
      '10': 'center'
    },
  ],
};

/// Descriptor for `ZoomCameraCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List zoomCameraCommandDescriptor = $convert.base64Decode(
    'ChFab29tQ2FtZXJhQ29tbWFuZBIUCgVzY2FsZRgBIAEoAVIFc2NhbGUSNQoGY2VudGVyGAIgAS'
    'gLMh0uc25vd2RyYXcuZW5naW5lLnYxLkRyYXdQb2ludFIGY2VudGVy');

@$core.Deprecated('Use engineCommandDescriptor instead')
const EngineCommand$json = {
  '1': 'EngineCommand',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.snowdraw.engine.v1.EngineCommandKind',
      '10': 'kind'
    },
    {
      '1': 'create_element',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.CreateElementCommand',
      '9': 0,
      '10': 'createElement'
    },
    {
      '1': 'select_element',
      '3': 11,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.SelectElementCommand',
      '9': 0,
      '10': 'selectElement'
    },
    {
      '1': 'delete_elements',
      '3': 12,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.DeleteElementsCommand',
      '9': 0,
      '10': 'deleteElements'
    },
    {
      '1': 'update_elements_style',
      '3': 13,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.UpdateElementsStyleCommand',
      '9': 0,
      '10': 'updateElementsStyle'
    },
    {
      '1': 'move_camera',
      '3': 14,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.MoveCameraCommand',
      '9': 0,
      '10': 'moveCamera'
    },
    {
      '1': 'zoom_camera',
      '3': 15,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.ZoomCameraCommand',
      '9': 0,
      '10': 'zoomCamera'
    },
    {
      '1': 'update_creating_element',
      '3': 16,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.UpdateCreatingElementCommand',
      '9': 0,
      '10': 'updateCreatingElement'
    },
    {
      '1': 'add_arrow_point',
      '3': 17,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.AddArrowPointCommand',
      '9': 0,
      '10': 'addArrowPoint'
    },
    {
      '1': 'duplicate_elements',
      '3': 18,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.DuplicateElementsCommand',
      '9': 0,
      '10': 'duplicateElements'
    },
    {
      '1': 'change_element_z_index',
      '3': 19,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.ChangeElementZIndexCommand',
      '9': 0,
      '10': 'changeElementZIndex'
    },
    {
      '1': 'change_elements_z_index',
      '3': 20,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.ChangeElementsZIndexCommand',
      '9': 0,
      '10': 'changeElementsZIndex'
    },
    {
      '1': 'update_global_elements',
      '3': 21,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.UpdateGlobalElementsCommand',
      '9': 0,
      '10': 'updateGlobalElements'
    },
    {
      '1': 'create_serial_number_text_elements',
      '3': 22,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.CreateSerialNumberTextElementsCommand',
      '9': 0,
      '10': 'createSerialNumberTextElements'
    },
    {
      '1': 'start_text_edit',
      '3': 23,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.StartTextEditCommand',
      '9': 0,
      '10': 'startTextEdit'
    },
    {
      '1': 'update_text_edit',
      '3': 24,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.UpdateTextEditCommand',
      '9': 0,
      '10': 'updateTextEdit'
    },
    {
      '1': 'finish_text_edit',
      '3': 25,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.FinishTextEditCommand',
      '9': 0,
      '10': 'finishTextEdit'
    },
    {
      '1': 'start_edit',
      '3': 26,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.StartEditCommand',
      '9': 0,
      '10': 'startEdit'
    },
    {
      '1': 'update_edit',
      '3': 27,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.UpdateEditCommand',
      '9': 0,
      '10': 'updateEdit'
    },
    {
      '1': 'set_drag_pending',
      '3': 28,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.SetDragPendingCommand',
      '9': 0,
      '10': 'setDragPending'
    },
    {
      '1': 'start_box_select',
      '3': 29,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.StartBoxSelectCommand',
      '9': 0,
      '10': 'startBoxSelect'
    },
    {
      '1': 'update_box_select',
      '3': 30,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.UpdateBoxSelectCommand',
      '9': 0,
      '10': 'updateBoxSelect'
    },
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `EngineCommand`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List engineCommandDescriptor = $convert.base64Decode(
    'Cg1FbmdpbmVDb21tYW5kEjkKBGtpbmQYASABKA4yJS5zbm93ZHJhdy5lbmdpbmUudjEuRW5naW'
    '5lQ29tbWFuZEtpbmRSBGtpbmQSUQoOY3JlYXRlX2VsZW1lbnQYCiABKAsyKC5zbm93ZHJhdy5l'
    'bmdpbmUudjEuQ3JlYXRlRWxlbWVudENvbW1hbmRIAFINY3JlYXRlRWxlbWVudBJRCg5zZWxlY3'
    'RfZWxlbWVudBgLIAEoCzIoLnNub3dkcmF3LmVuZ2luZS52MS5TZWxlY3RFbGVtZW50Q29tbWFu'
    'ZEgAUg1zZWxlY3RFbGVtZW50ElQKD2RlbGV0ZV9lbGVtZW50cxgMIAEoCzIpLnNub3dkcmF3Lm'
    'VuZ2luZS52MS5EZWxldGVFbGVtZW50c0NvbW1hbmRIAFIOZGVsZXRlRWxlbWVudHMSZAoVdXBk'
    'YXRlX2VsZW1lbnRzX3N0eWxlGA0gASgLMi4uc25vd2RyYXcuZW5naW5lLnYxLlVwZGF0ZUVsZW'
    '1lbnRzU3R5bGVDb21tYW5kSABSE3VwZGF0ZUVsZW1lbnRzU3R5bGUSSAoLbW92ZV9jYW1lcmEY'
    'DiABKAsyJS5zbm93ZHJhdy5lbmdpbmUudjEuTW92ZUNhbWVyYUNvbW1hbmRIAFIKbW92ZUNhbW'
    'VyYRJICgt6b29tX2NhbWVyYRgPIAEoCzIlLnNub3dkcmF3LmVuZ2luZS52MS5ab29tQ2FtZXJh'
    'Q29tbWFuZEgAUgp6b29tQ2FtZXJhEmoKF3VwZGF0ZV9jcmVhdGluZ19lbGVtZW50GBAgASgLMj'
    'Auc25vd2RyYXcuZW5naW5lLnYxLlVwZGF0ZUNyZWF0aW5nRWxlbWVudENvbW1hbmRIAFIVdXBk'
    'YXRlQ3JlYXRpbmdFbGVtZW50ElIKD2FkZF9hcnJvd19wb2ludBgRIAEoCzIoLnNub3dkcmF3Lm'
    'VuZ2luZS52MS5BZGRBcnJvd1BvaW50Q29tbWFuZEgAUg1hZGRBcnJvd1BvaW50El0KEmR1cGxp'
    'Y2F0ZV9lbGVtZW50cxgSIAEoCzIsLnNub3dkcmF3LmVuZ2luZS52MS5EdXBsaWNhdGVFbGVtZW'
    '50c0NvbW1hbmRIAFIRZHVwbGljYXRlRWxlbWVudHMSZQoWY2hhbmdlX2VsZW1lbnRfel9pbmRl'
    'eBgTIAEoCzIuLnNub3dkcmF3LmVuZ2luZS52MS5DaGFuZ2VFbGVtZW50WkluZGV4Q29tbWFuZE'
    'gAUhNjaGFuZ2VFbGVtZW50WkluZGV4EmgKF2NoYW5nZV9lbGVtZW50c196X2luZGV4GBQgASgL'
    'Mi8uc25vd2RyYXcuZW5naW5lLnYxLkNoYW5nZUVsZW1lbnRzWkluZGV4Q29tbWFuZEgAUhRjaG'
    'FuZ2VFbGVtZW50c1pJbmRleBJnChZ1cGRhdGVfZ2xvYmFsX2VsZW1lbnRzGBUgASgLMi8uc25v'
    'd2RyYXcuZW5naW5lLnYxLlVwZGF0ZUdsb2JhbEVsZW1lbnRzQ29tbWFuZEgAUhR1cGRhdGVHbG'
    '9iYWxFbGVtZW50cxKHAQoiY3JlYXRlX3NlcmlhbF9udW1iZXJfdGV4dF9lbGVtZW50cxgWIAEo'
    'CzI5LnNub3dkcmF3LmVuZ2luZS52MS5DcmVhdGVTZXJpYWxOdW1iZXJUZXh0RWxlbWVudHNDb2'
    '1tYW5kSABSHmNyZWF0ZVNlcmlhbE51bWJlclRleHRFbGVtZW50cxJSCg9zdGFydF90ZXh0X2Vk'
    'aXQYFyABKAsyKC5zbm93ZHJhdy5lbmdpbmUudjEuU3RhcnRUZXh0RWRpdENvbW1hbmRIAFINc3'
    'RhcnRUZXh0RWRpdBJVChB1cGRhdGVfdGV4dF9lZGl0GBggASgLMikuc25vd2RyYXcuZW5naW5l'
    'LnYxLlVwZGF0ZVRleHRFZGl0Q29tbWFuZEgAUg51cGRhdGVUZXh0RWRpdBJVChBmaW5pc2hfdG'
    'V4dF9lZGl0GBkgASgLMikuc25vd2RyYXcuZW5naW5lLnYxLkZpbmlzaFRleHRFZGl0Q29tbWFu'
    'ZEgAUg5maW5pc2hUZXh0RWRpdBJFCgpzdGFydF9lZGl0GBogASgLMiQuc25vd2RyYXcuZW5naW'
    '5lLnYxLlN0YXJ0RWRpdENvbW1hbmRIAFIJc3RhcnRFZGl0EkgKC3VwZGF0ZV9lZGl0GBsgASgL'
    'MiUuc25vd2RyYXcuZW5naW5lLnYxLlVwZGF0ZUVkaXRDb21tYW5kSABSCnVwZGF0ZUVkaXQSVQ'
    'oQc2V0X2RyYWdfcGVuZGluZxgcIAEoCzIpLnNub3dkcmF3LmVuZ2luZS52MS5TZXREcmFnUGVu'
    'ZGluZ0NvbW1hbmRIAFIOc2V0RHJhZ1BlbmRpbmcSVQoQc3RhcnRfYm94X3NlbGVjdBgdIAEoCz'
    'IpLnNub3dkcmF3LmVuZ2luZS52MS5TdGFydEJveFNlbGVjdENvbW1hbmRIAFIOc3RhcnRCb3hT'
    'ZWxlY3QSWAoRdXBkYXRlX2JveF9zZWxlY3QYHiABKAsyKi5zbm93ZHJhdy5lbmdpbmUudjEuVX'
    'BkYXRlQm94U2VsZWN0Q29tbWFuZEgAUg91cGRhdGVCb3hTZWxlY3RCCQoHcGF5bG9hZA==');

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
      '6': '.snowdraw.engine.v1.InteractionMode',
      '10': 'interactionMode'
    },
    {
      '1': 'camera',
      '3': 5,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.CameraState',
      '10': 'camera'
    },
    {
      '1': 'elements',
      '3': 6,
      '4': 3,
      '5': 11,
      '6': '.snowdraw.engine.v1.Element',
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
    'EoDjIjLnNub3dkcmF3LmVuZ2luZS52MS5JbnRlcmFjdGlvbk1vZGVSD2ludGVyYWN0aW9uTW9k'
    'ZRI3CgZjYW1lcmEYBSABKAsyHy5zbm93ZHJhdy5lbmdpbmUudjEuQ2FtZXJhU3RhdGVSBmNhbW'
    'VyYRI3CghlbGVtZW50cxgGIAMoCzIbLnNub3dkcmF3LmVuZ2luZS52MS5FbGVtZW50UghlbGVt'
    'ZW50cxIhCgxzZWxlY3RlZF9pZHMYByADKAlSC3NlbGVjdGVkSWRzEigKEGhpc3RvcnlfdW5kb1'
    '9sZW4YCCABKARSDmhpc3RvcnlVbmRvTGVuEigKEGhpc3RvcnlfcmVkb19sZW4YCSABKARSDmhp'
    'c3RvcnlSZWRvTGVuEjYKF2dsb2JhbF9lbGVtZW50c19wYXlsb2FkGAogASgMUhVnbG9iYWxFbG'
    'VtZW50c1BheWxvYWQ=');

@$core.Deprecated('Use framePlanRequestDescriptor instead')
const FramePlanRequest$json = {
  '1': 'FramePlanRequest',
  '2': [
    {
      '1': 'viewport',
      '3': 1,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.DrawRect',
      '10': 'viewport'
    },
    {'1': 'locale_tag', '3': 2, '4': 1, '5': 9, '10': 'localeTag'},
    {'1': 'scale_factor', '3': 3, '4': 1, '5': 1, '10': 'scaleFactor'},
  ],
};

/// Descriptor for `FramePlanRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List framePlanRequestDescriptor = $convert.base64Decode(
    'ChBGcmFtZVBsYW5SZXF1ZXN0EjgKCHZpZXdwb3J0GAEgASgLMhwuc25vd2RyYXcuZW5naW5lLn'
    'YxLkRyYXdSZWN0Ugh2aWV3cG9ydBIdCgpsb2NhbGVfdGFnGAIgASgJUglsb2NhbGVUYWcSIQoM'
    'c2NhbGVfZmFjdG9yGAMgASgBUgtzY2FsZUZhY3Rvcg==');

@$core.Deprecated('Use frameTaskDescriptor instead')
const FrameTask$json = {
  '1': 'FrameTask',
  '2': [
    {
      '1': 'kind',
      '3': 1,
      '4': 1,
      '5': 14,
      '6': '.snowdraw.engine.v1.FrameTaskKind',
      '10': 'kind'
    },
    {'1': 'element_id', '3': 2, '4': 1, '5': 9, '10': 'elementId'},
    {
      '1': 'element_type',
      '3': 3,
      '4': 1,
      '5': 14,
      '6': '.snowdraw.engine.v1.ElementType',
      '10': 'elementType'
    },
    {'1': 'payload', '3': 4, '4': 1, '5': 12, '10': 'payload'},
  ],
};

/// Descriptor for `FrameTask`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List frameTaskDescriptor = $convert.base64Decode(
    'CglGcmFtZVRhc2sSNQoEa2luZBgBIAEoDjIhLnNub3dkcmF3LmVuZ2luZS52MS5GcmFtZVRhc2'
    'tLaW5kUgRraW5kEh0KCmVsZW1lbnRfaWQYAiABKAlSCWVsZW1lbnRJZBJCCgxlbGVtZW50X3R5'
    'cGUYAyABKA4yHy5zbm93ZHJhdy5lbmdpbmUudjEuRWxlbWVudFR5cGVSC2VsZW1lbnRUeXBlEh'
    'gKB3BheWxvYWQYBCABKAxSB3BheWxvYWQ=');

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
      '6': '.snowdraw.engine.v1.CameraState',
      '10': 'camera'
    },
    {'1': 'scale_factor', '3': 3, '4': 1, '5': 1, '10': 'scaleFactor'},
    {'1': 'locale_tag', '3': 4, '4': 1, '5': 9, '10': 'localeTag'},
    {
      '1': 'tasks',
      '3': 5,
      '4': 3,
      '5': 11,
      '6': '.snowdraw.engine.v1.FrameTask',
      '10': 'tasks'
    },
  ],
};

/// Descriptor for `FrameRenderPlan`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List frameRenderPlanDescriptor = $convert.base64Decode(
    'Cg9GcmFtZVJlbmRlclBsYW4SJQoOc2NoZW1hX3ZlcnNpb24YASABKA1SDXNjaGVtYVZlcnNpb2'
    '4SNwoGY2FtZXJhGAIgASgLMh8uc25vd2RyYXcuZW5naW5lLnYxLkNhbWVyYVN0YXRlUgZjYW1l'
    'cmESIQoMc2NhbGVfZmFjdG9yGAMgASgBUgtzY2FsZUZhY3RvchIdCgpsb2NhbGVfdGFnGAQgAS'
    'gJUglsb2NhbGVUYWcSMwoFdGFza3MYBSADKAsyHS5zbm93ZHJhdy5lbmdpbmUudjEuRnJhbWVU'
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
      '6': '.snowdraw.engine.v1.EngineEventKind',
      '10': 'kind'
    },
    {'1': 'sequence', '3': 2, '4': 1, '5': 4, '10': 'sequence'},
    {
      '1': 'error',
      '3': 10,
      '4': 1,
      '5': 11,
      '6': '.snowdraw.engine.v1.EngineError',
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
    'CgtFbmdpbmVFdmVudBI3CgRraW5kGAEgASgOMiMuc25vd2RyYXcuZW5naW5lLnYxLkVuZ2luZU'
    'V2ZW50S2luZFIEa2luZBIaCghzZXF1ZW5jZRgCIAEoBFIIc2VxdWVuY2USNwoFZXJyb3IYCiAB'
    'KAsyHy5zbm93ZHJhdy5lbmdpbmUudjEuRW5naW5lRXJyb3JIAFIFZXJyb3ISFAoEYmxvYhgLIA'
    'EoDEgAUgRibG9iEhoKB21lc3NhZ2UYDCABKAlIAFIHbWVzc2FnZUIJCgdwYXlsb2Fk');
