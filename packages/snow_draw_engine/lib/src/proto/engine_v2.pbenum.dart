// This is a generated file - do not edit.
//
// Generated from engine_v2.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

class Capability extends $pb.ProtobufEnum {
  static const Capability CAPABILITY_UNSPECIFIED =
      Capability._(0, _omitEnumNames ? '' : 'CAPABILITY_UNSPECIFIED');
  static const Capability CAPABILITY_EVENT_STREAM =
      Capability._(1, _omitEnumNames ? '' : 'CAPABILITY_EVENT_STREAM');
  static const Capability CAPABILITY_FRAME_PLAN =
      Capability._(2, _omitEnumNames ? '' : 'CAPABILITY_FRAME_PLAN');
  static const Capability CAPABILITY_DISPATCH_BATCH =
      Capability._(3, _omitEnumNames ? '' : 'CAPABILITY_DISPATCH_BATCH');
  static const Capability CAPABILITY_INPUT_PIPELINE =
      Capability._(4, _omitEnumNames ? '' : 'CAPABILITY_INPUT_PIPELINE');
  static const Capability CAPABILITY_TEXT_METRICS_HOST =
      Capability._(5, _omitEnumNames ? '' : 'CAPABILITY_TEXT_METRICS_HOST');

  static const $core.List<Capability> values = <Capability>[
    CAPABILITY_UNSPECIFIED,
    CAPABILITY_EVENT_STREAM,
    CAPABILITY_FRAME_PLAN,
    CAPABILITY_DISPATCH_BATCH,
    CAPABILITY_INPUT_PIPELINE,
    CAPABILITY_TEXT_METRICS_HOST,
  ];

  static final $core.List<Capability?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static Capability? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const Capability._(super.value, super.name);
}

class ElementType extends $pb.ProtobufEnum {
  static const ElementType ELEMENT_TYPE_UNKNOWN =
      ElementType._(0, _omitEnumNames ? '' : 'ELEMENT_TYPE_UNKNOWN');
  static const ElementType ELEMENT_TYPE_RECTANGLE =
      ElementType._(1, _omitEnumNames ? '' : 'ELEMENT_TYPE_RECTANGLE');
  static const ElementType ELEMENT_TYPE_ARROW =
      ElementType._(2, _omitEnumNames ? '' : 'ELEMENT_TYPE_ARROW');
  static const ElementType ELEMENT_TYPE_LINE =
      ElementType._(3, _omitEnumNames ? '' : 'ELEMENT_TYPE_LINE');
  static const ElementType ELEMENT_TYPE_FREE_DRAW =
      ElementType._(4, _omitEnumNames ? '' : 'ELEMENT_TYPE_FREE_DRAW');
  static const ElementType ELEMENT_TYPE_FILTER =
      ElementType._(5, _omitEnumNames ? '' : 'ELEMENT_TYPE_FILTER');
  static const ElementType ELEMENT_TYPE_HIGHLIGHT =
      ElementType._(6, _omitEnumNames ? '' : 'ELEMENT_TYPE_HIGHLIGHT');
  static const ElementType ELEMENT_TYPE_TEXT =
      ElementType._(7, _omitEnumNames ? '' : 'ELEMENT_TYPE_TEXT');
  static const ElementType ELEMENT_TYPE_SERIAL_NUMBER =
      ElementType._(8, _omitEnumNames ? '' : 'ELEMENT_TYPE_SERIAL_NUMBER');

  static const $core.List<ElementType> values = <ElementType>[
    ELEMENT_TYPE_UNKNOWN,
    ELEMENT_TYPE_RECTANGLE,
    ELEMENT_TYPE_ARROW,
    ELEMENT_TYPE_LINE,
    ELEMENT_TYPE_FREE_DRAW,
    ELEMENT_TYPE_FILTER,
    ELEMENT_TYPE_HIGHLIGHT,
    ELEMENT_TYPE_TEXT,
    ELEMENT_TYPE_SERIAL_NUMBER,
  ];

  static final $core.List<ElementType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 8);
  static ElementType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ElementType._(super.value, super.name);
}

class InteractionMode extends $pb.ProtobufEnum {
  static const InteractionMode INTERACTION_MODE_IDLE =
      InteractionMode._(0, _omitEnumNames ? '' : 'INTERACTION_MODE_IDLE');
  static const InteractionMode INTERACTION_MODE_CREATING =
      InteractionMode._(1, _omitEnumNames ? '' : 'INTERACTION_MODE_CREATING');
  static const InteractionMode INTERACTION_MODE_EDITING =
      InteractionMode._(2, _omitEnumNames ? '' : 'INTERACTION_MODE_EDITING');
  static const InteractionMode INTERACTION_MODE_TEXT_EDITING =
      InteractionMode._(
          3, _omitEnumNames ? '' : 'INTERACTION_MODE_TEXT_EDITING');
  static const InteractionMode INTERACTION_MODE_BOX_SELECTING =
      InteractionMode._(
          4, _omitEnumNames ? '' : 'INTERACTION_MODE_BOX_SELECTING');
  static const InteractionMode INTERACTION_MODE_DRAG_PENDING =
      InteractionMode._(
          5, _omitEnumNames ? '' : 'INTERACTION_MODE_DRAG_PENDING');

