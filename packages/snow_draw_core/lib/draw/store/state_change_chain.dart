import '../models/draw_state.dart';
import 'draw_store_interface.dart';

class StateChangeContext {
  const StateChangeContext({
    required this.previous,
    required this.next,
    required this.changes,
  });
  final DrawState previous;
  final DrawState next;
  final Set<DrawStateChange> changes;
}

Set<DrawStateChange> computeDrawStateChanges(
  DrawState previous,
  DrawState next,
) {
  final changes = <DrawStateChange>{};
  if (previous.domain.document != next.domain.document) {
    changes.add(DrawStateChange.document);
  }
  if (previous.domain.selection != next.domain.selection) {
    changes.add(DrawStateChange.selection);
  }
  if (previous.application.view != next.application.view) {
    changes.add(DrawStateChange.view);
  }
  if (previous.application.interaction != next.application.interaction) {
    changes.add(DrawStateChange.interaction);
  }
  return changes;
}

abstract class StateChangeHandler {
  const StateChangeHandler(this.next);
  final StateChangeHandler? next;

  bool handle(
    StateChangeContext context,
    StateChangeListener<DrawState> listener,
  );
}

class AnyChangeHandler extends StateChangeHandler {
  const AnyChangeHandler() : super(null);

  @override
  bool handle(
    StateChangeContext context,
    StateChangeListener<DrawState> listener,
  ) {
    listener(context.next);
    return true;
  }
}

class ChangeTypeHandler extends StateChangeHandler {
  const ChangeTypeHandler(this.changeType, StateChangeHandler? next)
    : super(next);
  final DrawStateChange changeType;

  @override
  bool handle(
    StateChangeContext context,
    StateChangeListener<DrawState> listener,
  ) {
    if (context.changes.contains(changeType)) {
      listener(context.next);
      return true;
    }
    return next?.handle(context, listener) ?? false;
  }
}

class StateChangeChain {
  StateChangeChain._(this._head);

  factory StateChangeChain.forChanges(Set<DrawStateChange>? changeTypes) {
    if (changeTypes == null || changeTypes.isEmpty) {
      return StateChangeChain._(const AnyChangeHandler());
    }

    StateChangeHandler? chain;
    for (final type in DrawStateChange.values.reversed) {
      if (changeTypes.contains(type)) {
        chain = ChangeTypeHandler(type, chain);
      }
    }

    return StateChangeChain._(chain ?? const AnyChangeHandler());
  }
  final StateChangeHandler _head;

  bool notify(
    StateChangeContext context,
    StateChangeListener<DrawState> listener,
  ) => _head.handle(context, listener);
}
