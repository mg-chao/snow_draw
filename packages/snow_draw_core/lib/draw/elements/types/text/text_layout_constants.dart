/// Shared text-caret width in logical pixels.
const textCursorWidth = 1.2;

/// Shared caret-to-glyph gap in logical pixels.
const textCaretGap = 1.0;

/// Shared margin reserved for caret rendering in text editors.
const double textCaretMargin = textCursorWidth + textCaretGap;

const _textLayoutHorizontalPaddingFactor = 0.01;
const _textBackgroundHorizontalPaddingFactor = 0.32;
const _textBackgroundVerticalPaddingFactor = 0.1;

/// Resolves horizontal background padding from line height.
double resolveTextBackgroundHorizontalPadding(double lineHeight) {
  final padding = lineHeight * _textBackgroundHorizontalPaddingFactor;
  if (padding.isNaN || padding.isInfinite) {
    return 0;
  }
  return padding;
}

/// Resolves vertical background padding from line height.
double resolveTextBackgroundVerticalPadding(double lineHeight) {
  final padding = lineHeight * _textBackgroundVerticalPaddingFactor;
  if (padding.isNaN || padding.isInfinite) {
    return 0;
  }
  return padding;
}

/// Resolves horizontal layout padding from line height.
double resolveTextLayoutHorizontalPadding(double lineHeight) {
  final padding = lineHeight * _textLayoutHorizontalPaddingFactor;
  if (padding.isNaN || padding.isInfinite) {
    return 0;
  }
  return padding;
}
