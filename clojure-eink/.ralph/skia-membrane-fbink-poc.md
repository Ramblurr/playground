# Skia Membrane FBInk PoC Ralph Loop

Prepare and execute the proof of concept described in `prompts/004-skia-membrane-fbink-poc.md` from an isolated git worktree.

**Do not start this loop until the human reviews and approves this document.**

## Path map

> Use the worktree paths below for all loop work. The original checkout path is listed only for provenance and for ignored local context that was copied into the worktree.

- Original project checkout: `/home/ramblurr/src/github.com/ramblurr/playground/clojure-eink`
- Worktree root: `/home/ramblurr/src/github.com/ramblurr/playground/clojure-eink/.worktrees/skia-membrane-fbink-poc`
- Clojure project directory inside the worktree: `/home/ramblurr/src/github.com/ramblurr/playground/clojure-eink/.worktrees/skia-membrane-fbink-poc/clojure-eink`
- Ralph directory: `/home/ramblurr/src/github.com/ramblurr/playground/clojure-eink/.worktrees/skia-membrane-fbink-poc/clojure-eink/.ralph`
- This Ralph task document: `/home/ramblurr/src/github.com/ramblurr/playground/clojure-eink/.worktrees/skia-membrane-fbink-poc/clojure-eink/.ralph/skia-membrane-fbink-poc.md`
- Source prompt in original checkout: `/home/ramblurr/src/github.com/ramblurr/playground/clojure-eink/prompts/004-skia-membrane-fbink-poc.md`
- Local copied prompt in worktree: `/home/ramblurr/src/github.com/ramblurr/playground/clojure-eink/.worktrees/skia-membrane-fbink-poc/clojure-eink/prompts/004-skia-membrane-fbink-poc.md`

## Ignored local context copied into worktree

`clojure-eink/.gitignore` ignores `prompts/`, so `git worktree add` does not copy untracked prompt documents automatically. The prompt files were copied manually from the original checkout into the worktree with:

```sh
cp -a /home/ramblurr/src/github.com/ramblurr/playground/clojure-eink/prompts/. \
  /home/ramblurr/src/github.com/ramblurr/playground/clojure-eink/.worktrees/skia-membrane-fbink-poc/clojure-eink/prompts/
```

Those copied prompt files are intentionally local, ignored context for the loop. Do not assume they are tracked by git.

## Loop configuration proposal

- Ralph loop name: `skia-membrane-fbink-poc`
- Worktree root: `/home/ramblurr/src/github.com/ramblurr/playground/clojure-eink/.worktrees/skia-membrane-fbink-poc`
- Project directory for commands: `/home/ramblurr/src/github.com/ramblurr/playground/clojure-eink/.worktrees/skia-membrane-fbink-poc/clojure-eink`
- Source prompt: `prompts/004-skia-membrane-fbink-poc.md`
- Suggested `itemsPerIteration`: 2
- Suggested `reflectEvery`: 5
- Suggested `maxIterations`: 40

## Non-negotiable constraints

- Keep `src/clj/membrane/*` vendored Membrane files untouched.
- Keep the existing Java2D backend and scripts working.
- Add the Skia path beside the Java2D path; do not replace `ol.membrane.eink-backend`.
- Use a separate native library: `libclojure_eink_skia.so`.
- Use separate environment variables: `EINK_SKIA_NATIVE_LIB` and `EINK_FONT_DIR`.
- Render Skia output into gray8 (`kGray_8_SkColorType`) from the start.
- Use SkParagraph for the first real text proof; do not claim success with only placeholder/simple text rendering.
- Add tests before implementation behavior where practical.
- Do not run direct interactive Kobo commands over plain `ssh`; use `tmuxb capture` before every `tmuxb send`.
- Before deployment, service-impacting, or Kobo-device-changing steps, stop and record a safety/rollback note.
- Input is explicitly out of scope for this loop. A separate agent is working on low-level Linux input in the main worktree; do not touch that work unless the human explicitly redirects the Skia rendering loop.
- Interpret `prompts/004-skia-membrane-fbink-poc.md` as a rendering-only PoC. The current Java2D backend has no input path, and the Skia path should not add key/touch/evdev/event-loop input handling.

## Checkpoint commit policy

After each numbered checklist section is complete (`1`, `2`, `3`, etc.; not the pre-loop section `0`), the loop agent should:

1. Run the relevant verification commands for that section.
2. Update this Ralph document with changed paths, evidence, and any blockers.
3. Stage only the files that belong to that section's completed work.
4. Commit the checkpoint on branch `skia-membrane-fbink-poc` before starting the next numbered section.

Do not combine multiple numbered sections into one large commit unless the human explicitly approves that exception.

## Supervisor coordination

> Runtime subagent name: `cljeink-skia-ralph`; supervisor link name: `cljeink-skia-supervisor`.

After each checkpoint commit, send a concise pi-link callback to `cljeink-skia-supervisor` with:

- `DONE section <n>` or `BLOCKED section <n>`
- checkpoint commit hash, if a commit was created
- changed files
- verification commands and results
- next planned section or question/blocker

Do not wait for supervisor approval between ordinary numbered sections unless blocked, tests fail, deployment/device operations are next, or the Ralph document says to stop.

## Goals

- Build host and Kobo ARMv7 Skia bridge packages.
- Add a Java FFM-backed Clojure Membrane backend namespace for Skia rendering.
- Render basic Membrane primitives into a native-owned gray8 raster buffer.
- Render text through Skia font/shaping/paragraph stack.
- Present gray8 bytes to Kobo through FBInk from the Skia bridge.
- Add host tests proving non-empty gray8 Skia output without requiring a Kobo.
- Add a packaged Kobo smoke command and capture manual validation evidence.
- Preserve and regression-check the Java2D path.

## Checklist

### 0. Prepared before loop start

- [x] Created git worktree on branch `skia-membrane-fbink-poc`.
- [x] Copied ignored prompt documents into the worktree `prompts/` directory for local context.
- [x] Detected Clojure project setup (`deps.edn` + `bb.edn`); no separate dependency install required.
- [x] Ran baseline tests in the worktree.
- [x] Human reviewed this Ralph task document.
- [x] Human approved starting the Ralph loop.

