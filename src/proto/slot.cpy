# Vortex engine - the 26.3 item stack and its data components.
#
# Wire layout (protocol 777, verified against the published 26.x interchange
# description):
#
#   Slot             itemCount VarInt          0 means the slot is empty
#                    itemId VarInt             only when itemCount != 0
#                    addedComponentCount VarInt
#                    removedComponentCount VarInt
#                    components              addedComponentCount entries of
#                                            { type VarInt, payload }
#                    removeComponents        removedComponentCount VarInts
#
#   ItemStackTemplate is the same envelope with an explicit itemCount, used by
#   bundles, charged projectiles and the use-remainder component.
#
# A component's payload length depends on its type, so the reader has to know
# every one of the 122 types to find the end of a stack. Everything here is a
# structural walk: it validates the bytes and reports where the stack ends,
# without building a tree, because the renderer only needs the id and count
# until the item atlas lands.
#
# Registry holders follow the interchange rule for a holder: a VarInt of 0 is
# followed by the inline value, anything else is a registry id minus one and
# carries no payload. A holder set is a VarInt of 0 followed by a tag name, or
# a count plus one followed by that many registry ids.
#
# One self-recursive dispatcher walks the whole tree. Cpyte needs a definition
# before its use, so mutually recursive readers are not expressible; a single
# node number space keeps the cycle inside one function instead.

import stdlib


public def sl_component_count() -> int:
    return 122


public def sl_depth_max() -> int:
    return 12


public def sl_array_max() -> int:
    return 4096


public def sl_stack_max() -> int:
    return 1024


public def sl_text_max() -> int:
    return 32767


public def sl_item_max() -> int:
    return 1000000


def sl_fail_named(name: str) -> int64:
    if len(name) > 0:
        print("Slot: rejected component {name}")
    return (int64)-1


def sl_fail() -> int64:
    return sl_fail_named("")


# A varint into scratch[0]; the return value is the next cursor.
def sl_value(data: int64[], cursor: int64, scratch: int64[]) -> int64:
    int64[] read = decode_varint(data, cursor)
    if read[0] != 1:
        return sl_fail()
    scratch[0] = read[1]
    return read[2]


def sl_byte(data: int64[], cursor: int64, scratch: int64[]) -> int64:
    if cursor < 0 or cursor >= len(data):
        return sl_fail()
    scratch[0] = data[cursor]
    return cursor + 1


def sl_text(data: int64[], cursor: int64) -> int64:
    int64[] read = read_string_field(data, cursor, sl_text_max())
    if read[0] != 1:
        return sl_fail()
    return read[2] + read[1]


# One unnamed network NBT tag: a type byte, then that type's payload.
def sl_tag(data: int64[], cursor: int64) -> int64:
    if cursor < 0 or cursor >= len(data):
        return sl_fail()
    int64[] after = skip_nbt_payload(data, data[cursor], cursor + 1, 0)
    if after[0] != 1 or after[2] <= cursor:
        return sl_fail()
    return after[2]


def sl_count(data: int64[], cursor: int64, scratch: int64[]) -> int64:
    int64 at = sl_value(data, cursor, scratch)
    if at < 0:
        return sl_fail()
    if scratch[0] < (int64)0 or scratch[0] > (int64)sl_array_max():
        return sl_fail()
    return at


# A holder set: zero introduces a tag name, otherwise the value is one more
# than the number of registry ids that follow.
def sl_holder_set(data: int64[], cursor: int64, scratch: int64[]) -> int64:
    int64 at = sl_value(data, cursor, scratch)
    if at < 0:
        return sl_fail()
    int64 size = scratch[0]
    if size < (int64)0 or size > (int64)sl_array_max():
        return sl_fail()
    if size == (int64)0:
        return sl_text(data, at)
    int64 left = size - 1
    while left > (int64)0:
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        left = left - 1
    return at


