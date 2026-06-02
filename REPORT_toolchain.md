# GHC Persistent Worker Toolchain

## Overview

This implementation defines a buck2 toolchain that allows the buck2-haskell
rules to use the GHC persistent worker from `ghc-persistent-worker/`. The
worker is selectable at build time; the default remains regular GHC.

## Architecture

The persistent worker system has three components:

1. **ghc-worker** — A long-lived GHC server process that keeps compilation
   state (loaded packages, module graphs) in memory between actions.
2. **buck-proxy** — An orchestrator that speaks buck2's gRPC-based persistent
   worker protocol. Buck2 starts this process and sends action requests to it;
   the proxy forwards them to ghc-worker.
3. **WorkerRunInfo** — A buck2 Starlark type that tells the execution engine
   to route an action through a persistent worker instead of spawning a new
   process for each action.

## Implementation

### Toolchain targets (`toolchains/worker/`)

- **`build_worker.bzl`** — A `worker_binary` rule that copies pre-built
  binaries from `ghc-persistent-worker/dist-newstyle`. This decouples the
  worker's build system (cabal) from the buck2 build graph. The rule uses
  `local_only = True` since `dist-newstyle` is in `[project] ignore`.

- **`BUCK`** — Three targets:
  - `toolchains//worker:ghc_worker` — the ghc-worker binary
  - `toolchains//worker:buck_proxy` — the buck-proxy binary
  - `toolchains//worker:persistent_worker` — combines both into a
    `WorkerInfo` provider via `buck2-haskell/persistent_worker.bzl`

### Execution platform (`platforms/`)

- **`platforms//:worker`** — A new execution platform with
  `use_persistent_workers = True` in its `CommandExecutorConfig`. This is the
  critical configuration that tells the buck2 execution engine to actually
  start and use persistent worker processes rather than falling back to direct
  execution.

### Wiring into haskell rules (`buck2-haskell/`)

- **`defs.bzl`** — The `_worker` attribute (previously `attrs.option(...)`)
  is now `attrs.exec_dep(...)` with default
  `"toolchains//worker:persistent_worker"`. This ensures the worker target is
  always resolved.

- **`haskell.bzl` / `haskell_ghci.bzl`** — Simplified extraction:
  `ctx.attrs._worker[WorkerInfo]` (no None check needed).

## Usage

### Default (no worker)

```sh
buck2 build //my:target
buck2 test //my:target
```

### With persistent worker

```sh
buck2 build //my:target \
  --config ghc-worker.enable=true \
  --config build.execution_platforms=platforms//:worker
```

Both flags are required:
- `ghc-worker.enable=true` — Tells the Haskell toolchain to use worker code
  paths (build plans, worker-aware compilation).
- `build.execution_platforms=platforms//:worker` — Tells buck2's execution
  engine to start persistent worker processes (via
  `use_persistent_workers = True`).

## Key Insight: `use_persistent_workers`

The main challenge was discovering that buck2 requires
`use_persistent_workers = True` in the `CommandExecutorConfig` of the
execution platform. Without this, buck2 ignores `WorkerRunInfo` and falls
back to direct command execution (using the `exe` field, which is empty for
Haskell worker actions — causing "Spawning executable `-M` failed").

This is not well-documented; I found it by extracting strings from the buck2
binary which revealed `LocalExecutorOptions.use_persistent_workers` as the
configuration knob. The Java worker in the prelude doesn't explicitly set this
because it relies on a different execution infrastructure (RE workers).

## GHC Plugin Support

Getting GHC Core-to-Core plugins to run correctly under the persistent worker
required fixing four separate bugs spanning both the buck2 build rules and the
worker's Haskell source. The canonical test target is
`buck2-haskell//tests/plugins:ht_lib_real_plugin`, which compiles a library
through a plugin that replaces string literals with `"plugin_ok"` at compile
time.

### How make-mode compilation works in the worker

The worker splits compilation into two sequential buck2 actions per target:

