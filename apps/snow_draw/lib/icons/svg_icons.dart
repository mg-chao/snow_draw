import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

class InlineSvgIcon extends StatelessWidget {
  const InlineSvgIcon({
    required this.svg,
    super.key,
    this.size = 18,
    this.color,
  });

  final String svg;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      _SvgIcon(svg: svg, size: size, color: color);

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('svg', svg))
      ..add(DoubleProperty('size', size))
      ..add(ColorProperty('color', color));
  }
}

class StrokeWidthSmallIcon extends InlineSvgIcon {
  const StrokeWidthSmallIcon({super.key, super.size = 18, super.color})
    : super(svg: strokeWidthSmallSvg);
}

class StrokeWidthMediumIcon extends InlineSvgIcon {
  const StrokeWidthMediumIcon({super.key, super.size = 18, super.color})
    : super(svg: strokeWidthMediumSvg);
}

class StrokeWidthLargeIcon extends InlineSvgIcon {
  const StrokeWidthLargeIcon({super.key, super.size = 18, super.color})
    : super(svg: strokeWidthLargeSvg);
}

class StrokeStyleSolidIcon extends InlineSvgIcon {
  const StrokeStyleSolidIcon({super.key, super.size = 18, super.color})
    : super(svg: strokeStyleSolidSvg);
}

class StrokeStyleDashedIcon extends InlineSvgIcon {
  const StrokeStyleDashedIcon({super.key, super.size = 18, super.color})
    : super(svg: strokeStyleDashedSvg);
}

class StrokeStyleDottedIcon extends InlineSvgIcon {
  const StrokeStyleDottedIcon({super.key, super.size = 18, super.color})
    : super(svg: strokeStyleDottedSvg);
}

class FontSizeSmallIcon extends InlineSvgIcon {
  const FontSizeSmallIcon({super.key, super.size = 18, super.color})
    : super(svg: fontSizeSmallSvg);
}

class FontSizeMediumIcon extends InlineSvgIcon {
  const FontSizeMediumIcon({super.key, super.size = 18, super.color})
    : super(svg: fontSizeMediumSvg);
}

class FontSizeLargeIcon extends InlineSvgIcon {
  const FontSizeLargeIcon({super.key, super.size = 18, super.color})
    : super(svg: fontSizeLargeSvg);
}

class FontSizeVeryLargeIcon extends InlineSvgIcon {
  const FontSizeVeryLargeIcon({super.key, super.size = 18, super.color})
    : super(svg: fontSizeVeryLargeSvg);
}

class FillStyleLineIcon extends InlineSvgIcon {
  const FillStyleLineIcon({super.key, super.size = 18, super.color})
    : super(svg: fillStyleLineSvg);
}

class FillStyleCrossLineIcon extends InlineSvgIcon {
  const FillStyleCrossLineIcon({super.key, super.size = 18, super.color})
    : super(svg: fillStyleCrossLineSvg);
}

class FillStyleSolidIcon extends InlineSvgIcon {
  const FillStyleSolidIcon({super.key, super.size = 18, super.color})
    : super(svg: fillStyleSolidSvg);
}

class _SvgIcon extends StatelessWidget {
  const _SvgIcon({required this.svg, required this.size, this.color});

  final String svg;
  final double size;
  final Color? color;

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('svg', svg))
      ..add(DoubleProperty('size', size))
      ..add(ColorProperty('color', color));
  }

  @override
  Widget build(BuildContext context) {
    final resolvedColor = color ?? Theme.of(context).iconTheme.color;
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: resolvedColor == null
          ? null
          : ColorFilter.mode(resolvedColor, BlendMode.srcIn),
    );
  }
}

const strokeWidthSmallSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 20 20" class="" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4.167 10h11.666" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"></path></svg>''';
const strokeWidthMediumSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 20 20" class="" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M5 10h10" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"></path></svg>''';
const strokeWidthLargeSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 20 20" class="" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M5 10h10" stroke="currentColor" stroke-width="3.75" stroke-linecap="round" stroke-linejoin="round"></path></svg>''';
const strokeStyleSolidSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 20 20" class="" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4.167 10h11.666" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"></path></svg>''';
const strokeStyleDashedSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 24 24" class="" fill="none" stroke-width="2" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><g stroke-width="2"><path stroke="none" d="M0 0h24v24H0z" fill="none"></path><path d="M5 12h2"></path><path d="M17 12h2"></path><path d="M11 12h2"></path></g></svg>''';
const strokeStyleDottedSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 24 24" class="" fill="none" stroke-width="2" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><g stroke-width="2"><path stroke="none" d="M0 0h24v24H0z" fill="none"></path><path d="M4 12v.01"></path><path d="M8 12v.01"></path><path d="M12 12v.01"></path><path d="M16 12v.01"></path><path d="M20 12v.01"></path></g></svg>''';
const fontSizeSmallSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 20 20" class="" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><g clip-path="url(#a)"><path d="M14.167 6.667a3.333 3.333 0 0 0-3.334-3.334H9.167a3.333 3.333 0 0 0 0 6.667h1.666a3.333 3.333 0 0 1 0 6.667H9.167a3.333 3.333 0 0 1-3.334-3.334" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"></path></g><defs><clipPath id="a"><path fill="#fff" d="M0 0h20v20H0z"></path></clipPath></defs></svg>''';
const fontSizeMediumSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 20 20" class="" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><g clip-path="url(#a)"><path d="M5 16.667V3.333L10 15l5-11.667v13.334" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"></path></g><defs><clipPath id="a"><path fill="#fff" d="M0 0h20v20H0z"></path></clipPath></defs></svg>''';
const fontSizeLargeSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 20 20" class="" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><g clip-path="url(#a)"><path d="M5.833 3.333v13.334h8.334" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"></path></g><defs><clipPath id="a"><path fill="#fff" d="M0 0h20v20H0z"></path></clipPath></defs></svg>''';
const fontSizeVeryLargeSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 20 20" class="" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="m1.667 3.333 6.666 13.334M8.333 3.333 1.667 16.667M11.667 3.333v13.334h6.666" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"></path></svg>''';
const fillStyleLineSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 20 20" class="" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><defs><clipPath id="FillHachureClip"><path d="M5.879 2.625h8.242a3.254 3.254 0 0 1 3.254 3.254v8.242a3.254 3.254 0 0 1-3.254 3.254H5.88a3.254 3.254 0 0 1-3.254-3.254V5.88a3.254 3.254 0 0 1 3.254-3.254Z"></path></clipPath></defs><path d="M5.879 2.625h8.242a3.254 3.254 0 0 1 3.254 3.254v8.242a3.254 3.254 0 0 1-3.254 3.254H5.88a3.254 3.254 0 0 1-3.254-3.254V5.88a3.254 3.254 0 0 1 3.254-3.254Z" stroke="currentColor" stroke-width="1.25"></path><g clip-path="url(#FillHachureClip)"><path d="M2.258 15.156 15.156 2.258M7.324 20.222 20.222 7.325m-20.444 5.35L12.675-.222m-8.157 18.34L17.416 5.22" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"></path></g></svg>''';
const fillStyleCrossLineSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 20 20" class="" fill="none" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><defs><clipPath id="FillCrossHatchClip"><path d="M5.879 2.625h8.242a3.254 3.254 0 0 1 3.254 3.254v8.242a3.254 3.254 0 0 1-3.254 3.254H5.88a3.254 3.254 0 0 1-3.254-3.254V5.88a3.254 3.254 0 0 1 3.254-3.254Z"></path></clipPath></defs><path d="M5.879 2.625h8.242a3.254 3.254 0 0 1 3.254 3.254v8.242a3.254 3.254 0 0 1-3.254 3.254H5.88a3.254 3.254 0 0 1-3.254-3.254V5.88a3.254 3.254 0 0 1 3.254-3.254Z" stroke="currentColor" stroke-width="1.25"></path><g clip-path="url(#FillCrossHatchClip)"><path d="M2.426 15.044 15.044 2.426M7.383 20 20 7.383M0 12.617 12.617 0m-7.98 17.941L17.256 5.324m-2.211 12.25L2.426 4.956M20 12.617 7.383 0m5.234 20L0 7.383m17.941 7.98L5.324 2.745" stroke="currentColor" stroke-width="1.25" stroke-linecap="round" stroke-linejoin="round"></path></g></svg>''';
const fillStyleSolidSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 20 20" class="" fill="currentColor" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><g clip-path="url(#a)"><path d="M4.91 2.625h10.18a2.284 2.284 0 0 1 2.285 2.284v10.182a2.284 2.284 0 0 1-2.284 2.284H4.909a2.284 2.284 0 0 1-2.284-2.284V4.909a2.284 2.284 0 0 1 2.284-2.284Z" stroke="currentColor" stroke-width="1.25"></path></g><defs><clipPath id="a"><path fill="#fff" d="M0 0h20v20H0z"></path></clipPath></defs></svg>''';

const arrowTypeStraightSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 24 24" class="" fill="none" stroke-width="2" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><g><path stroke="none" d="M0 0h24v24H0z" fill="none"></path><path d="M6 18l12 -12"></path><path d="M18 10v-4h-4"></path></g></svg>''';
const arrowTypeCurvedSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 24 24" class="" fill="none" stroke-width="2" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><g><path d="M16,12L20,9L16,6"></path><path d="M6 20c0 -6.075 4.925 -11 11 -11h3"></path></g></svg>''';
const arrowTypeElbowSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 24 24" class="" fill="none" stroke-width="2" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><g><path stroke="none" d="M0 0h24v24H0z" fill="none"></path><path d="M4,19L10,19C11.097,19 12,18.097 12,17L12,9C12,7.903 12.903,7 14,7L21,7"></path><path d="M18 4l3 3l-3 3"></path></g></svg>''';

class ArrowTypeStraightIcon extends InlineSvgIcon {
  const ArrowTypeStraightIcon({super.key, super.size = 18, super.color})
    : super(svg: arrowTypeStraightSvg);
}

class ArrowTypeCurvedIcon extends InlineSvgIcon {
  const ArrowTypeCurvedIcon({super.key, super.size = 18, super.color})
    : super(svg: arrowTypeCurvedSvg);
}

class ArrowTypeElbowIcon extends InlineSvgIcon {
  const ArrowTypeElbowIcon({super.key, super.size = 18, super.color})
    : super(svg: arrowTypeElbowSvg);
}

// Arrowhead SVG constants
const arrowheadNoneSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 24 24" class="" fill="none" stroke-width="2" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12h16"></path></svg>''';
const arrowheadStandardSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 24 24" class="" fill="none" stroke-width="2" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12h16"></path><path d="M16 8l4 4l-4 4"></path></svg>''';
const arrowheadTriangleSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 24 24" class="" fill="none" stroke-width="2" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12h13"></path><path d="M17 8l4 4l-4 4z" fill="currentColor"></path></svg>''';
const arrowheadSquareSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 24 24" class="" fill="none" stroke-width="2" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12h12"></path><rect x="16" y="9" width="4" height="6" stroke="currentColor" fill="none"></rect></svg>''';
const arrowheadCircleSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 24 24" class="" fill="none" stroke-width="2" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12h11"></path><circle cx="18" cy="12" r="3" stroke="currentColor" fill="none"></circle></svg>''';
const arrowheadDiamondSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 24 24" class="" fill="none" stroke-width="2" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12h11"></path><path d="M15 12l3 -3l3 3l-3 3z" stroke="currentColor" fill="none"></path></svg>''';
const arrowheadInvertedTriangleSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 24 24" class="" fill="none" stroke-width="2" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12h13"></path><path d="M17 12l4 -4l0 8z" fill="currentColor"></path></svg>''';
const arrowheadVerticalLineSvg =
    '''<svg aria-hidden="true" focusable="false" role="img" viewBox="0 0 24 24" class="" fill="none" stroke-width="2" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12h14"></path><path d="M18 8v8"></path></svg>''';

class ArrowheadNoneIcon extends InlineSvgIcon {
  const ArrowheadNoneIcon({super.key, super.size = 18, super.color})
    : super(svg: arrowheadNoneSvg);
}

class ArrowheadStandardIcon extends InlineSvgIcon {
  const ArrowheadStandardIcon({super.key, super.size = 18, super.color})
    : super(svg: arrowheadStandardSvg);
}

class ArrowheadTriangleIcon extends InlineSvgIcon {
  const ArrowheadTriangleIcon({super.key, super.size = 18, super.color})
    : super(svg: arrowheadTriangleSvg);
}

class ArrowheadSquareIcon extends InlineSvgIcon {
  const ArrowheadSquareIcon({super.key, super.size = 18, super.color})
    : super(svg: arrowheadSquareSvg);
}

class ArrowheadCircleIcon extends InlineSvgIcon {
  const ArrowheadCircleIcon({super.key, super.size = 18, super.color})
    : super(svg: arrowheadCircleSvg);
}

class ArrowheadDiamondIcon extends InlineSvgIcon {
  const ArrowheadDiamondIcon({super.key, super.size = 18, super.color})
    : super(svg: arrowheadDiamondSvg);
}

class ArrowheadInvertedTriangleIcon extends InlineSvgIcon {
  const ArrowheadInvertedTriangleIcon({super.key, super.size = 18, super.color})
    : super(svg: arrowheadInvertedTriangleSvg);
}

class ArrowheadVerticalLineIcon extends InlineSvgIcon {
  const ArrowheadVerticalLineIcon({super.key, super.size = 18, super.color})
    : super(svg: arrowheadVerticalLineSvg);
}
