#!/usr/bin/env python3
"""Reusable authoring tooling for RUN//UNIT's Tiled route maps.

The playable route is authored in a Tiled `.tmj` map whose `Semantic` layer owns
every piece of collision (assets/generated/metadata/semantic_tile_contract.json).
This module turns that map into things a level designer can work with quickly:

    sketch   .tmj  -> a plain-text grid that is easy to read and hand-edit
    build    grid  -> a valid .tmj, reusing an existing map as a template so the
                      decorative layers and tileset wiring survive untouched
    check    validate a .tmj against the engine contract *and* the player motor,
             including whether the Goal is actually reachable from the Spawn
    autoart  regenerate the decorative ArtDeck / TunnelShell layers from geometry

`check` replays the real `RunUnitPlayerMotor` integration step and reads that
motor's exported constants straight out of scripts/player/player_motor.gd, so a
route can be proven traversable in milliseconds without opening Godot.

Everything here is deterministic: the same inputs always produce byte-identical
output, and an unmodified map round-trips through `sketch` + `build` unchanged.
"""

from __future__ import annotations

import argparse
import json
import math
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]

# Tiled stores tile mirroring in the high bits of every global tile id.
FLIP_HORIZONTAL = 0x80000000
FLIP_VERTICAL = 0x40000000
FLIP_DIAGONAL = 0x20000000
GID_MASK = 0x1FFFFFFF

# Layer names `scripts/world/static_world.gd` looks for by name.
SEMANTIC_LAYER = "Semantic"
OBSTACLE_LAYER = "Obstacles"
MARKER_LAYER = "Markers"
DECK_LAYER = "ArtDeck"
SHELL_LAYER = "TunnelShell"
LAYER_ORDER = (
    SEMANTIC_LAYER,
    OBSTACLE_LAYER,
    SHELL_LAYER,
    "ArtBackground",
    "ArtStructure",
    DECK_LAYER,
    MARKER_LAYER,
)
SPAWN_MARKER = "Spawn"
GOAL_MARKER = "Goal"

# Semantic cell values, per assets/generated/metadata/semantic_tile_contract.json.
SEMANTIC_EMPTY = 0
SEMANTIC_SOLID = 1
SEMANTIC_ONE_WAY = 2
STANDABLE = (SEMANTIC_SOLID, SEMANTIC_ONE_WAY)
CONTRACT_VALUES = {0: "empty", 1: "solid", 2: "one_way", 3: "hazard", 4: "conveyor", 5: "foreground"}

EMPTY_GLYPH = "."
# Sketch glyphs are keyed by the tileset's `data_semantic_name`, never by tile id,
# so re-ordering the semantic tileset cannot silently repaint a level.
SEMANTIC_GLYPHS = {
    "solid": "#",
    "one_way": "=",
    "hazard": "^",
    "conveyor": ">",
    "foreground": "*",
}
OBSTACLE_GLYPHS = {"gate_ceiling": "T"}
MARKER_GLYPHS = {SPAWN_MARKER: "S", GOAL_MARKER: "G"}

# ArtDeck trim, as local tile ids inside the industrial zone tileset: a capped
# top row, then two body rows whose three-tile pattern repeats along the run.
DECK_TILESET = "industrial_zone.tsj"
DECK_CAP_LEFT = 54
DECK_CAP_MID = 55
DECK_CAP_RIGHT = 56
DECK_BODY_ROWS = ((57, 58, 59), (66, 67, 68))
# TunnelShell backdrop: one macro bulkhead tile, 11 cells wide and 7 cells tall.
SHELL_TILESET = "bulkhead_macro.tsj"
SHELL_TILE = 0
SHELL_COLUMNS = 11
SHELL_ROWS = 7


class LevelKitError(Exception):
    """Raised for malformed input that the caller is expected to report."""


# --------------------------------------------------------------------------
# Tiled reading
# --------------------------------------------------------------------------


