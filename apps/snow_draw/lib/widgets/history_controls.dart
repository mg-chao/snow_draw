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
  StreamSubscription<HistoryAvailabilityChangedEvent>? _eventSubscription;
  var _canUndo = false;
  var _canRedo = false;

  @override
  void initState() {
    super.initState();
    _syncAvailability();
    _subscribe(widget.store);
  }

  @override
  void didUpdateWidget(HistoryControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.store != widget.store) {
      unawaited(_eventSubscription?.cancel());
      _syncAvailability();
      _subscribe(widget.store);
    }
  }

  void _subscribe(DefaultDrawStore store) {
    _eventSubscription = store.eventStream
        .where((event) => event is HistoryAvailabilityChangedEvent)
        .cast<HistoryAvailabilityChangedEvent>()
        .listen(_handleEvent);
  }

  void _syncAvailability() {
    _updateAvailability(widget.store.canUndo, widget.store.canRedo);
  }

  @override
  void dispose() {
    unawaited(_eventSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final buttonStyle = IconButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      minimumSize: const Size(36, 36),
      fixedSize: const Size(36, 36),
      padding: EdgeInsets.zero,
    );

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
                style: buttonStyle,
                onPressed: _canUndo ? _handleUndo : null,
                icon: const Icon(Icons.undo, size: 20),
              ),
            ),
            Tooltip(
              message: widget.strings.redo,
              child: IconButton(
                style: buttonStyle,
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
