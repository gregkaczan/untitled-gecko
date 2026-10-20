#[compute]
#version 450

layout(local_size_x = 256, local_size_y = 1, local_size_z = 1) in;
layout(set = 0, binding = 0, std430) buffer Data { uint d[]; } buf;

const uint GW = 320u, GH = 180u, MPC = 32u, PC = 518400u;
const uint O_P = 0u, O_M = 40u, O_GC = 136u, O_GP = 57736u, O_PT = 1900936u, O_RN = 6048136u;

float rf(uint i) { return uintBitsToFloat(buf.d[i]); }
void wf(uint i, float v) { buf.d[i] = floatBitsToUint(v); }

float kernel_w(float r, float h) {
    if (r >= h) return 0.0;
    float q = 1.0 - r / h;
    return q * q * q;
}

vec2 kernel_grad(vec2 diff, float r, float h) {
    if (r < 0.001 || r >= h) return vec2(0.0);
    float q = 1.0 - r / h;
    return (-3.0 / (h * r)) * q * q * diff;
}

void main() {
    uint id = gl_GlobalInvocationID.x;
    if (id >= PC) return;

    float cs = rf(O_P + 6u);
    float h = rf(O_P + 7u);

    uint b = O_PT + id * 8u;
    float px = rf(b + 4u), py = rf(b + 5u);
    uint mat_i = uint(rf(b + 7u));

    // Bullets and NPC dwellers skip PBD density constraints
    if (mat_i == 11u || mat_i == 13u) return;

    float rho0, stiff;
    if (mat_i < 8u) {
        rho0 = rf(O_M + mat_i * 12u);
        stiff = rf(O_M + mat_i * 12u + 1u);
    } else if (mat_i == 8u) {
        rho0 = 1.2; stiff = 0.8;
    } else if (mat_i == 9u) {
        rho0 = 1.8; stiff = 2.0;
    } else if (mat_i == 12u) {
        rho0 = 3.5; stiff = 1.5;
    } else if (mat_i == 13u) {
        rho0 = 4.0; stiff = 1.5;
    } else {
        rho0 = 2.5; stiff = 1.5; // lava
    }

    bool i_ephemeral = (mat_i == 8u || mat_i == 9u);
    int cx = int(floor(px / cs));
    int cy = int(floor(py / cs));

    float density = 0.0;
    float sum_grad_sq = 0.0;
    vec2 grad_i = vec2(0.0);

    for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
            int nx = cx + dx, ny = cy + dy;
            if (nx < 0 || nx >= int(GW) || ny < 0 || ny >= int(GH)) continue;
            uint cell = uint(ny) * GW + uint(nx);
            uint count = min(buf.d[O_GC + cell], MPC);
            for (uint k = 0u; k < count; k++) {
                uint j = buf.d[O_GP + cell * MPC + k];
                uint bj = O_PT + j * 8u;
                uint mat_j = uint(rf(bj + 7u));
                if (mat_j == 11u) continue;
                bool j_ephemeral = (mat_j == 8u || mat_j == 9u);
                if (i_ephemeral != j_ephemeral) continue;

                float jx = rf(bj + 4u), jy = rf(bj + 5u);
                vec2 diff = vec2(px - jx, py - jy);
                float r = length(diff);

                density += kernel_w(r, h);

                vec2 g = kernel_grad(diff, r, h) / rho0;
                sum_grad_sq += dot(g, g);
                grad_i -= g;
            }
        }
    }
    sum_grad_sq += dot(grad_i, grad_i);

    float C = density / rho0 - 1.0;
    float epsilon = 0.1;
    float lambda = -C * stiff / (sum_grad_sq + epsilon);

    wf(b + 6u, lambda);
}