### 1. Inventory and first failing tests

- [x] Inspect existing Java2D native bridge, Clojure FFM loading, packaging script, and Nix packages.
- [x] Inspect current Skia package outputs/flags; note whether BiDi/custom-directory fonts/pkg-config metadata need changes.
- [x] Add/adjust host tests for Skia native symbol loading, initially allowed to skip only when `EINK_SKIA_NATIVE_LIB` is absent.
- [x] Add a failing test or explicit pending check for the required `eink_skia_*` ABI surface.

### 2. Native bridge package skeleton

- [x] Add `src/native/eink_skia_native.h` and `src/native/eink_skia_native.cpp` with `eink_skia_last_error` and stable C ABI scaffolding.
- [x] Add `nix/pkgs/clojure-eink-skia-bridge/package.nix` for host and Kobo builds.
- [x] Wire host and Kobo bridge packages in `flake.nix`.
- [x] Verify host bridge build with `nix build .#clojure-eink-skia-bridge -o result-skia-native`.
- [x] Verify Kobo bridge build with `nix build .#clojure-eink-skia-bridge-kobo -o result-kobo-skia-native`.

### 3. Clojure FFM loading

- [x] Add `src/clj/ol/membrane/skia_eink_backend.clj` with native loading for the Skia bridge only.
- [x] Resolve `eink_skia_last_error` first, then expand to all required symbols.
- [x] Keep `EINK_NATIVE_LIB` reserved for the old Java2D/FBInk bridge.
- [x] Add tests for missing library behavior and required symbol resolution.

### 4. Native gray8 context

- [x] Implement create/destroy/width/height/stride/clear/copy functions.
- [x] Fail clearly for invalid dimensions and undersized copy buffers.
- [x] Add host tests for context creation, clear-to-white, copy size, and repeated create/destroy.

### 5. Skia primitive rendering

- [x] Create a wrapped `kGray_8_SkColorType` raster surface over native-owned pixels.
- [x] Implement save/restore/translate/scale/clip/color/style/stroke-width calls.
- [x] Implement rectangle, rounded rectangle, and path drawing.
- [x] Add host tests that drawing black geometry makes copied gray8 bytes non-white.

### 6. Font directory and text stack

- [x] Package or expose bundled Noto Sans/Noto Serif font files for host tests and Kobo dist.
- [x] Implement required `EINK_FONT_DIR` behavior; missing/empty font directories must fail clearly.
- [x] Wire `SkFontMgr_New_Custom_Directory` into SkParagraph font collection.
- [x] Implement `eink_skia_text_bounds` and `eink_skia_draw_text_box` with SkParagraph-backed layout.
- [x] Add host tests for positive text bounds and visible text pixels.

### 7. Membrane backend and project-local paragraph

- [x] Implement the small Membrane primitive set required by the prompt.
- [x] Add a project-local paragraph drawable for width-constrained e-reader text proof.
- [x] Add tests rendering simple Membrane values through the Skia backend into non-empty gray8 output.
- [x] Ensure repeated render calls do not crash and preserve stable dimensions.

### 8. Demo and packaging

- [x] Add `src/clj/ol/membrane_skia_demo.clj`.
- [x] Add packaged `run-membrane-skia-demo.sh` that sets `EINK_SKIA_NATIVE_LIB`, `EINK_FONT_DIR`, and `LD_LIBRARY_PATH`.
- [x] Update `scripts/package-kobo-dist.sh` without making existing Java2D scripts depend on Skia.
- [x] Add tests for package script output and environment setup.

### 9. FBInk present and Kobo smoke

- [x] Implement `eink_skia_present` inside `libclojure_eink_skia.so`, linked directly to FBInk.
- [x] Keep first PoC full-screen present acceptable; avoid overbuilding damage before visible proof.
- [x] Build/package/deploy the dist with safe `rsync` flags.
- [x] Use `tmuxb capture` before all Kobo `tmuxb send` commands.
- [x] Run `./run-membrane-skia-demo.sh --no-wait --no-flash` on Kobo.
- [x] Capture screenshot evidence only after a meaningful visual change.
- [x] Regression-check `./run-membrane-demo.sh --no-wait --no-flash` for Java2D path.

### 10. Documentation and final verification

- [ ] Update status/performance notes if those files exist; otherwise record observations in an appropriate project document or this Ralph file.
- [ ] Record host build/test commands and outputs.
- [ ] Record Kobo build/package/deploy/smoke evidence.
- [ ] Run `bb test` before any completion claim.
- [ ] Re-run Skia-specific acceptance commands after final changes.
- [ ] Summarize risks, known gaps, and next-step recommendations.

## Verification commands

Baseline:

```sh
bb test
```

Host Skia bridge build:

```sh
nix build .#clojure-eink-skia-bridge -o result-skia-native
```

Host tests with Skia bridge:

```sh
EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so \
EINK_FONT_DIR=resources/fonts \
clojure -M:kaocha
```

Kobo bridge build:

```sh
nix build .#clojure-eink-skia-bridge-kobo -o result-kobo-skia-native
```

Package:

```sh
scripts/package-kobo-dist.sh
```

Deploy, only after explicit safety review:

```sh
rsync -rtv --delete --no-owner --no-group --no-perms target/dist/ \
  root@kobo-lan:/mnt/onboard/clojure-eink-demo/
```

Kobo smoke, only through `tmuxb`:

```sh
tmuxb capture
tmuxb send -- '"cd /mnt/onboard/clojure-eink-demo" :Enter'
tmuxb capture
tmuxb send -- '"./run-membrane-skia-demo.sh --no-wait --no-flash" :Enter'
tmuxb capture
```

Java2D regression smoke, only through `tmuxb`:

```sh
tmuxb capture
tmuxb send -- '"cd /mnt/onboard/clojure-eink-demo" :Enter'
tmuxb capture
tmuxb send -- '"./run-membrane-demo.sh --no-wait --no-flash" :Enter'
tmuxb capture
```

## Prep evidence

