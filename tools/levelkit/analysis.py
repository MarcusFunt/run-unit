"""Difficulty-aware route selection and structured Level Kit reports."""

from __future__ import annotations

import heapq
import math


def _transition_exists(edges: dict[int, list[dict]], source: int, target: int) -> bool:
    return any(int(move.get("to", -1)) == target for move in edges.get(source, ()))


def move_difficulty(
    move: dict,
    source_ledge,
    physics,
    level,
    *,
    margin_edges: dict[int, list[dict]] | None = None,
    double_margin_edges: dict[int, list[dict]] | None = None,
    margin: float = 0.1,
) -> dict:
    """Classify one graph move by robustness and available takeoff run-up.

    ``margin`` keeps the existing ``check --margin`` meaning: a move that fails
    when run speed is reduced by that fraction is near-perfect. A move that
    survives one margin but not two is tight. Run-up uses the same setting, so
    changing ``--margin`` changes both the text warnings and JSON classification.
    """
    source = int(move.get("from", source_ledge.index))
    target = int(move["to"])
    charge = move.get("charge")

    usable_runup = max(source_ledge.width * level.tilewidth - float(physics.body_width), 0.0)
    acceleration = float(getattr(physics, "ground_acceleration", 2200.0))
    attainable = min(float(physics.max_run_speed), math.sqrt(max(2.0 * acceleration * usable_runup, 0.0)))
    runup_ratio = attainable / max(float(physics.max_run_speed), 1e-6)

    safe_margin = max(float(margin), 0.0)
    survives_margin = True if margin_edges is None else _transition_exists(margin_edges, source, target)
    survives_double = True if double_margin_edges is None else _transition_exists(double_margin_edges, source, target)
    near_runup_threshold = 0.0 if safe_margin <= 0.0 else max(1.0 - safe_margin, 0.0)
    tight_runup_threshold = 0.0 if safe_margin <= 0.0 else max(1.0 - safe_margin / 2.0, near_runup_threshold)

    if not survives_margin or runup_ratio < near_runup_threshold:
        rating = "near_perfect"
    elif not survives_double or runup_ratio < tight_runup_threshold:
        rating = "tight"
    else:
        rating = "comfortable"

    return {
        "from": source + 1,
        "to": target + 1,
        "charge": charge,
        "direction": int(move.get("direction", 0)),
        "landing_x": float(move.get("landing_x", 0.0)),
        "time": float(move.get("time", 0.0)),
        "rating": rating,
        "runup_ratio": round(runup_ratio, 3),
        "full_charge": bool(charge is not None and float(charge) >= 1.0),
    }


def best_route(
    start: int,
    finish_indices: set[int],
    edges: dict[int, list[dict]],
    ledges: list,
    classify,
) -> list[dict]:
    """Pick the most forgiving route using lexicographic Dijkstra cost.

    A route with fewer near-perfect moves always beats one with more; then
    tightness, full-charge dependence and finally move count break ties.
    """
    queue: list[tuple[tuple[int, int, int, int], int, tuple[dict, ...]]] = [((0, 0, 0, 0), start, ())]
    best: dict[int, tuple[int, int, int, int]] = {start: (0, 0, 0, 0)}
    while queue:
        cost, node, path = heapq.heappop(queue)
        if best.get(node) != cost:
            continue
        if node in finish_indices:
            return [dict(move) for move in path]
        for move in edges.get(node, ()):
            target = int(move["to"])
            detail = classify(dict(move, **{"from": node}), ledges[node])
            step = (
                1 if detail["rating"] == "near_perfect" else 0,
                1 if detail["rating"] == "tight" else 0,
                1 if detail["full_charge"] else 0,
                1,
            )
            new_cost = tuple(cost[i] + step[i] for i in range(4))
            if target in best and best[target] <= new_cost:
                continue
            best[target] = new_cost
            heapq.heappush(queue, (new_cost, target, path + (dict(move, **{"from": node}),)))
    return []


def route_length_m(route: list[dict], ledges: list, tile_width: int) -> float:
    total = 0.0
    for move in route:
        source = ledges[int(move["from"])]
        target = ledges[int(move["to"])]
        source_center = (source.left_px(tile_width) + source.right_px(tile_width)) * 0.5
        target_center = (target.left_px(tile_width) + target.right_px(tile_width)) * 0.5
        total += abs(target_center - source_center)
    # Godot/Tiled pixels do not have a physical SI scale. This is deliberately
    # a route-normalized metric using the project's 32 px tile as one metre.
    return round(total / max(float(tile_width), 1.0), 2)


def difficulty_summary(details: list[dict]) -> dict:
    counts = {"comfortable": 0, "tight": 0, "near_perfect": 0, "full_charge": 0}
    for detail in details:
        rating = str(detail.get("rating", "comfortable"))
        if rating in counts:
            counts[rating] += 1
        if detail.get("full_charge"):
            counts["full_charge"] += 1
    return counts
