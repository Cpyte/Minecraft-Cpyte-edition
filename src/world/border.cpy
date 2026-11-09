# Vortex engine - world border state.
#
# The six border packets each carry one field of the same object, so the table
# keeps the whole border and every handler updates its slice. Diameters are
# doubles because the server interpolates them; the transition speed is a
# varlong millisecond count.

public def vborder_default_diameter() -> double:
    return 59999968.0


public def vborder_default_boundary() -> int:
    return 29999984


public def vborder_default_warning_blocks() -> int:
    return 5


public def vborder_default_warning_time() -> int:
    return 15


struct VBorder:
    double center_x
    double center_z
    double diameter
    double old_diameter
    double new_diameter
    int64 lerp_remaining
    int portal_boundary
    int warning_blocks
    int warning_time
    bool initialised


public def vborder_new() -> VBorder*:
    VBorder* border = new VBorder
    border.center_x = 0.0
    border.center_z = 0.0
    border.diameter = vborder_default_diameter()
    border.old_diameter = border.diameter
    border.new_diameter = border.diameter
    border.lerp_remaining = 0
    border.portal_boundary = vborder_default_boundary()
    border.warning_blocks = vborder_default_warning_blocks()
    border.warning_time = vborder_default_warning_time()
    border.initialised = false
    return border


public def vborder_free(border: VBorder*) -> void:
    if border != null:
        del border


public def vborder_initialize(border: VBorder*, x: double, z: double,
                              old_diameter: double, new_diameter: double,
                              speed: int64, boundary: int, warning_blocks: int,
                              warning_time: int) -> int:
    if border == null or old_diameter < 0.0 or new_diameter < 0.0:
        return 1
    if speed < 0 or boundary < 1 or warning_blocks < 0 or warning_time < 0:
        return 1
    border.center_x = x
    border.center_z = z
    border.old_diameter = old_diameter
    border.new_diameter = new_diameter
    border.diameter = old_diameter
    border.lerp_remaining = speed
    border.portal_boundary = boundary
    border.warning_blocks = warning_blocks
    border.warning_time = warning_time
    border.initialised = true
    return 0


public def vborder_set_center(border: VBorder*, x: double, z: double) -> int:
    if border == null:
        return 1
    border.center_x = x
    border.center_z = z
    return 0


public def vborder_set_size(border: VBorder*, diameter: double) -> int:
    if border == null or diameter < 0.0:
        return 1
    border.diameter = diameter
    border.old_diameter = diameter
    border.new_diameter = diameter
    border.lerp_remaining = 0
    return 0


public def vborder_lerp_size(border: VBorder*, old_diameter: double,
                             new_diameter: double, speed: int64) -> int:
    if border == null or old_diameter < 0.0 or new_diameter < 0.0 or speed < 0:
        return 1
    border.old_diameter = old_diameter
    border.new_diameter = new_diameter
    border.diameter = old_diameter
    border.lerp_remaining = speed
    return 0


public def vborder_set_warning_delay(border: VBorder*, seconds: int) -> int:
    if border == null or seconds < 0:
        return 1
    border.warning_time = seconds
    return 0


public def vborder_set_warning_distance(border: VBorder*, blocks: int) -> int:
    if border == null or blocks < 0:
        return 1
    border.warning_blocks = blocks
    return 0


# Half-width of the current border, the distance a client compares against.
public def vborder_radius(border: VBorder*) -> double:
    if border == null:
        return 0.0
    return border.diameter / 2.0


public def vborder_contains(border: VBorder*, x: double, z: double) -> bool:
    if border == null:
        return true
    double radius = vborder_radius(border)
    double dx = x - border.center_x
    double dz = z - border.center_z
    if dx < 0.0:
        dx = 0.0 - dx
    if dz < 0.0:
        dz = 0.0 - dz
    return dx <= radius and dz <= radius