# The 26.3 component names, in registry id order. Only used for diagnostics:
# a payload that cannot be walked is refused with its name printed.
def sl_component_name(component: int) -> str:
    if component == 0:
        return "custom_data"
    if component == 1:
        return "max_stack_size"
    if component == 2:
        return "max_damage"
    if component == 3:
        return "damage"
    if component == 4:
        return "unbreakable"
    if component == 5:
        return "use_effects"
    if component == 6:
        return "custom_name"
    if component == 7:
        return "minimum_attack_charge"
    if component == 8:
        return "damage_type"
    if component == 9:
        return "item_name"
    if component == 10:
        return "item_model"
    if component == 11:
        return "lore"
    if component == 12:
        return "rarity"
    if component == 13:
        return "enchantments"
    if component == 14:
        return "can_place_on"
    if component == 15:
        return "can_break"
    if component == 16:
        return "attribute_modifiers"
    if component == 17:
        return "custom_model_data"
    if component == 18:
        return "tooltip_display"
    if component == 19:
        return "repair_cost"
    if component == 20:
        return "creative_slot_lock"
    if component == 21:
        return "enchantment_glint_override"
    if component == 22:
        return "intangible_projectile"
    if component == 23:
        return "food"
    if component == 24:
        return "consumable"
    if component == 25:
        return "use_remainder"
    if component == 26:
        return "use_cooldown"
    if component == 27:
        return "damage_resistant"
    if component == 28:
        return "tool"
    if component == 29:
        return "weapon"
    if component == 30:
        return "attack_range"
    if component == 31:
        return "enchantable"
    if component == 32:
        return "equippable"
    if component == 33:
        return "repairable"
    if component == 34:
        return "glider"
    if component == 35:
        return "tooltip_style"
    if component == 36:
        return "death_protection"
    if component == 37:
        return "blocks_attacks"
    if component == 38:
        return "piercing_weapon"
    if component == 39:
        return "kinetic_weapon"
    if component == 40:
        return "attack_animation"
    if component == 41:
        return "interact_animation"
    if component == 42:
        return "additional_trade_cost"
    if component == 43:
        return "block_transformer"
    if component == 44:
        return "villager_food"
    if component == 45:
        return "stored_enchantments"
    if component == 46:
        return "dye"
    if component == 47:
        return "dyed_color"
    if component == 48:
        return "map_id"
    if component == 49:
        return "map_decorations"
    if component == 50:
        return "map_post_processing"
    if component == 51:
        return "charged_projectiles"
    if component == 52:
        return "bundle_contents"
    if component == 53:
        return "potion_contents"
    if component == 54:
        return "potion_duration_scale"
    if component == 55:
        return "suspicious_stew_effects"
    if component == 56:
        return "writable_book_content"
    if component == 57:
        return "written_book_content"
    if component == 58:
        return "trim"
    if component == 59:
        return "debug_stick_state"
    if component == 60:
        return "entity_data"
    if component == 61:
        return "bucket_entity_data"
    if component == 62:
        return "block_entity_data"
    if component == 63:
        return "instrument"
    if component == 64:
        return "provides_trim_material"
    if component == 65:
        return "ominous_bottle_amplifier"
    if component == 66:
        return "jukebox_playable"
    if component == 67:
        return "provides_banner_patterns"
    if component == 68:
        return "recipes"
    if component == 69:
        return "lodestone_tracker"
    if component == 70:
        return "firework_explosion"
    if component == 71:
        return "fireworks"
    if component == 72:
        return "profile"
    if component == 73:
        return "note_block_sound"
    if component == 74:
        return "banner_patterns"
    if component == 75:
        return "base_color"
    if component == 76:
        return "pot_decorations"
    if component == 77:
        return "container"
    if component == 78:
        return "block_state"
    if component == 79:
        return "bees"
    if component == 80:
        return "sulfur_cube_content"
    if component == 81:
        return "lock"
    if component == 82:
        return "container_loot"
    if component == 83:
        return "break_sound"
    if component == 84:
        return "compostable"
    if component == 85:
        return "cooking_fuel"
    if component == 86:
        return "brewing_fuel"
    if component == 87:
        return "mob_visibility"
    if component == 88:
        return "villager/variant"
    if component == 89:
        return "wolf/variant"
    if component == 90:
        return "wolf/sound_variant"
    if component == 91:
        return "wolf/collar"
    if component == 92:
        return "fox/variant"
    if component == 93:
        return "salmon/size"
    if component == 94:
        return "parrot/variant"
    if component == 95:
        return "tropical_fish/pattern"
    if component == 96:
        return "tropical_fish/base_color"
    if component == 97:
        return "tropical_fish/pattern_color"
    if component == 98:
        return "mooshroom/variant"
    if component == 99:
        return "rabbit/variant"
    if component == 100:
        return "pig/variant"
    if component == 101:
        return "pig/sound_variant"
    if component == 102:
        return "cow/variant"
    if component == 103:
        return "cow/sound_variant"
    if component == 104:
        return "chicken/variant"
    if component == 105:
        return "chicken/sound_variant"
    if component == 106:
        return "zombie_nautilus/variant"
    if component == 107:
        return "frog/variant"
    if component == 108:
        return "horse/variant"
    if component == 109:
        return "painting/variant"
    if component == 110:
        return "llama/variant"
    if component == 111:
        return "axolotl/variant"
    if component == 112:
        return "cat/variant"
    if component == 113:
        return "cat/sound_variant"
    if component == 114:
        return "cat/collar"
    if component == 115:
        return "sheep/color"
    if component == 116:
        return "shulker/color"
    if component == 117:
        return "provides_pottery_pattern"
    if component == 118:
        return "sign_text_front"
    if component == 119:
        return "sign_text_back"
    if component == 120:
        return "waxed"
    if component == 121:
        return "cushion/color"
    return "?"


