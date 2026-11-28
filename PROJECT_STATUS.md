# CombatLab — Project Status

> Last updated: 2026-11-27 (debug cleanup)  
> Project: Godot 2D side-view action-combat prototype  
> Status source: current GitHub `main` plus user-confirmed test results. The HitInstance migration branch described below is not merged or locally tested yet.

## 1. Current focus

Complete and validate the HitInstance runtime migration. The Hit Editor is receiving a usability pass (Hitbox stacking order, per-Hitbox colors, visibility toggles, ActionData hierarchy, and canvas context menu) alongside HitInstance runtime validation, including Enemy-to-Player hit diagnosis and target-side damage numbers.

Current migration branch: `feature/hitinstance-runtime-migration` (pending PR review and Godot validation).

## 2. Latest implementation on the migration branch

The following changes have been prepared on the migration branch but have **not yet been tested in Godot**:

- `HitModule` is automatically created only when `CombatActionData.hit_module_enabled` is enabled; HitInstance presence alone no longer controls execution.
- The HitInstance array is hidden in the Inspector while disabled, but its data is preserved. Enabling HitModule creates one default HitInstance only when the array is empty.
- Collision Mask is configured once on `CombatActionData` and shared by every HitInstance in that Action. It appears only when the HitInstance array is non-empty; Player Actions target Enemy Layer 3 (Mask 4), Enemy Action 01 targets Player Layer 2 (Mask 2).
- Player1 and EnemyBase now have explicit collision layers/masks: Player Layer 2, Enemy Layer 3, both bodies mask World Layer 1.
- Hit Editor floating panel resizing is restricted to its right edge; tree row selection remains handled by the Tree control.
- Hitbox list rows and canvas Hitboxes both expose the same right-click layer menu (raise, lower, top, bottom); the underlying HitInstance Hitbox array order drives both draw order and click priority.
- The Hit Editor tree shows the ActionData title and HitInstance titles at the same indentation level; selecting the ActionData title inspects the complete `CombatActionData` resource.
- Hitboxes within each HitInstance receive related but slightly varied editor colors.
- HitInstance and individual Hitbox rows have independent eye-button visibility toggles; hidden Hitboxes are omitted from drawing and picking only, with no runtime collision setting changed.
- Damage debug numbers are now emitted by the hit target rather than the attacker, so incoming Enemy damage can appear over Player. Enemy targets also expose the same debug signal.
- Temporary HitModule contact/diagnostic prints and Overlay visibility prints have been removed after Enemy-to-Player damage feedback was restored. Damage debug numbers are emitted directly by `Player1.take_damage()` / `EnemyBase.take_damage()`.
- These new Hit Editor controls are committed but have not yet been run in Godot 4.7.2; local validation is still required.
- One runtime `Area2D` is created per HitInstance, with one `CollisionShape2D` per Hitbox.
- Hitboxes in one HitInstance share one target-hit record; different HitInstances have independent records.
- HitInstance windows are evaluated against the current update interval to avoid waiting an additional Executor update after crossing a configured time boundary.
- Hitbox X offsets and rotation are mirrored from the Action's captured facing direction.
- Collision masks belong to `CombatActionData` and are shared by all of its runtime HitInstance Areas; runtime Areas no longer depend on a scene-level `AttackArea`.
- `CombatDebugOverlay` reads runtime HitInstance data, draws actual runtime shapes, shows per-instance hit counts, and marks HitInstance windows under Active.
- Old `AttackArea` nodes were removed from Player1 and EnemyBase scenes.
- Existing action resources were cleaned of obsolete manual HitModule entries.
- The old HitstopModule settings were migrated to HitInstanceData where non-default values existed. The deprecated `HitstopModule` script was removed after checking its script references and all action resource references.

Important preserved behavior:
- `HitInstanceData` still owns Hitstop settings.
- Adjusting attacker freeze duration continues to add one frame to target freeze duration.
- `CombatTimeManager` remains the actual time-freeze executor.
- `HitManager` remains responsible for target interruption and super-armor comparison.
- MovementModule, Dash, and Stabilization were not changed by this migration.

