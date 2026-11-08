#!/usr/bin/env python3
"""Generate src/proto/shape.cpy from the Horizon reference packet definitions.

Every Play, Configuration and Login packet becomes one shape string: a comma
separated list of wire tokens that the descriptor codec in src/proto/wire.cpy
walks. Token grammar:

  vi vl i8 i4 u4 i2 u2 i1 u1 f4 f8 bo uu st id by bt cm rx em ps sp cp
  vd lv vv cv  fixed leaves
  stN / idN      length limited text
  skN            N raw bytes
  o<tok>         optional leaf (bool prefix)
  ox<name>       optional composite (bool prefix, then a measured span)
  ar<name>       varint-counted list, elements recorded inline
  ax<name>       varint-counted list, elements measured into (offset,len) pairs
  x<name>        a named composite, recorded as a measured span
  <tok>@N        only read when field N of the same shape is non-zero
  <tok>@N.M      only read when bit M of field N is set

Composites are looked up by name in pw_sub_shape, which also passes primitive
tokens through so `ar<vi>` works without a table entry.

License boundary: the shapes mirror Horizon's public MIT definitions; no
Mojang code or data is read or emitted. See docs/PARITY_BOUNDARY.md.
"""

import io
import os
import re
import sys

REF = os.environ.get("HZREF", "../.hzref")
OUT = "src/proto/shape.cpy"

# ---- codec -> tokens ---------------------------------------------------------

LEAF = {
    "VarInt": ["vi"], "UVarInt": ["vi"], "VarInt31": ["vi"], "VarShort": ["vi"],
    "VarLong": ["vl"], "Long": ["i8"], "Int": ["i4"], "Short": ["i2"],
    "UShort": ["u2"], "Byte": ["i1"], "UByte": ["u1"], "Float": ["f4"],
    "Double": ["f8"], "Bool": ["bo"], "Boolean": ["bo"], "Uuid": ["uu"],
    "String": ["st"], "Str": ["st"], "Ident": ["id"], "ResourceLocation": ["id"],
    "Nbt": ["bt"], "ComponentNbt": ["cm"], "Pos": ["ps"], "SectionPos": ["sp"],
    "ChunkPos": ["cp"], "Vec3d": ["vd"], "LpVec3": ["lv"], "VarVec3i": ["vv"],
    "Bytes": ["by"], "ByteArray": ["by"], "BitSet": ["by"],
    "HolderId": ["vi"], "EntityMetadata": ["em"], "SignSide": ["bo"],
    "EntityData": ["em"], "RegistryId": ["vi"], "Byte": ["i1"],
    "OptVarInt": ["ovi"], "OptVarLong": ["ovl"], "OptBoolean": ["obo"],
    # Rust type spellings, so a codec written as a type still resolves.
    "i8": ["i1"], "u8": ["u1"], "i16": ["i2"], "u16": ["u2"], "i32": ["i4"],
    "u32": ["u4"], "i64": ["i8"], "u64": ["u8"], "f32": ["f4"], "f64": ["f8"],
    "bool": ["bo"], "u128": ["uu"], "String": ["st"], "Tag": ["bt"],
}

# Hand-authored composites, keyed by the snake name used in a shape string.
EXTRA_SUB = {
    "fixed3": ["u1", "u1", "u1"],
    "cursor": ["f4", "f4", "f4"],
    "signature": ["by"],
    "packed_signature": ["vi", "oby"],
    "filter_mask": ["vi", "ar<vl>"],
    "last_seen_update": ["vi", "u1", "u1", "u1", "i1"],
    "look_at_entity": ["vi", "vi"],
    "global_pos": ["id", "ps"],
    "chat_type_bound": ["vi", "bt", "obt"],
    "game_rule_entry": ["id", "st"],
    "chunk_biome_data": ["cp", "by"],
    "map_decoration": ["vi", "i1", "i1", "i1", "obt"],
    "clock_state": ["vi", "vl", "f4", "f4"],
    "minecart_step": ["vd", "vd", "i1", "i1", "f4"],
    "attribute_modifier": ["id", "f8", "vi"],
    "attribute_snapshot": ["vi", "f8", "ar<attribute_modifier>"],
    "sign_lines": ["st", "st", "st", "st"],
    "book_pages": ["ar<st>"],
    "stat_entry": ["vi", "vi", "i4"],
    "stat_list": ["ar<stat_entry>"],
    "sound_extra": ["id", "of4"],
    "sound_holder": ["vi", "ox<sound_extra>"],
    "test_instance_data": ["oid", "vv", "vi", "bo", "vi", "obt"],
    "entity_event": ["i4", "i1"],
    "team_parameters": ["bt", "bt", "bt", "vi", "vi", "ovi", "i1"],
    "click_payload": ["by"],
    "server_link": ["bo", "ovi@0", "bt@0!", "st"],
    "map_decoration_list": ["ar<map_decoration>"],
    "map_patch": ["u1", "u1", "u1", "u1", "vi", "rx"],
    "player_info_entry": ["uu"],
}

