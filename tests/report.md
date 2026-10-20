# Movement suite report

Runs: 100, passing: 100, failing: 0. Columns are event counts; * marks informational metrics; travel is the body's path length in px, a check that the scene was exercised.

Compared against baseline baseline.json.

| run | result | draw | head | dance | upflip | uposc | state | stall | ftog | fslide | fjump | sink | float | body* | stuck* | travel | outcome |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| boulder_120:boulder_big | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1404 | ok |
| boulder_30:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  | 1 (-1) |  | 1150 | ok |
| boulder_70:traverse | pass |  (-2) |  (-3) |  |  |  |  |  |  |  |  |  |  |  (-8) |  | 1101 | ok |
| box:box_round | pass |  (-7) |  (-4) |  |  |  |  |  |  |  |  |  |  |  (-9) | 2 (+2) | 1153 | ok |
| bump_2x2:traverse | pass |  (-1) |  |  |  |  |  |  |  |  |  (-1) |  |  |  (-1) |  | 1171 | ok |
| bump_row:traverse | pass |  |  |  |  |  (-1) |  |  |  |  |  |  |  |  (-2) |  | 1168 | ok |
| cave_1:traverse_long | pass |  (-2) |  |  |  |  (-2) |  |  |  |  |  (-11) |  |  | 4 (+1) |  | 977 | ok |
| cave_2:traverse_long | pass |  |  (-3) |  |  |  (-1) |  |  |  |  |  (-10) |  |  |  (-2) |  | 886 | ok |
| cave_3:traverse_long | pass |  |  |  |  |  (-2) |  |  |  |  |  (-10) |  |  |  |  | 1918 | ok |
| cave_4:traverse_long | pass |  |  |  |  |  (-3) |  |  |  |  |  (-9) |  |  |  (-3) |  | 1876 | ok |
| cave_5:traverse_long | pass |  (-1) |  (-3) |  |  |  (-1) |  |  |  |  |  (-9) |  |  |  (-4) |  | 1852 | ok |
| cave_6:traverse_long | pass |  |  |  |  |  (-1) |  |  |  |  |  (-13) |  |  | 3 (+3) |  | 877 | ok |
| ceiling_specks:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1174 | ok |
| ceiling_step_down:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  (-2) |  | 1150 | ok |
| ceiling_step_up:traverse | pass |  |  |  (-1) |  |  (-1) |  |  (-1) |  |  |  |  |  |  | 4 (+4) | 904 | ok |
| ceiling_walk:bounce | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 727 | ok |
| ceiling_walk:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1163 | ok |
| cliff_jump:cliff_jump | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 881 | ok |
| cliff_walk:traverse | pass |  |  (-4) |  |  |  |  |  |  |  |  |  |  |  (-4) | 6 (+6) | 750 | ok |
| corner_climb:wall_ceiling | pass |  (-2) |  (-2) |  |  |  |  |  |  |  |  |  |  |  (-2) | 3 (+3) | 1602 | ok |
| dig_45:dig_45 | pass |  |  |  |  |  |  |  |  |  |  (-2) |  |  |  |  | 396 | ok |
| dig_level_wall:dig_level | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 396 | ok |
| dig_shaft:dig_shaft | pass |  |  (-13) |  |  |  |  |  |  |  |  (-3) |  |  |  (-1) |  | 298 | ok |
| dig_turns:dig_turns | pass |  |  (-4) |  |  |  |  |  |  |  |  (-2) |  |  |  |  | 996 | ok |
| drop_funnel:cliff_jump | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 642 | ok |
| flat:bounce | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 727 | ok |
| flat:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1163 | ok |
| funnel_40:funnel | pass |  |  |  |  |  |  |  |  |  |  |  |  |  | 4 | 659 | ok |
| funnel_60:funnel | pass |  |  |  |  |  (-3) |  |  |  |  |  |  |  |  | 4 | 677 | ok |
| funnel_90:funnel | pass |  (-2) |  (-8) |  |  |  |  |  |  |  |  |  |  |  (-2) | 4 | 686 | ok |
| gap_16:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  (-1) |  | 1164 | ok |
| gap_24:traverse | pass |  |  |  |  |  |  |  |  |  |  (-3) |  |  |  (-1) |  | 1164 | ok |
| gap_32:traverse | pass |  |  |  |  |  |  |  |  |  |  (-8) |  |  |  |  | 1169 | ok |
| gap_40:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 1369 | ok |
| gap_48:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 1383 | ok |
| gap_64:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1417 | ok |
| gap_8:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1164 | ok |
| gap_higher_16:traverse | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  | 2 (-3) |  | 1167 | ok |
| gap_higher_32:traverse | pass |  |  (-3) |  |  |  |  |  |  |  |  (-5) |  |  |  (-2) |  | 1149 | ok |
| gap_higher_48:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 1419 | ok |
| gap_lower_16:traverse | pass |  (-1) |  (-2) |  |  |  |  |  |  |  |  (-4) |  |  | 1 (-6) |  | 1153 | ok |
| gap_lower_32:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 1234 | ok |
| gap_lower_48:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 | 1338 | ok |
| jump_flat:jump_right | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  |  | 692 | ok |
| jump_flat:jump_up | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 129 | ok |
| jump_wall:jump_right | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 213 | ok |
| notch_1:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1165 | ok |
| notch_2:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1166 | ok |
| notch_deep:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  | 2 |  | 1176 | ok |
| notch_wide_deep:traverse | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  | 2 (-2) |  | 1154 | ok |
| overhang_shelf_under:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1163 | ok |
| overhang_wedge:traverse | pass |  |  (-3) |  |  |  |  |  |  |  |  |  |  |  (-3) | 3 (+3) | 980 | ok |
| pillar:climb_over | pass |  |  |  |  |  (-2) |  |  |  |  |  (-1) |  |  |  (-2) |  | 1143 | ok |
| pillar_thin:climb_over | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  (-3) |  | 955 | ok |
| pool:swim_across | pass |  (-1) |  (-4) |  |  |  |  |  |  |  |  (-2) |  |  |  (-4) |  | 1000 | ok |
| pool_bank_slope:swim_across | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  (-2) |  | 961 | ok |
| shelf_lip:traverse_left | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  |  | 1159 | ok |
| slope_down_10:traverse_left | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  |  | 1179 | ok |
| slope_down_20:traverse_left | pass |  |  |  |  |  |  |  |  |  |  (-2) |  |  |  |  | 1180 | ok |
| slope_down_30:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1180 | ok |
| slope_down_45:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1173 | ok |
| slope_down_60:traverse_diag_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1179 | ok |
| slope_down_75:traverse_diag_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1175 | ok |
| slope_up_10:traverse | pass |  |  |  |  |  |  |  |  |  |  (-2) |  |  |  |  | 1180 | ok |
| slope_up_20:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1180 | ok |
| slope_up_30:traverse | pass |  |  |  |  |  |  |  |  |  |  (-4) |  |  |  |  | 1180 | ok |
| slope_up_45:traverse | pass |  |  |  |  |  |  |  |  |  |  (-2) |  |  |  |  | 1163 | ok |
| slope_up_60:traverse_diag | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1171 | ok |
| slope_up_75:traverse_diag | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1175 | ok |
| slot_20:slot | pass |  |  |  |  |  |  |  |  |  |  |  |  |  (-1) |  | 574 | ok |
| slot_24:slot | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  (-1) |  | 575 | ok |
| slot_28:slot | pass |  |  |  |  |  |  |  |  |  |  |  |  |  (-1) |  | 574 | ok |
| slot_36:slot | pass |  |  |  |  |  |  |  |  |  |  (-3) |  |  | 1 |  | 576 | ok |
| specks_floor:traverse | pass |  |  |  |  |  (-1) |  |  |  |  |  (-2) |  |  |  |  | 1175 | ok |
| squeeze_low_12:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  | 832 | ok |
| squeeze_low_16:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 830 | ok |
| squeeze_ragged:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 652 | ok |
| squeeze_slot_12:slot_dive | pass |  |  |  |  |  |  |  |  |  |  |  |  | 2 | 2 | 682 | ok |
| squeeze_slot_16:slot_dive | pass |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 2 | 676 | ok |
| step_down_12:traverse_left | pass |  (-1) |  |  |  |  |  |  |  |  |  (-2) |  |  |  (-1) |  | 1173 | ok |
| step_down_16:traverse_left | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  (-2) |  | 1165 | ok |
| step_down_24:traverse_left | pass |  (-2) |  |  |  |  |  |  |  |  |  (-4) |  |  |  (-5) |  | 1149 | ok |
| step_down_32:traverse_left | pass |  |  (-3) |  |  |  |  |  |  |  |  (-6) |  |  |  (-2) |  | 1139 | ok |
| step_down_48:traverse_left | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  (-4) |  | 1127 | ok |
| step_down_4:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1167 | ok |
| step_down_8:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1170 | ok |
| step_up_12:traverse | pass |  |  |  |  |  |  |  |  |  |  (-2) |  |  |  |  | 1164 | ok |
| step_up_16:traverse | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  (-2) |  | 1171 | ok |
| step_up_24:traverse | pass |  (-1) |  (-3) |  |  |  |  |  |  |  |  (-4) |  |  |  (-5) |  | 1150 | ok |
| step_up_32:traverse | pass |  |  (-1) |  |  |  |  |  |  |  |  (-4) |  |  |  (-4) |  | 1147 | ok |
| step_up_48:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  (-2) | 6 (+6) | 772 | ok |
| step_up_4:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1167 | ok |
| step_up_8:traverse | pass |  (-1) |  |  |  |  |  |  |  |  |  |  |  |  (-1) |  | 1169 | ok |
| tunnel_45:traverse | pass |  |  (-26) |  |  |  (-2) |  |  |  |  |  (-1) |  (-1) |  |  |  (-13) | 1163 | ok |
| tunnel_45_ragged:traverse | pass |  |  (-29) |  |  |  (-2) |  |  |  |  |  |  (-1) |  |  |  (-11) | 1162 | ok |
| tunnel_bend:traverse_long | pass |  |  (-11) |  |  |  |  |  |  |  |  (-2) |  |  |  |  (-22) | 2326 | ok |
| tunnel_level:traverse | pass |  |  |  |  |  |  |  |  |  |  (-5) |  |  |  |  | 1164 | ok |
| tunnel_ragged:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  (-16) | 1166 | ok |
| tunnel_shaft:shaft | pass |  |  |  |  |  |  |  |  |  |  (-4) |  |  |  |  | 773 | ok |
| tunnel_up_bend:traverse_long | pass |  |  |  |  |  |  |  |  |  |  (-2) |  |  |  |  (-30) | 2313 | ok |

