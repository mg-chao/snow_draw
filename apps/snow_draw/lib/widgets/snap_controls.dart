import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:snow_draw_core/draw/utils/snapping_mode.dart';

import '../grid_toolbar_adapter.dart';
import '../l10n/app_localizations.dart';
import '../snap_toolbar_adapter.dart';

class SnapControls extends StatelessWidget {
  const SnapControls({
    required this.strings,
    required this.snapAdapter,
    required this.gridAdapter,
    required this.ctrlPressedListenable,
    super.key,
  });

  final AppLocalizations strings;
  final SnapToolbarAdapter snapAdapter;
  final GridToolbarAdapter gridAdapter;
  final ValueListenable<bool> ctrlPressedListenable;

  @override
  Widget build(BuildContext context) {
    final mergedListenable = Listenable.merge([
      snapAdapter.enabledListenable,
      gridAdapter.enabledListenable,
      ctrlPressedListenable,
    ]);
    return AnimatedBuilder(
      animation: mergedListenable,
      builder: (context, _) {
        final theme = Theme.of(context);
        const buttonShape = RoundedRectangleBorder();
        final iconButtonStyle = IconButton.styleFrom(
          shape: buttonShape,
          minimumSize: const Size(36, 36),
          fixedSize: const Size(36, 36),
          padding: EdgeInsets.zero,
        );
        final dividerColor = theme.colorScheme.outlineVariant.withValues(
          alpha: 0.6,
        );
        final snapEnabled = snapAdapter.isEnabled;
        final gridEnabled = gridAdapter.isEnabled;
        final ctrlPressed = ctrlPressedListenable.value;
        final snappingMode = resolveEffectiveSnappingMode(
          gridEnabled: gridEnabled,
          objectEnabled: snapEnabled,
          ctrlPressed: ctrlPressed,
        );
        final effectiveSnapEnabled = snappingMode == SnappingMode.object;
        final effectiveGridEnabled = snappingMode == SnappingMode.grid;
        final snapIconColor = effectiveSnapEnabled
            ? theme.colorScheme.primary
            : theme.iconTheme.color ?? Colors.black;
        final gridIconColor = effectiveGridEnabled
            ? theme.colorScheme.primary
            : theme.iconTheme.color ?? Colors.black;

        return Material(
          elevation: 2,
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: '${strings.objectSnapping} (Ctrl)',
                    child: IconButton(
                      style: iconButtonStyle,
                      onPressed: snapAdapter.toggle,
                      icon: SnapIcon(color: snapIconColor, size: 20),
                    ),
                  ),
                  _buildDivider(dividerColor),
                  Tooltip(
                    message: '${strings.gridSnapping} (Ctrl)',
                    child: IconButton(
                      style: iconButtonStyle,
                      onPressed: gridAdapter.toggle,
                      icon: Icon(Icons.grid_on, size: 20, color: gridIconColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<AppLocalizations>('strings', strings))
      ..add(DiagnosticsProperty<SnapToolbarAdapter>('snapAdapter', snapAdapter))
      ..add(DiagnosticsProperty<GridToolbarAdapter>('gridAdapter', gridAdapter))
      ..add(
        DiagnosticsProperty<ValueListenable<bool>>(
          'ctrlPressedListenable',
          ctrlPressedListenable,
        ),
      );
  }

  Widget _buildDivider(Color color) =>
      Container(width: 1, height: 20, color: color);
}

class SnapIcon extends StatelessWidget {
  const SnapIcon({required this.color, this.size, super.key});

  final Color color;
  final double? size;

  static const _pathData = '''
M85.333333 85.333333a42.666667 42.666667 0 0 1 42.666667-42.666666
h170.666667a42.666667 42.666667 0 0 1 42.666666 42.666666v469.333334
a170.666667 170.666667 0 0 0 341.333334 0V85.333333a42.666667 42.666667
0 0 1 42.666666-42.666666h170.666667a42.666667 42.666667 0 0 1
42.666667 42.666666v469.333334c0 235.648-191.018667 426.666667-426.666667
426.666666S85.333333 790.314667 85.333333 554.666667V85.333333z
m85.333334 170.666667v298.666667a341.333333 341.333333 0 1 0 682.666666
0V256h-85.333333v298.666667a256 256 0 0 1-512 0V256H170.666667z
''';

  static const _svg =
      '''
<svg viewBox="0 0 1024 1024" xmlns="http://www.w3.org/2000/svg">
  <path d="$_pathData"/>
</svg>
''';

  @override
  Widget build(BuildContext context) {
    final iconSize = size ?? IconTheme.of(context).size ?? 24;
    return SvgPicture.string(
      _svg,
      width: iconSize,
      height: iconSize,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(ColorProperty('color', color))
      ..add(DoubleProperty('size', size));
  }
}