# Packets whose layout the reference states in code rather than a field list.
MANUAL_SHAPES = {
    "stop_sound": "u1,ovi@0.0,st@0.1",
    "set_player_team": "st,i1,ox<team_parameters>@1&253=0,ar<st>@1=0|3|4",
    "custom_payload": "id,rx",
    "custom_query": "vi,id,rx",
    "custom_query_answer": "vi,bo,rx",
    "custom_click_action": "id,x<click_payload>",
    "intention": "vi,st255,u2,vi",
    "seen_advancements": "vi,ost@0=0",
    "server_links": "ar<server_link>",
    "map_item_data": "vi,i1,bo,ox<map_decoration_list>,ox<map_patch>",
    "set_structure_block":
        "ps,vi,vi,st,i1,i1,i1,i1,i1,i1,vi,vi,st128,f4,vl,i1",
    "client_information": "st,i1,vi,bo,u1,vi,bo,bo,vi",
}

# Codecs the engine cannot describe yet: the packet is left without a shape so
# the codec reports pw_err_shape and the session survives.
UNSUPPORTED = {
    "Slot", "Hashed", "HashedSlot", "DelimitedSlot", "Component", "Stack",
    "ItemStack", "Particle", "DialogHolder", "NumberFormat", "MapPatch",
    "MapPatchOpt", "Offers", "PositionPath", "ChunkData", "LightData",
    "ChangedSlots", "Equipment", "ArgumentSignatures", "Commands", "Node",
    "RewriteOptions", "Dialog", "JukeboxSong", "MusicDisc", "Value",
    "ItemStacks", "RegistryData", "RegistryDataEntry", "TransferInt",
    "Declaration", "Loot", "BlockDescriptor", "ItemDescriptor", "Source",
}


def snake(name):
    name = name.split("::")[-1]
    out = re.sub(r"(?<=[a-z0-9])([A-Z])", r"_\1", name)
    out = re.sub(r"(?<=[A-Z])([A-Z][a-z])", r"_\1", out)
    return out.lower()


def tokens_of(codec, type_str="", depth=0):
    """Tokens for one field. Returns None when the codec is not describable."""
    codec = codec.strip()
    if codec.startswith("crate::"):
        codec = codec.split("::")[-1]
    if codec.endswith("?"):
        codec = "Opt<" + codec[:-1] + ">"
    m = re.match(r"^Opt<(?>[^<>]+|<[^<>]*>)+>$", codec)
    if m:
        inner = tokens_of(codec[4:-1], type_str, depth)
        if inner is None:
            return None
        if len(inner) == 1:
            return ["o" + inner[0]]
        return ["ox<" + composite(inner) + ">"]
    m = re.match(r"^List<(.+)>\$$", codec)
    m = re.match(r"^(?:List|Array|Vec)<(.+)>$", codec)
    if m:
        inner = tokens_of(m.group(1), type_str, depth + 1)
        if inner is None:
            return None
        if len(inner) == 1:
            return ["ar<" + inner[0] + ">"]
        return ["ar<" + composite(inner) + ">"]
    m = re.match(r"^(?:PalettedContainer|Counted)<(.+)>$", codec)
    if m:
        return None
    m = re.match(r"^StrN<(\d+)>$", codec)
    if m:
        return ["st" + m.group(1)]
    m = re.match(r"^IdentN<(\d+)>$", codec)
    if m:
        return ["id" + m.group(1)]
    m = re.match(r"^BytesN<(\d+)>$", codec)
    if m:
        return ["by"]
    m = re.match(r"^Array<(\d+)>$", codec)
    if m:
        return ["sk" + m.group(1)]
    m = re.match(r"^FixedBytes<(\d+)>$", codec)
    if m:
        return ["sk" + m.group(1)]
    m = re.match(r"^Hashed<(.+)>$", codec)
    if m:
        return None
    m = re.match(r"^Remapped\((.+)\)$", codec)
    if m:
        return tokens_of(m.group(1), type_str, depth)
    if codec in LEAF:
        return list(LEAF[codec])
    if codec in EXTRA_SUB:
        return ["x<" + codec + ">"]
    if snake(codec) in EXTRA_SUB:
        return ["x<" + snake(codec) + ">"]
    if codec in UNSUPPORTED:
        return None
    if codec in LEAF:
        return list(LEAF[codec])
    clean = codec.split("::")[-1]
    if depth < 6 and clean in STRUCTS:
        inner = shape_fields(STRUCTS[clean], depth + 1)
        if inner is None:
            return None
        return ["x<" + composite(inner) + ">"]
    return None
    if codec.startswith("Empty"):
        return []
    return None


