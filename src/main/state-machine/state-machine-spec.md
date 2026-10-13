# State Machine Spec (draft v0.3)

## Context
- Purpose: top-level app architecture. One state machine drives what the app is doing each frame.

## States
1. **States are a tagged union** (`union(enum)`). Each variant is its own struct type holding that state's data.
2. **Every state struct must declare all three hooks**, even if empty:
   - `fn enter(self: *XState) void`
   - `fn tick(self: *XState) void`
   - `fn exit(self: *XState) void`
3. **Hooks take no parameters** other than `self`, and **return `void`**. A state handles its own errors.
4. States may own resources such as memory and GL objects. They acquire them in `enter` and release them in `exit`.
5. **Every state struct must be constructible as `.{}`**: every field has a default value. Defaults must be real values, not `undefined`. This lets the module build any state from its name (see the command-line override). Code that requests a transition may still pass non-default values.
6. **Dispatch uses `inline else`**: `inline else => |*s| s.tick()` (and likewise for `enter` and `exit`). Plain `else => |*s|` is **forbidden** here: without `inline` it captures the whole union, so `s.tick()` calls `State.tick` and recurses forever.

## StateMachine
7. **App-specific** (not generic): it knows the concrete `State` union.
8. **No hidden global inside the module.** `StateMachine` is a struct that owns `current: State`.
9. **Public API (for now):**
   - `init(initial: State)` and `deinit()`: see Startup and shutdown.
   - `tick()`: calls `tick` on the current state, then applies a pending transition if there is one.
   - `requestTransition(next: State)`: stores `next` as the pending transition. It **does not** change state immediately.
   - Module-level `initialStateFromArgs(args) !?State`: see Startup and shutdown.
10. **Private:** `transitionTo(next: State)` runs `exit` on the current state → replaces `current` → runs `enter` on `next`. Only the machine calls it.

## Startup and shutdown
- **`init(initial: State)`** sets `current = initial` and calls `enter` on it.
- **Default state is chosen by the caller (`main`)**, not by the state machine module. The module has no notion of a default.
- **Override from the command line:** the app can be started in a different state with `--gamestate=<name>` (e.g. `Zuimo --gamestate=playing`), mainly for testing. `<name>` is the state's tag name.
  - `main` reads the process arguments and passes them to `initialStateFromArgs(args) !?State` in the state machine module. It looks for `--gamestate=` and ignores every other argument. It returns the matching state (built as `.{}`), or `null` if the argument is absent.
  - On `null`, `main` uses its own default, e.g. `const initial = (try initialStateFromArgs(args)) orelse State{ .menu = .{} };`.
  - `main` then calls `StateMachine.init(initial)`. `init` itself never sees the arguments, so a machine can also be created in a specific state directly (e.g. in tests).
  - Errors: the module prints a message and returns an error; it never exits the process itself. `main` propagates the error, so the app stops with a non-zero exit code.
    - Unknown name, including an empty one (`--gamestate=`): print the valid state names and return an error (e.g. `error.UnknownGameState`).
    - `--gamestate=` given more than once: return an error (e.g. `error.DuplicateGameState`).
- **`deinit()`** calls `exit` on the current state, so the last state's resources are released at shutdown. A pending transition is discarded without being applied.

## Transition rules
11. **The state never changes while a hook is running.** Union variants share memory, so changing state inside `tick` would leave the running state's `self` pointing at another variant's data. All changes are deferred.
12. **Pending transitions are applied at the end of `StateMachine.tick`**, after the current state's `tick` returns.
13. **One pending slot, first request wins.** If a transition is already pending, later requests in the same frame are discarded with a `std.log.warn`.
14. **Same-state request:** checked **when the pending transition is applied** (end of `tick`), not when it is requested. If the pending state has the same tag as `current` at that moment, it is ignored with a `std.log.warn` naming the state, no hooks run, and it is discarded. (A request-time check would be wrong when a state requests the incoming state from its own `exit`: `current` hasn't been swapped yet, so the request would pass and later restart the state.)
15. **Requests made during `enter`/`exit`:** the pending slot is cleared *before* `exit` runs, so a request made inside `exit` or `enter` is accepted and stays pending until the end of the **next** frame's `tick`. At most one transition happens per frame; transitions are never chained within a frame. (Consequence: the new state's `tick` runs once before such a request is applied.)

## Concrete states
- This spec defines the mechanism only. Real app states are added later as separate work.
- The implementation includes two **placeholder states**, `menu` and `playing`, so the code compiles and the machine can be demonstrated. They hold no data except what tests need to record hook calls (with defaults, so they stay constructible as `.{}`). `enter` and `exit` only log the state and hook name with `std.log.info` (e.g. `menu: enter`). `tick` is empty, because it runs every frame and logging there would flood the output.

## File layout
- The state machine is app-specific, so it lives with the app, not in `src/utils/` or `src/framework/`: under **`src/main/state-machine/`**.
- The machine is in one file, and **each state is in its own file** in a `states/` subfolder:
  ```
  src/main/state-machine/
  ├── state-machine.zig   # StateMachine, State union, initialStateFromArgs
  └── states/
      ├── menu.zig
      └── playing.zig
  ```

## Tests (tentative, to be revisited)
- The implementation includes Zig `test` blocks and a `zig build test` step.
- Tests exercise **only the public API** (`init`, `requestTransition`, `tick`, `deinit`, `initialStateFromArgs`). Private functions are not called directly, so internals can be refactored without breaking tests.
- Tests cover every transition rule: `init` runs `enter`, `deinit` runs `exit`; `requestTransition` does not change state before the end of `tick`; order `exit` → swap → `enter`; first request wins; same-state request runs no hooks; a request made during `enter`/`exit` is applied on the next `tick`.
- Tests cover `initialStateFromArgs`: absent argument → `null`; valid name → matching state; unknown name, empty name and duplicate argument → errors.
- **Undecided:** which states the tests run against. Machine-rule tests must not depend on real states (they will use GL/ImGui). Candidates: (a) the machine is a private generic `Machine(comptime S: type)` exported as `pub const StateMachine = Machine(State);`, and tests use a test-only union; (b) tests use the placeholder states and are rewritten when real states arrive; (c) test-only states inside the real `State` union (not recommended: they would leak into the app, e.g. via `--gamestate=`). Whichever states the tests use record which hooks were called, so tests can check hook order.

## Future: signals (out of scope, but the design must allow them)
16. Most transitions will eventually be triggered by **signals (events)**. Callers report *what happened* (e.g. `play_pressed`), and the machine decides the next state in one central rules function: `(current state, event) → next state, or none`.
17. `requestTransition(state)` will remain as a direct escape hatch, e.g. for debug tools.
18. Signals will go through the **same deferred mechanism**: the same safe point, applied at the end of `tick`, and the **same pending slot** as direct requests. Whichever arrives first in a frame wins, whether it's a signal or a direct request; later ones are discarded with a `std.log.warn`.
19. A signal that doesn't apply in the current state will be ignored with a `std.log.warn`.

## Out of scope
- Signals/events (see the Future section).
- Memory allocation strategy for states.
- How other parts of the app (buttons, input callbacks) get access to the `StateMachine` instance.

## Open questions
- **Q9 (tentative):** tests are included for now; to be revisited.
- **Q9b:** which states the tests run against (see Tests, options a/b/c); to be revisited.