## 3. Existing systems and verified progress


### Unified Action request path
All formal combat actions must enter through:

`CombatActionRequest` → `CombatComboExecutor.submit_request()`

This applies to Player attacks, skills, Enemy attacks, and Dash. Do not bypass this path by calling `CombatActionExecutor.start_action()` directly from a character or controller.

### Action facing lock
- Action facing is captured in `CombatActionContext`.
- Facing remains locked while an Action is running, including Dash.
- New Actions take over the lock when replacing an old Action.
- Player1 has a corresponding visual-facing update path.
- Enemy implementation exists; user has not explicitly confirmed its full validation.

### Player movement / Dash
- Dash is implemented as a normal `CombatActionData` submitted through a `CombatActionRequest`.
- Dash direction/facing snapshots survive delayed or buffered requests.
- New Dash input replaces older pending Dash input.
- Dash charges are only consumed after successful start.
- D-01 through D-07 lifecycle tests passed, including movement-source takeover and diagonal-down end-velocity protection.
- Dash Movement can outlive its Action phase; Action completion does not blindly clear an independently running Movement source.

### Stabilization
- S-01 through S-05 passed.
- S-06 is not passed: airborne stabilization while falling (`Vy < 0`) can fail to cancel gravity because the stabilization acceleration is lower than gravity. User chose to defer this issue.
- Vertical stabilization is currently enabled by default and is not exposed as an Inspector toggle.

### TimeFreeze
- `CombatTimeManager` owns Actor-local freeze records.
- One active freeze record per Actor; new requests refresh/replace rather than stack.
- `source_id` prevents an old source from cancelling a newer freeze.
- Input sampling remains available during TimeFreeze; execution/physics is time-controlled.
- Dash pre-freeze tests were broadly passing.
- Do not add a global frozen check to `start_action()`.

### Action-time ordinary movement restriction
User reports this system is now essentially complete. It is not part of the current HitInstance migration task and should not be treated as an active to-do.
- Ordinary directional movement does not run during an Action.
- Direction input is still sampled for subsequent Actions/Jump.
- Existing horizontal velocity is allowed to decay naturally.
- Action Movement velocity override remains authoritative.
- Crouch is suppressed during an Action.

### Defense and interruption
- `DefenseModule` supports invincibility and damage immunity with phase-range or duration activation.
- `DefenseController` manages defense sources.
- `HitManager` retains responsibility for target Action interruption, including Interrupt Level / Super Armor Level comparison.
- Preserve existing defense source IDs and time-slow-on-success behavior.
- Do not reintroduce the previously removed Dash-source query for Dash invulnerability.

## 4. Multi-hit architecture decisions

### Action phases
- Keep exactly three Action phases: `STARTUP`, `ACTIVE`, `RECOVERY`.
- Do not add a `GAP` Action phase.
- Existing Phase Range modules continue to use these three Action phases.
- HitInstance timing is a separate timeline relative to the beginning of the Action's Active phase.

### HitInstance
- One HitInstance represents one independent hit opportunity/event.
- Each instance has `start_time` and `end_time`, relative to Active start.
- Gaps between HitInstances are allowed while the Action remains in its Active phase.
- One HitInstance can own multiple Hitboxes; all its Hitboxes open/close together.
- Each instance has its own target-hit record: a target can be hit once per instance, even if multiple shapes overlap it.
- A later HitInstance may hit the same target again.
- No rehit interval is required for the current design.

### Runtime hitbox nodes
- Chosen runtime layout: one `Area2D` per HitInstance, with multiple `CollisionShape2D` children.
- HitInstanceData and HitboxData are Resources, not scene Nodes.
- Runtime Areas are created/configured by the runtime hit system.
- Whether they are direct Player1 children or placed under a container is intentionally undecided. Do not force a `HitboxContainer` into the implementation yet.

### Hitstop
- Hitstop configuration belongs on `HitInstanceData`:
  - `hitstop_enabled`
  - `attacker_time_freeze_duration`
  - `target_time_freeze_duration`
