import '../../actions/draw_actions.dart';
import '../../core/dependency_interfaces.dart';
import '../../models/draw_state.dart';
import 'delete_element_handler.dart';
import 'serial_number_handler.dart';
import 'style_handler.dart';
import 'zindex_handler.dart';

DrawState? elementReducer(
  DrawState state,
  DrawAction action,
  ElementReducerDeps context,
) => switch (action) {
  final DeleteElements a => handleDeleteElements(state, a, context),
  final DuplicateElements a => handleDuplicateElements(state, a, context),
  final ChangeElementZIndex a => handleChangeZIndex(state, a, context),
  final ChangeElementsZIndex a => handleChangeZIndexBatch(state, a, context),
  final UpdateElementsStyle a => handleUpdateElementsStyle(state, a, context),
  final CreateSerialNumberTextElements a =>
      handleCreateSerialNumberTextElements(state, a, context),
  _ => null,
};
