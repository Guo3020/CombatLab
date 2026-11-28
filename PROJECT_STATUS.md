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

## 3. SkillSystem implementation

The separate `CombatEnergy` and `SkillSelector` nodes have been consolidated into one `SkillSystem` on the GPT branch. Local Godot validation is still pending.

- `SkillSystem` owns both Energy (0–100) and Decibel (0–3000).
- It selects the normal skill or enhanced special skill using the existing first-Action energy check.
- Energy is still consumed per Action segment through the existing Action execution route.
- `CombatActionExecutor` asks SkillSystem to consume the resource cost recorded by `CombatActionData`.
- The resource check is atomic when an Action has both Energy and Decibel costs.
- `CombatActionData.energy_cost` remains Inspector-editable.
- `CombatActionData.decibel_cost` is hidden from the Inspector and defaults to 1000 for Actions whose `action_type` is `ultimate`; other Action types do not consume Decibel.
- SkillSystem exposes `add_decibel()`, but Decibel gain rules have not yet been designed.
- The Ultimate request submits a normal `START_ACTION` request using a `CombatActionData`. SkillSystem has an `ultimate_action_data` slot, which is not assigned to a concrete Ultimate Action yet.
- An unbound `ultimate` Input Map action has been added. The user assigns its key in Project Settings; there is no runtime key-creation prompt.
- CombatDebugOverlay now displays both Energy and Decibel.

Preserved behavior:
- The same Skill input selects normal skill when the enhanced special skill's first Action cost cannot be paid, and selects enhanced special skill when it can.
- Energy costs remain per Action segment.
- If Energy becomes insufficient partway through an enhanced special combo, that combo stops at the unaffordable Action. Already-consumed Energy is not refunded, and the system does not switch to normal skill mid-combo.

## 4. Next tasks

### 4.1 SkillSystem / Ultimate validation

- [ ] Open the project in Godot and confirm there are no parse errors, missing script references, or invalid resources after replacing the two old nodes with SkillSystem.
- [ ] Verify normal skill and enhanced special selection, including insufficient Energy partway through a combo.
- [ ] Assign an Ultimate `CombatActionData` to SkillSystem's `ultimate_action_data` slot.
- [ ] Set that Action's `action_type` to `ultimate`; its hidden Decibel cost defaults to 1000 and is not Inspector-editable.
- [ ] Bind the `ultimate` Input Map action to a key in Project Settings.
- [ ] Test rejection below 1000 Decibel, successful activation at 1000 or more, and exact 1000 Decibel deduction.
- [ ] Confirm the Decibel debug bar updates when `add_decibel()` is called.

Decibel gain rules and any additional Ultimate availability conditions remain undecided. Do not invent them during implementation.

### 4.2 Deferred combat feature

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
