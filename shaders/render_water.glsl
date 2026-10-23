// Fluid metaball composite — per-pixel blending for water and lava. Reads density
// buffers (populated by render_write with atomicAdd), applies Gaussian gather to
// smooth nearby contributions into continuous bodies, and writes to the render buffer.
// Water uses alpha 0.98, lava uses alpha 0.99 — both below terrain (1.0) so
// atomicMax compositing keeps solids on top.
#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

const uint O_P = 0u, O_M = 40u, O_GC = 136u, O_GP = 57736u, O_PT = 1900936u, O_RN = 6048136u;
const uint O_WD = 6566536u;
const uint O_LD = 7084936u;
const uint O_CD = 7603336u;
const uint O_CT = 8294670u;    // cell class per pixel (render_write.glsl): 2, 4 to 7 and 16 up are solid, 8 slime
const uint O_SB = 25039822u;   // slime brains [x, y, reach, pull, drift x, drift y, drift speed, on] (sim.gd set_slime)
const uint O_SD = 25040014u;   // slime density per cell (render_write.glsl)

float rf(uint i) { return uintBitsToFloat(buf.d[i]); }

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
}

float hash21(vec2 p) {
    vec3 q = fract(vec3(p.xyx) * 0.1031);
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

float vnoise(vec2 p) {
    vec2 i = floor(p), f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

// The slime's density at a cell, gathered as main() gathers it.
float slime_gather(int x, int y, uint rw, uint rh) {
    float d = 0.0;
    for (int dy = -2; dy <= 2; dy++) {
        for (int dx = -2; dx <= 2; dx++) {
            int sx = x + dx, sy = y + dy;
            if (sx < 0 || sx >= int(rw) || sy < 0 || sy >= int(rh)) continue;
            uint sd = buf.d[O_SD + uint(sy) * rw + uint(sx)];
            if (sd > 0u) d += float(sd) * exp(-float(dx * dx + dy * dy) / 2.0);
        }
    }
    return d;
}

// Something solid in the cell: what a slime rests on or leans against.
bool cell_solid(int x, int y, uint rw, uint rh) {
    if (x < 0 || x >= int(rw) || y < 0 || y >= int(rh)) return false;
    uint cls = buf.d[O_CT + uint(y) * rw + uint(x)];
    return cls == 2u || (cls >= 4u && cls != 8u);
}

// Neither solid nor any slime in the cell or the eight about it: the air
// outside the slime's body.
bool slime_out(int x, int y, uint rw, uint rh) {
    if (x < 0 || x >= int(rw) || y < 0 || y >= int(rh)) return true;
    if (cell_solid(x, y, rw, rh)) return false;
    if (buf.d[O_SD + uint(y) * rw + uint(x)] > 0u) return false;
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int sx = x + dx, sy = y + dy;
            if (sx < 0 || sx >= int(rw) || sy < 0 || sy >= int(rh)) continue;
            if (buf.d[O_SD + uint(sy) * rw + uint(sx)] > 0u) return false;
        }
    }
    return true;
}

float compute_light(float px, float py) {
    float ground_y = 324.0;
    if (py < ground_y) return 1.0;

    float surface_fade_depth = 270.0 * 2.0;
    float depth_below = py - ground_y;
    float surface_light = clamp(1.0 - depth_below / surface_fade_depth, 0.0, 1.0);
    surface_light *= surface_light;

    float dpx = rf(O_P + 9u), dpy = rf(O_P + 10u);
    float ddx = rf(O_P + 11u), ddy = rf(O_P + 12u);
    float dx = px - dpx, dy = py - dpy;
    float dist = sqrt(dx * dx + dy * dy);
    float light_r = 160.0;
    float drill_light = clamp(1.0 - (dist / light_r) * (dist / light_r), 0.0, 1.0);

    float forward_dot = -(dx * ddx + dy * ddy) / max(dist, 1.0);
    float dir_bias = 0.4 + 0.6 * clamp(forward_dot * 0.5 + 0.5, 0.0, 1.0);
    drill_light *= dir_bias;

    return clamp(max(surface_light, drill_light), 0.04, 1.0);
}

