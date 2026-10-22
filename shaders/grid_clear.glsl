// Spatial grid clear — zeroes all cell particle counts before grid_insert.
// The grid partitions the world into GW×GH cells for O(1) neighbor lookup
// in the PBD constraint solver (avoids O(n²) all-pairs search).
#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

const uint GW = 320u, GH = 180u, MPC = 32u, PC = 518400u;
const uint O_P = 0u, O_M = 40u, O_GC = 136u, O_GP = 57736u, O_PT = 1900936u, O_RN = 6048136u;
// Solid-only cell counts (sand, clay, rock, wood, ores). The ship collides with these.
const uint O_SC = 8237070u;
const uint O_BC = 25037774u;   // the skinned chunks' particle count per bone (sim.gd), counted again by render_write.glsl
const uint O_SS = 25039950u;   // the slime brains' counts and sums, the same

float rf(uint i) { return uintBitsToFloat(buf.d[i]); } // reinterpret stored uint as float

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id < 2048u) buf.d[O_BC + id] = 0u;
    if (id < 64u) buf.d[O_SS + id] = 0u;
    if (id >= GW * GH) return; // one thread per grid cell (160×90 = 14400 cells)
    buf.d[O_GC + id] = 0u; // reset this cell's particle count to zero
    buf.d[O_SC + id] = 0u;
}
