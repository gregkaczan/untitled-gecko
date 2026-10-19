# Movement suite report

Runs: 95, passing: 95, failing: 0. Columns are event counts; * marks informational metrics; travel is the body's path length in px, a check that the scene was exercised.

Compared against baseline baseline.json.

| run | result | draw | head | dance | upflip | uposc | state | stall | ftog | fslide | fjump | sink | float | body* | stuck* | travel | outcome |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| boulder_120:boulder_big | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1421 | ok |
| boulder_30:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  (-2) |  | 1145 | ok |
| boulder_70:traverse | pass |  (-2) |  (-3) |  |  |  |  |  |  |  |  |  |  |  (-8) |  | 1119 | ok |
| box:box_round | pass |  (-7) |  (-4) |  |  |  |  |  |  |  |  |  |  |  (-9) |  | 1215 | ok |
| bump_2x2:traverse | pass |  (-1) |  |  |  |  |  |  |  |  |  (-1) |  |  |  (-1) |  | 1189 | ok |
| bump_row:traverse | pass |  |  |  |  |  (-1) |  |  |  |  |  |  |  |  (-2) |  | 1192 | ok |
| cave_1:traverse_long | pass |  (-2) |  |  |  |  (-2) |  |  |  |  |  (-11) |  |  | 4 (+1) |  | 929 | ok |
| cave_2:traverse_long | pass |  |  (-3) |  |  |  (-1) |  |  |  |  |  (-10) |  |  |  (-2) |  | 1961 | ok |
| cave_3:traverse_long | pass |  |  |  |  |  (-2) |  |  |  |  |  (-10) |  |  |  |  | 1969 | ok |
| cave_4:traverse_long | pass |  |  |  |  |  (-3) |  |  |  |  |  (-9) |  |  |  (-3) |  | 1939 | ok |
| cave_5:traverse_long | pass |  (-1) |  (-3) |  |  |  (-1) |  |  |  |  |  (-9) |  |  | 1 (-3) |  | 1920 | ok |
| cave_6:traverse_long | pass |  |  |  |  |  (-1) |  |  |  |  |  (-13) |  |  |  |  | 1959 | ok |
| ceiling_specks:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1192 | ok |
| ceiling_step_down:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  | 1 (-1) |  | 1161 | ok |
| ceiling_step_up:traverse | pass |  |  |  (-1) |  |  (-1) |  |  (-1) |  |  |  |  |  |  |  | 1144 | ok |
| ceiling_walk:bounce | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 743 | ok |
| ceiling_walk:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1181 | ok |
| cliff_jump:cliff_jump | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 892 | ok |
| cliff_walk:traverse | pass |  |  (-4) |  |  |  |  |  |  |  |  |  |  |  (-4) |  | 1143 | ok |
| corner_climb:wall_ceiling | pass |  (-2) |  (-2) |  |  |  |  |  |  |  |  |  |  |  (-2) |  | 1655 | ok |
| dig_45:dig_45 | pass |  |  |  |  |  |  |  |  |  |  (-2) |  |  |  |  | 435 | ok |
| dig_level_wall:dig_level | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 434 | ok |
| dig_shaft:dig_shaft | pass |  |  (-13) |  |  |  |  |  |  |  |  (-3) |  |  |  (-1) |  | 327 | ok |
| dig_turns:dig_turns | pass |  |  (-4) |  |  |  |  |  |  |  |  (-2) |  |  |  |  | 1040 | ok |
| drop_funnel:cliff_jump | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 656 | ok |
| flat:bounce | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 743 | ok |
| flat:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1181 | ok |
| funnel_40:funnel | pass |  |  |  |  |  |  |  |  |  |  |  |  |  | 4 | 692 | ok |
| funnel_60:funnel | pass |  |  |  |  |  (-3) |  |  |  |  |  |  |  |  | 4 | 709 | ok |
| funnel_90:funnel | pass |  (-2) |  (-8) |  |  |  |  |  |  |  |  |  |  |  (-2) | 4 | 724 | ok |
| gap_16:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  (-1) |  | 1182 | ok |
| gap_24:traverse | pass |  |  |  |  |  |  |  |  |  |  (-3) |  |  | 1 |  | 1184 | ok |
| gap_32:traverse | pass |  |  |  |  |  |  |  |  |  |  (-8) |  |  |  |  | 1183 | ok |
| gap_40:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 1418 | ok |
| gap_48:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 1428 | ok |
| gap_64:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1458 | ok |
| gap_8:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1181 | ok |
| gap_higher_16:traverse | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  | 1 (-4) |  | 1179 | ok |
| gap_higher_32:traverse | pass |  |  (-3) |  |  |  |  |  |  |  |  (-5) |  |  |  (-2) |  | 1161 | ok |
| gap_higher_48:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  | 1 | 1458 | ok |
| gap_lower_16:traverse | pass |  (-1) |  (-2) |  |  |  |  |  |  |  |  (-4) |  |  | 1 (-6) |  | 1168 | ok |
| gap_lower_32:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  | 1 |  | 1330 | ok |
| gap_lower_48:gap_cross | pass |  |  |  |  |  |  |  |  |  |  |  |  |  | 2 | 1388 | ok |
| jump_flat:jump_right | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  |  | 698 | ok |
| jump_flat:jump_up | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 165 | ok |
| jump_wall:jump_right | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 269 | ok |
| notch_1:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1183 | ok |
| notch_2:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1183 | ok |
| notch_deep:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  | 2 |  | 1187 | ok |
| notch_wide_deep:traverse | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  (-4) |  | 1170 | ok |
| overhang_shelf_under:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1181 | ok |
| overhang_wedge:traverse | pass |  |  (-3) |  |  |  |  |  |  |  |  |  |  |  (-3) | 3 (+3) | 1010 | ok |
| pillar:climb_over | pass |  |  |  |  |  (-2) |  |  |  |  |  (-1) |  |  |  (-2) |  | 1193 | ok |
| pillar_thin:climb_over | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  (-3) |  | 1035 | ok |
| pool:swim_across | pass |  (-1) |  (-4) |  |  |  |  |  |  |  |  (-2) |  |  |  (-4) |  | 1044 | ok |
| pool_bank_slope:swim_across | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  (-2) |  | 1011 | ok |
| shelf_lip:traverse_left | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  |  | 1176 | ok |
| slope_down_10:traverse_left | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  |  | 1192 | ok |
| slope_down_20:traverse_left | pass |  |  |  |  |  |  |  |  |  |  (-2) |  |  |  |  | 1196 | ok |
| slope_down_30:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1197 | ok |
| slope_down_45:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1184 | ok |
| slope_down_60:traverse_diag_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1194 | ok |
| slope_down_75:traverse_diag_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1187 | ok |
| slope_up_10:traverse | pass |  |  |  |  |  |  |  |  |  |  (-2) |  |  |  |  | 1192 | ok |
| slope_up_20:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1195 | ok |
| slope_up_30:traverse | pass |  |  |  |  |  |  |  |  |  |  (-4) |  |  |  |  | 1193 | ok |
| slope_up_45:traverse | pass |  |  |  |  |  |  |  |  |  |  (-2) |  |  |  |  | 1175 | ok |
| slope_up_60:traverse_diag | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1188 | ok |
| slope_up_75:traverse_diag | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1192 | ok |
| slot_20:slot | pass |  |  |  |  |  |  |  |  |  |  |  |  |  (-1) |  | 660 | ok |
| slot_24:slot | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  | 1 |  | 663 | ok |
| slot_28:slot | pass |  |  |  |  |  |  |  |  |  |  |  |  |  (-1) |  | 662 | ok |
| slot_36:slot | pass |  |  |  |  |  |  |  |  |  |  (-3) |  |  |  (-1) |  | 658 | ok |
| specks_floor:traverse | pass |  |  |  |  |  (-1) |  |  |  |  |  (-2) |  |  |  |  | 1192 | ok |
| step_down_12:traverse_left | pass |  (-1) |  |  |  |  |  |  |  |  |  (-2) |  |  |  (-1) |  | 1176 | ok |
| step_down_16:traverse_left | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  | 1 (-1) |  | 1186 | ok |
| step_down_24:traverse_left | pass |  (-2) |  |  |  |  |  |  |  |  |  (-4) |  |  |  (-5) |  | 1167 | ok |
| step_down_32:traverse_left | pass |  |  (-3) |  |  |  |  |  |  |  |  (-6) |  |  |  (-2) |  | 1162 | ok |
| step_down_48:traverse_left | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  |  (-4) |  | 1144 | ok |
| step_down_4:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1182 | ok |
| step_down_8:traverse_left | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1184 | ok |
| step_up_12:traverse | pass |  |  |  |  |  |  |  |  |  |  (-2) |  |  |  |  | 1187 | ok |
| step_up_16:traverse | pass |  |  |  |  |  |  |  |  |  |  (-1) |  |  | 1 (-1) |  | 1186 | ok |
| step_up_24:traverse | pass |  (-1) |  (-3) |  |  |  |  |  |  |  |  (-4) |  |  |  (-5) |  | 1164 | ok |
| step_up_32:traverse | pass |  |  (-1) |  |  |  |  |  |  |  |  (-4) |  |  |  (-4) |  | 1155 | ok |
| step_up_48:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  (-2) | 6 (+6) | 829 | ok |
| step_up_4:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  | 1182 | ok |
| step_up_8:traverse | pass |  (-1) |  |  |  |  |  |  |  |  |  |  |  |  (-1) |  | 1184 | ok |
| tunnel_45:traverse | pass |  |  (-26) |  |  |  (-2) |  |  |  |  |  (-1) |  (-1) |  |  |  (-13) | 1164 | ok |
| tunnel_45_ragged:traverse | pass |  |  (-29) |  |  |  (-2) |  |  |  |  |  |  (-1) |  |  |  (-11) | 1169 | ok |
| tunnel_bend:traverse_long | pass |  |  (-11) |  |  |  |  |  |  |  |  (-2) |  |  |  |  (-22) | 1202 | ok |
| tunnel_level:traverse | pass |  |  |  |  |  |  |  |  |  |  (-5) |  |  |  |  | 1187 | ok |
| tunnel_ragged:traverse | pass |  |  |  |  |  |  |  |  |  |  |  |  |  |  (-16) | 1190 | ok |
| tunnel_shaft:shaft | pass |  |  |  |  |  |  |  |  |  |  (-4) |  |  |  |  | 792 | ok |
| tunnel_up_bend:traverse_long | pass |  |  |  |  |  |  |  |  |  |  (-2) |  |  |  |  (-30) | 2333 | ok |

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

