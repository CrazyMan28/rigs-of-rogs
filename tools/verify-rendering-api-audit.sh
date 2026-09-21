#!/usr/bin/env bash
#
# Re-derives the tree-dependent numbers cited in doc/rendering-api-decision.md.
#
# The decision document rests on counts taken from this checkout (Cg program
# declarations, fixed-function materials, OGRE-Next call sites, ...). Those
# numbers go stale as the tree moves, and a stale number silently invalidates
# the recommendation built on it. Run this to find out whether the document
# still describes the code.
#
# Usage:  tools/verify-rendering-api-audit.sh
# Exit:   0 = every figure still matches, 1 = at least one drifted.
#
# This is a MANUAL check - no CI job invokes it. Run it before citing the
# document, and when a figure legitimately changes, update BOTH this script and
# the corresponding number in doc/rendering-api-decision.md in the same commit.

set -u

cd "$(dirname "$0")/.." || exit 1

fail=0
pass=0

# check <description> <expected> <actual>
check() {
    local what="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        printf '  ok    %-58s %s\n' "$what" "$actual"
        pass=$((pass + 1))
    else
        printf '  DRIFT %-58s expected %s, got %s\n' "$what" "$expected" "$actual"
        fail=$((fail + 1))
    fi
}

# An OGRE program declaration in a given shader language, e.g.
#   fragment_program NiceMetal_PS_mm cg
# %s is the language. Kept in one place so the count and the file list can
# never drift apart.
PROGRAM_DECL='^[[:space:]]*(vertex|fragment|geometry)_program[[:space:]]+[^[:space:]]+[[:space:]]+%s[[:space:]]*$'

decls_in_language() {
    grep -rhEi "$(printf "$PROGRAM_DECL" "$1")" \
        --include='*.material' --include='*.program' resources
}

files_in_language() {
    grep -rlEi "$(printf "$PROGRAM_DECL" "$1")" \
        --include='*.material' --include='*.program' resources
}

# Profile lines, trailing whitespace stripped. Indentation in resources/ mixes
# tabs and spaces; normalising matters, because not doing so is what produced a
# wrong frequency table in the first draft of the document.
profiles_normalised() {
    grep -rhEi '^[[:space:]]*profiles[[:space:]]' \
        --include='*.material' --include='*.program' resources | sed 's/[[:space:]]*$//'
}

D3D11_PROFILE='\b(vs_4_0|ps_4_0|vs_5_0|ps_5_0|hlslv|hlslf)\b'

echo "== Renderer / build configuration =="

check "OGRE pinned version (conanfile.py)" "1.11.6.1" \
    "$(grep -oE 'ogre3d/[0-9.]+' conanfile.py | head -1 | cut -d/ -f2)"

check "Direct3D12 lines in plugins.cfg.in" "0" \
    "$(grep -ci 'Direct3D12' source/main/plugins.cfg.in || true)"

check "D3D11 render system commented out in CMake" "1" \
    "$(grep -cE '^[[:space:]]*set\(CFG_COMMENT_RENDERSYSTEM_D3D11 "# "\)' source/main/CMakeLists.txt || true)"

check "REQUIRED_DEPS_VERSION" "30" \
    "$(grep -oE 'set\(REQUIRED_DEPS_VERSION ([0-9]+)\)' CMakeLists.txt | grep -oE '[0-9]+')"

echo
echo "== Experiment 1: Cg inventory =="

check "Cg program declarations (vertex+fragment)" "72" \
    "$(decls_in_language cg | wc -l | tr -d ' ')"

check "  ...fragment_program cg" "45" \
    "$(decls_in_language cg | grep -ciE '^[[:space:]]*fragment_program')"

check "  ...vertex_program cg" "27" \
    "$(decls_in_language cg | grep -ciE '^[[:space:]]*vertex_program')"

check "files declaring at least one Cg program" "17" \
    "$(files_in_language cg | wc -l | tr -d ' ')"

check "Cg file concentration by directory" "caelum=10 materials=4 managed_materials=2 OgreCore=1" \
    "$(files_in_language cg | awk -F/ '{print $2}' | sort | uniq -c | sort -rn \
        | awk '{printf "%s%s=%s", (NR>1 ? " " : ""), $2, $1}')"

# Only vs_4_0/ps_4_0/vs_5_0/ps_5_0 (or the hlslv/hlslf meta-profiles) let OGRE's
# Cg plugin build a D3D11-compatible HLSL delegate. Anything lower resolves to a
# D3D9-era assembly program, which the D3D11 render system cannot consume.
check "Cg profile lines naming a D3D11-capable profile" "5" \
    "$(grep -rhniE "$D3D11_PROFILE" \
        --include='*.material' --include='*.program' resources | wc -l | tr -d ' ')"