def read_json(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as error:
        raise LevelKitError(f"missing file: {path}") from error
    except json.JSONDecodeError as error:
        raise LevelKitError(f"{path}: invalid JSON ({error})") from error


def write_json(path: Path, value: object) -> None:
    """Write Tiled-style JSON: two-space indent, LF endings, trailing newline."""
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8", newline="\n")


@dataclass(frozen=True)
class TileDef:
    """One tile of a tileset, reduced to what gameplay and validation need."""

    tileset: str
    source: str
    local_id: int
    semantic: int
    semantic_name: str
    tilewidth: int
    tileheight: int
    # Tile-local collision rectangles as (x, y, width, height, one_way).
    rects: tuple[tuple[float, float, float, float, bool], ...] = ()
    has_semantic: bool = False


def _tile_properties(tile: dict) -> dict:
    return {prop.get("name"): prop.get("value") for prop in tile.get("properties", [])}


def _tile_rects(tile: dict) -> tuple[tuple[float, float, float, float, bool], ...]:
    group = tile.get("objectgroup")
    if not group:
        return ()
    rects: list[tuple[float, float, float, float, bool]] = []
    for obj in group.get("objects", []):
        width = float(obj.get("width", 0.0))
        height = float(obj.get("height", 0.0))
        if width <= 0.0 or height <= 0.0:
            continue
        props = _tile_properties(obj)
        rects.append(
            (float(obj.get("x", 0.0)), float(obj.get("y", 0.0)), width, height, bool(props.get("one_way", False)))
        )
    return tuple(rects)


@dataclass
class TilesetEntry:
    firstgid: int
    source: str
    name: str
    tilecount: int
    tilewidth: int
    tileheight: int
    tiles: dict[int, TileDef]

    @property
    def lastgid(self) -> int:
        return self.firstgid + max(self.tilecount, 1) - 1


class TileIndex:
    """Resolves a map's global tile ids back to their tileset definitions."""

    def __init__(self, entries: list[TilesetEntry]) -> None:
        self.entries = sorted(entries, key=lambda entry: entry.firstgid)

    @classmethod
    def load(cls, map_path: Path, tilesets: list[dict]) -> "TileIndex":
        entries: list[TilesetEntry] = []
        for declared in tilesets:
            firstgid = int(declared.get("firstgid", 1))
            source = str(declared.get("source", ""))
            if source:
                tileset_path = (map_path.parent / source).resolve()
                tileset = read_json(tileset_path)
            else:
                tileset = declared
            tiles: dict[int, TileDef] = {}
            name = str(tileset.get("name", source or "embedded"))
            tilewidth = int(tileset.get("tilewidth", 0))
            tileheight = int(tileset.get("tileheight", 0))
            for tile in tileset.get("tiles", []):
                props = _tile_properties(tile)
                has_semantic = "data_semantic" in props
                tiles[int(tile.get("id", 0))] = TileDef(
                    tileset=name,
                    source=source,
                    local_id=int(tile.get("id", 0)),
                    semantic=int(props.get("data_semantic", 0) or 0),
                    semantic_name=str(props.get("data_semantic_name", "")),
                    tilewidth=int(tile.get("imagewidth", tilewidth) or tilewidth),
                    tileheight=int(tile.get("imageheight", tileheight) or tileheight),
                    rects=_tile_rects(tile),
                    has_semantic=has_semantic,
                )
            entries.append(
                TilesetEntry(
                    firstgid=firstgid,
                    source=source,
                    name=name,
                    tilecount=int(tileset.get("tilecount", 0)),
                    tilewidth=tilewidth,
                    tileheight=tileheight,
                    tiles=tiles,
                )
            )
        return cls(entries)

    def entry_for(self, gid: int) -> TilesetEntry | None:
        raw = gid & GID_MASK
        found: TilesetEntry | None = None
        for entry in self.entries:
            if raw >= entry.firstgid:
                found = entry
            else:
                break
        if found is None or raw > found.lastgid:
            return None
        return found

    def tile_for(self, gid: int) -> TileDef | None:
        entry = self.entry_for(gid)
        if entry is None:
            return None
        local_id = (gid & GID_MASK) - entry.firstgid
        tile = entry.tiles.get(local_id)
        if tile is not None:
            return tile
        # Plain atlas tile: no properties, no collision, no semantic value.
        return TileDef(
            tileset=entry.name,
            source=entry.source,
            local_id=local_id,
            semantic=SEMANTIC_EMPTY,
            semantic_name="",
            tilewidth=entry.tilewidth,
            tileheight=entry.tileheight,
        )

    def entry_by_source(self, suffix: str) -> TilesetEntry | None:
        for entry in self.entries:
            if entry.source.endswith(suffix):
                return entry
        return None

    def gid_for_semantic_name(self, semantic_name: str) -> int | None:
        for entry in self.entries:
            for local_id, tile in sorted(entry.tiles.items()):
                if tile.semantic_name == semantic_name:
                    return entry.firstgid + local_id
        return None


@dataclass
class LevelMap:
    path: Path
    data: dict
    index: TileIndex

    @classmethod
    def load(cls, path: Path) -> "LevelMap":
        data = read_json(path)
        if data.get("type") != "map":
            raise LevelKitError(f"{path}: not a Tiled map (type={data.get('type')!r})")
        return cls(path=path, data=data, index=TileIndex.load(path, data.get("tilesets", [])))

    @property
    def width(self) -> int:
        return int(self.data.get("width", 0))

    @property
    def height(self) -> int:
        return int(self.data.get("height", 0))

    @property
    def tilewidth(self) -> int:
        return int(self.data.get("tilewidth", 32))

    @property
    def tileheight(self) -> int:
        return int(self.data.get("tileheight", 32))

    def tile_layers(self) -> list[dict]:
        return [layer for layer in self.data.get("layers", []) if layer.get("type") == "tilelayer"]

    def layer(self, name: str) -> dict | None:
        for layer in self.data.get("layers", []):
            if layer.get("name") == name:
                return layer
        return None

    def gids(self, name: str) -> list[int]:
        layer = self.layer(name)
        if layer is None or layer.get("type") != "tilelayer":
            return [0] * (self.width * self.height)
        return [int(gid) for gid in layer.get("data", [])]

    def gid_at(self, name: str, x: int, y: int) -> int:
        if not (0 <= x < self.width and 0 <= y < self.height):
            return 0
        return self.gids(name)[y * self.width + x]

    def semantic_grid(self) -> list[list[int]]:
        """Semantic value per cell of the `Semantic` layer, as the engine reads it."""
        gids = self.gids(SEMANTIC_LAYER)
        grid: list[list[int]] = []
        for y in range(self.height):
            row: list[int] = []
            for x in range(self.width):
                tile = self.index.tile_for(gids[y * self.width + x]) if gids[y * self.width + x] else None
                row.append(tile.semantic if tile else SEMANTIC_EMPTY)
            grid.append(row)
        return grid

    def markers(self) -> dict[str, tuple[float, float]]:
        layer = self.layer(MARKER_LAYER)
        if layer is None:
            return {}
        return {
            str(obj.get("name", "")): (float(obj.get("x", 0.0)), float(obj.get("y", 0.0)))
            for obj in layer.get("objects", [])
            if obj.get("name")
        }


# --------------------------------------------------------------------------
# Collision geometry
# --------------------------------------------------------------------------


@dataclass(frozen=True)
class Rect:
    x0: float
    y0: float
    x1: float
    y1: float
    one_way: bool


def collision_rects(level: LevelMap, layers: tuple[str, ...] = (SEMANTIC_LAYER, OBSTACLE_LAYER)) -> list[Rect]:
    """World-space collision rectangles contributed by the collidable layers.

    A tile's own collision polygon is used, not the cell box, so tiles like the
    crouch gate - whose collider hangs far outside its cell - are measured the
    way the imported level actually behaves.
    """
    rects: list[Rect] = []
    tile_w = level.tilewidth
    tile_h = level.tileheight
    for layer_name in layers:
        gids = level.gids(layer_name)
        for cell_index, gid in enumerate(gids):
            if not gid:
                continue
            tile = level.index.tile_for(gid)
            if tile is None or not tile.rects:
                continue
            cell_x = (cell_index % level.width) * tile_w
            # Tiles taller than a cell hang upward from the cell's bottom edge.
            cell_y = (cell_index // level.width) * tile_h + (tile_h - tile.tileheight)
            flip_h = bool(gid & FLIP_HORIZONTAL)
            flip_v = bool(gid & FLIP_VERTICAL)
            for x, y, width, height, one_way in tile.rects:
                local_x = tile.tilewidth - (x + width) if flip_h else x
                local_y = tile.tileheight - (y + height) if flip_v else y
                rects.append(
                    Rect(
                        x0=cell_x + local_x,
                        y0=cell_y + local_y,
                        x1=cell_x + local_x + width,
                        y1=cell_y + local_y + height,
                        one_way=one_way,
                    )
                )
    return rects


class CollisionWorld:
    """Collision rectangles bucketed by tile column for fast box queries."""

    def __init__(self, rects: list[Rect], tile_width: int) -> None:
        self.tile_width = tile_width
        self.rects = rects
        self._columns: dict[int, list[Rect]] = {}
        for rect in rects:
            first = math.floor(rect.x0 / tile_width)
            last = math.floor((rect.x1 - 0.001) / tile_width)
            for column in range(first, last + 1):
                self._columns.setdefault(column, []).append(rect)

    def near(self, x0: float, x1: float) -> list[Rect]:
        first = math.floor(x0 / self.tile_width)
        last = math.floor(x1 / self.tile_width)
        seen: dict[int, Rect] = {}
        for column in range(first, last + 1):
            for rect in self._columns.get(column, ()):
                seen[id(rect)] = rect
        return list(seen.values())

    def blocked(self, x0: float, y0: float, x1: float, y1: float) -> bool:
        """True when a solid (never one-way) rectangle overlaps the box."""
        for rect in self.near(x0, x1):
            if rect.one_way:
                continue
            if rect.x0 < x1 and x0 < rect.x1 and rect.y0 < y1 and y0 < rect.y1:
                return True
        return False

    def floor_below(self, x0: float, x1: float, from_y: float, to_y: float) -> float | None:
        """Highest surface a box spanning [x0, x1] would land on falling to `to_y`."""
        best: float | None = None
        for rect in self.near(x0, x1):
            if rect.x0 >= x1 or x0 >= rect.x1:
                continue
            if rect.y0 < from_y - 0.001 or rect.y0 > to_y:
                continue
            if best is None or rect.y0 < best:
                best = rect.y0
        return best

    def headroom(self, x0: float, x1: float, floor_y: float) -> float:
        """Open height above a surface at `floor_y` across [x0, x1].

        Infinite when nothing overhangs the span, which is the common case; a
        crouch gate returns the gap between its collider and the floor.
        """
        clearance = math.inf
        for rect in self.near(x0, x1):
            if rect.one_way or rect.x0 >= x1 or x0 >= rect.x1:
                continue
            if rect.y1 <= floor_y + 0.001:
                clearance = min(clearance, floor_y - rect.y1)
        return clearance


# --------------------------------------------------------------------------
# Player physics, read from the engine source so the two cannot drift apart
# --------------------------------------------------------------------------


@dataclass
class PlayerPhysics:
    max_run_speed: float = 285.0
    air_acceleration: float = 1400.0
    gravity: float = 1550.0
    jump_velocity: float = -650.0
    min_jump_velocity: float = -360.0
    charge_power_curve: float = 0.62
    fall_gravity_multiplier: float = 1.20
    max_fall_speed: float = 850.0
    crouch_speed_multiplier: float = 0.45
    crouch_collision_height: float = 36.0
    body_width: float = 50.0
    body_height: float = 64.0
    death_y: float = 900.0

    @classmethod
    def load(cls, project_root: Path = PROJECT_ROOT) -> "PlayerPhysics":
        physics = cls()
        motor = project_root / "scripts" / "player" / "player_motor.gd"
        if motor.is_file():
            source = motor.read_text(encoding="utf-8")
            for name in (
                "max_run_speed",
                "air_acceleration",
                "gravity",
                "jump_velocity",
                "min_jump_velocity",
                "charge_power_curve",
                "fall_gravity_multiplier",
                "max_fall_speed",
                "crouch_speed_multiplier",
                "crouch_collision_height",
            ):
                match = re.search(rf"var\s+{name}\s*:\s*float\s*=\s*(-?[0-9.]+)", source)
                if match:
                    setattr(physics, name, float(match.group(1)))
        player = project_root / "scenes" / "player.tscn"
        if player.is_file():
            match = re.search(r"size\s*=\s*Vector2\((-?[0-9.]+),\s*(-?[0-9.]+)\)", player.read_text(encoding="utf-8"))
            if match:
                physics.body_width = float(match.group(1))
                physics.body_height = float(match.group(2))
        world = project_root / "scripts" / "world" / "static_world.gd"
        if world.is_file():
            match = re.search(r"var\s+death_y\s*:\s*float\s*=\s*(-?[0-9.]+)", world.read_text(encoding="utf-8"))
            if match:
                physics.death_y = float(match.group(1))
        return physics

    def launch_velocity(self, charge: float) -> float:
        ratio = pow(max(charge, 0.0), self.charge_power_curve)
        return self.min_jump_velocity + (self.jump_velocity - self.min_jump_velocity) * ratio


# --------------------------------------------------------------------------
# Route graph: ledges, clearance and reachability
# --------------------------------------------------------------------------


@dataclass
class Ledge:
    """A standable run of surface tiles, split wherever a body cannot pass."""

    index: int
    row: int
    x0: int
    x1: int
    value: int
    crouch_columns: tuple[int, ...] = ()

    @property
    def top_y(self) -> float:
        return float(self.row * 32)

    def left_px(self, tile_width: int) -> float:
        return float(self.x0 * tile_width)

    def right_px(self, tile_width: int) -> float:
        return float((self.x1 + 1) * tile_width)

    @property
    def width(self) -> int:
        return self.x1 - self.x0 + 1


def surface_runs(grid: list[list[int]]) -> list[tuple[int, int, int, int]]:
    """Top-exposed horizontal runs of standable tiles as (row, x0, x1, value).

    Mirrors `RunUnitStaticWorld._load_platforms_from_tilemap`, so what this tool
    calls a platform is exactly what the running game calls a platform.
    """
    runs: list[tuple[int, int, int, int]] = []
    height = len(grid)
    width = len(grid[0]) if height else 0
    for y in range(height):
        x = 0
        while x < width:
            value = grid[y][x]
            above = grid[y - 1][x] if y > 0 else SEMANTIC_EMPTY
            if value not in STANDABLE or above in STANDABLE:
                x += 1
                continue
            start = x
            while (
                x + 1 < width
                and grid[y][x + 1] == value
                and (grid[y - 1][x + 1] if y > 0 else SEMANTIC_EMPTY) not in STANDABLE
            ):
                x += 1
            runs.append((y, start, x, value))
            x += 1
    return runs


def build_ledges(level: LevelMap, world: CollisionWorld, physics: PlayerPhysics) -> list[Ledge]:
    """Surface runs split at columns too low for even a crouched body to pass."""
    tile_w = level.tilewidth
    ledges: list[Ledge] = []
    for row, x0, x1, value in surface_runs(level.semantic_grid()):
        floor_y = float(row * level.tileheight)
        segment_start: int | None = None
        crouch: list[int] = []
        for column in range(x0, x1 + 1):
            clearance = world.headroom(column * tile_w + 0.5, (column + 1) * tile_w - 0.5, floor_y)
            passable = clearance >= physics.crouch_collision_height
            if passable:
                if segment_start is None:
                    segment_start = column
                if clearance < physics.body_height:
                    crouch.append(column)
                continue
            if segment_start is not None:
                ledges.append(Ledge(len(ledges), row, segment_start, column - 1, value, tuple(crouch)))
                segment_start = None
                crouch = []
        if segment_start is not None:
            ledges.append(Ledge(len(ledges), row, segment_start, x1, value, tuple(crouch)))
    for position, ledge in enumerate(ledges):
        ledge.index = position
    return ledges


class RouteGraph:
    """Which ledges a player can actually reach from which, under the real motor."""

    STEP = 1.0 / 60.0
    CHARGES = (1.0, 0.75, 0.5, 0.25, 0.0)

    def __init__(self, level: LevelMap, world: CollisionWorld, physics: PlayerPhysics, ledges: list[Ledge]) -> None:
        self.level = level
        self.world = world
        self.physics = physics
        self.ledges = ledges
        self.bounds_left = -float(level.tilewidth)
        self.bounds_right = float((level.width + 1) * level.tilewidth)
        self._by_row: dict[int, list[Ledge]] = {}
        for ledge in ledges:
            self._by_row.setdefault(ledge.row, []).append(ledge)

    def ledge_at(self, foot_x: float, surface_y: float) -> Ledge | None:
        row = int(round(surface_y / self.level.tileheight))
        half = self.physics.body_width / 2.0
        for ledge in self._by_row.get(row, ()):
            if ledge.left_px(self.level.tilewidth) < foot_x + half and foot_x - half < ledge.right_px(
                self.level.tilewidth
            ):
                return ledge
        return None

    def simulate(
        self,
        start_x: float,
        floor_y: float,
        direction: int,
        charge: float | None,
        max_time: float = 3.0,
    ) -> dict | None:
        """Integrate one airborne arc the way `RunUnitPlayerMotor` would.

        Returns the landing, or None when the arc leaves the map or falls past
        the death plane. Horizontal speed is the motor's full run speed: the
        check answers "is this jump possible", not "is it comfortable".
        """
        physics = self.physics
        half = physics.body_width / 2.0
        height = physics.body_height
        x = start_x
        feet = floor_y
        target_x = direction * physics.max_run_speed
        velocity_x = target_x
        velocity_y = 0.0 if charge is None else physics.launch_velocity(charge)
        elapsed = 0.0
        while elapsed < max_time:
            elapsed += self.STEP
            pull = physics.gravity * (physics.fall_gravity_multiplier if velocity_y > 0.0 else 1.0)
            velocity_y = min(velocity_y + pull * self.STEP, physics.max_fall_speed)
            # Airborne steering keeps pushing toward the run speed, so brushing a
            # wall costs the frame's movement but not the rest of the arc.
            step = physics.air_acceleration * self.STEP
            velocity_x = max(velocity_x - step, target_x) if velocity_x > target_x else min(velocity_x + step, target_x)

            next_x = x + velocity_x * self.STEP
            if velocity_x and self.world.blocked(next_x - half, feet - height, next_x + half, feet - 0.001):
                velocity_x = 0.0
            else:
                x = next_x

            next_feet = feet + velocity_y * self.STEP
            if velocity_y > 0.0:
                landing = self.world.floor_below(x - half, x + half, feet, next_feet)
                if landing is not None:
                    return {"x": x, "surface_y": landing, "time": elapsed}
                feet = next_feet
            else:
                if self.world.blocked(x - half, next_feet - height, x + half, next_feet - 0.001):
                    velocity_y = 0.0
                else:
                    feet = next_feet

            if feet > physics.death_y or x < self.bounds_left or x > self.bounds_right:
                return None
        return None

    def launches(self, ledge: Ledge) -> list[tuple[float, int, float | None]]:
        """Every (start_x, direction, charge) worth trying from one ledge."""
        tile_w = self.level.tilewidth
        half = self.physics.body_width / 2.0
        left = ledge.left_px(tile_w)
        right = ledge.right_px(tile_w)
        middle = (left + right) / 2.0
        points: list[tuple[float, int]] = [
            (right + half - 1.0, 1),
            (left - half + 1.0, -1),
            (middle, 1),
            (middle, -1),
            (middle, 0),
        ]
        attempts: list[tuple[float, int, float | None]] = []
        for start_x, direction in points:
            for charge in self.CHARGES:
                attempts.append((start_x, direction, charge))
        # Running off an edge without jumping: the body is already clear of the lip.
        attempts.append((right + half + 0.5, 1, None))
        attempts.append((left - half - 0.5, -1, None))
        return attempts

    def edges(self) -> dict[int, list[dict]]:
        """Reachable-neighbour map, keyed by source ledge index."""
        result: dict[int, list[dict]] = {ledge.index: [] for ledge in self.ledges}
        for ledge in self.ledges:
            best: dict[int, dict] = {}
            for start_x, direction, charge in self.launches(ledge):
                landing = self.simulate(start_x, ledge.top_y, direction, charge)
                if landing is None:
                    continue
                target = self.ledge_at(landing["x"], landing["surface_y"])
                if target is None or target.index == ledge.index:
                    continue
                move = {
                    "to": target.index,
                    "charge": charge,
                    "direction": direction,
                    "landing_x": landing["x"],
                    "time": landing["time"],
                }
                previous = best.get(target.index)
                if previous is None or (charge or 0.0) < (previous["charge"] or 0.0):
                    best[target.index] = move
            result[ledge.index] = [best[key] for key in sorted(best)]
        return result

    def drop_onto(self, world_x: float, world_y: float) -> Ledge | None:
        """Which ledge a body released at a world position comes to rest on."""
        feet = world_y + self.physics.body_height / 2.0
        landing = self.simulate(world_x, feet, 0, None, max_time=6.0)
        if landing is None:
            return None
        return self.ledge_at(landing["x"], landing["surface_y"])

    def reachable_from(self, start: int, edges: dict[int, list[dict]]) -> dict[int, list[dict]]:
        """Breadth-first search returning the move path to every reachable ledge."""
        paths: dict[int, list[dict]] = {start: []}
        queue = [start]
        while queue:
            current = queue.pop(0)
            for move in edges.get(current, ()):
                target = int(move["to"])
                if target in paths:
                    continue
                paths[target] = paths[current] + [dict(move, **{"from": current})]
                queue.append(target)
        return paths


# --------------------------------------------------------------------------
# Sketches: a hand-editable text view of a route
# --------------------------------------------------------------------------


def _glyph_tables(index: TileIndex) -> tuple[dict[int, str], dict[int, str]]:
    """Map gids to sketch glyphs for the semantic and obstacle layers."""
    semantic: dict[int, str] = {}
    obstacles: dict[int, str] = {}
    for entry in index.entries:
        for local_id, tile in entry.tiles.items():
            gid = entry.firstgid + local_id
            if tile.semantic_name in SEMANTIC_GLYPHS:
                semantic.setdefault(gid, SEMANTIC_GLYPHS[tile.semantic_name])
            if tile.semantic_name in OBSTACLE_GLYPHS:
                obstacles.setdefault(gid, OBSTACLE_GLYPHS[tile.semantic_name])
    return semantic, obstacles


def _relative_to_project(path: Path) -> str:
    try:
        return path.resolve().relative_to(PROJECT_ROOT).as_posix()
    except ValueError:
        return path.as_posix()


def sketch_text(level: LevelMap) -> str:
    """Render a level's gameplay layers as an editable text grid."""
    semantic_glyphs, obstacle_glyphs = _glyph_tables(level.index)
    semantic = level.gids(SEMANTIC_LAYER)
    obstacles = level.gids(OBSTACLE_LAYER)
    width, height = level.width, level.height
    grid = [[EMPTY_GLYPH] * width for _ in range(height)]
    for cell, gid in enumerate(semantic):
        if gid:
            grid[cell // width][cell % width] = semantic_glyphs.get(gid & GID_MASK, "?")
    for cell, gid in enumerate(obstacles):
        if gid:
            grid[cell // width][cell % width] = obstacle_glyphs.get(gid & GID_MASK, "O")

    markers = level.markers()
    for name, (x, y) in sorted(markers.items()):
        glyph = MARKER_GLYPHS.get(name)
        if glyph is None:
            continue
        column = int(x // level.tilewidth)
        row = int(y // level.tileheight)
        # A marker over a painted cell keeps the tile visible; its exact position
        # still round-trips through the @marker directive below.
        if 0 <= column < width and 0 <= row < height and grid[row][column] == EMPTY_GLYPH:
            grid[row][column] = glyph

    lines = [
        "// RUN//UNIT level sketch - %s" % _relative_to_project(level.path),
        "// Edit the grid, then rebuild the map:",
        "//   python tools/level_kit.py build <this file> --out <level>.tmj",
        "//   python tools/level_kit.py check <level>.tmj",
        "// Legend: %s empty  %s solid  %s one_way  %s hazard  %s conveyor  %s foreground"
        % (
            EMPTY_GLYPH,
            SEMANTIC_GLYPHS["solid"],
            SEMANTIC_GLYPHS["one_way"],
            SEMANTIC_GLYPHS["hazard"],
            SEMANTIC_GLYPHS["conveyor"],
            SEMANTIC_GLYPHS["foreground"],
        ),
        "//         %s gate_ceiling (Obstacles layer)  %s Spawn  %s Goal"
        % (OBSTACLE_GLYPHS["gate_ceiling"], MARKER_GLYPHS[SPAWN_MARKER], MARKER_GLYPHS[GOAL_MARKER]),
        "@size %d %d" % (width, height),
        "@tile %d %d" % (level.tilewidth, level.tileheight),
        "@template %s" % _relative_to_project(level.path),
    ]
    for name in sorted(markers):
        x, y = markers[name]
        lines.append("@marker %s %g %g" % (name, x, y))
    lines.append("//     " + "".join(str((column // 10) % 10) if column % 10 == 0 else " " for column in range(width)))
    lines.append("//     " + "".join(str(column % 10) for column in range(width)))
    for row in range(height):
        lines.append("%3d | %s" % (row, "".join(grid[row])))
    return "\n".join(lines) + "\n"


@dataclass
class Sketch:
    width: int
    height: int
    tilewidth: int
    tileheight: int
    rows: list[str]
    template: str | None = None
    markers: dict[str, tuple[float, float]] = field(default_factory=dict)
    marker_cells: dict[str, tuple[int, int]] = field(default_factory=dict)


def parse_sketch(text: str) -> Sketch:
    """Read a sketch file back into a structured grid."""
    width = height = 0
    tilewidth = tileheight = 32
    template: str | None = None
    markers: dict[str, tuple[float, float]] = {}
    rows: list[str] = []
    for number, raw in enumerate(text.splitlines(), start=1):
        line = raw.rstrip()
        if not line or line.lstrip().startswith("//"):
            continue
        if line.startswith("@"):
            parts = line.split()
            directive = parts[0]
            try:
                if directive == "@size":
                    width, height = int(parts[1]), int(parts[2])
                elif directive == "@tile":
                    tilewidth, tileheight = int(parts[1]), int(parts[2])
                elif directive == "@template":
                    template = parts[1]
                elif directive == "@marker":
                    markers[parts[1]] = (float(parts[2]), float(parts[3]))
                else:
                    raise LevelKitError("line %d: unknown directive %s" % (number, directive))
            except (IndexError, ValueError) as error:
                raise LevelKitError("line %d: malformed %s (%s)" % (number, directive, error)) from error
            continue
        rows.append(line.split("|", 1)[1].strip() if "|" in line else line.strip())

    if not rows:
        raise LevelKitError("sketch contains no grid rows")
    if width <= 0:
        width = max(len(row) for row in rows)
    if height <= 0:
        height = len(rows)
    if len(rows) != height:
        raise LevelKitError("sketch declares %d rows but contains %d" % (height, len(rows)))

    marker_cells: dict[str, tuple[int, int]] = {}
    normalised: list[str] = []
    for row_index, row in enumerate(rows):
        if len(row) > width:
            raise LevelKitError("row %d is %d cells wide but the sketch declares %d" % (row_index, len(row), width))
        padded = row.ljust(width, EMPTY_GLYPH)
        cleaned = []
        for column, glyph in enumerate(padded):
            marker = next((name for name, mark in MARKER_GLYPHS.items() if mark == glyph), None)
            if marker is not None:
                if marker in marker_cells:
                    raise LevelKitError("sketch places more than one %s marker" % marker)
                marker_cells[marker] = (column, row_index)
                cleaned.append(EMPTY_GLYPH)
            else:
                cleaned.append(glyph)
        normalised.append("".join(cleaned))

    known = set(SEMANTIC_GLYPHS.values()) | set(OBSTACLE_GLYPHS.values()) | {EMPTY_GLYPH}
    for row_index, row in enumerate(normalised):
        for column, glyph in enumerate(row):
            if glyph not in known:
                raise LevelKitError("row %d column %d: unknown glyph %r" % (row_index, column, glyph))

    return Sketch(
        width=width,
        height=height,
        tilewidth=tilewidth,
        tileheight=tileheight,
        rows=normalised,
        template=template,
        markers=markers,
        marker_cells=marker_cells,
    )


# --------------------------------------------------------------------------
# Building a Tiled map from a sketch
# --------------------------------------------------------------------------


DEFAULT_SEMANTIC_TILESET = PROJECT_ROOT / "assets" / "tiled" / "semantic" / "semantic_layer.tsj"


def _resize(data: list[int], old_width: int, old_height: int, width: int, height: int) -> list[int]:
    """Re-fit tile data to new map bounds, keeping the overlapping top-left area."""
    if old_width == width and old_height == height:
        return list(data)
    resized = [0] * (width * height)
    for y in range(min(old_height, height)):
        for x in range(min(old_width, width)):
            resized[y * width + x] = data[y * old_width + x]
    return resized


def _tile_layer(name: str, layer_id: int, width: int, height: int, data: list[int], template: dict | None) -> dict:
    return {
        "data": data,
        "height": height,
        "id": layer_id,
        "name": name,
        "opacity": float(template.get("opacity", 1)) if template else 1,
        "type": "tilelayer",
        "visible": bool(template.get("visible", True)) if template else True,
        "width": width,
        "x": 0,
        "y": 0,
    }


def _round_trip_number(value: float) -> float | int:
    """Keep whole pixel coordinates as ints, the way Tiled writes them."""
    return int(value) if float(value).is_integer() else value


def _marker_object(object_id: int, name: str, x: float, y: float) -> dict:
    return {
        "id": object_id,
        "name": name,
        "type": "",
        "point": True,
        "x": _round_trip_number(x),
        "y": _round_trip_number(y),
        "width": 0,
        "height": 0,
        "rotation": 0,
        "visible": True,
    }


def build_map(sketch: Sketch, out_path: Path, template: LevelMap | None) -> dict:
    """Assemble a Tiled map from a sketch, reusing a template's art and tilesets.

    Only the gameplay layers are authored in text; every decorative layer the
    template carries is preserved (re-fitted if the sketch resized the map), so
    iterating on route geometry never costs the level its artwork.
    """
    width, height = sketch.width, sketch.height
    if template is not None:
        # Tileset paths are relative to the map that names them, so a level built
        # into a different directory has to have them re-pointed.
        tilesets = []
        for declared in json.loads(json.dumps(template.data.get("tilesets", []))):
            source = str(declared.get("source", ""))
            if source:
                declared["source"] = _relative_path(out_path.parent, template.path.parent / source)
            tilesets.append(declared)
        index = template.index
        base = template.data
    else:
        source = Path(_relative_path(out_path.parent, DEFAULT_SEMANTIC_TILESET))
        tilesets = [{"firstgid": 1, "source": source.as_posix()}]
        index = TileIndex.load(out_path, tilesets)
        base = {}

    glyph_to_gid: dict[str, int] = {}
    for semantic_name, glyph in list(SEMANTIC_GLYPHS.items()) + list(OBSTACLE_GLYPHS.items()):
        gid = index.gid_for_semantic_name(semantic_name)
        if gid is not None:
            glyph_to_gid[glyph] = gid
    obstacle_glyphs = set(OBSTACLE_GLYPHS.values())

    semantic_data = [0] * (width * height)
    obstacle_data = [0] * (width * height)
    for y, row in enumerate(sketch.rows):
        for x, glyph in enumerate(row):
            if glyph == EMPTY_GLYPH:
                continue
            gid = glyph_to_gid.get(glyph)
            if gid is None:
                raise LevelKitError("glyph %r has no tile in the semantic tileset" % glyph)
            if glyph in obstacle_glyphs:
                obstacle_data[y * width + x] = gid
            else:
                semantic_data[y * width + x] = gid

    template_layers = {layer.get("name"): layer for layer in base.get("layers", [])} if base else {}
    ordered_names: list[str] = [str(layer.get("name")) for layer in base.get("layers", [])] if base else []
    for name in LAYER_ORDER:
        if name not in ordered_names:
            ordered_names.append(name)

    next_layer_id = max([int(layer.get("id", 0)) for layer in base.get("layers", [])] + [0]) if base else 0
    layers: list[dict] = []
    for name in ordered_names:
        existing = template_layers.get(name)
        if name == MARKER_LAYER or (existing is not None and existing.get("type") == "objectgroup"):
            continue
        if name == SEMANTIC_LAYER:
            data = semantic_data
        elif name == OBSTACLE_LAYER:
            data = obstacle_data
        elif existing is not None:
            data = _resize(
                [int(gid) for gid in existing.get("data", [])],
                int(existing.get("width", width)),
                int(existing.get("height", height)),
                width,
                height,
            )
        else:
            data = [0] * (width * height)
        if existing is not None:
            layer_id = int(existing.get("id", 0))
        else:
            next_layer_id += 1
            layer_id = next_layer_id
        layers.append(_tile_layer(name, layer_id, width, height, data, existing))

    marker_template = template_layers.get(MARKER_LAYER)
    kept: list[dict] = []
    next_object_id = 0
    if marker_template is not None:
        for obj in marker_template.get("objects", []):
            next_object_id = max(next_object_id, int(obj.get("id", 0)))
            if str(obj.get("name", "")) not in MARKER_GLYPHS:
                kept.append(json.loads(json.dumps(obj)))
    previous = {str(obj.get("name", "")): obj for obj in (marker_template or {}).get("objects", [])}
    marker_objects: list[dict] = []
    for name in MARKER_GLYPHS:
        cell = sketch.marker_cells.get(name)
        declared = sketch.markers.get(name)
        if cell is None:
            if declared is None:
                continue
            # Drawn over a painted cell, so the grid carries no glyph for it.
            x, y = declared
        else:
            column, row = cell
            if declared is not None and (
                int(declared[0] // sketch.tilewidth),
                int(declared[1] // sketch.tileheight),
            ) == cell:
                x, y = declared
            else:
                x = column * sketch.tilewidth + sketch.tilewidth / 2.0
                y = row * sketch.tileheight + sketch.tileheight / 2.0
        source_object = previous.get(name)
        if source_object is not None:
            object_id = int(source_object.get("id", 0))
        else:
            next_object_id += 1
            object_id = next_object_id
        marker_objects.append(_marker_object(object_id, name, x, y))
    marker_objects.sort(key=lambda obj: int(obj["id"]))

    if marker_template is not None:
        marker_layer_id = int(marker_template.get("id", 0))
    else:
        next_layer_id += 1
        marker_layer_id = next_layer_id
    layers.append(
        {
            "draworder": (marker_template or {}).get("draworder", "index"),
            "id": marker_layer_id,
            "name": MARKER_LAYER,
            "opacity": (marker_template or {}).get("opacity", 1),
            "type": "objectgroup",
            "visible": (marker_template or {}).get("visible", True),
            "x": 0,
            "y": 0,
            "objects": kept + marker_objects,
        }
    )

    next_layer_id = max([int(layer.get("id", 0)) for layer in layers] + [0])
    next_object_id = max([int(obj.get("id", 0)) for obj in kept + marker_objects] + [0])
    return {
        "compressionlevel": base.get("compressionlevel", -1),
        "height": height,
        "infinite": False,
        "layers": layers,
        "nextlayerid": next_layer_id + 1,
        "nextobjectid": next_object_id + 1,
        "orientation": "orthogonal",
        "renderorder": "right-down",
        "tiledversion": base.get("tiledversion", "1.11"),
        "tileheight": sketch.tileheight,
        "tilesets": tilesets,
        "tilewidth": sketch.tilewidth,
        "type": "map",
        "version": base.get("version", "1.10"),
        "width": width,
    }


def _relative_path(start: Path, target: Path) -> str:
    """POSIX-style relative path from a directory to a file, with `..` allowed."""
    start_parts = start.resolve().parts
    target_parts = target.resolve().parts
    common = 0
    while common < min(len(start_parts), len(target_parts)) and start_parts[common] == target_parts[common]:
        common += 1
    return "/".join([".."] * (len(start_parts) - common) + list(target_parts[common:]))


# --------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------


COMPLETION_TRIGGER_SIZE = (64.0, 128.0)


@dataclass
class Report:
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)
    summary: dict = field(default_factory=dict)

    @property
    def ok(self) -> bool:
        return not self.errors


def _check_structure(level: LevelMap, report: Report) -> None:
    """Contract checks: what `static_world.gd` and the YATI import require."""
    if level.data.get("infinite"):
        report.errors.append("map is infinite; the importer and route indexing need a fixed-size map")
    if level.tilewidth != 32 or level.tileheight != 32:
        report.errors.append(
            "tile size is %dx%d; RunUnitStaticWorld.TILE_SIZE is 32" % (level.tilewidth, level.tileheight)
        )
    if level.layer(SEMANTIC_LAYER) is None:
        report.errors.append("no '%s' tile layer; the route would be empty" % SEMANTIC_LAYER)
    if level.layer(OBSTACLE_LAYER) is None:
        report.warnings.append("no '%s' layer; obstacle tiles have nowhere to live" % OBSTACLE_LAYER)
    if level.layer(MARKER_LAYER) is None:
        report.errors.append("no '%s' object layer; Spawn and Goal come from it" % MARKER_LAYER)

    for layer in level.tile_layers():
        name = str(layer.get("name"))
        if int(layer.get("width", 0)) != level.width or int(layer.get("height", 0)) != level.height:
            report.errors.append("layer '%s' is not the map's size" % name)
        for cell, gid in enumerate(layer.get("data", [])):
            if not gid:
                continue
            tile = level.index.tile_for(int(gid))
            position = "x=%d y=%d" % (cell % level.width, cell // level.width)
            if tile is None:
                report.errors.append("layer '%s' %s: tile id %d is outside every declared tileset" % (name, position, gid))
                continue
            if name == SEMANTIC_LAYER and not tile.has_semantic:
                report.errors.append(
                    "layer '%s' %s: '%s' tile has no data_semantic property, so it is silently non-collidable"
                    % (name, position, tile.tileset)
                )
            if name == SEMANTIC_LAYER and tile.semantic not in CONTRACT_VALUES:
                report.errors.append(
                    "layer '%s' %s: semantic value %d is outside the tile contract" % (name, position, tile.semantic)
                )
            if name not in (SEMANTIC_LAYER, OBSTACLE_LAYER) and tile.rects:
                report.warnings.append(
                    "layer '%s' %s: decoration tile carries collision; only %s may create collision"
                    % (name, position, SEMANTIC_LAYER)
                )


def _describe_move(move: dict, ledges: list[Ledge], tile_width: int) -> str:
    source = ledges[int(move["from"])]
    target = ledges[int(move["to"])]
    gap = max(target.left_px(tile_width) - source.right_px(tile_width), source.left_px(tile_width) - target.right_px(tile_width))
    gap_tiles = max(gap, 0.0) / tile_width
    drop = (target.row - source.row)
    charge = move["charge"]
    action = "run off" if charge is None else ("tap jump" if charge <= 0.25 else "charge %d%%" % round(charge * 100))
    return "ledge %d -> %d (%s, gap %.1f tiles, %+d rows)" % (source.index + 1, target.index + 1, action, gap_tiles, drop)


def check_level(level: LevelMap, physics: PlayerPhysics | None = None, margin: float = 0.1) -> Report:
    """Validate a route map against the engine contract and the player motor.

    `margin` is how much run speed a jump must be able to spare before the route
    counts as comfortable; moves that only work at a perfect full-speed takeoff
    are reported so a designer can widen them before a player finds them.
    """
    physics = physics or PlayerPhysics.load()
    report = Report()
    _check_structure(level, report)
    if report.errors:
        report.summary = {"checked": False}
        return report

    world = CollisionWorld(collision_rects(level), level.tilewidth)
    ledges = build_ledges(level, world, physics)
    graph = RouteGraph(level, world, physics, ledges)
    report.summary = {
        "checked": True,
        "size": [level.width, level.height],
        "ledges": len(ledges),
        "tilesets": len(level.index.entries),
    }
    if not ledges:
        report.errors.append("no standable surface in '%s'; RunUnitStaticWorld would report an invalid route" % SEMANTIC_LAYER)
        return report

    for ledge in ledges:
        if ledge.top_y > physics.death_y:
            report.warnings.append(
                "ledge %d (row %d) sits below the death plane at y=%g" % (ledge.index + 1, ledge.row, physics.death_y)
            )
        if ledge.crouch_columns:
            report.notes.append(
                "ledge %d needs a crouch across columns %d-%d"
                % (ledge.index + 1, min(ledge.crouch_columns), max(ledge.crouch_columns))
            )

    markers = level.markers()
    spawn = markers.get(SPAWN_MARKER)
    goal = markers.get(GOAL_MARKER)
    if spawn is None:
        report.errors.append("no '%s' point in '%s'; runs would start at the fallback position" % (SPAWN_MARKER, MARKER_LAYER))
    if goal is None:
        report.warnings.append("no '%s' point in '%s'; the route can never be completed" % (GOAL_MARKER, MARKER_LAYER))
    if spawn is None:
        return report

    if world.blocked(spawn[0] - physics.body_width / 2, spawn[1] - physics.body_height / 2, spawn[0] + physics.body_width / 2, spawn[1] + physics.body_height / 2):
        report.errors.append("%s at (%g, %g) starts inside collision" % (SPAWN_MARKER, spawn[0], spawn[1]))
    spawn_ledge = graph.drop_onto(*spawn)
    if spawn_ledge is None:
        report.errors.append("%s at (%g, %g) falls past the death plane without landing" % (SPAWN_MARKER, spawn[0], spawn[1]))
        return report
    report.summary["spawn_ledge"] = spawn_ledge.index + 1

    edges = graph.edges()
    paths = graph.reachable_from(spawn_ledge.index, edges)
    report.summary["reachable_ledges"] = len(paths)
    stranded = [ledge for ledge in ledges if ledge.index not in paths and ledge.width > 1]
    for ledge in stranded:
        report.warnings.append(
            "ledge %d (row %d, columns %d-%d) cannot be reached from %s"
            % (ledge.index + 1, ledge.row, ledge.x0, ledge.x1, SPAWN_MARKER)
        )

    if goal is None:
        return report
    half = physics.body_width / 2.0
    trigger_x0 = goal[0] - COMPLETION_TRIGGER_SIZE[0] / 2.0
    trigger_x1 = goal[0] + COMPLETION_TRIGGER_SIZE[0] / 2.0
    trigger_y0 = goal[1] - COMPLETION_TRIGGER_SIZE[1] / 2.0
    trigger_y1 = goal[1] + COMPLETION_TRIGGER_SIZE[1] / 2.0
    finishers = [
        ledge
        for ledge in ledges
        if ledge.left_px(level.tilewidth) - half < trigger_x1
        and trigger_x0 < ledge.right_px(level.tilewidth) + half
        and ledge.top_y - physics.body_height < trigger_y1
        and trigger_y0 < ledge.top_y
    ]
    if not finishers:
        report.errors.append(
            "%s at (%g, %g) has no standable surface inside its completion trigger" % (GOAL_MARKER, goal[0], goal[1])
        )
        return report

    reached = [ledge for ledge in finishers if ledge.index in paths]
    if not reached:
        report.errors.append(
            "%s is unreachable from %s: no jump the motor can perform connects them" % (GOAL_MARKER, SPAWN_MARKER)
        )
        blocked_at = max((ledge for ledge in ledges if ledge.index in paths), key=lambda ledge: ledge.x1, default=None)
        if blocked_at is not None:
            report.errors.append(
                "  the reachable route stops at ledge %d (row %d, columns %d-%d)"
                % (blocked_at.index + 1, blocked_at.row, blocked_at.x0, blocked_at.x1)
            )
        return report

    finish_indices = {ledge.index for ledge in finishers}
    for ledge in ledges:
        if ledge.index not in paths or ledge.index in finish_indices:
            continue
        onward = graph.reachable_from(ledge.index, edges)
        if finish_indices & set(onward):
            continue
        report.warnings.append(
            "soft-lock: ledge %d (row %d, columns %d-%d) can be reached but the %s cannot be reached from it"
            % (ledge.index + 1, ledge.row, ledge.x0, ledge.x1, GOAL_MARKER)
        )

    best = min(reached, key=lambda ledge: len(paths[ledge.index]))
    route = paths[best.index]
    report.summary["route_moves"] = len(route)
    report.summary["goal_ledge"] = best.index + 1
    report.notes.append(
        "route: %s -> %s in %d move(s)" % (SPAWN_MARKER, GOAL_MARKER, len(route))
        + ("" if not route else ": " + "; ".join(_describe_move(move, ledges, level.tilewidth) for move in route))
    )
    for move in route:
        if move["charge"] is not None and move["charge"] >= 1.0:
            report.warnings.append(
                "%s needs a full-charge jump, leaving the player no margin" % _describe_move(move, ledges, level.tilewidth)
            )

    if margin > 0.0:
        # Re-run the route with a slightly slower player. A jump that survives
        # only at a perfect takeoff will not survive contact with a human.
        careful = PlayerPhysics(**dict(physics.__dict__))
        careful.max_run_speed = physics.max_run_speed * (1.0 - margin)
        forgiving = RouteGraph(level, world, careful, ledges).edges()
        for move in route:
            source = int(move["from"])
            if not any(int(other["to"]) == int(move["to"]) for other in forgiving.get(source, ())):
                report.warnings.append(
                    "tight: %s only clears at full run speed"
                    % _describe_move(move, ledges, level.tilewidth)
                )
    return report


# --------------------------------------------------------------------------
# Decoration passes
# --------------------------------------------------------------------------


def deck_layer_data(level: LevelMap, firstgid: int) -> list[int]:
    """Deck trim for every surface run: capped top row, then two body rows."""
    grid = level.semantic_grid()
    data = [0] * (level.width * level.height)
    for row, x0, x1, _value in surface_runs(grid):
        for column in range(x0, x1 + 1):
            if x1 == x0:
                cap = DECK_CAP_LEFT
            elif column == x0:
                cap = DECK_CAP_LEFT
            elif column == x1:
                cap = DECK_CAP_RIGHT
            else:
                cap = DECK_CAP_MID
            data[row * level.width + column] = firstgid + cap
            for depth, body in enumerate(DECK_BODY_ROWS, start=1):
                y = row + depth
                if y >= level.height or grid[y][column] not in STANDABLE:
                    break
                data[y * level.width + column] = firstgid + body[(column - x0) % len(body)]
    return data


def shell_layer_data(level: LevelMap, firstgid: int) -> list[int]:
    """Repeat the macro bulkhead backdrop across the authored part of the map."""
    grid = level.semantic_grid()
    used = [(y, x) for y in range(level.height) for x in range(level.width) if grid[y][x] in STANDABLE]
    if not used:
        return [0] * (level.width * level.height)
    top_row = min(cell[0] for cell in used)
    right_column = max(cell[1] for cell in used)
    data = [0] * (level.width * level.height)
    lower = top_row + 1
    upper = lower - SHELL_ROWS
    for column in range(0, right_column + 1, SHELL_COLUMNS):
        if 0 <= lower < level.height:
            data[lower * level.width + column] = firstgid + SHELL_TILE
        if 0 <= upper < level.height:
            data[upper * level.width + column] = (firstgid + SHELL_TILE) | FLIP_VERTICAL
    return data


def autoart(level: LevelMap) -> list[str]:
    """Rebuild the decorative deck and shell layers from the semantic geometry."""
    changed: list[str] = []
    passes = (
        (DECK_LAYER, DECK_TILESET, deck_layer_data),
        (SHELL_LAYER, SHELL_TILESET, shell_layer_data),
    )
    for layer_name, tileset_source, builder in passes:
        entry = level.index.entry_by_source(tileset_source)
        if entry is None:
            continue
        layer = level.layer(layer_name)
        if layer is None or layer.get("type") != "tilelayer":
            continue
        data = builder(level, entry.firstgid)
        if [int(gid) for gid in layer.get("data", [])] != data:
            layer["data"] = data
            changed.append(layer_name)
    return changed


# --------------------------------------------------------------------------
# Command line
# --------------------------------------------------------------------------


def _resolve(value: str) -> Path:
    path = Path(value)
    return path if path.is_absolute() else (PROJECT_ROOT / path if not path.exists() else path)


def command_sketch(args: argparse.Namespace) -> int:
    level = LevelMap.load(_resolve(args.level))
    text = sketch_text(level)
    if args.out:
        out = _resolve(args.out)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(text, encoding="utf-8", newline="\n")
        print("wrote %s (%dx%d cells)" % (_relative_to_project(out), level.width, level.height))
    else:
        sys.stdout.write(text)
    return 0


def blank_sketch(width: int, height: int, template: str | None) -> str:
    """A starting sketch: one floor, a Spawn on it and a Goal at the far end."""
    floor_row = max(height // 2, 2)
    spawn_column = 4
    goal_column = max(width - 4, spawn_column + 1)
    grid = [[EMPTY_GLYPH] * width for _ in range(height)]
    for row in range(floor_row, height):
        for column in range(width):
            grid[row][column] = SEMANTIC_GLYPHS["solid"]
    grid[floor_row - 2][spawn_column] = MARKER_GLYPHS[SPAWN_MARKER]
    grid[floor_row - 2][goal_column] = MARKER_GLYPHS[GOAL_MARKER]
    lines = [
        "// RUN//UNIT level sketch",
        "// Paint the route, then build and validate it:",
        "//   python tools/level_kit.py build <this file> --out <level>.tmj --check",
        "// Legend: %s empty  %s solid  %s one_way  %s hazard  %s conveyor  %s foreground"
        % (
            EMPTY_GLYPH,
            SEMANTIC_GLYPHS["solid"],
            SEMANTIC_GLYPHS["one_way"],
            SEMANTIC_GLYPHS["hazard"],
            SEMANTIC_GLYPHS["conveyor"],
            SEMANTIC_GLYPHS["foreground"],
        ),
        "//         %s gate_ceiling (Obstacles layer)  %s Spawn  %s Goal"
        % (OBSTACLE_GLYPHS["gate_ceiling"], MARKER_GLYPHS[SPAWN_MARKER], MARKER_GLYPHS[GOAL_MARKER]),
        "@size %d %d" % (width, height),
        "@tile 32 32",
    ]
    if template:
        lines.append("@template %s" % template)
    lines.append("//     " + "".join(str((column // 10) % 10) if column % 10 == 0 else " " for column in range(width)))
    lines.append("//     " + "".join(str(column % 10) for column in range(width)))
    lines += ["%3d | %s" % (row, "".join(grid[row])) for row in range(height)]
    return "\n".join(lines) + "\n"


def command_new(args: argparse.Namespace) -> int:
    if args.width < 4 or args.height < 4:
        raise LevelKitError("a new level needs to be at least 4x4 cells")
    text = blank_sketch(args.width, args.height, args.template)
    out = _resolve(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8", newline="\n")
    print("wrote %s (%dx%d cells)" % (_relative_to_project(out), args.width, args.height))
    return 0


def command_build(args: argparse.Namespace) -> int:
    source = _resolve(args.sketch)
    sketch = parse_sketch(source.read_text(encoding="utf-8"))
    out = _resolve(args.out)
    template_path = args.template or sketch.template
    # Rebuilding a map from its own sketch is the normal edit loop, so the
    # template and the output being the same file is expected.
    template = LevelMap.load(_resolve(template_path)) if template_path else None
    data = build_map(sketch, out, template)
    write_json(out, data)
    print("wrote %s (%dx%d cells)" % (_relative_to_project(out), sketch.width, sketch.height))
    if args.check:
        return command_check(argparse.Namespace(level=str(out), json=False, quiet=False))
    return 0


def command_check(args: argparse.Namespace) -> int:
    level = LevelMap.load(_resolve(args.level))
    report = check_level(level, margin=getattr(args, "margin", 0.1))
    if getattr(args, "json", False):
        print(
            json.dumps(
                {
                    "level": _relative_to_project(level.path),
                    "ok": report.ok,
                    "errors": report.errors,
                    "warnings": report.warnings,
                    "notes": report.notes,
                    "summary": report.summary,
                },
                indent=2,
                sort_keys=True,
            )
        )
        return 0 if report.ok else 1
    print("check %s" % _relative_to_project(level.path))
    summary = report.summary
    if summary.get("checked"):
        print(
            "  %dx%d cells, %d tileset(s), %d ledge(s)"
            % (summary["size"][0], summary["size"][1], summary["tilesets"], summary["ledges"])
        )
    for note in report.notes:
        print("  note  %s" % note)
    for warning in report.warnings:
        print("  WARN  %s" % warning)
    for error in report.errors:
        print("  ERROR %s" % error)
    print("  %s" % ("PASS" if report.ok else "FAIL (%d error(s))" % len(report.errors)))
    return 0 if report.ok else 1


def command_autoart(args: argparse.Namespace) -> int:
    path = _resolve(args.level)
    level = LevelMap.load(path)
    changed = autoart(level)
    out = _resolve(args.out) if args.out else path
    write_json(out, level.data)
    print("wrote %s (%s)" % (_relative_to_project(out), ", ".join(changed) if changed else "already up to date"))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="level_kit",
        description="Sketch, build, validate and decorate RUN//UNIT Tiled routes.",
    )
    commands = parser.add_subparsers(dest="command", required=True)

    sketch_parser = commands.add_parser("sketch", help="write a .tmj out as an editable text grid")
    sketch_parser.add_argument("level", help="path to a .tmj map")
    sketch_parser.add_argument("--out", help="write the sketch here instead of stdout")
    sketch_parser.set_defaults(func=command_sketch)

    build_parser_ = commands.add_parser("build", help="turn a text grid back into a .tmj map")
    build_parser_.add_argument("sketch", help="path to a sketch written by `sketch`")
    build_parser_.add_argument("--out", required=True, help="path of the .tmj map to write")
    build_parser_.add_argument("--template", help="map to inherit tilesets and art layers from")
    build_parser_.add_argument("--check", action="store_true", help="validate the result straight after writing it")
    build_parser_.set_defaults(func=command_build)

    new_parser = commands.add_parser("new", help="scaffold a blank sketch to start a level from")
    new_parser.add_argument("--out", required=True, help="path of the sketch to write")
    new_parser.add_argument("--width", type=int, default=90, help="map width in cells (default 90)")
    new_parser.add_argument("--height", type=int, default=29, help="map height in cells (default 29)")
    new_parser.add_argument(
        "--template",
        default="assets/tiled/levels/maintenance_shaft.tmj",
        help="map the built level should inherit tilesets and art from",
    )
    new_parser.set_defaults(func=command_new)

    check_parser = commands.add_parser("check", help="validate a map against the engine contract and the motor")
    check_parser.add_argument("level", help="path to a .tmj map")
    check_parser.add_argument("--json", action="store_true", help="machine-readable output")
    check_parser.add_argument(
        "--margin",
        type=float,
        default=0.1,
        help="fraction of run speed a jump must spare before it counts as comfortable (default 0.1)",
    )
    check_parser.set_defaults(func=command_check)

    autoart_parser = commands.add_parser("autoart", help="regenerate decorative layers from the route geometry")
    autoart_parser.add_argument("level", help="path to a .tmj map")
    autoart_parser.add_argument("--out", help="write here instead of editing in place")
    autoart_parser.set_defaults(func=command_autoart)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        return int(args.func(args))
    except LevelKitError as error:
        print("level_kit: %s" % error, file=sys.stderr)
        return 2


# Internal implementation extensions keep this file as the stable public facade.
from levelkit.api import install_into as _install_levelkit_extensions
_install_levelkit_extensions(globals())

if __name__ == "__main__":
    raise SystemExit(main())
