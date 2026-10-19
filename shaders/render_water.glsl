// Fluid metaball composite — per-pixel blending for water and lava. Reads density
// buffers (populated by render_write with atomicAdd), applies Gaussian gather to
// smooth nearby contributions into continuous bodies, and writes to the render buffer.
// Water uses alpha 0.98, lava uses alpha 0.99 — both below terrain (1.0) so
// atomicMax compositing keeps solids on top.
#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

const uint O_P = 0u, O_M = 40u, O_GC = 136u, O_GP = 14536u, O_PT = 475336u, O_RN = 1512136u;
const uint O_WD = 1641736u;
const uint O_LD = 1771336u;
const uint O_CD = 1900936u;

float rf(uint i) { return uintBitsToFloat(buf.d[i]); }

float hash11(float p) {
    p = fract(p * 0.1031);
    p *= p + 33.33;
    p *= p + p;
    return fract(p);
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
    if (!has_water && !has_lava && !has_clay) return;

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
