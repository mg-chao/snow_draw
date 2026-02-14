import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/events/state_events.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';

import '../l10n/app_localizations.dart';

class HistoryControls extends StatefulWidget {
  const HistoryControls({
    required this.strings,
    required this.store,
    super.key,
  });

  final AppLocalizations strings;
  final DefaultDrawStore store;

  @override
  State<HistoryControls> createState() => _HistoryControlsState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<AppLocalizations>('strings', strings))
      ..add(DiagnosticsProperty<DefaultDrawStore>('store', store));
  }
}

class _HistoryControlsState extends State<HistoryControls> {
  static final ButtonStyle _iconButtonStyle = IconButton.styleFrom(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    minimumSize: const Size(36, 36),
    fixedSize: const Size(36, 36),
    padding: EdgeInsets.zero,
  );

  StreamSubscription<HistoryAvailabilityChangedEvent>? _eventSubscription;
  var _canUndo = false;
  var _canRedo = false;

  @override
  void initState() {
    super.initState();
    _attachToStore(widget.store);
  }

  @override
  void didUpdateWidget(HistoryControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      _attachToStore(widget.store);
    }
  }

  void _attachToStore(DefaultDrawStore store) {
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = store.onEvent<HistoryAvailabilityChangedEvent>(
      _handleEvent,
    );
    _updateAvailability(store.canUndo, store.canRedo);
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      elevation: 2,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Tooltip(
              message: widget.strings.undo,
              child: IconButton(
                style: _iconButtonStyle,
                onPressed: _canUndo ? _handleUndo : null,
                icon: const Icon(Icons.undo, size: 20),
              ),
            ),
            Tooltip(
              message: widget.strings.redo,
              child: IconButton(
                style: _iconButtonStyle,
                onPressed: _canRedo ? _handleRedo : null,
                icon: const Icon(Icons.redo, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleUndo() => widget.store.dispatch(const Undo());

  Future<void> _handleRedo() => widget.store.dispatch(const Redo());

  void _handleEvent(HistoryAvailabilityChangedEvent event) {
    _updateAvailability(event.canUndo, event.canRedo);
  }

  void _updateAvailability(bool nextUndo, bool nextRedo) {
    if (nextUndo == _canUndo && nextRedo == _canRedo) {
      return;
    }
    if (!mounted) {
      _canUndo = nextUndo;
      _canRedo = nextRedo;
      return;
    }
    setState(() {
      _canUndo = nextUndo;
      _canRedo = nextRedo;
    });
  }
}
