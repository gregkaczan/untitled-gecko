// Light out: the spread's result (the A half) as RGB8 per cell, the
// overlay texture sim.gd reads back.
#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

const uint O_P = 0u;
const uint O_CT = 2073870u;   // cell class per pixel: 0 air, 1 water, 2 static solid, 3 lava, 4 loose grain, 16 + id a chunk's cell
const uint O_LA = 4795470u;   // light, two uints per cell (RG and B as 16-bit): the result of the last tick's spread, and of this one
const uint O_LB = 5054670u;   // light, the spread's other half
const uint O_EM = 5313870u;   // emission per cell, packed RGB8, written by the particles (render_write.glsl)
const uint O_LO = 5443470u;   // the light as RGB8 per cell, for the overlay texture (light_out.glsl, read back by sim.gd)
const uint O_LP = 5573070u;   // light parameters (sim.gd): [0] decay of last tick's light, [1] glow count, [4..7] daylight rect x0 y0 x1 y1, [8..10] daylight colour, [11..14] passage of air, water, loose grains, solid; from [16] the glows, 8 floats each: x y r g b radius

float rf(uint i) { return uintBitsToFloat(buf.d[i]); }

// 16 bits a channel: with 8 the small loss per cell rounded away at low
// levels and the light stuck there instead of fading out.
vec3 at(uint base, uint i) {
    uint b = base + i * 2u;
    return vec3(unpackUnorm2x16(buf.d[b]), unpackUnorm2x16(buf.d[b + 1u]).x);
}

void put(uint base, uint i, vec3 l) {
    uint b = base + i * 2u;
    buf.d[b] = packUnorm2x16(l.rg);
    buf.d[b + 1u] = packUnorm2x16(vec2(l.b, 1.0));
}

void main() {
    uint id = gl_GlobalInvocationID.x;
    uint rw = uint(rf(O_P + 16u)), rh = uint(rf(O_P + 17u));
    if (id >= rw * rh) return;
    buf.d[O_LO + id] = packUnorm4x8(vec4(at(O_LA, id), 1.0));
}
