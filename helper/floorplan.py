"""Clean vector floor plan from the robot's pixel map.

The robot's map is a noisy raster: rooms have ragged, stair-stepped edges, furniture leaves holes and
specks, and some floor isn't assigned to any room. This turns it into one outline for the whole home
plus one outline per room, where rooms tile the home without gaps and near-axis walls are straight.

Input: the map image as sent to the app (2D uint8 array; 0 outside, 1-63 room floor, 101-163 room edge,
other values floor without room). Output polygons use the same pixel coordinates.
"""

import cv2
import numpy as np

PADDING = 4  # room for morphology at the image border
# Holes smaller than this (in pixels) are furniture, not real gaps; 600 px = 1.5 m² at 5 cm per pixel.
MAX_FURNITURE_HOLE = 600
SIMPLIFY_EPSILON = 1.2  # pixels; higher = smoother but less detailed outlines
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


def build(image: np.ndarray, room_ids: list[int]) -> dict:
    """Returns {"outline": rings, "rooms": {id: {"outline": rings, "pixels": area, "center": (x, y)}}}."""
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

    rooms = {}
    for room_id in room_ids:
        mask = cv2.morphologyEx((labels == room_id).astype(np.uint8), cv2.MORPH_OPEN, _kernel(3))
        if not mask.any():
            continue
        mask = _fill_small_holes(_largest_piece(mask), MAX_FURNITURE_HOLE)
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
    return {"outline": _outlines(home), "rooms": rooms}
