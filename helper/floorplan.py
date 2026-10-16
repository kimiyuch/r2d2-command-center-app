"""Clean vector floor plan from the robot's pixel map.

The robot's map is a noisy raster: rooms have ragged, stair-stepped edges, furniture leaves holes and
specks, some floor isn't assigned to any room, and the lidar sees through doors and windows (long thin
"arms"). Our rooms are all rectangles, so each room becomes the rectangle that best matches what the
robot measured: thin arms are cut off, nearby walls of neighboring rooms are aligned, and overlaps go
to the room the robot saw more of. A room the rectangle fits badly falls back to its traced outline.

Input: the map image as sent to the app (2D uint8 array; 0 outside, 1-63 room floor, 101-163 room edge,
other values floor without room). Output polygons use the same pixel coordinates.
"""

import cv2
import numpy as np

PADDING = 4  # room for morphology at the image border
# Holes smaller than this (in pixels) are furniture, not real gaps; 600 px = 1.5 m² at 5 cm per pixel.
MAX_FURNITURE_HOLE = 600
SIMPLIFY_EPSILON = 1.2  # pixels; higher = smoother but less detailed outlines (traced fallback)
# Rectangle fit: shrink a side while its outermost row/column is less than this much room.
RECTANGLE_EDGE_COVERAGE = 0.5
# Walls of neighboring rooms closer than this are aligned; 6 px = 30 cm at 5 cm per pixel.
WALL_SNAP_DISTANCE = 6
# Below this share of the room's measured floor inside the rectangle, keep the traced outline instead.
MIN_RECTANGLE_COVERAGE = 0.6
AXIS_TOLERANCE = 0.2  # edges within ~11° of horizontal/vertical are straightened


def _kernel(size: int) -> np.ndarray:
    return cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (size, size))


def _largest_piece(mask: np.ndarray) -> np.ndarray:
    count, labels, stats, _ = cv2.connectedComponentsWithStats(mask)
    if count <= 1:
        return mask
    return (labels == 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])).astype(np.uint8)


def _fill_small_holes(mask: np.ndarray, max_hole: int) -> np.ndarray:
    count, labels, stats, _ = cv2.connectedComponentsWithStats(1 - mask)
    height, width = mask.shape
    mask = mask.copy()
    for i in range(1, count):
        x, y, w, h, area = stats[i]
        touches_border = x == 0 or y == 0 or x + w == width or y + h == height
        if area < max_hole and not touches_border:
            mask[labels == i] = 1
    return mask


def _straighten(points: np.ndarray) -> np.ndarray:
    """Make near-horizontal/vertical edges exact; each vertex takes x from a vertical and y from a horizontal neighbor edge."""
    count = len(points)
    result = points.copy()
    kinds = []
    for i in range(count):
        dx, dy = np.abs(points[(i + 1) % count] - points[i])
        kinds.append("h" if dy <= AXIS_TOLERANCE * dx else "v" if dx <= AXIS_TOLERANCE * dy else "d")
    for axis, kind in ((1, "h"), (0, "v")):
        for i in range(count):
            if kinds[i] == kind:
                j = (i + 1) % count
                result[i][axis] = result[j][axis] = (points[i][axis] + points[j][axis]) / 2
    return result


def _outlines(mask: np.ndarray) -> list[list[float]]:
    """Outer rings and holes as flat [x0, y0, x1, y1, ...] lists (fill with the even-odd rule)."""
    contours, _ = cv2.findContours(mask, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    rings = []
    for contour in contours:
        if cv2.contourArea(contour) < 30:
            continue
        points = cv2.approxPolyDP(contour, SIMPLIFY_EPSILON, True).reshape(-1, 2).astype(float)
        if len(points) < 3:
            continue
        # Same coordinates as robot/dock positions: pixel indices, padding removed.
        points = _straighten(points) - PADDING
        rings.append([round(float(v), 1) for v in points.flatten()])
    return rings


def _fit_rectangle(mask: np.ndarray) -> list[int]:
    """[x0, y0, x1, y1] in pixel-edge coordinates (x1/y1 exclusive), arms with little coverage peeled off."""
    ys, xs = np.nonzero(mask)
    x0, x1, y0, y1 = int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max())
    changed = True
    while changed and x1 - x0 > 4 and y1 - y0 > 4:
        changed = False
        if mask[y0 : y1 + 1, x0].mean() < RECTANGLE_EDGE_COVERAGE:
            x0, changed = x0 + 1, True
        if mask[y0 : y1 + 1, x1].mean() < RECTANGLE_EDGE_COVERAGE:
            x1, changed = x1 - 1, True
        if mask[y0, x0 : x1 + 1].mean() < RECTANGLE_EDGE_COVERAGE:
            y0, changed = y0 + 1, True
        if mask[y1, x0 : x1 + 1].mean() < RECTANGLE_EDGE_COVERAGE:
            y1, changed = y1 - 1, True
    return [x0, y0, x1 + 1, y1 + 1]


