import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/utils/id_generator.dart';

import 'grid_toolbar_adapter.dart';
import 'l10n/app_localizations.dart';
import 'snap_toolbar_adapter.dart';
import 'tool_controller.dart';
import 'toolbar_adapter.dart';
import 'widgets/canvas_layer.dart';
import 'widgets/history_controls.dart';
import 'widgets/main_toolbar.dart';
import 'widgets/snap_controls.dart';
import 'widgets/style_toolbar.dart';
import 'widgets/zoom_controls.dart';

void main() {
  final drawContext = createAppContext();
  runApp(MyApp(context: drawContext));
}

DrawContext createAppContext() {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);

  return DrawContext.withDefaults(
    elementRegistry: registry,
    idGenerator: RandomStringIdGenerator().call,
  );
}

class MyApp extends StatefulWidget {
  const MyApp({required this.context, super.key});
  final DrawContext context;

  @override
  State<MyApp> createState() => _MyAppState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<DrawContext>('context', context));
  }
}

class _MyAppState extends State<MyApp> {
  late final DefaultDrawStore store;
  late final ToolController toolController;
  late final StyleToolbarAdapter styleToolbarAdapter;
  late final SnapToolbarAdapter snapToolbarAdapter;
  late final GridToolbarAdapter gridToolbarAdapter;
  late final ValueNotifier<bool> _ctrlPressedNotifier;

  @override
  void initState() {
    super.initState();
    store = DefaultDrawStore(
      context: widget.context,
      includeSelectionInHistory: true,
    );
    toolController = ToolController();
    styleToolbarAdapter = StyleToolbarAdapter(store: store);
    snapToolbarAdapter = SnapToolbarAdapter(store: store);
    gridToolbarAdapter = GridToolbarAdapter(store: store);
    _ctrlPressedNotifier = ValueNotifier<bool>(false);
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _ctrlPressedNotifier.dispose();
    toolController.dispose();
    styleToolbarAdapter.dispose();
    snapToolbarAdapter.dispose();
    gridToolbarAdapter.dispose();
    store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1576FE),
        primary: const Color(0xFF1576FE),
        surface: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        elevation: 0,
      ),
    ),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
    builder: (context, child) {
      final resolvedChild = child ?? const SizedBox.shrink();
      if (!_shouldDisableSemantics()) {
        return resolvedChild;
      }
      return Semantics(
        container: true,
        label: 'Snow Draw',
        child: ExcludeSemantics(child: resolvedChild),
      );
    },
    home: Builder(
      builder: (context) {
        final strings = AppLocalizations.of(context);
        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                const styleToolbarTop = 72.0;
                const bottomToolbarPadding = 12.0;
                const bottomControlsHeight = 44.0;
                const bottomToolbarGap = 8.0;
                const styleToolbarBottomInset =
                    bottomToolbarPadding +
                    bottomControlsHeight +
                    bottomToolbarGap;
                final styleToolbarWidth = math
                    .min(220, size.width - 24)
                    .toDouble();

                return Stack(
                  children: [
                    Positioned.fill(
                      child: CanvasLayer(
                        size: size,
                        store: store,
                        toolController: toolController,
                      ),
                    ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: MainToolbar(
                          strings: strings,
                          toolController: toolController,
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      top: styleToolbarTop,
                      child: StyleToolbar(
                        strings: strings,
                        adapter: styleToolbarAdapter,
                        toolController: toolController,
                        size: size,
                        width: styleToolbarWidth,
                        topInset: styleToolbarTop,
                        bottomInset: styleToolbarBottomInset,
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: bottomToolbarPadding,
                      child: Row(
                        children: [
                          ZoomControls(
                            strings: strings,
                            store: store,
                            size: size,
                          ),
                          const SizedBox(width: 8),
                          HistoryControls(strings: strings, store: store),
                        ],
                      ),
                    ),
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: SnapControls(
                        strings: strings,
                        snapAdapter: snapToolbarAdapter,
                        gridAdapter: gridToolbarAdapter,
                        ctrlPressedListenable: _ctrlPressedNotifier,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    ),
  );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<DefaultDrawStore>('store', store))
      ..add(
        DiagnosticsProperty<ToolController>('toolController', toolController),
      )
      ..add(
        DiagnosticsProperty<StyleToolbarAdapter>(
          'styleToolbarAdapter',
          styleToolbarAdapter,
        ),
      )
      ..add(
        DiagnosticsProperty<SnapToolbarAdapter>(
          'snapToolbarAdapter',
          snapToolbarAdapter,
        ),
      )
      ..add(
        DiagnosticsProperty<GridToolbarAdapter>(
          'gridToolbarAdapter',
          gridToolbarAdapter,
        ),
      )
      ..add(
        DiagnosticsProperty<ValueNotifier<bool>>(
          'ctrlPressedNotifier',
          _ctrlPressedNotifier,
        ),
      );
  }

  // Fix: [ERROR:flutter/shell/platform/common/accessibility_bridge.cc(114)] Failed to update ui::AXTree, error: 7 will not be in the tree and is not the new root
  bool _shouldDisableSemantics() =>
      defaultTargetPlatform == TargetPlatform.windows;

  bool _handleKeyEvent(KeyEvent event) {
    final keysPressed = HardwareKeyboard.instance.logicalKeysPressed;
    final isCtrlPressed =
        keysPressed.contains(LogicalKeyboardKey.controlLeft) ||
        keysPressed.contains(LogicalKeyboardKey.controlRight) ||
        keysPressed.contains(LogicalKeyboardKey.control);
    if (_ctrlPressedNotifier.value != isCtrlPressed) {
      _ctrlPressedNotifier.value = isCtrlPressed;
    }
    return false;
  }
}