- Worktree command: `git worktree add .worktrees/skia-membrane-fbink-poc -b skia-membrane-fbink-poc`
- Worktree branch: `skia-membrane-fbink-poc`
- Project setup detection: `deps.edn` + `bb.edn` found; dependencies fetched on first run.
- Baseline command run from worktree project directory: `bb test`
- Baseline result: `29 tests, 94 assertions, 0 failures`.

## Notes for the first loop iteration

- Start by reading `prompts/004-skia-membrane-fbink-poc.md` inside this worktree.
- Compare prompt assumptions with actual files before editing; for example, `PERF_NOTES.md` and `STATUS.md` may not exist in the current checkout.
- Current `nix/pkgs/skia/package.nix` already has raster/text-related flags, but `skia_use_bidi=false` conflicts with the prompt's desired BiDi support and needs investigation.
- Keep implementation batches small; after each batch, update this file with changed paths and verification evidence.

## Section 1 checkpoint notes

> Completed in Ralph iteration 1.

Changed paths for this section:
- `test/clj/ol/membrane/skia_eink_backend_test.clj` (new host Skia ABI loading/pending tests).
- `.ralph/skia-membrane-fbink-poc.md` (this evidence log).

Inventory findings:
- Existing native bridge is `src/native/eink_native.c`; it exports only the old `eink_*` ABI, owns a singleton FBInk context, and presents compact/cropped gray8 through `fbink_print_raw_data`.
- Existing Clojure FFM loading is in `src/clj/ol/project.clj`; it uses `SymbolLookup/libraryLookup`, resolves `eink_init`, `eink_close`, screen-size, `eink_present_gray8`, and `eink_last_error`, and discovers the old library from `EINK_NATIVE_LIB`/`result-native`.
- Existing Membrane backend `src/clj/ol/membrane/eink_backend.clj` remains a Java2D `BufferedImage/TYPE_BYTE_GRAY` renderer and calls `project/present-gray8!`; no input path is present or needed for this rendering-only loop.
- Existing packaging script `scripts/package-kobo-dist.sh` copies `result-kobo-native/lib/libclojure_eink.so` and FBInk, then writes Java2D scripts that set `EINK_NATIVE_LIB`; the Skia script/package path must be added without changing those old script requirements.
- `flake.nix` currently exposes `clojure-eink-fbink-bridge`, `clojure-eink-fbink-bridge-kobo`, aliases `native`/`native-kobo`, and Skia packages `skia-native` (host) and `skia` (ARM cross). It has no `clojure-eink-skia-bridge*` packages yet.
- Current Skia package eval: `nix eval --raw .#skia-native.pname` => `skia-kobo-raster-clang`; version `144-unstable-2025-12-02`; `meta.pkgConfigModules` => `["skia","skia-paragraph"]`.
- Current Skia flags keep raster/no-GPU, `skia_use_freetype=true`, `skia_use_harfbuzz=true`, `skia_use_icu=true`, `skia_enable_skunicode=true`, `skia_use_fontconfig=false`, and build `skia`, `skunicode_core`, `skunicode_icu`, `skshaper`, `skparagraph`.
- BiDi note: package explicitly sets `skia_use_bidi=false`, which conflicts with the prompt wording. Upstream inspection shows `skia_use_icu=true` builds ICU/full-BiDi SkUnicode sources, while `skia_use_bidi=true` adds the separate subset implementation/define; next Skia-package pass should decide whether to flip the flag or document why ICU/full-BiDi satisfies the PoC.
- Custom-directory font note: upstream default `skia_enable_fontmgr_custom_directory = skia_use_freetype && !is_canvaskit`; current package does not set it explicitly, but the `skia` target depends on `:fontmgr_custom_directory` and installed public headers include `include/ports/SkFontMgr_directory.h`. Consider making the flag explicit for clarity.
- Pkg-config note: current metadata exposes only `skia.pc` and `skia-paragraph.pc`; bridge packaging may need direct library/header flags for SkParagraph/SkShaper/SkUnicode and runtime closure copying.
- `STATUS.md` and `PERF_NOTES.md` are absent in this checkout; final notes should remain here or use another appropriate document unless those files are added later.

Test/evidence commands:
- `bb test --focus ol.membrane.skia-eink-backend-test` => `2 tests, 1 assertions, 1 pending, 0 failures` with `EINK_SKIA_NATIVE_LIB` absent.
- `nix build .#clojure-eink-fbink-bridge -o result-native` => built the existing Java2D/FBInk host bridge for red-test evidence only.
- `EINK_SKIA_NATIVE_LIB=result-native/lib/libclojure_eink.so bb test --focus ol.membrane.skia-eink-backend-test/skia-native-library-loads-last-error-symbol-test` => expected RED failure: missing `eink_skia_last_error` from old bridge.
- `unset EINK_SKIA_NATIVE_LIB; bb test` => `31 tests, 95 assertions, 1 pending, 0 failures`.
- `bb fmt:check` was not used as a gate for this section because it reports pre-existing formatting differences across vendored/existing files; the new test file was not listed among formatting failures.

Section 1 blockers: none. Next section: native Skia bridge skeleton and Nix packages.

## Section 2 checkpoint notes

Completed in Ralph iteration 2.

Changed paths for this section:
- `src/native/eink_skia_native.h` (new C ABI header for the v0 `eink_skia_*` surface).
- `src/native/eink_skia_native.cpp` (new C++20 skeleton exporting all v0 symbols, with `eink_skia_last_error` and `-ENOSYS` stubs).
- `nix/pkgs/clojure-eink-skia-bridge/package.nix` (new host/cross native bridge derivation producing `libclojure_eink_skia.so`).
- `flake.nix` (new packages `clojure-eink-skia-bridge` and `clojure-eink-skia-bridge-kobo`).
- `test/clj/ol/membrane/skia_eink_backend_test.clj` (full ABI surface check activated now that the skeleton exports all symbols).
- `.ralph/skia-membrane-fbink-poc.md` (this evidence log).

