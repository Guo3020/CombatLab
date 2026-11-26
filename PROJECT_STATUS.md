# CombatLab — Project Status

> Last updated: 2026-11-26  
> Project: Godot 2D side-view action-combat prototype  
> Status source: current GitHub `main` plus user-confirmed test results. The HitInstance migration branch described below is not merged or locally tested yet.

## 1. Current focus

Complete and validate the HitInstance runtime migration. The visual Hit Editor is now considered sufficient for the current workflow; editor expansion is not the active priority.

Current migration branch: `feature/hitinstance-runtime-migration` (pending PR review and Godot validation).

## 2. Latest implementation on the migration branch

The following changes have been prepared on the migration branch but have **not yet been tested in Godot**:

- `HitModule` is automatically created by `CombatActionExecutor` when an Action has HitInstances.
- One runtime `Area2D` is created per HitInstance, with one `CollisionShape2D` per Hitbox.
- Hitboxes in one HitInstance share one target-hit record; different HitInstances have independent records.
- HitInstance windows are evaluated against the current update interval to avoid waiting an additional Executor update after crossing a configured time boundary.
- Hitbox X offsets and rotation are mirrored from the Action's captured facing direction.
- Collision masks now belong to `HitInstanceData`; runtime Areas no longer depend on a scene-level `AttackArea`.
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

- `MovementTrack` is planned as a new mode/capability within `MovementModule`, not a replacement for it.
- Existing Dash, velocity override, stabilization, Movement Request lifecycle, and Dash TimeFreeze responsibilities remain.
- Initial Track implementation should focus on X/Y curves relative to the starting position.
- Complex `Curve2D` trajectories can come later.
- Dash remains on its existing implementation.
- Collision policy should distinguish blocking world collision from a configurable ignore-world mode, while retaining map-boundary/fall protection.

## 6. Immediate next steps

1. Review the migration PR and synchronize the local project when ready to test.
2. Open the project in Godot 4.7.2 and confirm there are no script parse errors, missing resources, or invalid `.tres` references.
3. Verify left/right Hitbox mirroring for rectangle, circle, and capsule shapes.
4. Verify HitInstance start/end timing, including boundaries that fall between frame timestamps.
5. Verify per-instance target deduplication, later-instance re-hits, Hitstop, and Action cancellation cleanup.
6. Verify the DebugOverlay displays actual runtime Hitboxes and HitInstance timing for both Player and Enemy.
7. Only after these checks pass, mark the migration complete and continue to the next combat-system feature.

## 7. Collaboration constraints

- Make small, explainable changes; avoid broad refactors.
- Use complete replacement scripts when edits span multiple scattered sections.
- GDScript indentation must use tabs.
- Script files, variables, and functions use lowercase `snake_case`; node names may use PascalCase (e.g. `Player1`).
- Avoid unused variables, speculative fields, and unnecessary abstraction.
- Do not guess current source code: use the latest files the user provides.
- Do not add art or generate images unless explicitly requested.