  static const $core.List<InteractionMode> values = <InteractionMode>[
    INTERACTION_MODE_IDLE,
    INTERACTION_MODE_CREATING,
    INTERACTION_MODE_EDITING,
    INTERACTION_MODE_TEXT_EDITING,
    INTERACTION_MODE_BOX_SELECTING,
    INTERACTION_MODE_DRAG_PENDING,
  ];

  static final $core.List<InteractionMode?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static InteractionMode? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const InteractionMode._(super.value, super.name);
}

class FrameTaskKind extends $pb.ProtobufEnum {
  static const FrameTaskKind FRAME_TASK_KIND_UNKNOWN =
      FrameTaskKind._(0, _omitEnumNames ? '' : 'FRAME_TASK_KIND_UNKNOWN');
  static const FrameTaskKind FRAME_TASK_KIND_RECTANGLE =
      FrameTaskKind._(1, _omitEnumNames ? '' : 'FRAME_TASK_KIND_RECTANGLE');
  static const FrameTaskKind FRAME_TASK_KIND_LINE =
      FrameTaskKind._(2, _omitEnumNames ? '' : 'FRAME_TASK_KIND_LINE');
  static const FrameTaskKind FRAME_TASK_KIND_ARROW =
      FrameTaskKind._(3, _omitEnumNames ? '' : 'FRAME_TASK_KIND_ARROW');
  static const FrameTaskKind FRAME_TASK_KIND_FREE_DRAW =
      FrameTaskKind._(4, _omitEnumNames ? '' : 'FRAME_TASK_KIND_FREE_DRAW');
  static const FrameTaskKind FRAME_TASK_KIND_TEXT =
      FrameTaskKind._(5, _omitEnumNames ? '' : 'FRAME_TASK_KIND_TEXT');
  static const FrameTaskKind FRAME_TASK_KIND_SERIAL_NUMBER =
      FrameTaskKind._(6, _omitEnumNames ? '' : 'FRAME_TASK_KIND_SERIAL_NUMBER');
  static const FrameTaskKind FRAME_TASK_KIND_HIGHLIGHT =
      FrameTaskKind._(7, _omitEnumNames ? '' : 'FRAME_TASK_KIND_HIGHLIGHT');
  static const FrameTaskKind FRAME_TASK_KIND_FILTER =
      FrameTaskKind._(8, _omitEnumNames ? '' : 'FRAME_TASK_KIND_FILTER');
  static const FrameTaskKind FRAME_TASK_KIND_BACKGROUND =
      FrameTaskKind._(9, _omitEnumNames ? '' : 'FRAME_TASK_KIND_BACKGROUND');
  static const FrameTaskKind FRAME_TASK_KIND_GRID =
      FrameTaskKind._(10, _omitEnumNames ? '' : 'FRAME_TASK_KIND_GRID');
  static const FrameTaskKind FRAME_TASK_KIND_SELECTION_OUTLINE =
      FrameTaskKind._(
          11, _omitEnumNames ? '' : 'FRAME_TASK_KIND_SELECTION_OUTLINE');
  static const FrameTaskKind FRAME_TASK_KIND_SELECTION_CONTROLS =
      FrameTaskKind._(
          12, _omitEnumNames ? '' : 'FRAME_TASK_KIND_SELECTION_CONTROLS');
  static const FrameTaskKind FRAME_TASK_KIND_ARROW_POINT_OVERLAY =
      FrameTaskKind._(
          13, _omitEnumNames ? '' : 'FRAME_TASK_KIND_ARROW_POINT_OVERLAY');
  static const FrameTaskKind FRAME_TASK_KIND_ARROW_BINDING_HIGHLIGHT =
      FrameTaskKind._(
          14, _omitEnumNames ? '' : 'FRAME_TASK_KIND_ARROW_BINDING_HIGHLIGHT');
  static const FrameTaskKind FRAME_TASK_KIND_HOVER_OUTLINE = FrameTaskKind._(
      15, _omitEnumNames ? '' : 'FRAME_TASK_KIND_HOVER_OUTLINE');
  static const FrameTaskKind FRAME_TASK_KIND_SNAP_GUIDES =
      FrameTaskKind._(16, _omitEnumNames ? '' : 'FRAME_TASK_KIND_SNAP_GUIDES');
  static const FrameTaskKind FRAME_TASK_KIND_BOX_SELECTION = FrameTaskKind._(
      17, _omitEnumNames ? '' : 'FRAME_TASK_KIND_BOX_SELECTION');
  static const FrameTaskKind FRAME_TASK_KIND_HIGHLIGHT_MASK = FrameTaskKind._(
      18, _omitEnumNames ? '' : 'FRAME_TASK_KIND_HIGHLIGHT_MASK');
  static const FrameTaskKind FRAME_TASK_KIND_WATERMARK =
      FrameTaskKind._(19, _omitEnumNames ? '' : 'FRAME_TASK_KIND_WATERMARK');