# Assert the denominator too. "0 files outside OgreCore/" is also what a broken
# regex or a missing resources/ tree produces, so on its own it proves nothing.
check "  ...in how many files (denominator; guards the next check)" "1" \
    "$(grep -rlniE "$D3D11_PROFILE" \
        --include='*.material' --include='*.program' resources | wc -l | tr -d ' ')"

check "  ...of which outside OgreCore/ (i.e. RoR's own content)" "0" \
    "$(grep -rlniE "$D3D11_PROFILE" \
        --include='*.material' --include='*.program' resources \
        | grep -vc 'resources/OgreCore/' || true)"

# The frequency table printed in the document is generated from exactly this.
check "distinct 'profiles' lists (rows in the document's table)" "13" \
    "$(profiles_normalised | sed 's/^[[:space:]]*//' | sort -u | wc -l | tr -d ' ')"

check "total 'profiles' declarations (the table must sum to this)" "72" \
    "$(profiles_normalised | wc -l | tr -d ' ')"

# vs_1_1 is the only profile RoR uses that D3D11 never registers, so those
# declarations fail to resolve to a supported syntax at all.
# NOTE: ps_2_x *is* registered (OgreD3D11RenderSystem.cpp:1145, under
# SUPPORT_SM2_0_HLSL_SHADERS). Those resolve, then die on the assembly path
# instead. Counted here because the document cites the number - not because
# they are unregistered. An earlier draft got this backwards.
check "declarations using vs_1_1 with no SM4/SM5 alternative (unresolvable)" "12" \
    "$(profiles_normalised | grep -E '\bvs_1_1\b' | grep -vcE '\b(vs_4_0|vs_5_0)\b')"

check "declarations using ps_2_x (registered, but fail on the assembly path)" "9" \
    "$(profiles_normalised | grep -cE '\bps_2_x\b')"

check ".material files total" "48" \
    "$(find resources -name '*.material' | wc -l | tr -d ' ')"

# NUL-delimited: resources/ has no paths containing spaces today, but a
# word-splitting loop would miscount silently the day one appears.
ff_mat=0
while IFS= read -r -d '' f; do
    grep -qEi '(vertex_program_ref|fragment_program_ref|shadow_caster_vertex_program_ref)' "$f" \
        || ff_mat=$((ff_mat + 1))
done < <(find resources -name '*.material' -print0)
check ".material files with no shader program_ref (fixed-function)" "32" "$ff_mat"

echo
echo "== RTShaderSystem (D3D11 has no fixed-function pipeline) =="

check "gfx_enable_rtshaders default" "false" \
    "$(grep -oE '"gfx_enable_rtshaders".*"(true|false)"' source/main/system/CVar.cpp \
        | grep -oE '"(true|false)"$' | tr -d '"')"

# Declaration + extern + creation, and nothing else: the CVar is never read, so
# RTSS is unwired rather than switched off. If this becomes 4+, something now
# reads it and the "unwired" diagnosis in the document needs revisiting.
check "gfx_enable_rtshaders references in source/ (decl+extern+create only)" "3" \
    "$(grep -rc 'gfx_enable_rtshaders' source --include='*.cpp' --include='*.h' \
        | awk -F: '{s+=$NF} END{print s+0}')"

check "ShaderGenerator::initialize() calls in source/" "0" \
    "$(grep -rc 'ShaderGenerator::initialize' source --include='*.cpp' --include='*.h' \
        | awk -F: '{s+=$NF} END{print s+0}')"

check "RTShader::ShaderGenerator call sites in source/" "2" \
    "$(grep -rn 'RTShader::ShaderGenerator::getSingleton' source \
        --include='*.cpp' --include='*.h' | wc -l | tr -d ' ')"

# Widened from just the getSingleton() calls so the document's "RTSS is unwired"
# paragraph is actually guarded: 1 cvar creation + 1 #include + 2 call sites.
# Any growth here means someone has started wiring RTSS up.
check "RTShader mentions in source/ (cvar + include + 2 call sites)" "4" \
    "$(grep -rc 'RTShader' source --include='*.cpp' --include='*.h' \
        | awk -F: '{s+=$NF} END{print s+0}')"

# The NiceMetal materials are gated on this and it defaults off, which is why
# they are the alternate vehicle material and not the core path.
check "gfx_alt_actor_materials default (gates the NiceMetal materials)" "false" \
    "$(grep -oE '"gfx_alt_actor_materials".*"(true|false)"' source/main/system/CVar.cpp \
        | grep -oE '"(true|false)"$' | tr -d '"')"

echo
echo "== D3D11 startup blocker (Experiment 2) =="

