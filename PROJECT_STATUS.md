# CombatLab — Project Status

> Last updated: 2026-11-28  
> Project: Godot 2D side-view action-combat prototype  
> Status source: GPT branch implementation plus explicitly user-confirmed local test results. Do not treat unverified code as runtime-tested.

## 1. Current development direction

The next major task is to build a unified **SkillSystem**. The existing `CombatEnergy` and `SkillSelector` responsibilities are currently separate; the agreed direction is to bring energy/resource management and skill selection under one SkillSystem for easier management.

After the SkillSystem is established, the Decibel / Ultimate system should reuse it rather than introducing a parallel skill execution path.

All formal Actions must continue to use the existing request route:

`CombatActionRequest` → `CombatComboExecutor.submit_request()` → `CombatActionExecutor`

## 2. Verified completed features

### Player movement and Action interaction

- Ordinary directional movement is blocked while an Action is running.
- Direction input continues to be sampled during an Action for subsequent Actions and Jump.
- Action-to-Jump transitions are complete.
- Action facing remains locked while an Action is running.
- Dash uses `CombatActionData` and the unified Action request path.
- Dash charges are consumed only after a Dash successfully starts.
- Dash lifecycle tests D-01 through D-07 passed.
- Stabilization tests S-01 through S-06 passed. S-06 (starting Stabilization in the air while falling) was tested and confirmed normal.
- MovementTrack editor auto-save is complete.
- MovementTrack BLOCK / IGNORE_WORLD collision behavior has been tested and accepted:
  - BLOCK retains normal collision behavior.
  - IGNORE_WORLD removes only Collision Mask Layer 2.
  - Layer 1 remains collidable, including colliders that belong to both Layers 1 and 2.
  - The original Collision Mask is restored when the Movement request ends.

### Death movement

The shared Non-Knockback Death implementation has been tested locally by the user and passed for Player1 and EnemyBase.

- Player1 and EnemyBase use the shared `DeathMovementController`.
- Ground and airborne deaths use one Non-Knockback mode.
- A lethal hit supplies its horizontal direction from the Action Context's captured facing direction.
- With a usable incoming direction, horizontal death speed is exactly 500 in that direction.
- Without a usable source direction, death-time horizontal velocity is preserved.
- Horizontal velocity decelerates while gravity remains active.
- An airborne death bounces once on its first landing, using pre-impact vertical speed multiplied by the configured bounce ratio. A grounded death does not bounce.
- Death collision retains Layers 1 and 2.
- Death movement debug data is available for Player and Enemy.

**Note:** Knockback Death is not implemented. It is deferred until `KnockbackModule` exists.

### Combat architecture and editor

- Formal combat Actions use the unified `CombatActionRequest` route.
- Action phases remain Startup → Active → Recovery.
- HitInstance timing is relative to the beginning of Active.
- One HitInstance can own multiple Hitboxes and maintains its own target-hit record.
- Hitstop configuration belongs to HitInstanceData; `CombatTimeManager` remains the time-freeze executor.
- `CombatDebugOverlay` is the central combat-debug interface.
- MovementTrack is implemented within `MovementModule`, not as a replacement for it.
- The Hit Editor includes the Action timeline, HitInstance lanes, MovementTrack lane, frame-snapped playhead, and Actor / Hitbox trajectory preview.

These bullets describe the implemented architecture; they do not imply that every editor interaction or runtime edge case has been independently re-tested in the latest local project.

## 3. Existing Skill baseline

The current implementation still has separate nodes/scripts:

- `CombatEnergy`: manages the existing 0–100 energy resource.
- `SkillSelector`: chooses the normal skill or enhanced special skill, then submits a combo request.
- `CombatActionData.energy_cost`: stores the energy cost for an individual Action.

Previously confirmed skill behavior to preserve during the refactor:

- The same Skill input selects the normal skill when energy is insufficient and the enhanced special skill when sufficient.
- Energy costs are paid per Action segment, not as one up-front combo payment.
- If energy becomes insufficient partway through an enhanced special combo, the combo may stop at that point.
- Already-consumed energy is not refunded, and the system does not switch to the normal skill mid-combo.

The new SkillSystem should consolidate resource management and skill selection while keeping Action execution in the existing Executor / ComboExecutor architecture.

## 4. Next tasks

### 4.1 Unified SkillSystem

- [ ] Replace the separate `CombatEnergy` + `SkillSelector` ownership model with one SkillSystem.
- [ ] Preserve the existing 0–100 energy behavior and normal / enhanced-special selection rules.
- [ ] Preserve per-Action energy consumption and the confirmed insufficient-energy combo behavior.
- [ ] Keep skill input configurable through Godot's Input Map; do not hardcode a physical key.

### 4.2 Decibel / Ultimate system

Planned to reuse the SkillSystem:

- [ ] Decibel resource range: 0–3000.
- [ ] Ultimate is a normal `CombatActionData` Action and uses the unified Action request path.
- [ ] Default Ultimate cost: 1000 Decibel.
- [ ] The default cost is internal behavior and must not appear as an editable Inspector property.
- [ ] The Ultimate input must be a normal configurable Godot Input Map action. The user will assign the key, just as with ordinary controls.
- [ ] Do not show runtime prompts saying that an input action was created or asking the user to create one.

Still undecided: how Decibel is gained, whether there are any special gain rules, and any additional Ultimate-specific availability conditions. Do not invent these rules during implementation.

### 4.3 Deferred combat feature

- [ ] Knockback Death, after `KnockbackModule` is implemented. It should use the future KnockbackModule vector, preserve vector direction when enforcing a minimum whole-vector speed, and support one landing bounce.

## 5. Explicitly removed / not planned

- Heavy / charged attack interactions that continue or alter an attack through Dodge are cancelled and are no longer a CombatLab task.
- Ground reverse-deceleration as a separate parameter is not an agreed requirement and must not be reintroduced as a pending task.
- Stabilization S-06 is complete; do not list it as pending.

## 6. Collaboration and implementation constraints

- Make small, explainable changes; avoid broad refactors.
- GDScript indentation must use tabs.
- Script files, variables, and functions use lowercase `snake_case`; node names may use PascalCase.
- Avoid unused variables, speculative fields, and unnecessary abstraction.
- New combat features must include `CombatDebugOverlay` support from the start.
- Do not add art or generate images unless explicitly requested.
- The user's `本地修改分支` is read-only for assistant changes. Assistant code/document changes belong only on the `GPT` branch.
- Do not claim local runtime validation unless the user confirms it.