def _snap(values: list[int]) -> dict[int, int]:
    """Groups values closer than WALL_SNAP_DISTANCE and maps each to its group's mean."""
    groups: list[list[int]] = []
    for value in sorted(set(values)):
        if groups and value - groups[-1][-1] <= WALL_SNAP_DISTANCE:
            groups[-1].append(value)
        else:
            groups.append([value])
    return {value: round(float(np.mean(group))) for group in groups for value in group}


def _resolve_overlaps(rects: dict[int, list[int]], labels: np.ndarray) -> None:
    """Gives each overlap to the room with more measured floor in it; the other room gives up the thinner side."""
    for _ in range(20):
        changed = False
        for a in rects:
            for b in rects:
                if a >= b:
                    continue
                ra, rb = rects[a], rects[b]
                ox0, oy0, ox1, oy1 = max(ra[0], rb[0]), max(ra[1], rb[1]), min(ra[2], rb[2]), min(ra[3], rb[3])
                if ox0 >= ox1 or oy0 >= oy1:
                    continue
                region = labels[oy0:oy1, ox0:ox1]
                loser = rects[b] if (region == a).sum() >= (region == b).sum() else rects[a]
                if ox1 - ox0 <= oy1 - oy0:  # cut along x
                    if loser[0] >= ox0:
                        loser[0] = ox1
                    else:
                        loser[2] = ox0
                else:
                    if loser[1] >= oy0:
                        loser[1] = oy1
                    else:
                        loser[3] = oy0
                changed = True
        if not changed:
            return


def _rectangle_ring(rect: list[int]) -> list[float]:
    # Edge coordinates -> the pixel-index coordinates used everywhere else (pixel i is centered on i).
    x0, y0, x1, y1 = (v - 0.5 - PADDING for v in rect)
    return [x0, y0, x1, y0, x1, y1, x0, y1]


def build(image: np.ndarray, room_ids: list[int]) -> dict:
    """Returns {id: {"outline": rings, "pixels": area, "center": (x, y)}} for the rooms that have floor."""
    pixels = np.pad(image, PADDING)

    home = cv2.morphologyEx((pixels != 0).astype(np.uint8), cv2.MORPH_CLOSE, _kernel(5))
    home = cv2.morphologyEx(home, cv2.MORPH_OPEN, _kernel(3))
    home = _fill_small_holes(_largest_piece(home), MAX_FURNITURE_HOLE)

    # Seed each room with its own floor, then grow rooms over edges and unassigned floor until they tile the home.
    labels = np.zeros(pixels.shape, np.int32)
    for room_id in room_ids:
        labels[cv2.morphologyEx((pixels == room_id).astype(np.uint8), cv2.MORPH_OPEN, _kernel(3)) > 0] = room_id
    for _ in range(100):
        unassigned = (labels == 0) & (home > 0)
        if not unassigned.any():
            break
        grown = cv2.dilate(labels.astype(np.float32), _kernel(3)).astype(np.int32)
        labels[unassigned] = grown[unassigned]
    labels[home == 0] = 0

    masks = {}
    for room_id in room_ids:
        mask = cv2.morphologyEx((labels == room_id).astype(np.uint8), cv2.MORPH_OPEN, _kernel(3))
        if mask.any():
            masks[room_id] = _fill_small_holes(_largest_piece(mask), MAX_FURNITURE_HOLE)

    rects = {room_id: _fit_rectangle(mask) for room_id, mask in masks.items()}
    xs = _snap([v for r in rects.values() for v in (r[0], r[2])])
    ys = _snap([v for r in rects.values() for v in (r[1], r[3])])
    rects = {room_id: [xs[r[0]], ys[r[1]], xs[r[2]], ys[r[3]]] for room_id, r in rects.items()}
    _resolve_overlaps(rects, labels)

    rooms = {}
    for room_id, mask in masks.items():
        x0, y0, x1, y1 = rects[room_id]
        coverage = mask[y0:y1, x0:x1].sum() / mask.sum() if x1 > x0 and y1 > y0 else 0
        if coverage >= MIN_RECTANGLE_COVERAGE:
            rooms[room_id] = {
                "outline": [_rectangle_ring(rects[room_id])],
                "pixels": (x1 - x0) * (y1 - y0),
                "center": ((x0 + x1) / 2 - 0.5 - PADDING, (y0 + y1) / 2 - 0.5 - PADDING),
            }
            continue
        # Label position: well inside the room (so names never sit on a wall), as close to its middle as possible.
        distance = cv2.distanceTransform(mask, cv2.DIST_L2, 5)
        candidates = np.argwhere(distance >= 0.8 * distance.max())
        middle = np.argwhere(mask).mean(axis=0)
        y, x = candidates[np.argmin(((candidates - middle) ** 2).sum(axis=1))]
        rooms[room_id] = {
            "outline": _outlines(mask),
            "pixels": int(mask.sum()),
            "center": (float(x) - PADDING, float(y) - PADDING),
        }
    return rooms