  static const $core.List<FrameTaskKind> values = <FrameTaskKind>[
    FRAME_TASK_KIND_UNKNOWN,
    FRAME_TASK_KIND_RECTANGLE,
    FRAME_TASK_KIND_LINE,
    FRAME_TASK_KIND_ARROW,
    FRAME_TASK_KIND_FREE_DRAW,
    FRAME_TASK_KIND_TEXT,
    FRAME_TASK_KIND_SERIAL_NUMBER,
    FRAME_TASK_KIND_HIGHLIGHT,
    FRAME_TASK_KIND_FILTER,
    FRAME_TASK_KIND_BACKGROUND,
    FRAME_TASK_KIND_GRID,
    FRAME_TASK_KIND_SELECTION_OUTLINE,
    FRAME_TASK_KIND_SELECTION_CONTROLS,
    FRAME_TASK_KIND_ARROW_POINT_OVERLAY,
    FRAME_TASK_KIND_ARROW_BINDING_HIGHLIGHT,
    FRAME_TASK_KIND_HOVER_OUTLINE,
    FRAME_TASK_KIND_SNAP_GUIDES,
    FRAME_TASK_KIND_BOX_SELECTION,
    FRAME_TASK_KIND_HIGHLIGHT_MASK,
    FRAME_TASK_KIND_WATERMARK,
  ];

  static final $core.List<FrameTaskKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 19);
  static FrameTaskKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const FrameTaskKind._(super.value, super.name);
}

class EngineEventKind extends $pb.ProtobufEnum {
  static const EngineEventKind ENGINE_EVENT_KIND_UNKNOWN =
      EngineEventKind._(0, _omitEnumNames ? '' : 'ENGINE_EVENT_KIND_UNKNOWN');
  static const EngineEventKind ENGINE_EVENT_KIND_STATE_CHANGED =
      EngineEventKind._(
          1, _omitEnumNames ? '' : 'ENGINE_EVENT_KIND_STATE_CHANGED');
  static const EngineEventKind ENGINE_EVENT_KIND_VALIDATION_FAILED =
      EngineEventKind._(
          2, _omitEnumNames ? '' : 'ENGINE_EVENT_KIND_VALIDATION_FAILED');
  static const EngineEventKind ENGINE_EVENT_KIND_ERROR =
      EngineEventKind._(3, _omitEnumNames ? '' : 'ENGINE_EVENT_KIND_ERROR');
  static const EngineEventKind ENGINE_EVENT_KIND_HISTORY_CHANGED =
      EngineEventKind._(
          4, _omitEnumNames ? '' : 'ENGINE_EVENT_KIND_HISTORY_CHANGED');
  static const EngineEventKind ENGINE_EVENT_KIND_DEBUG =
      EngineEventKind._(5, _omitEnumNames ? '' : 'ENGINE_EVENT_KIND_DEBUG');

  static const $core.List<EngineEventKind> values = <EngineEventKind>[
    ENGINE_EVENT_KIND_UNKNOWN,
    ENGINE_EVENT_KIND_STATE_CHANGED,
    ENGINE_EVENT_KIND_VALIDATION_FAILED,
    ENGINE_EVENT_KIND_ERROR,
    ENGINE_EVENT_KIND_HISTORY_CHANGED,
    ENGINE_EVENT_KIND_DEBUG,
  ];

  static final $core.List<EngineEventKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static EngineEventKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const EngineEventKind._(super.value, super.name);
}

class PointerPhase extends $pb.ProtobufEnum {
  static const PointerPhase POINTER_PHASE_UNSPECIFIED =
      PointerPhase._(0, _omitEnumNames ? '' : 'POINTER_PHASE_UNSPECIFIED');
  static const PointerPhase POINTER_PHASE_DOWN =
      PointerPhase._(1, _omitEnumNames ? '' : 'POINTER_PHASE_DOWN');
  static const PointerPhase POINTER_PHASE_MOVE =
      PointerPhase._(2, _omitEnumNames ? '' : 'POINTER_PHASE_MOVE');
  static const PointerPhase POINTER_PHASE_UP =
      PointerPhase._(3, _omitEnumNames ? '' : 'POINTER_PHASE_UP');
  static const PointerPhase POINTER_PHASE_CANCEL =
      PointerPhase._(4, _omitEnumNames ? '' : 'POINTER_PHASE_CANCEL');
  static const PointerPhase POINTER_PHASE_HOVER =
      PointerPhase._(5, _omitEnumNames ? '' : 'POINTER_PHASE_HOVER');

  static const $core.List<PointerPhase> values = <PointerPhase>[
    POINTER_PHASE_UNSPECIFIED,
    POINTER_PHASE_DOWN,
    POINTER_PHASE_MOVE,
    POINTER_PHASE_UP,
    POINTER_PHASE_CANCEL,
    POINTER_PHASE_HOVER,
  ];

  static final $core.List<PointerPhase?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 5);
  static PointerPhase? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const PointerPhase._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
