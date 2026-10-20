// Cell fold: the marked cell classes (cell_post.glsl) folded 2x2 onto
// the 4 px grid, for the gecko's coarse senses (the debug panel's
// "Senses 4 px"; sim_map.gd reads this back while it is on). Of the
// four cells the weightiest wins: static solid, a chunk's cell, then
// crumbling rock, moss, a loose grain, lava, water, air. A crumb counts
// as air, so a speck vanishes from the coarse senses altogether.
#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

const uint O_P = 0u;
const uint O_LN = 22291598u;  // marked cell classes (cell_post.glsl)
const uint O_C4 = 22809998u;  // the folded grid, (rw / 2) by (rh / 2)

float rf(uint i) { return uintBitsToFloat(buf.d[i]); }

uint weight(uint v) {
    if (v == 2u) return 8u;
    if (v >= 16u) return 7u;
    if (v == 6u) return 6u;
    if (v == 5u) return 5u;
    if (v == 4u) return 4u;
    if (v == 3u) return 3u;
    if (v == 1u) return 2u;
    return 0u;
}

void main() {
    uint id = gl_GlobalInvocationID.x;
    uint rw = uint(rf(O_P + 16u)), rh = uint(rf(O_P + 17u));
    uint fw = rw / 2u, fh = rh / 2u;
    if (id >= fw * fh) return;
    uint x = (id % fw) * 2u, y = (id / fw) * 2u;
    uint best = 0u, pri = 0u;
    for (uint j = 0u; j < 2u; j++) {
        for (uint i = 0u; i < 2u; i++) {
            uint v = buf.d[O_LN + (y + j) * rw + x + i];
            if (v >= 256u) v = 0u;
            uint w = weight(v);
            if (w > pri) { pri = w; best = v; }
        }
    }
    buf.d[O_C4 + id] = best;
}
