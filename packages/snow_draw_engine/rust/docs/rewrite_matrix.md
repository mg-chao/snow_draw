# Snow Draw Rust Rewrite Matrix

This matrix tracks the current Rust runtime coverage against the Dart engine
surface and highlights parity gaps that are intentionally deferred.

Status legend:

- `implemented`: behavior is present in `engine_core` and used in runtime flow.
- `partial`: command/task exists, but semantics are reduced or some flags are
  currently ignored.
- `missing`: not yet emitted/handled by Rust runtime.

## Engine Command Coverage (v1/v2 command bytes)

| Command Kind | Status | Notes |
| --- | --- | --- |
| `select_element` | implemented | Deterministic selection/version updates. |
| `clear_selection` | implemented | Clears selected IDs and bumps selection version. |
| `select_all` | implemented | Selects all elements in snapshot. |
| `create_element` | partial | Creation works with deterministic anchor capture; `snap_override` and full host snapping parity remain deferred. |
| `update_creating_element` | partial | Resizing preview now supports `create_from_center`; `snap_override` is still not applied. |
| `add_arrow_point` | partial | Appends points for currently creating arrow/line elements and re-normalizes payload points against updated rect bounds; `snap_override`/host snapping parity remains deferred. |
| `finish_create_element` | implemented | Ends create interaction. |
| `cancel_create_element` | implemented | Removes in-progress created element. |
| `delete_elements` | implemented | Deletes by IDs and updates selection/document version. |
| `duplicate_elements` | implemented | Deterministic IDs and z-order assignment. |
| `change_element_z_index` | implemented | Routed through multi-element z-index operation. |
| `change_elements_z_index` | implemented | Deterministic reordering and z-index normalization. |
| `update_elements_style` | partial | JSON style merge works; opaque/binary payloads pass through as compatibility fallback. |
| `update_global_elements` | implemented | Stores normalized global payload and drives overlay tasks. |
| `create_serial_number_text_elements` | partial | Creates/reuses companion text elements, updates `serial_number.textElementId`, and focuses single-target text edit; text style/layout defaults are still simplified. |
| `start_text_edit` | implemented | Opens/creates text edit session. |
| `update_text_edit` | implemented | Updates text payload and optional rect. |
| `refresh_auto_resize_text_layouts_after_font_load` | implemented | V2 runtime emits text-metrics host requests for auto-resize text elements and applies response-driven layout updates; direct v1 flow now recomputes deterministic fallback auto-resize text bounds. |
| `finish_text_edit` | implemented | Commits or removes new-empty text as expected. |
| `cancel_text_edit` | implemented | Cancels text session and removes new draft text. |
| `start_edit` | partial | `move`/`resize`/`rotate` are implemented; `arrow_point` sessions are now recognized, while advanced/non-core edit types remain reduced. |
| `update_edit` | partial | `move`/`resize`/`rotate` are implemented; `arrow_point` turning/addable updates are applied with rect+point normalization and endpoint binding cleanup; `snap_override` and full elbow/curve parity remain deferred. |
| `finish_edit` | implemented | Closes edit session. |
| `cancel_edit` | implemented | Reverts to session baseline rect/rotation/payload snapshots. |
| `set_drag_pending` | implemented | Sets drag-pending interaction state. |
| `clear_drag_pending` | implemented | Returns interaction state to idle. |
| `start_box_select` | implemented | Starts box-select interaction. |
| `update_box_select` | implemented | Selects intersecting elements. |
| `finish_box_select` | implemented | Ends box-select interaction. |
| `cancel_box_select` | implemented | Cancels box-select interaction. |
| `move_camera` | implemented | Applies camera translation. |
| `zoom_camera` | implemented | Zoom applies around optional `center` and clamps to the same min/max bounds as Dart camera state. |
| `undo` | implemented | Snapshot-based undo with event emission. |
| `redo` | implemented | Snapshot-based redo with event emission. |
| `clear_history` | implemented | Clears stacks and emits history event. |

## Frame Task Emission Coverage (`Engine::build_frame_plan`)

| Frame Task Kind | Status | Notes |
| --- | --- | --- |
| `background` | implemented | Always emitted first. |
| `rectangle` | implemented | Emitted from sorted element list. |
| `line` | implemented | Emitted from sorted element list. |
| `arrow` | implemented | Emitted from sorted element list. |
| `free_draw` | implemented | Emitted from sorted element list. |
| `text` | implemented | Emitted from sorted element list. |
| `serial_number` | implemented | Emitted from sorted element list. |
| `highlight` | implemented | Emitted from sorted element list. |
| `filter` | implemented | Emitted from sorted element list. |
| `selection_outline` | implemented | Emitted when selection is non-empty. |
| `selection_controls` | implemented | Emitted when selection is non-empty. |
| `box_selection` | implemented | Emitted in box-select interaction mode. |
| `highlight_mask` | implemented | Emitted when global highlight mask is visible. |
| `watermark` | implemented | Emitted when watermark is visible. |
| `grid` | implemented | Always emitted near the top of the plan (host decides enabled/visibility). |
| `arrow_point_overlay` | partial | Emitted for single selected arrow/line elements with deterministic handle payloads and mixed normalized/world payload compatibility; advanced loop/elbow parity remains deferred. |
| `arrow_binding_highlight` | partial | Emitted for selected arrow/line bindings; hover/edit-session driven highlight parity remains deferred. |
| `hover_outline` | partial | Emitted when `global_elements_payload.hoverOutline` (or `hoveredElementId`) is present with a valid non-selected target; pointer-driven hover parity remains deferred. |
| `snap_guides` | partial | Emitted when `global_elements_payload.snapGuides` provides guide entries; runtime-computed snapping guide parity remains deferred. |

## V2 Host Request/Response Coverage

| V2 Path | Status | Notes |
| --- | --- | --- |
| `command_event -> snapshot/state_delta/frame_plan` | implemented | Core runtime flow for store dispatch. |
| `pointer_event -> host_request` | implemented | Forwarded as typed host request. |
| `keyboard_event -> host_request` | implemented | Forwarded as typed host request. |
| `tool_event -> host_request` | implemented | Forwarded as typed host request. |
| `text_metrics_request` generation | implemented | Runtime emits typed text-metrics host requests for `start_text_edit`, `update_text_edit`, and font-load refresh flows using unbounded width for auto-resize text. |
| `text_metrics_response` handling | implemented | Successful responses update auto-resize text layout bounds (line-height-aware width padding + stale-request guards) and emit snapshot/state/frame outputs. |
