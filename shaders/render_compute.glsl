#[compute]
#version 450

// Render compute shader: muuntaa simulaatioruudukon RGBA8-tekstuuriksi suoraan GPU:lla.
// Eliminoi CPU-roundtripin: ei buffer_get_data + texture.update renderöintiä varten.
// Lukee: grid_buffer (binding=0) — uint32/pikseli: (seed << 8) | material_id
// Kirjoittaa: rgba_image (binding=1) — RGBA8 renderöintitekstuuriin

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// Simulaation grid-bufferi (sama kuin simulation.glsl)
layout(set = 0, binding = 0, std430) restrict readonly buffer GridData {
    uint cells[];
} grid;

// Renderöintitekstuurin tulostus — rgba8 vastaa DATA_FORMAT_R8G8B8A8_UNORM
// imageStore arvoilla [0, 255] / 255.0 = [0.0, 1.0] UNORM-formaatissa
layout(set = 0, binding = 1, rgba8) restrict writeonly uniform image2D rgba_image;

layout(push_constant, std430) uniform Params {
    uint width;
    uint height;
    uint frame;
    uint _pad0;
} p;

// Materiaalitunnukset (sama kuin simulation.glsl)
const uint EMPTY       = 0u;
const uint SAND        = 1u;
const uint WATER       = 2u;
const uint STONE       = 3u;
const uint WOOD        = 4u;
const uint FIRE        = 5u;
const uint OIL         = 6u;
const uint STEAM       = 7u;
const uint ASH         = 8u;
const uint WOOD_FALLING = 9u;
const uint GLASS       = 10u;
const uint DIRT        = 11u;
const uint IRON_ORE    = 12u;
const uint GOLD_ORE    = 13u;
const uint IRON        = 14u;
const uint GOLD        = 15u;
const uint COAL        = 16u;
const uint HELD        = 17u;
const uint GRAVEL      = 18u;
const uint BEDROCK     = 19u;

// Materiaalien perusvärit (sama kuin pixel_render.gdshader MAT_COLORS)
// Tallennettu 0-255 uint-arvoina
uvec3 mat_base_color(uint mat) {
    if (mat == SAND)         return uvec3(219u, 199u, 114u);
    if (mat == WATER)        return uvec3(51u,  102u, 217u);
    if (mat == STONE)        return uvec3(127u, 127u, 132u);
    if (mat == WOOD)         return uvec3(114u, 71u,  30u);
    if (mat == FIRE)         return uvec3(255u, 127u, 25u);
    if (mat == OIL)          return uvec3(51u,  38u,  25u);
    if (mat == STEAM)        return uvec3(204u, 217u, 230u);
    if (mat == ASH)          return uvec3(89u,  84u,  76u);
    if (mat == WOOD_FALLING) return uvec3(114u, 71u,  30u);
    if (mat == GLASS)        return uvec3(165u, 224u, 214u);
    if (mat == DIRT)         return uvec3(114u, 81u,  45u);
    if (mat == IRON_ORE)     return uvec3(140u, 107u, 96u);
    if (mat == GOLD_ORE)     return uvec3(183u, 165u, 63u);
    if (mat == IRON)         return uvec3(173u, 173u, 183u);
    if (mat == GOLD)         return uvec3(229u, 198u, 51u);
    if (mat == COAL)         return uvec3(46u,  43u,  53u);
    if (mat == HELD)         return uvec3(255u, 216u, 25u);
    if (mat == GRAVEL)       return uvec3(140u, 127u, 114u);
    if (mat == BEDROCK)      return uvec3(63u,  56u,  76u);
    return uvec3(20u, 20u, 30u);  // EMPTY ja tuntemattomat
}

// Materiaalien värivariaatio-kerroin (0-255, kuten pixel_render.gdshader MAT_VAR * 255)
uint mat_variation(uint mat) {
    if (mat == SAND)         return 15u;   // 0.06 * 255 ≈ 15
    if (mat == WATER)        return 10u;   // 0.04
    if (mat == STONE)        return 12u;   // 0.05
    if (mat == WOOD)         return 10u;   // 0.04
    if (mat == FIRE)         return 51u;   // 0.20
    if (mat == OIL)          return 5u;    // 0.02
    if (mat == STEAM)        return 12u;   // 0.05
    if (mat == ASH)          return 7u;    // 0.03
    if (mat == WOOD_FALLING) return 10u;   // 0.04
    if (mat == GLASS)        return 7u;    // 0.03
    if (mat == DIRT)         return 8u;    // 0.03
    if (mat == IRON_ORE)     return 10u;   // 0.04
    if (mat == GOLD_ORE)     return 10u;   // 0.04
    if (mat == IRON)         return 5u;    // 0.02
    if (mat == GOLD)         return 5u;    // 0.02
    if (mat == COAL)         return 12u;   // 0.05
    if (mat == GRAVEL)       return 10u;   // 0.04
    if (mat == BEDROCK)      return 7u;    // 0.03
    return 0u;
}

