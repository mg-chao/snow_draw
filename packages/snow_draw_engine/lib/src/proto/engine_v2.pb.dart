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

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'engine_v2.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'engine_v2.pbenum.dart';

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
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
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
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
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
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
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

class RectanglePayload extends $pb.GeneratedMessage {
  factory RectanglePayload({
    $fixnum.Int64? colorArgb32,
    $fixnum.Int64? fillColorArgb32,
    $core.double? strokeWidth,
  }) {
    final result = create();
    if (colorArgb32 != null) result.colorArgb32 = colorArgb32;
    if (fillColorArgb32 != null) result.fillColorArgb32 = fillColorArgb32;
    if (strokeWidth != null) result.strokeWidth = strokeWidth;
    return result;
  }

  RectanglePayload._();

  factory RectanglePayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RectanglePayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RectanglePayload',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'colorArgb32', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'fillColorArgb32', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aD(3, _omitFieldNames ? '' : 'strokeWidth')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RectanglePayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RectanglePayload copyWith(void Function(RectanglePayload) updates) =>
      super.copyWith((message) => updates(message as RectanglePayload))
          as RectanglePayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RectanglePayload create() => RectanglePayload._();
  @$core.override
  RectanglePayload createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RectanglePayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<RectanglePayload>(create);
  static RectanglePayload? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get colorArgb32 => $_getI64(0);
  @$pb.TagNumber(1)
  set colorArgb32($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasColorArgb32() => $_has(0);
  @$pb.TagNumber(1)
  void clearColorArgb32() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get fillColorArgb32 => $_getI64(1);
  @$pb.TagNumber(2)
  set fillColorArgb32($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFillColorArgb32() => $_has(1);
  @$pb.TagNumber(2)
  void clearFillColorArgb32() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get strokeWidth => $_getN(2);
  @$pb.TagNumber(3)
  set strokeWidth($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStrokeWidth() => $_has(2);
  @$pb.TagNumber(3)
  void clearStrokeWidth() => $_clearField(3);
}

class ArrowPayload extends $pb.GeneratedMessage {
  factory ArrowPayload({
    $core.Iterable<DrawPoint>? points,
    $core.String? arrowType,
  }) {
    final result = create();
    if (points != null) result.points.addAll(points);
    if (arrowType != null) result.arrowType = arrowType;
    return result;
  }

  ArrowPayload._();

  factory ArrowPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ArrowPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ArrowPayload',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..pPM<DrawPoint>(1, _omitFieldNames ? '' : 'points',
        subBuilder: DrawPoint.create)
    ..aOS(2, _omitFieldNames ? '' : 'arrowType')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ArrowPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ArrowPayload copyWith(void Function(ArrowPayload) updates) =>
      super.copyWith((message) => updates(message as ArrowPayload))
          as ArrowPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ArrowPayload create() => ArrowPayload._();
  @$core.override
  ArrowPayload createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ArrowPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ArrowPayload>(create);
  static ArrowPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<DrawPoint> get points => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get arrowType => $_getSZ(1);
  @$pb.TagNumber(2)
  set arrowType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasArrowType() => $_has(1);
  @$pb.TagNumber(2)
  void clearArrowType() => $_clearField(2);
}

class LinePayload extends $pb.GeneratedMessage {
  factory LinePayload({
    $core.Iterable<DrawPoint>? points,
    $core.String? lineType,
  }) {
    final result = create();
    if (points != null) result.points.addAll(points);
    if (lineType != null) result.lineType = lineType;
    return result;
  }

  LinePayload._();

  factory LinePayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LinePayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LinePayload',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..pPM<DrawPoint>(1, _omitFieldNames ? '' : 'points',
        subBuilder: DrawPoint.create)
    ..aOS(2, _omitFieldNames ? '' : 'lineType')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LinePayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LinePayload copyWith(void Function(LinePayload) updates) =>
      super.copyWith((message) => updates(message as LinePayload))
          as LinePayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LinePayload create() => LinePayload._();
  @$core.override
  LinePayload createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LinePayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LinePayload>(create);
  static LinePayload? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<DrawPoint> get points => $_getList(0);

  @$pb.TagNumber(2)
  $core.String get lineType => $_getSZ(1);
  @$pb.TagNumber(2)
  set lineType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLineType() => $_has(1);
  @$pb.TagNumber(2)
  void clearLineType() => $_clearField(2);
}

class FreeDrawPayload extends $pb.GeneratedMessage {
  factory FreeDrawPayload({
    $core.Iterable<DrawPoint>? points,
  }) {
    final result = create();
    if (points != null) result.points.addAll(points);
    return result;
  }

  FreeDrawPayload._();

  factory FreeDrawPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FreeDrawPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FreeDrawPayload',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..pPM<DrawPoint>(1, _omitFieldNames ? '' : 'points',
        subBuilder: DrawPoint.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FreeDrawPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FreeDrawPayload copyWith(void Function(FreeDrawPayload) updates) =>
      super.copyWith((message) => updates(message as FreeDrawPayload))
          as FreeDrawPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FreeDrawPayload create() => FreeDrawPayload._();
  @$core.override
  FreeDrawPayload createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FreeDrawPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FreeDrawPayload>(create);
  static FreeDrawPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<DrawPoint> get points => $_getList(0);
}

class FilterPayload extends $pb.GeneratedMessage {
  factory FilterPayload({
    $core.String? filterType,
    $core.double? strength,
  }) {
    final result = create();
    if (filterType != null) result.filterType = filterType;
    if (strength != null) result.strength = strength;
    return result;
  }

  FilterPayload._();

