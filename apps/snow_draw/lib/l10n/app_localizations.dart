import 'package:flutter/widgets.dart';

class AppLocalizations {
  AppLocalizations(this.locale);

  final Locale locale;

  static const supportedLocales = [Locale('en')];
  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  String get appTitle => 'Snow Draw';
  String get toolSelection => 'Selection';
  String get toolRectangle => 'Rectangle';
  String get toolHighlight => 'Highlight';
  String get toolFilter => 'Filter';
  String get toolArrow => 'Arrow';
  String get toolLine => 'Line';
  String get toolFreeDraw => 'Free Draw';
  String get toolText => 'Text';
  String get toolSerialNumber => 'Serial Number';
  String get objectSnapping => 'Object Snapping';
  String get gridSnapping => 'Grid Snapping';
  String get color => 'Color';
  String get textStrokeColor => 'Text Stroke Color';
  String get fillColor => 'Fill Color';
  String get fillStyle => 'Fill Style';
  String get strokeStyle => 'Stroke Style';
  String get strokeWidth => 'Stroke Width';
  String get arrowType => 'Arrow Type';
  String get arrowTypeStraight => 'Straight';
  String get arrowTypeCurved => 'Curved';
  String get arrowTypeElbow => 'Elbow';
  String get arrowheads => 'Arrowheads';
  String get startArrowhead => 'Start Arrowhead';
  String get endArrowhead => 'End Arrowhead';
  String get arrowheadNone => 'None';
  String get arrowheadStandard => 'Standard';
  String get arrowheadTriangle => 'Triangle';
  String get arrowheadSquare => 'Square';
  String get arrowheadCircle => 'Circle';
  String get arrowheadDiamond => 'Diamond';
  String get arrowheadInvertedTriangle => 'Inverted Triangle';
  String get arrowheadVerticalLine => 'Vertical Line';
  String get textStrokeWidth => 'Text Stroke Width';
  String get highlightShape => 'Highlight Shape';
  String get highlightShapeRectangle => 'Rectangle';
  String get highlightShapeEllipse => 'Ellipse';
  String get filterType => 'Filter Type';
  String get filterTypeMosaic => 'Mosaic';
  String get filterTypeGaussianBlur => 'Gaussian Blur';
  String get filterTypeGrayscale => 'Grayscale';
  String get filterTypeInversion => 'Inversion';
  String get filterStrength => 'Filter Strength';
  String get highlightTextStrokeWidth => 'Highlight Stroke Width';
  String get highlightTextStrokeColor => 'Highlight Stroke Color';
  String get maskColor => 'Mask Color';
  String get maskOpacity => 'Mask Opacity';
  String get fontSize => 'Font Size';
  String get fontFamily => 'Font Family';
  String get number => 'Number';
  String get increase => 'Increase';
  String get decrease => 'Decrease';
  String get createText => 'Create Text';
  String get fontFamilySystem => 'System';
  String get fontFamilySans => 'Sans Serif';
  String get fontFamilySerif => 'Serif';
  String get fontFamilyMonospace => 'Monospace';
  String get textAlignment => 'Text Alignment';
  String get horizontalAlign => 'Horizontal Align';
  String get verticalAlign => 'Vertical Align';
  String get alignLeft => 'Align Left';
  String get alignCenter => 'Align Center';
  String get alignRight => 'Align Right';
  String get alignTop => 'Align Top';
  String get alignBottom => 'Align Bottom';
  String get cornerRadius => 'Corner Radius';
  String get opacity => 'Opacity';
  String get layerOrder => 'Layer Order';
  String get bringToFront => 'Bring to Top';
  String get sendToBack => 'Send to Bottom';
  String get bringForward => 'Bring Forward';
  String get sendBackward => 'Send Backward';
  String get copy => 'Copy';
  String get delete => 'Delete';
  String get operations => 'Operations';
  String get undo => 'Undo';
  String get redo => 'Redo';
  String get zoomIn => 'Zoom In';
  String get zoomOut => 'Zoom Out';
  String get resetZoom => 'Reset Zoom';
  String get mixed => 'Mixed';
  String get thin => 'Thin';
  String get medium => 'Medium';
  String get thick => 'Thick';
  String get small => 'Small';
  String get large => 'Large';
  String get solid => 'Solid';
  String get dashed => 'Dashed';
  String get dotted => 'Dotted';
  String get lineFill => 'Line Fill';
  String get crossLineFill => 'Cross-Line Fill';
  String get solidFill => 'Solid Fill';
  String get customColor => 'Custom Color';
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'en';

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}
