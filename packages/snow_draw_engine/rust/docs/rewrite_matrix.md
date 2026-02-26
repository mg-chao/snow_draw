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
| `create_element` | partial | Creation works with deterministic anchor capture and runtime style defaults (payload + opacity) from config events; runtime grid + object snapping honor `snap_override` plus runtime point/gap toggles (`enablePointSnaps` / `enableGapSnaps`), including center/side gap snapping with frequency-aware candidate ranking, while full Dart tie-break and associated-guide parity remains deferred. |
| `update_creating_element` | partial | Resizing preview supports `create_from_center`; runtime grid + object snapping honor `snap_override` plus runtime point/gap toggles (`enablePointSnaps` / `enableGapSnaps`), including center/side gap snapping with frequency-aware candidate ranking, while full Dart tie-break and associated-guide parity remains deferred. |
| `add_arrow_point` | partial | Appends points for currently creating arrow/line elements and re-normalizes payload points against updated rect bounds; runtime grid + object snapping honor `snap_override` plus runtime point/gap toggles (`enablePointSnaps` / `enableGapSnaps`), including center/side gap snapping with frequency-aware candidate ranking, while full Dart tie-break and associated-guide parity remains deferred. |
| `finish_create_element` | implemented | Ends create interaction. |
| `cancel_create_element` | implemented | Removes in-progress created element. |
| `delete_elements` | implemented | Deletes by IDs and updates selection/document version. |
| `duplicate_elements` | implemented | Deterministic IDs and z-order assignment. |
| `change_element_z_index` | implemented | Routed through multi-element z-index operation. |
| `change_elements_z_index` | implemented | Deterministic reordering and z-index normalization. |
| `update_elements_style` | partial | JSON style merge works; opaque/binary payloads pass through as compatibility fallback. |
| `update_global_elements` | implemented | Stores normalized global payload and drives overlay tasks. |
| `create_serial_number_text_elements` | partial | Creates/reuses companion text elements, updates `serial_number.textElementId`, focuses single-target text edit, and applies runtime text style defaults from config events; advanced text-metrics parity remains deferred. |
| `start_text_edit` | implemented | Opens/creates text edit session and applies runtime text style defaults for newly created text drafts. |
| `update_text_edit` | implemented | Updates text payload and optional rect. |
| `refresh_auto_resize_text_layouts_after_font_load` | implemented | V2 runtime emits text-metrics host requests for auto-resize text elements and applies response-driven layout updates; direct v1 flow now recomputes deterministic fallback auto-resize text bounds. |
| `finish_text_edit` | implemented | Commits or removes new-empty text as expected. |
| `cancel_text_edit` | implemented | Cancels text session and removes new draft text. |
| `start_edit` | partial | `move`/`resize`/`rotate` are implemented; `arrow_point` sessions are now recognized, while advanced/non-core edit types remain reduced. |
| `update_edit` | partial | `move`/`resize`/`rotate` are implemented; `arrow_point` turning/addable updates are applied with rect+point normalization and endpoint binding cleanup; runtime grid + object snapping for move/resize/arrow-point follow Dart parity (including center-resize snap suppression), honor `snap_override`, and respect runtime point/gap toggles (including center/side gap move snapping with frequency-aware candidate ranking), while advanced elbow/curve edit parity remains deferred. |
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
| `arrow_point_overlay` | implemented | Emitted for single selected arrow/line elements with deterministic handle payloads, mixed normalized/world payload compatibility, plus loop/elbow handle semantics (including elbow fixed-segment flags) and curved-segment midpoint fidelity. |
| `arrow_binding_highlight` | partial | Emitted for selected arrow/line bindings plus hover-driven `hoveredBindingElementId` payloads (suppressed when `hoveredArrowHandle` is present); full pointer-driven/edit-session parity remains deferred. |
| `hover_outline` | partial | Emitted when `global_elements_payload.hoverOutline` (or `hoveredElementId`) is present with a valid non-selected target; pointer-driven hover parity remains deferred. |
| `snap_guides` | partial | Emitted from `global_elements_payload.snapGuides` and from runtime snapping during create/edit sessions (grid + object point guides plus runtime center/side-gap guides); full Dart associated multi-guide gap parity remains deferred. |

## V2 Host Request/Response Coverage

| V2 Path | Status | Notes |
| --- | --- | --- |
| `command_event -> snapshot/state_delta/frame_plan` | implemented | Core runtime flow for store dispatch. |
| `config_event -> runtime config` | implemented | Locale/scale updates plus typed runtime config payload application (e.g. grid/object snap toggles and per-element runtime style defaults); supports optional snapshot bootstrap via `__bootstrapSnapshotV1ProtoBase64` for Rust runtime hydration from host-provided initial state. |
| `pointer_event -> host_request` | implemented | Forwarded as typed host request. |
| `keyboard_event -> host_request` | implemented | Forwarded as typed host request. |
| `tool_event -> host_request` | implemented | Forwarded as typed host request. |
| `text_metrics_request` generation | implemented | Runtime emits typed text-metrics host requests for `start_text_edit`, `update_text_edit`, and font-load refresh flows using unbounded width for auto-resize text. |
| `text_metrics_response` handling | implemented | Successful responses update auto-resize text layout bounds (line-height-aware width padding + stale-request guards) and emit snapshot/state/frame outputs. |
| `snapshot element payload fidelity` | implemented | V2 snapshots preserve canonical raw JSON element payloads for all known element types, avoiding style/binding truncation from narrower typed payload variants. |
