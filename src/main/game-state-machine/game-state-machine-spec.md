# Game State Machine Spec (draft v0.5)

> In this spec, "state" and "game state" mean the same thing. Everywhere else (code, comments, other docs) always say "game state".

## Context
- Purpose: top-level game architecture. One state machine drives what the game is doing each frame. Game states can have substates, each level driven by its own machine.

## States
1. **States are a tagged union** (`union(enum)`). Each variant is its own struct type holding that state's data. Each struct is named `<Name>GameState` (e.g. `MenuGameState`), and its variant in the union is the lowercase name (e.g. `.menu`). The top-level union is `GameState`; substate unions follow the same rules (see Substates).
2. **Every state struct must declare all three hooks**, even if empty:
   - `fn enter(self: *XGameState) void`
   - `fn tick(self: *XGameState) void`
   - `fn exit(self: *XGameState) void`
3. **Hooks take no parameters** other than `self`, and **return `void`**. A state handles its own errors.
4. States may own resources such as memory and GL objects. They acquire them in `enter` and release them in `exit`.
5. **Every state struct must be constructible as `.{}`**: every field has a default value. Defaults must be real values, not `undefined`. This lets the module build any state from its name (see the command-line override). Code that requests a transition may still pass non-default values.
6. **The machine dispatches hooks to the active variant with `inline else`**: `inline else => |*s| s.tick()` (and likewise for `enter` and `exit`). Plain `else => |*s|` is **forbidden** here: without `inline` it captures the whole union instead of the active variant's struct.

## Machine
7. **Generic machine, game-specific use.** The machine logic is written once as `fn Machine(comptime S: type) type`, where `S` is a state union. The game uses `pub const GameStateMachine = Machine(GameState);`. Substate machines use the same `Machine` with their own union (see Substates).
8. **No hidden global inside the module.** A machine is a struct value that owns `current: ?S`. `null` means the machine is **empty** (no active state).
9. **Public API:**
   - `init(initial: ?S)` and `deinit()`: see Startup and shutdown.
   - `tick()`: calls `tick` on the current state (if any), then applies a pending request if there is one.
   - `requestTransition(next: S)`: stores a pending transition to `next`. It **does not** change state immediately.
   - `requestClear()`: stores a pending request to exit the current state and leave the machine empty. It **does not** change state immediately.
   - Module-level `initialGameStateFromArgs(args) !?GameState` (top level only): see Startup and shutdown.
10. **Private:** applying a request runs `exit` on the current state (if any) → replaces `current` (with `next`, or `null` for a clear) → runs `enter` on the new state (if any). Only the machine does this.

## Startup and shutdown
- **`init(initial: ?S)`** sets `current = initial` and calls `enter` on it, if it is not `null`.
- **The top-level `GameStateMachine` is never empty**: `main` always starts it with a game state and never calls `requestClear` on it. This is a documented rule, not enforced in code.
- **Default state is chosen by the caller (`main`)**, not by the state machine module. The module has no notion of a default.
- **Override from the command line:** the game can be started in a different state with `--gamestate=<name>` (e.g. `Zuimo --gamestate=playing`), mainly for testing. `<name>` is the tag name of a top-level game state.
  - `main` reads the process arguments and passes them to `initialGameStateFromArgs(args) !?GameState` in the state machine module. It looks for `--gamestate=` and ignores every other argument. It returns the matching state (built as `.{}`), or `null` if the argument is absent.
  - On `null`, `main` uses its own default, e.g. `const initial = (try initialGameStateFromArgs(args)) orelse GameState{ .menu = .{} };`.
  - `main` then calls `GameStateMachine.init(initial)`. `init` itself never sees the arguments, so a machine can also be created in a specific state directly (e.g. in tests).
  - Errors: the module prints a message and returns an error; it never exits the process itself. `main` propagates the error, so the game stops with a non-zero exit code.
    - Unknown name, including an empty one (`--gamestate=`): print the valid state names and return an error (e.g. `error.UnknownGameState`).
    - `--gamestate=` given more than once: return an error (e.g. `error.DuplicateGameState`).
- **`deinit()`** calls `exit` on the current state (if any), so the last state's resources are released at shutdown. A pending request is discarded without being applied.

## Transition rules
These apply to every machine, at every level.

