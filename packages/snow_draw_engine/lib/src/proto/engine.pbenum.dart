// This is a generated file - do not edit.
//
// Generated from engine.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

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

class EngineCommandKind extends $pb.ProtobufEnum {
  static const EngineCommandKind ENGINE_COMMAND_KIND_UNKNOWN =
      EngineCommandKind._(
          0, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_UNKNOWN');
  static const EngineCommandKind ENGINE_COMMAND_KIND_SELECT_ELEMENT =
      EngineCommandKind._(
          1, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_SELECT_ELEMENT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_CLEAR_SELECTION =
      EngineCommandKind._(
          2, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_CLEAR_SELECTION');
  static const EngineCommandKind ENGINE_COMMAND_KIND_SELECT_ALL =
      EngineCommandKind._(
          3, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_SELECT_ALL');
  static const EngineCommandKind ENGINE_COMMAND_KIND_CREATE_ELEMENT =
      EngineCommandKind._(
          4, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_CREATE_ELEMENT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_UPDATE_CREATING_ELEMENT =
      EngineCommandKind._(5,
          _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_UPDATE_CREATING_ELEMENT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_ADD_ARROW_POINT =
      EngineCommandKind._(
          6, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_ADD_ARROW_POINT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_FINISH_CREATE_ELEMENT =
      EngineCommandKind._(
          7, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_FINISH_CREATE_ELEMENT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_CANCEL_CREATE_ELEMENT =
      EngineCommandKind._(
          8, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_CANCEL_CREATE_ELEMENT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_DELETE_ELEMENTS =
      EngineCommandKind._(
          9, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_DELETE_ELEMENTS');
  static const EngineCommandKind ENGINE_COMMAND_KIND_DUPLICATE_ELEMENTS =
      EngineCommandKind._(
          10, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_DUPLICATE_ELEMENTS');
  static const EngineCommandKind ENGINE_COMMAND_KIND_CHANGE_ELEMENT_Z_INDEX =
      EngineCommandKind._(11,
          _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_CHANGE_ELEMENT_Z_INDEX');
  static const EngineCommandKind ENGINE_COMMAND_KIND_CHANGE_ELEMENTS_Z_INDEX =
      EngineCommandKind._(12,
          _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_CHANGE_ELEMENTS_Z_INDEX');
  static const EngineCommandKind ENGINE_COMMAND_KIND_UPDATE_ELEMENTS_STYLE =
      EngineCommandKind._(13,
          _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_UPDATE_ELEMENTS_STYLE');
  static const EngineCommandKind ENGINE_COMMAND_KIND_UPDATE_GLOBAL_ELEMENTS =
      EngineCommandKind._(14,
          _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_UPDATE_GLOBAL_ELEMENTS');
  static const EngineCommandKind
      ENGINE_COMMAND_KIND_CREATE_SERIAL_NUMBER_TEXT_ELEMENTS =
      EngineCommandKind._(
          15,
          _omitEnumNames
              ? ''
              : 'ENGINE_COMMAND_KIND_CREATE_SERIAL_NUMBER_TEXT_ELEMENTS');
  static const EngineCommandKind ENGINE_COMMAND_KIND_START_TEXT_EDIT =
      EngineCommandKind._(
          16, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_START_TEXT_EDIT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_UPDATE_TEXT_EDIT =
      EngineCommandKind._(
          17, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_UPDATE_TEXT_EDIT');
  static const EngineCommandKind
      ENGINE_COMMAND_KIND_REFRESH_AUTO_RESIZE_TEXT_LAYOUTS_AFTER_FONT_LOAD =
      EngineCommandKind._(
          18,
          _omitEnumNames
              ? ''
              : 'ENGINE_COMMAND_KIND_REFRESH_AUTO_RESIZE_TEXT_LAYOUTS_AFTER_FONT_LOAD');
  static const EngineCommandKind ENGINE_COMMAND_KIND_FINISH_TEXT_EDIT =
      EngineCommandKind._(
          19, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_FINISH_TEXT_EDIT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_CANCEL_TEXT_EDIT =
      EngineCommandKind._(
          20, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_CANCEL_TEXT_EDIT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_START_EDIT =
      EngineCommandKind._(
          21, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_START_EDIT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_UPDATE_EDIT =
      EngineCommandKind._(
          22, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_UPDATE_EDIT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_FINISH_EDIT =
      EngineCommandKind._(
          23, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_FINISH_EDIT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_CANCEL_EDIT =
      EngineCommandKind._(
          24, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_CANCEL_EDIT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_SET_DRAG_PENDING =
      EngineCommandKind._(
          25, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_SET_DRAG_PENDING');
  static const EngineCommandKind ENGINE_COMMAND_KIND_CLEAR_DRAG_PENDING =
      EngineCommandKind._(
          26, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_CLEAR_DRAG_PENDING');
  static const EngineCommandKind ENGINE_COMMAND_KIND_START_BOX_SELECT =
      EngineCommandKind._(
          27, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_START_BOX_SELECT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_UPDATE_BOX_SELECT =
      EngineCommandKind._(
          28, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_UPDATE_BOX_SELECT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_FINISH_BOX_SELECT =
      EngineCommandKind._(
          29, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_FINISH_BOX_SELECT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_CANCEL_BOX_SELECT =
      EngineCommandKind._(
          30, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_CANCEL_BOX_SELECT');
  static const EngineCommandKind ENGINE_COMMAND_KIND_MOVE_CAMERA =
      EngineCommandKind._(
          31, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_MOVE_CAMERA');
  static const EngineCommandKind ENGINE_COMMAND_KIND_ZOOM_CAMERA =
      EngineCommandKind._(
          32, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_ZOOM_CAMERA');
  static const EngineCommandKind ENGINE_COMMAND_KIND_UNDO =
      EngineCommandKind._(33, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_UNDO');
  static const EngineCommandKind ENGINE_COMMAND_KIND_REDO =
      EngineCommandKind._(34, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_REDO');
  static const EngineCommandKind ENGINE_COMMAND_KIND_CLEAR_HISTORY =
      EngineCommandKind._(
          35, _omitEnumNames ? '' : 'ENGINE_COMMAND_KIND_CLEAR_HISTORY');

  static const $core.List<EngineCommandKind> values = <EngineCommandKind>[
    ENGINE_COMMAND_KIND_UNKNOWN,
    ENGINE_COMMAND_KIND_SELECT_ELEMENT,
    ENGINE_COMMAND_KIND_CLEAR_SELECTION,
    ENGINE_COMMAND_KIND_SELECT_ALL,
    ENGINE_COMMAND_KIND_CREATE_ELEMENT,
    ENGINE_COMMAND_KIND_UPDATE_CREATING_ELEMENT,
    ENGINE_COMMAND_KIND_ADD_ARROW_POINT,
    ENGINE_COMMAND_KIND_FINISH_CREATE_ELEMENT,
    ENGINE_COMMAND_KIND_CANCEL_CREATE_ELEMENT,
    ENGINE_COMMAND_KIND_DELETE_ELEMENTS,
    ENGINE_COMMAND_KIND_DUPLICATE_ELEMENTS,
    ENGINE_COMMAND_KIND_CHANGE_ELEMENT_Z_INDEX,
    ENGINE_COMMAND_KIND_CHANGE_ELEMENTS_Z_INDEX,
    ENGINE_COMMAND_KIND_UPDATE_ELEMENTS_STYLE,
    ENGINE_COMMAND_KIND_UPDATE_GLOBAL_ELEMENTS,
    ENGINE_COMMAND_KIND_CREATE_SERIAL_NUMBER_TEXT_ELEMENTS,
    ENGINE_COMMAND_KIND_START_TEXT_EDIT,
    ENGINE_COMMAND_KIND_UPDATE_TEXT_EDIT,
    ENGINE_COMMAND_KIND_REFRESH_AUTO_RESIZE_TEXT_LAYOUTS_AFTER_FONT_LOAD,
    ENGINE_COMMAND_KIND_FINISH_TEXT_EDIT,
    ENGINE_COMMAND_KIND_CANCEL_TEXT_EDIT,
    ENGINE_COMMAND_KIND_START_EDIT,
    ENGINE_COMMAND_KIND_UPDATE_EDIT,
    ENGINE_COMMAND_KIND_FINISH_EDIT,
    ENGINE_COMMAND_KIND_CANCEL_EDIT,
    ENGINE_COMMAND_KIND_SET_DRAG_PENDING,
    ENGINE_COMMAND_KIND_CLEAR_DRAG_PENDING,
    ENGINE_COMMAND_KIND_START_BOX_SELECT,
    ENGINE_COMMAND_KIND_UPDATE_BOX_SELECT,
    ENGINE_COMMAND_KIND_FINISH_BOX_SELECT,
    ENGINE_COMMAND_KIND_CANCEL_BOX_SELECT,
    ENGINE_COMMAND_KIND_MOVE_CAMERA,
    ENGINE_COMMAND_KIND_ZOOM_CAMERA,
    ENGINE_COMMAND_KIND_UNDO,
    ENGINE_COMMAND_KIND_REDO,
    ENGINE_COMMAND_KIND_CLEAR_HISTORY,
  ];

  static final $core.List<EngineCommandKind?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 35);
  static EngineCommandKind? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const EngineCommandKind._(super.value, super.name);
}

class ZIndexOperation extends $pb.ProtobufEnum {
  static const ZIndexOperation Z_INDEX_OPERATION_BRING_TO_FRONT =
      ZIndexOperation._(
          0, _omitEnumNames ? '' : 'Z_INDEX_OPERATION_BRING_TO_FRONT');
  static const ZIndexOperation Z_INDEX_OPERATION_SEND_TO_BACK =
      ZIndexOperation._(
          1, _omitEnumNames ? '' : 'Z_INDEX_OPERATION_SEND_TO_BACK');
  static const ZIndexOperation Z_INDEX_OPERATION_BRING_FORWARD =
      ZIndexOperation._(
          2, _omitEnumNames ? '' : 'Z_INDEX_OPERATION_BRING_FORWARD');
  static const ZIndexOperation Z_INDEX_OPERATION_SEND_BACKWARD =
      ZIndexOperation._(
          3, _omitEnumNames ? '' : 'Z_INDEX_OPERATION_SEND_BACKWARD');

  static const $core.List<ZIndexOperation> values = <ZIndexOperation>[
    Z_INDEX_OPERATION_BRING_TO_FRONT,
    Z_INDEX_OPERATION_SEND_TO_BACK,
    Z_INDEX_OPERATION_BRING_FORWARD,
    Z_INDEX_OPERATION_SEND_BACKWARD,
  ];

  static final $core.List<ZIndexOperation?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 3);
  static ZIndexOperation? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ZIndexOperation._(super.value, super.name);
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

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
