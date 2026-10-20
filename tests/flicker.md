# Frame flicker report

Silhouette change between consecutive frames, as a share of the gecko's pixels, after alignment. Change events are frames over 0.35; fragment events are frames with 8 px or more of silhouette not attached to its largest piece.

| run | frames | median | p95 | max | change events | fragment events |
|---|---|---|---|---|---|---|
| tunnel_45_ragged:traverse | 573 | 0.150 | 0.217 | 0.937 | 0 | 5 |
| tunnel_bend:traverse_long | 1111 | 0.126 | 0.209 | 0.725 | 3 | 0 |
| dig_shaft:dig_shaft | 297 | 0.119 | 0.230 | 0.456 | 3 | 0 |
| cave_1:traverse_long | 1111 | 0.142 | 0.236 | 1.307 | 0 | 2 |
| funnel_90:funnel | 617 | 0.080 | 0.186 | 0.534 | 0 | 2 |
| ceiling_step_up:traverse | 573 | 0.114 | 0.222 | 0.500 | 2 | 0 |
| cave_5:traverse_long | 1111 | 0.141 | 0.240 | 0.483 | 0 | 2 |
| cave_6:traverse_long | 1111 | 0.140 | 0.234 | 0.455 | 0 | 2 |
| cliff_jump:cliff_jump | 308 | 0.115 | 0.233 | 0.879 | 1 | 0 |
| gap_lower_32:gap_cross | 841 | 0.098 | 0.199 | 0.771 | 1 | 0 |
| boulder_30:traverse | 573 | 0.124 | 0.229 | 0.551 | 1 | 0 |
| funnel_40:funnel | 617 | 0.067 | 0.172 | 0.441 | 0 | 1 |
| jump_flat:jump_up | 214 | 0.004 | 0.226 | 1.021 | 0 | 0 |
| tunnel_level:traverse | 573 | 0.117 | 0.184 | 0.838 | 0 | 0 |
| jump_wall:jump_right | 297 | 0.004 | 0.178 | 0.824 | 0 | 0 |
| jump_flat:jump_right | 297 | 0.112 | 0.198 | 0.806 | 0 | 0 |
| step_up_4:traverse | 573 | 0.112 | 0.189 | 0.787 | 0 | 0 |
| tunnel_45:traverse | 573 | 0.130 | 0.195 | 0.781 | 0 | 0 |
| notch_2:traverse | 573 | 0.112 | 0.191 | 0.763 | 0 | 0 |
| corner_climb:wall_ceiling | 875 | 0.111 | 0.189 | 0.701 | 0 | 0 |
| slope_down_20:traverse_left | 573 | 0.139 | 0.212 | 0.700 | 0 | 0 |
| slope_up_30:traverse | 573 | 0.149 | 0.224 | 0.693 | 0 | 0 |
| tunnel_up_bend:traverse_long | 1111 | 0.121 | 0.202 | 0.680 | 0 | 0 |
| slope_up_45:traverse | 573 | 0.130 | 0.201 | 0.661 | 0 | 0 |
| tunnel_ragged:traverse | 573 | 0.112 | 0.190 | 0.655 | 0 | 0 |
| ceiling_step_down:traverse | 573 | 0.115 | 0.200 | 0.646 | 0 | 0 |
| slope_down_60:traverse_diag_left | 573 | 0.141 | 0.217 | 0.646 | 0 | 0 |
| step_up_24:traverse | 573 | 0.115 | 0.193 | 0.645 | 0 | 0 |
| step_down_16:traverse_left | 573 | 0.116 | 0.213 | 0.643 | 0 | 0 |
| gap_40:gap_cross | 841 | 0.105 | 0.211 | 0.639 | 0 | 0 |
| gap_24:traverse | 573 | 0.113 | 0.190 | 0.637 | 0 | 0 |
| gap_32:traverse | 573 | 0.114 | 0.209 | 0.635 | 0 | 0 |
| gap_8:traverse | 573 | 0.111 | 0.189 | 0.625 | 0 | 0 |
| flat:bounce | 391 | 0.120 | 0.301 | 0.621 | 0 | 0 |
| slope_up_20:traverse | 573 | 0.143 | 0.224 | 0.609 | 0 | 0 |
| bump_2x2:traverse | 573 | 0.113 | 0.197 | 0.603 | 0 | 0 |
| bump_row:traverse | 573 | 0.116 | 0.195 | 0.603 | 0 | 0 |
| specks_floor:traverse | 573 | 0.117 | 0.197 | 0.602 | 0 | 0 |
| ceiling_walk:bounce | 391 | 0.121 | 0.309 | 0.601 | 0 | 0 |
| funnel_60:funnel | 617 | 0.076 | 0.179 | 0.600 | 0 | 0 |
| step_up_8:traverse | 573 | 0.113 | 0.193 | 0.600 | 0 | 0 |
| cave_2:traverse_long | 1111 | 0.142 | 0.236 | 0.595 | 0 | 0 |
| notch_1:traverse | 573 | 0.110 | 0.188 | 0.593 | 0 | 0 |
| flat:traverse | 573 | 0.110 | 0.188 | 0.590 | 0 | 0 |
| gap_higher_16:traverse | 573 | 0.115 | 0.193 | 0.588 | 0 | 0 |
| drop_funnel:cliff_jump | 308 | 0.109 | 0.190 | 0.586 | 0 | 0 |
| ceiling_specks:traverse | 573 | 0.116 | 0.190 | 0.584 | 0 | 0 |
| step_up_48:traverse | 573 | 0.095 | 0.185 | 0.582 | 0 | 0 |
| tunnel_shaft:shaft | 393 | 0.101 | 0.185 | 0.580 | 0 | 0 |
| gap_lower_16:traverse | 573 | 0.115 | 0.203 | 0.578 | 0 | 0 |
| slope_up_10:traverse | 573 | 0.125 | 0.199 | 0.565 | 0 | 0 |
| gap_higher_32:traverse | 573 | 0.115 | 0.209 | 0.563 | 0 | 0 |
| step_up_16:traverse | 573 | 0.115 | 0.209 | 0.563 | 0 | 0 |
| gap_higher_48:gap_cross | 841 | 0.105 | 0.213 | 0.556 | 0 | 0 |
| gap_lower_48:gap_cross | 841 | 0.104 | 0.213 | 0.555 | 0 | 0 |
| gap_16:traverse | 573 | 0.110 | 0.184 | 0.551 | 0 | 0 |
| cliff_walk:traverse | 573 | 0.114 | 0.209 | 0.545 | 0 | 0 |
| overhang_wedge:traverse | 573 | 0.102 | 0.189 | 0.537 | 0 | 0 |
| shelf_lip:traverse_left | 573 | 0.112 | 0.186 | 0.536 | 0 | 0 |
| slope_down_10:traverse_left | 573 | 0.123 | 0.198 | 0.536 | 0 | 0 |
| slope_down_30:traverse_left | 573 | 0.145 | 0.232 | 0.536 | 0 | 0 |
| slope_down_45:traverse_left | 573 | 0.126 | 0.189 | 0.536 | 0 | 0 |
| slope_down_75:traverse_diag_left | 573 | 0.130 | 0.212 | 0.536 | 0 | 0 |
| step_down_12:traverse_left | 573 | 0.114 | 0.196 | 0.536 | 0 | 0 |
| step_down_24:traverse_left | 573 | 0.115 | 0.213 | 0.536 | 0 | 0 |
| step_down_32:traverse_left | 573 | 0.115 | 0.222 | 0.536 | 0 | 0 |
| step_down_4:traverse_left | 573 | 0.112 | 0.190 | 0.536 | 0 | 0 |
| step_down_48:traverse_left | 573 | 0.115 | 0.218 | 0.536 | 0 | 0 |
| step_down_8:traverse_left | 573 | 0.113 | 0.194 | 0.536 | 0 | 0 |
| notch_deep:traverse | 573 | 0.112 | 0.187 | 0.533 | 0 | 0 |
| slope_up_75:traverse_diag | 573 | 0.128 | 0.227 | 0.533 | 0 | 0 |
| step_up_32:traverse | 573 | 0.114 | 0.204 | 0.530 | 0 | 0 |
| boulder_120:boulder_big | 791 | 0.121 | 0.212 | 0.514 | 0 | 0 |
| ceiling_walk:traverse | 573 | 0.111 | 0.190 | 0.509 | 0 | 0 |
| boulder_70:traverse | 573 | 0.125 | 0.241 | 0.508 | 0 | 0 |
| overhang_shelf_under:traverse | 573 | 0.110 | 0.189 | 0.500 | 0 | 0 |
| notch_wide_deep:traverse | 573 | 0.112 | 0.190 | 0.489 | 0 | 0 |
| step_up_12:traverse | 573 | 0.113 | 0.194 | 0.488 | 0 | 0 |
| slope_up_60:traverse_diag | 573 | 0.146 | 0.235 | 0.462 | 0 | 0 |
| gap_48:gap_cross | 841 | 0.107 | 0.212 | 0.456 | 0 | 0 |
| gap_64:gap_cross | 841 | 0.105 | 0.225 | 0.454 | 0 | 0 |
| cave_4:traverse_long | 1111 | 0.141 | 0.239 | 0.446 | 0 | 0 |
| cave_3:traverse_long | 1111 | 0.140 | 0.243 | 0.435 | 0 | 0 |
| dig_turns:dig_turns | 571 | 0.153 | 0.235 | 0.408 | 0 | 0 |
| slot_36:slot | 598 | 0.007 | 0.179 | 0.369 | 0 | 0 |
| pool:swim_across | 634 | 0.101 | 0.193 | 0.307 | 0 | 0 |
| pool_bank_slope:swim_across | 634 | 0.101 | 0.190 | 0.307 | 0 | 0 |
| box:box_round | 786 | 0.102 | 0.195 | 0.283 | 0 | 0 |
| pillar_thin:climb_over | 726 | 0.087 | 0.183 | 0.275 | 0 | 0 |
| pillar:climb_over | 726 | 0.099 | 0.183 | 0.265 | 0 | 0 |
| slot_28:slot | 598 | 0.007 | 0.168 | 0.241 | 0 | 0 |
| dig_45:dig_45 | 297 | 0.145 | 0.208 | 0.239 | 0 | 0 |
| slot_20:slot | 598 | 0.024 | 0.160 | 0.227 | 0 | 0 |
| dig_level_wall:dig_level | 297 | 0.088 | 0.177 | 0.223 | 0 | 0 |
| slot_24:slot | 598 | 0.014 | 0.160 | 0.214 | 0 | 0 |

## Events

- boulder_30:traverse change: t185 (0.46)
- cave_1:traverse_long fragments: t153 (96 px), t154 (48 px)
- cave_5:traverse_long fragments: t911 (64 px), t912 (24 px)
- cave_6:traverse_long fragments: t82 (48 px), t83 (12 px)
- ceiling_step_up:traverse change: t142 (0.40), t447 (0.38)
- cliff_jump:cliff_jump change: t160 (0.87)
- dig_shaft:dig_shaft change: t37 (0.38), t38 (0.46), t39 (0.39)
- funnel_40:funnel fragments: t270 (16 px)
- funnel_90:funnel fragments: t244 (44 px), t245 (8 px)
- gap_lower_32:gap_cross change: t609 (0.40)
- tunnel_45_ragged:traverse fragments: t83 (24 px), t84 (8 px), t228 (36 px), t229 (12 px), t350 (32 px)
- tunnel_bend:traverse_long change: t594 (0.67), t596 (0.36), t971 (0.38)