  factory FilterPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FilterPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FilterPayload',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'filterType')
    ..aD(2, _omitFieldNames ? '' : 'strength')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FilterPayload copyWith(void Function(FilterPayload) updates) =>
      super.copyWith((message) => updates(message as FilterPayload))
          as FilterPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FilterPayload create() => FilterPayload._();
  @$core.override
  FilterPayload createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FilterPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FilterPayload>(create);
  static FilterPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get filterType => $_getSZ(0);
  @$pb.TagNumber(1)
  set filterType($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFilterType() => $_has(0);
  @$pb.TagNumber(1)
  void clearFilterType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get strength => $_getN(1);
  @$pb.TagNumber(2)
  set strength($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasStrength() => $_has(1);
  @$pb.TagNumber(2)
  void clearStrength() => $_clearField(2);
}

class HighlightPayload extends $pb.GeneratedMessage {
  factory HighlightPayload({
    $core.String? shape,
    $fixnum.Int64? colorArgb32,
  }) {
    final result = create();
    if (shape != null) result.shape = shape;
    if (colorArgb32 != null) result.colorArgb32 = colorArgb32;
    return result;
  }

  HighlightPayload._();

  factory HighlightPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HighlightPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HighlightPayload',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'shape')
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'colorArgb32', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HighlightPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HighlightPayload copyWith(void Function(HighlightPayload) updates) =>
      super.copyWith((message) => updates(message as HighlightPayload))
          as HighlightPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HighlightPayload create() => HighlightPayload._();
  @$core.override
  HighlightPayload createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HighlightPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HighlightPayload>(create);
  static HighlightPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get shape => $_getSZ(0);
  @$pb.TagNumber(1)
  set shape($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasShape() => $_has(0);
  @$pb.TagNumber(1)
  void clearShape() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get colorArgb32 => $_getI64(1);
  @$pb.TagNumber(2)
  set colorArgb32($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasColorArgb32() => $_has(1);
  @$pb.TagNumber(2)
  void clearColorArgb32() => $_clearField(2);
}

class TextPayload extends $pb.GeneratedMessage {
  factory TextPayload({
    $core.String? text,
    $core.double? fontSize,
    $core.String? fontFamily,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (fontSize != null) result.fontSize = fontSize;
    if (fontFamily != null) result.fontFamily = fontFamily;
    return result;
  }

  TextPayload._();

  factory TextPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TextPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TextPayload',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aD(2, _omitFieldNames ? '' : 'fontSize')
    ..aOS(3, _omitFieldNames ? '' : 'fontFamily')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TextPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TextPayload copyWith(void Function(TextPayload) updates) =>
      super.copyWith((message) => updates(message as TextPayload))
          as TextPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TextPayload create() => TextPayload._();
  @$core.override
  TextPayload createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TextPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TextPayload>(create);
  static TextPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get fontSize => $_getN(1);
  @$pb.TagNumber(2)
  set fontSize($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFontSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearFontSize() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get fontFamily => $_getSZ(2);
  @$pb.TagNumber(3)
  set fontFamily($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFontFamily() => $_has(2);
  @$pb.TagNumber(3)
  void clearFontFamily() => $_clearField(3);
}

class SerialNumberPayload extends $pb.GeneratedMessage {
  factory SerialNumberPayload({
    $core.int? number,
    $core.String? textElementId,
  }) {
    final result = create();
    if (number != null) result.number = number;
    if (textElementId != null) result.textElementId = textElementId;
    return result;
  }

  SerialNumberPayload._();

  factory SerialNumberPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SerialNumberPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SerialNumberPayload',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'number')
    ..aOS(2, _omitFieldNames ? '' : 'textElementId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SerialNumberPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SerialNumberPayload copyWith(void Function(SerialNumberPayload) updates) =>
      super.copyWith((message) => updates(message as SerialNumberPayload))
          as SerialNumberPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SerialNumberPayload create() => SerialNumberPayload._();
  @$core.override
  SerialNumberPayload createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SerialNumberPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SerialNumberPayload>(create);
  static SerialNumberPayload? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get number => $_getIZ(0);
  @$pb.TagNumber(1)
  set number($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasNumber() => $_has(0);
  @$pb.TagNumber(1)
  void clearNumber() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get textElementId => $_getSZ(1);
  @$pb.TagNumber(2)
  set textElementId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTextElementId() => $_has(1);
  @$pb.TagNumber(2)
  void clearTextElementId() => $_clearField(2);
}

enum ElementPayload_Payload {
  rectangle,
  arrow,
  line,
  freeDraw,
  filter,
  highlight,
  text,
  serialNumber,
  rawJsonPayload,
  rawBinaryPayload,
  notSet
}

class ElementPayload extends $pb.GeneratedMessage {
  factory ElementPayload({
    RectanglePayload? rectangle,
    ArrowPayload? arrow,
    LinePayload? line,
    FreeDrawPayload? freeDraw,
    FilterPayload? filter,
    HighlightPayload? highlight,
    TextPayload? text,
    SerialNumberPayload? serialNumber,
    $core.List<$core.int>? rawJsonPayload,
    $core.List<$core.int>? rawBinaryPayload,
  }) {
    final result = create();
    if (rectangle != null) result.rectangle = rectangle;
    if (arrow != null) result.arrow = arrow;
    if (line != null) result.line = line;
    if (freeDraw != null) result.freeDraw = freeDraw;
    if (filter != null) result.filter = filter;
    if (highlight != null) result.highlight = highlight;
    if (text != null) result.text = text;
    if (serialNumber != null) result.serialNumber = serialNumber;
    if (rawJsonPayload != null) result.rawJsonPayload = rawJsonPayload;
    if (rawBinaryPayload != null) result.rawBinaryPayload = rawBinaryPayload;
    return result;
  }

  ElementPayload._();

  factory ElementPayload.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ElementPayload.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ElementPayload_Payload>
      _ElementPayload_PayloadByTag = {
    1: ElementPayload_Payload.rectangle,
    2: ElementPayload_Payload.arrow,
    3: ElementPayload_Payload.line,
    4: ElementPayload_Payload.freeDraw,
    5: ElementPayload_Payload.filter,
    6: ElementPayload_Payload.highlight,
    7: ElementPayload_Payload.text,
    8: ElementPayload_Payload.serialNumber,
    100: ElementPayload_Payload.rawJsonPayload,
    101: ElementPayload_Payload.rawBinaryPayload,
    0: ElementPayload_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ElementPayload',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4, 5, 6, 7, 8, 100, 101])
    ..aOM<RectanglePayload>(1, _omitFieldNames ? '' : 'rectangle',
        subBuilder: RectanglePayload.create)
    ..aOM<ArrowPayload>(2, _omitFieldNames ? '' : 'arrow',
        subBuilder: ArrowPayload.create)
    ..aOM<LinePayload>(3, _omitFieldNames ? '' : 'line',
        subBuilder: LinePayload.create)
    ..aOM<FreeDrawPayload>(4, _omitFieldNames ? '' : 'freeDraw',
        subBuilder: FreeDrawPayload.create)
    ..aOM<FilterPayload>(5, _omitFieldNames ? '' : 'filter',
        subBuilder: FilterPayload.create)
    ..aOM<HighlightPayload>(6, _omitFieldNames ? '' : 'highlight',
        subBuilder: HighlightPayload.create)
    ..aOM<TextPayload>(7, _omitFieldNames ? '' : 'text',
        subBuilder: TextPayload.create)
    ..aOM<SerialNumberPayload>(8, _omitFieldNames ? '' : 'serialNumber',
        subBuilder: SerialNumberPayload.create)
    ..a<$core.List<$core.int>>(
        100, _omitFieldNames ? '' : 'rawJsonPayload', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        101, _omitFieldNames ? '' : 'rawBinaryPayload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ElementPayload clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ElementPayload copyWith(void Function(ElementPayload) updates) =>
      super.copyWith((message) => updates(message as ElementPayload))
          as ElementPayload;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ElementPayload create() => ElementPayload._();
  @$core.override
  ElementPayload createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ElementPayload getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ElementPayload>(create);
  static ElementPayload? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(100)
  @$pb.TagNumber(101)
  ElementPayload_Payload whichPayload() =>
      _ElementPayload_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(100)
  @$pb.TagNumber(101)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  RectanglePayload get rectangle => $_getN(0);
  @$pb.TagNumber(1)
  set rectangle(RectanglePayload value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasRectangle() => $_has(0);
  @$pb.TagNumber(1)
  void clearRectangle() => $_clearField(1);
  @$pb.TagNumber(1)
  RectanglePayload ensureRectangle() => $_ensure(0);

  @$pb.TagNumber(2)
  ArrowPayload get arrow => $_getN(1);
  @$pb.TagNumber(2)
  set arrow(ArrowPayload value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasArrow() => $_has(1);
  @$pb.TagNumber(2)
  void clearArrow() => $_clearField(2);
  @$pb.TagNumber(2)
  ArrowPayload ensureArrow() => $_ensure(1);

  @$pb.TagNumber(3)
  LinePayload get line => $_getN(2);
  @$pb.TagNumber(3)
  set line(LinePayload value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasLine() => $_has(2);
  @$pb.TagNumber(3)
  void clearLine() => $_clearField(3);
  @$pb.TagNumber(3)
  LinePayload ensureLine() => $_ensure(2);

  @$pb.TagNumber(4)
  FreeDrawPayload get freeDraw => $_getN(3);
  @$pb.TagNumber(4)
  set freeDraw(FreeDrawPayload value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasFreeDraw() => $_has(3);
  @$pb.TagNumber(4)
  void clearFreeDraw() => $_clearField(4);
  @$pb.TagNumber(4)
  FreeDrawPayload ensureFreeDraw() => $_ensure(3);

  @$pb.TagNumber(5)
  FilterPayload get filter => $_getN(4);
  @$pb.TagNumber(5)
  set filter(FilterPayload value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasFilter() => $_has(4);
  @$pb.TagNumber(5)
  void clearFilter() => $_clearField(5);
  @$pb.TagNumber(5)
  FilterPayload ensureFilter() => $_ensure(4);

  @$pb.TagNumber(6)
  HighlightPayload get highlight => $_getN(5);
  @$pb.TagNumber(6)
  set highlight(HighlightPayload value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasHighlight() => $_has(5);
  @$pb.TagNumber(6)
  void clearHighlight() => $_clearField(6);
  @$pb.TagNumber(6)
  HighlightPayload ensureHighlight() => $_ensure(5);

  @$pb.TagNumber(7)
  TextPayload get text => $_getN(6);
  @$pb.TagNumber(7)
  set text(TextPayload value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasText() => $_has(6);
  @$pb.TagNumber(7)
  void clearText() => $_clearField(7);
  @$pb.TagNumber(7)
  TextPayload ensureText() => $_ensure(6);

  @$pb.TagNumber(8)
  SerialNumberPayload get serialNumber => $_getN(7);
  @$pb.TagNumber(8)
  set serialNumber(SerialNumberPayload value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasSerialNumber() => $_has(7);
  @$pb.TagNumber(8)
  void clearSerialNumber() => $_clearField(8);
  @$pb.TagNumber(8)
  SerialNumberPayload ensureSerialNumber() => $_ensure(7);

  @$pb.TagNumber(100)
  $core.List<$core.int> get rawJsonPayload => $_getN(8);
  @$pb.TagNumber(100)
  set rawJsonPayload($core.List<$core.int> value) => $_setBytes(8, value);
  @$pb.TagNumber(100)
  $core.bool hasRawJsonPayload() => $_has(8);
  @$pb.TagNumber(100)
  void clearRawJsonPayload() => $_clearField(100);

  @$pb.TagNumber(101)
  $core.List<$core.int> get rawBinaryPayload => $_getN(9);
  @$pb.TagNumber(101)
  set rawBinaryPayload($core.List<$core.int> value) => $_setBytes(9, value);
  @$pb.TagNumber(101)
  $core.bool hasRawBinaryPayload() => $_has(9);
  @$pb.TagNumber(101)
  void clearRawBinaryPayload() => $_clearField(101);
}

class Element extends $pb.GeneratedMessage {
  factory Element({
    $core.String? id,
    ElementType? elementType,
    DrawRect? rect,
    $core.double? rotation,
    $core.double? opacity,
    $core.int? zIndex,
    ElementPayload? payload,
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
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'id')
    ..aE<ElementType>(2, _omitFieldNames ? '' : 'elementType',
        enumValues: ElementType.values)
    ..aOM<DrawRect>(3, _omitFieldNames ? '' : 'rect',
        subBuilder: DrawRect.create)
    ..aD(4, _omitFieldNames ? '' : 'rotation')
    ..aD(5, _omitFieldNames ? '' : 'opacity')
    ..aI(6, _omitFieldNames ? '' : 'zIndex')
    ..aOM<ElementPayload>(7, _omitFieldNames ? '' : 'payload',
        subBuilder: ElementPayload.create)
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
  ElementPayload get payload => $_getN(6);
  @$pb.TagNumber(7)
  set payload(ElementPayload value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasPayload() => $_has(6);
  @$pb.TagNumber(7)
  void clearPayload() => $_clearField(7);
  @$pb.TagNumber(7)
  ElementPayload ensurePayload() => $_ensure(6);
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
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
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

class FrameTask extends $pb.GeneratedMessage {
  factory FrameTask({
    FrameTaskKind? kind,
    $core.String? elementId,
    ElementType? elementType,
    ElementPayload? payload,
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
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aE<FrameTaskKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: FrameTaskKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'elementId')
    ..aE<ElementType>(3, _omitFieldNames ? '' : 'elementType',
        enumValues: ElementType.values)
    ..aOM<ElementPayload>(4, _omitFieldNames ? '' : 'payload',
        subBuilder: ElementPayload.create)
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
  ElementPayload get payload => $_getN(3);
  @$pb.TagNumber(4)
  set payload(ElementPayload value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasPayload() => $_has(3);
  @$pb.TagNumber(4)
  void clearPayload() => $_clearField(4);
  @$pb.TagNumber(4)
  ElementPayload ensurePayload() => $_ensure(3);
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
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
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
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
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
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
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

class EngineInitRequest extends $pb.GeneratedMessage {
  factory EngineInitRequest({
    $core.int? requestedAbiVersion,
    $core.int? schemaVersion,
    $core.String? localeTag,
    $core.double? scaleFactor,
    $fixnum.Int64? requestedCapabilitiesMask,
    $fixnum.Int64? deterministicSeed,
  }) {
    final result = create();
    if (requestedAbiVersion != null)
      result.requestedAbiVersion = requestedAbiVersion;
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (localeTag != null) result.localeTag = localeTag;
    if (scaleFactor != null) result.scaleFactor = scaleFactor;
    if (requestedCapabilitiesMask != null)
      result.requestedCapabilitiesMask = requestedCapabilitiesMask;
    if (deterministicSeed != null) result.deterministicSeed = deterministicSeed;
    return result;
  }

  EngineInitRequest._();

  factory EngineInitRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EngineInitRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EngineInitRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'requestedAbiVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..aOS(3, _omitFieldNames ? '' : 'localeTag')
    ..aD(4, _omitFieldNames ? '' : 'scaleFactor')
    ..a<$fixnum.Int64>(5, _omitFieldNames ? '' : 'requestedCapabilitiesMask',
        $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        6, _omitFieldNames ? '' : 'deterministicSeed', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineInitRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineInitRequest copyWith(void Function(EngineInitRequest) updates) =>
      super.copyWith((message) => updates(message as EngineInitRequest))
          as EngineInitRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineInitRequest create() => EngineInitRequest._();
  @$core.override
  EngineInitRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EngineInitRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EngineInitRequest>(create);
  static EngineInitRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get requestedAbiVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set requestedAbiVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestedAbiVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestedAbiVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get schemaVersion => $_getIZ(1);
  @$pb.TagNumber(2)
  set schemaVersion($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSchemaVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearSchemaVersion() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get localeTag => $_getSZ(2);
  @$pb.TagNumber(3)
  set localeTag($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLocaleTag() => $_has(2);
  @$pb.TagNumber(3)
  void clearLocaleTag() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get scaleFactor => $_getN(3);
  @$pb.TagNumber(4)
  set scaleFactor($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasScaleFactor() => $_has(3);
  @$pb.TagNumber(4)
  void clearScaleFactor() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get requestedCapabilitiesMask => $_getI64(4);
  @$pb.TagNumber(5)
  set requestedCapabilitiesMask($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRequestedCapabilitiesMask() => $_has(4);
  @$pb.TagNumber(5)
  void clearRequestedCapabilitiesMask() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get deterministicSeed => $_getI64(5);
  @$pb.TagNumber(6)
  set deterministicSeed($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasDeterministicSeed() => $_has(5);
  @$pb.TagNumber(6)
  void clearDeterministicSeed() => $_clearField(6);
}

class EngineInitAck extends $pb.GeneratedMessage {
  factory EngineInitAck({
    $core.int? abiVersion,
    $core.int? schemaVersion,
    $fixnum.Int64? grantedCapabilitiesMask,
    $core.String? message,
  }) {
    final result = create();
    if (abiVersion != null) result.abiVersion = abiVersion;
    if (schemaVersion != null) result.schemaVersion = schemaVersion;
    if (grantedCapabilitiesMask != null)
      result.grantedCapabilitiesMask = grantedCapabilitiesMask;
    if (message != null) result.message = message;
    return result;
  }

  EngineInitAck._();

  factory EngineInitAck.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EngineInitAck.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EngineInitAck',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'abiVersion', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'schemaVersion',
        fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(3, _omitFieldNames ? '' : 'grantedCapabilitiesMask',
        $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(4, _omitFieldNames ? '' : 'message')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineInitAck clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineInitAck copyWith(void Function(EngineInitAck) updates) =>
      super.copyWith((message) => updates(message as EngineInitAck))
          as EngineInitAck;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineInitAck create() => EngineInitAck._();
  @$core.override
  EngineInitAck createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EngineInitAck getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EngineInitAck>(create);
  static EngineInitAck? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get abiVersion => $_getIZ(0);
  @$pb.TagNumber(1)
  set abiVersion($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAbiVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearAbiVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get schemaVersion => $_getIZ(1);
  @$pb.TagNumber(2)
  set schemaVersion($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSchemaVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearSchemaVersion() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get grantedCapabilitiesMask => $_getI64(2);
  @$pb.TagNumber(3)
  set grantedCapabilitiesMask($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasGrantedCapabilitiesMask() => $_has(2);
  @$pb.TagNumber(3)
  void clearGrantedCapabilitiesMask() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get message => $_getSZ(3);
  @$pb.TagNumber(4)
  set message($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearMessage() => $_clearField(4);
}

class CommandEvent extends $pb.GeneratedMessage {
  factory CommandEvent({
    $core.List<$core.int>? commandBytes,
  }) {
    final result = create();
    if (commandBytes != null) result.commandBytes = commandBytes;
    return result;
  }

  CommandEvent._();

  factory CommandEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CommandEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CommandEvent',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'commandBytes', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommandEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CommandEvent copyWith(void Function(CommandEvent) updates) =>
      super.copyWith((message) => updates(message as CommandEvent))
          as CommandEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CommandEvent create() => CommandEvent._();
  @$core.override
  CommandEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CommandEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CommandEvent>(create);
  static CommandEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get commandBytes => $_getN(0);
  @$pb.TagNumber(1)
  set commandBytes($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasCommandBytes() => $_has(0);
  @$pb.TagNumber(1)
  void clearCommandBytes() => $_clearField(1);
}

class PointerEvent extends $pb.GeneratedMessage {
  factory PointerEvent({
    $fixnum.Int64? pointerId,
    PointerPhase? phase,
    DrawPoint? position,
    $core.int? buttons,
    $core.int? modifiers,
  }) {
    final result = create();
    if (pointerId != null) result.pointerId = pointerId;
    if (phase != null) result.phase = phase;
    if (position != null) result.position = position;
    if (buttons != null) result.buttons = buttons;
    if (modifiers != null) result.modifiers = modifiers;
    return result;
  }

  PointerEvent._();

  factory PointerEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PointerEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PointerEvent',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'pointerId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aE<PointerPhase>(2, _omitFieldNames ? '' : 'phase',
        enumValues: PointerPhase.values)
    ..aOM<DrawPoint>(3, _omitFieldNames ? '' : 'position',
        subBuilder: DrawPoint.create)
    ..aI(4, _omitFieldNames ? '' : 'buttons', fieldType: $pb.PbFieldType.OU3)
    ..aI(5, _omitFieldNames ? '' : 'modifiers', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerEvent copyWith(void Function(PointerEvent) updates) =>
      super.copyWith((message) => updates(message as PointerEvent))
          as PointerEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PointerEvent create() => PointerEvent._();
  @$core.override
  PointerEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PointerEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PointerEvent>(create);
  static PointerEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get pointerId => $_getI64(0);
  @$pb.TagNumber(1)
  set pointerId($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPointerId() => $_has(0);
  @$pb.TagNumber(1)
  void clearPointerId() => $_clearField(1);

  @$pb.TagNumber(2)
  PointerPhase get phase => $_getN(1);
  @$pb.TagNumber(2)
  set phase(PointerPhase value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPhase() => $_has(1);
  @$pb.TagNumber(2)
  void clearPhase() => $_clearField(2);

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
  $core.int get buttons => $_getIZ(3);
  @$pb.TagNumber(4)
  set buttons($core.int value) => $_setUnsignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasButtons() => $_has(3);
  @$pb.TagNumber(4)
  void clearButtons() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get modifiers => $_getIZ(4);
  @$pb.TagNumber(5)
  set modifiers($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasModifiers() => $_has(4);
  @$pb.TagNumber(5)
  void clearModifiers() => $_clearField(5);
}

class KeyboardEvent extends $pb.GeneratedMessage {
  factory KeyboardEvent({
    $core.String? key,
    $core.bool? down,
    $core.int? modifiers,
  }) {
    final result = create();
    if (key != null) result.key = key;
    if (down != null) result.down = down;
    if (modifiers != null) result.modifiers = modifiers;
    return result;
  }

  KeyboardEvent._();

  factory KeyboardEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory KeyboardEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'KeyboardEvent',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'key')
    ..aOB(2, _omitFieldNames ? '' : 'down')
    ..aI(3, _omitFieldNames ? '' : 'modifiers', fieldType: $pb.PbFieldType.OU3)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KeyboardEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KeyboardEvent copyWith(void Function(KeyboardEvent) updates) =>
      super.copyWith((message) => updates(message as KeyboardEvent))
          as KeyboardEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static KeyboardEvent create() => KeyboardEvent._();
  @$core.override
  KeyboardEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static KeyboardEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<KeyboardEvent>(create);
  static KeyboardEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get key => $_getSZ(0);
  @$pb.TagNumber(1)
  set key($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasKey() => $_has(0);
  @$pb.TagNumber(1)
  void clearKey() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get down => $_getBF(1);
  @$pb.TagNumber(2)
  set down($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDown() => $_has(1);
  @$pb.TagNumber(2)
  void clearDown() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get modifiers => $_getIZ(2);
  @$pb.TagNumber(3)
  set modifiers($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasModifiers() => $_has(2);
  @$pb.TagNumber(3)
  void clearModifiers() => $_clearField(3);
}

class ToolEvent extends $pb.GeneratedMessage {
  factory ToolEvent({
    $core.String? toolId,
    $core.List<$core.int>? payload,
  }) {
    final result = create();
    if (toolId != null) result.toolId = toolId;
    if (payload != null) result.payload = payload;
    return result;
  }

  ToolEvent._();

  factory ToolEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolEvent',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'toolId')
    ..a<$core.List<$core.int>>(
        2, _omitFieldNames ? '' : 'payload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolEvent copyWith(void Function(ToolEvent) updates) =>
      super.copyWith((message) => updates(message as ToolEvent)) as ToolEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolEvent create() => ToolEvent._();
  @$core.override
  ToolEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolEvent getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolEvent>(create);
  static ToolEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get toolId => $_getSZ(0);
  @$pb.TagNumber(1)
  set toolId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasToolId() => $_has(0);
  @$pb.TagNumber(1)
  void clearToolId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.List<$core.int> get payload => $_getN(1);
  @$pb.TagNumber(2)
  set payload($core.List<$core.int> value) => $_setBytes(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPayload() => $_has(1);
  @$pb.TagNumber(2)
  void clearPayload() => $_clearField(2);
}

class ConfigEvent extends $pb.GeneratedMessage {
  factory ConfigEvent({
    $core.String? localeTag,
    $core.double? scaleFactor,
    $core.List<$core.int>? configPayload,
  }) {
    final result = create();
    if (localeTag != null) result.localeTag = localeTag;
    if (scaleFactor != null) result.scaleFactor = scaleFactor;
    if (configPayload != null) result.configPayload = configPayload;
    return result;
  }

  ConfigEvent._();

  factory ConfigEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfigEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfigEvent',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'localeTag')
    ..aD(2, _omitFieldNames ? '' : 'scaleFactor')
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'configPayload', $pb.PbFieldType.OY)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigEvent copyWith(void Function(ConfigEvent) updates) =>
      super.copyWith((message) => updates(message as ConfigEvent))
          as ConfigEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfigEvent create() => ConfigEvent._();
  @$core.override
  ConfigEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfigEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfigEvent>(create);
  static ConfigEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get localeTag => $_getSZ(0);
  @$pb.TagNumber(1)
  set localeTag($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLocaleTag() => $_has(0);
  @$pb.TagNumber(1)
  void clearLocaleTag() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get scaleFactor => $_getN(1);
  @$pb.TagNumber(2)
  set scaleFactor($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasScaleFactor() => $_has(1);
  @$pb.TagNumber(2)
  void clearScaleFactor() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get configPayload => $_getN(2);
  @$pb.TagNumber(3)
  set configPayload($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasConfigPayload() => $_has(2);
  @$pb.TagNumber(3)
  void clearConfigPayload() => $_clearField(3);
}

class TextMetricsRequest extends $pb.GeneratedMessage {
  factory TextMetricsRequest({
    $core.String? text,
    $core.double? fontSize,
    $core.String? fontFamily,
    $core.double? maxWidth,
    $core.double? minWidth,
    $core.String? localeTag,
    $core.bool? isResizing,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (fontSize != null) result.fontSize = fontSize;
    if (fontFamily != null) result.fontFamily = fontFamily;
    if (maxWidth != null) result.maxWidth = maxWidth;
    if (minWidth != null) result.minWidth = minWidth;
    if (localeTag != null) result.localeTag = localeTag;
    if (isResizing != null) result.isResizing = isResizing;
    return result;
  }

  TextMetricsRequest._();

  factory TextMetricsRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TextMetricsRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TextMetricsRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aD(2, _omitFieldNames ? '' : 'fontSize')
    ..aOS(3, _omitFieldNames ? '' : 'fontFamily')
    ..aD(4, _omitFieldNames ? '' : 'maxWidth')
    ..aD(5, _omitFieldNames ? '' : 'minWidth')
    ..aOS(6, _omitFieldNames ? '' : 'localeTag')
    ..aOB(7, _omitFieldNames ? '' : 'isResizing')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TextMetricsRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TextMetricsRequest copyWith(void Function(TextMetricsRequest) updates) =>
      super.copyWith((message) => updates(message as TextMetricsRequest))
          as TextMetricsRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TextMetricsRequest create() => TextMetricsRequest._();
  @$core.override
  TextMetricsRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TextMetricsRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TextMetricsRequest>(create);
  static TextMetricsRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get fontSize => $_getN(1);
  @$pb.TagNumber(2)
  set fontSize($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFontSize() => $_has(1);
  @$pb.TagNumber(2)
  void clearFontSize() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get fontFamily => $_getSZ(2);
  @$pb.TagNumber(3)
  set fontFamily($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFontFamily() => $_has(2);
  @$pb.TagNumber(3)
  void clearFontFamily() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get maxWidth => $_getN(3);
  @$pb.TagNumber(4)
  set maxWidth($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxWidth() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxWidth() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get minWidth => $_getN(4);
  @$pb.TagNumber(5)
  set minWidth($core.double value) => $_setDouble(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMinWidth() => $_has(4);
  @$pb.TagNumber(5)
  void clearMinWidth() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get localeTag => $_getSZ(5);
  @$pb.TagNumber(6)
  set localeTag($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLocaleTag() => $_has(5);
  @$pb.TagNumber(6)
  void clearLocaleTag() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.bool get isResizing => $_getBF(6);
  @$pb.TagNumber(7)
  set isResizing($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasIsResizing() => $_has(6);
  @$pb.TagNumber(7)
  void clearIsResizing() => $_clearField(7);
}

class TextMetricsLine extends $pb.GeneratedMessage {
  factory TextMetricsLine({
    $core.double? width,
    $core.double? height,
  }) {
    final result = create();
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    return result;
  }

  TextMetricsLine._();

  factory TextMetricsLine.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TextMetricsLine.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TextMetricsLine',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'width')
    ..aD(2, _omitFieldNames ? '' : 'height')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TextMetricsLine clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TextMetricsLine copyWith(void Function(TextMetricsLine) updates) =>
      super.copyWith((message) => updates(message as TextMetricsLine))
          as TextMetricsLine;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TextMetricsLine create() => TextMetricsLine._();
  @$core.override
  TextMetricsLine createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TextMetricsLine getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TextMetricsLine>(create);
  static TextMetricsLine? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get width => $_getN(0);
  @$pb.TagNumber(1)
  set width($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasWidth() => $_has(0);
  @$pb.TagNumber(1)
  void clearWidth() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get height => $_getN(1);
  @$pb.TagNumber(2)
  set height($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHeight() => $_has(1);
  @$pb.TagNumber(2)
  void clearHeight() => $_clearField(2);
}

class TextMetricsResult extends $pb.GeneratedMessage {
  factory TextMetricsResult({
    $core.double? width,
    $core.double? height,
    $core.double? lineHeight,
    $core.Iterable<TextMetricsLine>? lines,
  }) {
    final result = create();
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (lineHeight != null) result.lineHeight = lineHeight;
    if (lines != null) result.lines.addAll(lines);
    return result;
  }

  TextMetricsResult._();

  factory TextMetricsResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TextMetricsResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TextMetricsResult',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'width')
    ..aD(2, _omitFieldNames ? '' : 'height')
    ..aD(3, _omitFieldNames ? '' : 'lineHeight')
    ..pPM<TextMetricsLine>(4, _omitFieldNames ? '' : 'lines',
        subBuilder: TextMetricsLine.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TextMetricsResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TextMetricsResult copyWith(void Function(TextMetricsResult) updates) =>
      super.copyWith((message) => updates(message as TextMetricsResult))
          as TextMetricsResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TextMetricsResult create() => TextMetricsResult._();
  @$core.override
  TextMetricsResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TextMetricsResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TextMetricsResult>(create);
  static TextMetricsResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get width => $_getN(0);
  @$pb.TagNumber(1)
  set width($core.double value) => $_setDouble(0, value);
  @$pb.TagNumber(1)
  $core.bool hasWidth() => $_has(0);
  @$pb.TagNumber(1)
  void clearWidth() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.double get height => $_getN(1);
  @$pb.TagNumber(2)
  set height($core.double value) => $_setDouble(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHeight() => $_has(1);
  @$pb.TagNumber(2)
  void clearHeight() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get lineHeight => $_getN(2);
  @$pb.TagNumber(3)
  set lineHeight($core.double value) => $_setDouble(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLineHeight() => $_has(2);
  @$pb.TagNumber(3)
  void clearLineHeight() => $_clearField(3);

  @$pb.TagNumber(4)
  $pb.PbList<TextMetricsLine> get lines => $_getList(3);
}

class TextMetricsResponse extends $pb.GeneratedMessage {
  factory TextMetricsResponse({
    $fixnum.Int64? requestId,
    $core.bool? ok,
    TextMetricsResult? metrics,
    EngineError? error,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (ok != null) result.ok = ok;
    if (metrics != null) result.metrics = metrics;
    if (error != null) result.error = error;
    return result;
  }

  TextMetricsResponse._();

  factory TextMetricsResponse.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TextMetricsResponse.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TextMetricsResponse',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'requestId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOB(2, _omitFieldNames ? '' : 'ok')
    ..aOM<TextMetricsResult>(3, _omitFieldNames ? '' : 'metrics',
        subBuilder: TextMetricsResult.create)
    ..aOM<EngineError>(4, _omitFieldNames ? '' : 'error',
        subBuilder: EngineError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TextMetricsResponse clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TextMetricsResponse copyWith(void Function(TextMetricsResponse) updates) =>
      super.copyWith((message) => updates(message as TextMetricsResponse))
          as TextMetricsResponse;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TextMetricsResponse create() => TextMetricsResponse._();
  @$core.override
  TextMetricsResponse createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TextMetricsResponse getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TextMetricsResponse>(create);
  static TextMetricsResponse? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get requestId => $_getI64(0);
  @$pb.TagNumber(1)
  set requestId($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get ok => $_getBF(1);
  @$pb.TagNumber(2)
  set ok($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOk() => $_has(1);
  @$pb.TagNumber(2)
  void clearOk() => $_clearField(2);

  @$pb.TagNumber(3)
  TextMetricsResult get metrics => $_getN(2);
  @$pb.TagNumber(3)
  set metrics(TextMetricsResult value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasMetrics() => $_has(2);
  @$pb.TagNumber(3)
  void clearMetrics() => $_clearField(3);
  @$pb.TagNumber(3)
  TextMetricsResult ensureMetrics() => $_ensure(2);

  @$pb.TagNumber(4)
  EngineError get error => $_getN(3);
  @$pb.TagNumber(4)
  set error(EngineError value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasError() => $_has(3);
  @$pb.TagNumber(4)
  void clearError() => $_clearField(4);
  @$pb.TagNumber(4)
  EngineError ensureError() => $_ensure(3);
}

enum EngineInput_Payload {
  commandEvent,
  pointerEvent,
  keyboardEvent,
  toolEvent,
  configEvent,
  textMetricsResponse,
  notSet
}

class EngineInput extends $pb.GeneratedMessage {
  factory EngineInput({
    $fixnum.Int64? sequence,
    CommandEvent? commandEvent,
    PointerEvent? pointerEvent,
    KeyboardEvent? keyboardEvent,
    ToolEvent? toolEvent,
    ConfigEvent? configEvent,
    TextMetricsResponse? textMetricsResponse,
  }) {
    final result = create();
    if (sequence != null) result.sequence = sequence;
    if (commandEvent != null) result.commandEvent = commandEvent;
    if (pointerEvent != null) result.pointerEvent = pointerEvent;
    if (keyboardEvent != null) result.keyboardEvent = keyboardEvent;
    if (toolEvent != null) result.toolEvent = toolEvent;
    if (configEvent != null) result.configEvent = configEvent;
    if (textMetricsResponse != null)
      result.textMetricsResponse = textMetricsResponse;
    return result;
  }

  EngineInput._();

  factory EngineInput.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EngineInput.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, EngineInput_Payload>
      _EngineInput_PayloadByTag = {
    10: EngineInput_Payload.commandEvent,
    11: EngineInput_Payload.pointerEvent,
    12: EngineInput_Payload.keyboardEvent,
    13: EngineInput_Payload.toolEvent,
    14: EngineInput_Payload.configEvent,
    15: EngineInput_Payload.textMetricsResponse,
    0: EngineInput_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EngineInput',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..oo(0, [10, 11, 12, 13, 14, 15])
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<CommandEvent>(10, _omitFieldNames ? '' : 'commandEvent',
        subBuilder: CommandEvent.create)
    ..aOM<PointerEvent>(11, _omitFieldNames ? '' : 'pointerEvent',
        subBuilder: PointerEvent.create)
    ..aOM<KeyboardEvent>(12, _omitFieldNames ? '' : 'keyboardEvent',
        subBuilder: KeyboardEvent.create)
    ..aOM<ToolEvent>(13, _omitFieldNames ? '' : 'toolEvent',
        subBuilder: ToolEvent.create)
    ..aOM<ConfigEvent>(14, _omitFieldNames ? '' : 'configEvent',
        subBuilder: ConfigEvent.create)
    ..aOM<TextMetricsResponse>(15, _omitFieldNames ? '' : 'textMetricsResponse',
        subBuilder: TextMetricsResponse.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineInput clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineInput copyWith(void Function(EngineInput) updates) =>
      super.copyWith((message) => updates(message as EngineInput))
          as EngineInput;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineInput create() => EngineInput._();
  @$core.override
  EngineInput createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EngineInput getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EngineInput>(create);
  static EngineInput? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  EngineInput_Payload whichPayload() =>
      _EngineInput_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $fixnum.Int64 get sequence => $_getI64(0);
  @$pb.TagNumber(1)
  set sequence($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSequence() => $_has(0);
  @$pb.TagNumber(1)
  void clearSequence() => $_clearField(1);

  @$pb.TagNumber(10)
  CommandEvent get commandEvent => $_getN(1);
  @$pb.TagNumber(10)
  set commandEvent(CommandEvent value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasCommandEvent() => $_has(1);
  @$pb.TagNumber(10)
  void clearCommandEvent() => $_clearField(10);
  @$pb.TagNumber(10)
  CommandEvent ensureCommandEvent() => $_ensure(1);

  @$pb.TagNumber(11)
  PointerEvent get pointerEvent => $_getN(2);
  @$pb.TagNumber(11)
  set pointerEvent(PointerEvent value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasPointerEvent() => $_has(2);
  @$pb.TagNumber(11)
  void clearPointerEvent() => $_clearField(11);
  @$pb.TagNumber(11)
  PointerEvent ensurePointerEvent() => $_ensure(2);

  @$pb.TagNumber(12)
  KeyboardEvent get keyboardEvent => $_getN(3);
  @$pb.TagNumber(12)
  set keyboardEvent(KeyboardEvent value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasKeyboardEvent() => $_has(3);
  @$pb.TagNumber(12)
  void clearKeyboardEvent() => $_clearField(12);
  @$pb.TagNumber(12)
  KeyboardEvent ensureKeyboardEvent() => $_ensure(3);

  @$pb.TagNumber(13)
  ToolEvent get toolEvent => $_getN(4);
  @$pb.TagNumber(13)
  set toolEvent(ToolEvent value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasToolEvent() => $_has(4);
  @$pb.TagNumber(13)
  void clearToolEvent() => $_clearField(13);
  @$pb.TagNumber(13)
  ToolEvent ensureToolEvent() => $_ensure(4);

  @$pb.TagNumber(14)
  ConfigEvent get configEvent => $_getN(5);
  @$pb.TagNumber(14)
  set configEvent(ConfigEvent value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasConfigEvent() => $_has(5);
  @$pb.TagNumber(14)
  void clearConfigEvent() => $_clearField(14);
  @$pb.TagNumber(14)
  ConfigEvent ensureConfigEvent() => $_ensure(5);

  @$pb.TagNumber(15)
  TextMetricsResponse get textMetricsResponse => $_getN(6);
  @$pb.TagNumber(15)
  set textMetricsResponse(TextMetricsResponse value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasTextMetricsResponse() => $_has(6);
  @$pb.TagNumber(15)
  void clearTextMetricsResponse() => $_clearField(15);
  @$pb.TagNumber(15)
  TextMetricsResponse ensureTextMetricsResponse() => $_ensure(6);
}

class PointerHostRequest extends $pb.GeneratedMessage {
  factory PointerHostRequest({
    PointerEvent? event,
  }) {
    final result = create();
    if (event != null) result.event = event;
    return result;
  }

  PointerHostRequest._();

  factory PointerHostRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PointerHostRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PointerHostRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aOM<PointerEvent>(1, _omitFieldNames ? '' : 'event',
        subBuilder: PointerEvent.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerHostRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PointerHostRequest copyWith(void Function(PointerHostRequest) updates) =>
      super.copyWith((message) => updates(message as PointerHostRequest))
          as PointerHostRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PointerHostRequest create() => PointerHostRequest._();
  @$core.override
  PointerHostRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PointerHostRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PointerHostRequest>(create);
  static PointerHostRequest? _defaultInstance;

  @$pb.TagNumber(1)
  PointerEvent get event => $_getN(0);
  @$pb.TagNumber(1)
  set event(PointerEvent value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasEvent() => $_has(0);
  @$pb.TagNumber(1)
  void clearEvent() => $_clearField(1);
  @$pb.TagNumber(1)
  PointerEvent ensureEvent() => $_ensure(0);
}

class KeyboardHostRequest extends $pb.GeneratedMessage {
  factory KeyboardHostRequest({
    KeyboardEvent? event,
  }) {
    final result = create();
    if (event != null) result.event = event;
    return result;
  }

  KeyboardHostRequest._();

  factory KeyboardHostRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory KeyboardHostRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'KeyboardHostRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aOM<KeyboardEvent>(1, _omitFieldNames ? '' : 'event',
        subBuilder: KeyboardEvent.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KeyboardHostRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  KeyboardHostRequest copyWith(void Function(KeyboardHostRequest) updates) =>
      super.copyWith((message) => updates(message as KeyboardHostRequest))
          as KeyboardHostRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static KeyboardHostRequest create() => KeyboardHostRequest._();
  @$core.override
  KeyboardHostRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static KeyboardHostRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<KeyboardHostRequest>(create);
  static KeyboardHostRequest? _defaultInstance;

  @$pb.TagNumber(1)
  KeyboardEvent get event => $_getN(0);
  @$pb.TagNumber(1)
  set event(KeyboardEvent value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasEvent() => $_has(0);
  @$pb.TagNumber(1)
  void clearEvent() => $_clearField(1);
  @$pb.TagNumber(1)
  KeyboardEvent ensureEvent() => $_ensure(0);
}

class ToolHostRequest extends $pb.GeneratedMessage {
  factory ToolHostRequest({
    ToolEvent? event,
  }) {
    final result = create();
    if (event != null) result.event = event;
    return result;
  }

  ToolHostRequest._();

  factory ToolHostRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolHostRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolHostRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..aOM<ToolEvent>(1, _omitFieldNames ? '' : 'event',
        subBuilder: ToolEvent.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolHostRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolHostRequest copyWith(void Function(ToolHostRequest) updates) =>
      super.copyWith((message) => updates(message as ToolHostRequest))
          as ToolHostRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolHostRequest create() => ToolHostRequest._();
  @$core.override
  ToolHostRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolHostRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ToolHostRequest>(create);
  static ToolHostRequest? _defaultInstance;

  @$pb.TagNumber(1)
  ToolEvent get event => $_getN(0);
  @$pb.TagNumber(1)
  set event(ToolEvent value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasEvent() => $_has(0);
  @$pb.TagNumber(1)
  void clearEvent() => $_clearField(1);
  @$pb.TagNumber(1)
  ToolEvent ensureEvent() => $_ensure(0);
}

enum HostRequest_Payload {
  textMetricsRequest,
  pointerHostRequest,
  keyboardHostRequest,
  toolHostRequest,
  notSet
}

class HostRequest extends $pb.GeneratedMessage {
  factory HostRequest({
    $fixnum.Int64? requestId,
    TextMetricsRequest? textMetricsRequest,
    PointerHostRequest? pointerHostRequest,
    KeyboardHostRequest? keyboardHostRequest,
    ToolHostRequest? toolHostRequest,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (textMetricsRequest != null)
      result.textMetricsRequest = textMetricsRequest;
    if (pointerHostRequest != null)
      result.pointerHostRequest = pointerHostRequest;
    if (keyboardHostRequest != null)
      result.keyboardHostRequest = keyboardHostRequest;
    if (toolHostRequest != null) result.toolHostRequest = toolHostRequest;
    return result;
  }

  HostRequest._();

  factory HostRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HostRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, HostRequest_Payload>
      _HostRequest_PayloadByTag = {
    10: HostRequest_Payload.textMetricsRequest,
    11: HostRequest_Payload.pointerHostRequest,
    12: HostRequest_Payload.keyboardHostRequest,
    13: HostRequest_Payload.toolHostRequest,
    0: HostRequest_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HostRequest',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..oo(0, [10, 11, 12, 13])
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'requestId', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<TextMetricsRequest>(10, _omitFieldNames ? '' : 'textMetricsRequest',
        subBuilder: TextMetricsRequest.create)
    ..aOM<PointerHostRequest>(11, _omitFieldNames ? '' : 'pointerHostRequest',
        subBuilder: PointerHostRequest.create)
    ..aOM<KeyboardHostRequest>(12, _omitFieldNames ? '' : 'keyboardHostRequest',
        subBuilder: KeyboardHostRequest.create)
    ..aOM<ToolHostRequest>(13, _omitFieldNames ? '' : 'toolHostRequest',
        subBuilder: ToolHostRequest.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HostRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HostRequest copyWith(void Function(HostRequest) updates) =>
      super.copyWith((message) => updates(message as HostRequest))
          as HostRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HostRequest create() => HostRequest._();
  @$core.override
  HostRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HostRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HostRequest>(create);
  static HostRequest? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  HostRequest_Payload whichPayload() =>
      _HostRequest_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $fixnum.Int64 get requestId => $_getI64(0);
  @$pb.TagNumber(1)
  set requestId($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(10)
  TextMetricsRequest get textMetricsRequest => $_getN(1);
  @$pb.TagNumber(10)
  set textMetricsRequest(TextMetricsRequest value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasTextMetricsRequest() => $_has(1);
  @$pb.TagNumber(10)
  void clearTextMetricsRequest() => $_clearField(10);
  @$pb.TagNumber(10)
  TextMetricsRequest ensureTextMetricsRequest() => $_ensure(1);

  @$pb.TagNumber(11)
  PointerHostRequest get pointerHostRequest => $_getN(2);
  @$pb.TagNumber(11)
  set pointerHostRequest(PointerHostRequest value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasPointerHostRequest() => $_has(2);
  @$pb.TagNumber(11)
  void clearPointerHostRequest() => $_clearField(11);
  @$pb.TagNumber(11)
  PointerHostRequest ensurePointerHostRequest() => $_ensure(2);

  @$pb.TagNumber(12)
  KeyboardHostRequest get keyboardHostRequest => $_getN(3);
  @$pb.TagNumber(12)
  set keyboardHostRequest(KeyboardHostRequest value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasKeyboardHostRequest() => $_has(3);
  @$pb.TagNumber(12)
  void clearKeyboardHostRequest() => $_clearField(12);
  @$pb.TagNumber(12)
  KeyboardHostRequest ensureKeyboardHostRequest() => $_ensure(3);

  @$pb.TagNumber(13)
  ToolHostRequest get toolHostRequest => $_getN(4);
  @$pb.TagNumber(13)
  set toolHostRequest(ToolHostRequest value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasToolHostRequest() => $_has(4);
  @$pb.TagNumber(13)
  void clearToolHostRequest() => $_clearField(13);
  @$pb.TagNumber(13)
  ToolHostRequest ensureToolHostRequest() => $_ensure(4);
}

class EngineStateDelta extends $pb.GeneratedMessage {
  factory EngineStateDelta({
    $fixnum.Int64? documentVersion,
    $fixnum.Int64? selectionVersion,
    $core.Iterable<$core.String>? changedElementIds,
  }) {
    final result = create();
    if (documentVersion != null) result.documentVersion = documentVersion;
    if (selectionVersion != null) result.selectionVersion = selectionVersion;
    if (changedElementIds != null)
      result.changedElementIds.addAll(changedElementIds);
    return result;
  }

  EngineStateDelta._();

  factory EngineStateDelta.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EngineStateDelta.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EngineStateDelta',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'documentVersion', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'selectionVersion', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..pPS(3, _omitFieldNames ? '' : 'changedElementIds')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineStateDelta clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineStateDelta copyWith(void Function(EngineStateDelta) updates) =>
      super.copyWith((message) => updates(message as EngineStateDelta))
          as EngineStateDelta;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineStateDelta create() => EngineStateDelta._();
  @$core.override
  EngineStateDelta createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EngineStateDelta getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EngineStateDelta>(create);
  static EngineStateDelta? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get documentVersion => $_getI64(0);
  @$pb.TagNumber(1)
  set documentVersion($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasDocumentVersion() => $_has(0);
  @$pb.TagNumber(1)
  void clearDocumentVersion() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get selectionVersion => $_getI64(1);
  @$pb.TagNumber(2)
  set selectionVersion($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSelectionVersion() => $_has(1);
  @$pb.TagNumber(2)
  void clearSelectionVersion() => $_clearField(2);

  /// Canonical deterministic element IDs affected by the state transition.
  @$pb.TagNumber(3)
  $pb.PbList<$core.String> get changedElementIds => $_getList(2);
}

enum EngineOutput_Payload {
  initAck,
  snapshot,
  stateDelta,
  framePlan,
  event,
  hostRequest,
  notSet
}

class EngineOutput extends $pb.GeneratedMessage {
  factory EngineOutput({
    $fixnum.Int64? sequence,
    EngineInitAck? initAck,
    EngineSnapshot? snapshot,
    EngineStateDelta? stateDelta,
    FrameRenderPlan? framePlan,
    EngineEvent? event,
    HostRequest? hostRequest,
  }) {
    final result = create();
    if (sequence != null) result.sequence = sequence;
    if (initAck != null) result.initAck = initAck;
    if (snapshot != null) result.snapshot = snapshot;
    if (stateDelta != null) result.stateDelta = stateDelta;
    if (framePlan != null) result.framePlan = framePlan;
    if (event != null) result.event = event;
    if (hostRequest != null) result.hostRequest = hostRequest;
    return result;
  }

  EngineOutput._();

  factory EngineOutput.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EngineOutput.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, EngineOutput_Payload>
      _EngineOutput_PayloadByTag = {
    10: EngineOutput_Payload.initAck,
    11: EngineOutput_Payload.snapshot,
    12: EngineOutput_Payload.stateDelta,
    13: EngineOutput_Payload.framePlan,
    14: EngineOutput_Payload.event,
    15: EngineOutput_Payload.hostRequest,
    0: EngineOutput_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EngineOutput',
      package:
          const $pb.PackageName(_omitMessageNames ? '' : 'snowdraw.engine.v2'),
      createEmptyInstance: create)
    ..oo(0, [10, 11, 12, 13, 14, 15])
    ..a<$fixnum.Int64>(
        1, _omitFieldNames ? '' : 'sequence', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOM<EngineInitAck>(10, _omitFieldNames ? '' : 'initAck',
        subBuilder: EngineInitAck.create)
    ..aOM<EngineSnapshot>(11, _omitFieldNames ? '' : 'snapshot',
        subBuilder: EngineSnapshot.create)
    ..aOM<EngineStateDelta>(12, _omitFieldNames ? '' : 'stateDelta',
        subBuilder: EngineStateDelta.create)
    ..aOM<FrameRenderPlan>(13, _omitFieldNames ? '' : 'framePlan',
        subBuilder: FrameRenderPlan.create)
    ..aOM<EngineEvent>(14, _omitFieldNames ? '' : 'event',
        subBuilder: EngineEvent.create)
    ..aOM<HostRequest>(15, _omitFieldNames ? '' : 'hostRequest',
        subBuilder: HostRequest.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineOutput clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EngineOutput copyWith(void Function(EngineOutput) updates) =>
      super.copyWith((message) => updates(message as EngineOutput))
          as EngineOutput;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EngineOutput create() => EngineOutput._();
  @$core.override
  EngineOutput createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EngineOutput getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<EngineOutput>(create);
  static EngineOutput? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  EngineOutput_Payload whichPayload() =>
      _EngineOutput_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  $fixnum.Int64 get sequence => $_getI64(0);
  @$pb.TagNumber(1)
  set sequence($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSequence() => $_has(0);
  @$pb.TagNumber(1)
  void clearSequence() => $_clearField(1);

  @$pb.TagNumber(10)
  EngineInitAck get initAck => $_getN(1);
  @$pb.TagNumber(10)
  set initAck(EngineInitAck value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasInitAck() => $_has(1);
  @$pb.TagNumber(10)
  void clearInitAck() => $_clearField(10);
  @$pb.TagNumber(10)
  EngineInitAck ensureInitAck() => $_ensure(1);

  @$pb.TagNumber(11)
  EngineSnapshot get snapshot => $_getN(2);
  @$pb.TagNumber(11)
  set snapshot(EngineSnapshot value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasSnapshot() => $_has(2);
  @$pb.TagNumber(11)
  void clearSnapshot() => $_clearField(11);
  @$pb.TagNumber(11)
  EngineSnapshot ensureSnapshot() => $_ensure(2);

  @$pb.TagNumber(12)
  EngineStateDelta get stateDelta => $_getN(3);
  @$pb.TagNumber(12)
  set stateDelta(EngineStateDelta value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasStateDelta() => $_has(3);
  @$pb.TagNumber(12)
  void clearStateDelta() => $_clearField(12);
  @$pb.TagNumber(12)
  EngineStateDelta ensureStateDelta() => $_ensure(3);

  @$pb.TagNumber(13)
  FrameRenderPlan get framePlan => $_getN(4);
  @$pb.TagNumber(13)
  set framePlan(FrameRenderPlan value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasFramePlan() => $_has(4);
  @$pb.TagNumber(13)
  void clearFramePlan() => $_clearField(13);
  @$pb.TagNumber(13)
  FrameRenderPlan ensureFramePlan() => $_ensure(4);

  @$pb.TagNumber(14)
  EngineEvent get event => $_getN(5);
  @$pb.TagNumber(14)
  set event(EngineEvent value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasEvent() => $_has(5);
  @$pb.TagNumber(14)
  void clearEvent() => $_clearField(14);
  @$pb.TagNumber(14)
  EngineEvent ensureEvent() => $_ensure(5);

  @$pb.TagNumber(15)
  HostRequest get hostRequest => $_getN(6);
  @$pb.TagNumber(15)
  set hostRequest(HostRequest value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasHostRequest() => $_has(6);
  @$pb.TagNumber(15)
  void clearHostRequest() => $_clearField(15);
  @$pb.TagNumber(15)
  HostRequest ensureHostRequest() => $_ensure(6);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