# Components whose whole payload is one VarInt: the scalars, the id mappers
# and every registry holder with no inline form.
def sl_shape_varint(component: int) -> int:
    if component == 1 or (component == 2 or component == 3):
        return 1
    if component == 8 or (component == 12 or component == 19):
        return 1
    if component == 31 or (component == 42 or component == 43):
        return 1
    if component == 44 or (component == 46 or component == 48):
        return 1
    if component == 50 or (component == 60 or component == 65):
        return 1
    if component == 75:
        return 1
    if component >= 88 and component <= 108:
        return 1
    if component >= 110 and component <= 117:
        return 1
    return 0


# One unnamed network NBT tag: the JSON only components and the chat
# components that are streamed as NBT.
def sl_shape_nbt(component: int) -> int:
    if component == 6 or (component == 9 or component == 61):
        return 1
    return 0


# One resource location.
def sl_shape_text(component: int) -> int:
    if component == 10 or (component == 35 or component == 73):
        return 1
    return 0


# The first node of a payload, or -1 when it carries no bytes and -2 when its
# shape is not known here.
def sl_component_first(component: int) -> int:
    if component == 4 or (component == 20 or component == 34):
        return -1
    if component == 120:
        return -1
    # These have no networkSynchronized codec, so a server never puts them in a
    # stack. Landing here means the bytes are not what they claim to be.
    if component == 0 or (component == 22 or component == 49):
        return -2
    if component == 59 or (component == 68 or component == 81):
        return -2
    if component == 82:
        return -2
    if sl_shape_varint(component):
        return 250
    if sl_shape_nbt(component):
        return 255
    if sl_shape_text(component):
        return 254
    if component == 7 or component == 54:
        return 252
    if component == 47:
        return 251
    if component == 21:
        return 253
    if component == 11:
        return 1255
    if component == 13 or (component == 45 or component == 55):
        return 1240
    if component == 14 or component == 15:
        return 1215
    if component == 16:
        return 1233
    if component == 27 or (component == 33 or component == 67):
        return 211
    if component == 36:
        return 1214
    if component == 51 or component == 52:
        return 1202
    if component == 25 or component == 80:
        return 202
    if component == 56:
        return 1238
    if component == 70:
        return 218
    if component == 72:
        return 219
    if component == 74:
        return 1243
    if component == 79:
        return 1237
    if component == 63:
        return 627
    if component == 64:
        return 625
    if component == 66:
        return 628
    if component == 83:
        return 644
    if component == 109:
        return 629
    if component == 77:
        return 300
    if component == 78:
        return 303
    if component == 84:
        return 304
    if component == 118 or component == 119:
        return 320
    # Multi field payloads, of which these are the first step.
    if component == 5:
        return 253
    if component == 18:
        return 253
    if component == 23:
        return 250
    if component == 24:
        return 252
    if component == 26:
        return 252
    if component == 17:
        return 1252
    if component == 28:
        return 1234
    if component == 29:
        return 250
    if component == 30:
        return 252
    if component == 32:
        return 250
    if component == 37:
        return 252
    if component == 38:
        return 253
    if component == 39:
        return 250
    if component == 40 or component == 41:
        return 250
    if component == 53:
        return 258
    if component == 57:
        return 238
    if component == 58:
        return 625
    if component == 62:
        return 250
    if component == 69:
        return 2231
    if component == 71:
        return 250
    if component == 76:
        return 2202
    if component == 85 or component == 86:
        return 304
    if component == 87:
        return 211
    return -2


