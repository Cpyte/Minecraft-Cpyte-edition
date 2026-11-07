#!/usr/bin/env python3
"""Build Vortex's compact block database from the vanilla data generator report.

Input:  reports/blocks.json + reports/registries.json from
        `java -DbundlerMainClass=net.minecraft.data.Main -jar server.jar
         --reports --output generated`
Output: generated/blockdb.bin (and optionally a synthetic test fixture).

The report is Mojang-generated data, so it is not part of this repository and
the output is written below `generated/` (git-ignored). What this script adds
is our own classification: a handful of flags per block that the mesher uses.
The state id -> block mapping is a faithful copy of the report; the flags are
a heuristic over block names and properties, documented as such.

Binary layout (little endian):

    char magic[8]        "VBLKDB01"
    u32  state_count
    u32  block_count
    u32  name_bytes
    record[block_count]  each 20 bytes:
        u32 protocol_id
        u32 first_state
        u16 state_count
        u16 flags
        u32 name_offset
        u16 name_len
        u16 reserved
    char names[name_bytes]   concatenated, without the "minecraft:" prefix

Blocks are sorted by first_state, and every block's states are contiguous, so
state lookup is a binary search over records.
"""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

# Classification flags. Keep in sync with src/world/blockdb.cpy.
FLAG_AIR = 1 << 0
FLAG_FLUID = 1 << 1
FLAG_CUBE = 1 << 2
FLAG_OPAQUE = 1 << 3
FLAG_TRANSLUCENT = 1 << 4
FLAG_LEAVES = 1 << 5
FLAG_CROSS = 1 << 6

AIR_BLOCKS = {"air", "cave_air", "void_air"}

FLUID_BLOCKS = {"water", "lava"}

TRANSLUCENT_BLOCKS = {
    "glass",
    "tinted_glass",
    "ice",
    "packed_ice",
    "blue_ice",
    "frosted_ice",
    "slime_block",
    "honey_block",
    "water",
    "lava",
    "beacon",
    "sea_lantern",
    "copper_grate",
    "exposed_copper_grate",
    "weathered_copper_grate",
    "oxidized_copper_grate",
    "waxed_copper_grate",
    "waxed_exposed_copper_grate",
    "waxed_weathered_copper_grate",
    "waxed_oxidized_copper_grate",
}

LEAF_SUFFIXES = ("_leaves",)
LEAF_BLOCKS = {"mangrove_roots"}

# Plants and other flat/cross geometry: emitted as crossed quads.
CROSS_BLOCKS = {
    "short_grass",
    "tall_grass",
    "fern",
    "large_fern",
    "dead_bush",
    "short_dry_grass",
    "tall_dry_grass",
    "firefly_bush",
    "bush",
    "dandelion",
    "poppy",
    "blue_orchid",
    "allium",
    "azure_bluet",
    "red_tulip",
    "orange_tulip",
    "white_tulip",
    "pink_tulip",
    "oxeye_daisy",
    "cornflower",
    "lily_of_the_valley",
    "wither_rose",
    "torchflower",
    "sunflower",
    "lilac",
    "rose_bush",
    "peony",
    "wheat",
    "carrots",
    "potatoes",
    "beetroots",
    "torchflower_crop",
    "pitcher_crop",
    "melon_stem",
    "pumpkin_stem",
    "attached_melon_stem",
    "attached_pumpkin_stem",
    "sweet_berry_bush",
    "nether_wart",
    "crimson_roots",
    "warped_roots",
    "nether_sprouts",
    "seagrass",
    "tall_seagrass",
    "kelp",
    "kelp_plant",
    "sugar_cane",
    "bamboo",
    "bamboo_sapling",
    "cocoa",
    "vine",
    "cave_vines",
    "cave_vines_plant",
    "twisting_vines",
    "weeping_vines",
    "hanging_roots",
    "glow_lichen",
    "sculk_vein",
    "pink_petals",
    "wildflowers",
    "leaf_litter",
    "torch",
    "wall_torch",
    "soul_torch",
    "soul_wall_torch",
    "redstone_torch",
    "redstone_wall_torch",
    "copper_torch",
    "copper_wall_torch",
    "cobweb",
    "fire",
    "soul_fire",
}
CROSS_SUFFIXES = ("_sapling", "_coral", "_coral_fan", "_coral_wall_fan")

# Everything that is not a full cube and is not crossed geometry. The mesher
# skips these rather than drawing a wrong cube; a full client would use the
# block model assets, which this project deliberately does not ship.
ATTACHED_SUFFIXES = (
    "_slab",
    "_stairs",
    "_fence",
    "_fence_gate",
    "_wall",
    "_door",
    "_trapdoor",
    "_button",
    "_pressure_plate",
    "_carpet",
    "_pane",
    "_bars",
    "_chain",
    "_lantern",
    "_sign",
    "_banner",
    "_bed",
    "_candle",
    "_candles",
    "_cake",
    "_plant",
    "_flower",
    "_tulip",
    "_orchid",
    "_bluet",
    "_daisy",
    "_poppy",
    "_rose",
    "_lily",
    "_grass",
    "_fern",
    "_bush",
    "_vine",
    "_stem",
    "_rail",
    "_repeater",
    "_comparator",
    "_lever",
    "_wire",
    "_hook",
    "_tripwire",
    "_scaffolding",
    "_campfire",
    "_anvil",
    "_cauldron",
    "_composter",
    "_hopper",
    "_lectern",
    "_brewing_stand",
    "_conduit",
    "_chest",
    "_shulker_box",
    "_skull",
    "_head",
    "_egg",
    "_pickle",
    "_frogspawn",
    "_portal",
    "_fire",
    "_bud",
    "_cluster",
    "_spawner",
    "_piston_head",
    "_dragon_egg",
    "_amethyst",
    "_banner",
    "_wall_hanging_sign",
    "_hanging_sign",
    "_cocoa",
)
ATTACHED_BLOCKS = {
    "moving_piston",
    "flower_pot",
    "decorated_pot",
    "composter",
    "hopper",
    "lectern",
    "brewing_stand",
    "beacon",
    "conduit",
    "chest",
    "trapped_chest",
    "ender_chest",
    "barrel",
    "scaffolding",
    "campfire",
    "soul_campfire",
    "anvil",
    "chipped_anvil",
    "damaged_anvil",
    "cauldron",
    "water_cauldron",
    "lava_cauldron",
    "powder_snow_cauldron",
    "enchanting_table",
    "stonecutter",
    "grindstone",
    "smithing_table",
    "cartography_table",
    "fletching_table",
    "loom",
    "bell",
    "lantern",
    "soul_lantern",
    "twisted_vines",
    "nether_portal",
    "end_portal",
    "end_gateway",
    "piston_head",
}


