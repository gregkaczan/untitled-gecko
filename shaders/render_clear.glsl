// Render clear — resets every pixel to black and zeroes the water density buffer.
// Must run first because render_write uses atomicMax for compositing, which needs
// a zero baseline (otherwise stale bright pixels from previous frames would persist).
#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

const uint GW = 320u, GH = 180u, MPC = 32u, PC = 518400u;
const uint O_P = 0u, O_M = 40u, O_GC = 136u, O_GP = 57736u, O_PT = 1900936u, O_RN = 6048136u;
const uint O_WD = 6566536u;
const uint O_LD = 7084936u;
const uint O_CD = 7603336u;
const uint O_CT = 8294670u;   // cell class per pixel: 0 air, 1 water, 2 static solid, 3 lava, 4 loose grain, 16 + id a chunk's cell
const uint O_EM = 21254670u;
const uint O_SD = 25040014u;   // slime density per cell (render_write.glsl, render_water.glsl)   // emission per cell (light_seed.glsl), written by render_write.glsl

float rf(uint i) { return uintBitsToFloat(buf.d[i]); }

void main() {
    uint id = gl_GlobalInvocationID.x;
    uint total = uint(rf(O_P + 16u)) * uint(rf(O_P + 17u));
    if (id >= total) return;
    buf.d[O_RN + id] = packUnorm4x8(vec4(0.0, 0.0, 0.0, 0.0));
    buf.d[O_WD + id] = 0u;
    buf.d[O_LD + id] = 0u;
    buf.d[O_CD + id] = 0u;
    buf.d[O_CT + id] = 0u;
    buf.d[O_EM + id] = 0u;
    buf.d[O_SD + id] = 0u;
}