# The step at index, for the payloads with more than one field. -1 ends the
# payload, and any component not listed here is a single step payload.
def sl_component_next(component: int, index: int) -> int:
    if component == 5:
        if index == 1:
            return 253
        if index == 2:
            return 252
        return -1
    if component == 17:
        if index == 1:
            return 1253
        if index == 2:
            return 1254
        if index == 3:
            return 1251
        return -1
    if component == 18:
        if index == 1:
            return 1250
        return -1
    if component == 23:
        if index == 1:
            return 252
        if index == 2:
            return 253
        return -1
    if component == 24:
        if index == 1:
            return 250
        if index == 2:
            return 644
        if index == 3:
            return 253
        if index == 4:
            return 1214
        return -1
    if component == 26:
        if index == 1:
            return 256
        return -1
    if component == 28:
        if index == 1:
            return 252
        if index == 2:
            return 250
        if index == 3:
            return 253
        return -1
    if component == 29:
        if index == 1:
            return 252
        return -1
    if component == 30:
        if index < 6:
            return 252
        return -1
    if component == 32:
        if index == 1:
            return 644
        if index == 2:
            return 256
        if index == 3:
            return 256
        if index == 4:
            return 2211
        if index < 10:
            return 253
        if index == 10:
            return 644
        return -1
    if component == 37:
        if index == 1:
            return 252
        if index == 2:
            return 1235
        if index == 3:
            return 236
        if index == 4:
            return 2211
        if index == 5:
            return 2210
        if index == 6:
            return 2210
        return -1
    if component == 38:
        if index == 1:
            return 253
        if index == 2:
            return 2210
        if index == 3:
            return 2210
        return -1
    if component == 39:
        if index == 1:
            return 250
        if index < 5:
            return 2232
        if index < 7:
            return 252
        if index == 7:
            return 2210
        if index == 8:
            return 2210
        return -1
    if component == 40 or component == 41:
        if index == 1:
            return 250
        return -1
    if component == 53:
        if index == 1:
            return 259
        if index == 2:
            return 1213
        if index == 3:
            return 256
        return -1
    if component == 57:
        if index == 1:
            return 254
        if index == 2:
            return 250
        if index == 3:
            return 1239
        if index == 4:
            return 253
        return -1
    if component == 58:
        if index == 1:
            return 626
        return -1
    if component == 62:
        if index == 1:
            return 255
        return -1
    if component == 69:
        if index == 1:
            return 253
        return -1
    if component == 71:
        if index == 1:
            return 1218
        return -1
    if component == 76:
        if index < 4:
            return 2202
        return -1
    if component == 85 or component == 86:
        if index == 1:
            return 305
        return -1
    if component == 87:
        if index == 1:
            return 252
        return -1
    return -1


def sl_component_step(component: int, index: int) -> int:
    if index == 0:
        return sl_component_first(component)
    return sl_component_next(component, index)


