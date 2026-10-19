#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

const uint GW = 160u, GH = 90u, MPC = 32u, PC = 129600u;
const uint O_P = 0u, O_M = 40u, O_GC = 136u, O_GP = 14536u, O_PT = 475336u, O_RN = 1512136u;
const uint O_NP = 2059336u; // NPC tunable params: [0]=separation [1]=cohesion [2]=flow_speed
// Capsule erosion slots for drone drills. Only this shader reads them.
// Slot layout: [pos.x, pos.y, dir.x, dir.y, radius, half_length, active, melt]
// melt > 0 turns the slot into a melter: each tick every ground particle
// inside vanishes with that probability, and nothing inside is pushed.
const uint O_CAP = 2059339u;
const uint N_CAP = 8u;
// Feedback block (see simulation.gd O_FB):
// [0] player contact count, [1] creature kills, [2] impact count,
// [3 + i*2] impact packed position (y << 12 | x), [4 + i*2] impact kind
const uint O_FB = 2059403u;
const uint MAX_IMPACTS = 32u;
// Impact kinds 0..9 are bullet kinds. 15 marks a purple ore detonation.
const uint KIND_PURPLE = 15u;

float rf(uint i) { return uintBitsToFloat(buf.d[i]); }
void wf(uint i, float v) { buf.d[i] = floatBitsToUint(v); }

vec2 kernel_grad(vec2 diff, float r, float h) {
    if (r < 0.001 || r >= h) return vec2(0.0);
    float q = 1.0 - r / h;
    return (-3.0 / (h * r)) * q * q * diff;
}

float capsule_dist(vec2 p, vec2 ca, vec2 cb) {
    vec2 pa = p - ca, ba = cb - ca;
    float t = clamp(dot(pa, ba) / max(dot(ba, ba), 0.001), 0.0, 1.0);
    return length(p - (ca + ba * t));
}

// Appends one impact to the feedback list. Dropped when the list is full.
// kind holds the impact kind in bits 0..6; bit 7 set means a bullet caused
// it and bits 8.. hold that bullet's particle index, so the CPU can drop
// its mirror of the bullet.
const uint IMPACT_FROM_BULLET = 0x80u;
void push_impact(float x, float y, uint kind) {
    uint i = atomicAdd(buf.d[O_FB + 2u], 1u);
    if (i >= MAX_IMPACTS) return;
    uint packed = (uint(clamp(y, 0.0, 4095.0)) << 12u) | uint(clamp(x, 0.0, 4095.0));
    buf.d[O_FB + 3u + i * 2u] = packed;
    buf.d[O_FB + 4u + i * 2u] = kind;
}

