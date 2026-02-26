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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'engine.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'engine.pbenum.dart';

class DrawPoint extends $pb.GeneratedMessage {
  factory DrawPoint({
    $core.double? x,
    $core.double? y,
    $core.double? pressure,
    $fixnum.Int64? timestampUs,
  }) {
    final result = create();
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (pressure != null) result.pressure = pressure;
    if (timestampUs != null) result.timestampUs = timestampUs;
    return result;
  }

  DrawPoint._();

  factory DrawPoint.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DrawPoint.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DrawPoint',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'x')
    ..aD(2, _omitFieldNames ? '' : 'y')
    ..aD(3, _omitFieldNames ? '' : 'pressure')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'timestampUs', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DrawPoint clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DrawPoint copyWith(void Function(DrawPoint) updates) =>
      super.copyWith((message) => updates(message as DrawPoint)) as DrawPoint;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DrawPoint create() => DrawPoint._();
  @$core.override
  DrawPoint createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DrawPoint getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DrawPoint>(create);
  static DrawPoint? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get x => $_getN(0);
  @$pb.TagNumber(1)
  set x($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasX() => $_has(0);
  @$pb.TagNumber(1)
  void clearX() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get y => $_getN(1);
  @$pb.TagNumber(2)
  set y($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasY() => $_has(1);
  @$pb.TagNumber(2)
  void clearY() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get pressure => $_getN(2);
  @$pb.TagNumber(3)
  set pressure($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPressure() => $_has(2);
  @$pb.TagNumber(3)
  void clearPressure() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get timestampUs => $_getI64(3);
  @$pb.TagNumber(4)
  set timestampUs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTimestampUs() => $_has(3);
  @$pb.TagNumber(4)
  void clearTimestampUs() => $_clearField(4);
}

class DrawRect extends $pb.GeneratedMessage {
  factory DrawRect({
    $core.double? minX,
    $core.double? minY,
    $core.double? maxX,
    $core.double? maxY,
  }) {
    final result = create();
    if (minX != null) result.minX = minX;
    if (minY != null) result.minY = minY;
    if (maxX != null) result.maxX = maxX;
    if (maxY != null) result.maxY = maxY;
    return result;
  }

  DrawRect._();

  factory DrawRect.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DrawRect.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DrawRect',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'minX')
    ..aD(2, _omitFieldNames ? '' : 'minY')
    ..aD(3, _omitFieldNames ? '' : 'maxX')
    ..aD(4, _omitFieldNames ? '' : 'maxY')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DrawRect clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DrawRect copyWith(void Function(DrawRect) updates) =>
      super.copyWith((message) => updates(message as DrawRect)) as DrawRect;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DrawRect create() => DrawRect._();
  @$core.override
  DrawRect createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DrawRect getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<DrawRect>(create);
  static DrawRect? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get minX => $_getN(0);
  @$pb.TagNumber(1)
  set minX($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMinX() => $_has(0);
  @$pb.TagNumber(1)
  void clearMinX() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get minY => $_getN(1);
  @$pb.TagNumber(2)
  set minY($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMinY() => $_has(1);
  @$pb.TagNumber(2)
  void clearMinY() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get maxX => $_getN(2);
  @$pb.TagNumber(3)
  set maxX($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxX() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxX() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get maxY => $_getN(3);
  @$pb.TagNumber(4)
  set maxY($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxY() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxY() => $_clearField(4);
}

class CameraState extends $pb.GeneratedMessage {
  factory CameraState({
    DrawPoint? position,
    $core.double? zoom,
  }) {
    final result = create();
    if (position != null) result.position = position;
    if (zoom != null) result.zoom = zoom;
    return result;
  }

  CameraState._();

  factory CameraState.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CameraState.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CameraState',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aOM<DrawPoint>(1, _omitFieldNames ? '' : 'position',
        subBuilder: DrawPoint.create)
    ..aD(2, _omitFieldNames ? '' : 'zoom')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CameraState clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CameraState copyWith(void Function(CameraState) updates) =>
      super.copyWith((message) => updates(message as CameraState))
          as CameraState;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CameraState create() => CameraState._();
  @$core.override
  CameraState createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CameraState getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CameraState>(create);
  static CameraState? _defaultInstance;

  @$pb.TagNumber(1)
  DrawPoint get position => $_getN(0);
  @$pb.TagNumber(1)
  set position(DrawPoint value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPosition() => $_has(0);
  @$pb.TagNumber(1)
  void clearPosition() => $_clearField(1);
  @$pb.TagNumber(1)
  DrawPoint ensurePosition() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.double get zoom => $_getN(1);
  @$pb.TagNumber(2)
  set zoom($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasZoom() => $_has(1);
  @$pb.TagNumber(2)
  void clearZoom() => $_clearField(2);
}

class Element extends $pb.GeneratedMessage {
  factory Element({
    $core.String? id,
    ElementType? elementType,
    DrawRect? rect,
    $core.double? rotation,
    $core.double? opacity,
    $core.int? zIndex,
    $core.List<$core.int>? payload,
  }) {
    final result = create();
    if (id != null) result.id = id;
    if (elementType != null) result.elementType = elementType;
    if (rect != null) result.rect = rect;
    if (rotation != null) result.rotation = rotation;
    if (opacity != null) result.opacity = opacity;
    if (zIndex != null) result.zIndex = zIndex;
    if (payload != null) result.payload = payload;
    return result;
  }

  Element._();

  factory Element.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory Element.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'Element',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aE<ElementType>(2, _omitFieldNames ? '' : 'elementType',
        enumValues: ElementType.values)
    ..aOM<DrawRect>(3, _omitFieldNames ? '' : 'rect',
        subBuilder: DrawRect.create)
    ..aD(4, _omitFieldNames ? '' : 'rotation')
    ..aD(5, _omitFieldNames ? '' : 'opacity')
    ..aI(6, _omitFieldNames ? '' : 'zIndex')
    ..a<$core.List<$core.int>>(
        7, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Element clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  Element copyWith(void Function(Element) updates) =>
      super.copyWith((message) => updates(message as Element)) as Element;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static Element create() => Element._();
  @$core.override
  Element createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static Element getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<Element>(create);
  static Element? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get id => $_getSZ(0);
  @$pb.TagNumber(1)
  set id($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasId() => $_has(0);
  @$pb.TagNumber(1)
  void clearId() => $_clearField(1);

  @$pb.TagNumber(2)
  ElementType get elementType => $_getN(1);
  @$pb.TagNumber(2)
  set elementType(ElementType value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasElementType() => $_has(1);
  @$pb.TagNumber(2)
  void clearElementType() => $_clearField(2);

  @$pb.TagNumber(3)
  DrawRect get rect => $_getN(2);
  @$pb.TagNumber(3)
  set rect(DrawRect value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasRect() => $_has(2);
  @$pb.TagNumber(3)
  void clearRect() => $_clearField(3);
  @$pb.TagNumber(3)
  DrawRect ensureRect() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.double get rotation => $_getN(3);
  @$pb.TagNumber(4)
  set rotation($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRotation() => $_has(3);
  @$pb.TagNumber(4)
  void clearRotation() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get opacity => $_getN(4);
  @$pb.TagNumber(5)
  set opacity($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOpacity() => $_has(4);
  @$pb.TagNumber(5)
  void clearOpacity() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get zIndex => $_getIZ(5);
  @$pb.TagNumber(6)
  set zIndex($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasZIndex() => $_has(5);
  @$pb.TagNumber(6)
  void clearZIndex() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.List<$core.int> get payload => $_getN(6);
  @$pb.TagNumber(7)
  set payload($core.List<$core.int> value) => $_setBytes(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPayload() => $_has(6);
  @$pb.TagNumber(7)
  void clearPayload() => $_clearField(7);
}

class EngineConfig extends $pb.GeneratedMessage {
  factory EngineConfig({
    $core.int? schemaVersion,
    $core.String? localeTag,
    $core.double? scaleFactor,
    $fixnum.Int64? requestedCapabilities,
    $fixnum.Int64? deterministicSeed,
  }) {
    final result = create();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (localeTag != null) result.localeTag = localeTag;
    if (scaleFactor != null) result.scaleFactor = scaleFactor;
    if (requestedCapabilities != null)
      result.requestedCapabilities = requestedCapabilities;
    if (deterministicSeed != null) result.deterministicSeed = deterministicSeed;
    return result;
  }

  EngineConfig._();

  factory EngineConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EngineConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EngineConfig',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'localeTag')
    ..aD(3, _omitFieldNames ? '' : 'scaleFactor')
    ..a<$fixnum.Int64>(
        4, _omitFieldNames ? '' : 'requestedCapabilities', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        5, _omitFieldNames ? '' : 'deterministicSeed', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineConfig copyWith(void Function(EngineConfig) updates) =>
      super.copyWith((message) => updates(message as EngineConfig))
          as EngineConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineConfig create() => EngineConfig._();
  @$core.override
  EngineConfig createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EngineConfig getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EngineConfig>(create);
  static EngineConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get localeTag => $_getSZ(1);
  @$pb.TagNumber(2)
  set localeTag($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLocaleTag() => $_has(1);
  @$pb.TagNumber(2)
  void clearLocaleTag() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get scaleFactor => $_getN(2);
  @$pb.TagNumber(3)
  set scaleFactor($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasScaleFactor() => $_has(2);
  @$pb.TagNumber(3)
  void clearScaleFactor() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get requestedCapabilities => $_getI64(3);
  @$pb.TagNumber(4)
  set requestedCapabilities($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRequestedCapabilities() => $_has(3);
  @$pb.TagNumber(4)
  void clearRequestedCapabilities() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get deterministicSeed => $_getI64(4);
  @$pb.TagNumber(5)
  set deterministicSeed($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasDeterministicSeed() => $_has(4);
  @$pb.TagNumber(5)
  void clearDeterministicSeed() => $_clearField(5);
}

class CreateElementCommand extends $pb.GeneratedMessage {
  factory CreateElementCommand({
    ElementType? elementType,
    $core.String? elementId,
    DrawPoint? position,
    $core.List<$core.int>? initialPayload,
    $core.bool? maintainAspectRatio,
    $core.bool? createFromCenter,
    $core.bool? snapOverride,
  }) {
    final result = create();
    if (elementType != null) result.elementType = elementType;
    if (elementId != null) result.elementId = elementId;
    if (position != null) result.position = position;
    if (initialPayload != null) result.initialPayload = initialPayload;
    if (maintainAspectRatio != null)
      result.maintainAspectRatio = maintainAspectRatio;
    if (createFromCenter != null) result.createFromCenter = createFromCenter;
    if (snapOverride != null) result.snapOverride = snapOverride;
    return result;
  }

  CreateElementCommand._();

  factory CreateElementCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateElementCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateElementCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aE<ElementType>(1, _omitFieldNames ? '' : 'elementType',
        enumValues: ElementType.values)
    ..aOS(2, _omitFieldNames ? '' : 'elementId')
    ..aOM<DrawPoint>(3, _omitFieldNames ? '' : 'position',
        subBuilder: DrawPoint.create)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'initialPayload', $pb.PbFieldType.OY)
    ..aOB(5, _omitFieldNames ? '' : 'maintainAspectRatio')
    ..aOB(6, _omitFieldNames ? '' : 'createFromCenter')
    ..aOB(7, _omitFieldNames ? '' : 'snapOverride')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateElementCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateElementCommand copyWith(void Function(CreateElementCommand) updates) =>
      super.copyWith((message) => updates(message as CreateElementCommand))
          as CreateElementCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateElementCommand create() => CreateElementCommand._();
  @$core.override
  CreateElementCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateElementCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CreateElementCommand>(create);
  static CreateElementCommand? _defaultInstance;

  @$pb.TagNumber(1)
  ElementType get elementType => $_getN(0);
  @$pb.TagNumber(1)
  set elementType(ElementType value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasElementType() => $_has(0);
  @$pb.TagNumber(1)
  void clearElementType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get elementId => $_getSZ(1);
  @$pb.TagNumber(2)
  set elementId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasElementId() => $_has(1);
  @$pb.TagNumber(2)
  void clearElementId() => $_clearField(2);

  @$pb.TagNumber(3)
  DrawPoint get position => $_getN(2);
  @$pb.TagNumber(3)
  set position(DrawPoint value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPosition() => $_has(2);
  @$pb.TagNumber(3)
  void clearPosition() => $_clearField(3);
  @$pb.TagNumber(3)
  DrawPoint ensurePosition() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.List<$core.int> get initialPayload => $_getN(3);
  @$pb.TagNumber(4)
  set initialPayload($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasInitialPayload() => $_has(3);
  @$pb.TagNumber(4)
  void clearInitialPayload() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get maintainAspectRatio => $_getBF(4);
  @$pb.TagNumber(5)
  set maintainAspectRatio($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMaintainAspectRatio() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaintainAspectRatio() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.bool get createFromCenter => $_getBF(5);
  @$pb.TagNumber(6)
  set createFromCenter($core.bool value) => $_setBool(5, value);
  @$pb.TagNumber(6)
  $core.bool hasCreateFromCenter() => $_has(5);
  @$pb.TagNumber(6)
  void clearCreateFromCenter() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get snapOverride => $_getBF(6);
  @$pb.TagNumber(7)
  set snapOverride($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasSnapOverride() => $_has(6);
  @$pb.TagNumber(7)
  void clearSnapOverride() => $_clearField(7);
}

class SelectElementCommand extends $pb.GeneratedMessage {
  factory SelectElementCommand({
    $core.String? elementId,
    $core.bool? addToSelection,
    DrawPoint? position,
  }) {
    final result = create();
    if (elementId != null) result.elementId = elementId;
    if (addToSelection != null) result.addToSelection = addToSelection;
    if (position != null) result.position = position;
    return result;
  }

  SelectElementCommand._();

  factory SelectElementCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SelectElementCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SelectElementCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'elementId')
    ..aOB(2, _omitFieldNames ? '' : 'addToSelection')
    ..aOM<DrawPoint>(3, _omitFieldNames ? '' : 'position',
        subBuilder: DrawPoint.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SelectElementCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SelectElementCommand copyWith(void Function(SelectElementCommand) updates) =>
      super.copyWith((message) => updates(message as SelectElementCommand))
          as SelectElementCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SelectElementCommand create() => SelectElementCommand._();
  @$core.override
  SelectElementCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SelectElementCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SelectElementCommand>(create);
  static SelectElementCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get elementId => $_getSZ(0);
  @$pb.TagNumber(1)
  set elementId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasElementId() => $_has(0);
  @$pb.TagNumber(1)
  void clearElementId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get addToSelection => $_getBF(1);
  @$pb.TagNumber(2)
  set addToSelection($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasAddToSelection() => $_has(1);
  @$pb.TagNumber(2)
  void clearAddToSelection() => $_clearField(2);

  @$pb.TagNumber(3)
  DrawPoint get position => $_getN(2);
  @$pb.TagNumber(3)
  set position(DrawPoint value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPosition() => $_has(2);
  @$pb.TagNumber(3)
  void clearPosition() => $_clearField(3);
  @$pb.TagNumber(3)
  DrawPoint ensurePosition() => $_ensure(2);
}

class UpdateCreatingElementCommand extends $pb.GeneratedMessage {
  factory UpdateCreatingElementCommand({
    $core.Iterable<DrawPoint>? positions,
    $core.bool? maintainAspectRatio,
    $core.bool? createFromCenter,
    $core.bool? snapOverride,
  }) {
    final result = create();
    if (positions != null) result.positions.addAll(positions);
    if (maintainAspectRatio != null)
      result.maintainAspectRatio = maintainAspectRatio;
    if (createFromCenter != null) result.createFromCenter = createFromCenter;
    if (snapOverride != null) result.snapOverride = snapOverride;
    return result;
  }

  UpdateCreatingElementCommand._();

  factory UpdateCreatingElementCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateCreatingElementCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateCreatingElementCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..pPM<DrawPoint>(1, _omitFieldNames ? '' : 'positions',
        subBuilder: DrawPoint.create)
    ..aOB(2, _omitFieldNames ? '' : 'maintainAspectRatio')
    ..aOB(3, _omitFieldNames ? '' : 'createFromCenter')
    ..aOB(4, _omitFieldNames ? '' : 'snapOverride')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateCreatingElementCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateCreatingElementCommand copyWith(
          void Function(UpdateCreatingElementCommand) updates) =>
      super.copyWith(
              (message) => updates(message as UpdateCreatingElementCommand))
          as UpdateCreatingElementCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateCreatingElementCommand create() =>
      UpdateCreatingElementCommand._();
  @$core.override
  UpdateCreatingElementCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateCreatingElementCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateCreatingElementCommand>(create);
  static UpdateCreatingElementCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<DrawPoint> get positions => $_getList(0);

  @$pb.TagNumber(2)
  $core.bool get maintainAspectRatio => $_getBF(1);
  @$pb.TagNumber(2)
  set maintainAspectRatio($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMaintainAspectRatio() => $_has(1);
  @$pb.TagNumber(2)
  void clearMaintainAspectRatio() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get createFromCenter => $_getBF(2);
  @$pb.TagNumber(3)
  set createFromCenter($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCreateFromCenter() => $_has(2);
  @$pb.TagNumber(3)
  void clearCreateFromCenter() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get snapOverride => $_getBF(3);
  @$pb.TagNumber(4)
  set snapOverride($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSnapOverride() => $_has(3);
  @$pb.TagNumber(4)
  void clearSnapOverride() => $_clearField(4);
}

class AddArrowPointCommand extends $pb.GeneratedMessage {
  factory AddArrowPointCommand({
    DrawPoint? position,
    $core.bool? snapOverride,
  }) {
    final result = create();
    if (position != null) result.position = position;
    if (snapOverride != null) result.snapOverride = snapOverride;
    return result;
  }

  AddArrowPointCommand._();

  factory AddArrowPointCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AddArrowPointCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AddArrowPointCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aOM<DrawPoint>(1, _omitFieldNames ? '' : 'position',
        subBuilder: DrawPoint.create)
    ..aOB(2, _omitFieldNames ? '' : 'snapOverride')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AddArrowPointCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AddArrowPointCommand copyWith(void Function(AddArrowPointCommand) updates) =>
      super.copyWith((message) => updates(message as AddArrowPointCommand))
          as AddArrowPointCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AddArrowPointCommand create() => AddArrowPointCommand._();
  @$core.override
  AddArrowPointCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AddArrowPointCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AddArrowPointCommand>(create);
  static AddArrowPointCommand? _defaultInstance;

  @$pb.TagNumber(1)
  DrawPoint get position => $_getN(0);
  @$pb.TagNumber(1)
  set position(DrawPoint value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPosition() => $_has(0);
  @$pb.TagNumber(1)
  void clearPosition() => $_clearField(1);
  @$pb.TagNumber(1)
  DrawPoint ensurePosition() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.bool get snapOverride => $_getBF(1);
  @$pb.TagNumber(2)
  set snapOverride($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSnapOverride() => $_has(1);
  @$pb.TagNumber(2)
  void clearSnapOverride() => $_clearField(2);
}

class DeleteElementsCommand extends $pb.GeneratedMessage {
  factory DeleteElementsCommand({
    $core.Iterable<$core.String>? elementIds,
  }) {
    final result = create();
    if (elementIds != null) result.elementIds.addAll(elementIds);
    return result;
  }

  DeleteElementsCommand._();

  factory DeleteElementsCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeleteElementsCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeleteElementsCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'elementIds')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteElementsCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeleteElementsCommand copyWith(
          void Function(DeleteElementsCommand) updates) =>
      super.copyWith((message) => updates(message as DeleteElementsCommand))
          as DeleteElementsCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeleteElementsCommand create() => DeleteElementsCommand._();
  @$core.override
  DeleteElementsCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeleteElementsCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeleteElementsCommand>(create);
  static DeleteElementsCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get elementIds => $_getList(0);
}

class UpdateElementsStyleCommand extends $pb.GeneratedMessage {
  factory UpdateElementsStyleCommand({
    $core.Iterable<$core.String>? elementIds,
    $core.List<$core.int>? stylePayload,
  }) {
    final result = create();
    if (elementIds != null) result.elementIds.addAll(elementIds);
    if (stylePayload != null) result.stylePayload = stylePayload;
    return result;
  }

  UpdateElementsStyleCommand._();

  factory UpdateElementsStyleCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateElementsStyleCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateElementsStyleCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'elementIds')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'stylePayload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateElementsStyleCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateElementsStyleCommand copyWith(
          void Function(UpdateElementsStyleCommand) updates) =>
      super.copyWith(
              (message) => updates(message as UpdateElementsStyleCommand))
          as UpdateElementsStyleCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateElementsStyleCommand create() => UpdateElementsStyleCommand._();
  @$core.override
  UpdateElementsStyleCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateElementsStyleCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateElementsStyleCommand>(create);
  static UpdateElementsStyleCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get elementIds => $_getList(0);

  @$pb.TagNumber(2)
  $core.List<$core.int> get stylePayload => $_getN(1);
  @$pb.TagNumber(2)
  set stylePayload($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStylePayload() => $_has(1);
  @$pb.TagNumber(2)
  void clearStylePayload() => $_clearField(2);
}

class DuplicateElementsCommand extends $pb.GeneratedMessage {
  factory DuplicateElementsCommand({
    $core.Iterable<$core.String>? elementIds,
    $core.double? offsetX,
    $core.double? offsetY,
  }) {
    final result = create();
    if (elementIds != null) result.elementIds.addAll(elementIds);
    if (offsetX != null) result.offsetX = offsetX;
    if (offsetY != null) result.offsetY = offsetY;
    return result;
  }

  DuplicateElementsCommand._();

  factory DuplicateElementsCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DuplicateElementsCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DuplicateElementsCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'elementIds')
    ..aD(2, _omitFieldNames ? '' : 'offsetX')
    ..aD(3, _omitFieldNames ? '' : 'offsetY')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DuplicateElementsCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DuplicateElementsCommand copyWith(
          void Function(DuplicateElementsCommand) updates) =>
      super.copyWith((message) => updates(message as DuplicateElementsCommand))
          as DuplicateElementsCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DuplicateElementsCommand create() => DuplicateElementsCommand._();
  @$core.override
  DuplicateElementsCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DuplicateElementsCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DuplicateElementsCommand>(create);
  static DuplicateElementsCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get elementIds => $_getList(0);

  @$pb.TagNumber(2)
  $core.double get offsetX => $_getN(1);
  @$pb.TagNumber(2)
  set offsetX($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOffsetX() => $_has(1);
  @$pb.TagNumber(2)
  void clearOffsetX() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get offsetY => $_getN(2);
  @$pb.TagNumber(3)
  set offsetY($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOffsetY() => $_has(2);
  @$pb.TagNumber(3)
  void clearOffsetY() => $_clearField(3);
}

class ChangeElementZIndexCommand extends $pb.GeneratedMessage {
  factory ChangeElementZIndexCommand({
    $core.String? elementId,
    ZIndexOperation? operation,
  }) {
    final result = create();
    if (elementId != null) result.elementId = elementId;
    if (operation != null) result.operation = operation;
    return result;
  }

  ChangeElementZIndexCommand._();

  factory ChangeElementZIndexCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChangeElementZIndexCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChangeElementZIndexCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'elementId')
    ..aE<ZIndexOperation>(2, _omitFieldNames ? '' : 'operation',
        enumValues: ZIndexOperation.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChangeElementZIndexCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChangeElementZIndexCommand copyWith(
          void Function(ChangeElementZIndexCommand) updates) =>
      super.copyWith(
              (message) => updates(message as ChangeElementZIndexCommand))
          as ChangeElementZIndexCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChangeElementZIndexCommand create() => ChangeElementZIndexCommand._();
  @$core.override
  ChangeElementZIndexCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChangeElementZIndexCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChangeElementZIndexCommand>(create);
  static ChangeElementZIndexCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get elementId => $_getSZ(0);
  @$pb.TagNumber(1)
  set elementId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasElementId() => $_has(0);
  @$pb.TagNumber(1)
  void clearElementId() => $_clearField(1);

  @$pb.TagNumber(2)
  ZIndexOperation get operation => $_getN(1);
  @$pb.TagNumber(2)
  set operation(ZIndexOperation value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasOperation() => $_has(1);
  @$pb.TagNumber(2)
  void clearOperation() => $_clearField(2);
}

class ChangeElementsZIndexCommand extends $pb.GeneratedMessage {
  factory ChangeElementsZIndexCommand({
    $core.Iterable<$core.String>? elementIds,
    ZIndexOperation? operation,
  }) {
    final result = create();
    if (elementIds != null) result.elementIds.addAll(elementIds);
    if (operation != null) result.operation = operation;
    return result;
  }

  ChangeElementsZIndexCommand._();

  factory ChangeElementsZIndexCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ChangeElementsZIndexCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ChangeElementsZIndexCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'elementIds')
    ..aE<ZIndexOperation>(2, _omitFieldNames ? '' : 'operation',
        enumValues: ZIndexOperation.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChangeElementsZIndexCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ChangeElementsZIndexCommand copyWith(
          void Function(ChangeElementsZIndexCommand) updates) =>
      super.copyWith(
              (message) => updates(message as ChangeElementsZIndexCommand))
          as ChangeElementsZIndexCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ChangeElementsZIndexCommand create() =>
      ChangeElementsZIndexCommand._();
  @$core.override
  ChangeElementsZIndexCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ChangeElementsZIndexCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ChangeElementsZIndexCommand>(create);
  static ChangeElementsZIndexCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get elementIds => $_getList(0);

  @$pb.TagNumber(2)
  ZIndexOperation get operation => $_getN(1);
  @$pb.TagNumber(2)
  set operation(ZIndexOperation value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasOperation() => $_has(1);
  @$pb.TagNumber(2)
  void clearOperation() => $_clearField(2);
}

class UpdateGlobalElementsCommand extends $pb.GeneratedMessage {
  factory UpdateGlobalElementsCommand({
    $core.List<$core.int>? payload,
  }) {
    final result = create();
    if (payload != null) result.payload = payload;
    return result;
  }

  UpdateGlobalElementsCommand._();

  factory UpdateGlobalElementsCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateGlobalElementsCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateGlobalElementsCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateGlobalElementsCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateGlobalElementsCommand copyWith(
          void Function(UpdateGlobalElementsCommand) updates) =>
      super.copyWith(
              (message) => updates(message as UpdateGlobalElementsCommand))
          as UpdateGlobalElementsCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateGlobalElementsCommand create() =>
      UpdateGlobalElementsCommand._();
  @$core.override
  UpdateGlobalElementsCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateGlobalElementsCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateGlobalElementsCommand>(create);
  static UpdateGlobalElementsCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get payload => $_getN(0);
  @$pb.TagNumber(1)
  set payload($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPayload() => $_has(0);
  @$pb.TagNumber(1)
  void clearPayload() => $_clearField(1);
}

class CreateSerialNumberTextElementsCommand extends $pb.GeneratedMessage {
  factory CreateSerialNumberTextElementsCommand({
    $core.Iterable<$core.String>? elementIds,
  }) {
    final result = create();
    if (elementIds != null) result.elementIds.addAll(elementIds);
    return result;
  }

  CreateSerialNumberTextElementsCommand._();

  factory CreateSerialNumberTextElementsCommand.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CreateSerialNumberTextElementsCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CreateSerialNumberTextElementsCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..pPS(1, _omitFieldNames ? '' : 'elementIds')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateSerialNumberTextElementsCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CreateSerialNumberTextElementsCommand copyWith(
          void Function(CreateSerialNumberTextElementsCommand) updates) =>
      super.copyWith((message) =>
              updates(message as CreateSerialNumberTextElementsCommand))
          as CreateSerialNumberTextElementsCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CreateSerialNumberTextElementsCommand create() =>
      CreateSerialNumberTextElementsCommand._();
  @$core.override
  CreateSerialNumberTextElementsCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CreateSerialNumberTextElementsCommand getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<
          CreateSerialNumberTextElementsCommand>(create);
  static CreateSerialNumberTextElementsCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$core.String> get elementIds => $_getList(0);
}

class StartTextEditCommand extends $pb.GeneratedMessage {
  factory StartTextEditCommand({
    $core.String? elementId,
    DrawPoint? position,
  }) {
    final result = create();
    if (elementId != null) result.elementId = elementId;
    if (position != null) result.position = position;
    return result;
  }

  StartTextEditCommand._();

  factory StartTextEditCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StartTextEditCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartTextEditCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'elementId')
    ..aOM<DrawPoint>(2, _omitFieldNames ? '' : 'position',
        subBuilder: DrawPoint.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartTextEditCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartTextEditCommand copyWith(void Function(StartTextEditCommand) updates) =>
      super.copyWith((message) => updates(message as StartTextEditCommand))
          as StartTextEditCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StartTextEditCommand create() => StartTextEditCommand._();
  @$core.override
  StartTextEditCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StartTextEditCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartTextEditCommand>(create);
  static StartTextEditCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get elementId => $_getSZ(0);
  @$pb.TagNumber(1)
  set elementId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasElementId() => $_has(0);
  @$pb.TagNumber(1)
  void clearElementId() => $_clearField(1);

  @$pb.TagNumber(2)
  DrawPoint get position => $_getN(1);
  @$pb.TagNumber(2)
  set position(DrawPoint value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPosition() => $_has(1);
  @$pb.TagNumber(2)
  void clearPosition() => $_clearField(2);
  @$pb.TagNumber(2)
  DrawPoint ensurePosition() => $_ensure(1);
}

class UpdateTextEditCommand extends $pb.GeneratedMessage {
  factory UpdateTextEditCommand({
    $core.String? text,
    DrawRect? rect,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (rect != null) result.rect = rect;
    return result;
  }

  UpdateTextEditCommand._();

  factory UpdateTextEditCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateTextEditCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateTextEditCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOM<DrawRect>(2, _omitFieldNames ? '' : 'rect',
        subBuilder: DrawRect.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateTextEditCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateTextEditCommand copyWith(
          void Function(UpdateTextEditCommand) updates) =>
      super.copyWith((message) => updates(message as UpdateTextEditCommand))
          as UpdateTextEditCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateTextEditCommand create() => UpdateTextEditCommand._();
  @$core.override
  UpdateTextEditCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateTextEditCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateTextEditCommand>(create);
  static UpdateTextEditCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  DrawRect get rect => $_getN(1);
  @$pb.TagNumber(2)
  set rect(DrawRect value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasRect() => $_has(1);
  @$pb.TagNumber(2)
  void clearRect() => $_clearField(2);
  @$pb.TagNumber(2)
  DrawRect ensureRect() => $_ensure(1);
}

class FinishTextEditCommand extends $pb.GeneratedMessage {
  factory FinishTextEditCommand({
    $core.String? elementId,
    $core.String? text,
    $core.bool? isNew,
  }) {
    final result = create();
    if (elementId != null) result.elementId = elementId;
    if (text != null) result.text = text;
    if (isNew != null) result.isNew = isNew;
    return result;
  }

  FinishTextEditCommand._();

  factory FinishTextEditCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FinishTextEditCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FinishTextEditCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'elementId')
    ..aOS(2, _omitFieldNames ? '' : 'text')
    ..aOB(3, _omitFieldNames ? '' : 'isNew')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishTextEditCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FinishTextEditCommand copyWith(
          void Function(FinishTextEditCommand) updates) =>
      super.copyWith((message) => updates(message as FinishTextEditCommand))
          as FinishTextEditCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FinishTextEditCommand create() => FinishTextEditCommand._();
  @$core.override
  FinishTextEditCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FinishTextEditCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FinishTextEditCommand>(create);
  static FinishTextEditCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get elementId => $_getSZ(0);
  @$pb.TagNumber(1)
  set elementId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasElementId() => $_has(0);
  @$pb.TagNumber(1)
  void clearElementId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get text => $_getSZ(1);
  @$pb.TagNumber(2)
  set text($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasText() => $_has(1);
  @$pb.TagNumber(2)
  void clearText() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.bool get isNew => $_getBF(2);
  @$pb.TagNumber(3)
  set isNew($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIsNew() => $_has(2);
  @$pb.TagNumber(3)
  void clearIsNew() => $_clearField(3);
}

class StartEditCommand extends $pb.GeneratedMessage {
  factory StartEditCommand({
    $core.String? operationId,
    DrawPoint? position,
    $core.List<$core.int>? params,
  }) {
    final result = create();
    if (operationId != null) result.operationId = operationId;
    if (position != null) result.position = position;
    if (params != null) result.params = params;
    return result;
  }

  StartEditCommand._();

  factory StartEditCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StartEditCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartEditCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'operationId')
    ..aOM<DrawPoint>(2, _omitFieldNames ? '' : 'position',
        subBuilder: DrawPoint.create)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'params', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartEditCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartEditCommand copyWith(void Function(StartEditCommand) updates) =>
      super.copyWith((message) => updates(message as StartEditCommand))
          as StartEditCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StartEditCommand create() => StartEditCommand._();
  @$core.override
  StartEditCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StartEditCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartEditCommand>(create);
  static StartEditCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get operationId => $_getSZ(0);
  @$pb.TagNumber(1)
  set operationId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOperationId() => $_has(0);
  @$pb.TagNumber(1)
  void clearOperationId() => $_clearField(1);

  @$pb.TagNumber(2)
  DrawPoint get position => $_getN(1);
  @$pb.TagNumber(2)
  set position(DrawPoint value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPosition() => $_has(1);
  @$pb.TagNumber(2)
  void clearPosition() => $_clearField(2);
  @$pb.TagNumber(2)
  DrawPoint ensurePosition() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.List<$core.int> get params => $_getN(2);
  @$pb.TagNumber(3)
  set params($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasParams() => $_has(2);
  @$pb.TagNumber(3)
  void clearParams() => $_clearField(3);
}

class UpdateEditCommand extends $pb.GeneratedMessage {
  factory UpdateEditCommand({
    DrawPoint? currentPosition,
    $core.List<$core.int>? modifiers,
  }) {
    final result = create();
    if (currentPosition != null) result.currentPosition = currentPosition;
    if (modifiers != null) result.modifiers = modifiers;
    return result;
  }

  UpdateEditCommand._();

  factory UpdateEditCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateEditCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateEditCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aOM<DrawPoint>(1, _omitFieldNames ? '' : 'currentPosition',
        subBuilder: DrawPoint.create)
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'modifiers', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateEditCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateEditCommand copyWith(void Function(UpdateEditCommand) updates) =>
      super.copyWith((message) => updates(message as UpdateEditCommand))
          as UpdateEditCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateEditCommand create() => UpdateEditCommand._();
  @$core.override
  UpdateEditCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateEditCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateEditCommand>(create);
  static UpdateEditCommand? _defaultInstance;

  @$pb.TagNumber(1)
  DrawPoint get currentPosition => $_getN(0);
  @$pb.TagNumber(1)
  set currentPosition(DrawPoint value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCurrentPosition() => $_has(0);
  @$pb.TagNumber(1)
  void clearCurrentPosition() => $_clearField(1);
  @$pb.TagNumber(1)
  DrawPoint ensureCurrentPosition() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.List<$core.int> get modifiers => $_getN(1);
  @$pb.TagNumber(2)
  set modifiers($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModifiers() => $_has(1);
  @$pb.TagNumber(2)
  void clearModifiers() => $_clearField(2);
}

class SetDragPendingCommand extends $pb.GeneratedMessage {
  factory SetDragPendingCommand({
    DrawPoint? pointerDownPosition,
    $core.String? intent,
  }) {
    final result = create();
    if (pointerDownPosition != null)
      result.pointerDownPosition = pointerDownPosition;
    if (intent != null) result.intent = intent;
    return result;
  }

  SetDragPendingCommand._();

  factory SetDragPendingCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SetDragPendingCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SetDragPendingCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aOM<DrawPoint>(1, _omitFieldNames ? '' : 'pointerDownPosition',
        subBuilder: DrawPoint.create)
    ..aOS(2, _omitFieldNames ? '' : 'intent')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetDragPendingCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SetDragPendingCommand copyWith(
          void Function(SetDragPendingCommand) updates) =>
      super.copyWith((message) => updates(message as SetDragPendingCommand))
          as SetDragPendingCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SetDragPendingCommand create() => SetDragPendingCommand._();
  @$core.override
  SetDragPendingCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SetDragPendingCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SetDragPendingCommand>(create);
  static SetDragPendingCommand? _defaultInstance;

  @$pb.TagNumber(1)
  DrawPoint get pointerDownPosition => $_getN(0);
  @$pb.TagNumber(1)
  set pointerDownPosition(DrawPoint value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasPointerDownPosition() => $_has(0);
  @$pb.TagNumber(1)
  void clearPointerDownPosition() => $_clearField(1);
  @$pb.TagNumber(1)
  DrawPoint ensurePointerDownPosition() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get intent => $_getSZ(1);
  @$pb.TagNumber(2)
  set intent($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIntent() => $_has(1);
  @$pb.TagNumber(2)
  void clearIntent() => $_clearField(2);
}

class StartBoxSelectCommand extends $pb.GeneratedMessage {
  factory StartBoxSelectCommand({
    DrawPoint? startPosition,
  }) {
    final result = create();
    if (startPosition != null) result.startPosition = startPosition;
    return result;
  }

  StartBoxSelectCommand._();

  factory StartBoxSelectCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StartBoxSelectCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StartBoxSelectCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aOM<DrawPoint>(1, _omitFieldNames ? '' : 'startPosition',
        subBuilder: DrawPoint.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartBoxSelectCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StartBoxSelectCommand copyWith(
          void Function(StartBoxSelectCommand) updates) =>
      super.copyWith((message) => updates(message as StartBoxSelectCommand))
          as StartBoxSelectCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StartBoxSelectCommand create() => StartBoxSelectCommand._();
  @$core.override
  StartBoxSelectCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StartBoxSelectCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StartBoxSelectCommand>(create);
  static StartBoxSelectCommand? _defaultInstance;

  @$pb.TagNumber(1)
  DrawPoint get startPosition => $_getN(0);
  @$pb.TagNumber(1)
  set startPosition(DrawPoint value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStartPosition() => $_has(0);
  @$pb.TagNumber(1)
  void clearStartPosition() => $_clearField(1);
  @$pb.TagNumber(1)
  DrawPoint ensureStartPosition() => $_ensure(0);
}

class UpdateBoxSelectCommand extends $pb.GeneratedMessage {
  factory UpdateBoxSelectCommand({
    DrawPoint? currentPosition,
  }) {
    final result = create();
    if (currentPosition != null) result.currentPosition = currentPosition;
    return result;
  }

  UpdateBoxSelectCommand._();

  factory UpdateBoxSelectCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory UpdateBoxSelectCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'UpdateBoxSelectCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aOM<DrawPoint>(1, _omitFieldNames ? '' : 'currentPosition',
        subBuilder: DrawPoint.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateBoxSelectCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  UpdateBoxSelectCommand copyWith(
          void Function(UpdateBoxSelectCommand) updates) =>
      super.copyWith((message) => updates(message as UpdateBoxSelectCommand))
          as UpdateBoxSelectCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static UpdateBoxSelectCommand create() => UpdateBoxSelectCommand._();
  @$core.override
  UpdateBoxSelectCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static UpdateBoxSelectCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<UpdateBoxSelectCommand>(create);
  static UpdateBoxSelectCommand? _defaultInstance;

  @$pb.TagNumber(1)
  DrawPoint get currentPosition => $_getN(0);
  @$pb.TagNumber(1)
  set currentPosition(DrawPoint value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasCurrentPosition() => $_has(0);
  @$pb.TagNumber(1)
  void clearCurrentPosition() => $_clearField(1);
  @$pb.TagNumber(1)
  DrawPoint ensureCurrentPosition() => $_ensure(0);
}

class MoveCameraCommand extends $pb.GeneratedMessage {
  factory MoveCameraCommand({
    $core.double? dx,
    $core.double? dy,
  }) {
    final result = create();
    if (dx != null) result.dx = dx;
    if (dy != null) result.dy = dy;
    return result;
  }

  MoveCameraCommand._();

  factory MoveCameraCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory MoveCameraCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'MoveCameraCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'dx')
    ..aD(2, _omitFieldNames ? '' : 'dy')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoveCameraCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  MoveCameraCommand copyWith(void Function(MoveCameraCommand) updates) =>
      super.copyWith((message) => updates(message as MoveCameraCommand))
          as MoveCameraCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static MoveCameraCommand create() => MoveCameraCommand._();
  @$core.override
  MoveCameraCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static MoveCameraCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<MoveCameraCommand>(create);
  static MoveCameraCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get dx => $_getN(0);
  @$pb.TagNumber(1)
  set dx($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDx() => $_has(0);
  @$pb.TagNumber(1)
  void clearDx() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get dy => $_getN(1);
  @$pb.TagNumber(2)
  set dy($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDy() => $_has(1);
  @$pb.TagNumber(2)
  void clearDy() => $_clearField(2);
}

class ZoomCameraCommand extends $pb.GeneratedMessage {
  factory ZoomCameraCommand({
    $core.double? scale,
    DrawPoint? center,
  }) {
    final result = create();
    if (scale != null) result.scale = scale;
    if (center != null) result.center = center;
    return result;
  }

  ZoomCameraCommand._();

  factory ZoomCameraCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ZoomCameraCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ZoomCameraCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'scale')
    ..aOM<DrawPoint>(2, _omitFieldNames ? '' : 'center',
        subBuilder: DrawPoint.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ZoomCameraCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ZoomCameraCommand copyWith(void Function(ZoomCameraCommand) updates) =>
      super.copyWith((message) => updates(message as ZoomCameraCommand))
          as ZoomCameraCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ZoomCameraCommand create() => ZoomCameraCommand._();
  @$core.override
  ZoomCameraCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ZoomCameraCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ZoomCameraCommand>(create);
  static ZoomCameraCommand? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get scale => $_getN(0);
  @$pb.TagNumber(1)
  set scale($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasScale() => $_has(0);
  @$pb.TagNumber(1)
  void clearScale() => $_clearField(1);

  @$pb.TagNumber(2)
  DrawPoint get center => $_getN(1);
  @$pb.TagNumber(2)
  set center(DrawPoint value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCenter() => $_has(1);
  @$pb.TagNumber(2)
  void clearCenter() => $_clearField(2);
  @$pb.TagNumber(2)
  DrawPoint ensureCenter() => $_ensure(1);
}

enum EngineCommand_Payload {
  createElement,
  selectElement,
  deleteElements,
  updateElementsStyle,
  moveCamera,
  zoomCamera,
  updateCreatingElement,
  addArrowPoint,
  duplicateElements,
  changeElementZIndex,
  changeElementsZIndex,
  updateGlobalElements,
  createSerialNumberTextElements,
  startTextEdit,
  updateTextEdit,
  finishTextEdit,
  startEdit,
  updateEdit,
  setDragPending,
  startBoxSelect,
  updateBoxSelect,
  notSet
}

class EngineCommand extends $pb.GeneratedMessage {
  factory EngineCommand({
    EngineCommandKind? kind,
    CreateElementCommand? createElement,
    SelectElementCommand? selectElement,
    DeleteElementsCommand? deleteElements,
    UpdateElementsStyleCommand? updateElementsStyle,
    MoveCameraCommand? moveCamera,
    ZoomCameraCommand? zoomCamera,
    UpdateCreatingElementCommand? updateCreatingElement,
    AddArrowPointCommand? addArrowPoint,
    DuplicateElementsCommand? duplicateElements,
    ChangeElementZIndexCommand? changeElementZIndex,
    ChangeElementsZIndexCommand? changeElementsZIndex,
    UpdateGlobalElementsCommand? updateGlobalElements,
    CreateSerialNumberTextElementsCommand? createSerialNumberTextElements,
    StartTextEditCommand? startTextEdit,
    UpdateTextEditCommand? updateTextEdit,
    FinishTextEditCommand? finishTextEdit,
    StartEditCommand? startEdit,
    UpdateEditCommand? updateEdit,
    SetDragPendingCommand? setDragPending,
    StartBoxSelectCommand? startBoxSelect,
    UpdateBoxSelectCommand? updateBoxSelect,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (createElement != null) result.createElement = createElement;
    if (selectElement != null) result.selectElement = selectElement;
    if (deleteElements != null) result.deleteElements = deleteElements;
    if (updateElementsStyle != null)
      result.updateElementsStyle = updateElementsStyle;
    if (moveCamera != null) result.moveCamera = moveCamera;
    if (zoomCamera != null) result.zoomCamera = zoomCamera;
    if (updateCreatingElement != null)
      result.updateCreatingElement = updateCreatingElement;
    if (addArrowPoint != null) result.addArrowPoint = addArrowPoint;
    if (duplicateElements != null) result.duplicateElements = duplicateElements;
    if (changeElementZIndex != null)
      result.changeElementZIndex = changeElementZIndex;
    if (changeElementsZIndex != null)
      result.changeElementsZIndex = changeElementsZIndex;
    if (updateGlobalElements != null)
      result.updateGlobalElements = updateGlobalElements;
    if (createSerialNumberTextElements != null)
      result.createSerialNumberTextElements = createSerialNumberTextElements;
    if (startTextEdit != null) result.startTextEdit = startTextEdit;
    if (updateTextEdit != null) result.updateTextEdit = updateTextEdit;
    if (finishTextEdit != null) result.finishTextEdit = finishTextEdit;
    if (startEdit != null) result.startEdit = startEdit;
    if (updateEdit != null) result.updateEdit = updateEdit;
    if (setDragPending != null) result.setDragPending = setDragPending;
    if (startBoxSelect != null) result.startBoxSelect = startBoxSelect;
    if (updateBoxSelect != null) result.updateBoxSelect = updateBoxSelect;
    return result;
  }

  EngineCommand._();

  factory EngineCommand.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EngineCommand.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, EngineCommand_Payload>
      _EngineCommand_PayloadByTag = {
    10: EngineCommand_Payload.createElement,
    11: EngineCommand_Payload.selectElement,
    12: EngineCommand_Payload.deleteElements,
    13: EngineCommand_Payload.updateElementsStyle,
    14: EngineCommand_Payload.moveCamera,
    15: EngineCommand_Payload.zoomCamera,
    16: EngineCommand_Payload.updateCreatingElement,
    17: EngineCommand_Payload.addArrowPoint,
    18: EngineCommand_Payload.duplicateElements,
    19: EngineCommand_Payload.changeElementZIndex,
    20: EngineCommand_Payload.changeElementsZIndex,
    21: EngineCommand_Payload.updateGlobalElements,
    22: EngineCommand_Payload.createSerialNumberTextElements,
    23: EngineCommand_Payload.startTextEdit,
    24: EngineCommand_Payload.updateTextEdit,
    25: EngineCommand_Payload.finishTextEdit,
    26: EngineCommand_Payload.startEdit,
    27: EngineCommand_Payload.updateEdit,
    28: EngineCommand_Payload.setDragPending,
    29: EngineCommand_Payload.startBoxSelect,
    30: EngineCommand_Payload.updateBoxSelect,
    0: EngineCommand_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EngineCommand',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..oo(0, [
      10,
      11,
      12,
      13,
      14,
      15,
      16,
      17,
      18,
      19,
      20,
      21,
      22,
      23,
      24,
      25,
      26,
      27,
      28,
      29,
      30
    ])
    ..aE<EngineCommandKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: EngineCommandKind.values)
    ..aOM<CreateElementCommand>(10, _omitFieldNames ? '' : 'createElement',
        subBuilder: CreateElementCommand.create)
    ..aOM<SelectElementCommand>(11, _omitFieldNames ? '' : 'selectElement',
        subBuilder: SelectElementCommand.create)
    ..aOM<DeleteElementsCommand>(12, _omitFieldNames ? '' : 'deleteElements',
        subBuilder: DeleteElementsCommand.create)
    ..aOM<UpdateElementsStyleCommand>(
        13, _omitFieldNames ? '' : 'updateElementsStyle',
        subBuilder: UpdateElementsStyleCommand.create)
    ..aOM<MoveCameraCommand>(14, _omitFieldNames ? '' : 'moveCamera',
        subBuilder: MoveCameraCommand.create)
    ..aOM<ZoomCameraCommand>(15, _omitFieldNames ? '' : 'zoomCamera',
        subBuilder: ZoomCameraCommand.create)
    ..aOM<UpdateCreatingElementCommand>(
        16, _omitFieldNames ? '' : 'updateCreatingElement',
        subBuilder: UpdateCreatingElementCommand.create)
    ..aOM<AddArrowPointCommand>(17, _omitFieldNames ? '' : 'addArrowPoint',
        subBuilder: AddArrowPointCommand.create)
    ..aOM<DuplicateElementsCommand>(
        18, _omitFieldNames ? '' : 'duplicateElements',
        subBuilder: DuplicateElementsCommand.create)
    ..aOM<ChangeElementZIndexCommand>(
        19, _omitFieldNames ? '' : 'changeElementZIndex',
        subBuilder: ChangeElementZIndexCommand.create)
    ..aOM<ChangeElementsZIndexCommand>(
        20, _omitFieldNames ? '' : 'changeElementsZIndex',
        subBuilder: ChangeElementsZIndexCommand.create)
    ..aOM<UpdateGlobalElementsCommand>(
        21, _omitFieldNames ? '' : 'updateGlobalElements',
        subBuilder: UpdateGlobalElementsCommand.create)
    ..aOM<CreateSerialNumberTextElementsCommand>(
        22, _omitFieldNames ? '' : 'createSerialNumberTextElements',
        subBuilder: CreateSerialNumberTextElementsCommand.create)
    ..aOM<StartTextEditCommand>(23, _omitFieldNames ? '' : 'startTextEdit',
        subBuilder: StartTextEditCommand.create)
    ..aOM<UpdateTextEditCommand>(24, _omitFieldNames ? '' : 'updateTextEdit',
        subBuilder: UpdateTextEditCommand.create)
    ..aOM<FinishTextEditCommand>(25, _omitFieldNames ? '' : 'finishTextEdit',
        subBuilder: FinishTextEditCommand.create)
    ..aOM<StartEditCommand>(26, _omitFieldNames ? '' : 'startEdit',
        subBuilder: StartEditCommand.create)
    ..aOM<UpdateEditCommand>(27, _omitFieldNames ? '' : 'updateEdit',
        subBuilder: UpdateEditCommand.create)
    ..aOM<SetDragPendingCommand>(28, _omitFieldNames ? '' : 'setDragPending',
        subBuilder: SetDragPendingCommand.create)
    ..aOM<StartBoxSelectCommand>(29, _omitFieldNames ? '' : 'startBoxSelect',
        subBuilder: StartBoxSelectCommand.create)
    ..aOM<UpdateBoxSelectCommand>(30, _omitFieldNames ? '' : 'updateBoxSelect',
        subBuilder: UpdateBoxSelectCommand.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineCommand clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineCommand copyWith(void Function(EngineCommand) updates) =>
      super.copyWith((message) => updates(message as EngineCommand))
          as EngineCommand;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineCommand create() => EngineCommand._();
  @$core.override
  EngineCommand createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EngineCommand getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EngineCommand>(create);
  static EngineCommand? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  @$pb.TagNumber(26)
  @$pb.TagNumber(27)
  @$pb.TagNumber(28)
  @$pb.TagNumber(29)
  @$pb.TagNumber(30)
  EngineCommand_Payload whichPayload() =>
      _EngineCommand_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  @$pb.TagNumber(26)
  @$pb.TagNumber(27)
  @$pb.TagNumber(28)
  @$pb.TagNumber(29)
  @$pb.TagNumber(30)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  EngineCommandKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(EngineCommandKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(10)
  CreateElementCommand get createElement => $_getN(1);
  @$pb.TagNumber(10)
  set createElement(CreateElementCommand value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasCreateElement() => $_has(1);
  @$pb.TagNumber(10)
  void clearCreateElement() => $_clearField(10);
  @$pb.TagNumber(10)
  CreateElementCommand ensureCreateElement() => $_ensure(1);

  @$pb.TagNumber(11)
  SelectElementCommand get selectElement => $_getN(2);
  @$pb.TagNumber(11)
  set selectElement(SelectElementCommand value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasSelectElement() => $_has(2);
  @$pb.TagNumber(11)
  void clearSelectElement() => $_clearField(11);
  @$pb.TagNumber(11)
  SelectElementCommand ensureSelectElement() => $_ensure(2);

  @$pb.TagNumber(12)
  DeleteElementsCommand get deleteElements => $_getN(3);
  @$pb.TagNumber(12)
  set deleteElements(DeleteElementsCommand value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasDeleteElements() => $_has(3);
  @$pb.TagNumber(12)
  void clearDeleteElements() => $_clearField(12);
  @$pb.TagNumber(12)
  DeleteElementsCommand ensureDeleteElements() => $_ensure(3);

  @$pb.TagNumber(13)
  UpdateElementsStyleCommand get updateElementsStyle => $_getN(4);
  @$pb.TagNumber(13)
  set updateElementsStyle(UpdateElementsStyleCommand value) =>
      $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasUpdateElementsStyle() => $_has(4);
  @$pb.TagNumber(13)
  void clearUpdateElementsStyle() => $_clearField(13);
  @$pb.TagNumber(13)
  UpdateElementsStyleCommand ensureUpdateElementsStyle() => $_ensure(4);

  @$pb.TagNumber(14)
  MoveCameraCommand get moveCamera => $_getN(5);
  @$pb.TagNumber(14)
  set moveCamera(MoveCameraCommand value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasMoveCamera() => $_has(5);
  @$pb.TagNumber(14)
  void clearMoveCamera() => $_clearField(14);
  @$pb.TagNumber(14)
  MoveCameraCommand ensureMoveCamera() => $_ensure(5);

  @$pb.TagNumber(15)
  ZoomCameraCommand get zoomCamera => $_getN(6);
  @$pb.TagNumber(15)
  set zoomCamera(ZoomCameraCommand value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasZoomCamera() => $_has(6);
  @$pb.TagNumber(15)
  void clearZoomCamera() => $_clearField(15);
  @$pb.TagNumber(15)
  ZoomCameraCommand ensureZoomCamera() => $_ensure(6);

  @$pb.TagNumber(16)
  UpdateCreatingElementCommand get updateCreatingElement => $_getN(7);
  @$pb.TagNumber(16)
  set updateCreatingElement(UpdateCreatingElementCommand value) =>
      $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasUpdateCreatingElement() => $_has(7);
  @$pb.TagNumber(16)
  void clearUpdateCreatingElement() => $_clearField(16);
  @$pb.TagNumber(16)
  UpdateCreatingElementCommand ensureUpdateCreatingElement() => $_ensure(7);

  @$pb.TagNumber(17)
  AddArrowPointCommand get addArrowPoint => $_getN(8);
  @$pb.TagNumber(17)
  set addArrowPoint(AddArrowPointCommand value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasAddArrowPoint() => $_has(8);
  @$pb.TagNumber(17)
  void clearAddArrowPoint() => $_clearField(17);
  @$pb.TagNumber(17)
  AddArrowPointCommand ensureAddArrowPoint() => $_ensure(8);

  @$pb.TagNumber(18)
  DuplicateElementsCommand get duplicateElements => $_getN(9);
  @$pb.TagNumber(18)
  set duplicateElements(DuplicateElementsCommand value) =>
      $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasDuplicateElements() => $_has(9);
  @$pb.TagNumber(18)
  void clearDuplicateElements() => $_clearField(18);
  @$pb.TagNumber(18)
  DuplicateElementsCommand ensureDuplicateElements() => $_ensure(9);

  @$pb.TagNumber(19)
  ChangeElementZIndexCommand get changeElementZIndex => $_getN(10);
  @$pb.TagNumber(19)
  set changeElementZIndex(ChangeElementZIndexCommand value) =>
      $_setField(19, value);
  @$pb.TagNumber(19)
  $core.bool hasChangeElementZIndex() => $_has(10);
  @$pb.TagNumber(19)
  void clearChangeElementZIndex() => $_clearField(19);
  @$pb.TagNumber(19)
  ChangeElementZIndexCommand ensureChangeElementZIndex() => $_ensure(10);

  @$pb.TagNumber(20)
  ChangeElementsZIndexCommand get changeElementsZIndex => $_getN(11);
  @$pb.TagNumber(20)
  set changeElementsZIndex(ChangeElementsZIndexCommand value) =>
      $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasChangeElementsZIndex() => $_has(11);
  @$pb.TagNumber(20)
  void clearChangeElementsZIndex() => $_clearField(20);
  @$pb.TagNumber(20)
  ChangeElementsZIndexCommand ensureChangeElementsZIndex() => $_ensure(11);

  @$pb.TagNumber(21)
  UpdateGlobalElementsCommand get updateGlobalElements => $_getN(12);
  @$pb.TagNumber(21)
  set updateGlobalElements(UpdateGlobalElementsCommand value) =>
      $_setField(21, value);
  @$pb.TagNumber(21)
  $core.bool hasUpdateGlobalElements() => $_has(12);
  @$pb.TagNumber(21)
  void clearUpdateGlobalElements() => $_clearField(21);
  @$pb.TagNumber(21)
  UpdateGlobalElementsCommand ensureUpdateGlobalElements() => $_ensure(12);

  @$pb.TagNumber(22)
  CreateSerialNumberTextElementsCommand get createSerialNumberTextElements =>
      $_getN(13);
  @$pb.TagNumber(22)
  set createSerialNumberTextElements(
          CreateSerialNumberTextElementsCommand value) =>
      $_setField(22, value);
  @$pb.TagNumber(22)
  $core.bool hasCreateSerialNumberTextElements() => $_has(13);
  @$pb.TagNumber(22)
  void clearCreateSerialNumberTextElements() => $_clearField(22);
  @$pb.TagNumber(22)
  CreateSerialNumberTextElementsCommand
      ensureCreateSerialNumberTextElements() => $_ensure(13);

  @$pb.TagNumber(23)
  StartTextEditCommand get startTextEdit => $_getN(14);
  @$pb.TagNumber(23)
  set startTextEdit(StartTextEditCommand value) => $_setField(23, value);
  @$pb.TagNumber(23)
  $core.bool hasStartTextEdit() => $_has(14);
  @$pb.TagNumber(23)
  void clearStartTextEdit() => $_clearField(23);
  @$pb.TagNumber(23)
  StartTextEditCommand ensureStartTextEdit() => $_ensure(14);

  @$pb.TagNumber(24)
  UpdateTextEditCommand get updateTextEdit => $_getN(15);
  @$pb.TagNumber(24)
  set updateTextEdit(UpdateTextEditCommand value) => $_setField(24, value);
  @$pb.TagNumber(24)
  $core.bool hasUpdateTextEdit() => $_has(15);
  @$pb.TagNumber(24)
  void clearUpdateTextEdit() => $_clearField(24);
  @$pb.TagNumber(24)
  UpdateTextEditCommand ensureUpdateTextEdit() => $_ensure(15);

  @$pb.TagNumber(25)
  FinishTextEditCommand get finishTextEdit => $_getN(16);
  @$pb.TagNumber(25)
  set finishTextEdit(FinishTextEditCommand value) => $_setField(25, value);
  @$pb.TagNumber(25)
  $core.bool hasFinishTextEdit() => $_has(16);
  @$pb.TagNumber(25)
  void clearFinishTextEdit() => $_clearField(25);
  @$pb.TagNumber(25)
  FinishTextEditCommand ensureFinishTextEdit() => $_ensure(16);

  @$pb.TagNumber(26)
  StartEditCommand get startEdit => $_getN(17);
  @$pb.TagNumber(26)
  set startEdit(StartEditCommand value) => $_setField(26, value);
  @$pb.TagNumber(26)
  $core.bool hasStartEdit() => $_has(17);
  @$pb.TagNumber(26)
  void clearStartEdit() => $_clearField(26);
  @$pb.TagNumber(26)
  StartEditCommand ensureStartEdit() => $_ensure(17);

  @$pb.TagNumber(27)
  UpdateEditCommand get updateEdit => $_getN(18);
  @$pb.TagNumber(27)
  set updateEdit(UpdateEditCommand value) => $_setField(27, value);
  @$pb.TagNumber(27)
  $core.bool hasUpdateEdit() => $_has(18);
  @$pb.TagNumber(27)
  void clearUpdateEdit() => $_clearField(27);
  @$pb.TagNumber(27)
  UpdateEditCommand ensureUpdateEdit() => $_ensure(18);

  @$pb.TagNumber(28)
  SetDragPendingCommand get setDragPending => $_getN(19);
  @$pb.TagNumber(28)
  set setDragPending(SetDragPendingCommand value) => $_setField(28, value);
  @$pb.TagNumber(28)
  $core.bool hasSetDragPending() => $_has(19);
  @$pb.TagNumber(28)
  void clearSetDragPending() => $_clearField(28);
  @$pb.TagNumber(28)
  SetDragPendingCommand ensureSetDragPending() => $_ensure(19);

  @$pb.TagNumber(29)
  StartBoxSelectCommand get startBoxSelect => $_getN(20);
  @$pb.TagNumber(29)
  set startBoxSelect(StartBoxSelectCommand value) => $_setField(29, value);
  @$pb.TagNumber(29)
  $core.bool hasStartBoxSelect() => $_has(20);
  @$pb.TagNumber(29)
  void clearStartBoxSelect() => $_clearField(29);
  @$pb.TagNumber(29)
  StartBoxSelectCommand ensureStartBoxSelect() => $_ensure(20);

  @$pb.TagNumber(30)
  UpdateBoxSelectCommand get updateBoxSelect => $_getN(21);
  @$pb.TagNumber(30)
  set updateBoxSelect(UpdateBoxSelectCommand value) => $_setField(30, value);
  @$pb.TagNumber(30)
  $core.bool hasUpdateBoxSelect() => $_has(21);
  @$pb.TagNumber(30)
  void clearUpdateBoxSelect() => $_clearField(30);
  @$pb.TagNumber(30)
  UpdateBoxSelectCommand ensureUpdateBoxSelect() => $_ensure(21);
}

class EngineSnapshot extends $pb.GeneratedMessage {
  factory EngineSnapshot({
    $core.int? schemaVersion,
    $fixnum.Int64? documentVersion,
    $fixnum.Int64? selectionVersion,
    InteractionMode? interactionMode,
    CameraState? camera,
    $core.Iterable<Element>? elements,
    $core.Iterable<$core.String>? selectedIds,
    $fixnum.Int64? historyUndoLen,
    $fixnum.Int64? historyRedoLen,
    $core.List<$core.int>? globalElementsPayload,
  }) {
    final result = create();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (documentVersion != null) result.documentVersion = documentVersion;
    if (selectionVersion != null) result.selectionVersion = selectionVersion;
    if (interactionMode != null) result.interactionMode = interactionMode;
    if (camera != null) result.camera = camera;
    if (elements != null) result.elements.addAll(elements);
    if (selectedIds != null) result.selectedIds.addAll(selectedIds);
    if (historyUndoLen != null) result.historyUndoLen = historyUndoLen;
    if (historyRedoLen != null) result.historyRedoLen = historyRedoLen;
    if (globalElementsPayload != null)
      result.globalElementsPayload = globalElementsPayload;
    return result;
  }

  EngineSnapshot._();

  factory EngineSnapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EngineSnapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EngineSnapshot',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'documentVersion', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        3, _omitFieldNames ? '' : 'selectionVersion', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aE<InteractionMode>(4, _omitFieldNames ? '' : 'interactionMode',
        enumValues: InteractionMode.values)
    ..aOM<CameraState>(5, _omitFieldNames ? '' : 'camera',
        subBuilder: CameraState.create)
    ..pPM<Element>(6, _omitFieldNames ? '' : 'elements',
        subBuilder: Element.create)
    ..pPS(7, _omitFieldNames ? '' : 'selectedIds')
    ..a<$fixnum.Int64>(
        8, _omitFieldNames ? '' : 'historyUndoLen', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        9, _omitFieldNames ? '' : 'historyRedoLen', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$core.List<$core.int>>(
        10, _omitFieldNames ? '' : 'globalElementsPayload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineSnapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineSnapshot copyWith(void Function(EngineSnapshot) updates) =>
      super.copyWith((message) => updates(message as EngineSnapshot))
          as EngineSnapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineSnapshot create() => EngineSnapshot._();
  @$core.override
  EngineSnapshot createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EngineSnapshot getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EngineSnapshot>(create);
  static EngineSnapshot? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get documentVersion => $_getI64(1);
  @$pb.TagNumber(2)
  set documentVersion($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDocumentVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearDocumentVersion() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get selectionVersion => $_getI64(2);
  @$pb.TagNumber(3)
  set selectionVersion($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSelectionVersion() => $_has(2);
  @$pb.TagNumber(3)
  void clearSelectionVersion() => $_clearField(3);

  @$pb.TagNumber(4)
  InteractionMode get interactionMode => $_getN(3);
  @$pb.TagNumber(4)
  set interactionMode(InteractionMode value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasInteractionMode() => $_has(3);
  @$pb.TagNumber(4)
  void clearInteractionMode() => $_clearField(4);

  @$pb.TagNumber(5)
  CameraState get camera => $_getN(4);
  @$pb.TagNumber(5)
  set camera(CameraState value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasCamera() => $_has(4);
  @$pb.TagNumber(5)
  void clearCamera() => $_clearField(5);
  @$pb.TagNumber(5)
  CameraState ensureCamera() => $_ensure(4);

  @$pb.TagNumber(6)
  $pb.PbList<Element> get elements => $_getList(5);

  @$pb.TagNumber(7)
  $pb.PbList<$core.String> get selectedIds => $_getList(6);

  @$pb.TagNumber(8)
  $fixnum.Int64 get historyUndoLen => $_getI64(7);
  @$pb.TagNumber(8)
  set historyUndoLen($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasHistoryUndoLen() => $_has(7);
  @$pb.TagNumber(8)
  void clearHistoryUndoLen() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get historyRedoLen => $_getI64(8);
  @$pb.TagNumber(9)
  set historyRedoLen($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasHistoryRedoLen() => $_has(8);
  @$pb.TagNumber(9)
  void clearHistoryRedoLen() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.List<$core.int> get globalElementsPayload => $_getN(9);
  @$pb.TagNumber(10)
  set globalElementsPayload($core.List<$core.int> value) =>
      $_setBytes(9, value);
  @$pb.TagNumber(10)
  $core.bool hasGlobalElementsPayload() => $_has(9);
  @$pb.TagNumber(10)
  void clearGlobalElementsPayload() => $_clearField(10);
}

class FramePlanRequest extends $pb.GeneratedMessage {
  factory FramePlanRequest({
    DrawRect? viewport,
    $core.String? localeTag,
    $core.double? scaleFactor,
  }) {
    final result = create();
    if (viewport != null) result.viewport = viewport;
    if (localeTag != null) result.localeTag = localeTag;
    if (scaleFactor != null) result.scaleFactor = scaleFactor;
    return result;
  }

  FramePlanRequest._();

  factory FramePlanRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FramePlanRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FramePlanRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aOM<DrawRect>(1, _omitFieldNames ? '' : 'viewport',
        subBuilder: DrawRect.create)
    ..aOS(2, _omitFieldNames ? '' : 'localeTag')
    ..aD(3, _omitFieldNames ? '' : 'scaleFactor')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FramePlanRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FramePlanRequest copyWith(void Function(FramePlanRequest) updates) =>
      super.copyWith((message) => updates(message as FramePlanRequest))
          as FramePlanRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FramePlanRequest create() => FramePlanRequest._();
  @$core.override
  FramePlanRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FramePlanRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FramePlanRequest>(create);
  static FramePlanRequest? _defaultInstance;

  @$pb.TagNumber(1)
  DrawRect get viewport => $_getN(0);
  @$pb.TagNumber(1)
  set viewport(DrawRect value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasViewport() => $_has(0);
  @$pb.TagNumber(1)
  void clearViewport() => $_clearField(1);
  @$pb.TagNumber(1)
  DrawRect ensureViewport() => $_ensure(0);

  @$pb.TagNumber(2)
  $core.String get localeTag => $_getSZ(1);
  @$pb.TagNumber(2)
  set localeTag($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLocaleTag() => $_has(1);
  @$pb.TagNumber(2)
  void clearLocaleTag() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get scaleFactor => $_getN(2);
  @$pb.TagNumber(3)
  set scaleFactor($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasScaleFactor() => $_has(2);
  @$pb.TagNumber(3)
  void clearScaleFactor() => $_clearField(3);
}

class FrameTask extends $pb.GeneratedMessage {
  factory FrameTask({
    FrameTaskKind? kind,
    $core.String? elementId,
    ElementType? elementType,
    $core.List<$core.int>? payload,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (elementId != null) result.elementId = elementId;
    if (elementType != null) result.elementType = elementType;
    if (payload != null) result.payload = payload;
    return result;
  }

  FrameTask._();

  factory FrameTask.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FrameTask.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FrameTask',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aE<FrameTaskKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: FrameTaskKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'elementId')
    ..aE<ElementType>(3, _omitFieldNames ? '' : 'elementType',
        enumValues: ElementType.values)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FrameTask clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FrameTask copyWith(void Function(FrameTask) updates) =>
      super.copyWith((message) => updates(message as FrameTask)) as FrameTask;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FrameTask create() => FrameTask._();
  @$core.override
  FrameTask createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FrameTask getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<FrameTask>(create);
  static FrameTask? _defaultInstance;

  @$pb.TagNumber(1)
  FrameTaskKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(FrameTaskKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get elementId => $_getSZ(1);
  @$pb.TagNumber(2)
  set elementId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasElementId() => $_has(1);
  @$pb.TagNumber(2)
  void clearElementId() => $_clearField(2);

  @$pb.TagNumber(3)
  ElementType get elementType => $_getN(2);
  @$pb.TagNumber(3)
  set elementType(ElementType value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasElementType() => $_has(2);
  @$pb.TagNumber(3)
  void clearElementType() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get payload => $_getN(3);
  @$pb.TagNumber(4)
  set payload($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPayload() => $_has(3);
  @$pb.TagNumber(4)
  void clearPayload() => $_clearField(4);
}

class FrameRenderPlan extends $pb.GeneratedMessage {
  factory FrameRenderPlan({
    $core.int? schemaVersion,
    CameraState? camera,
    $core.double? scaleFactor,
    $core.String? localeTag,
    $core.Iterable<FrameTask>? tasks,
  }) {
    final result = create();
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (camera != null) result.camera = camera;
    if (scaleFactor != null) result.scaleFactor = scaleFactor;
    if (localeTag != null) result.localeTag = localeTag;
    if (tasks != null) result.tasks.addAll(tasks);
    return result;
  }

  FrameRenderPlan._();

  factory FrameRenderPlan.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FrameRenderPlan.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FrameRenderPlan',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOM<CameraState>(2, _omitFieldNames ? '' : 'camera',
        subBuilder: CameraState.create)
    ..aD(3, _omitFieldNames ? '' : 'scaleFactor')
    ..aOS(4, _omitFieldNames ? '' : 'localeTag')
    ..pPM<FrameTask>(5, _omitFieldNames ? '' : 'tasks',
        subBuilder: FrameTask.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FrameRenderPlan clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FrameRenderPlan copyWith(void Function(FrameRenderPlan) updates) =>
      super.copyWith((message) => updates(message as FrameRenderPlan))
          as FrameRenderPlan;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FrameRenderPlan create() => FrameRenderPlan._();
  @$core.override
  FrameRenderPlan createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FrameRenderPlan getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FrameRenderPlan>(create);
  static FrameRenderPlan? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get schemaVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set schemaVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSchemaVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearSchemaVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  CameraState get camera => $_getN(1);
  @$pb.TagNumber(2)
  set camera(CameraState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasCamera() => $_has(1);
  @$pb.TagNumber(2)
  void clearCamera() => $_clearField(2);
  @$pb.TagNumber(2)
  CameraState ensureCamera() => $_ensure(1);

  @$pb.TagNumber(3)
  $core.double get scaleFactor => $_getN(2);
  @$pb.TagNumber(3)
  set scaleFactor($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasScaleFactor() => $_has(2);
  @$pb.TagNumber(3)
  void clearScaleFactor() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get localeTag => $_getSZ(3);
  @$pb.TagNumber(4)
  set localeTag($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLocaleTag() => $_has(3);
  @$pb.TagNumber(4)
  void clearLocaleTag() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<FrameTask> get tasks => $_getList(4);
}

class EngineError extends $pb.GeneratedMessage {
  factory EngineError({
    $core.int? code,
    $core.String? message,
    $core.String? details,
  }) {
    final result = create();
    if (code != null) result.code = code;
    if (message != null) result.message = message;
    if (details != null) result.details = details;
    return result;
  }

  EngineError._();

  factory EngineError.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EngineError.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EngineError',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'code', fieldType: $pb.PbFieldType.OU3)
    ..aOS(2, _omitFieldNames ? '' : 'message')
    ..aOS(3, _omitFieldNames ? '' : 'details')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineError clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineError copyWith(void Function(EngineError) updates) =>
      super.copyWith((message) => updates(message as EngineError))
          as EngineError;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineError create() => EngineError._();
  @$core.override
  EngineError createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EngineError getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EngineError>(create);
  static EngineError? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get code => $_getIZ(0);
  @$pb.TagNumber(1)
  set code($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get message => $_getSZ(1);
  @$pb.TagNumber(2)
  set message($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMessage() => $_has(1);
  @$pb.TagNumber(2)
  void clearMessage() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get details => $_getSZ(2);
  @$pb.TagNumber(3)
  set details($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasDetails() => $_has(2);
  @$pb.TagNumber(3)
  void clearDetails() => $_clearField(3);
}

enum EngineEvent_Payload { error, blob, message, notSet }

class EngineEvent extends $pb.GeneratedMessage {
  factory EngineEvent({
    EngineEventKind? kind,
    $fixnum.Int64? sequence,
    EngineError? error,
    $core.List<$core.int>? blob,
    $core.String? message,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (sequence != null) result.sequence = sequence;
    if (error != null) result.error = error;
    if (blob != null) result.blob = blob;
    if (message != null) result.message = message;
    return result;
  }

  EngineEvent._();

  factory EngineEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EngineEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, EngineEvent_Payload>
      _EngineEvent_PayloadByTag = {
    10: EngineEvent_Payload.error,
    11: EngineEvent_Payload.blob,
    12: EngineEvent_Payload.message,
    0: EngineEvent_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EngineEvent',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v1'),
      createEmptyInstance: create)
    ..oo(0, [10, 11, 12])
    ..aE<EngineEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: EngineEventKind.values)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<EngineError>(10, _omitFieldNames ? '' : 'error',
        subBuilder: EngineError.create)
    ..a<$core.List<$core.int>>(
        11, _omitFieldNames ? '' : 'blob', $pb.PbFieldType.OY)
    ..aOS(12, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineEvent copyWith(void Function(EngineEvent) updates) =>
      super.copyWith((message) => updates(message as EngineEvent))
          as EngineEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineEvent create() => EngineEvent._();
  @$core.override
  EngineEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EngineEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EngineEvent>(create);
  static EngineEvent? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  EngineEvent_Payload whichPayload() =>
      _EngineEvent_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  EngineEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(EngineEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get sequence => $_getI64(1);
  @$pb.TagNumber(2)
  set sequence($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSequence() => $_has(1);
  @$pb.TagNumber(2)
  void clearSequence() => $_clearField(2);

  @$pb.TagNumber(10)
  EngineError get error => $_getN(2);
  @$pb.TagNumber(10)
  set error(EngineError value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(10)
  void clearError() => $_clearField(10);
  @$pb.TagNumber(10)
  EngineError ensureError() => $_ensure(2);

  @$pb.TagNumber(11)
  $core.List<$core.int> get blob => $_getN(3);
  @$pb.TagNumber(11)
  set blob($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(11)
  $core.bool hasBlob() => $_has(3);
  @$pb.TagNumber(11)
  void clearBlob() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get message => $_getSZ(4);
  @$pb.TagNumber(12)
  set message($core.String value) => $_setString(4, value);
  @$pb.TagNumber(12)
  $core.bool hasMessage() => $_has(4);
  @$pb.TagNumber(12)
  void clearMessage() => $_clearField(12);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
