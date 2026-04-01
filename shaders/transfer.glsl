#[compute]
#version 450

// Transfer-shader: purkaa/pakkaa materiaali- ja seed-datat
// Mode 0 = extract: grid (uint32/pikseli) → mat_packed + seed_packed (uint8/pikseli)
// Mode 1 = pack: mat_packed + seed_packed → grid

layout(local_size_x = 64, local_size_y = 1, local_size_z = 1) in;

layout(set = 0, binding = 0, std430) restrict buffer GridData {
    uint cells[];
} grid;

layout(set = 0, binding = 1, std430) restrict buffer MatPacked {
    uint data[];
} mat_packed;

layout(set = 0, binding = 2, std430) restrict buffer SeedPacked {
    uint data[];
} seed_packed;

layout(push_constant, std430) uniform Params {
    uint total_quads;  // ceil(total / 4)
    uint total;        // w * h
    uint mode;         // 0 = extract, 1 = pack
    uint _pad;         // tasaus 16 tavuun
} p;

void main() {
    uint qid = gl_GlobalInvocationID.x;
    if (qid >= p.total_quads) return;
    uint base = qid * 4u;

    if (p.mode == 0u) {
        // Extract: grid → packed
        uint mat_word = 0u;
        uint seed_word = 0u;
        for (uint i = 0u; i < 4u && (base + i) < p.total; i++) {
            uint cell = grid.cells[base + i];
            mat_word |= (cell & 0xFFu) << (i * 8u);
            seed_word |= ((cell >> 8u) & 0xFFu) << (i * 8u);
        }
        mat_packed.data[qid] = mat_word;
        seed_packed.data[qid] = seed_word;
    } else {
        // Pack: packed → grid
        uint mat_word = mat_packed.data[qid];
        uint seed_word = seed_packed.data[qid];
        for (uint i = 0u; i < 4u && (base + i) < p.total; i++) {
            uint mat = (mat_word >> (i * 8u)) & 0xFFu;
            uint seed_val = (seed_word >> (i * 8u)) & 0xFFu;
            grid.cells[base + i] = mat | (seed_val << 8u);
        }
    }
}