void kill_particle(uint b) {
    wf(b, -1000.0); wf(b + 1u, -1000.0);
    wf(b + 2u, 0.0); wf(b + 3u, 0.0);
    wf(b + 4u, -1000.0); wf(b + 5u, -1000.0);
    wf(b + 7u, 0.0);
}

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= PC) return;

    float cs = rf(O_P + 6u);
    float h = rf(O_P + 7u);
    float ww = rf(O_P + 2u), wh = rf(O_P + 3u);

    uint b = O_PT + id * 8u;
    float px = rf(b + 4u), py = rf(b + 5u);
    float vx = rf(b + 2u), vy = rf(b + 3u);
    float lambda_i = rf(b + 6u);
    float mat_f = rf(b + 7u);
    uint mat_i = uint(mat_f);

    // --- Bullet collision detection (ray-march from old to predicted pos) ---
    // Kind 0..7 are player bullets, 8..9 are enemy bullets. Player bullets
    // get a grace period while they overlap the ship capsule. Enemy
    // bullets explode on the ship capsule instead.
    if (mat_i == 11u) {
        if (rf(b + 6u) > 0.5) return;
        wf(b + 6u, 1.0);

        uint kind = uint(round(fract(mat_f) * 100.0));
        bool enemy_shot = kind >= 8u;

        float ox = rf(b), oy = rf(b + 1u);

        float dpx = rf(O_P + 9u), dpy = rf(O_P + 10u);
        float d_dx = rf(O_P + 11u), d_dy = rf(O_P + 12u);
        float dr = rf(O_P + 13u), dhl = rf(O_P + 14u);
        vec2 cap_a = vec2(dpx - d_dx * dhl, dpy - d_dy * dhl);
        vec2 cap_b = vec2(dpx + d_dx * dhl, dpy + d_dy * dhl);
        float dist_to_drill = capsule_dist(vec2(px, py), cap_a, cap_b);
        float drill_clear = dr + 8.0;
        if (!enemy_shot && dist_to_drill < drill_clear) return;

        float travel_dx = px - ox, travel_dy = py - oy;
        float travel_len = length(vec2(travel_dx, travel_dy));

        float step_size = 4.0;
        int num_steps = max(int(ceil(travel_len / step_size)), 1);

        bool hit = false;
        bool hit_purple = false;
        bool hit_player = false;
        float hit_x = px, hit_y = py;

        for (int s = 0; s <= num_steps && !hit; s++) {
            float t = float(s) / float(num_steps);
            float sx = ox + travel_dx * t;
            float sy = oy + travel_dy * t;

            float d_ship = capsule_dist(vec2(sx, sy), cap_a, cap_b);
            if (enemy_shot) {
                if (d_ship < dr + 2.0) {
                    hit = true; hit_player = true;
                    hit_x = sx; hit_y = sy;
                    break;
                }
            } else if (d_ship < drill_clear) {
                continue;
            }

            int cx = int(floor(sx / cs));
            int cy = int(floor(sy / cs));

            for (int dy = -1; dy <= 1 && !hit; dy++) {
                for (int dx = -1; dx <= 1 && !hit; dx++) {
                    int nx = cx + dx, ny = cy + dy;
                    if (nx < 0 || nx >= int(GW) || ny < 0 || ny >= int(GH)) continue;
                    uint cell = uint(ny) * GW + uint(nx);
                    uint count = min(buf.d[O_GC + cell], MPC);
                    for (uint k = 0u; k < count; k++) {
                        uint j = buf.d[O_GP + cell * MPC + k];
                        if (j == id) continue;
                        uint bj = O_PT + j * 8u;
                        float jx = rf(bj + 4u), jy = rf(bj + 5u);
                        float dist = length(vec2(sx - jx, sy - jy));
                        if (dist < 6.0) {
                            uint mat_j = uint(rf(bj + 7u));
                            if (mat_j < 8u || mat_j == 12u || mat_j == 13u) {
                                hit = true;
                                hit_x = sx;
                                hit_y = sy;
                                if (mat_j == 12u) hit_purple = true;
                                break;
                            }
                        }
                    }
                }
            }
        }

        if (hit) {
            push_impact(hit_x, hit_y, (hit_purple ? KIND_PURPLE : kind) | IMPACT_FROM_BULLET | (id << 8u));
            kill_particle(b);
        }
        return;
    }

    // Load material properties; ephemerals and purple ore use hardcoded values
    float rho0, cohesion, yield_s, fric_val;
    if (mat_i < 8u) {
        rho0 = rf(O_M + mat_i * 12u);
        cohesion = rf(O_M + mat_i * 12u + 3u);
        yield_s = rf(O_M + mat_i * 12u + 5u);
        fric_val = rf(O_M + mat_i * 12u + 4u);
    } else if (mat_i == 8u) {
        rho0 = 1.2; cohesion = 0.0; yield_s = 0.0; fric_val = 0.0;
    } else if (mat_i == 9u) {
        rho0 = 1.8; cohesion = 0.0; yield_s = 0.0; fric_val = 0.0;
    } else if (mat_i == 12u) {
        rho0 = 3.5; cohesion = 0.5; yield_s = 2.0; fric_val = 0.4;
    } else if (mat_i == 10u) {
        rho0 = 2.5; cohesion = 0.15; yield_s = 0.0; fric_val = 0.0;
    } else if (mat_i == 13u) {
        rho0 = 4.0; cohesion = 0.0; yield_s = 0.0; fric_val = 0.2;
    } else {
        rho0 = 2.5; cohesion = 0.0; yield_s = 0.0; fric_val = 0.0;
    }

    bool is_ephemeral = (mat_i == 8u || mat_i == 9u);
    bool has_velocity = (abs(vx) > 0.01 || abs(vy) > 0.01);
    bool drill_on = rf(O_P + 15u) > 0.5;
    bool near_drill = false;

    float dpx = rf(O_P + 9u), dpy = rf(O_P + 10u);
    float d_dx = rf(O_P + 11u), d_dy = rf(O_P + 12u);
    float dr = rf(O_P + 13u);
    float dhl = rf(O_P + 14u);
    vec2 cap_a = vec2(dpx - d_dx * dhl, dpy - d_dy * dhl);
    vec2 cap_b = vec2(dpx + d_dx * dhl, dpy + d_dy * dhl);

    // Ship ram flag: while the ship dashes, creatures inside the capsule die.
    bool ship_ram = rf(O_P + 20u) > 0.5;

    if (drill_on) {
        if (yield_s >= 5.0) {
            float ddx = px - dpx, ddy = py - dpy;
            near_drill = (ddx * ddx + ddy * ddy < 22500.0);
        } else {
            near_drill = (capsule_dist(vec2(px, py), cap_a, cap_b) < dr + 5.0);
        }
    }
    // --- Capsule array proximity (drone drills, slots at O_CAP) ---
    bool near_cap = false;
    for (uint c = 0u; c < N_CAP && !near_cap; c++) {
        uint slot = O_CAP + c * 8u;
        if (rf(slot + 6u) < 0.5) continue;
        vec2 cpos = vec2(rf(slot), rf(slot + 1u));
        vec2 cdir = vec2(rf(slot + 2u), rf(slot + 3u));
        float cr = rf(slot + 4u), chl = rf(slot + 5u);
        vec2 c_a = cpos - cdir * chl;
        vec2 c_b = cpos + cdir * chl;
        if (capsule_dist(vec2(px, py), c_a, c_b) < cr + 5.0) near_cap = true;
    }

    bool near_any_drill = near_drill || near_cap;
    if (!has_velocity && !near_any_drill && !is_ephemeral) return;
    if (yield_s >= 5.0 && !near_any_drill) return;

    int cx = int(floor(px / cs));
    int cy = int(floor(py / cs));

    vec2 delta_p = vec2(0.0);
    bool convert_to_rock = false;

    // NPC particles: hard collision + body-head constraint + boid forces
    if (mat_i == 13u) {
        uint my_enc = uint(round(fract(mat_f) * 1000.0));
        uint my_cid = my_enc >> 1u;
        bool i_am_head = (my_enc & 1u) == 1u;

        int boid_count = 0;
        vec2 avg_vel = vec2(0.0);
        vec2 avg_pos = vec2(0.0);

        for (int dy = -1; dy <= 1; dy++) {
            for (int dx = -1; dx <= 1; dx++) {
                int nx = cx + dx, ny = cy + dy;
                if (nx < 0 || nx >= int(GW) || ny < 0 || ny >= int(GH)) continue;
                uint cell = uint(ny) * GW + uint(nx);
                uint count = min(buf.d[O_GC + cell], MPC);
                for (uint k = 0u; k < count; k++) {
                    uint j = buf.d[O_GP + cell * MPC + k];
                    if (j == id) continue;
                    uint bj = O_PT + j * 8u;
                    float mat_fj = rf(bj + 7u);
                    uint mat_j = uint(mat_fj);
                    float jx = rf(bj + 4u), jy = rf(bj + 5u);
                    vec2 diff = vec2(px - jx, py - jy);
                    float r = length(diff);

                    if (mat_j != 13u && mat_j != 11u && r < 5.0 && r > 0.001) {
                        float pen = 5.0 - r;
                        delta_p += (diff / r) * pen * 1.2;
                    }

                    if (mat_j == 13u) {
                        uint j_enc = uint(round(fract(mat_fj) * 1000.0));
                        uint j_cid = j_enc >> 1u;

                        if (my_cid == j_cid) {
                            float target_dist = 3.5;
                            if (r > 0.001) {
                                float correction = (r - target_dist) * 0.4;
                                delta_p -= (diff / r) * correction;
                            }
                            delta_p.x -= (px - jx) * 0.7;
                            if (i_am_head && py > jy - 2.5) {
                                delta_p.y -= 1.2;
                            }
                        } else {
                            // Boid separation: horizontal only to keep NPCs on the ground
                            float npc_sep = rf(O_NP);
                            if (r < 5.0 && r > 0.001) {
                                float sep = npc_sep * (1.0 - r / 5.0);
                                float hdiff = px - jx;
                                float hsgn = (abs(hdiff) > 0.001) ? sign(hdiff) : ((id > j) ? 1.0 : -1.0);
                                delta_p.x += hsgn * sep;
                            }
                            avg_vel += vec2(rf(bj + 2u), rf(bj + 3u));
                            avg_pos += vec2(jx, jy);
                            boid_count++;
                        }
                    }
                }
            }
        }

        // Boid alignment + cohesion from other-creature NPCs
        if (boid_count > 0) {
            float npc_coh = rf(O_NP + 1u);
            avg_vel /= float(boid_count);
            avg_pos /= float(boid_count);
            delta_p += (avg_vel - vec2(vx, vy)) * 0.015;
            delta_p += (avg_pos - vec2(px, py)) * npc_coh;
        }
    } else {
    // Standard PBD for all non-NPC particles
    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int nx = cx + dx, ny = cy + dy;
            if (nx < 0 || nx >= int(GW) || ny < 0 || ny >= int(GH)) continue;
            uint cell = uint(ny) * GW + uint(nx);
            uint count = min(buf.d[O_GC + cell], MPC);
            for (uint k = 0u; k < count; k++) {
                uint j = buf.d[O_GP + cell * MPC + k];
                if (j == id) continue;
                uint bj = O_PT + j * 8u;
                uint mat_j = uint(rf(bj + 7u));
                if (mat_j == 11u) continue;
                bool j_ephemeral = (mat_j == 8u || mat_j == 9u);
                if (!is_ephemeral && j_ephemeral) continue;
                bool cross_class = (is_ephemeral && !j_ephemeral);

                float jx = rf(bj + 4u), jy = rf(bj + 5u);

                vec2 diff = vec2(px - jx, py - jy);
                float r = length(diff);

                if (cross_class) {
                    if (r < 4.5 && r > 0.001) {
                        float pen = 4.5 - r;
                        delta_p += (diff / r) * pen * 0.35;
                    }
                } else {
                    float lambda_j = rf(bj + 6u);
                    vec2 g = kernel_grad(diff, r, h);

                    delta_p += (lambda_i + lambda_j) * g / rho0;

                    bool both_water = (mat_i == 1u && mat_j == 1u);
                    bool both_lava = (mat_i == 10u && mat_j == 10u);
                    float sep_dist = (both_water || both_lava) ? 1.5 : 2.0;
                    float sep_str  = both_water ? 0.15 : (both_lava ? 0.10 : 0.3);
                    if (r < sep_dist && r > 0.001) {
                        delta_p += (diff / r) * (sep_dist - r) * sep_str;
                    }

                    if (cohesion > 0.0 && r > h * 0.3 && r < h) {
                        if (mat_j == mat_i) {
                            delta_p -= cohesion * 0.01 * diff / max(r, 0.001);
                        }
                    }

                    if (r < 6.0) {
                        if ((mat_i == 10u && mat_j == 1u) || (mat_i == 1u && mat_j == 10u)) {
                            convert_to_rock = true;
                        }
                    }
                }
            }
        }
    }
    } // end non-NPC

    if (convert_to_rock) {
        uint hash = id * 2654435761u;
        float var_rock = float(hash >> 16u) / 65535.0 * 0.99;
        wf(b + 7u, 3.0 + var_rock * 0.1);
        wf(b + 2u, 0.0);
        wf(b + 3u, 0.0);
        return;
    }

    if (length(delta_p) < yield_s * 0.1) {
        delta_p = vec2(0.0);
    }

    px += delta_p.x;
    py += delta_p.y;

    float margin = 2.0;
    px = clamp(px, margin, ww - margin);
    py = clamp(py, margin, wh - margin);

    // --- Drill capsule collision ---
    if (drill_on && !is_ephemeral) {
        vec2 p = vec2(px, py);
        vec2 pa = p - cap_a, ba = cap_b - cap_a;
        float t = clamp(dot(pa, ba) / max(dot(ba, ba), 0.001), 0.0, 1.0);
        vec2 closest = cap_a + ba * t;
        vec2 diff = p - closest;
        float dist = length(diff);

        if (dist < dr + 4.0) {
            atomicMax(buf.d[O_P + 19u], floatBitsToUint(yield_s + fric_val));
            if (mat_i == 10u) {
                atomicAdd(buf.d[O_P + 34u], 1u);
            }
        }
        if (dist < dr) {
            if (mat_i >= 5u && mat_i <= 7u) {
                wf(b, -1000.0); wf(b + 1u, -1000.0);
                wf(b + 2u, 0.0); wf(b + 3u, 0.0);
                wf(b + 4u, -1000.0); wf(b + 5u, -1000.0);
                wf(b + 7u, 0.0);
                uint ore_slot = O_M + 9u + (mat_i - 5u);
                atomicAdd(buf.d[ore_slot], 1u);
                return;
            }
            if (mat_i == 12u) {
                push_impact(px, py, KIND_PURPLE);
                kill_particle(b);
                return;
            }
            if (mat_i == 13u) {
                // A creature touching the ship: dies to a ram, else bites.
                if (ship_ram) {
                    uint enc = uint(round(fract(mat_f) * 1000.0));
                    if ((enc & 1u) == 0u) atomicAdd(buf.d[O_FB + 1u], 1u);
                    kill_particle(b);
                    return;
                }
                atomicAdd(buf.d[O_FB], 1u);
            }
            vec2 n = (dist > 0.001) ? diff / dist : vec2(0.0, -1.0);
            float pen = dr - dist;
            px += n.x * (pen + 2.0);
            py += n.y * (pen + 2.0);
        }
    }

    // --- Capsule array collision and erosion (same rules as the drill capsule,
    //     minus the player-only resistance and lava-contact feedback) ---
    if (near_cap && !is_ephemeral) {
        uint tick = uint(rf(O_P + 21u));
        for (uint c = 0u; c < N_CAP; c++) {
            uint slot = O_CAP + c * 8u;
            if (rf(slot + 6u) < 0.5) continue;
            vec2 cpos = vec2(rf(slot), rf(slot + 1u));
            vec2 cdir = vec2(rf(slot + 2u), rf(slot + 3u));
            float cr = rf(slot + 4u), chl = rf(slot + 5u);
            vec2 c_a = cpos - cdir * chl;
            vec2 c_b = cpos + cdir * chl;
            vec2 p = vec2(px, py);
            vec2 pa = p - c_a, ba = c_b - c_a;
            float t = clamp(dot(pa, ba) / max(dot(ba, ba), 0.001), 0.0, 1.0);
            vec2 closest = c_a + ba * t;
            vec2 cdiff = p - closest;
            float dist = length(cdiff);
            if (dist >= cr) continue;
            float melt = rf(slot + 7u);
            if (melt > 0.0) {
                // Melter: ground erodes at the melt rate and nothing is pushed,
                // so the ground thins out in place instead of piling up.
                bool ground = (mat_i < 8u && mat_i != 1u) || mat_i == 12u;
                if (ground) {
                    uint hsh = (id * 2654435761u) ^ (tick * 2246822519u);
                    hsh = hsh * 747796405u + 2891336453u;
                    float rnd = float(hsh >> 16u) / 65535.0;
                    if (rnd < melt) {
                        if (mat_i == 12u) push_impact(px, py, KIND_PURPLE);
                        kill_particle(b);
                        atomicAdd(buf.d[O_P + 22u], 1u); // melted this tick (CPU stat)
                        return;
                    }
                }
                continue;
            } else {
                if (mat_i >= 5u && mat_i <= 7u) {
                    // Ore: remove the particle and add to the global ore counters.
                    kill_particle(b);
                    atomicAdd(buf.d[O_M + 9u + (mat_i - 5u)], 1u);
                    return;
                }
                if (mat_i == 12u) {
                    // Purple ore detonates when carved.
                    push_impact(px, py, KIND_PURPLE);
                    kill_particle(b);
                    return;
                }
                if (mat_i == 13u) {
                    // Creature particles die inside a capsule (laser, worm head).
                    uint enc = uint(round(fract(mat_f) * 1000.0));
                    if ((enc & 1u) == 0u) atomicAdd(buf.d[O_FB + 1u], 1u);
                    kill_particle(b);
                    return;
                }
            }
            vec2 n = (dist > 0.001) ? cdiff / dist : vec2(0.0, -1.0);
            float pen = cr - dist;
            px += n.x * (pen + 2.0);
            py += n.y * (pen + 2.0);
        }
    }

    wf(b + 4u, px);
    wf(b + 5u, py);
}