Implementation notes:
- The skeleton intentionally keeps the Skia bridge separate from the existing Java2D/FBInk `libclojure_eink.so`; it exports only `eink_skia_*` symbols.
- The section 2 derivation compiles only the C++ ABI skeleton and does not yet link Skia or FBInk. Skia/FBInk linkage will be added with the rendering and present implementations in later sections.
- The Kobo artifact was verified as a 32-bit ARM shared object: `ELF 32-bit LSB shared object, ARM, EABI5`.

Test/evidence commands:
- RED before implementation: `EINK_SKIA_NATIVE_LIB=result-native/lib/libclojure_eink.so bb test --focus ol.membrane.skia-eink-backend-test/required-skia-abi-surface-test` => expected failure listing all missing `eink_skia_*` symbols from the old bridge.
- `nix build .#clojure-eink-skia-bridge -o result-skia-native` => success.
- `nm -D --defined-only result-skia-native/lib/libclojure_eink_skia.so | rg 'eink_skia_'` => all 22 required v0 ABI symbols exported.
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so bb test --focus ol.membrane.skia-eink-backend-test` => `2 tests, 3 assertions, 0 failures`.
- `nix build .#clojure-eink-skia-bridge-kobo -o result-kobo-skia-native` => success.
- `file result-kobo-skia-native/lib/libclojure_eink_skia.so` => `ELF 32-bit LSB shared object, ARM, EABI5 version 1 (SYSV), dynamically linked, not stripped`.
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so bb test` => `31 tests, 97 assertions, 0 failures`.

Section 2 blockers: none. Next section: Clojure FFM loading for the Skia bridge.

## Section 3 checkpoint notes

Completed in Ralph iteration 3.

Changed paths for this section:
- `src/clj/ol/membrane/skia_eink_backend.clj` (new Skia-only Java FFM loader namespace).
- `test/clj/ol/membrane/skia_eink_backend_test.clj` (loader behavior tests for env separation, missing library errors, last-error resolution, and full symbol resolution).
- `.ralph/skia-membrane-fbink-poc.md` (this evidence log).

Implementation notes:
- `ol.membrane.skia-eink-backend/default-native-lib` reads `EINK_SKIA_NATIVE_LIB` and Skia-specific local candidates only; tests verify `EINK_NATIVE_LIB` is ignored/reserved for the old Java2D/FBInk bridge.
- `load-native` validates nil/missing paths before FFM lookup and reports clear `ExceptionInfo` messages.
- `load-native` resolves `eink_skia_last_error` first, then reduces over the rest of `native-symbols` to resolve the full v0 ABI into method handles.
- `native-last-error` can already read the C string returned by `eink_skia_last_error`; current skeleton returns an empty string before any failed native call.
- `size_t` is represented as a platform-dependent layout (`JAVA_LONG` on 64-bit JVMs, `JAVA_INT` on 32-bit JVMs) for the future `eink_skia_copy_gray8` downcall.

Test/evidence commands:
- RED before implementation: `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so bb test --focus ol.membrane.skia-eink-backend-test` => expected load error because `ol.membrane.skia-eink-backend` namespace did not exist.
- `cljfmt check src/clj/ol/membrane/skia_eink_backend.clj test/clj/ol/membrane/skia_eink_backend_test.clj` initially reported formatting differences; `cljfmt fix ...` applied only to these two files, then `cljfmt check ...` => `All source files formatted correctly`.
- `unset EINK_SKIA_NATIVE_LIB; bb test --focus ol.membrane.skia-eink-backend-test` => `4 tests, 5 assertions, 0 failures` (native ABI checks skip when env is absent).
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so bb test --focus ol.membrane.skia-eink-backend-test` => `4 tests, 7 assertions, 0 failures`.
- `unset EINK_SKIA_NATIVE_LIB; bb test` => `33 tests, 99 assertions, 0 failures`.
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so bb test` => `33 tests, 101 assertions, 0 failures`.

Section 3 blockers: none. Next section: native gray8 context implementation.

## Section 4 checkpoint notes

Completed in Ralph iteration 4.

Changed paths for this section:
- `src/native/eink_skia_native.cpp` (native gray8 context ownership, create/destroy, geometry accessors, clear, copy, and clear error paths).
- `test/clj/ol/membrane/skia_eink_backend_test.clj` (host FFM tests for context lifecycle, invalid dimensions, clear/copy, undersized copy, and repeated create/destroy).
- `.ralph/skia-membrane-fbink-poc.md` (this evidence log).

Implementation notes:
- `eink_skia_context` now owns compact gray8 `pixels` and `previous_pixels` vectors, dimensions, stride, and a saved default-family string.
- `eink_skia_create` validates positive dimensions and overflow before allocating; initial current and previous buffers are white (`0xFF`).
- `eink_skia_destroy`, `eink_skia_width`, `eink_skia_height`, `eink_skia_stride`, `eink_skia_clear`, and `eink_skia_copy_gray8` now operate on the opaque context.
- Invalid dimensions return `NULL` from create and set `eink_skia_last_error` with `invalid dimensions`.
- `eink_skia_copy_gray8` returns `-EINVAL` for null context/null destination and undersized buffers; undersized copies set an error containing `undersized`.
- Drawing, transform, text, and present functions remain `-ENOSYS` stubs for later sections.

Test/evidence commands:
- RED before implementation: `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so bb test --focus ...native-context-*` => expected failures from `eink_skia_create: not implemented`/`-ENOSYS`.
- `nix build .#clojure-eink-skia-bridge -o result-skia-native` => success after native context implementation.
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so bb test --focus ol.membrane.skia-eink-backend-test/native-context-create-destroy-test --focus ol.membrane.skia-eink-backend-test/native-context-clear-copy-test --focus ol.membrane.skia-eink-backend-test/native-context-invalid-dimensions-test --focus ol.membrane.skia-eink-backend-test/native-context-repeated-create-destroy-test` => `4 tests, 11 assertions, 0 failures`.
- `nix build .#clojure-eink-skia-bridge-kobo -o result-kobo-skia-native` => success after native context implementation.
- `cljfmt check src/clj/ol/membrane/skia_eink_backend.clj test/clj/ol/membrane/skia_eink_backend_test.clj` reported test formatting differences; `cljfmt fix test/clj/ol/membrane/skia_eink_backend_test.clj`, then `cljfmt check ...` => `All source files formatted correctly`.
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so bb test --focus ol.membrane.skia-eink-backend-test` => `8 tests, 18 assertions, 0 failures`.
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so bb test` => `37 tests, 112 assertions, 0 failures`.
- `unset EINK_SKIA_NATIVE_LIB; bb test` => `37 tests, 103 assertions, 0 failures` (native-dependent tests skip when env is absent).

