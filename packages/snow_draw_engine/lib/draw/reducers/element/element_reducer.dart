import '../../actions/draw_actions.dart';
import '../../core/draw_context.dart';
import '../../models/draw_state.dart';
import 'delete_element_handler.dart';
import 'global_elements_handler.dart';
import 'serial_number_handler.dart';
import 'style_handler.dart';
import 'text_layout_refresh_handler.dart';
import 'zindex_handler.dart';

DrawState? elementReducer(
  DrawState state,
  DrawAction action,
  DrawContext context,
) => switch (action) {
  final DeleteElements delete => handleDeleteElements(state, delete, context),
  final DuplicateElements duplicate => handleDuplicateElements(
    state,
    duplicate,
    context,
  ),
  final ChangeElementZIndex zIndex => handleChangeZIndex(
    state,
    zIndex,
    context,
  ),
  final ChangeElementsZIndex zIndexBatch => handleChangeZIndexBatch(
    state,
    zIndexBatch,
    context,
  ),
  final UpdateElementsStyle style => handleUpdateElementsStyle(
    state,
    style,
    context,
  ),
  final RefreshAutoResizeTextLayoutsAfterFontLoad refresh =>
    handleRefreshAutoResizeTextLayoutsAfterFontLoad(state, refresh, context),
  final UpdateGlobalElements global => handleUpdateGlobalElements(
    state,
    global,
    context,
  ),
  final CreateSerialNumberTextElements serial =>
    handleCreateSerialNumberTextElements(state, serial, context),
  _ => null,
};
