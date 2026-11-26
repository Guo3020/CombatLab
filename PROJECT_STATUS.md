# CombatLab — Project Status

> Last updated: 2026-11-26  
> Project: Godot 2D side-view action-combat prototype  
> Status source: project snapshot `20261125_combatlab.zip` plus changes explicitly confirmed by the user in the current conversation.  
> Important: the snapshot predates some recent edits. Treat the user's latest confirmations as authoritative where they differ.

## 1. Current focus

Implement multi-hit Active windows using `HitInstanceData`, then migrate hit detection and hitstop execution into a unified `HitModule`.

The intended implementation order is incremental:
1. Add data Resources (`HitboxData`, `HitInstanceData`).
2. Add the HitInstance list to `CombatActionData`.
3. Make the action system automatically provide hit capability when HitInstances are configured.
4. Implement `HitModule` scheduling, runtime hitboxes, per-instance target deduplication, hit resolution, and hitstop requests.
5. Migrate old `.tres` action resources and remove old modules only after compatibility is verified.

## 2. Latest confirmed changes

- User has replaced/added the two data scripts:
  - `03_scripts/01_combat/data/hitbox_data.gd`
  - `03_scripts/01_combat/data/hit_instance_data.gd`
- User has added this export to `CombatActionData`:
  ```gdscript
  @export var hit_instances: Array[HitInstanceData] = []
  ```
- These edits have not yet been confirmed as successfully imported/parsed by the Godot editor. Verify before proceeding.
- No existing `HitboxModule` or `HitstopModule` has been removed.
- No Action execution, Player1 scene tree, or MovementModule changes have been made as part of this migration yet.

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
User accepted the current implementation temporarily:
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

1. Ask the user to confirm whether Godot imports the two new Resources and the `CombatActionData` export without parse errors.
2. Inspect the current versions of `hitbox_data.gd`, `hit_instance_data.gd`, and `combat_action_data.gd` if any mismatch or error appears.
3. Review the current `CombatActionExecutor` lifecycle before wiring HitModule callbacks.
4. Implement automatic HitModule availability for Actions with configured HitInstances.
5. Only then implement runtime Area2D creation and HitInstance timing.
6. Migrate old `.tres` resources and compare behavior before deleting legacy modules.

## 7. Collaboration constraints

- Make small, explainable changes; avoid broad refactors.
- Use complete replacement scripts when edits span multiple scattered sections.
- GDScript indentation must use tabs.
- Script files, variables, and functions use lowercase `snake_case`; node names may use PascalCase (e.g. `Player1`).
- Avoid unused variables, speculative fields, and unnecessary abstraction.
- Do not guess current source code: use the latest files the user provides.
- Do not add art or generate images unless explicitly requested.
