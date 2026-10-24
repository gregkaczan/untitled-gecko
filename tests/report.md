# Movement suite report

Runs: 206, passing: 204, failing: 2. Columns are event counts; * marks informational metrics; travel is the body's path length in px, a check that the scene was exercised.

| run | result | draw | head | chain | bunch | lag | dance | upflip | uposc | state | stall | ftog | fslide | fjump | sink | float | cjerk | shake | tube | body* | stuck* | creep* | settle* | travel | outcome |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| clutch_pit:cl_pit | FAIL | 1 |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 4 |  |  |  | 628 | ok |
| dig_45:dig_45 | FAIL |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 | 1 | 186 | never reaches x 0..1920 y 900..1080 |
| ball_hang:ball_round | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 7 |  |  | 816 | ok |
| ball_hang:bounce | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 464 | ok |
| boulder_120:boulder_big | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1385 | ok |
| boulder_30:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1148 | ok |
| boulder_70:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1066 | ok |
| box:box_round | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 6 |  |  | 1140 | ok |
| bump_2x2:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  |  | 1165 | ok |
| bump_row:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1176 | ok |
| cave_1:traverse_long | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 949 | ok |
| cave_2:traverse_long | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 872 | ok |
| cave_3:traverse_long | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 893 | ok |
| cave_4:traverse_long | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 |  |  |  | 869 | ok |
| cave_5:pool_right | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 636 | ok |
| cave_5:traverse_long | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 14 | 1 |  | 1283 | ok |
| cave_6:traverse_long | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 4 |  |  |  | 2012 | ok |
| ceiling_specks:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1170 | ok |
| ceiling_step_down:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1147 | ok |
| ceiling_step_up:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1125 | ok |
| ceiling_walk:bounce | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 727 | ok |
| ceiling_walk:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1163 | ok |
| cliff_jump:cliff_jump | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 881 | ok |
| cliff_walk:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1123 | ok |
| clutch:idle | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 0 | ok |
| clutch_exit:cl_exit | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  |  | 107 | ok |
| clutch_gulf_climb:cl_gulf_climb | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 3 | 2 |  | 1 | 839 | ok |
| clutch_gulf_grapple:cl_gulf_grapple | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  |  | 221 | ok |
| clutch_hall:cl_hall | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 5 |  |  |  | 1139 | ok |
| clutch_hatch:cl_hatch | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 |  |  |  | 532 | ok |
| clutch_leap:cl_leap | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  | 916 | ok |
| clutch_pinch:cl_pinch | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 3 | 2 |  |  | 329 | ok |
| clutch_pool:cl_pool | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 4 |  |  | 965 | ok |
| clutch_shaft:cl_shaft | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  |  | 607 | ok |
| clutch_turn:cl_turn | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  | 812 | ok |
| corner_climb:wall_ceiling | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1612 | ok |
| crumb_perch_12_812:leap_still | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 308 | ok |
| crumb_perch_4_820:leap_still | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 308 | ok |
| crumb_perch_8_790:leap_still | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 415 | ok |
| crumb_perch_8_816:leap_still | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 308 | ok |
| crumb_perch_8_850:leap_still | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 325 | ok |
| crumble_wall:climb_wall | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 837 | ok |
| dig_level_wall:dig_level | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 335 | ok |
| dig_shaft:dig_shaft | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 215 | ok |
| dig_turns:dig_turns | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 | 1 | 520 | ok |
| drop_200:leap_on | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 972 | ok |
| drop_200:leap_still | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 560 | ok |
| drop_200_back:leap_back | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 513 | ok |
| drop_200_pool:leap_on | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 984 | ok |
| drop_200_pool:leap_still | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 748 | ok |
| drop_440:leap_on | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1188 | ok |
| drop_440:leap_still | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 817 | ok |
| drop_440_back:leap_back | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 588 | ok |
| drop_440_pool:leap_on | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1228 | ok |
| drop_440_pool:leap_still | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 992 | ok |
| drop_64:leap_on | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 857 | ok |
| drop_64:leap_still | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 415 | ok |
| drop_64_back:leap_back | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  | 373 | ok |
| drop_64_pool:leap_on | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 848 | ok |
| drop_64_pool:leap_still | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 568 | ok |
| drop_760:leap_on | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1475 | ok |
| drop_760:leap_still | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1142 | ok |
| drop_760_back:leap_back | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 588 | ok |
| drop_760_pool:leap_on | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1495 | ok |
| drop_760_pool:leap_still | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1319 | ok |
| drop_funnel:cliff_jump | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 652 | ok |
| flat:bounce | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 727 | ok |
| flat:idle | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 0 | ok |
| flat:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1163 | ok |
| funnel_40:funnel | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 3 |  |  | 721 | ok |
| funnel_60:funnel | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 4 |  |  | 668 | ok |
| funnel_90:funnel | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 4 |  |  | 679 | ok |
| gap_16:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1164 | ok |
| gap_24:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1165 | ok |
| gap_32:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1161 | ok |
| gap_40:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  | 1336 | ok |
| gap_48:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  | 1381 | ok |
| gap_64:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1412 | ok |
| gap_8:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1164 | ok |
| gap_higher_16:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 |  |  |  | 1166 | ok |
| gap_higher_32:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1146 | ok |
| gap_higher_48:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 1 |  | 1413 | ok |
| gap_lower_16:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  |  | 1150 | ok |
| gap_lower_32:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  | 1228 | ok |
| gap_lower_48:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 | 1 |  | 1334 | ok |
| gas_pocket:dig_pocket | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  | 1 | 343 | ok |
| idle_ledge:idle | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 0 | ok |
| idle_rim:idle | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 0 | ok |
| idle_slot:slot_lip | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 363 | ok |
| idle_slot:slot_out | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 377 | ok |
| idle_wall:idle | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 0 | ok |
| jump_flat:jump_right | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 688 | ok |
| jump_flat:jump_up | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 124 | ok |
| jump_wall:jump_right | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 213 | ok |
| moss_bitten:bite_climb | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 652 | ok |
| moss_wall:climb_wall | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 579 | ok |
| notch_1:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1165 | ok |
| notch_2:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1166 | ok |
| notch_climb:bite_climb | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 652 | ok |
| notch_deep:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 |  |  |  | 1172 | ok |
| notch_wide_deep:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 |  | 1 |  | 1151 | ok |
| overhang_shelf_under:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1163 | ok |
| overhang_wedge:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 3 |  |  | 979 | ok |
| pillar:climb_over | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 4 |  |  | 1119 | ok |
| pillar_thin:climb_over | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 953 | ok |
| pool:swim_across | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 997 | ok |
| pool:swim_out | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1184 | ok |
| pool_bank_slope:swim_across | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 959 | ok |
| pool_bank_slope:swim_out | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1213 | ok |
| pool_bank_slope:swim_out_back | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1104 | ok |
| pool_bank_slope:swim_out_edge | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1365 | ok |
| pool_bank_slope:swim_out_rest | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 959 | ok |
| pool_current:swim_right | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 520 | ok |
| pool_drop:float | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 469 | ok |
| rest_jagged:walk_rest | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 1 | 1 | 777 | ok |
| shelf_lip:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1160 | ok |
| slope_down_10:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1168 | ok |
| slope_down_20:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1169 | ok |
| slope_down_30:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1168 | ok |
| slope_down_45:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1165 | ok |
| slope_down_60:traverse_diag_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1169 | ok |
| slope_down_75:traverse_diag_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1166 | ok |
| slope_up_10:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1168 | ok |
| slope_up_20:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1168 | ok |
| slope_up_30:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 1168 | ok |
| slope_up_45:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1155 | ok |
| slope_up_60:traverse_diag | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1161 | ok |
| slope_up_75:traverse_diag | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  | 1164 | ok |
| slot_20:slot | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 575 | ok |
| slot_24:slot | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 576 | ok |
| slot_28:slot | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  | 576 | ok |
| slot_36:slot | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  |  | 575 | ok |
| specks_floor:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1165 | ok |
| squeeze_door_12_12:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 |  |  |  | 1094 | ok |
| squeeze_door_12_16:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1089 | ok |
| squeeze_door_24_12:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 |  |  |  | 1057 | ok |
| squeeze_door_24_16:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1052 | ok |
| squeeze_low_12:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 |  |  |  | 831 | ok |
| squeeze_low_16:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 826 | ok |
| squeeze_ragged:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 647 | ok |
| squeeze_slot_12:slot_dive | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 |  |  |  | 681 | ok |
| squeeze_slot_16:slot_dive | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  |  | 676 | ok |
| squeeze_window_12:window | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 | 1 |  |  | 627 | ok |
| squeeze_window_jagged:window | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 | 1 |  |  | 625 | ok |
| step_down_12:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1161 | ok |
| step_down_16:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  | 1165 | ok |
| step_down_24:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1145 | ok |
| step_down_32:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1143 | ok |
| step_down_48:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1123 | ok |
| step_down_4:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1167 | ok |
| step_down_8:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1171 | ok |
| step_up_12:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  |  | 1167 | ok |
| step_up_16:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1172 | ok |
| step_up_24:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1150 | ok |
| step_up_32:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1140 | ok |
| step_up_48:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1123 | ok |
| step_up_4:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1167 | ok |
| step_up_8:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1170 | ok |
| switch_30:switch_up | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 3 | ok |
| switch_30:switch_up_hold | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 3 | ok |
| switch_30:switch_walk | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 395 | ok |
| switch_30_back:switch_back | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 5 | ok |
| switch_30_ceiling:switch_down | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 3 | ok |
| switch_40:switch_up | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  | 1 |  | 11 | ok |
| switch_40:switch_up_hold | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  | 1 |  | 11 | ok |
| switch_40:switch_walk | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  | 1 |  | 403 | ok |
| switch_40_back:switch_back | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 |  | 1 |  | 21 | ok |
| switch_40_ceiling:switch_down | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  |  | 11 | ok |
| switch_60:switch_up | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 0 | ok |
| switch_60:switch_up_hold | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 0 | ok |
| thorn_floor:walk_right | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  |  |  | 685 | ok |
| thorn_wall:climb_wall | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 926 | ok |
| tongue_shaft_a:tap_shaft_a | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 2 |  | 1 | 220 | ok |
| tongue_shaft_b:tap_shaft_b | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 2 |  | 1 | 237 | ok |
| tongue_shaft_c:tap_shaft_c | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 2 |  | 1 | 253 | ok |
| tongue_tunnel_fall:tap_dig_fall | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 5 | 1 |  | 798 | ok |
| tongue_tunnel_fall_mouth:tap_dig_fall_mouth | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 5 | 1 |  | 806 | ok |
| tongue_tunnel_fall_mouth_wide:tap_dig_fall_mouth_wide | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 5 | 1 |  | 796 | ok |
| tongue_tunnel_level:tap_dig_level | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 5 |  |  | 783 | ok |
| tongue_tunnel_level_mouth:tap_dig_level_mouth | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 5 | 1 |  | 790 | ok |
| tongue_tunnel_level_mouth_wide:tap_dig_level_mouth_wide | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 5 |  |  | 804 | ok |
| tongue_tunnel_low:tap_dig_low | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 5 | 1 | 1 | 788 | ok |
| tongue_tunnel_low_mouth:tap_dig_low_mouth | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 5 |  |  | 799 | ok |
| tongue_tunnel_low_mouth_wide:tap_dig_low_mouth_wide | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 5 |  |  | 794 | ok |
| tongue_tunnel_rise:tap_dig_rise | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 5 |  |  | 796 | ok |
| tongue_tunnel_rise_mouth:tap_dig_rise_mouth | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 5 |  |  | 800 | ok |
| tongue_tunnel_rise_mouth_wide:tap_dig_rise_mouth_wide | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 6 |  |  | 802 | ok |
| tongue_tunnel_steep:tap_dig_steep | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 5 |  |  | 809 | ok |
| tongue_tunnel_steep_mouth:tap_dig_steep_mouth | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 5 |  |  | 814 | ok |
| tongue_tunnel_steep_mouth_wide:tap_dig_steep_mouth_wide | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 5 |  |  | 807 | ok |
| tongue_tunnel_thin:tap_dig_thin | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 4 |  |  | 766 | ok |
| tongue_tunnel_thin_mouth:tap_dig_thin_mouth | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 4 |  |  | 767 | ok |
| tongue_tunnel_thin_mouth_wide:tap_dig_thin_mouth_wide | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 4 |  |  | 777 | ok |
| tongue_tunnel_wide:tap_dig_wide | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 6 | 1 |  | 793 | ok |
| tongue_tunnel_wide_mouth:tap_dig_wide_mouth | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 6 |  |  | 797 | ok |
| tongue_tunnel_wide_mouth_wide:tap_dig_wide_mouth_wide | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 6 |  |  | 814 | ok |
| tunnel_45:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1161 | ok |
| tunnel_45_ragged:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 1157 | ok |
| tunnel_bend:traverse_long | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 2286 | ok |
| tunnel_jagged:walk_long | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 742 | ok |
| tunnel_jagged_fine:walk_long | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 3 |  |  | 779 | ok |
| tunnel_jagged_wide:walk_long | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 792 | ok |
| tunnel_level:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1164 | ok |
| tunnel_ragged:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1171 | ok |
| tunnel_shaft:shaft | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 773 | ok |
| tunnel_up_bend:traverse_long | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 2266 | ok |

## Failing runs

### clutch_pit:cl_pit
- draw_jump: 1 events, worst 4.09: t86 (4.09)

### dig_45:dig_45
- outcome: never reaches x 0..1920 y 900..1080

