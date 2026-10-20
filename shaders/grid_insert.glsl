// Spatial grid insert — bins each particle into a grid cell by its predicted position.
// Uses predicted (not current) position because the PBD solver operates on predictions.
// Each cell holds up to MPC=32 particle IDs; overflow particles are silently dropped.
#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

const uint GW = 320u, GH = 180u, MPC = 32u, PC = 518400u;
const uint O_P = 0u, O_M = 40u, O_GC = 136u, O_GP = 57736u, O_PT = 1900936u, O_RN = 6048136u;
// Solid-only cell counts, read back by the CPU for ship collision.
const uint O_SC = 8237070u;

float rf(uint i) { return uintBitsToFloat(buf.d[i]); }

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= PC) return;

    float cs = rf(O_P + 6u); // cell_size: world-space width/height of each grid cell
    uint b = O_PT + id * 8u; // base offset into this particle's 8-float data block
    float px = rf(b + 4u), py = rf(b + 5u); // predicted position (pred.x, pred.y)

    // Map world-space position to integer grid cell coordinates
    int cx = int(floor(px / cs));
    int cy = int(floor(py / cs));
    if (cx < 0 || cx >= int(GW) || cy < 0 || cy >= int(GH)) return; // discard out-of-bounds

    uint cell = uint(cy) * GW + uint(cx); // row-major cell index
    uint mat = uint(rf(b + 7u));
    if ((mat < 8u && mat != 1u) || mat == 12u) {
        atomicAdd(buf.d[O_SC + cell], 1u);
    }
    uint slot = atomicAdd(buf.d[O_GC + cell], 1u); // atomically claim a slot in this cell
    if (slot < MPC) {
        buf.d[O_GP + cell * MPC + slot] = id; // store particle ID in the cell's list
    }
    // If slot >= MPC the cell is full — particle won't be found by neighbors this frame.
    // Acceptable trade-off: caps memory and keeps solver cost bounded.
}