1. **Buildplan (metadata) step** — buck2 runs `ghc -M` via the worker. The
   worker calls `writeMetadata`, which runs `downsweep` to resolve the module
   graph. All home units are inserted into the worker's in-memory
   `HomeUnitGraph` (HUG). This action produces a JSON file (`md_file`) that
   encodes the module graph; it is an input to every subsequent compile action.

2. **Compile step** — For each module, buck2 runs the worker with
   `--module Foo`, `--unit my-pkg`, `--home-unit <md_file>`, and
   `--dep-modules [...]`. The compile step calls `withGhcMakeModule`, which
   restores the HUG from the buildplan state (`withCacheMake`) before calling
   `initializeSessionPlugins` and compiling.

The DynFlags for each unit are stored in `homeUnitEnv_dflags` inside its
`HomeUnitEnv` entry in the HUG. After `withCacheMake` restores the state,
`hscSetActiveUnitId` makes the relevant unit's DynFlags the active
`hsc_dflags`. Only then does `initializeSessionPlugins` read
`hsc_dflags.pluginModNames` to discover and load plugins.

### Bug 1 — Plugin flags missing from the buildplan step (`compile.bzl`)

`UnitParams.plugin_flags` controls which GHC flags reach the buildplan
step. Originally it was always `None` for worker actions, so the HUG stored
DynFlags with empty `pluginModNames`. When the compile step restored that HUG
and set the unit's DynFlags as active, `initializeSessionPlugins` had nothing
to load.

**Fix:** In `target_metadata` (`compile.bzl`), compute plugin flags
conditionally and pass them to `UnitParams`:

```python
worker_plugin_flags = compute_plugin_flags(ctx, link_style).unit if is_worker_execute else None
```

The guard is necessary: the metadata step also runs `ghc -M` in non-worker
mode, and `ghc -M` will attempt to load any `-fplugin=...` passed to it,
failing because the plugin package is not loaded yet during makedepend.

### Bug 2 — Swapped visibility maps in `queryFindOrigin` (`UnitIndex.hs`)

The worker maintains a shared `UnitIndexBackend` with two separate visibility
maps: `visibilities` (built from `-package` flags) and `pluginVisibilities`
(built from `-plugin-package` flags). `queryFindOrigin` has a `plugins :: Bool`
parameter that selects which map to use.

The original code had the maps swapped in the `if plugins` branch:

```haskell
-- Before (wrong):
(overrides, vis) =
  if plugins
  then (state.pluginModuleNameProvidersMap, visibilities)      -- wrong map
  else (state.moduleNameProvidersMap, pluginVisibilities)      -- wrong map
```

GHC's `lookupPluginModuleWithSuggestions` calls `findOrigin` with
`plugins = True`. With the swap, it searched the normal package visibility
map for the plugin module and found nothing.

**Fix:** Swap the two map references so `plugins = True` uses
`pluginVisibilities`:

```haskell
-- After (correct):
(overrides, vis) =
  if plugins
  then (state.pluginModuleNameProvidersMap, pluginVisibilities)
  else (state.moduleNameProvidersMap, visibilities)
```

### Bug 3 — `initializeSessionPlugins` called too early (`Metadata.hs`)