Section 4 blockers: none. Next section: Skia primitive rendering.

## Section 5 checkpoint notes

Completed in resumed Ralph iteration after the iteration-6 handoff.

Changed paths for this section:
- `flake.nix` (passes `skia-native`/`skia` into the host and Kobo Skia bridge packages).
- `nix/pkgs/clojure-eink-skia-bridge/package.nix` (links the bridge against Skia and copies `libsk*.so*` beside `libclojure_eink_skia.so`).
- `src/native/eink_skia_native.cpp` (Skia gray8 surface wrapping and primitive drawing implementation).
- `test/clj/ol/membrane/skia_eink_backend_test.clj` (host tests for visible primitive output and order-stable last-error loading test).
- `.ralph/skia-membrane-fbink-poc.md` (this evidence log).

Implementation notes:
- The Skia bridge derivation now accepts a `skia` input, adds Skia headers, defines `SKIA_DLL`, links `-lskia`, sets an `$ORIGIN` runtime path, and installs Skia shared libraries next to the bridge library.
- `eink_skia_context` now owns a `SkSurfaces::WrapPixels` surface over its native-owned compact gray8 pixel vector with `kGray_8_SkColorType` and `kOpaque_SkAlphaType`.
- The context keeps a `SkCanvas*` and `SkPaint`; save/restore, translate, scale, clip-rect, color, style, stroke-width, rectangle, rounded rectangle, and path drawing are implemented.
- `eink_skia_draw_path` uses `SkPathBuilder` instead of direct `SkPath::moveTo`/`lineTo`/`close` calls because the earlier direct calls left unresolved symbols with the component `libskia.so`.
- The first final verification run found an order-dependent test expectation: `eink_skia_last_error` can retain a previous native error after randomized tests. The loader test now verifies that the symbol is callable and returns a string instead of requiring an empty string.
- Text and present functions remain stubs for later sections.

Test/evidence commands:
- RED before implementation: `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so bb test --focus ...native-draw...` failed as expected with `-ENOSYS` stubs/no dark pixels.
- `nix build .#clojure-eink-skia-bridge -o result-skia-native` => success.
- `ldd -r result-skia-native/lib/libclojure_eink_skia.so | tail -30` => no `undefined symbol` lines; `libskia.so` resolves from the bridge output directory.
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so bb test --focus ol.membrane.skia-eink-backend-test` => `11 tests, 48 assertions, 0 failures`.
- `cljfmt check src/clj/ol/membrane/skia_eink_backend.clj test/clj/ol/membrane/skia_eink_backend_test.clj` => `All source files formatted correctly`.
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so bb test` => `40 tests, 142 assertions, 0 failures`.
- `unset EINK_SKIA_NATIVE_LIB; bb test` => `40 tests, 106 assertions, 0 failures`.
- `nix build .#clojure-eink-skia-bridge-kobo -o result-kobo-skia-native` => success.

Section 5 blockers: none. Next section: font directory and SkParagraph-backed text stack.

## Section 6 checkpoint notes

Completed in Ralph iteration 2 after Section 5 was checkpointed.

Changed paths for this section:
- `resources/fonts/NotoSans.ttf` and `resources/fonts/NotoSerif.ttf` (host-test font bundle copied from nixpkgs `noto-fonts`).
- `resources/fonts/README.md` (font bundle provenance and purpose).
- `nix/pkgs/skia/package.nix` (makes custom-directory font manager explicit, installs required `src/*.h` headers used by SkParagraph public headers, and exports component symbols needed by consumers).
- `nix/pkgs/clojure-eink-skia-bridge/package.nix` (links the bridge against `libskparagraph`, `libskshaper`, and `libskunicode_*` in addition to `libskia`).
- `src/native/eink_skia_native.cpp` (required font directory validation, custom-directory font manager, ICU `SkUnicode`, SkParagraph text bounds and draw implementation).
- `test/clj/ol/membrane/skia_eink_backend_test.clj` (FFM helpers for UTF-8 strings, required-font-directory tests, and SkParagraph bounds/draw visibility tests).
- `.ralph/skia-membrane-fbink-poc.md` (this evidence log).

Implementation notes:
- `eink_skia_create` now requires a non-empty font directory and validates that it exists, is a directory, and contains at least one `.ttf`, `.otf`, or `.ttc` file before creating a context.
- The native context initializes `SkFontMgr_New_Custom_Directory`, `skia::textlayout::FontCollection`, and `SkUnicodes::ICU::Make`; the first discovered font family is used when no default family is passed.
- `eink_skia_text_bounds` and `eink_skia_draw_text_box` now build/layout/paint through `skia::textlayout::ParagraphBuilder`/`Paragraph`; no `SkCanvas::drawSimpleText` placeholder is used.
- The host tests use the bundled Noto fonts via `EINK_FONT_DIR=resources/fonts` and verify positive bounds plus non-white gray8 pixels after paragraph drawing.
- Skia package changes were needed because SkParagraph public headers include `src/core/*`, and because component builds hid SkParagraph C++ symbols unless the focused package compiles the needed components with default visibility.
- `skia_use_bidi` remains `false`; current ICU-enabled SkUnicode build includes full ICU BiDi sources. Revisit if later tests require the separate subset `skunicode_bidi` component.