def classify(name: str) -> int:
    """Flags for a block name, without the namespace."""
    base = name.split(":", 1)[-1]
    if base in AIR_BLOCKS:
        return FLAG_AIR
    if base in FLUID_BLOCKS:
        return FLAG_FLUID | FLAG_CUBE | FLAG_TRANSLUCENT
    if base in LEAF_BLOCKS or base.endswith(LEAF_SUFFIXES):
        return FLAG_CUBE | FLAG_LEAVES
    if base in CROSS_BLOCKS or base.endswith(CROSS_SUFFIXES):
        return FLAG_CROSS
    if base in TRANSLUCENT_BLOCKS:
        return FLAG_CUBE | FLAG_TRANSLUCENT
    if base in ATTACHED_BLOCKS or base.endswith(ATTACHED_SUFFIXES):
        return 0
    return FLAG_CUBE | FLAG_OPAQUE


def load(blocks_path: Path, registries_path: Path):
    blocks = json.loads(blocks_path.read_text())
    registries = json.loads(registries_path.read_text())
    registry = registries["minecraft:block"]["entries"]

    records = []
    state_count = 0
    for name, entry in blocks.items():
        states = entry.get("states", [])
        if not states:
            continue
        ids = sorted(state["id"] for state in states)
        if ids != list(range(ids[0], ids[0] + len(ids))):
            raise SystemExit(f"{name}: states are not contiguous")
        protocol = registry.get(name, {}).get("protocol_id")
        if protocol is None:
            raise SystemExit(f"{name}: missing block registry id")
        records.append(
            {
                "name": name.split(":", 1)[-1],
                "protocol_id": protocol,
                "first_state": ids[0],
                "state_count": len(ids),
                "flags": classify(name),
            }
        )
        state_count += len(ids)

    records.sort(key=lambda r: r["first_state"])
    expected = 0
    for record in records:
        if record["first_state"] != expected:
            raise SystemExit(
                f"state space is not tiled: {record['name']} starts at "
                f"{record['first_state']}, expected {expected}"
            )
        expected += record["state_count"]
    if state_count != expected:
        raise SystemExit("state count mismatch")
    return records, state_count


def write_binary(records, state_count: int, out: Path) -> None:
    names = bytearray()
    offsets = []
    for record in records:
        encoded = record["name"].encode()
        offsets.append((len(names), len(encoded)))
        names += encoded
    out.parent.mkdir(parents=True, exist_ok=True)
    with out.open("wb") as handle:
        handle.write(b"VBLKDB01")
        handle.write(struct.pack("<III", state_count, len(records), len(names)))
        for record, (offset, length) in zip(records, offsets):
            handle.write(
                struct.pack(
                    "<IIHHIHH",
                    record["protocol_id"],
                    record["first_state"],
                    record["state_count"],
                    record["flags"],
                    offset,
                    length,
                    0,
                )
            )
        handle.write(names)


def fixture_records():
    """A synthetic database used by the loader test; no vanilla data involved."""
    rows = [
        ("air", 0, 1, FLAG_AIR),
        ("stone", 1, 1, FLAG_CUBE | FLAG_OPAQUE),
        ("oak_log", 2, 3, FLAG_CUBE | FLAG_OPAQUE),
        ("water", 5, 2, FLAG_FLUID | FLAG_CUBE | FLAG_TRANSLUCENT),
        ("glass", 7, 1, FLAG_CUBE | FLAG_TRANSLUCENT),
        ("oak_leaves", 8, 1, FLAG_CUBE | FLAG_LEAVES),
        ("short_grass", 9, 1, FLAG_CROSS),
        ("oak_slab", 10, 2, 0),
    ]
    records = []
    for protocol, (name, first, count, flags) in enumerate(rows):
        records.append(
            {
                "name": name,
                "protocol_id": protocol,
                "first_state": first,
                "state_count": count,
                "flags": flags,
            }
        )
    return records, rows[-1][1] + rows[-1][2]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--blocks", type=Path)
    parser.add_argument("--registries", type=Path)
    parser.add_argument("--out", type=Path, default=Path("generated/blockdb.bin"))
    parser.add_argument(
        "--fixture",
        action="store_true",
        help="write a small synthetic database instead of reading a report",
    )
    args = parser.parse_args()

    if args.fixture:
        records, state_count = fixture_records()
    else:
        if not args.blocks or not args.registries:
            parser.error("--blocks and --registries are required without --fixture")
        records, state_count = load(args.blocks, args.registries)

    write_binary(records, state_count, args.out)
    print(
        f"wrote {args.out}: {len(records)} blocks, {state_count} states, "
        f"{args.out.stat().st_size} bytes"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