11. **A state's memory never changes while that state's own hook is running.** Union variants share memory, so changing state inside a state's `tick` would leave its `self` pointing at another variant's data. All changes are deferred. (A substate transition applied inside a parent's `tick` is fine: only the nested union changes, and the parent's `self` stays valid.)
12. **Pending requests are applied at the end of the machine's `tick`**, after the current state's `tick` returns. On an empty machine, `tick` runs no hook but still applies a pending request, so an empty machine can enter a state.
13. **One pending slot, first request wins.** `requestTransition` and `requestClear` share the slot. If a request is already pending, later requests in the same frame are discarded with a `std.log.warn`.
14. **Same-state request:** checked **when the pending request is applied** (end of `tick`), not when it is requested. A transition to the tag that is already current, or a clear while the machine is already empty, is ignored with a `std.log.warn` naming the state, no hooks run, and the request is discarded. (A request-time check would be wrong when a state requests the incoming state from its own `exit`: `current` hasn't been swapped yet, so the request would pass and later restart the state.)
15. **Requests made during `enter`/`exit`:** the pending slot is cleared *before* `exit` runs, so a request made inside `exit` or `enter` is accepted and stays pending until the end of the **next** frame's `tick`. At most one transition happens per frame per machine; transitions are never chained within a frame. (Consequence: the new state's `tick` runs once before such a request is applied.)

## Substates
16. **A game state may own a machine for its substates** as a regular field: the game state *has* a machine, it *is not* one. Its substates are a separate tagged union, e.g. `PlayingSubState = union(enum) { intro: IntroGameState, gameplay: GameplayGameState, map: MapGameState }`, and the field is e.g. `sub_machine: Machine(PlayingSubState)`.
17. **Substates follow every rule above**: the three hooks, `.{}`-constructible, `<Name>GameState` naming, all transition rules.
18. **The parent drives its machine explicitly**: `init` in its own `enter`, `tick` in its own `tick`, `deinit` in its own `exit`. Nothing is forwarded automatically, so the parent decides, e.g. it may skip ticking its substates.
19. **Exit order is children first**: the parent calls `deinit` on its machine at the start of its own `exit`.
20. **Substates are optional**: owning a machine does not require an active substate. The parent chooses its initial substate or none (`init(null)`), and can return to no substate with `requestClear()`.
21. **Any depth**: a substate may own its own machine.

## Concrete states
- This spec defines the mechanism only. Real game states are added later as separate work.
- The implementation includes two **placeholder states**, `menu` (`MenuGameState`) and `playing` (`PlayingGameState`), so the code compiles and the machine can be demonstrated. They hold no data. `enter` and `exit` only log the state and hook name with `std.log.info` (e.g. `menu: enter`). `tick` is empty, because it runs every frame and logging there would flood the output.

## File layout
- The state machine is game-specific in use, so it lives with the game, not in `src/utils/` or `src/framework/`: under **`src/main/game-state-machine/`**.
- The machine is in one file, and **each state is in its own file** in a `states/` subfolder:
  ```
  src/main/game-state-machine/
  ├── game-state-machine.zig   # Machine, GameState union, GameStateMachine, initialGameStateFromArgs
  └── states/
      ├── menu.zig
      └── playing.zig
  ```

## Tests (tentative, to be revisited)
- The implementation includes Zig `test` blocks and a `zig build test` step.
- Tests exercise **only the public API** (`init`, `requestTransition`, `requestClear`, `tick`, `deinit`, `initialGameStateFromArgs`). Private functions are not called directly, so internals can be refactored without breaking tests.
- Machine-rule tests use `Machine(TestState)` with a **test-only union**, never the real game states (which will use GL/ImGui). Test states record which hooks were called, so tests can check hook order.
- Tests cover every transition rule: `init` runs `enter`, `deinit` runs `exit`; a request does not change state before the end of `tick`; order `exit` → swap → `enter`; first request wins; same-state request and clear-while-empty run no hooks; a request made during `enter`/`exit` is applied on the next `tick`; an empty machine runs no hooks but can enter a state; `requestClear` exits the current state and leaves the machine empty.
- Tests cover `initialGameStateFromArgs`: absent argument → `null`; valid name → matching state; unknown name, empty name and duplicate argument → errors.

## Future: signals (out of scope, but the design must allow them)
22. Most transitions will eventually be triggered by **signals (events)**. Callers report *what happened* (e.g. `play_pressed`), and the machine decides the next state in one central rules function: `(current state, event) → next state, or none`.
23. `requestTransition(state)` will remain as a direct escape hatch, e.g. for debug tools.
24. Signals will go through the **same deferred mechanism**: the same safe point, applied at the end of `tick`, and the **same pending slot** as direct requests. Whichever arrives first in a frame wins, whether it's a signal or a direct request; later ones are discarded with a `std.log.warn`.
25. A signal that doesn't apply in the current state will be ignored with a `std.log.warn`.

## Out of scope
- Signals/events (see the Future section).
- Memory allocation strategy for states.
- How other parts of the game (buttons, input callbacks) get access to a machine instance.
- Cross-level transitions: a substate requesting a transition of its parent's (or any ancestor's) machine.
- Choosing a substate from outside: no `--gamestate=playing.map`, and no transitions that specify the target's substate. The parent always picks its initial substate.

## Open questions
- **Q9 (tentative):** tests are included for now; to be revisited.
