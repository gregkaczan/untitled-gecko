#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

const uint GW = 160u, GH = 90u, MPC = 32u, PC = 129600u;
const uint O_P = 0u, O_M = 40u, O_GC = 136u, O_GP = 14536u, O_PT = 475336u, O_RN = 1512136u;
const uint O_NF = 2030536u;
const uint O_NP = 2059336u;

float rf(uint i) { return uintBitsToFloat(buf.d[i]); }
void wf(uint i, float v) { buf.d[i] = floatBitsToUint(v); }

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= PC) return;

    float dt = rf(O_P);
    float ww = rf(O_P + 2u), wh = rf(O_P + 3u);

    uint b = O_PT + id * 8u;
    float ox = rf(b), oy = rf(b + 1u);
    float px = rf(b + 4u), py = rf(b + 5u);
    float mat_raw = rf(b + 7u);
    uint mat = uint(mat_raw);

    // --- Bullet finalize: lifetime decay, velocity preservation ---
    if (mat == 11u) {
        if (ox < -500.0) return; // already killed by collision in delta

        float life = mat_raw - 11.0;
        life -= 0.0005;
        float margin = 2.0;
        if (life <= 0.001 || px < margin || px > ww - margin || py < margin || py > wh - margin) {
            wf(b, -1000.0); wf(b + 1u, -1000.0);
            wf(b + 2u, 0.0); wf(b + 3u, 0.0);
            wf(b + 4u, -1000.0); wf(b + 5u, -1000.0);
            wf(b + 7u, 0.0);
            return;
        }
        wf(b + 7u, 11.0 + life);

        float vx = (px - ox) / dt;
        float vy = (py - oy) / dt;

        wf(b, px); wf(b + 1u, py);
        wf(b + 2u, vx); wf(b + 3u, vy);
        return;
    }

    float visc, fric, yield_s;
    if (mat < 8u) {
        visc = rf(O_M + mat * 12u + 2u);
        fric = rf(O_M + mat * 12u + 4u);
        yield_s = rf(O_M + mat * 12u + 5u);
    } else if (mat == 10u) {
        visc = 0.35; fric = 0.15; yield_s = 0.0;
    } else if (mat == 12u) {
        visc = 0.0; fric = 0.4; yield_s = 2.0;
    } else if (mat == 13u) {
        visc = 0.02; fric = 0.05; yield_s = 0.0;
    } else {
        visc = 0.01; fric = 0.0; yield_s = 0.0;
    }

    // --- Ephemeral life decay (fire and smoke) ---
    if (mat == 8u || mat == 9u) {
        float life = mat_raw - float(mat);
        uint hash = id * 2654435761u;
        float rand01 = float(hash >> 16u) / 65535.0;
        float decay = (mat == 8u) ? 0.00055 * (0.4 + rand01 * 1.2) : 0.00008 * (0.3 + rand01 * 1.4);
        life -= decay;
        if (life <= 0.001) {
            wf(b, -1000.0);
            wf(b + 1u, -1000.0);
            wf(b + 2u, 0.0);
            wf(b + 3u, 0.0);
            wf(b + 4u, -1000.0);
            wf(b + 5u, -1000.0);
            wf(b + 7u, 0.0);
            return;
        }
        wf(b + 7u, float(mat) + life);
    }

    if (yield_s >= 5.0) {
        float moved = length(vec2(px - ox, py - oy));
        if (moved < 0.01) return;
    }

    float vx = (px - ox) / dt;
    float vy = (py - oy) / dt;

    vx *= (1.0 - visc);
    vy *= (1.0 - visc);
    vx *= (1.0 - fric);

    float speed = length(vec2(vx, vy));
    bool never_sleep = (mat == 1u) || (mat == 8u) || (mat == 9u) || (mat == 10u) || (mat == 13u);
    if (!never_sleep) {
        float sleep_thresh = 3.0;
        float snap_thresh = 0.5;
        if (speed < sleep_thresh) {
            float fade = speed / sleep_thresh;
            fade = fade * fade;
            vx *= fade;
            vy *= fade;
            if (speed < snap_thresh) {
                vx = 0.0;
                vy = 0.0;
                px = ox;
                py = oy;
            }
        }
    }

    // NPC flow field movement + jump AI: body particle drives locomotion
    if (mat == 13u) {
        uint mat_enc = uint(round(fract(mat_raw) * 1000.0));
        bool is_body = (mat_enc & 1u) == 0u;
        if (is_body) {
            float cs = rf(O_P + 6u);
            int cx = int(floor(px / cs));
            int cy = int(floor(py / cs));

            float flow_dx = 0.0;
            if (cx >= 0 && cx < int(GW) && cy >= 0 && cy < int(GH)) {
                uint fi = (uint(cy) * GW + uint(cx)) * 2u;
                flow_dx = rf(O_NF + fi);
            }

            float npc_speed = rf(O_NP + 2u);
            if (abs(flow_dx) > 0.001) {
                vx += flow_dx * npc_speed;
            } else {
                uint frame = uint(rf(O_P + 36u));
                uint creature_hash = id * 2654435761u;
                uint period_len = 90u + (creature_hash & 63u);
                uint period = frame / period_len;
                float dir = ((period & 1u) == 0u) ? 1.0 : -1.0;
                vx += dir * 15.0;
            }

            float move_dir = (abs(flow_dx) > 0.001) ? sign(flow_dx) : sign(vx);
            int ahead_cx = cx + int(move_dir);

            if (ahead_cx >= 0 && ahead_cx < int(GW) && cy >= 0 && cy < int(GH)) {
                uint ahead_count = buf.d[O_GC + uint(cy) * GW + uint(ahead_cx)];
                bool blocked = ahead_count > 3u;

                bool grounded = false;
                if (cy + 1 < int(GH)) {
                    grounded = buf.d[O_GC + uint(cy + 1) * GW + uint(cx)] > 2u;
                }

                if (blocked && grounded && vy > -10.0) {
                    vy = -100.0;
                    vx += move_dir * 20.0;
                }
            }
        }
    }

    float maxv = rf(O_P + 28u) > 0.0 ? 1500.0 : 300.0;
    // Also raise cap if deferred bullet explosion is active
    if (rf(O_P + 37u) > 0.0) maxv = 1500.0;
    if (mat == 13u) maxv = 110.0;
    vx = clamp(vx, -maxv, maxv);
    vy = clamp(vy, -maxv, maxv);

    float margin = 2.0;
    px = clamp(px, margin, ww - margin);
    py = clamp(py, margin, wh - margin);

    wf(b, px);
    wf(b + 1u, py);
    wf(b + 2u, vx);
    wf(b + 3u, vy);
}
