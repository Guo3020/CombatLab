# CombatLab — Architecture

> Last updated: 2026-11-26  
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
             +--> HitModule (planned)
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

`CombatActionData` owns an exported array:

```gdscript
@export var hit_instances: Array[HitInstanceData] = []
```

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
- Multiple instances may have gaps between them.
- The Action remains in the single Active phase across those gaps.
- A HitInstance's multiple Hitboxes are enabled/disabled as one group.

### 6.3 Runtime collision structure

Chosen structure:

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

For each HitInstance:
- Keep an independent set of targets already hit.
- Multiple shapes touching the same target must resolve only once for that instance.
- A later instance has a fresh hit record and may hit that same target again.

`HitInstanceData` and `HitboxData` are Resources, never runtime collision Nodes.

## 7. HitModule and hit resolution

Planned `HitModule` is a `CombatActionModule` Resource responsible for:
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

The old `HitstopModule` submits attacker and target freeze requests. Existing behavior automatically adds one frame (`1/60` second) to the target duration when the attacker duration is adjusted. The migration to `HitModule` should preserve this behavior unless explicitly changed after discussion.

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

Desired/ongoing debug information includes:
- Startup / Active / Recovery timeline and current phase.
- HitInstance active windows.
- Hitbox visualization and ranges.
- Damage numbers.
- Movement and velocity state where useful.

The overlay should query the existing Actor debug interface rather than hard-coding assumptions about unrelated nodes.

## 12. Future editor direction (not current implementation scope)

Future Action Preview may build on Godot's `AnimationPlayer` and extend it with combat-specific tracks:
- Hitbox Track / HitInstance events
- Movement Track
- Hurtbox Profile Track
- Action phase and hit-event display

AnimationPlayer remains responsible for animation keyframes. CombatLab adds combat timeline information; it should not recreate a full animation editor.

Character animation is expected to be in-place while programmatic systems control world position. This keeps animation and movement trajectory independently inspectable.

Do not start an EditorPlugin or visual Hitbox editor as part of the current migration.

## 13. Naming and code conventions

- Script files, variables, and functions: lowercase `snake_case`.
- Node names: PascalCase is acceptable (e.g. `Player1`).
- GDScript indentation: tabs.
- Avoid unused fields, speculative APIs, and redundant modules.
- Prefer clear ownership and small steps over abstraction for its own sake.
