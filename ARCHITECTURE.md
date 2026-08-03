# GravSling Architecture

This document explains the two load-bearing subsystems of the project:

1. **Hot reload** — how the running game is recompiled and swapped without losing state.
2. **Memory model & tracking** — how memory is partitioned, which allocator owns what, and how leaks/bad-frees are caught.

If you only read one thing, read the [Invariants](#invariants) at the bottom — everything else is the reasoning behind them.

---

## 1. High-level shape

The project is split into a **thin host exe** and a **fat game DLL**:

```
main_hot_reload.exe            game.dll  (rebuilt & swapped live)
──────────────────             ─────────────────────────────────
 owns the outer loop     ──▶    all game + platform + UI code
 owns the reload logic   ◀──    exposes a small proc table (Game_API)
 never reloads                  reloaded on every recompile
```

This is the **"loop in the exe"** pattern: the exe owns the `for` loop and calls into the DLL once per tick through a table of function pointers. The exe itself contains almost no logic — it is a dispatcher plus the reload state machine. Everything else (timing, input, simulation, rendering, UI) lives in the DLL so it can be edited and reloaded.

There are three build targets, selected by the `HOTLOAD` config flag:

| Target | `HOTLOAD` | What it is |
|---|---|---|
| `main_hot_reload.exe` + `game.dll` | `true` (default) | dev build with live reload |
| `main_release.exe` | `false` | single-exe release, no reload |
| (`main_web` — legacy, not maintained) | — | wasm attempt, ignore |

### Package layout

| Path | Role |
|---|---|
| `source/game.odin` (+ siblings) | the `game` package: all game/platform/UI code, and the DLL exports |
| `source/hotload_api/api.odin` | `Game_API` proc table, DLL load/unload, reload classification |
| `source/main_hot_reload/` | dev host exe (`HOTLOAD=true`) |
| `source/main_release/` | release exe (`HOTLOAD=false`) |
| `source/config/` | platform context + platform allocator setup (runs in the host) |
| `source/mem_tracking/` | tracking-allocator leak/bad-free reporting helpers |
| `source/imgui_impl_sdl3.odin`, `imgui_impl_sdlrenderer3.odin` | Dear ImGui backends, ported to Odin, compiled into `game` |
| `source/b2_debug_draw.odin` | box2d debug-draw `proc "c"` callbacks |

---

## 2. Hot reload

### 2.1 The proc table (`Game_API`)

The DLL exposes its capabilities through a struct of function pointers (`hotload_api/api.odin`):

```odin
Game_API :: struct {
    lib:                dynlib.Library,
    init:               proc(platform_ctx: runtime.Context) -> rawptr, // returns opaque ^Hotload_Memory
    tick:               proc(handle: rawptr),
    should_quit:        proc(handle: rawptr) -> bool,
    unload_for_hotload: proc(handle: rawptr),
    unload_for_reset:   proc(handle: rawptr),
    rebuild_memory:     proc(handle: rawptr, platform_ctx: runtime.Context),
    shutdown:           proc(handle: rawptr, platform_ctx: runtime.Context),
    hot_reloaded:       proc(handle: rawptr, platform_ctx: runtime.Context),
    force_reload:       proc() -> bool,   // F4
    force_reset:        proc() -> bool,   // F5
    memory_size:        proc() -> int,    // size_of(Game_Memory)
    platform_size:      proc() -> int,    // size_of(Platform_State)
    modification_time:  time.Time,
    api_version:        int,
}
```

`dynlib.initialize_symbols(&api, dll, "game_", "lib")` fills each field by matching it to an exported symbol named `game_<field>`. So `Game_API.tick` binds to the DLL's `@(export) game_tick`, and so on. The proc table is Odin's substitute for a vtable across the DLL boundary.

The corresponding exports live in `game.odin` inside a `when HOTLOAD { ... }` block (`game_init`, `game_tick`, `game_should_quit`, `game_unload_for_hotload`, `game_unload_for_reset`, `game_rebuild_memory`, `game_shutdown`, `game_hot_reloaded`, `game_force_reload`, `game_force_reset`, `game_memory_size`, `game_platform_size`). Each is a thin wrapper that unpacks the opaque handle, restores context (see §3.3), and calls into the *shared* game procs — the same procs the release build calls directly.

### 2.2 The host loop

`main_hot_reload/main_hot_reload.odin`, simplified:

```odin
platform_context := config.init()          // cwd, logger, platform allocator
game_api := load_game_api(0)               // load game_0.dll
old_game_apis := make([dynamic]Game_API)   // pinned old DLLs (see §2.5)

handle := game_api.init(platform_context)  // build platform + game memory
for !game_api.should_quit(handle) {
    game_api.tick(handle)                  // one frame, entirely inside the DLL

    new_api, reload := check_for_reload(game_api, handle)
    switch reload {
    case .None:
    case .Hot:   /* swap code, keep memory   */
    case .Reset: /* swap code, rebuild memory */
    }
}
game_api.shutdown(handle, platform_context)
config.shutdown(platform_context)
```

`tick` runs a whole frame (input → fixed-timestep simulation → render → UI) without yielding control-flow back to the exe mid-frame. The exe only regains control between frames, which is where reloads happen.

### 2.3 The DLL copy/pin scheme

The compiler writes `build/hot_reload/game.dll`. The exe never loads that file directly (that would lock it and block the next compile). Instead, `copy_dll` copies it to `game_{N}.dll` and loads *that*. Each reload increments `api_version`, so successive loads are `game_0.dll`, `game_1.dll`, … This lets the compiler overwrite `game.dll` while the exe keeps running a private, pinned copy.

Reload is detected by polling `game.dll`'s last-write time each frame (plus the manual F4/F5 keys).

### 2.4 The reload state machine

`check_for_reload` classifies each reload:

```
mod-time changed?  ── no ──▶ and no F4/F5 ──▶ .None
       │ yes / F4 / F5
       ▼
 load game_{N+1}.dll
       │
       ▼
 F5 pressed, OR size_of(Game_Memory) changed, OR size_of(Platform_State) changed?
       │ yes ──▶ .Reset
       │ no  ──▶ .Hot
```

A struct-size change **forces a Reset** because old memory can't be safely reinterpreted under a new layout.

**`.Hot`** — code changes, state preserved:

```
old.unload_for_hotload()   // im_shutdown() on the OLD dll (see §4)
append old to pinned list
game_api = new
new.hot_reloaded()         // im_init() + rebind_callbacks() + reset frame timing, on the NEW dll
                           // Game_Memory is untouched
```

**`.Reset`** — hard reset, state rebuilt:

```
old.unload_for_reset()     // im_shutdown() + g_mem_shutdown() on the OLD dll
game_api = new
new.rebuild_memory()       // g_mem_reset(): fresh Game_Memory in the NEW dll
new.hot_reloaded()         // im_init() + rebind + timing
unload ALL pinned old dlls + the previous one
```

The split between "tear down on the old DLL" and "build up on the new DLL" is deliberate: teardown must run with the code/allocator that created the memory, and rebuild must run with the new code (which may have a new `Game_Memory` layout). See §5 for why this matters for ImGui specifically.

### 2.5 Why old DLLs are pinned

On `.Hot` we do **not** unload the outgoing DLL — we push it onto `old_game_apis` and keep it mapped. Reason: `Game_Memory` persists across a hot reload, and it contains pointers *into the old DLL's image* — string literals and, critically, `#caller_location` source-code-location data stored in tracking-allocator entries. Unloading the old DLL would dangle those pointers and corrupt leak reports.

On `.Reset`, `Game_Memory` is being torn down anyway, so nothing references the old DLLs anymore and they are all unloaded.

---

## 3. Memory model

### 3.1 Two persistence tiers

State is partitioned by **how long it must live**:

```
Platform_State   ── persists across resets ──  window, renderer, allocator,
                                                platform_memory_tracking,
                                                game_memory_tracking
                                                (created ONCE at launch)

Game_Memory      ── rebuilt on reset       ──  physics_world, avatar, ball,
                                                walls, sim_ctx, b2_debug_draw,
                                                allocator
                                                (built by g_mem_reset)
```

`Hotload_Memory { platform: ^Platform_State, g_mem: ^Game_Memory }` is the opaque handle the exe holds. `game_init` allocates it on the platform allocator and returns it as `rawptr`; every export casts the handle back and reads `.platform` / `.g_mem`.

The rule that follows: **anything that must survive a reload lives in `Platform_State` (or another persistent module); anything disposable per-reset lives in `Game_Memory`.**

### 3.2 Allocator tiers

There are three tracking allocators, each scoped to a lifetime:

| Allocator | Where it's set up | Backs | Lifetime |
|---|---|---|---|
| **host exe** | `main_hot_reload.main` | the exe's own bookkeeping (`old_game_apis`, etc.) | whole process |
| **platform** | `config.init` (`g_platform_tracking_allocator`) | `Platform_State`, `Hotload_Memory` | whole process |
| **game** | `g_mem_reset` (`platform.game_memory_tracking.tracking_allocator`) | `Game_Memory` **and** ImGui | one generation (rebuilt each reset) |

`config.init` runs in the **host exe**, so the platform allocator's procedure and its bookkeeping live in the exe — a module that never reloads. `Platform_State` therefore sits on memory whose allocator can't dangle across a DLL swap.

The **game allocator** is per-generation. `context.allocator` (and `g_context.allocator`, §3.3) point at it, so `new(Game_Memory)`, the entity `*_make` procs, and all ImGui allocations flow through it and are tracked together.

#### The backing-allocator seam

`g_mem_reset` gets its raw backing through a single indirection:

```odin
game_allocator := game_backing_allocator(platform)  // os.heap_allocator() today
// ... wrap in tracking allocator ...
game_backing_reset(platform)                        // reclaim hook, no-op for heap
```

`game_backing_allocator` / `game_backing_reset` are the seam for later swapping the heap for a custom allocator (e.g. a per-generation arena) without touching call sites. Today they are a plain `os.heap_allocator()` and a no-op.

### 3.3 Context & globals across the boundary

Odin's `context` (allocator, logger, temp allocator) is implicit and does not cross a raw function-pointer or `proc "c"` call automatically, and per-DLL globals are **zeroed in a freshly loaded DLL**. So two globals are re-established on every reload:

- **`g_context`** — the game context: the platform context with `.allocator` swapped to the game allocator. Set by `establish_game_context` in both `init` and `game_hot_reloaded`. The exports (`game_tick`, etc.) open with `context = g_context`.
- **`g_platform`** — the platform handle, for `proc "c"` callbacks that need platform state. Set by `establish_globals` in `init` and `game_hot_reloaded`.

`proc "c"` callbacks (the ImGui allocator funcs `im_mem_alloc_func`/`im_mem_free_func`, the box2d debug-draw callbacks) carry no Odin context, so their first line is `context = g_context` to restore the game allocator/logger before doing anything.

---

## 4. Memory tracking

Each tier uses `mem.Tracking_Allocator`, which wraps a backing allocator, records every live allocation in a map, and reports **bad frees** (freeing an untracked pointer) and **leaks** (allocations still live at teardown). It is gated by the `MEMORY_TRACKING` config flag (default `true`; `false` uses raw allocators).

### 4.1 Where each tracker is checked

- **Game tracker** — bad-free array is checked every frame in `update_and_render` (panics on a bad free), and leaks are reported at `g_mem_shutdown`.
- **Platform tracker** — checked/destroyed in `config.shutdown`.
- **Host exe tracker** — checked/destroyed at the end of `main`.

### 4.2 Game-tracker lifecycle (the subtle part)

The game tracker lives in `Platform_State` (persistent) but is **re-initialized per generation**:

- `g_mem_reset` → `tracking_allocator_init(...)` — start a fresh generation.
- `g_mem_shutdown` → `tracking_allocator_destroy(...)` — end the generation.

It is re-inited each reset (rather than inited once and cleared) so the map's internals allocator is re-pointed to the **current** DLL. `os.heap_allocator`'s procedure is statically linked, so its address is per-DLL; a map that kept an old DLL's proc would call into unmapped code after that DLL unloads.

> **Historical footnote — the dangling-map bug.** `tracking_allocator_destroy` does `delete(t.allocation_map)`. Odin's `delete(map)` takes the map **by value**, so it frees the backing storage but cannot nil the caller's `.data` pointer, and `tracking_allocator_init` only sets `.allocator`, never `.data`. Older Odin therefore left a **dangling map** after `destroy`+`init`, and the next generation's inserts wrote into freed memory — silently clobbering entries (this manifested as ImGui allocations "disappearing" from the map after a reset). This is now fixed upstream: `tracking_allocator_destroy` zeroes the headers after freeing. No workaround is needed in this repo as long as the toolchain includes that fix.

### 4.3 Tracking ⇄ DLL pinning

Tracking-allocator entries store a `#caller_location` (source-code location) whose string pointers live in the **DLL image** that made the allocation. This is the other reason old DLLs are pinned on hot reload (§2.5): unloading them would dangle those pointers and break leak reporting for memory that outlived the reload.

---

## 5. ImGui integration

Dear ImGui (via cimgui) is **statically linked** into `game.dll` (`imgui_windows_x64.lib`). Its context pointer `GImGui` and its allocator-function globals are therefore **per-DLL** and are wiped in each freshly loaded `game.dll`. Consequently ImGui is fully **torn down and rebuilt on every reload**:

- `im_shutdown` — backend `Shutdown` + `DestroyContext` (on the **old** DLL, in `unload_for_hotload` / `unload_for_reset`).
- `im_init` — `SetAllocatorFunctions` + `CreateContext` + backend `Init` (on the **new** DLL, in `hot_reloaded`).

**ImGui memory is deliberately on the game tracker** (via `g_context.allocator`), not the platform allocator. This keeps ImGui allocations tracked, and — because ImGui is fully torn down each reload — the game tracker's leak/bad-free check actually *verifies* that teardown drained everything. Putting ImGui on the platform allocator would hide its lifecycle instead of validating it.

Two details worth knowing:

- **Monitors buffer.** `platform_io.Monitors` is a C++ `ImVector`. The bindings expose no `push_back`, so `ImGui_ImplSDL3_UpdateMonitors` grows it through ImGui's own allocator (`im.MemAlloc`/`im.MemFree`, via `im_monitors_push`/`im_monitors_reserve`). This gives ImGui sole ownership of the buffer — its `~ImVector` frees a matching `IM_ALLOC` — instead of the earlier hack of aliasing an Odin `[dynamic]` into the `ImVector` fields (which caused split ownership and heap corruption).
- **Layout persistence.** Window/dock layout survives reloads via `imgui.ini` on disk, so the full Destroy/Create cycle doesn't visibly reset the UI.

**Why not keep the context alive across reloads (`SetCurrentContext`)?** It would require re-pointing the per-DLL allocator funcs, the backend callbacks, *and* the `ImGuiSettingsHandler` function pointers (a known unresolved ImGui hot-reload hazard, ocornut/imgui#7379), and it forfeits the per-reload teardown verification. Destroy/Create is simpler and robust; the cost (re-rasterizing the font atlas) is negligible.

---

## 6. box2d — known limitation

box2d is currently **statically linked** (`vendor:box2d`, a static `.lib`). box2d v3 keeps its world pool in a `static` array *inside the library*, so that state is **per-`game.dll`**.

**Consequence:** on a **hot reload**, `Game_Memory` still holds `WorldId`/`BodyId` handles into the *old* DLL's world pool, but the new `game.dll` has a fresh, empty pool. The first box2d call after a hot reload (e.g. `b2.Body_GetMass(avatar.body)`) reads invalid memory → access violation. A **reset (F5) works**, because `g_mem_reset` calls `b2.CreateWorld` and repopulates the current DLL's pool.

**Planned fix:** build box2d as its own DLL (`box2d.dll` + import lib), exactly like `SDL3.dll`. Then box2d's world pool lives in a persistent module and the handles survive `game.dll` reloads — no function-pointer forwarding needed; the OS loader resolves `game.dll`'s imports to `box2d.dll` on every load. Until that lands: **hot-reloading code that touches box2d handles crashes; use reset.**

The general principle this illustrates: *state that must outlive a `game.dll` reload has to live in a module that doesn't reload* — the exe (`config`'s platform allocator), or another DLL (`SDL3.dll`, and eventually `box2d.dll`).

---

## 7. Build flags & the release path

- **`HOTLOAD`** (`#config`, default `true`): `true` builds `game.dll` + `main_hot_reload.exe`; `false` builds `main_release.exe` with no reload.
- **`MEMORY_TRACKING`** (`#config`, default `true`): enables the tracking allocators; `false` uses raw allocators.

The DLL exports live inside `when HOTLOAD`, so in the release build they don't exist. `main_release` instead calls the **shared** procs directly — the same ones the exports wrap: `game.init`, `game.should_quit`, `game.poll_input`, `game.update_and_render`, `game.on_frame_end`, `game.shutdown`. This is why the frame loop and lifecycle logic live in shared, non-exported procs and are never duplicated between the hotload and release paths.

---

## Invariants

The rules that keep all of the above correct:

1. **Persistence follows the module.** State that must survive a `game.dll` reload lives in a module that doesn't reload — the host exe, another DLL, or persistent memory on the platform allocator (`Platform_State`). Disposable-per-reset state lives in `Game_Memory` on the per-generation game allocator.
2. **Re-establish per-DLL globals every reload.** `g_context`, `g_platform`, and ImGui's `GImGui` / allocator funcs / backend callbacks are zeroed in a fresh DLL and must be set again in `hot_reloaded` (and `init`).
3. **`proc "c"` callbacks restore `context = g_context`** before allocating, logging, or touching game state.
4. **Tear down on the old DLL, rebuild on the new.** On reset, the outgoing DLL runs `im_shutdown` + `g_mem_shutdown` (with the code/allocator that made the memory); the incoming DLL runs `g_mem_reset` + `im_init` (with the new code/layout).
5. **A struct-size change forces a Reset.** `Game_Memory` / `Platform_State` layout changes can't be reinterpreted in place.
6. **Pin old DLLs on hot reload.** Persisted memory holds pointers (string literals, source locations) into old DLL images; keep them mapped until the memory referencing them is gone.
7. **The game allocator is per-generation and re-inited each reset**, so its internals allocator always belongs to the current DLL.
