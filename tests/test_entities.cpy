# Vortex engine - entity registry tests.

import stdlib


def ent_near(label: str, got: double, want: double, fails: int*) -> void:
    double delta = got - want
    if delta < 0.0:
        delta = -delta
    if delta > 0.000001:
        print(f"FAIL {label}: got {(int)(got * 1000000.0)} want {(int)(want * 1000000.0)}")
        *fails = *fails + 1


def main() -> int:
    int fails = 0
    VEntities* table = ventities_new()
    check("table starts empty", table.count == 0 and ventities_find(table, 5) < 0, &fails)
    check("id 5 is created on touch", ventities_touch(table, 5) >= 0, &fails)
    check("id 5 is found", ventities_find(table, 5) >= 0, &fails)
    check("count follows inserts", table.count == 1, &fails)
    check("touch is idempotent", ventities_touch(table, 5) >= 0 and table.count == 1, &fails)
    check("unknown id stays absent", ventities_find(table, 6) < 0, &fails)

    check("negative ids are refused", ventities_touch(table, -3) < 0, &fails)
    check("oversized reserve is refused", ventities_reserve(table, 65537) == 0, &fails)
    check("unset type reads as -1", ventities_type(table, 5) == -1, &fails)
    check("type is stored", ventities_set_type(table, 5, 61) == 1, &fails)
    check_int("type reads back", ventities_type(table, 5), 61, &fails)

    check("position is stored", ventities_set_position(table, 5, 1.5, -2.25, 3.0) == 1, &fails)
    ent_near("position x", ventities_position(table, 5, 0), 1.5, &fails)
    ent_near("position y", ventities_position(table, 5, 1), -2.25, &fails)
    ent_near("position z", ventities_position(table, 5, 2), 3.0, &fails)
    check("delta axis is refused", ventities_move_by(table, 999, 1.0, 1.0, 1.0) == 0, &fails)
    check("relative move accumulates", ventities_move_by(table, 5, 0.5, -0.25, 2.0) == 1, &fails)
    ent_near("moved x", ventities_position(table, 5, 0), 2.0, &fails)
    ent_near("moved y", ventities_position(table, 5, 1), -2.5, &fails)
    ent_near("moved z", ventities_position(table, 5, 2), 5.0, &fails)

    check("motion is stored", ventities_set_motion(table, 5, 0.1, 0.2, 0.3) == 1, &fails)
    ent_near("motion y", ventities_motion(table, 5, 1), 0.2, &fails)
    check("out of range axis reads zero", ventities_position(table, 5, 3) == 0.0, &fails)

    check("angle is stored", ventities_set_angle(table, 5, 1, 64) == 1, &fails)
    ent_near("angle converts to degrees", ventities_angle(table, 5, 1), 90.0, &fails)
    check("angle accepts a full turn", ventities_set_angle(table, 5, 1, 320) == 1, &fails)
    ent_near("angle is masked into a byte", ventities_angle(table, 5, 1), 90.0, &fails)
    check("bad angle slot is refused", ventities_set_angle(table, 5, 9, 1) == 0, &fails)
    check("bad angle does not create entity", ventities_find(table, 77) < 0, &fails)

    check("live flag is set on insert", ventities_flag(table, 5, vent_flag_live()) == 1, &fails)
    check("on ground starts off", ventities_flag(table, 5, vent_flag_on_ground()) == 0, &fails)
    check("on ground can be set", ventities_set_flag(table, 5, vent_flag_on_ground(), true) == 1, &fails)
    check("on ground reads back", ventities_flag(table, 5, vent_flag_on_ground()) == 1, &fails)
    check("on ground can be cleared", ventities_set_flag(table, 5, vent_flag_on_ground(), false) == 1, &fails)
    check("cleared on ground reads zero", ventities_flag(table, 5, vent_flag_on_ground()) == 0, &fails)

    check("value is stored", ventities_set_value(table, 5, 0, -20) == 1, &fails)
    check_int("value reads back", (int)ventities_value(table, 5, 0), -20, &fails)
    check("out of range value is refused", ventities_set_value(table, 5, 99, 1) == 0, &fails)
    check("bad value does not create entity", ventities_find(table, 78) < 0, &fails)

    int64[] name = new int64[8]
    name[0] = 67
    name[1] = 114
    name[2] = 101
    name[3] = 101
    name[4] = 112
    name[5] = 101
    name[6] = 114
    check("name is stored", ventities_set_name(table, 5, name, 7) == 1, &fails)
    check("negative name length rejected", ventities_set_name(table, 80, name, -1) == 0, &fails)
    check("name length beyond buffer rejected", ventities_set_name(table, 81, name, 9) == 0, &fails)
    check("invalid name does not create entity", ventities_find(table, 80) < 0 and ventities_find(table, 81) < 0, &fails)
    check_int("name length reads back", ventities_name_length(table, 5), 7, &fails)
    check_int("first name byte", ventities_name_byte(table, 5, 0), 67, &fails)
    check_int("name is NUL padded", ventities_name_byte(table, 5, 7), 0, &fails)

    check("absent entity name is empty", ventities_name_length(table, 77) == 0, &fails)

    int64[] long_name = new int64[200]
    int fill = 0
    while fill < 200:
        long_name[fill] = 65
        fill = fill + 1
    check("overlong name is truncated", ventities_set_name(table, 5, long_name, 200) == 1, &fails)
    check_int("truncated name length", ventities_name_length(table, 5), ventity_name_stride() - 1, &fails)

    check("removal reports the entity", ventities_drop(table, 5) == 1, &fails)
    check("removed entity is gone", ventities_find(table, 5) < 0, &fails)
    check("count follows removal", table.count == 0, &fails)
    check("removing twice is a no-op", ventities_drop(table, 5) == 0, &fails)

    int probe = 0
    while probe < 4000:
        ventities_touch(table, probe * 3 + 1)
        ventities_set_position(table, probe * 3 + 1, (double)probe, 1.0, 2.0)
        probe = probe + 1
    check("growth kept every entity", table.count == 4000, &fails)
    check("growth kept capacity above load", table.capacity >= 8192, &fails)
    check("rehashed lookup works", ventities_find(table, 3999 * 3 + 1) >= 0, &fails)
    ent_near("rehashed payload", ventities_position(table, 1234 * 3 + 1, 0), 1234.0, &fails)

    probe = 0
    while probe < 2000:
        ventities_drop(table, probe * 3 + 1)
        probe = probe + 1
    check("half removal counted", table.count == 2000, &fails)
    check("removed entry stays removed", ventities_find(table, 1) < 0, &fails)
    check("survivor after a hole", ventities_find(table, 3999 * 3 + 1) >= 0, &fails)
    ent_near("survivor payload after hole",
             ventities_position(table, 3999 * 3 + 1, 0), 3999.0, &fails)

    ventities_free(table)
    return report("entities", fails)