# Node numbers. Components are their own type id, 0 to 121. Above that:
#
#   200 the component lists that close a stack envelope
#   201 a Slot              202 an ItemStackTemplate
#   210 sound holder        211 holder set        212 effect detail
#   213 potion effect       214 consume effect    215 block predicate
#   216 block property      217 component matchers
#   218 firework explosion  219 resolvable profile 220 skin patch
#   221 game profile        222 partial profile   223 profile property
#   225 trim material       226 trim pattern
#   227 instrument data     228 jukebox song      229 painting variant
#   230 banner pattern      231 global position   232 kinetic condition
#   233 attribute modifier  234 tool rule         235 damage reduction
#   236 item damage         237 hive occupant     238 filtered string
#   239 filtered component  240 varint pair       243 banner layer
#   244 sound event
#   250 varint  251 i32  252 f32  253 bool  254 string  255 nbt
#   256 optional string   257 optional nbt      258 optional varint
#   259 optional i32      260 optional f32      261 optional bool
#   262 uuid  263 optional uuid     264 f64  265 block position
#   300 list of optional stacks     301 typed component value
#   303 string keyed string map     304 resolvable int
#   305 resolvable float            306 component matcher entry
#   307 attribute modifier value    320 sign text
#   400 + n  a registry holder whose inline value is node n
#   1000 + n a VarInt counted array of node n
#   2000 + n a boolean prefixed optional node n
def sl_node(data: int64[], cursor: int64, node: int, depth: int,
            scratch: int64[]) -> int64:
    if depth > sl_depth_max():
        return sl_fail()
    if cursor < 0 or cursor > len(data):
        return sl_fail()
    int down = depth + 1
    if node >= 2000:
        int64 at = sl_byte(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] == (int64)0:
            return at
        if scratch[0] != (int64)1:
            return sl_fail()
        return sl_node(data, at, node - 2000, down, scratch)
    if node >= 1000:
        int64 at = sl_count(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 left = scratch[0]
        int element = node - 1000
        while left > (int64)0:
            at = sl_node(data, at, element, down, scratch)
            if at < 0:
                return sl_fail()
            left = left - 1
        return at
    if node >= 400:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 holder = scratch[0]
        if holder < (int64)0:
            return sl_fail()
        if holder == (int64)0:
            return sl_node(data, at, node - 400, down, scratch)
        return at
    if node == 200:
        int64 at = sl_count(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 added = scratch[0]
        at = sl_count(data, at, scratch)
        if at < 0:
            return sl_fail()
        int64 removed = scratch[0]
        if added + removed > (int64)sl_array_max():
            return sl_fail()
        while added > (int64)0:
            at = sl_value(data, at, scratch)
            if at < 0:
                return sl_fail()
            int64 kind = scratch[0]
            if kind < (int64)0 or kind >= (int64)sl_component_count():
                return sl_fail()
            at = sl_node(data, at, (int)kind, down, scratch)
            if at < 0:
                return sl_fail_named(sl_component_name((int)kind))
            added = added - 1
        while removed > (int64)0:
            at = sl_value(data, at, scratch)
            if at < 0:
                return sl_fail()
            if scratch[0] < (int64)0 or scratch[0] >= (int64)sl_component_count():
                return sl_fail()
            removed = removed - 1
        return at
    if node == 201:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 count = scratch[0]
        if count < (int64)0 or count > (int64)sl_stack_max():
            return sl_fail()
        if count == (int64)0:
            return at
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] < (int64)0 or scratch[0] > (int64)sl_item_max():
            return sl_fail()
        return sl_node(data, at, 200, down, scratch)
    if node == 202:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] < (int64)0 or scratch[0] > (int64)sl_item_max():
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] < (int64)0 or scratch[0] > (int64)sl_stack_max():
            return sl_fail()
        return sl_node(data, at, 200, down, scratch)
    if node == 210:
        return sl_node(data, cursor, 644, down, scratch)
    if node == 211:
        return sl_holder_set(data, cursor, scratch)
    if node == 212:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 253, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 253, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 253, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 2212, down, scratch)
    if node == 213:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 212, down, scratch)
    if node == 214:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 kind = scratch[0]
        if kind == (int64)0:
            at = sl_node(data, at, 1213, down, scratch)
            if at < 0:
                return sl_fail()
            return sl_node(data, at, 252, down, scratch)
        if kind == (int64)1:
            return sl_node(data, at, 211, down, scratch)
        if kind == (int64)2:
            return at
        if kind == (int64)3:
            at = sl_node(data, at, 252, down, scratch)
            if at < 0:
                return sl_fail()
            return sl_node(data, at, 253, down, scratch)
        if kind == (int64)4:
            return sl_node(data, at, 210, down, scratch)
        return sl_fail()
    if node == 215:
        int64 at = sl_node(data, cursor, 2211, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 3216, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 257, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 217, down, scratch)
    if node == 216:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        at = sl_byte(data, at, scratch)
        if at < 0:
            return sl_fail()
        int64 exact = scratch[0]
        if exact == (int64)0:
            return sl_text(data, at)
        if exact != (int64)1:
            return sl_fail()
        at = sl_node(data, at, 256, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 256, down, scratch)
    if node == 217:
        int64 at = sl_node(data, cursor, 1301, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 1306, down, scratch)
    if node == 218:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 1251, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 1251, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 253, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 253, down, scratch)
    if node == 219:
        int64 at = sl_byte(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 kind = scratch[0]
        if kind == (int64)0:
            at = sl_node(data, at, 221, down, scratch)
        elif kind == (int64)1:
            at = sl_node(data, at, 222, down, scratch)
        else:
            return sl_fail()
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 220, down, scratch)
    if node == 220:
        int64 at = sl_node(data, cursor, 256, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 256, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 256, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 261, down, scratch)
    if node == 221:
        int64 at = pl_take(data, cursor, 16)
        if at < 0:
            return sl_fail()
        at = sl_text(data, at)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 1223, down, scratch)
    if node == 222:
        int64 at = sl_node(data, cursor, 256, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 263, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 1223, down, scratch)
    if node == 223:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        at = sl_text(data, at)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 256, down, scratch)
    if node == 225:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 255, down, scratch)
    if node == 226:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 255, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 253, down, scratch)
    if node == 227:
        int64 at = sl_node(data, cursor, 210, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 252, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 252, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 255, down, scratch)
    if node == 228:
        int64 at = sl_node(data, cursor, 210, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 255, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 252, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_value(data, at, scratch)
    if node == 229:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        at = sl_text(data, at)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 257, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 257, down, scratch)
    if node == 230:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        return sl_text(data, at)
    if node == 231:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        return pl_take(data, at, 8)
    if node == 232:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 252, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 252, down, scratch)
    if node == 233:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 307, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        int64 display = scratch[0]
        if display == (int64)2:
            return sl_node(data, at, 255, down, scratch)
        if display < (int64)0 or display > (int64)2:
            return sl_fail()
        return at
    if node == 234:
        int64 at = sl_node(data, cursor, 211, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 260, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 261, down, scratch)
    if node == 235:
        int64 at = sl_node(data, cursor, 252, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 2211, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 252, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 252, down, scratch)
    if node == 236:
        return pl_take(data, cursor, 12)
    if node == 237:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        return sl_value(data, at, scratch)
    if node == 238:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 256, down, scratch)
    if node == 239:
        int64 at = sl_node(data, cursor, 255, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 257, down, scratch)
    if node == 240:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        return sl_value(data, at, scratch)
    if node == 243:
        int64 at = sl_node(data, cursor, 630, down, scratch)
        if at < 0:
            return sl_fail()
        return sl_value(data, at, scratch)
    if node == 244:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 260, down, scratch)
    if node == 250:
        return sl_value(data, cursor, scratch)
    if node == 251 or node == 252:
        return pl_take(data, cursor, 4)
    if node == 253:
        return sl_byte(data, cursor, scratch)
    if node == 254:
        return sl_text(data, cursor)
    if node == 255:
        return sl_tag(data, cursor)
    if node == 262:
        return pl_take(data, cursor, 16)
    if node == 264 or node == 265:
        return pl_take(data, cursor, 8)
    if node >= 256 and node <= 263:
        int64 at = sl_byte(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] == (int64)0:
            return at
        if scratch[0] != (int64)1:
            return sl_fail()
        int inner = 254
        if node == 257:
            inner = 255
        elif node == 258:
            inner = 250
        elif node == 259:
            inner = 251
        elif node == 260:
            inner = 252
        elif node == 261:
            inner = 253
        elif node == 263:
            inner = 262
        return sl_node(data, at, inner, down, scratch)
    if node == 300:
        int64 at = sl_count(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 left = scratch[0]
        while left > (int64)0:
            at = sl_node(data, at, 2202, down, scratch)
            if at < 0:
                return sl_fail()
            left = left - 1
        return at
    if node == 301:
        int64 at = sl_value(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 kind = scratch[0]
        if kind < (int64)0 or kind >= (int64)sl_component_count():
            return sl_fail()
        return sl_node(data, at, (int)kind, down, scratch)
    if node == 303:
        int64 at = sl_count(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        int64 left = scratch[0]
        while left > (int64)0:
            at = sl_text(data, at)
            if at < 0:
                return sl_fail()
            at = sl_text(data, at)
            if at < 0:
                return sl_fail()
            left = left - 1
        return at
    if node == 304:
        int64 at = sl_byte(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] == (int64)0:
            return pl_take(data, at, 4)
        if scratch[0] != (int64)1:
            return sl_fail()
        return sl_text(data, at)
    if node == 305:
        int64 at = sl_byte(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] == (int64)0:
            return pl_take(data, at, 4)
        if scratch[0] != (int64)1:
            return sl_fail()
        return sl_text(data, at)
    if node == 306:
        int64 at = sl_byte(data, cursor, scratch)
        if at < 0:
            return sl_fail()
        if scratch[0] > (int64)1:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        return sl_node(data, at, 255, down, scratch)
    if node == 307:
        int64 at = sl_text(data, cursor)
        if at < 0:
            return sl_fail()
        at = pl_take(data, at, 8)
        if at < 0:
            return sl_fail()
        return sl_value(data, at, scratch)
    if node == 320:
        int64 at = sl_node(data, cursor, 255, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 255, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 255, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_node(data, at, 255, down, scratch)
        if at < 0:
            return sl_fail()
        at = sl_byte(data, at, scratch)
        if at < 0:
            return sl_fail()
        int64 filtered = scratch[0]
        if filtered == (int64)1:
            at = sl_node(data, at, 255, down, scratch)
            if at < 0:
                return sl_fail()
            at = sl_node(data, at, 255, down, scratch)
            if at < 0:
                return sl_fail()
            at = sl_node(data, at, 255, down, scratch)
            if at < 0:
                return sl_fail()
            at = sl_node(data, at, 255, down, scratch)
            if at < 0:
                return sl_fail()
        elif filtered != (int64)0:
            return sl_fail()
        at = sl_value(data, at, scratch)
        if at < 0:
            return sl_fail()
        return sl_byte(data, at, scratch)

    # Everything below is one component payload: walk its step list.
    int component = node
    if component < 0 or component >= sl_component_count():
        return sl_fail()
    int64 here = cursor
    int index = 0
    int step = sl_component_step(component, 0)
    while step >= 0:
        here = sl_node(data, here, step, down, scratch)
        if here < 0:
            return sl_fail_named(sl_component_name(component))
        index = index + 1
        step = sl_component_step(component, index)
    if step == -2:
        return sl_fail_named(sl_component_name(component))
    return here


public def sl_component_known(component: int) -> int:
    if component < 0 or component >= sl_component_count():
        return 0
    return 1


# Skip one component payload, for a caller that already read the type varint.
public def sl_skip_component(data: int64[], cursor: int64, component: int) -> int64:
    int64[] scratch = new int64[1]
    return sl_node(data, cursor, component, 0, scratch)


# Read one Slot. out receives {present, item id, count}; the return value is
# the offset after the stack, or -1 when the bytes are not a valid stack.
public def sl_read(data: int64[], cursor: int64, out: int64[]) -> int64:
    out[0] = 0
    out[1] = 0
    out[2] = 0
    int64[] scratch = new int64[1]
    int64 at = sl_value(data, cursor, scratch)
    if at < 0:
        return sl_fail()
    int64 count = scratch[0]
    if count < (int64)0 or count > (int64)sl_stack_max():
        return sl_fail()
    if count == (int64)0:
        return at
    at = sl_value(data, at, scratch)
    if at < 0:
        return sl_fail()
    int64 item = scratch[0]
    if item < (int64)0 or item > (int64)sl_item_max():
        return sl_fail()
    at = sl_node(data, at, 200, 0, scratch)
    if at < 0:
        return sl_fail()
    out[0] = 1
    out[1] = item
    out[2] = count
    return at


# Read one ItemStackTemplate: the same envelope with an explicit item count.
public def sl_read_template(data: int64[], cursor: int64,
                            out: int64[]) -> int64:
    out[0] = 0
    out[1] = 0
    out[2] = 0
    int64[] scratch = new int64[1]
    int64 at = sl_value(data, cursor, scratch)
    if at < 0:
        return sl_fail()
    int64 item = scratch[0]
    if item < (int64)0 or item > (int64)sl_item_max():
        return sl_fail()
    at = sl_value(data, at, scratch)
    if at < 0:
        return sl_fail()
    int64 count = scratch[0]
    if count < (int64)0 or count > (int64)sl_stack_max():
        return sl_fail()
    at = sl_node(data, at, 200, 0, scratch)
    if at < 0:
        return sl_fail()
    out[0] = 1
    out[1] = item
    out[2] = count
    return at

# Public entry points for the registry-holder forms, so the recipe and display
# readers can reuse the same length rules as the component payloads.
public def sl_read_node(data: int64[], cursor: int64, node: int) -> int64:
    int64[] scratch = new int64[1]
    return sl_node(data, cursor, node, 0, scratch)


public def sl_read_holder(data: int64[], cursor: int64, node: int) -> int64:
    return sl_read_node(data, cursor, 400 + node)


public def sl_read_holder_set(data: int64[], cursor: int64) -> int64:
    int64[] scratch = new int64[1]
    return sl_holder_set(data, cursor, scratch)