STRUCTS = {}
COMPOSITES = {}


def composite(tokens):
    """Register an anonymous composite made of `tokens`, return its name."""
    shape = ",".join(tokens)
    for name, existing in COMPOSITES.items():
        if existing == shape:
            return name
    name = "c_" + re.sub(r"[^a-z0-9_]", "", snake(shape))
    base = name
    n = 0
    while name in COMPOSITES:
        n += 1
        name = base + str(n)
    COMPOSITES[name] = shape
    return name


def add_named_composites():
    for name, tokens in EXTRA_SUB.items():
        COMPOSITES[name] = ",".join(tokens)
    for entry in ("packet", "packet_field"):
        pass


# ---- reference parsing -------------------------------------------------------

PACKET_RE = re.compile(r"packet!\s*\(\s*([\w:]+)\s*\{([^{}]*)\}", re.S)
DOC_RE = re.compile(r"^\s*///")
FIELD_RE = re.compile(r"([\w]+)\s*:\s*([^=]*?)\s*=>\s*([^,\n]+)")
ENUM_RE = re.compile(r"packet_enum!\s*\((\w+),\s*crate::ids::(\w+)::(\w+)\s*\{(.*?)\}\s*\);",
                     re.S)
ENUM_ITEM_RE = re.compile(r"(\w+)\s*\(\s*([\w:<>]+)\s*\)\s*=\s*([A-Z0-9_]+)")
IDS_RE = re.compile(
    r"pub mod (\w+) \{\s*pub mod (\w+) \{(.*?)\n\s*\}\s*\}", re.S)
ID_CONST_RE = re.compile(r"pub const ([A-Z0-9_]+): i32 = (\d+);")
NAMES_RE = re.compile(r'pub const NAMES: &\[&str\] = &\[(.*?)\];', re.S)


def parse_packets(files):
    structs = {}
    for path in files:
        text = io.open(path, encoding="utf-8").read()
        text = re.sub(r"^\s*///.*$", "", text, flags=re.M)
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        for m in PACKET_RE.finditer(text):
            name = m.group(1).split("::")[-1]
            body = m.group(2)
            fields = []
            for fm in FIELD_RE.finditer(body):
                fields.append((fm.group(1), fm.group(2).strip(), fm.group(3).strip()))
            structs[name] = fields
    return structs


def parse_id_names(files):
    """CONSTANT -> vanilla name, per state and direction."""
    table = {}
    for path in files:
        text = io.open(path, encoding="utf-8").read()
        text = re.sub(r"pub const NAMES:.*?\];",
                      lambda m: re.sub(r"\s+", " ", m.group(0)),
                      text, flags=re.S)
        state = direction = None
        for raw in text.split("\n"):
            line = raw.strip()
            mod = re.match(r"pub mod (\w+) \{", line)
            if mod:
                if state is None:
                    state = mod.group(1)
                else:
                    direction = mod.group(1)
                continue
            if line.startswith("}"):
                if direction is not None:
                    direction = None
                else:
                    state = None
                continue
            const = re.match(r"pub const ([A-Z0-9_]+): i32 = (\d+);", line)
            if const and state and direction:
                table.setdefault(state + "." + direction, {})[const.group(1)] = int(const.group(2))
                continue
            names = NAMES_RE.search(line)
            if names and state and direction:
                by_id = table[state + "." + direction]
                vanilla = re.findall(r'"([^"]+)"', line)
                inv = {v: k for k, v in by_id.items()}
                table[state + "." + direction] = {
                    inv[i]: name for i, name in enumerate(vanilla) if i in inv
                }
    return table


def parse_enums(files):
    """state.direction.id -> struct name (or None for Empty)."""
    mapping = {}
    for path in files:
        text = io.open(path, encoding="utf-8").read()
        text = re.sub(r"^\s*///.*$", "", text, flags=re.M)
        text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
        for m in ENUM_RE.finditer(text):
            direction = m.group(3)
            body = m.group(4)
            key = m.group(2) + "." + direction
            for im in ENUM_ITEM_RE.finditer(body):
                mapping.setdefault(key, {})[im.group(3)] = im.group(2)
    return mapping


# ---- shape building ----------------------------------------------------------

def shape_fields(fields, depth=0):
    tokens = []
    for name, type_str, codec in fields:
        toks = tokens_of(codec, type_str, depth)
        if toks is None:
            return None
        tokens.extend(toks)
    return ",".join(tokens)


def shape_for(fields, problems, label):
    shape = shape_fields(fields)
    if shape is None:
        problems.add("%s: no shape (see UNSUPPORTED)" % label)
    return shape


