# Render API decision: DirectX 9 → DirectX 12

**Status:** research complete, recommendation pending owner confirmation
**Issue:** [#2](https://github.com/CrazyMan28/rigs-of-rogs/issues/2) · **Epic:** [#1](https://github.com/CrazyMan28/rigs-of-rogs/issues/1)
**Audited against:** this checkout, `master` @ `8c821c052`, OGRE **1.11.6.1** (`conanfile.py:25`)

> Every load-bearing count in this document is re-derivable. Run
> `tools/verify-rendering-api-audit.sh`; it re-computes the **39** tree-dependent figures it
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

**But most of what you actually want is reachable, and one piece of it costs nothing.**
Windows already ships `d3d9on12.dll`, which runs RoR's existing DirectX 9 calls on top of a
DirectX 12 driver — no code changes, no rebuild. DXVK does the same onto Vulkan. In the only
sense that is cheaply achievable, "running RoR on DirectX 12" is a drop-in change you can test
this afternoon. The genuine engine-side modernization step is **DirectX 11**, whose render
system is already present in the source tree and merely switched off — but switching it on is
*not* the one-line change it appears to be, for reasons quantified in Option A below.

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

## Experiments 2 and 3 — NOT RUN

**These two experiments could not be performed in this environment, and no numbers for them
are invented below.** This is the one acceptance criterion in issue #2 left unmet.

| Missing | Evidence |
|---|---|
| CMake | not installed |
| Conan | not installed |
| Visual Studio / MSBuild | no installation found |
| Game content (terrains, vehicles) | `content/` is empty |

- **Experiment 2 (D3D11 smoke test)** — needs a full toolchain to build and a content set to
  launch. The static analysis above predicts the outcome in detail (Cg programs fail to bind;
  32 fixed-function materials fail without RTSS), but the smoke test is what *settles* it and
  is still the single highest-information experiment in this issue. It will also turn Option A's
  wide effort range into a real estimate.
- **Experiment 3 (translation-layer benchmark)** — needs a built binary, content, and a GPU.
  Option E's numbers are therefore **unmeasured**; see Option E for exactly what to run.

`C:\Windows\System32\d3d9on12.dll` **is** present on this machine, confirming D3D9On12 needs no
installation — the one Option E fact that could be checked here.

---

## The five options

### Option A — enable the D3D11 render system already in the tree

|  |  |
|---|---|
| **Possible?** | **Yes.** The plugin exists, is built, and is switched off by one CMake line. |
| **Effort** | **8–20 engineer-weeks.** See the note below on why the floor is not lower. |
| **Buys** | A supported, modern-driver API. Removes the D3D9 deprecation risk. Keeps OGRE, keeps the fork close to upstream. The necessary first step of *any* real modernization. |
| **Breaks** | 67 of 72 Cg declarations cannot bind (no D3D11-capable profile). 32 of 48 materials are fixed-function and need RTSS, which is not merely off but **unwired** — `gfx_enable_rtshaders` is read by nothing and `ShaderGenerator` is never initialised. |
| **Maintenance** | Low. Upstream OGRE maintains the backend; the work is one-time. |

Work: (1) stand RTSS up from nothing — initialise `ShaderGenerator`, attach it to the scene
manager and viewport, wire `gfx_enable_rtshaders` to something,
register the material-scheme listener across the game, not just terrain objects; (2) give the
67 Cg declarations a D3D11-capable profile (`vs_4_0`/`ps_4_0`, or `hlslv`/`hlslf`), then fix the
SM2/SM3-era Cg that fails to compile at SM4 — texture sampling and semantics are the usual
casualties; (3) ship `RenderSystem_Direct3D11` and uncomment `source/main/CMakeLists.txt:496`.

**On the estimate:** an earlier draft said 4–8 weeks. That floor is not defensible against
this document's own evidence — item (1) is building RTSS wiring from nothing, item (2) is
porting 67 Cg declarations across 17 files of which 10 are third-party Caelum, Hydrax layers
its own material manager on top, and **none of it can be smoke-tested here** because
Experiments 2 and 3 could not run. Four weeks assumes a working build and content set that do
not currently exist. The `upstream/ogre-14` branch (D3D11 already on for Windows) is the
cheapest way to collapse this range — run the smoke test there first and re-estimate.

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
| **Buys** | RoR's existing D3D9 calls execute on a **DirectX 12** (D3D9On12) or **Vulkan** (DXVK) driver path. Often the practical fix on modern GPUs with weak native D3D9 drivers. |
| **Breaks** | Nothing in the codebase. Ships as a deployment/config choice, per-user and reversible. |
| **Maintenance** | Near zero. D3D9On12 is part of Windows; DXVK is externally maintained. |

- **D3D9On12** — Microsoft's D3D9-over-D3D12 mapping layer, **already present** on this machine
  at `C:\Windows\System32\d3d9on12.dll`. Nothing to install or ship.
- **DXVK** — D3D8/9/10/11 over Vulkan ([doitsujin/dxvk](https://github.com/doitsujin/dxvk)).
  Drop-in DLLs next to the executable. Windows is *not officially supported* by the project,
  though it is widely used there — a real caveat to weigh.

Published comparisons suggest the win is highly hardware-dependent: DXVK substantially
outperforming D3D9On12 on Intel Arc, where native D3D9 drivers are weak
([Intel community report](https://community.intel.com/t5/Intel-Arc-Discrete-Graphics/Suggestions-DXVK-outperforms-D3D9On12-when-running-DirectX-9-on/m-p/1428393)),
against a general expectation that translation costs some frames versus a good native driver
([PCGamingWiki](https://www.pcgamingwiki.com/wiki/DXVK)).

**This must be measured before it is relied upon, and it was not measured here.** To close that
gap: one fixed scene — named terrain, fixed vehicle count, fixed resolution and settings —
three runs each of native D3D9, D3D9On12, and DXVK, reporting **median and 1%-low frame time**
plus the hardware. Record all of it here per §9 of issue #2.

**What it does *not* buy:** it is a driver-path and compatibility win, not an engine-architecture
win. It does not remove Cg, does not modernize the material system, and does not advance
Options A–D by a single step.

---

## Recommendation

**Evaluate Option E now and ship it if the numbers hold; treat Option A as the only
engine-side modernization worth funding.**

Option E is the only thing in this document that answers the owner's literal question at a cost
worth paying: it puts RoR's rendering on a DirectX 12 driver path today, with no code change, no
rebuild, no risk to the D3D9 path, and a per-user switch that can be reverted instantly — and on
the modern GPUs where native D3D9 drivers are weakest, it is likely to be the single largest
practical improvement available. It should be measured and, if the numbers hold, shipped as a
documented deployment option. It is explicitly *not* modernization: it buys frames and driver
compatibility, not architecture. If and when the goal becomes a genuinely modern renderer, the
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

1. **Experiment 2 (D3D11 smoke test)** — unrun; it converts Option A's 4–8 week range into a
   real number and is the highest-information experiment remaining.
2. **Experiment 3 (translation-layer benchmark)** — unrun; Option E is recommended on
   qualitative grounds and a zero-cost/zero-risk profile, and should be measured before it is
   relied upon.
3. **Owner confirmation** of this recommendation in issue #2, per that issue's definition of done.
