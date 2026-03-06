import 'arrow_like_data.dart';

/// Project-native alias for path elements that share connector behavior.
///
/// In Snow Draw both arrows and line-style connectors reuse the same path,
/// binding, and endpoint-decoration helpers. This alias exposes that shared
/// concept without leaking migration-oriented naming into higher layers.
typedef ConnectorData = ArrowLikeData;