void main() {
    uint id = gl_GlobalInvocationID.x;
    uint rw = uint(rf(O_P + 16u));
    uint rh = uint(rf(O_P + 17u));
    uint total = rw * rh;
    if (id >= total) return;

    int px = int(id % rw);
    int py = int(id / rw);

    // Gaussian-weighted 5x5 gather from water and lava density buffers (sigma ~1.2)
    float water_density = 0.0;
    float lava_density = 0.0;
    float clay_density = 0.0;
    float slime_density = 0.0;
    const int R = 2;
    for (int dy = -R; dy <= R; dy++) {
        for (int dx = -R; dx <= R; dx++) {
            int sx = px + dx;
            int sy = py + dy;
            if (sx < 0 || sx >= int(rw) || sy < 0 || sy >= int(rh)) continue;
            uint idx = uint(sy) * rw + uint(sx);
            float dist_sq = float(dx * dx + dy * dy);

            uint wd = buf.d[O_WD + idx];
            if (wd > 0u) {
                float w_weight = exp(-dist_sq / 2.88); // 2 * 1.2^2
                water_density += float(wd) * w_weight;
            }

            uint ld = buf.d[O_LD + idx];
            if (ld > 0u) {
                float l_weight = exp(-dist_sq / 2.88); // same sigma as water
                lava_density += float(ld) * l_weight;
            }

            // Clay: tight 3x3 gather with sigma ~0.4 (2*0.4^2 = 0.32)
            uint sd = buf.d[O_SD + idx];
            if (sd > 0u) slime_density += float(sd) * exp(-dist_sq / 2.0);

            if (dx >= -1 && dx <= 1 && dy >= -1 && dy <= 1) {
                uint cd = buf.d[O_CD + idx];
                if (cd > 0u) {
                    float c_weight = exp(-dist_sq / 0.32);
                    clay_density += float(cd) * c_weight;
                }
            }
        }
    }

    bool has_water = (water_density >= 0.35);
    bool has_lava = (lava_density >= 0.35);
    bool has_clay = (clay_density >= 0.5);
    bool has_slime = (slime_density >= 0.9);
    if (!has_water && !has_lava && !has_clay && !has_slime) return;

    float psz = rf(O_P + 18u);
    float wx = (float(px) + 0.5) * psz;
    float wy = (float(py) + 0.5) * psz;
    float world_h = rf(O_P + 3u);
    float depth_shade = 1.0 - (wy / world_h) * 0.2;

    float lighting_on = rf(O_P + 27u);
    float light = (lighting_on > 0.5) ? compute_light(wx, wy) : 1.0;

    // --- Water metaball ---
    if (has_water) {
        float d_norm = clamp((water_density - 0.35) / 3.0, 0.0, 1.0);

        float cr = 0.06 + 0.14 * (1.0 - d_norm);
        float cg = 0.25 + 0.20 * (1.0 - d_norm);
        float cb = 0.60 + 0.30 * (1.0 - d_norm);

        float shimmer = hash11(wx * 0.07 + wy * 0.13) * 0.07;
        cb += shimmer;
        cg += shimmer * 0.3;
        float shimmer2 = hash11(wx * 0.19 + wy * 0.31) * 0.04;
        cg += shimmer2;

        cr *= depth_shade;
        cg *= depth_shade;
        cb *= depth_shade;

        cr *= light;
        cg *= light;
        cb *= light;

        cr = clamp(cr, 0.0, 1.0);
        cg = clamp(cg, 0.0, 1.0);
        cb = clamp(cb, 0.0, 1.0);

        atomicMax(buf.d[O_RN + id], packUnorm4x8(vec4(cr, cg, cb, 0.98)));
    }

    // --- Lava metaball ---
    if (has_lava) {
        float d_norm = clamp((lava_density - 0.35) / 2.5, 0.0, 1.0);

        float lava_h = hash11(wx * 0.13 + wy * 0.19);
        float pulse = 0.85 + 0.15 * sin(wx * 0.05 + wy * 0.07);

        float cr = (0.95 + lava_h * 0.05) * pulse;
        float cg = mix(0.45, 0.20, d_norm) + lava_h * 0.10;
        float cb = 0.02 + lava_h * 0.03;
        cg *= pulse;

        float bright = step(0.82, hash11(wx * 0.07 + wy * 0.11));
        cr += bright * 0.05;
        cg += bright * 0.20;

        cr *= depth_shade;
        cg *= depth_shade;
        cb *= depth_shade;

        float lava_light = max(light, 0.80);
        cr *= lava_light;
        cg *= lava_light;
        cb *= lava_light;

        cr = clamp(cr, 0.0, 1.0);
        cg = clamp(cg, 0.0, 1.0);
        cb = clamp(cb, 0.0, 1.0);

        atomicMax(buf.d[O_RN + id], packUnorm4x8(vec4(cr, cg, cb, 0.99)));
    }

    // --- Slime: banded by depth like a jelly drawn by hand. A bright
    //     yellow rim a pixel wide where it meets air, a lime band with a
    //     darker yellow crescent and a pale gleam where the light falls
    //     (up and to the left), green inside that, licking up into a
    //     dark green core in tongues that rise slowly. The depth is
    //     the distance to the nearest air with no slime about it (rock
    //     counts as more slime), taken over the body's thickness there,
    //     so a big slime and a puddle band alike. The pattern is laid
    //     out from its brain's centre and travels with the blob. Drawn
    //     over the water. ---
    if (has_slime) {
        bool rim = false;
        ivec2 side[4] = ivec2[4](ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1));
        for (int j = 0; j < 4; j++) {
            ivec2 q = ivec2(px, py) + side[j];
            if (!cell_solid(q.x, q.y, rw, rh) && slime_gather(q.x, q.y, rw, rh) < 0.9) rim = true;
        }
        float depth = 17.0;
        vec2 out_dir = vec2(0.0, -1.0);
        for (int k = 1; k <= 16; k++) {
            if (float(k) >= depth) break;   // a ring k away is no nearer than k
            for (int i = -k; i <= k; i++) {
                ivec2 ring[4] = ivec2[4](ivec2(i, -k), ivec2(i, k), ivec2(-k, i), ivec2(k, i));
                for (int j = 0; j < 4; j++) {
                    vec2 o = vec2(ring[j]);
                    float dl = length(o);
                    if (dl < depth && slime_out(px + ring[j].x, py + ring[j].y, rw, rh)) { depth = dl; out_dir = normalize(o); }
                }
            }
        }
        vec2 origin = vec2(0.0);
        float best = 1e9;
        for (uint i = 0u; i < 16u; i++) {
            uint o = O_SB + i * 8u;
            if (rf(o + 7u) < 0.5) continue;
            vec2 c = vec2(rf(o), rf(o + 1u));
            float dd = length(vec2(wx, wy) - c);
            if (dd < rf(o + 2u) && dd < best) { best = dd; origin = c; }
        }
        vec2 lp = (vec2(wx, wy) - origin) / psz;   // cells from the centre (a puddle: from the world's corner)
        float t = rf(O_P + 21u) / 60.0;
        // Which way this part of the body faces, from its centre (the
        // nearest edge's way jumps from pixel to pixel): the light falls
        // up and to the left, the lime is thickest on top, and the green
        // licks up into the core from below.
        vec2 face = best < 1e9 ? normalize(lp + vec2(0.0, 0.001)) : -out_dir;
        // The far side: on from here through the centre. Rock
        // there is a mirror (the body goes on as far again as it came),
        // so a mound bands like the top half of a drop, its core on the
        // floor.
        float across = 40.0;
        for (int k = 1; k <= 40; k++) {
            ivec2 q = ivec2(px, py) + ivec2(round(-face * float(k)));
            if (cell_solid(q.x, q.y, rw, rh)) { across = 2.0 * float(k) + depth; break; }
            if (slime_out(q.x, q.y, rw, rh)) { across = float(k); break; }
        }
        float thick = depth + across;
        float u = depth / max(thick * 0.5, 1.0);   // 0 at the edge, 1 midway through
        float lit = dot(face, normalize(vec2(-0.8, -0.6)));
        float lime_u = 0.14 + 0.22 * max(0.0, -face.y);
        float flame = (vnoise(vec2(lp.x * 0.8, lp.y * 0.25 + t * 0.4)) - 0.35) * 0.5 * clamp(0.5 + face.y, 0.15, 1.2);
        float green_u = lime_u + 0.16 + flame;
        vec3 col;
        if (rim) {
            col = vec3(0.945, 0.949, 0.176);                                // #f1f22d
        } else if (u < lime_u || depth < 2.5) {
            col = vec3(0.522, 0.757, 0.0);                                  // #85c100
            float crescent = 1.5 + min(0.03 * thick, 2.5) * smoothstep(0.45, 0.95, lit);   // tapers off to either side
            if (thick > 10.0 && lit > 0.45 && depth < crescent) col = vec3(0.875, 0.859, 0.0);                          // #dfdb00, the lit crescent
            if (thick > 16.0 && lit > 0.85 && depth >= crescent && depth < crescent + 1.2) col = vec3(1.0, 0.988, 0.0);   // #fffc00, the gleam
        } else if (u < green_u || depth < 3.5) {
            col = vec3(0.0, 0.624, 0.0);                                    // #009f00
        } else {
            col = vec3(0.0, 0.322, 0.024);                                  // #005206
            if (thick > 16.0 && u < green_u + 0.08 && ((px + py) & 1) == 0) col = vec3(0.0, 0.404, 0.122);   // #00671f
        }
        col *= light;
        atomicMax(buf.d[O_RN + id], packUnorm4x8(vec4(clamp(col, 0.0, 1.0), 1.0)));
    }

    // --- Clay metaball (tight 3x3 gather around each particle) ---
    if (has_clay) {
        float d_norm = clamp((clay_density - 0.5) / 2.0, 0.0, 1.0);
        float cr = rf(O_M + 2u * 12u + 6u);
        float cg = rf(O_M + 2u * 12u + 7u);
        float cb = rf(O_M + 2u * 12u + 8u);
        float shimmer = hash11(wx * 0.031 + wy * 0.017) * 0.08;
        cr += shimmer;
        cg += shimmer * 0.9;
        cb += shimmer * 0.7;

        cr *= depth_shade;
        cg *= depth_shade;
        cb *= depth_shade;

        cr *= light;
        cg *= light;
        cb *= light;

        cr = clamp(cr, 0.0, 1.0);
        cg = clamp(cg, 0.0, 1.0);
        cb = clamp(cb, 0.0, 1.0);

        atomicMax(buf.d[O_RN + id], packUnorm4x8(vec4(cr, cg, cb, 1.0)));
    }
}
