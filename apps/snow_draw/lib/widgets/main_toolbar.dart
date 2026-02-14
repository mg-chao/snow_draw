import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../tool_controller.dart';

class MainToolbar extends StatefulWidget {
  const MainToolbar({
    required this.strings,
    required this.toolController,
    super.key,
  });

  final AppLocalizations strings;
  final ToolController toolController;

  @override
  State<MainToolbar> createState() => _MainToolbarState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<AppLocalizations>('strings', strings))
      ..add(
        DiagnosticsProperty<ToolController>('toolController', toolController),
      );
  }
}

class _MainToolbarState extends State<MainToolbar> {
  static const double _buttonSize = 40;
  static const double _buttonRadius = 12;
  static const double _buttonGap = 2;
  static const double _dividerGap = 8;
  static const double _iconSize = 18;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.toolController,
    builder: (context, _) {
      final theme = Theme.of(context);
      final tool = widget.toolController.value;
      final selectedColor = theme.colorScheme.primary;
      final unselectedColor = theme.iconTheme.color ?? Colors.black;
      final selectedBackground = selectedColor.withValues(alpha: 0.12);
      final dividerColor = theme.colorScheme.outlineVariant.withValues(
        alpha: 0.6,
      );
      final tools = _resolveToolItems(widget.strings);

      return Material(
        elevation: 3,
        borderRadius: BorderRadius.circular(16),
        color: Colors.white,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildToolButton(
                item: tools.first,
                currentTool: tool,
                selectedColor: selectedColor,
                unselectedColor: unselectedColor,
                selectedBackground: selectedBackground,
              ),
              _buildDivider(dividerColor),
              for (var i = 1; i < tools.length; i++) ...[
                if (i > 1) const SizedBox(width: _buttonGap),
                _buildToolButton(
                  item: tools[i],
                  currentTool: tool,
                  selectedColor: selectedColor,
                  unselectedColor: unselectedColor,
                  selectedBackground: selectedBackground,
                ),
              ],
            ],
          ),
        ),
      );
    },
  );

  List<_ToolItem> _resolveToolItems(AppLocalizations strings) => [
    _ToolItem(
      type: ToolType.selection,
      tooltip: strings.toolSelection,
      icon: Icons.near_me_outlined,
    ),
    _ToolItem(
      type: ToolType.rectangle,
      tooltip: strings.toolRectangle,
      icon: Icons.rectangle_outlined,
    ),
    _ToolItem(
      type: ToolType.arrow,
      tooltip: strings.toolArrow,
      icon: Icons.arrow_right_alt,
    ),
    _ToolItem(
      type: ToolType.line,
      tooltip: strings.toolLine,
      icon: Icons.show_chart,
    ),
    _ToolItem(
      type: ToolType.freeDraw,
      tooltip: strings.toolFreeDraw,
      icon: Icons.brush_outlined,
    ),
    _ToolItem(
      type: ToolType.highlight,
      tooltip: strings.toolHighlight,
      icon: Icons.highlight,
    ),
    _ToolItem(
      type: ToolType.text,
      tooltip: strings.toolText,
      icon: Icons.text_fields,
    ),
    _ToolItem(
      type: ToolType.serialNumber,
      tooltip: strings.toolSerialNumber,
      icon: Icons.looks_one_outlined,
    ),
    _ToolItem(
      type: ToolType.filter,
      tooltip: strings.toolFilter,
      icon: Icons.auto_fix_high,
    ),
  ];

  Widget _buildToolButton({
    required _ToolItem item,
    required ToolType currentTool,
    required Color selectedColor,
    required Color unselectedColor,
    required Color selectedBackground,
  }) {
    final selected = currentTool == item.type;
    return IconButton(
      tooltip: item.tooltip,
      onPressed: () => widget.toolController.setTool(item.type),
      icon: Icon(item.icon, size: _iconSize),
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_buttonRadius),
        ),
        minimumSize: const Size(_buttonSize, _buttonSize),
        fixedSize: const Size(_buttonSize, _buttonSize),
        padding: EdgeInsets.zero,
        foregroundColor: selected ? selectedColor : unselectedColor,
        backgroundColor: selected ? selectedBackground : Colors.transparent,
      ),
    );
  }

  Widget _buildDivider(Color color) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: _dividerGap),
    child: Container(width: 1, height: 20, color: color),
  );
}

@immutable
class _ToolItem {
  const _ToolItem({
    required this.type,
    required this.tooltip,
    required this.icon,
  });

  final ToolType type;
  final String tooltip;
  final IconData icon;
}