- `CombatTimeManager` remains the actual time-freeze executor.
- The old HitstopModule behavior includes a one-frame addition to target freeze duration when attacker duration is adjusted. Preserve this unless a deliberate, discussed change is made.
- Planned migration: `HitModule` requests hitstop; it does not replace `CombatTimeManager`.

### Hit resolution responsibilities
- Planned `HitModule` responsibilities:
  - Schedule HitInstances against Active-relative time.
  - Create/configure and enable/disable runtime hitbox Areas.
  - Deduplicate targets per HitInstance.
  - Coordinate damage/defense result and hit feedback.
  - Request hitstop through `CombatTimeManager`.
- `HitManager` remains responsible for target Action interruption.
- Debug damage numbers must remain supported.
- Do not move every responsibility into the data Resources; Resources store configuration only.

### Hitbox geometry
Initial shape support:
- Rectangle
- Circle
- Capsule

The exact fields and shape construction must be checked against the actual `hitbox_data.gd` and Godot API before implementation. A visual Hitbox editor is a future idea, not current scope.

## 5. MovementTrack direction

- `MovementTrack` is implemented as a new mode within `MovementModule`; it does not replace the module.
- Existing Dash, Velocity Override, Stabilization, Movement Request lifecycle, and Dash TimeFreeze responsibilities remain.
- Track uses X/Y Curves: normalized progress 0–1 on the horizontal axis and pixel displacement relative to Actor start position on the vertical axis.
- Duration is runtime seconds; Curve2D trajectories remain a possible later extension.
- Dash remains on its existing implementation.
- BLOCK keeps the normal Collision Mask. IGNORE_WORLD temporarily removes only Layer 2 and preserves Layer 1 plus all other mask bits; the original mask is restored when the Movement request ends.
- Collision layers are now Layer 1 Map Boundary, Layer 2 World Geometry, Layer 3 Player, and Layer 4 Enemy. Ground/platforms use Layer 2; the arena bottom and side boundary guards use Layer 1. Map colliders may belong to both layers.
- Project physics tick rate is set to 60 Hz. Runtime Action timing remains seconds; Hit Editor's timeline ruler and playhead use 60 Hz frames via CombatTimebase.
- Hit Editor now displays the full Action phase timeline, HitInstance windows, MovementTrack lane, and a frame-snapped playhead that previews Actor and Hitbox movement.

## 6. Immediate next steps

1. Review PR #2 and synchronize the local project when ready to test.
2. Open the project in Godot 4.7.2 and confirm there are no script parse errors, invalid resources, or warnings. Confirm Player and Enemy expose `movement_request_handler`; Enemy Action Movement requests remain accepted no-ops without changing AI locomotion.
3. Re-test Player attacks against Enemy and Enemy Action 01 against Player after the Layer 1–4 migration.
4. Test MovementTrack BLOCK against walls, platforms, and ground; test IGNORE_WORLD against Layer 2 and Layer 1 objects.
5. Confirm IGNORE_WORLD restores the exact original Collision Mask after normal completion, Action cancellation, replacement, and Jump interruption.
6. Test X/Y curves, positive/negative displacement, durations, and movement with gravity suppressed while the Track is active.
7. In Hit Editor, scrub by frame and confirm the Actor and Hitboxes follow the MovementTrack preview; verify selection and dragging still work at non-zero playhead positions.
8. Re-test HitInstance timing, per-instance deduplication, Hitstop, DebugOverlay, Hitbox layer ordering, Undo/Redo, and visibility toggles.
9. Only after these checks pass, mark the MovementTrack and editor updates complete.

## 7. Collaboration constraints

- Make small, explainable changes; avoid broad refactors.
- Use complete replacement scripts when edits span multiple scattered sections.
- GDScript indentation must use tabs.
- Script files, variables, and functions use lowercase `snake_case`; node names may use PascalCase (e.g. `Player1`).
- Avoid unused variables, speculative fields, and unnecessary abstraction.
- Do not guess current source code: use the latest files the user provides.
- Do not add art or generate images unless explicitly requested.