`writeMetadata` (the buildplan step's inner function) called
`initializeSessionPlugins` before running `downsweep`. The buildplan step's
`HscEnv` is initialised with `setTopSessionDynFlags` but without the
interpreter (`hsc_interp = Nothing`). Loading a plugin requires the
interpreter because it involves dynamic linking and calling Haskell code at
build time. Calling `initializeSessionPlugins` without an interpreter either
fails or silently does nothing, and the call is unnecessary — plugins do not
affect module dependency computation.

**Fix:** Remove `initializeSessionPlugins` from `writeMetadata`. Plugin
initialisation stays in `withGhcMakeModule` (the compile step), where the
interpreter is available via `withGhcInSession`.

### Bug 4 — Compile step missing from Buck2 cache invalidation (`compile.bzl`)

This was the most subtle bug. Even with bugs 1–3 fixed, the plugin
transformation was not applied — because Buck2 served a stale cached result
for the compile action.

**Root cause:** The worker compile path in `_compile_module` built
`compile_args_for_file` from `common_args.args_for_file` only:

```python
compile_args_for_file = cmd_args(common_args.args_for_file, hidden = aux_deps or [])
```

`common_args.oneshot_args_for_file` — which contains the unit-level GHC
flags including `-fplugin=...`, `-plugin-package`, and `-package-db` entries —
was absent from the worker compile path (it was only added on the non-worker
`else` branch). Buck2's cache key for the compile action is a hash of its
inputs, including command-line arguments. Since `oneshot_args_for_file` was
not part of the worker compile action's arguments, adding plugin flags to the
buildplan step did not change the compile action's cache key. Buck2 found a
cached result and used it without running compilation again.

A secondary effect was that even on a cache miss, `setSessionDynFlags` (called
inside `withGhcInSession`) did not see the plugin flags, so
`initializeSessionPlugins` had nothing to initialise before `withCacheMake`
restored the HUG.

**Fix:** Add `oneshot_args_for_file` to the worker compile path:

```python
if is_worker_execute:
    ...
    compile_args_for_file.add(common_args.oneshot_args_for_file)
```

This is safe because `oneshot_args_for_file` conditionally includes `-c` only
when `not is_worker_execute` (the worker receives `-c` through
`_compile_make_args` instead), so no flag duplication occurs. After
`withCacheMake` restores the full HUG from the buildplan state, the unit
DynFlags in the HUG take precedence over what `setSessionDynFlags` parsed, so
the restored plugin state is authoritative.

### Summary of four-part fix

| # | File | Change |
|---|------|--------|
| 1 | `buck2-haskell/compile.bzl` | Pass plugin flags to buildplan step (worker only) |
| 2 | `ghc-persistent-worker/.../UnitIndex.hs` | Fix swapped `visibilities` / `pluginVisibilities` |
| 3 | `ghc-persistent-worker/.../Metadata.hs` | Remove premature `initializeSessionPlugins` |
| 4 | `buck2-haskell/compile.bzl` | Add `oneshot_args_for_file` to worker compile path |

All four fixes are required. Each addresses a distinct failure mode in a
different layer of the system (build rules, package index, session lifecycle,
cache invalidation).

## Per-module Plugin Support (`srcs_plugins`)

The four-part fix above restores support for *unit-level* plugins (the global
`plugins` attribute on a target). A separate bug prevented *per-module*
plugins (`srcs_plugins`, where different source files can use different
plugins) from working in worker mode.

The canonical test target is
`buck2-haskell//tests/plugins:ht_srcs_real_plugin_shared`, which compiles a
`haskell_test` with `link_style = "shared"` and
`srcs_plugins = {"PluginMain.hs": [":real_plugin"]}`.

### How `srcs_plugins` differs from global `plugins`

For a target using only `srcs_plugins` (no global `plugins`):

- `compute_plugin_flags(ctx, link_style).unit` returns `cmd_args()` — empty.
- Plugin flags for each source file live in `.srcs[source_file]`, not in `.unit`.

Before this fix, `worker_plugin_flags` was set to `.unit` only:

```python
worker_plugin_flags = compute_plugin_flags(ctx, link_style).unit if is_worker_execute else None
```

This left `worker_plugin_flags = cmd_args()` for `srcs_plugins`-only targets,
which had two cascading effects:

### Bug 5 — Empty `pluginVisibilities[unit]` in the buildplan UnitIndex (`compile.bzl`)

The buildplan step calls `addHomeUnit dflags` with the flags from
`worker_plugin_flags`. These flags are processed by `computeProvidersShared`
(our custom `UnitIndexBackend`), which extracts `-plugin-package <id>` entries
from `pluginPackageFlags` and stores them in `pluginVisibilities[unit]`.

When `worker_plugin_flags` is empty, `pluginVisibilities[unit]` is empty. In
the compile step, `withCacheMake` restores the UnitIndex from the buildplan
state; since the restored UnitIndex has no plugin visibility for this unit,
`queryFindOrigin(plugins=True)` cannot find the plugin package, and
`initializeSessionPlugins` silently finds nothing to load.

**Fix:** In `target_metadata` (`compile.bzl`), merge all plugin flags — both
unit-level and every per-module entry — into `worker_plugin_flags`:

```python
if is_worker_execute:
    _pf = compute_plugin_flags(ctx, link_style)
    _all_plugin_flags = cmd_args(_pf.unit)
    for _, _src_flags in _pf.srcs.items():
        _all_plugin_flags.add(_src_flags)
    worker_plugin_flags = _all_plugin_flags
else:
    worker_plugin_flags = None
```

This ensures the buildplan step's UnitIndex has `pluginVisibilities[unit]` for
every plugin referenced by any module in the target, regardless of whether
plugins are declared at unit or module granularity.

### Bug 6 — `hscSetActiveUnitId` overwrites per-module plugin DynFlags (`Session.hs`)

After the buildplan step stores the HUG (now carrying all plugin flags from
bug 5's fix), `withCacheMake` in `withGhcMakeModule` restores that HUG.
`hscSetActiveUnitId` then pulls `homeUnitEnv_dflags` from the HUG into
`hsc_dflags`. For a multi-module target where only *some* modules have
`srcs_plugins`, the HUG's DynFlags (set from the union of all plugin flags in
the buildplan step) would carry `pluginModNames = [Plugin]` for *all* modules
— even those that should not run the plugin.

The compile step's `setSessionDynFlags` call (inside `withGhcInSession`) does
set correct per-module flags into `dflags0`. However, `dflags0` is captured
*before* `withCacheMake` restores the HUG, and `hscSetActiveUnitId` runs
*after* the restore. The per-module flags are therefore overwritten.

**Fix:** In `withGhcMakeModule` (`Session.hs`), after `hscSetActiveUnitId`,
re-apply the plugin-related fields from `dflags0` before
`initializeSessionPlugins`:

```haskell
modifySession \ hsc_env ->
  hsc_env { hsc_dflags = hsc_env.hsc_dflags
    { pluginModNames    = dflags0.pluginModNames
    , pluginModNameOpts = dflags0.pluginModNameOpts
    , pluginPackageFlags = dflags0.pluginPackageFlags
    } }
initializeSessionPlugins
```

`dflags0` was produced by `setSessionDynFlags` from this specific compile
action's arguments:
- For modules *with* `srcs_plugins`: `dflags0.pluginModNames = [Plugin]` → plugin loads and Core pass runs.
- For modules *without* `srcs_plugins`: `dflags0.pluginModNames = []` → plugin fields are cleared, no spurious plugin loading.

The `modifySession` here only modifies `hsc_dflags`, not the HUG itself. The
`storeState` call (inside `withCacheMake`) stores `ue_home_unit_graph`, not
`hsc_dflags`, so per-module plugin overrides do not pollute shared state.

### Summary of two-part fix for `srcs_plugins`

| # | File | Change |
|---|------|--------|
| 5 | `buck2-haskell/compile.bzl` | Merge all srcs_plugins flags into buildplan's `worker_plugin_flags` |
| 6 | `ghc-persistent-worker/.../Session.hs` | Re-apply `dflags0` plugin fields after `hscSetActiveUnitId` |

Both fixes are required together: fix 5 ensures the UnitIndex can resolve the
plugin package; fix 6 ensures `initializeSessionPlugins` reads the correct
per-module `pluginModNames` rather than the HUG's broader set.

## Verified

- `buck2 test buck2-haskell//tests/build_tests/pkgA:test_app` passes with
  both the worker and non-worker configurations.
- `buck2 test buck2-haskell//tests/build_tests/...` — all 8 tests pass with
  the worker.
- `buck2 test buck2-haskell//tests/plugins:ht_lib_real_plugin` passes with
  the worker; the plugin correctly replaces `"plugin"` with `"plugin_ok"`.
- `buck2 test buck2-haskell//tests/plugins:ht_srcs_real_plugin_shared` passes
  with the worker; per-module `srcs_plugins` correctly applies the plugin only
  to the specified source file.
- Worker execution is confirmed via `-v5` logs showing `worker_init executor`
  and `worker executor` prefixes on actions.
