# CombatLab — Architecture

> Last updated: 2026-11-27  
> This document records the currently agreed architecture and important constraints. It is a design reference, not a claim that every planned component is already implemented.

## 1. Project intent

CombatLab is a Godot 2D side-view action-combat prototype focused on combat feel, action timing, hit feedback, movement behavior, and debugging before production art.

Reference direction: *Zenless Zone Zero* and *Katana ZERO*. The game is a simple side-view platform/action layout, not a multi-lane beat-'em-up.

## 2. Core architecture principles

1. **One formal Action request path.** Characters and controllers submit `CombatActionRequest` to `CombatComboExecutor`; they do not directly start Actions through the low-level executor.
2. **Data describes; runtime systems execute.** Resource data stores configuration. Modules, executors, controllers, and managers perform behavior.
3. **Action phase and sub-event timelines are distinct.** Startup/Active/Recovery remain the Action phases; HitInstances are timed events inside Active.
4. **Ownership and lifecycle must be explicit.** Movement sources, defense sources, and time-freeze sources use source identity so stale cleanup cannot cancel newer state.
5. **Debug support is part of feature work.** New combat features should expose useful state through `CombatDebugOverlay`.
6. **Prefer incremental migration.** Keep old behavior available until new behavior is tested against it.

## 3. High-level runtime flow

```text
Input / AI
    |
    v
CombatActionRequest
    |
    v
CombatComboExecutor.submit_request()
    |
    +--> combo routing / pending request handling
    |
    v
CombatActionExecutor
    |
    +--> CombatActionContext
    |
    +--> Action phases: Startup -> Active -> Recovery
    |
    +--> CombatActionModules
             |
             +--> HitModule (automatically created only when hit_module_enabled is true)
             +--> MovementModule
             +--> DefenseModule
```

Supporting systems:
- `CombatTimeManager`: Actor-local and global time scaling/freezing.
- `HitManager`: target Action interruption and interrupt/super-armor comparison.
- `DefenseController`: defense source aggregation/state.
- `CombatDebugOverlay`: central combat timeline and debug visualization.

## 4. Action request contract

`CombatActionRequest` is the unified request object. Its current conceptual fields include:
- `request_type`
- `combo_data`
- `action_data`
- `facing_direction`
- `input_direction`
- `actor_state_captured`

Request types:
- `CONTINUE_COMBO`
- `START_COMBO`
- `START_ACTION`

`facing_direction = 0` means unspecified; the request submission path captures the Actor's current facing. `actor_state_captured` prevents a delayed/cached request from overwriting its original direction snapshot.

`CombatComboExecutor.submit_request(request)` is the public entry point. Dash also uses this route.

## 5. Action lifecycle and context

`CombatActionExecutor` manages the current Action and its phase progression. `CombatActionContext` carries the runtime state and captured Actor state for that Action.

Action phases remain:
1. `STARTUP`
2. `ACTIVE`
3. `RECOVERY`

Action facing is locked for the duration of a running Action. The Action Context stores the facing snapshot; visual facing changes are handled by the character, not by a generic executor reaching into visual nodes.

Modules that use phase ranges must continue to refer to these three Action phases. They must not reinterpret HitInstance indices or HitInstance time as Action phase values.

## 6. Multi-hit design

### 6.1 Data model

`CombatActionData` owns an explicit `hit_module_enabled` toggle, a shared `collision_mask`, and an exported HitInstance array.

- `hit_module_enabled` is the only switch that controls whether HitModule runs.
- `hit_instances` is shown in the Inspector only while the toggle is enabled.
- `collision_mask` is configured once per Action and shared by every HitInstance. It is shown only while the HitInstance array contains at least one entry.
- Disabling HitModule hides the array but preserves all configured HitInstance data.
- Re-enabling it restores the previous data. If the array is empty, one default HitInstance is created automatically.
- The Executor must not infer enablement from whether the array happens to contain data.

`HitInstanceData` is a Resource representing one hit opportunity. Its agreed conceptual data:
- `start_time`
- `end_time`
- `damage`
- `hitboxes: Array[HitboxData]`
- `hitstop_enabled`
- `attacker_time_freeze_duration`
- `target_time_freeze_duration`

Do not add speculative knockback fields until the old project code or an explicit design decision provides the actual required schema.

`HitboxData` is a Resource describing one collision shape and its local transform/geometry. Initial geometry types:
- Rectangle
- Circle
- Capsule

Exact property names/types must follow the actual script and Godot's supported Shape2D APIs.

### 6.2 Timeline semantics

- HitInstance times are measured from the beginning of the Action's Active phase.
- `start_time` and `end_time` define when the instance's hitboxes are enabled.
- `HitModule` evaluates the overlap between the current Executor update interval and the HitInstance interval. This avoids waiting for an additional update after a time boundary is crossed. Actual Area2D overlap events remain quantized by Godot's physics ticks.
- Multiple instances may have gaps between them.
- The Action remains in the single Active phase across those gaps.
- A HitInstance's multiple Hitboxes are enabled/disabled as one group.

### 6.3 Runtime collision structure

Implemented runtime structure:

```text
Actor
  ...
  Area2D (runtime HitInstance A)
    CollisionShape2D
    CollisionShape2D
  Area2D (runtime HitInstance B)
    CollisionShape2D
```

