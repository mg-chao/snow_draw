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
| `add_arrow_point` | partial | Appends points only for currently creating arrow element. |
| `finish_create_element` | implemented | Ends create interaction. |
| `cancel_create_element` | implemented | Removes in-progress created element. |
| `delete_elements` | implemented | Deletes by IDs and updates selection/document version. |
| `duplicate_elements` | implemented | Deterministic IDs and z-order assignment. |
| `change_element_z_index` | implemented | Routed through multi-element z-index operation. |
| `change_elements_z_index` | implemented | Deterministic reordering and z-index normalization. |
| `update_elements_style` | partial | JSON style merge works; opaque/binary payloads pass through as compatibility fallback. |
| `update_global_elements` | implemented | Stores normalized global payload and drives overlay tasks. |
| `create_serial_number_text_elements` | partial | Creates companion text elements with simplified layout defaults. |
| `start_text_edit` | implemented | Opens/creates text edit session. |
| `update_text_edit` | implemented | Updates text payload and optional rect. |
| `refresh_auto_resize_text_layouts_after_font_load` | partial | Currently treated as no-op state refresh. |
| `finish_text_edit` | implemented | Commits or removes new-empty text as expected. |
| `cancel_text_edit` | implemented | Cancels text session and removes new draft text. |
| `start_edit` | partial | `move`/`resize`/`rotate` are implemented; non-core operation types resolve to unknown. |
| `update_edit` | partial | `move`/`resize`/`rotate` are implemented; only subset of modifier fields are applied. |
| `finish_edit` | implemented | Closes edit session. |
| `cancel_edit` | implemented | Reverts to session baseline rect/rotation. |
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
| `arrow_point_overlay` | partial | Emitted for single selected arrow/line elements with deterministic handle payloads; advanced loop/elbow parity remains deferred. |
| `arrow_binding_highlight` | partial | Emitted for selected arrow/line bindings; hover/edit-session driven highlight parity remains deferred. |
| `hover_outline` | missing | Not yet emitted by Rust frame planner. |
| `snap_guides` | missing | Not yet emitted by Rust frame planner. |

## V2 Host Request/Response Coverage

| V2 Path | Status | Notes |
| --- | --- | --- |
| `command_event -> snapshot/state_delta/frame_plan` | implemented | Core runtime flow for store dispatch. |
| `pointer_event -> host_request` | implemented | Forwarded as typed host request. |
| `keyboard_event -> host_request` | implemented | Forwarded as typed host request. |
| `tool_event -> host_request` | implemented | Forwarded as typed host request. |
| `text_metrics_request` generation | missing | Rust runtime currently consumes responses but does not originate requests yet. |
| `text_metrics_response` handling | partial | Response is acknowledged and logged; no downstream metrics-driven layout mutation yet. |