Test/evidence commands:
- RED before implementation: `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so EINK_FONT_DIR=resources/fonts bb test --focus ol.membrane.skia-eink-backend-test` failed with expected missing font validation and text `-ENOSYS`/missing behavior before native implementation.
- `nix build .#clojure-eink-skia-bridge -o result-skia-native` => success after SkParagraph/font implementation.
- `ldd -r result-skia-native/lib/libclojure_eink_skia.so | tail -40` => no `undefined symbol` lines after adding SkParagraph link libraries and Skia visibility/header fixes.
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so EINK_FONT_DIR=resources/fonts bb test --focus ol.membrane.skia-eink-backend-test` => `13 tests, 63 assertions, 0 failures`.
- `cljfmt check src/clj/ol/membrane/skia_eink_backend.clj test/clj/ol/membrane/skia_eink_backend_test.clj` => `All source files formatted correctly`.
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so EINK_FONT_DIR=resources/fonts bb test` => `42 tests, 157 assertions, 0 failures`.
- `unset EINK_SKIA_NATIVE_LIB EINK_FONT_DIR; bb test` => `42 tests, 108 assertions, 0 failures`.
- `nix build .#clojure-eink-skia-bridge-kobo -o result-kobo-skia-native` => success.
- `file result-kobo-skia-native/lib/libclojure_eink_skia.so` => `ELF 32-bit LSB shared object, ARM, EABI5 version 1 (SYSV), dynamically linked, not stripped`.

Section 6 blockers: none. Next section: Membrane backend and project-local paragraph.

## Section 7 checkpoint notes

Completed in this Ralph iteration.

Changed paths for this section:
- `src/clj/ol/membrane/skia_eink_backend.clj` (high-level Skia Membrane backend, draw protocol implementations, paragraph drawable, render/view helpers, gray8 copy wrapper).
- `test/clj/ol/membrane/skia_eink_backend_test.clj` (RED/GREEN high-level backend tests for API presence, primitive rendering, paragraph rendering, and repeated stable renders).
- `.ralph/skia-membrane-fbink-poc.md` (this evidence log).

Implementation notes:
- Added `open-context!`, `close-context!`, `render-frame!`, `present-frame!`, `render-view!`, `view-element`, `run-loop!`, `run`, and `run-sync` to the Skia backend namespace.
- Added a Skia-specific `IDraw` protocol and registered Membrane default draw implementations without touching vendored `src/clj/membrane/*`.
- Implemented the required Membrane drawing set: `Label`, `Translate`, `WithColor`, `WithStyle`, `WithStrokeWidth`, `Rectangle`, `RoundedRectangle`, `Path`, `Scale`, `ScissorView`, and `ScrollView`.
- Added a project-local `Paragraph` record plus `paragraph`/`paragraph-bounds`; paragraph and label drawing both call the SkParagraph-backed native `eink_skia_draw_text_box`.
- `text-metrics`/`text-bounds` call the native `eink_skia_text_bounds`; label `IBounds` uses Skia only when a Skia context is bound and falls back to the Java2D backend outside that context to avoid breaking existing Java2D Membrane tests.
- `render-frame!` clears the native gray8 surface, draws into the native context, copies compact gray8 bytes back for host tests, and increments `:render-count`.
- `present-frame!` is wired to the native `eink_skia_present` ABI but remains effectively future-facing until Section 9 implements the native FBInk present body.
- During GREEN verification, a `ClassCastException: Cannot cast java.lang.Long to java.lang.Integer` traced to default font weight/slant arguments passed to int FFM parameters; fixed by explicitly returning `int` values from the font weight/slant helpers.

