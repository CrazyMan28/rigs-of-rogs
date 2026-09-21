# Render API decision: DirectX 9 → DirectX 12

**Status:** research complete — all four required experiments run, including the D3D11 smoke
test and the translation-layer benchmark. Recommendation pending owner confirmation.
**Issue:** [#2](https://github.com/CrazyMan28/rigs-of-rogs/issues/2) · **Epic:** [#1](https://github.com/CrazyMan28/rigs-of-rogs/issues/1)
**Audited against:** this checkout, `master` @ `4c607c7f6`, OGRE **1.11.6.1** (`conanfile.py:25`)

> Every load-bearing count in this document is re-derivable. Run
> `tools/verify-rendering-api-audit.sh`; it re-computes the **40** tree-dependent figures it
> lists and exits non-zero if any has drifted. It is a manual check — no CI job runs it. The
> tree moves: do not trust a number here that the script no longer confirms.

---

## The answer, in plain language

**No — you cannot upgrade Rigs of Rods to DirectX 12, and the reason has nothing to do with
how much work you are willing to spend.** RoR renders through OGRE, and *no version of OGRE
has a DirectX 12 backend at all* — not the 1.x line this fork pins, and not OGRE-Next. There
is nothing to switch on and nothing to upgrade to. The only route to literal DX12 is to write
a Direct3D 12 render system for OGRE yourself, from scratch — roughly two engineer-years
of specialist graphics work, permanently maintained by this fork alone, and it would still not
make the game look or run better by itself.

**But you can run RoR on DirectX 12 today, and it was measured — it just isn't worth it.**
Windows already ships `d3d9on12.dll`, which runs RoR's existing DirectX 9 calls on a DirectX 12
driver with no code changes and no rebuild. It works: the game runs correctly that way
(Experiment 3). It is also **not faster** — roughly 28% slower than a healthy D3D9 path, though
it never had a bad round, which D3D9 did. The translation layer that *is* faster maps D3D9 onto
**Vulkan**, not DX12 — DXVK ran 36% faster than native on median frame time and was faster in
**all five** test rounds. So the honest answer to "should we move to DX12" is: you can, cheaply,
and it buys you nothing — but there is a free speed-up next door. The genuine engine-side modernization step is **DirectX 11**, whose render system is already
present in the source tree and merely switched off. Switching it on is *not* the one-line
change it appears to be: it was tried (Experiment 2) and **the game crashes during startup**,
before it renders a single frame.

### How the "no DirectX 12" claim was verified

This is the load-bearing claim, so it was checked against OGRE's own sources rather than taken
on faith — including at the exact version this fork pins:

| Checked | Result |
|---|---|
| [`OGRECave/ogre/RenderSystems`](https://github.com/OGRECave/ogre/tree/master/RenderSystems) (1.x line, `master`) | `Direct3D11, Direct3D9, GL, GL3Plus, GLES2, GLSupport, Metal, Tiny, Vulkan` |
| Same, at tag **`v1.11.6`** — the pinned version | `Direct3D11, Direct3D9, GL, GL3Plus, GLES2, GLSupport` — note: **no Vulkan yet** |
| [`OGRECave/ogre-next/RenderSystems`](https://github.com/OGRECave/ogre-next/tree/master/RenderSystems) (`master`) | `Direct3D11, GL3Plus, GLES2, Metal, NULL, Vulkan` |
| Same, at branch `v3-0` (latest release line) | `Direct3D11, GL3Plus, GLES2, Metal, NULL, Vulkan` |
| All branches of `OGRECave/ogre` | only `master` and `gh-pages` — no D3D12 work in progress |
| All 15 branches of `OGRECave/ogre-next` (`v2-0`…`v3-0`, `ParticleFX2`, …) | none D3D12-related |
| Historical tags `v1.12.13`, `v13.0.0`–`v13.6.0`, `v14.0.0` | no `Direct3D12` directory at any of them |
| Commit / code search for `Direct3D12` / `D3D12` | 0 hits in `ogre`; in `ogre-next`, only docs and comments |
| Maintainer statement | [ogre-next#417](https://github.com/OGRECave/ogre-next/issues/417) (2023-09-27), darksylinc: *"There are no current plans for D3D12 support."* |

**No Direct3D 12 backend exists on any branch, tag or release line of either project, none is
in progress, and the OGRE-Next lead has said there are no plans for one.** If this ever becomes
false, the recommendation below must be revisited first.

---

## What the audit found

The starting-point audit in issue #2 was re-verified line by line. Confirmed:

| Claim | Status |
|---|---|
| Renderer is OGRE 1.11.6.1, the 1.x line (`conanfile.py:25`) | ✅ confirmed |
| `source/main/plugins.cfg.in` offers D3D9, D3D11, GL, GL3Plus — no D3D12 entry | ✅ confirmed |
| `source/main/CMakeLists.txt:496-497` unconditionally comments out D3D11 and GL3Plus | ✅ confirmed |
| `source/main/CMakeLists.txt:493-494` comments out GL on Windows → a Windows build loads D3D9 only | ✅ confirmed |
| Runtime render-system selection already works (`AppContext.cpp:291-298`, `GUI_GameSettings.cpp:143-157`) | ✅ confirmed |
| `Plugin_CgProgramManager` loaded unconditionally | ✅ confirmed |
| `REQUIRED_DEPS_VERSION 30` (root `CMakeLists.txt:19`) | ✅ confirmed |

**One correction.** Issue #2 states "exactly two places branch on render-system name."
There are **three**:

- `source/main/gfx/HydraxWater.cpp:78` — picks HLSL vs GLSL shader mode; **already handles
  `"Direct3D11 Rendering Subsystem"`.**
- `source/main/gui/imgui/OgreImGuiOverlay.cpp:285` — `mConvertToBGR` for D3D9 only; correct
  under D3D11 as written.
- `source/main/terrain/TerrainGeometryManager.cpp:472` — **missed by the original audit.**
  Exact-matches `"OpenGL Rendering Subsystem"` to force normal/specular mapping on
  ("Fix for OpenGL, otherwise terrains are black"). Harmless under D3D11, which takes the
  `else` branch like D3D9 — but it is an *exact* string compare, and the names OGRE actually
  reports are `"OpenGL Rendering Subsystem"` (GL), `"OpenGL 3+ Rendering Subsystem"` (GL3Plus)
  and `"Vulkan Rendering Subsystem"` (Vulkan), verified in `OgreGLRenderSystem.cpp`,
  `OgreGL3PlusRenderSystem.cpp` and `OgreVulkanRenderSystem.cpp`. Neither of the latter two
  matches. **Any move from GL to GL3Plus or Vulkan (Options B and C) reintroduces black
  terrain on Linux until this line is fixed.**

The engine needs no new plumbing to *run* on another API. The obstacle is entirely in the
shader and material layer.

---

## Experiment 1 — Cg inventory (the number that decides everything)

RoR's materials are built on NVIDIA **Cg**, which NVIDIA discontinued; the final release, Cg
3.1, shipped in **April 2012**, and NVIDIA directs new work to GLSL or HLSL
([Cg Toolkit](https://developer.nvidia.com/cg-toolkit)). It is still a hard build dependency —
`.github/workflows/linux-native.yml` installs `nvidia-cg-dev`.

Measured across `resources/`:

| Figure | Count |
|---|---|
| Cg program declarations (45 fragment + 27 vertex) | **72** |
| Files declaring at least one Cg program | **17** |
| Cg declarations naming a **D3D11-capable** profile (`vs_4_0`/`ps_4_0`/`vs_5_0`/`ps_5_0`/`hlslv`/`hlslf`) | **5** |
| …of those 5, how many are RoR's own content rather than OGRE's bundled files | **0** |

Concentration: `caelum/` 10 files, `materials/` 4, `managed_materials/` 2, `OgreCore/` 1.

**This is not peripheral.** `resources/managed_materials/` is RoR's managed-material system,
imported by 14 further `.material` files. Its `BaseTechnique` inherits
`Shadows/managed/base_receiver`, which resolves to `PSSM/shadow_receiver_vs` /
`PSSM/shadow_receiver_ps` (`shadows/pssm/on/shadows.material:8-9`) — Cg programs declaring
`vs_1_1 arbvp1` and `ps_2_x arbfp1` (`shadows/pssm/on/depthshadows.program:33,53`). Ordinary
vehicle rendering with shadows on therefore depends on Cg.

(`nicemetal_mm.program` is Cg-only too, but it is the *opt-in alternate* material — gated on
`gfx_alt_actor_materials`, which defaults to `"false"` at `CVar.cpp:209` — so it is not the
core path and is not the argument here.)

### Does the D3D11 render system run them? Mostly no — and this inverts the issue's expectation

The good news first: OGRE's Cg plugin **is** D3D11-capable. `PlugIns/CgProgramManager/src/OgreCgProgram.cpp`
recognises `vs_4_0`/`ps_4_0` (Cg ≥ 2.2) and `vs_5_0`/`ps_5_0` (Cg ≥ 3.0) and, for those
profiles, builds an **HLSL delegate program** rather than D3D9 assembly. Cg 3.1 is new enough
to emit them. `CgProgramManager` is still present in OGRE `master` today.
**Verified at tag `v1.11.6`** — the delegate branch is `CgProgram::createLowLevelImpl()` at
`OgreCgProgram.cpp:442-459` in the pinned version, not just in current `master`.

The bad news is what RoR actually declares. Every `profiles` line in the tree:

```
count  profile list                        count  profile list
   24  profiles ps_2_0 arbfp1                  3  profiles ps_2_0 arbfp1 fp30
   12  profiles vs_1_1 arbvp1                  2  profiles vs_3_0 vp40 arbvp1
    8  profiles ps_2_x arbfp1                  2  profiles vs_2_0 arbvp1 vp30
    5  profiles vs_2_0 arbvp1                  1  profiles vs_4_0 vs_2_0 vs_1_1 arbvp1
    5  profiles ps_3_0 arbfp1                  1  profiles vs_2_x arbvp1 vp30
    4  profiles vs_4_0 vs_1_1 arbvp1           1  profiles ps_2_x arbfp1 fp30
    4  profiles ps_3_0 fp40 arbfp1
                                             ——— 13 distinct lists, 72 declarations
```

Every entry is either a **D3D9-era Shader Model 1–3 profile** or an **OpenGL ARB/NV profile**
(`arbvp1`, `arbfp1`, `vp30`, `vp40`, `fp40`). The only `vs_4_0` mentions are the five in
`resources/OgreCore/StdQuad_vp.program` — OGRE's own bundled compositor quads. **Not one
fragment program anywhere declares `ps_4_0`, and not one RoR-authored program declares any
D3D11-capable profile.**

**What actually happens, and it is decisive.** The Cg plugin has three outcomes, not two
(`OgreCgProgram.cpp` @ `v1.11.6`):

1. **`hlslv`/`hlslf`/`glslv`/`glslf`/`glslg`** — the only profiles that set `useDelegate` in
   `selectProfile()` (line 43). These produce a genuine delegate program. **RoR declares none.**
2. **`vs_4_0`/`ps_4_0`/`vs_5_0`/`ps_5_0`** (plus `ds_5_0`/`hs_5_0`) — `createLowLevelImpl()`
   (line 442) builds an **HLSL high-level program** into `mAssemblerProgram`. Not a delegate,
   but it works on D3D11. **RoR declares 5, all in OGRE's own bundled file.**
3. **Everything else** — `GpuProgramManager::createProgramFromString(..., mSelectedProfile)`,
   i.e. a **D3D9-era low-level assembly program**.

Outcome 3 is where 67 of RoR's 72 declarations land, and D3D11 does not merely lack a path for
them — it refuses them explicitly. `OgreD3D11GpuProgramManager.cpp` returns a
`D3D11UnsupportedGpuProgram` from both `createImpl` overloads, and loading one throws:

```cpp
String message = "D3D11 dosn't support assembly shaders. Shader name:" + mName + "
";
OGRE_EXCEPT(Exception::ERR_RENDERINGAPI_ERROR, message, ...);
```

**That exception is the predicted result of Experiment 2**, repeated once per Cg program.

A caveat worth stating, because it cuts *against* an earlier draft of this document: the
legacy syntaxes largely **are** registered. Under `#define SUPPORT_SM2_0_HLSL_SHADERS 1`
(`OgreD3D11RenderSystem.h:49`, identical at `v1.11.6` — a hard `#define`, not a build option),
D3D11 registers `vs_2_0`, `vs_2_a`, `vs_2_x`, `vs_3_0`, `ps_2_0`, `ps_2_a`, `ps_2_b`,
**`ps_2_x`**, `ps_3_0` and `ps_3_x`. That define exists precisely so SM2-era shaders reach
D3D11 "directly or via Cg", per its own comment. **`vs_1_1` is the only profile RoR uses that
is never registered** — 12 declarations, which fail to resolve at all. The other 55 resolve
happily, compile to assembly, and then throw at load. Both roads end in the same place; only
the first one is about profile registration.

### And there is a second, larger problem: fixed-function materials

OGRE's D3D11 render system **has no fixed-function pipeline**. This is not an inference — at
tag `v1.11.6`, `OgreD3D11RenderSystem.cpp:927-928` reads:

```cpp
// Does NOT support fixed-function!
//rsc->setCapability(RSC_FIXED_FUNCTION);
```

D3D9 sets that capability (`OgreD3D9RenderSystem.cpp:922`); D3D11 and GL3Plus never do.
Materials without shaders are therefore rendered only via the RTShaderSystem, which
auto-generates them. In this tree:

- **32 of 48** `.material` files contain no `vertex_program_ref`/`fragment_program_ref`
  *in the file itself*. Read that as an upper bound, not a count of fixed-function materials:
  OGRE inherits techniques across files, and ~14 of the 32 `import` from
  `managed_mats.material` and pick up the PSSM shader technique above when shadows are on. It
  is also a **file** count, not a material count — `eurosigns.material` alone defines 76
  materials — so it does not measure how much content is affected.
- **RTSS is unwired, not merely disabled.** `gfx_enable_rtshaders` is declared
  (`Application.cpp:269`), externed (`Application.h:815`) and created with default `"false"`
  (`CVar.cpp:208`) — and **read by nothing**. Those are its only three references in `source/`.
- `Ogre::RTShader::ShaderGenerator::initialize()` is **never called anywhere in `source/`**. The
  only RTSS uses at all are two `getSingleton()` calls in `TerrainObjectManager.cpp:808-809`,
  for terrain objects with `mat_name_generate` — reached without an initialised singleton.

  So Option A cannot "turn RTSS on"; there is no switch. RTSS has to be stood up from nothing:
  initialise the generator, attach it to the scene manager and viewport, and register a material
  scheme listener game-wide. (The two existing `getSingleton()` call sites look like a latent bug
  independent of this decision, and are worth a separate issue.)

One point in favour: `resources/rtshader/` already ships **9 HLSL** FFPLib variants alongside
9 Cg and 9 GLSL, so RTSS itself has a working D3D11 path. It just isn't turned on.

**Conclusion: flipping `source/main/CMakeLists.txt:496` yields a game that starts on D3D11 and renders
almost nothing correctly.** Option A is real and worthwhile, but it is a shader-and-materials
project, not a build-flag change.

---

## Experiment 2 — D3D11 smoke test: RUN, and it crashes

**Correction to an earlier revision of this document.** It claimed these experiments could not
be run because no toolchain and no content were available. Both claims were wrong:

- **Visual Studio Build Tools 2026 (MSVC 14.51) and Windows SDK 10.0.26100 were already
  installed** — the earlier check looked under `Program Files` and missed
  `Program Files (x86)/Microsoft Visual Studio/18/BuildTools`.
- **`content/` is not empty, it is an uninitialised git submodule**
  (`RigsOfRods/content.git`, 5 MB). `git submodule update --init content` yields the
  `simple2` terrain plus the `agora` and `dafsemi` vehicles — enough for a fixed scene.

Only CMake and Conan were actually missing. With those added, the game builds and runs, and
both experiments were performed. Method is recorded in §"How to reproduce" below.

### Result: D3D11 does not start. It crashes before it reaches the shader layer.

Flipping `source/main/CMakeLists.txt:496` and rebuilding does ship the plugin — the generated
`plugins.cfg` gains `Plugin=RenderSystem_Direct3D11`, and `RenderSystem_Direct3D11.dll` is
already copied into the runtime directory by the existing build, so **no packaging work is
needed at all**. Selecting it produces, reproducibly (2 of 2 runs, exit `0xC000041D`):

```
Ogre::RenderingAPIException: D3D11 device cannot copy a subresource - source and dest
size are not the same and they have to be the same in DX11.
  in D3D11HardwarePixelBuffer::blitFromMemory at OgreD3D11HardwarePixelBuffer.cpp (line 333)
```

Triggered while loading OGRE's built-in 8×8 `Warning` texture during Overlay/Font
initialisation, immediately after `Registering ResourceManager for type Font`.

**This inverts this document's own prediction.** The analysis above predicted the first failure
would be Cg programs hitting `D3D11UnsupportedGpuProgram`. It is not. The Cg plugin never gets
that far — the log shows only `Installing plugin: Cg Program Manager`, with no program ever
compiled. **The Cg problem is real but it is the *second* blocker, not the first.**

**Root cause**, traced in the OGRE source:

- `D3D11HardwarePixelBuffer::blitFromMemory` throws unconditionally when source and destination
  dimensions differ — D3D11 requires an exact-size copy, whereas the D3D9 backend performs a
  scaling blit happily.
- RoR calls `Ogre::TextureManager::setDefaultNumMipmaps(5)` (`main.cpp:145` and
  `ContentManager.cpp:236`), so every texture requests 5 mip levels. Under D3D9 the `Warning`
  texture loads natively as `PF_R5G6B5` with no mip generation; under D3D11 it is converted to
  `PF_A8B8G8R8` **with 3 generated mipmaps**, and that mip upload is the mismatched blit.
- **This limitation is still present in OGRE `master`** (same `OGRE_EXCEPT`, now at
  `OgreD3D11HardwarePixelBuffer.cpp:280`), so it is not something a version bump fixes.

It is a RoR-side setting meeting a standing OGRE D3D11 limitation, so it *is* fixable — but it
is a third work item for Option A that nobody had counted, and it sits *ahead* of the Cg work.

---

## Experiment 3 — translation-layer benchmark: RUN

Raw per-run data: [`doc/rendering-api-benchmark-data.csv`](rendering-api-benchmark-data.csv).
Scene, hardware and method are in §"How to reproduce".

**Design note, because the first attempt was wrong.** Earlier batches ran all of one
configuration, then all of the next. Between those batches the machine's own baseline shifted
by roughly 3× (native median 2.08 ms → 0.85 ms) as it cooled down from the dependency build.
That confounds time with configuration, so those batches were discarded rather than reported.
The numbers below come from an **interleaved** design: each round runs all three
configurations back-to-back, five rounds, so slow drift hits all three about equally. Each
configuration also got one discarded warm-up first, and the wrapper's identity was re-verified
by file size immediately before every launch.

### Results — 5 interleaved rounds

Median frame time, per round (ms) — read the rows, not just the summary:

| round | native D3D9 | D3D9On12 (DX12) | DXVK (Vulkan) |
|---|---|---|---|
| 1 | 0.821 | 1.056 | **0.538** |
| 2 | 0.824 | 1.040 | **0.528** |
| 3 | 0.840 | 1.078 | **0.538** |
| 4 | **1.574** | 1.044 | **0.566** |
| 5 | **1.433** | 1.076 | **0.563** |
| **spread** | **0.753** | **0.038** | **0.038** |

| Configuration | median | 1%-low | *median* worst frame | **true worst frame** | median FPS |
|---|---|---|---|---|---|
| native D3D9 | 0.840 ms | 1.917 ms | 4.810 ms | 11.353 ms | 1190 |
| D3D9On12 (**DirectX 12**) | 1.056 ms | 2.107 ms | 6.028 ms | **7.977 ms** | 947 |
| DXVK (**Vulkan**) | **0.538 ms** | **1.381 ms** | 3.556 ms | 11.384 ms | **1859** |

Note the last two columns disagree, and the distinction matters. The *median* worst frame
flatters DXVK; the **true** worst frame across all five rounds is **D3D9On12's 7.977 ms** — the
best of the three — with DXVK's 11.384 ms the single worst value in the dataset. DXVK wins
decisively on typical frames and loses on the tail's tail.

Paired against native *within each round*:

| | median frame time | 1%-low | consistency |
|---|---|---|---|
| D3D9On12 | +26.2% median of deltas | +6.3% | **mixed** — slower in rounds 1–3, faster in 4–5 |
| DXVK | **−36.0%** | **−29.9%** | faster in **5 of 5** rounds |

### What this actually says

1. **All three configurations run the game correctly.** Rigs of Rods renders fine on a
   DirectX 12 driver path and on a Vulkan one, with no code changes and no installation —
   just one DLL beside the executable. The owner's literal question — *can this run on
   DirectX 12* — is answered **yes, today**, and it was measured, not argued.

2. **But DirectX 12 is not the fast one, and the comparison is not a single number.** Native
   D3D9 was **bimodal**: ~0.83 ms in rounds 1–3, then ~1.50 ms in rounds 4–5. D3D9On12 sat at a
   near-constant 1.05 ms throughout. So D3D9On12 is **~28% slower than native at its best and
   ~30% faster than native at its worst** — the headline "+26%" is just where the median of the
   per-round deltas happens to land, and quoting it alone would be misleading. **D3D9On12 never
   beats a healthy D3D9 path; it is simply immune to whatever degraded it.**

   *Rounds 4 and 5 were disturbed, and this document should not pretend otherwise.* An earlier
   revision claimed the degradation was native-only and therefore "not machine-wide". That was
   wrong, and the shipped CSV refutes it: **all three configurations lost average FPS in rounds
   4–5** — native −20.2%, DXVK −19.5%, D3D9On12 −16.5% — and DXVK's tail degraded as badly as
   native's (worst frame +157% vs native's +151%). Something disturbed the machine.

   What survives that correction is narrower but still real: **native's *median* frame time was
   uniquely sensitive** to the disturbance (+81%, 0.83 → 1.50 ms) while both wrappers' medians
   moved under 3%. And **D3D9On12's tail was the only one that did not degrade at all** (worst
   frame actually *improved* 25%).

3. **DXVK — Vulkan, not DirectX 12 — is the only configuration that is clearly faster**, and it
   won every single round on both median and 1%-low. If the goal behind "upgrade to DX12" is
   "make it faster on a modern driver", **Vulkan via DXVK is the option that delivers it.**

4. **The clean comparison is rounds 1–3**, before the disturbance. There the picture is
   unambiguous and tight: native 0.824 ms, D3D9On12 1.056 ms, DXVK 0.538 ms — DXVK **−35%**
   against native, D3D9On12 **+28%**, and DXVK also holds the best true worst frame
   (3.556 ms vs native's 4.810 ms and D3D9On12's 7.977 ms). Rounds 4–5 do not change that
   ranking; they only add the observation that native's median is the most fragile of the three
   under load, and that D3D9On12's tail is the most robust.

### The caveat that limits all of the above

**This scene is far too light to predict gameplay performance.** One vehicle on `simple2` at
1280×720 runs at **950–1860 FPS**; the GPU is effectively idle and what is being measured is
**CPU-side API and driver overhead**. That is exactly the thing a translation layer changes, so
the comparison is meaningful *as an overhead measurement* — but it is not a frame-rate
prediction for a loaded scene with many vehicles, heavy terrain and shadows, where the GPU
becomes the constraint and these rankings could change or compress to nothing. Anyone acting on
Option E should re-measure on a representative scene before committing. The content submodule
ships only `simple2`, `agora` and `dafsemi`, which is not enough to build one.

## Experiment 4 — OGRE-Next call-site count

Mechanical count of OGRE API call sites that OGRE-Next changes (`SceneManager`, `Entity`,
`SceneNode`, `Material`/`Technique`/`Pass`/`TextureUnitState`, `Compositor`, `ParticleSystem`,
`BillboardSet`, `ManualObject`, `HardwareBuffer*`, `RenderTarget`/`RenderWindow`, `Viewport`,
`Camera`, `TextureManager`):

| Scope | Call sites | Files |
|---|---|---|
| `source/main/gfx/` | **1,532** | 87 of 130 |
| `source/main/` (whole game) | **2,655** | **173 of 450** |
| …of which `Material`/`Technique`/`Pass`/`TextureUnitState` — the Hlms rewrite surface | **1,289** | — |

For scale: `source/main/gfx/` is 39,950 lines; `source/main/` is 200,801.

**Read these as matching source lines, not as "OGRE calls in RoR's game code."** Two caveats,
both verified:

- **About 49% is vendored third-party code**: `source/main/gfx/hydrax/` accounts for 903 of the
  2,655 and vendored `Ogre*.cpp`/`Ogre*.h` files for another 408.
- **Hydrax ships its own `MaterialManager` and `TextureManager` classes**
  (`gfx/hydrax/MaterialManager.h:44`, `TextureManager.h:45`), so not every hit is an OGRE
  symbol at all — only 77 of 439 `MaterialManager` lines are spelled `Ogre::MaterialManager`.

This does not shrink Option C: vendored Hydrax, Caelum, PagedGeometry and SkyX all have to be
ported to OGRE-Next too, and they are the *least* pleasant part of it. But the honest
characterisation is "lines that a port has to look at", not "OGRE API calls in RoR".

---

## How to reproduce these measurements

Per §9 of issue #2, every measurement names its scene and hardware.

**Hardware / OS:** NVIDIA GeForce RTX 4070 Laptop GPU (driver 32.0.16.1692) with an AMD Radeon
integrated GPU also present; Windows 11 Pro 10.0.26200.

**Toolchain:** Visual Studio Build Tools 2026 (MSVC 14.51.36231), Windows SDK 10.0.26100,
CMake 4.4.3, Conan 2.32.0. Conan has no prebuilt binaries for `compiler.version=195`, so the
dependency graph builds from source; it completes without errors.

**Build:**

```sh
git submodule update --init content          # content/ is a submodule, not empty
conan remote add rigs-of-rods-deps https://nexus.anotherfoxguy.com/repository/rigs-of-rods/ -f
cmake . -GNinja -DCMAKE_BUILD_TYPE=Release -Bbuild       -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=cmake/conan_provider.cmake       -DCMAKE_INSTALL_PREFIX=redist -DROR_CREATE_CONTENT_FOLDER=ON
cd build && ninja install
```

**Scene — identical for every run:** terrain `simple2.terrn2`; **one** vehicle,
`b6b0UID-semi.truck` (dafsemi), entered; 1280×720 windowed; **VSync off**; FPS limit 0
(`gfx_fps_limit` default). Settings otherwise default, and unchanged between runs.

**Harness:** `tools/rorbench.as`, run via RoR's own `-runscript`. It discards a 20-second
warm-up (terrain streaming, shader and material compile, cache fill), then samples per-frame
delta time for 60 seconds, reports median / 1%-low / best / worst, and quits. The 1%-low is the
mean of the slowest 1% of frames.

```sh
RoR.exe -terrain simple2.terrn2 -truck b6b0UID-semi.truck -enter -runscript rorbench.as
```

Results are written to `RoR.log`, prefixed `BENCH|`.

**Translation layers** are selected by dropping a `d3d9.dll` next to `RoR.exe` — nothing is
installed system-wide and nothing is written to the registry:

- **native D3D9** — no `d3d9.dll` present.
- **D3D9On12** — the wrapper from [narzoul/ForceD3D9On12](https://github.com/narzoul/ForceD3D9On12)
  v1.0.0 (`x64/d3d9.dll`), which forces the D3D9 runtime onto Windows' own `d3d9on12.dll`.
  Verified active by module inspection: the process loads `d3d9on12.dll`, `d3d12.dll` and
  `D3D12Core.dll`.
- **DXVK** — [doitsujin/dxvk](https://github.com/doitsujin/dxvk) v3.1.1 (`x64/d3d9.dll`).
  Verified active by its own `RoR_d3d9.log` (`DXVK: v3.1.1`, device `NVIDIA GeForce RTX 4070`).

Each configuration ran one discarded warm-up plus three recorded runs, with the wrapper's
identity re-verified by file size immediately before every launch.

## The five options

### Option A — enable the D3D11 render system already in the tree

|  |  |
|---|---|
| **Possible?** | **Yes.** The plugin exists, is built, and is switched off by one CMake line. |
| **Effort** | **8–20 engineer-weeks.** See the note below on why the floor is not lower. |
| **Buys** | A supported, modern-driver API. Removes the D3D9 deprecation risk. Keeps OGRE, keeps the fork close to upstream. The necessary first step of *any* real modernization. |
| **Breaks** | **Measured: the game crashes during startup before rendering anything** (Experiment 2) — a mipmap blit D3D11 refuses. Behind that: 67 of 72 Cg declarations cannot bind, and 32 of 48 materials are fixed-function needing RTSS, which is not merely off but **unwired**. |
| **Maintenance** | Low. Upstream OGRE maintains the backend; the work is one-time. |

Work, in the order the blockers actually appear:

1. **Fix the startup crash** (Experiment 2). Either stop requesting generated mipmaps for
   textures whose upload path D3D11 rejects, or route mip generation through
   `TU_AUTOMIPMAP`/GPU generation instead of `blitFromMemory`. This is the first thing that
   happens and nothing else can be tested until it is done.
2. **Stand RTSS up from nothing** — initialise `ShaderGenerator`, attach it to the scene manager
   and viewport, wire `gfx_enable_rtshaders` to something, and register the material-scheme
   listener across the game rather than only for terrain objects.
3. **Give the 67 Cg declarations a D3D11-capable profile** (`vs_4_0`/`ps_4_0`, or
   `hlslv`/`hlslf`), then fix the SM2/SM3-era Cg that fails to compile at SM4 — texture
   sampling and semantics are the usual casualties.
4. Uncomment `source/main/CMakeLists.txt:496`. **Nothing else is needed to ship the plugin** —
   `RenderSystem_Direct3D11.dll` is already copied into the runtime directory by the existing
   build, as Experiment 2 confirmed.

**On the estimate:** an earlier draft said 4–8 weeks, on the assumption that the first failure
would be shaders. Experiment 2 disproved that — the game does not reach the shader stage at
all, so there is a whole blocker ahead of the work that was being estimated, and the Cg cost
sits entirely *behind* an unknown: nobody has yet seen what D3D11 does once it gets past
startup. The floor is raised accordingly. Item (2) is building RTSS wiring from nothing and
item (3) is porting 67 Cg declarations across 17 files, 10 of them third-party Caelum, with
Hydrax layering its own material manager on top. The `upstream/ogre-14` branch (D3D11 already
enabled for Windows) remains the cheapest way to collapse this range — fix the startup crash
there and the rest of the picture becomes measurable in an afternoon.

**Risks:** the SM4 recompile of decade-old Cg is the unknown, and it is the whole variance in
the estimate. Caelum (10 of the 17 Cg files) is third-party. Keep D3D9 selectable throughout —
it is the fallback if a material family cannot be ported.
**Linux/GL:** none. D3D11 is Windows-only; the GL path is untouched.
**Upstream debt:** minimal, and arguably negative — this is work upstream RoR would take.

### Option B — Vulkan on a newer OGRE 1.x

|  |  |
|---|---|
| **Possible?** | **Yes — premise verified.** |
| **Effort** | **3–6 engineer-months.** |
| **Buys** | Vulkan on Windows *and* Linux — one modern API for both platforms. |
| **Breaks** | Cg does not target Vulkan at all: **all 72** declarations must be ported to GLSL/SPIR-V. Three major-version jump. `TerrainGeometryManager.cpp:472` breaks Linux terrain. |
| **Maintenance** | Moderate; upstream-maintained backend, but a large one-time dependency jump. |

**Verified:** `RenderSystems/Vulkan` exists in OGRE's 1.x-line `master`
([OGRECave/ogre/RenderSystems](https://github.com/OGRECave/ogre/tree/master/RenderSystems) —
the full backend list is `Direct3D11, Direct3D9, GL, GL3Plus, GLES2, GLSupport, Metal, Tiny,
Vulkan`). The `RenderSystems/Vulkan` directory is absent at `v13.0.0`, `v13.1.0` and
`v13.1.1` and first present at **`v13.2.0` (2021-11-28)**, whose notes open *"Highlight: Vulkan
RenderSystem added."* It is actively maintained — **v14.6.0 (2026-09-09)** adds HDR display
output on Vulkan among others.

The cost is the version jump: **1.11.6.1 → 14.x** crosses 1.12, 1.13, 13.x and 14.x with
breaking changes at each. Per issue #2's invariant, this is a **`ror-dependencies` package bump
plus a `REQUIRED_DEPS_VERSION` change** (root `CMakeLists.txt:19`, currently `30`) — a change in
another repository, not a local edit. Note `linux-native.yml` pins `v1.11.6` explicitly and
would need updating too.

#### Upstream has already done most of this jump — and it did not solve Cg

This checkout already fetches three upstream branches that attempt exactly this work:

| Branch | OGRE pin | Last commit | Cg declarations | `Plugin_CgProgramManager` | D3D11 on Windows |
|---|---|---|---|---|---|
| `upstream/ogre-1.12` | `OGRE/1.12.12` (`conanfile.txt`) | 2021-05-31 | 75 | loaded | off (commented unconditionally, `:497`) |
| `upstream/ogre-13` | `ogre3d/14.1.0` | 2023-09-23 | 68 | loaded | **ON** (comment-out is inside `if (NOT WIN32)`, `:461`) |
| `upstream/ogre-14` | `ogre3d/14.1.2` | 2024-02-12 | 68 | loaded | **ON** (same, `:469`) |

On `ogre-13` and `ogre-14` upstream also re-enabled GL on Windows and commented out GL3Plus
instead, so a Windows build on those branches loads D3D9 + D3D11 + GL.

This cuts both ways, and both directions matter.

**It lowers Option B's cost:** the engine-API half of the jump is largely done and directly
fetchable — `upstream/ogre-14` already pins **OGRE 14.1.2**, which ships the Vulkan render
system. Rebasing onto that work is far cheaper than doing the 1.11 → 14.x port cold, and the
3–6 month estimate above should be read as an upper bound if that branch is used as the base.
Both branches have been stalled since 2024, so expect to finish and re-validate them.

**And it is the single strongest piece of evidence in this document:** upstream RoR bumped
OGRE to 14.1.2, **switched the D3D11 render system on for Windows**, and *still* ships 68 Cg
programs and still loads `Plugin_CgProgramManager`. They had the backend enabled and available
— and did not de-Cg. The version bump and the render-system flag were never the hard part.
**Cg is.** That is why issue #4 is not a side quest but the whole of the engine-side work, and
why no option in this document can route around it.

**It also makes Experiment 2 cheap.** `upstream/ogre-14` is a branch with D3D11 already enabled
on Windows. Whoever next has a working toolchain should build *that* rather than flipping
`source/main/CMakeLists.txt:496` here — it is the smoke test, most of the way set up already.

### Option C — migrate to OGRE-Next (2.3 / 3.0)

|  |  |
|---|---|
| **Possible?** | Yes, but it is an engine rewrite. |
| **Effort** | **12–24 engineer-months.** |
| **Buys** | D3D11 + Vulkan + Metal, a modern threaded render pipeline, genuine architectural modernization. |
| **Breaks** | **Everything listed below.** |
| **Maintenance** | High, permanently. OGRE-Next is a different engine; this fork would no longer share upstream RoR's renderer. |

**OGRE-Next still does not give you DirectX 12.** Verified: its backends are
`Direct3D11, GL3Plus, GLES2, Metal, NULL, Vulkan`
([OGRECave/ogre-next/RenderSystems](https://github.com/OGRECave/ogre-next/tree/master/RenderSystems)).
Latest release v3.0.0 (2024-10-15).

Scope: **2,655 call sites across 173 of 450 files**, of which **1,289** are the
`Material`/`Technique`/`Pass`/`TextureUnitState` surface that OGRE-Next replaces with Hlms
datablocks — a redesign, not a mechanical port. On top of that, OGRE-Next **drops Direct3D 9
entirely**, so the invariant "keep D3D9 selectable" cannot be met; it drops the old compositor
and RTSS; and all 72 Cg programs must be rewritten. **Upstream debt: total** — this permanently
forks the renderer from upstream RoR, and every future upstream merge is paid against it.

### Option D — write a native Direct3D 12 RenderSystem for OGRE

|  |  |
|---|---|
| **Possible?** | Technically yes. Realistically no, for a fork. |
| **Effort** | **18–30 engineer-months** of specialist graphics work. |
| **Buys** | Literal DirectX 12 — and little else that Options A/B do not deliver far cheaper. |
| **Breaks** | Nothing directly; it is additive. But it inherits *all* of Option A's shader work, since Cg cannot target D3D12 either. |
| **Maintenance** | **Highest, forever, borne alone.** No upstream shares the burden. |

A from-scratch `Ogre::RenderSystem` backend means device and swapchain management, command list
recording and submission, descriptor heap allocation, PSO creation and caching, resource
residency and state transitions, fence-based frame synchronisation, and the complete
`Ogre::RenderSystem` virtual interface — then correctness and performance parity with a D3D11
backend that already exists and is already maintained by someone else. OGRE-Next's lead
maintainer has stated the position directly — *"There are no current plans for D3D12 support"*
([ogre-next#417](https://github.com/OGRECave/ogre-next/issues/417), 2023-09-27; asked again in
[#561](https://github.com/OGRECave/ogre-next/issues/561), still unanswered). OGRE's 1.x
mainline has never proposed one at all. Writing and owning a graphics backend that no upstream maintains is a
permanent tax on a fork whose renderer is otherwise free.

### Option E — translation layer, zero engine changes

|  |  |
|---|---|
| **Possible?** | **Yes, today, with no code changes.** |
| **Effort** | **Hours to a few days** — entirely evaluation, not development. |
| **Buys** | **Measured (Experiment 3): DXVK gives −36% median frame time and −29.9% 1%-low, faster in 5 of 5 rounds. D3D9On12 buys no speed — ~28% slower than a healthy D3D9 path — but never had a bad round, which native did.** Both run the game correctly with no code changes. |
| **Breaks** | Nothing in the codebase. Ships as a deployment/config choice, per-user and reversible. |
| **Maintenance** | Near zero. D3D9On12 is part of Windows; DXVK is externally maintained. |

- **D3D9On12** — Microsoft's D3D9-over-D3D12 mapping layer, **already present** on this machine
  at `C:\Windows\System32\d3d9on12.dll`. Nothing to install or ship.
- **DXVK** — D3D8/9/10/11 over Vulkan ([doitsujin/dxvk](https://github.com/doitsujin/dxvk)).
  Drop-in DLLs next to the executable. Windows is *not officially supported* by the project,
  though it is widely used there — a real caveat to weigh.

**This has now been measured** — see Experiment 3 for the full table, method and caveats. The
short version on an RTX 4070 Laptop, one vehicle on `simple2` at 1280×720:

- **DXVK (Vulkan): 0.538 ms median vs native's 0.840 ms** — faster in every round, on both
  median and 1%-low.
- **D3D9On12 (DirectX 12): 1.056 ms median** — slower than native's good rounds (~0.83 ms),
  faster than its degraded ones (~1.50 ms), and the steadiest of the three (0.038 ms spread).

That ordering matches the published expectation that DXVK tends to beat D3D9On12
([Intel community report](https://community.intel.com/t5/Intel-Arc-Discrete-Graphics/Suggestions-DXVK-outperforms-D3D9On12-when-running-DirectX-9-on/m-p/1428393),
[PCGamingWiki](https://www.pcgamingwiki.com/wiki/DXVK)), and sharpens it: here DXVK beat native
too, while D3D9On12 did not.

**The measurement's limit is the scene, not the method.** At 950–1860 FPS the GPU is idle and
this is a CPU-overhead benchmark. Re-measure on a heavy scene before shipping a default.

**What it does *not* buy:** it is a driver-path and compatibility win, not an engine-architecture
win. It does not remove Cg, does not modernize the material system, and does not advance
Options A–D by a single step.

---

## Recommendation

**Ship DXVK as a supported option now; treat Option A as the only engine-side modernization
worth funding. Do not pursue DirectX 12 — measured, it buys no performance over the D3D9 path
you already have.**

Experiment 3 settled what was previously a guess, and it inverted half of it. A translation
layer is still the only thing in this document that costs nothing — no code change, no rebuild,
no risk to the D3D9 path, a single DLL the user can delete — but **the DirectX 12 layer is not
the one to ship.** D3D9On12 never beat a healthy D3D9 path; it only looked good against native's
two degraded rounds. **DXVK, which maps D3D9 onto Vulkan, was faster in all five rounds on both
median (−36%) and 1%-low (−29.9%)**, and is the one worth shipping as a documented, opt-in
option. It is explicitly
*not* modernization: it buys frames and driver compatibility, not architecture. If and when the goal becomes a genuinely modern renderer, the
entry point is **Option A** — not because D3D11 is exciting, but because its real content is
killing the Cg dependency and wiring up RTSS, and *that work is an unavoidable prerequisite for
Options B, C and D alike*. Do it once, under the cheapest option that forces it, while D3D9
remains selectable as a fallback. Options C and D are out of proportion to this fork: C is an
engine rewrite touching 173 files that still does not deliver DX12, and D is roughly two
engineer-years of specialist work to build and then permanently maintain a graphics backend
alone.

### Consequences for the epic

- **#3 and #4 should be re-scoped against this.** #4 (the Cg dependency) is not a side issue —
  it is the whole of the engine-side work, and it gates A, B, C and D without exception.
- **Nothing here justifies pursuing literal DX12.** If DX12 is a hard requirement rather than a
  proxy for "modern and fast", Option D is the only route and its price is stated above.
- **Multiplayer:** no impact from any option. None of them touch the network layer.

### Open items

All four experiments required by issue #2 have now been run. What remains:

1. **Re-measure Option E on a representative scene.** The benchmark ran at 950–1860 FPS on one
   vehicle, which measures CPU-side driver overhead rather than gameplay. The content submodule
   does not ship a heavy enough terrain to do better; this needs real content.
2. **Decide whether to ship DXVK**, and if so whether as an opt-in download or bundled — note
   DXVK does not officially support Windows, which is a support-burden question, not a
   technical one.
3. **Owner confirmation** of this recommendation in issue #2, per that issue's definition of done.