// Yksinkertainen hash-funktio (sama kuin simulation.glsl)
uint hash(uint x) {
    x ^= x >> 17u;
    x *= 0xbf58476du;
    x ^= x >> 13u;
    x *= 0x94d049bbu;
    x ^= x >> 16u;
    return x;
}

void main() {
    uint x = gl_GlobalInvocationID.x;
    uint y = gl_GlobalInvocationID.y;

    if (x >= p.width || y >= p.height) return;

    uint idx  = y * p.width + x;
    uint cell = grid.cells[idx];
    uint mat  = cell & 0xFFu;
    uint seed = (cell >> 8u) & 0xFFu;

    // Rajaa materiaali-ID tunnettuun väliin (0-19)
    if (mat > 19u) mat = 0u;

    uvec3 color = mat_base_color(mat);
    uint  var_  = mat_variation(mat);

    // --- Seed-pohjainen värivariaatio ---
    if (var_ > 0u) {
        // seed [0,255] → offset [-var_, +var_] (kokonaisluku)
        int offset = int(seed) - 128;
        int scale  = int(var_);
        int off    = (offset * scale) / 128;

        color.r = uint(clamp(int(color.r) + off,          0, 255));
        color.g = uint(clamp(int(color.g) + off * 4 / 5,  0, 255));
        color.b = uint(clamp(int(color.b) + off * 3 / 5,  0, 255));
    }

    // --- Tulen välke (materiaalit 5 = FIRE) ---
    if (mat == FIRE) {
        // Pseudo-random flicker per pikseli per frame
        uint flick_h = hash(x * 374761393u ^ y * 668265263u ^ p.frame * 2654435769u);
        uint flicker  = flick_h & 0xFFu;          // [0,255]
        // Lisää punaiseen, skaala vihreää, poista sininen
        color.r = uint(min(255u, color.r + (flicker * 76u) / 255u));
        color.g = uint((color.g * (128u + flicker / 2u)) / 255u);
        color.b = uint((color.b * flicker) / 255u / 4u);
    }

    // --- Veden aaltoilu ---
    if (mat == WATER) {
        // sin-approksimaatio: käytä kokonaislukuaritmtiikkaa
        // wave = sin(x * 50/width_scale + frame * 0.15) * 0.025
        // Lasketaan approksimoidusti hash-pohjaisesti
        uint wave_h = hash(x * 12345u ^ p.frame * 6789u);
        int wave    = int((wave_h & 0xFFu)) - 128;   // [-128, 127]
        // Skaala: 0.025 * 255 ≈ 6
        int wave_scaled = (wave * 6) / 128;
        color.b = uint(clamp(int(color.b) + wave_scaled,         0, 255));
        color.g = uint(clamp(int(color.g) + wave_scaled / 2,     0, 255));
    }

    // --- Höyryn häive ---
    if (mat == STEAM) {
        // mix(EMPTY_väri, STEAM_väri, 0.5 + seed * 0.4/255)
        // EMPTY = (20, 20, 30), sekoituskerroin [0.5, 0.9]
        uint empty_r = 20u;
        uint empty_g = 20u;
        uint empty_b = 30u;
        // alpha = 128 + seed * 102 / 255  (seed [0,255] → alpha [128, 230])
        uint alpha = 128u + (seed * 102u) / 255u;   // [128, 230] / 255
        color.r = uint((color.r * alpha + empty_r * (255u - alpha)) / 255u);
        color.g = uint((color.g * alpha + empty_g * (255u - alpha)) / 255u);
        color.b = uint((color.b * alpha + empty_b * (255u - alpha)) / 255u);
    }

    // --- Bedrock-efekti: diagonaalinen raitakuvio ---
    if (mat == BEDROCK) {
        // Approksimoi sin((x+y)*800 + frame*0.3)*0.5+0.5
        uint stripe_h = hash((x + y) * 12345u ^ p.frame * 1234u);
        uint stripe = (stripe_h & 0xFFu);  // [0, 255]
        // mix(color, color * 0.6, stripe * 0.2 / 255) — tummennusefekti
        uint dark_mult = 255u - (stripe * 51u / 255u);  // 0.2 * stripe
        color.r = (color.r * dark_mult) / 255u;
        color.g = (color.g * dark_mult) / 255u;
        color.b = (color.b * dark_mult) / 255u;
    }

    // UNORM: arvo / 255 → [0.0, 1.0], imageStore ottaa vec4 (ei uvec4) rgba8-formaatissa
    vec4 out_color = vec4(float(color.r) / 255.0, float(color.g) / 255.0, float(color.b) / 255.0, 1.0);
    imageStore(rgba_image, ivec2(x, y), out_color);
}