## 8. Shared Movement Request Interface (2026-11-27)

- Added the `CombatMovementInterface` request contract and shared Action end-reason enum.
- `MovementModule` now resolves `Actor.movement_request_handler` and no longer casts to `PlayerMovementController`.
- Player1 exposes its existing `PlayerMovementController` through `movement_request_handler`; player movement behavior is unchanged.
- EnemyBase exposes its existing `EnemyMovementController` through the same property. The enemy controller implements no-op request/lifecycle methods only; AI locomotion is unchanged and Action-driven enemy movement remains unimplemented.
- Godot runtime validation is still pending; this change has been statically reviewed only.


## 9. MovementTrack implementation status (2026-11-27)

- Runtime X/Y Curve sampling and MovementTrack velocity handoff are implemented in PlayerMovementController.
- BLOCK and IGNORE_WORLD are wired through MovementModule. IGNORE_WORLD removes only the Layer 2 mask bit and restores the captured mask on movement cleanup.
- Runtime debug shows the MovementTrack path, progress, displacement, collision strategy, and current mask.
- Hit Editor has the full Action timeline, HitInstance lanes, MovementTrack lane, frame-snapped playhead, and Actor/Hitbox trajectory preview.
- Collision layer assignments and Player/Enemy Action hit masks were shifted to preserve target detection.
- Godot 4.7.2 import, parse, editor, and runtime tests have not yet been run. Treat all runtime behavior as pending local verification.


## 10. User-confirmed completion update (2026-11-28)

The user explicitly reconfirmed that the following features are complete:
- Ordinary movement is blocked while an Action is active.
- Direction input is still sampled while an Action is active.
- Action-to-Jump transitions are complete.
- MovementTrack editor auto-save is complete.

These are completed items, not current to-dos. Preserve this status in future progress summaries.

MovementTrack collision behavior (BLOCK / IGNORE_WORLD and Collision Layer / Mask handling) has also been tested by the user and accepted as working. Do not reopen collision debugging unless the user reports a new regression.

Current narrow UI investigation:
- The remaining issue is the MovementTrack floating editor panel layout: SpinBox / OptionButton appear too wide, and the CurveGraph Control rectangle itself extends beyond the panel's right edge.
- The user's current local CurveGraph._ready() already has custom_minimum_size = Vector2(0.0, 150.0), so its former 270 px minimum width is not the cause.
- CurveGraph instances are created in _ready() and inserted through _make_graph_section():
  `x_graph = CurveGraph.new()`
  `content.add_child(_make_graph_section("Track_X", x_graph, true))`
  `y_graph = CurveGraph.new()`
  `content.add_child(_make_graph_section("Track_Y", y_graph, false))`
- The next layout investigation should inspect the full parent/child sizing chain around ScrollContainer, content VBoxContainer, _make_graph_section(), and the panel's resize logic. Avoid broad searches for SIZE_EXPAND_FILL; inspect the specific hierarchy.


## 11. Death movement update (2026-11-28)

Implemented on the GPT branch; Godot runtime validation is pending.

- Added shared `DeathMovementController` for Player1 and EnemyBase.
- Ground Death and Air Death are unified as `Non-Knockback Death`; no separate ground/air mode is used.
- Lethal HitModule damage now passes the incoming horizontal attack direction to the target.
- With an incoming attack direction, Non-Knockback Death sets X velocity to exactly 500 toward the attack direction. With no usable source direction, it preserves the death-time X velocity.
- Horizontal velocity gradually decelerates while gravity remains active.
- Airborne deaths bounce once on first landing, using pre-impact vertical speed multiplied by the configured bounce ratio. Grounded deaths do not bounce.
- Death collision masks include Layers 1 and 2.
- Player death movement state is shown in CombatDebugOverlay; EnemyBase exposes the same controller debug data.
- Knockback Death is not implemented. Add it after KnockbackModule exists, including whole-vector minimum-speed protection and one landing bounce.
- No death animation has been added yet.
