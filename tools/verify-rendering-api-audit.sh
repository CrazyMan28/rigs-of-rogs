#!/usr/bin/env bash
#
# Re-derives every tree-dependent number cited in doc/rendering-api-decision.md.
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
# When a figure legitimately changes, update BOTH this script and the
# corresponding number in doc/rendering-api-decision.md in the same commit.

set -u

cd "$(dirname "$0")/.." || exit 1

fail=0
pass=0

# check <description> <expected> <actual>
check() {
    local what="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        printf '  ok   %-58s %s\n' "$what" "$actual"
        pass=$((pass + 1))
    else
        printf '  DRIFT %-57s expected %s, got %s\n' "$what" "$expected" "$actual"
        fail=$((fail + 1))
    fi
}

# Matches an OGRE program declaration of a given language, e.g.
#   fragment_program NiceMetal_PS_mm cg
decls_in_language() {
    grep -rhEi \
        "^[[:space:]]*(vertex|fragment|geometry)_program[[:space:]]+[^[:space:]]+[[:space:]]+$1[[:space:]]*\$" \
        --include=*.material --include=*.program resources | wc -l | tr -d ' '
}

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

vert_cg=$(decls_in_language cg)
check "Cg program declarations (vertex+fragment)" "72" "$vert_cg"

check "files declaring at least one Cg program" "17" \
    "$(grep -rlEi '^[[:space:]]*(vertex|fragment|geometry)_program[[:space:]]+[^[:space:]]+[[:space:]]+cg[[:space:]]*$' \
        --include=*.material --include=*.program resources | wc -l | tr -d ' ')"

# Only vs_4_0/ps_4_0/vs_5_0/ps_5_0 (or the hlslv/hlslf meta-profiles) let OGRE's
# Cg plugin build a D3D11-compatible HLSL delegate. Anything lower resolves to a
# D3D9-era assembly program, which the D3D11 render system cannot consume.
check "Cg profile lines naming a D3D11-capable profile" "5" \
    "$(grep -rhniE '\b(vs_4_0|ps_4_0|vs_5_0|ps_5_0|hlslv|hlslf)\b' \
        --include=*.material --include=*.program resources | wc -l | tr -d ' ')"

check "  ...of which outside OgreCore/ (i.e. RoR's own content)" "0" \
    "$(grep -rlniE '\b(vs_4_0|ps_4_0|vs_5_0|ps_5_0|hlslv|hlslf)\b' \
        --include=*.material --include=*.program resources \
        | grep -v 'resources/OgreCore/' | wc -l | tr -d ' ')"

# D3D11 never registers vs_1_1 or ps_2_x at any setting, so declarations resting
# on them are unreachable regardless of SUPPORT_SM2_0_HLSL_SHADERS.
profiles_normalised() {
    grep -rhEi '^[[:space:]]*profiles[[:space:]]' \
        --include=*.material --include=*.program resources | sed 's/[[:space:]]*$//'
}

# The frequency table printed in the document is generated from exactly this.
check "distinct 'profiles' lists (rows in the document's table)" "13" \
    "$(profiles_normalised | sed 's/^[[:space:]]*//' | sort -u | wc -l | tr -d ' ')"

check "total 'profiles' declarations (table must sum to this)" "72" \
    "$(profiles_normalised | wc -l | tr -d ' ')"

check "declarations using vs_1_1 with no SM4/SM5 alternative" "12" \
    "$(profiles_normalised | grep -E '\bvs_1_1\b' | grep -vcE '\b(vs_4_0|vs_5_0)\b')"

check "declarations using ps_2_x (never registered by D3D11)" "9" \
    "$(profiles_normalised | grep -cE '\bps_2_x\b')"

total_mat=$(find resources -name '*.material' | wc -l | tr -d ' ')
ff_mat=0
for f in $(find resources -name '*.material'); do
    grep -qEi '(vertex_program_ref|fragment_program_ref|shadow_caster_vertex_program_ref)' "$f" || ff_mat=$((ff_mat + 1))
done
check ".material files total" "48" "$total_mat"
check ".material files with no shader program_ref (fixed-function)" "32" "$ff_mat"

echo
echo "== RTShaderSystem (D3D11 has no fixed-function pipeline) =="

check "gfx_enable_rtshaders default" "false" \
    "$(grep -oE '"gfx_enable_rtshaders".*"(true|false)"' source/main/system/CVar.cpp | grep -oE '"(true|false)"$' | tr -d '"')"

# Declaration + extern + creation, and nothing else: the CVar is never read, so
# RTSS is unwired rather than switched off. If this becomes 4+, something now
# reads it and the "unwired" diagnosis in the document needs revisiting.
check "gfx_enable_rtshaders references in source/ (decl+extern+create only)" "3" \
    "$(grep -rc 'gfx_enable_rtshaders' source --include=*.cpp --include=*.h \
        | awk -F: '{s+=$NF} END{print s+0}')"

check "ShaderGenerator::initialize() calls in source/" "0" \
    "$(grep -rc 'ShaderGenerator::initialize' source --include=*.cpp --include=*.h \
        | awk -F: '{s+=$NF} END{print s+0}')"

check "RTShader::ShaderGenerator call sites in source/" "2" \
    "$(grep -rn 'RTShader::ShaderGenerator::getSingleton' source --include=*.cpp --include=*.h | wc -l | tr -d ' ')"

check "RTSS FFPLib HLSL variants shipped" "9" \
    "$(find resources/rtshader -name '*.hlsl' | wc -l | tr -d ' ')"

echo
echo "== Render-system name branches =="

check "sites branching on getRenderSystem()->getName()" "3" \
    "$(grep -rn 'getRenderSystem()->getName()[[:space:]]*\(==\|\.find\)' source/main --include=*.cpp \
        | wc -l | tr -d ' ')"

echo
echo "== Experiment 4: OGRE-Next affected API surface =="

NEXT_PAT='(SceneManager|Ogre::Entity|createEntity|SceneNode|MaterialPtr|MaterialManager|Technique|Ogre::Pass|getPass|setMaterialName|Compositor|ParticleSystem|BillboardSet|ManualObject|HardwareBuffer|RenderTarget|RenderWindow|Viewport|Ogre::Camera|TextureUnitState|TextureManager)'

check "affected call sites in source/main/gfx" "1532" \
    "$(grep -rE "$NEXT_PAT" source/main/gfx --include=*.cpp --include=*.h | wc -l | tr -d ' ')"

check "affected call sites in source/main" "2655" \
    "$(grep -rE "$NEXT_PAT" source/main --include=*.cpp --include=*.h | wc -l | tr -d ' ')"

check "files in source/main touching that surface" "173" \
    "$(grep -rlE "$NEXT_PAT" source/main --include=*.cpp --include=*.h | wc -l | tr -d ' ')"

MAT_PAT='(MaterialPtr|MaterialManager|Technique|Ogre::Pass|getPass|setMaterialName|TextureUnitState)'
check "Material/Technique/Pass sites in source/main (Hlms surface)" "1289" \
    "$(grep -rE "$MAT_PAT" source/main --include=*.cpp --include=*.h | wc -l | tr -d ' ')"

echo
if [ "$fail" -eq 0 ]; then
    echo "All $pass figures in doc/rendering-api-decision.md still match the tree."
    exit 0
fi
echo "$fail of $((pass + fail)) figures drifted. Update the document and this script together."
exit 1