def main():
    add_named_composites()
    structs = parse_packets([os.path.join(REF, f) for f in
                             ("play.rs", "configuration.rs", "login.rs",
                              "recipes.rs", "status.rs", "handshake.rs",
                              "entity_data.rs", "item.rs", "chunk.rs")
                             if os.path.exists(os.path.join(REF, f))])
    names = parse_id_names([os.path.join(REF, "ids.rs")])
    enums = parse_enums([os.path.join(REF, "play.rs"),
                         os.path.join(REF, "configuration.rs"),
                         os.path.join(REF, "login.rs")])

    global STRUCTS
    STRUCTS = structs
    problems = set()
    shapes = dict(MANUAL_SHAPES)
    covered = {}
    total = {}
    for key, per_id in sorted(enums.items()):
        vanilla_by_id = names.get(key, {})
        good = 0
        for const, struct in per_id.items():
            vanilla = vanilla_by_id.get(const)
            if vanilla is None:
                continue
            total[key] = total.get(key, 0) + 1
            if struct == "Empty":
                shapes[vanilla] = ""
                good += 1
                continue
            clean = struct.split("::")[-1]
            fields = structs.get(clean)
            if fields is None:
                problems.add("%s: no definition for %s" % (key, clean))
                continue
            shape = shape_for(fields, problems, vanilla)
            if shape is None:
                continue
            shapes[vanilla] = shape
            good += 1
        covered[key] = good

    lines = []
    lines.append("# Vortex protocol - packet shapes for protocol 777 (Minecraft 26.3).")
    lines.append("#")
    lines.append("# GENERATED by tools/gen_shapes.py from the Horizon reference definitions; do")
    lines.append("# not edit by hand. One shape string per packet describes its fields as a")
    lines.append("# comma separated token list, which src/proto/wire.cpy walks. A packet with")
    lines.append("# no shape here is unknown to the codec: it costs one undecoded packet and")
    lines.append("# never the connection.")
    lines.append("#")
    lines.append("# License boundary: these describe Horizon's public MIT packet definitions;")
    lines.append("# no Mojang code or data. See docs/PARITY_BOUNDARY.md.")
    lines.append("")
    lines.append("import stdlib")
    lines.append("")
    lines.append("")
    lines.append("# A composite referenced by name from a shape (`x<name>`, `ar<name>`).")
    lines.append("# Primitive tokens pass through so `ar<vi>` needs no table entry.")
    lines.append("public def pw_sub_shape(name: str) -> str:")
    for token in sorted(set(sum([v for v in LEAF.values()], []))):
        lines.append('    if str_equals(name, "%s"): return "%s"' % (token, token))
    for name in sorted(COMPOSITES):
        if name in LEAF:
            continue
        lines.append('    if str_equals(name, "%s"): return "%s"'
                     % (name, COMPOSITES[name]))
    lines.append('    return ""')
    lines.append("")
    lines.append("")
    lines.append("# The shape of one packet, by the name protocol_ids.cpy stores.")
    lines.append("public def pw_shape(name: str) -> str:")
    for vanilla in sorted(shapes):
        lines.append('    if str_equals(name, "%s"): return "%s"'
                     % (vanilla, shapes[vanilla]))
    lines.append('    return ""')
    lines.append("")
    lines.append("")
    lines.append("def pw_shape_names() -> str[]:")
    lines.append("    str[] out = new str[0]")
    for vanilla in sorted(shapes):
        lines.append('    append(out, "%s")' % vanilla)
    lines.append("    return out")
    lines.append("")
    lines.append("")
    lines.append("public def pw_shape_count() -> int:")
    lines.append("    return len(pw_shape_names())")
    lines.append("")
    lines.append("")
    lines.append("# True when a packet is described (an empty shape is: it carries no fields).")
    lines.append("public def pw_shape_known(name: str) -> int:")
    lines.append("    str[] names = pw_shape_names()")
    lines.append("    int i = 0")
    lines.append("    while i < len(names):")
    lines.append("        if str_equals(names[i], name):")
    lines.append("            return 1")
    lines.append("        i += 1")
    lines.append("    return 0")
    lines.append("")

    io.open(OUT, "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")

    print("wrote %s: %d shapes, %d composites" % (OUT, len(shapes), len(COMPOSITES)))
    for key in sorted(total):
        print("  %-18s %3d/%3d packets described" % (key, covered.get(key, 0), total[key]))
    missing = []
    for key in names:
        for _, vanilla in sorted(names[key].items()):
            if vanilla not in shapes:
                missing.append((key, vanilla))
    by_key = {}
    for key, vanilla in missing:
        by_key.setdefault(key, []).append(vanilla)
    for key in sorted(by_key):
        print("  %-22s no shape for %2d: %s" % (key, len(by_key[key]),
                                                " ".join(sorted(by_key[key]))))
    if problems:
        print("notes (%d unique):" % len(problems))
        for p in sorted(problems)[:40]:
            print("   ", p)


if __name__ == "__main__":
    sys.exit(main())