## Against the baseline

Regressions: 0. Improvements: 93.
- improved boulder_70:traverse draw_jump: 2 -> 0
- improved boulder_70:traverse head_jump: 3 -> 0
- improved box:box_round draw_jump: 7 -> 0
- improved box:box_round head_jump: 4 -> 0
- improved bump_2x2:traverse draw_jump: 1 -> 0
- improved bump_2x2:traverse foot_jump: 1 -> 0
- improved bump_row:traverse up_osc: 1 -> 0
- improved cave_1:traverse_long draw_jump: 2 -> 0
- improved cave_1:traverse_long up_osc: 2 -> 0
- improved cave_1:traverse_long foot_jump: 11 -> 0
- improved cave_2:traverse_long head_jump: 3 -> 0
- improved cave_2:traverse_long up_osc: 1 -> 0
- improved cave_2:traverse_long foot_jump: 10 -> 0
- improved cave_3:traverse_long up_osc: 2 -> 0
- improved cave_3:traverse_long foot_jump: 10 -> 0
- improved cave_4:traverse_long up_osc: 3 -> 0
- improved cave_4:traverse_long foot_jump: 9 -> 0
- improved cave_5:traverse_long draw_jump: 1 -> 0
- improved cave_5:traverse_long head_jump: 3 -> 0
- improved cave_5:traverse_long up_osc: 1 -> 0
- improved cave_5:traverse_long foot_jump: 9 -> 0
- improved cave_6:traverse_long up_osc: 1 -> 0
- improved cave_6:traverse_long foot_jump: 13 -> 0
- improved ceiling_step_up:traverse dance: 1 -> 0
- improved ceiling_step_up:traverse up_osc: 1 -> 0
- improved ceiling_step_up:traverse stall: 1 -> 0
- improved cliff_walk:traverse head_jump: 4 -> 0
- improved corner_climb:wall_ceiling draw_jump: 2 -> 0
- improved corner_climb:wall_ceiling head_jump: 2 -> 0
- improved dig_45:dig_45 foot_jump: 2 -> 0
- improved dig_shaft:dig_shaft head_jump: 13 -> 0
- improved dig_shaft:dig_shaft foot_jump: 3 -> 0
- improved dig_turns:dig_turns head_jump: 4 -> 0
- improved dig_turns:dig_turns foot_jump: 2 -> 0
- improved funnel_60:funnel up_osc: 3 -> 0
- improved funnel_90:funnel draw_jump: 2 -> 0
- improved funnel_90:funnel head_jump: 8 -> 0
- improved gap_24:traverse foot_jump: 3 -> 0
- improved gap_32:traverse foot_jump: 8 -> 0
- improved gap_higher_16:traverse foot_jump: 1 -> 0
- improved gap_higher_32:traverse head_jump: 3 -> 0
- improved gap_higher_32:traverse foot_jump: 5 -> 0
- improved gap_lower_16:traverse draw_jump: 1 -> 0
- improved gap_lower_16:traverse head_jump: 2 -> 0
- improved gap_lower_16:traverse foot_jump: 4 -> 0
- improved jump_flat:jump_right foot_jump: 1 -> 0
- improved notch_wide_deep:traverse foot_jump: 1 -> 0
- improved overhang_wedge:traverse head_jump: 3 -> 0
- improved pillar:climb_over up_osc: 2 -> 0
- improved pillar:climb_over foot_jump: 1 -> 0
- improved pillar_thin:climb_over foot_jump: 1 -> 0
- improved pool:swim_across draw_jump: 1 -> 0
- improved pool:swim_across head_jump: 4 -> 0
- improved pool:swim_across foot_jump: 2 -> 0
- improved pool_bank_slope:swim_across foot_jump: 1 -> 0
- improved shelf_lip:traverse_left foot_jump: 1 -> 0
- improved slope_down_10:traverse_left foot_jump: 1 -> 0
- improved slope_down_20:traverse_left foot_jump: 2 -> 0
- improved slope_up_10:traverse foot_jump: 2 -> 0
- improved slope_up_30:traverse foot_jump: 4 -> 0
- improved slope_up_45:traverse foot_jump: 2 -> 0
- improved slot_24:slot foot_jump: 1 -> 0
- improved slot_36:slot foot_jump: 3 -> 0
- improved specks_floor:traverse up_osc: 1 -> 0
- improved specks_floor:traverse foot_jump: 2 -> 0
- improved step_down_12:traverse_left draw_jump: 1 -> 0
- improved step_down_12:traverse_left foot_jump: 2 -> 0
- improved step_down_16:traverse_left foot_jump: 1 -> 0
- improved step_down_24:traverse_left draw_jump: 2 -> 0
- improved step_down_24:traverse_left foot_jump: 4 -> 0
- improved step_down_32:traverse_left head_jump: 3 -> 0
- improved step_down_32:traverse_left foot_jump: 6 -> 0
- improved step_down_48:traverse_left foot_jump: 1 -> 0
- improved step_up_12:traverse foot_jump: 2 -> 0
- improved step_up_16:traverse foot_jump: 1 -> 0
- improved step_up_24:traverse draw_jump: 1 -> 0
- improved step_up_24:traverse head_jump: 3 -> 0
- improved step_up_24:traverse foot_jump: 4 -> 0
- improved step_up_32:traverse head_jump: 1 -> 0
- improved step_up_32:traverse foot_jump: 4 -> 0
- improved step_up_8:traverse draw_jump: 1 -> 0
- improved tunnel_45:traverse head_jump: 26 -> 0
- improved tunnel_45:traverse up_osc: 2 -> 0
- improved tunnel_45:traverse foot_jump: 1 -> 0
- improved tunnel_45:traverse sink: 1 -> 0
- improved tunnel_45_ragged:traverse head_jump: 29 -> 0
- improved tunnel_45_ragged:traverse up_osc: 2 -> 0
- improved tunnel_45_ragged:traverse sink: 1 -> 0
- improved tunnel_bend:traverse_long head_jump: 11 -> 0
- improved tunnel_bend:traverse_long foot_jump: 2 -> 0
- improved tunnel_level:traverse foot_jump: 5 -> 0
- improved tunnel_shaft:shaft foot_jump: 4 -> 0
- improved tunnel_up_bend:traverse_long foot_jump: 2 -> 0

## Failing runs