# Every texture requests 5 mip levels. Under D3D11 that routes the 8x8 'Warning'
# texture through a mismatched-size blitFromMemory, which OGRE refuses - the
# crash that stops D3D11 before it ever reaches a shader. If this stops being 5,
# or stops being called, re-run the smoke test before trusting the document.
check "setDefaultNumMipmaps(5) call sites" "2" \
    "$(grep -rc 'setDefaultNumMipmaps(5)' source/main --include='*.cpp' \
        | awk -F: '{s+=$NF} END{print s+0}')"

echo
echo "== RTShaderSystem (continued) =="

check "RTSS FFPLib HLSL variants shipped" "9" \
    "$(find resources/rtshader -name '*.hlsl' | wc -l | tr -d ' ')"

echo
echo "== Render-system name branches =="

check "sites branching on getRenderSystem()->getName()" "3" \
    "$(grep -rnE 'getRenderSystem\(\)->getName\(\)[[:space:]]*(==|\.find)' source/main \
        --include='*.cpp' | wc -l | tr -d ' ')"

echo
echo "== Experiment 4: OGRE-Next affected API surface =="

NEXT_PAT='(SceneManager|Ogre::Entity|createEntity|SceneNode|MaterialPtr|MaterialManager|Technique|Ogre::Pass|getPass|setMaterialName|Compositor|ParticleSystem|BillboardSet|ManualObject|HardwareBuffer|RenderTarget|RenderWindow|Viewport|Ogre::Camera|TextureUnitState|TextureManager)'
MAT_PAT='(MaterialPtr|MaterialManager|Technique|Ogre::Pass|getPass|setMaterialName|TextureUnitState)'

check "source/main/gfx .cpp/.h files" "130" \
    "$(find source/main/gfx -type f \( -name '*.cpp' -o -name '*.h' \) | wc -l | tr -d ' ')"

check "source/main .cpp/.h files" "450" \
    "$(find source/main -type f \( -name '*.cpp' -o -name '*.h' \) | wc -l | tr -d ' ')"

check "source/main/gfx lines (quoted for scale)" "39950" \
    "$(find source/main/gfx -type f \( -name '*.cpp' -o -name '*.h' \) -exec cat {} + | wc -l | tr -d ' ')"

check "source/main lines (quoted for scale)" "200801" \
    "$(find source/main -type f \( -name '*.cpp' -o -name '*.h' \) -exec cat {} + | wc -l | tr -d ' ')"

check "affected call sites in source/main/gfx" "1532" \
    "$(grep -rE "$NEXT_PAT" source/main/gfx --include='*.cpp' --include='*.h' | wc -l | tr -d ' ')"

check "  ...spread over how many gfx files" "87" \
    "$(grep -rlE "$NEXT_PAT" source/main/gfx --include='*.cpp' --include='*.h' | wc -l | tr -d ' ')"

check "affected call sites in source/main" "2655" \
    "$(grep -rE "$NEXT_PAT" source/main --include='*.cpp' --include='*.h' | wc -l | tr -d ' ')"

check "  ...spread over how many source/main files" "173" \
    "$(grep -rlE "$NEXT_PAT" source/main --include='*.cpp' --include='*.h' | wc -l | tr -d ' ')"

check "Material/Technique/Pass sites in source/main (Hlms surface)" "1289" \
    "$(grep -rE "$MAT_PAT" source/main --include='*.cpp' --include='*.h' | wc -l | tr -d ' ')"

# How much of that 2,655 is vendored third-party code rather than RoR's own.
# The document leans on these to avoid overstating Option C's game-code scope.
check "  ...of which in vendored gfx/hydrax/" "903" \
    "$(grep -rE "$NEXT_PAT" source/main/gfx/hydrax --include='*.cpp' --include='*.h' | wc -l | tr -d ' ')"

check "  ...of which in vendored Ogre* files" "408" \
    "$(grep -rE "$NEXT_PAT" source/main --include='Ogre*.cpp' --include='Ogre*.h' | wc -l | tr -d ' ')"

# Hydrax defines its own MaterialManager/TextureManager, so a bare name match
# overcounts OGRE symbols. Guards the document's false-positive caveat.
check "MaterialManager lines in source/main (bare name)" "439" \
    "$(grep -rE 'MaterialManager' source/main --include='*.cpp' --include='*.h' | wc -l | tr -d ' ')"

check "  ...actually spelled Ogre::MaterialManager" "77" \
    "$(grep -rE 'Ogre::MaterialManager' source/main --include='*.cpp' --include='*.h' | wc -l | tr -d ' ')"

echo
if [ "$fail" -eq 0 ]; then
    echo "All $pass figures in doc/rendering-api-decision.md still match the tree."
    exit 0
fi
echo "$fail of $((pass + fail)) figures drifted. Update the document and this script together."
exit 1