This is conceptual; do not create a fixed scene hierarchy prematurely. The runtime Areas may be direct Actor children or later be organized under a container.

Collision layer convention:
- Layer 1: World
- Layer 2: Player
- Layer 3: Enemy
- Player CharacterBody2D: Layer 2, Mask 1 (World)
- Enemy CharacterBody2D: Layer 3, Mask 1 (World)
- Player CombatActionData: Mask 4 (Enemy Layer 3)
- Enemy CombatActionData: Mask 2 (Player Layer 2)
- All HitInstance Areas created by the same Action use that ActionData's shared mask.

For each HitInstance:
- Keep an independent set of targets already hit.
- Multiple shapes touching the same target must resolve only once for that instance.
- A later instance has a fresh hit record and may hit that same target again.

`HitInstanceData` and `HitboxData` are Resources, never runtime collision Nodes.

## 7. HitModule and hit resolution

`HitModule` is automatically created by `CombatActionExecutor` only when `CombatActionData.hit_module_enabled` is true. The presence of HitInstance data alone does not enable it. It is responsible for:
- Managing HitInstance schedules during Active.
- Building/configuring runtime Area2D and CollisionShape2D nodes.
- Enabling/disabling all hitboxes for each instance.
- Deduplicating targets per instance.
- Coordinating damage and defense result handling.
- Requesting hitstop from `CombatTimeManager`.
- Preserving debug damage number support.

Data Resources must not execute collision logic or manipulate time.

`HitManager` retains its dedicated target-interruption responsibility:
- Compare incoming interrupt level with target super armor level.
- Cancel/interfere with target Action/Combo as appropriate.
- Emit the target interruption signal.

Do not collapse `HitManager` into `HitModule`.

## 8. Hitstop and time management

`CombatTimeManager` remains the single authority for time-freeze execution.

Hitstop configuration belongs to `HitInstanceData`, and `HitModule` submits attacker and target freeze requests to `CombatTimeManager`. The existing behavior that adds one frame (`1/60` second) to target duration when attacker duration is adjusted is preserved. The deprecated `HitstopModule` is removed after its action-resource references are migrated.

TimeFreeze source identity is important:
- One active freeze record per Actor.
- A new request refreshes/replaces the existing record rather than stacking.
- A source ID prevents cleanup from an old Action from cancelling a newer source.
- Input collection is not stopped by Actor-local TimeFreeze; time-controlled execution/physics is.

Do not add a blanket frozen check to `CombatActionExecutor.start_action()`.

## 9. Movement architecture

`PlayerMovementController` is the single authority for Player1 movement, jump, gravity, Dash, Stabilization, crouch/duck behavior, and future movement tracks. Player1 calls `move_and_slide()`.

`MovementModule` remains responsible for Action-driven movement configuration and lifecycle:
- `DASH`
- `VELOCITY_OVERRIDE`
- Stabilization
- Movement source/request lifecycle
- Dash-related TimeFreeze
- Planned `TRACK` mode

`MovementTrack` is an addition to `MovementModule`, not a replacement. Start with X/Y curves relative to the Actor's starting position. More complex Curve2D paths can be added later.

Dash remains on its current dedicated behavior; do not migrate Dash to MovementTrack.

Collision policies planned for Track:
- `BLOCK`: normal world collision.
- `IGNORE_WORLD`: ignore ordinary map obstacles, but preserve boundary/fall protection. Exact wall/platform behavior should be configurable rather than assuming all collisions are ignored.

## 10. Defense and interruption

`DefenseModule` configures defense such as:
- `INVINCIBLE`
- `DAMAGE_IMMUNE`

It supports phase-range or duration activation. `DefenseController` aggregates active defense sources, including manually controlled states.

Preserve source IDs and existing `trigger_time_slow_on_success` behavior. Do not restore a removed Dash-specific invulnerability source query.

## 11. Debug architecture

`CombatDebugOverlay` is the central place for combat debugging. New features should integrate with it rather than adding scattered debug drawing.

The HitInstance migration provides runtime debug data through the Action Context:
- Active HitInstance count and total count.
- Per-instance active state and hit-target count.
- References to the runtime Area2D nodes, allowing the overlay to draw their actual CollisionShape2D geometry.
- HitInstance time windows displayed beneath the Action Active timeline.

The overlay should query the existing Executor debug interface rather than hard-coding assumptions about legacy scene nodes.

## 12. Future editor direction (not current implementation scope)

Future Action Preview may build on Godot's `AnimationPlayer` and extend it with combat-specific tracks:
- Hitbox Track / HitInstance events
- Movement Track
- Hurtbox Profile Track
- Action phase and hit-event display

AnimationPlayer remains responsible for animation keyframes. CombatLab adds combat timeline information; it should not recreate a full animation editor.

Character animation is expected to be in-place while programmatic systems control world position. This keeps animation and movement trajectory independently inspectable.

The visual Hit Editor now exists and is considered sufficient for the current workflow. Do not expand it while the HitInstance runtime migration is the active priority.

## 13. Naming and code conventions

- Script files, variables, and functions: lowercase `snake_case`.
- Node names: PascalCase is acceptable (e.g. `Player1`).
- GDScript indentation: tabs.
- Avoid unused fields, speculative APIs, and redundant modules.
- Prefer clear ownership and small steps over abstraction for its own sake.
