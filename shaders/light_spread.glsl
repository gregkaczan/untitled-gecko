// Light spread: one step of light from cell to cell. A cell takes the
// brightest of its four neighbours times what it lets through: most of
// it through air, less through water, little through loose grains, and
// a fraction into solid, so a rock face lights up a cell or two deep
// and the rock behind stays dark. Passes alternate between the two
// halves (the push constant's parity: even reads B and writes A, odd
// the other way); sim.gd runs an odd number, so the result lands in A,
// where light_seed.glsl and light_out.glsl expect it. Light further
// from a source than one tick's passes reach is carried on from last
// tick's decayed field, so the fall-off per cell is the passage times
// the decay spread over the passes (sim.gd sets the passage with that
// in mind).
#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

const uint O_P = 0u;
const uint O_CT = 8294670u;   // cell class per pixel: 0 air, 1 water, 2 static solid, 3 lava, 4 loose grain, 16 + id a chunk's cell
const uint O_LA = 19181070u;   // light, two uints per cell (RG and B as 16-bit): the result of the last tick's spread, and of this one
const uint O_LB = 20217870u;   // light, the spread's other half
const uint O_EM = 21254670u;   // emission per cell, packed RGB8, written by the particles (render_write.glsl)
const uint O_LO = 21773070u;   // the light as RGB8 per cell, for the overlay texture (light_out.glsl, read back by sim.gd)
const uint O_LP = 22291470u;   // light parameters (sim.gd): [0] decay of last tick's light, [1] glow count, [4..7] daylight rect x0 y0 x1 y1, [8..10] daylight colour, [11..14] passage of air, water, loose grains, solid; from [16] the glows, 8 floats each: x y r g b radius x2 y2 (a strip to x2 y2, a cone when the radius is negative)

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

layout(push_constant, std430) uniform Pass { uvec4 v; } pc;

void main() {
    uint id = gl_GlobalInvocationID.x;
    uint rw = uint(rf(O_P + 16u)), rh = uint(rf(O_P + 17u));
    if (id >= rw * rh) return;
    uint x = id % rw, y = id / rw;
    uint src = (pc.v.x % 2u == 0u) ? O_LB : O_LA;
    uint dst = (pc.v.x % 2u == 0u) ? O_LA : O_LB;
    uint cls = buf.d[O_CT + id];
    float k;
    if (cls == 0u) k = rf(O_LP + 11u);
    else if (cls == 1u || cls == 3u) k = rf(O_LP + 12u);
    else if (cls == 4u || cls == 8u) k = rf(O_LP + 13u);
    else k = rf(O_LP + 14u);
    vec3 n = vec3(0.0);
    if (x > 0u) n = max(n, at(src, id - 1u));
    if (x + 1u < rw) n = max(n, at(src, id + 1u));
    if (y > 0u) n = max(n, at(src, id - rw));
    if (y + 1u < rh) n = max(n, at(src, id + rw));
    vec3 l = max(at(src, id), n * k - 1.0 / 65535.0);
    put(dst, id, l);
}