Test/evidence commands:
- RED before implementation: `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so EINK_FONT_DIR=resources/fonts bb test --focus ol.membrane.skia-eink-backend-test/skia-backend-high-level-api-test --focus ol.membrane.skia-eink-backend-test/skia-render-frame-draws-membrane-primitives-test --focus ol.membrane.skia-eink-backend-test/skia-paragraph-drawable-renders-visible-wrapped-text-test --focus ol.membrane.skia-eink-backend-test/skia-render-frame-repeated-stable-dimensions-test` => expected RED: `4 tests, 4 assertions, 4 failures` listing missing high-level vars.
- `cljfmt fix src/clj/ol/membrane/skia_eink_backend.clj test/clj/ol/membrane/skia_eink_backend_test.clj`, then `cljfmt check src/clj/ol/membrane/skia_eink_backend.clj test/clj/ol/membrane/skia_eink_backend_test.clj` => `All source files formatted correctly`.
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so EINK_FONT_DIR=resources/fonts bb test --focus ol.membrane.skia-eink-backend-test` => `17 tests, 73 assertions, 0 failures`.
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so EINK_FONT_DIR=resources/fonts bb test` => `46 tests, 167 assertions, 0 failures`.
- `unset EINK_SKIA_NATIVE_LIB EINK_FONT_DIR; bb test` => `46 tests, 112 assertions, 0 failures` (native-dependent Skia tests skip when env is absent).
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so EINK_FONT_DIR=resources/fonts clojure -M:kaocha` => `46 tests, 167 assertions, 0 failures`.

Section 7 blockers: none. Next section: demo namespace and Kobo packaging script support.

## Section 8 checkpoint notes

Completed in this Ralph iteration.

Changed paths for this section:
- `src/clj/ol/membrane_skia_demo.clj` (new Skia Membrane demo namespace with title, SkParagraph-backed paragraph, rounded action rectangle, and Unicode smoke line).
- `test/clj/ol/membrane_skia_demo_test.clj` (new demo structure and Skia-backend render tests).
- `scripts/package-kobo-dist.sh` (copies Kobo Skia bridge/runtime libs, copies `resources/fonts`, writes `run-membrane-skia-demo.sh`, and documents the Skia smoke command).
- `test/clj/ol/package_kobo_dist_test.clj` (package-script tests for Skia runtime setup and Java2D script env isolation).
- `.ralph/skia-membrane-fbink-poc.md` (this evidence log).

Implementation notes:
- `ol.membrane-skia-demo/demo-ui` builds a fixed-size Membrane value with white background, black title, a project-local `backend/paragraph` body, rounded rectangle/button proof, and `Unicode smoke: Café — Ω`.
- `demo-view` consumes `:container-size` and `:context` from the Skia backend's container-info path so centered text can use Skia text bounds when rendering.
- `-main` reuses `ol.project/parse-args` and opens a Skia backend context; `--present` is accepted for the packaged Kobo command, while `--no-present` works for host smoke before Section 9 present is implemented.
- `scripts/package-kobo-dist.sh` now requires/copies `result-kobo-skia-native/lib/libclojure_eink_skia.so` and `libsk*.so*` beside the existing Java2D native bridge, and copies bundled fonts to `target/dist/fonts`.
- The new packaged `run-membrane-skia-demo.sh` sets only Skia-specific env (`EINK_SKIA_NATIVE_LIB`, `EINK_FONT_DIR`) plus `LD_LIBRARY_PATH`; existing Java2D `run-membrane-demo.sh`/`run-membrane-loop.sh` continue to set `EINK_NATIVE_LIB` and do not depend on Skia env vars.
- A balancing mishap while creating the demo namespace initially left `demo-view`/`-main` inside `demo-ui`; this was caught by the demo tests and fixed before final verification.

Test/evidence commands:
- RED before implementation: `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so EINK_FONT_DIR=resources/fonts bb test --focus ol.membrane-skia-demo-test --focus ol.package-kobo-dist-test/package-script-ships-skia-demo-runtime-test --focus ol.package-kobo-dist-test/java2d-membrane-script-stays-on-old-native-env-test` => expected RED: missing demo vars and missing Skia packaging/runtime script pieces.
- `cljfmt fix src/clj/ol/membrane_skia_demo.clj test/clj/ol/membrane_skia_demo_test.clj test/clj/ol/package_kobo_dist_test.clj`, then `cljfmt check ...` => `All source files formatted correctly`.
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so EINK_FONT_DIR=resources/fonts bb test --focus ol.membrane-skia-demo-test --focus ol.package-kobo-dist-test` => `5 tests, 9 assertions, 0 failures`.
- Host no-present smoke: `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so EINK_FONT_DIR=resources/fonts clojure -M -m ol.membrane-skia-demo --no-present --width 240 --height 160` => rendered `240 x 160` without native present.
- `nix build .#clojure-eink-fbink-bridge-kobo -o result-kobo-native` => success; restored the Java2D Kobo bridge symlink needed by the package script.
- `scripts/package-kobo-dist.sh` => success; packaged `target/dist` with `run-membrane-skia-demo.sh`, `lib/libclojure_eink_skia.so`, `lib/libsk*.so`, and `fonts/NotoSans.ttf`/`NotoSerif.ttf`.
- Dist inspection: `target/dist/run-membrane-skia-demo.sh` exports `EINK_SKIA_NATIVE_LIB`, `EINK_FONT_DIR`, and `LD_LIBRARY_PATH`; dist libs include old `libclojure_eink.so`/`libfbink.so*` and new `libclojure_eink_skia.so`/`libsk*.so`; dist fonts include bundled Noto files.
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so EINK_FONT_DIR=resources/fonts bb test` => `50 tests, 175 assertions, 0 failures`.
- `unset EINK_SKIA_NATIVE_LIB EINK_FONT_DIR; bb test` => `50 tests, 117 assertions, 0 failures`.
- `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so EINK_FONT_DIR=resources/fonts clojure -M:kaocha` => `50 tests, 175 assertions, 0 failures`.

Section 8 blockers: none. Next section: native FBInk present and Kobo smoke. Stop for safety/rollback review before deployment or Kobo-device-changing steps.

## Section 9 checkpoint notes

Completed as a normal interactive Pi task after the Ralph loop was intentionally stopped by the supervisor; no `ralph_done` call was used.
Changed paths so far for this section:
- `src/native/eink_skia_native.cpp` (FBInk lifecycle in Skia context and native full-context `eink_skia_present`).
- `nix/pkgs/clojure-eink-skia-bridge/package.nix` (Skia bridge now accepts/links/copies FBInk in addition to Skia).
- `flake.nix` (passes host/Kobo FBInk packages to the Skia bridge derivation).
- `test/clj/ol/membrane/skia_eink_backend_test.clj` (native present validation test proving invalid geometry is rejected before touching FBInk).
- `scripts/package-kobo-dist.sh` (materializes FBInk soname files as regular files for the project-standard `rsync -rtv` deploy flags).
- `test/clj/ol/package_kobo_dist_test.clj` (package-script assertion for FBInk runtime library handling).
- `prompts/004-skia-membrane-fbink-poc_kobo-smoke-ocp.md` and `prompts/008-skia-kobo-smoke.md` (ignored OCP safety/rollback ledgers for deployment and Kobo smoke; `008` is the active supervisor-requested ledger).
- `.ralph/skia-membrane-fbink-poc.md` (this progress log).

Implementation notes:
- `eink_skia_present` now validates the opaque context and full-context dimensions, initializes FBInk lazily with a per-Skia-context fd/config/state, presents `context->pixels` through `fbink_print_raw_data`, optionally waits with `fbink_wait_for_complete`, and snapshots pixels into `previous_pixels` after a successful present.
- The first native Skia present intentionally accepts only full-context `width`/`height`; partial damage/cropping remains out of scope until after visible proof.
- `eink_skia_destroy` closes the Skia context's FBInk fd if it was opened.
- The Skia bridge derivation links `-lfbink`, installs `libfbink.so*` beside the Skia bridge output, and the Kobo artifact has a `NEEDED` entry for `libfbink.so.1`.
- Packaging initially preserved FBInk symlinks, but the mandated `rsync -rtv` dry-run skipped those symlinks. The package script now removes stale `target/dist/lib/libfbink.so*` and copies them with `cp -L`, producing regular files for `libfbink.so`, `libfbink.so.1`, and `libfbink.so.1.0.0`.

Safety/rollback ledger:
- Created/updated ignored OCP ledger `prompts/004-skia-membrane-fbink-poc_kobo-smoke-ocp.md` during earlier Section 9 work.
- Read and updated the active supervisor-requested ledger `prompts/008-skia-kobo-smoke.md` in iteration 12.
- Recorded scope, exact deployment/smoke commands, rollback plan, local preflight evidence, and the adjusted rsync `--exclude 'src/clj/ol/input/***'` scope.
- No target mutation has been executed.

Current Section 9 status after main rebase and human GO:
- Human reported the Kobo input PoC is now committed on `main` and instructed: rebase the Skia branch against `main`, then GO for deploy.
- Supervisor rebased branch `skia-membrane-fbink-poc` onto `main` commit `8811e01` (`Complete Kobo input POC`) and restored the uncommitted Section 9 changes.
- Current pre-Section-9-commit HEAD after rebase is `3ff28e7` (`Package Skia Membrane demo`).
- Input files now exist in this worktree from `main`: `src/clj/ol/input/evdev.clj`, `src/clj/ol/input/kobo.clj`, and `src/clj/ol/input/runtime.clj`.
- The previous `--exclude 'src/clj/ol/input/***'` deployment plan is obsolete. Use standard project rsync flags with **no input exclude**.
- Proceed through Section 9 deployment/smoke using the active OCP ledger `prompts/008-skia-kobo-smoke.md`. No additional go/no-go is needed for the standard no-exclude plan unless the fresh rsync dry-run still shows unexpected deletes.

Section 9 next steps:
1. Update `prompts/008-skia-kobo-smoke.md` to record the human GO, the rebase onto `main`, and the standard no-exclude rsync plan.
2. Rerun local build/package verification after rebase as needed.
3. Run standard `rsync -rtvn --delete --no-owner --no-group --no-perms target/dist/ root@kobo-lan:/mnt/onboard/clojure-eink-demo/` with no exclude. If it plans to delete `src/clj/ol/input/*`, STOP and send `BLOCKED section 9`.
4. If the dry-run is clean, run remote baseline + local backup, then live rsync deploy with the same standard flags.
5. Use `tmuxb capture` before every Kobo `tmuxb send`. Run the Skia smoke, capture screenshot only after meaningful visual change, then run the Java2D regression smoke.
6. Record command evidence in the OCP ledger and this Ralph document.
7. Stage and commit Section 9 repo changes only; do not commit ignored OCP ledger files unless explicitly asked.
8. Send `DONE section 9` or `BLOCKED section 9` to `cljeink-skia-supervisor` with `link_send` and `triggerTurn:true`.

Section 9 final completion evidence:
- Additional changed paths for final Section 9 work: `src/clj/ol/membrane_skia_demo.clj` (clear SKIA-specific visible copy), `test/clj/ol/membrane_skia_demo_test.clj` (asserts SKIA-specific demo text), `scripts/package-kobo-dist.sh` (copies non-glibc Nix runtime closure libraries as regular files), and `test/clj/ol/package_kobo_dist_test.clj` (package-script assertions for closure copying/deduplication).
- Root cause found during Kobo smoke: `SymbolLookup/libraryLookup` could not load `libclojure_eink_skia.so` because the dist lacked transitive Skia text-shaping runtime libraries (`libharfbuzz.so.0` first, plus ICU/freetype/png/zlib/libstdc++/libgcc dependencies). The package script now copies non-glibc `nix-store -qR` closure libraries into `target/dist/lib` with `cp -L` and removes duplicate basename files before copying.
- Human requested clearer Skia visual copy after seeing the Java2D `Membrane on FBInk` screen. The Skia demo now renders title `SKIA renderer on FBInk`, body text explicitly saying it is on the SKIA path, and button `Rendered by Skia`.
- Safety/rollback ledger: `prompts/008-skia-kobo-smoke.md` (ignored) records GO/no-exclude deployment scope, backup `target/kobo-backups/clojure-eink-demo-20260531T165156Z`, dry-runs, live deploys, smoke commands, screenshots, and rollback plan.
- Deploy evidence: standard no-exclude `rsync -rtv --delete --no-owner --no-group --no-perms target/dist/ root@kobo-lan:/mnt/onboard/clojure-eink-demo/` succeeded. Initial deploy evidence in `target/rsync-skia-section9-deploy.txt`; closure-complete redeploy in `target/rsync-skia-section9-closure-deploy.txt`; final text-update deploy in `target/rsync-skia-section9-text-update-deploy.txt`.
- Kobo Skia smoke evidence: after closure-complete deploy, `./run-membrane-skia-demo.sh --no-wait --no-flash` printed `starting Skia Membrane render 800x600`, `finished Skia Membrane render`, and `presented Skia Membrane demo 800 x 600 via /mnt/onboard/clojure-eink-demo/lib/libclojure_eink_skia.so`. After the copy update, the same command succeeded again.
- Screenshot evidence: `screenshots/kobo-screen-20260531-191453.png` showed the first Skia screen; `screenshots/kobo-screen-20260531-192727.png` shows the final clear SKIA-specific screen with title `SKIA renderer on FBInk` and button `Rendered by Skia`.
- Java2D regression evidence: `./run-membrane-demo.sh --no-wait --no-flash` printed `starting Membrane render 1264x1680`, `finished Membrane render`, and `presented Membrane demo 1264 x 1680 via /mnt/onboard/clojure-eink-demo/lib/libclojure_eink.so mode full` both before and after the final text-update deploy.
- Required rebuild/package evidence after package-used changes: `nix build .#clojure-eink-fbink-bridge-kobo -o result-kobo-native`, `nix build .#clojure-eink-skia-bridge-kobo -o result-kobo-skia-native`, `nix build .#clojure-eink-skia-bridge -o result-skia-native`, and `scripts/package-kobo-dist.sh` all succeeded after the Skia copy/package-script changes.
- Local verification evidence: `cljfmt check src/clj/ol/membrane/skia_eink_backend.clj src/clj/ol/membrane_skia_demo.clj test/clj/ol/membrane/skia_eink_backend_test.clj test/clj/ol/membrane_skia_demo_test.clj test/clj/ol/package_kobo_dist_test.clj` => `All source files formatted correctly`; focused Skia/package tests => `23 tests, 87 assertions, 0 failures`; `EINK_SKIA_NATIVE_LIB=result-skia-native/lib/libclojure_eink_skia.so EINK_FONT_DIR=resources/fonts bb test` => `73 tests, 214 assertions, 0 failures`; `unset EINK_SKIA_NATIVE_LIB EINK_FONT_DIR; bb test` => `73 tests, 152 assertions, 0 failures`.
- Section 9 blockers: none remaining. Next section: documentation/final verification.
