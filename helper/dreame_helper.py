"""JSON-lines bridge between the macOS app and the Dreamehome cloud.

The app starts this process and talks to it over stdin/stdout, one JSON object per line:

  request:  {"id": 1, "method": "status", "params": {}}
  response: {"id": 1, "result": {...}}  or  {"id": 1, "error": {"code": "...", "message": "..."}}

Methods:
  login       {user, country, password?, refreshToken?} -> {refreshToken, devices: [{did, name, model, online}]}
  select      {did}                                     -> {did, name, model, online}; error robot_offline if offline
  status      {}                                        -> {state, error, battery, charging, status, suction, task, cleaningMode}
  action      {name: start|pause|stop|dock|locate}      -> {}
  rooms       {}                                        -> [{id, name, type}]
  map         {}                                        -> {mapID, width, height, pixels, rooms: [{id, name, x, y}], charger}
              pixels: base64 uint8 per pixel, row-major from the top-left, already rotated like the Dreame app.
              Values: 0 outside, 1-63 floor of that room, 101-163 that room's edge, 254/253 floor without room.
              status then also contains `robot: {x, y}` in the same image coordinates.
  cleanRooms  {rooms: [id], mode?, suction?, repeats?}  -> {}
              mode: vacuum|mop|vacuum_and_mop|mop_after_vacuum, suction: quiet|standard|strong|turbo

Robot access goes through `DreameVacuumDevice` from the vendored dreame_vacuum package, which keeps
itself up to date in the background (polling + MQTT) and decodes the map (rooms).

Secrets only ever arrive over stdin; the app owns the Keychain. stdout is reserved for responses,
all logging goes to stderr.
"""

import base64
import json
import logging
import sys
import time
from enum import IntEnum
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent / "vendor"))

import numpy as np  # noqa: E402
from dreame.device import DreameVacuumDevice  # noqa: E402
from dreame.exceptions import DeviceException  # noqa: E402
from dreame.protocol import DreameVacuumDreameHomeCloudProtocol  # noqa: E402
from dreame.types import (  # noqa: E402
    DreameVacuumChargingStatus,
    DreameVacuumCleaningMode,
    DreameVacuumErrorCode,
    DreameVacuumProperty,
    DreameVacuumState,
    DreameVacuumStatus,
    DreameVacuumSuctionLevel,
    DreameVacuumTaskStatus,
)

_LOGGER = logging.getLogger("dreame_helper")

ACCOUNT_TYPE = "dreame"
# The device decodes the map in the background after connecting; rooms may take a few seconds.
ROOMS_TIMEOUT = 20

# key -> (property, enum)
STATUS_PROPERTIES = {
    "state": (DreameVacuumProperty.STATE, DreameVacuumState),
    "error": (DreameVacuumProperty.ERROR, DreameVacuumErrorCode),
    "battery": (DreameVacuumProperty.BATTERY_LEVEL, None),
    "charging": (DreameVacuumProperty.CHARGING_STATUS, DreameVacuumChargingStatus),
    "status": (DreameVacuumProperty.STATUS, DreameVacuumStatus),
    "suction": (DreameVacuumProperty.SUCTION_LEVEL, DreameVacuumSuctionLevel),
    "task": (DreameVacuumProperty.TASK_STATUS, DreameVacuumTaskStatus),
    "cleaningMode": (DreameVacuumProperty.CLEANING_MODE, None),
}

ACTIONS = {
    "start": DreameVacuumDevice.start,
    "pause": DreameVacuumDevice.pause,
    "stop": DreameVacuumDevice.stop,
    "dock": DreameVacuumDevice.return_to_base,
    "locate": DreameVacuumDevice.locate,
}

CLEANING_MODES = {
    "vacuum": DreameVacuumCleaningMode.SWEEPING,
    "mop": DreameVacuumCleaningMode.MOPPING,
    "vacuum_and_mop": DreameVacuumCleaningMode.SWEEPING_AND_MOPPING,
    "mop_after_vacuum": DreameVacuumCleaningMode.MOPPING_AFTER_SWEEPING,
}

SUCTION_LEVELS = {
    "quiet": DreameVacuumSuctionLevel.QUIET,
    "standard": DreameVacuumSuctionLevel.STANDARD,
    "strong": DreameVacuumSuctionLevel.STRONG,
    "turbo": DreameVacuumSuctionLevel.TURBO,
}

# Models with mop pad lifting (like the X50) pack several settings into the raw cleaning mode value
# (see DreameVacuumDevice.split_group_value / _cleaning_mode_changed).
GROUPED_CLEANING_MODES = {
    0: DreameVacuumCleaningMode.SWEEPING_AND_MOPPING,
    1: DreameVacuumCleaningMode.MOPPING,
    2: DreameVacuumCleaningMode.SWEEPING,
    3: DreameVacuumCleaningMode.MOPPING_AFTER_SWEEPING,
}


class HelperError(Exception):
    def __init__(self, code: str, message: str) -> None:
        super().__init__(message)
        self.code = code


def enum_value(value: int, enum: type[IntEnum]) -> dict:
    try:
        name = enum(value).name.lower()
    except ValueError:
        name = "unknown"
    return {"raw": value, "name": name}


def cleaning_mode_value(value: int) -> dict:
    return {
        "raw": value,
        "name": GROUPED_CLEANING_MODES[value & 0x03].name.lower(),
        "selfClean": (value >> 8) & ~0x300,
        "humidity": value >> 16,
    }


def device_summary(device: dict) -> dict:
    return {
        "did": str(device.get("did")),
        "name": device.get("customName") or device.get("deviceInfo", {}).get("displayName") or "",
        "model": device.get("model") or "",
        "online": bool(device.get("online")),
    }


def choice(table: dict, key: str | None, what: str):
    if key is None:
        return None
    if key not in table:
        raise HelperError("invalid_request", f"Unknown {what} {key!r}, expected one of {sorted(table)}")
    return table[key]


class MapTransform:
    """World coordinates (mm) -> pixel coordinates of the image sent by `map` (flipped, cropped, rotated)."""

    def __init__(self, dimensions, crop_x: int, crop_y: int, width: int, height: int, quarter_turns: int) -> None:
        self.dimensions = dimensions
        self.crop_x = crop_x
        self.crop_y = crop_y
        self.width = width  # before rotating
        self.height = height
        self.quarter_turns = quarter_turns

    def __call__(self, point) -> dict:
        d = self.dimensions
        x = (point.x - d.left) / d.grid_size - self.crop_x
        y = ((d.height * d.grid_size - 1) - (point.y - d.top)) / d.grid_size - self.crop_y
        width, height = self.width, self.height
        for _ in range(self.quarter_turns):  # same as np.rot90: counterclockwise
            x, y = y, width - 1 - x
            width, height = height, width
        return {"x": round(x, 1), "y": round(y, 1)}


class Session:
    def __init__(self) -> None:
        self.credentials: dict | None = None
        self.refresh_token: str | None = None
        self.devices: list[dict] = []
        self.device: DreameVacuumDevice | None = None
        self.summary: dict | None = None
        self.map_transform: MapTransform | None = None

    def login(self, user: str, country: str, password: str | None = None, refreshToken: str | None = None) -> dict:
        self._disconnect()
        cloud = DreameVacuumDreameHomeCloudProtocol(user, password or "", ACCOUNT_TYPE, country, refreshToken)
        try:
            if not cloud.login():
                raise HelperError("auth_failed" if cloud.auth_failed else "login_failed", "Login failed")
            response = cloud.get_devices()
            if not response:
                raise HelperError("request_failed", "Could not fetch device list")
        finally:
            cloud.disconnect()

        self.credentials = {"user": user, "country": country, "password": password}
        self.refresh_token = cloud.auth_key
        self.devices = [d for d in response["page"]["records"] if ".vacuum." in str(d.get("model"))]
        return {"refreshToken": self.refresh_token, "devices": [device_summary(d) for d in self.devices]}

    def select(self, did: str) -> dict:
        if self.credentials is None:
            raise HelperError("not_logged_in", "Not logged in")
        record = next((d for d in self.devices if str(d.get("did")) == did), None)
        if record is None:
            raise HelperError("no_device", f"Unknown device {did}")

        self._disconnect()
        summary = device_summary(record)
        if not summary["online"]:
            # Commands would only time out (cloud error 80001, "device may be offline").
            raise HelperError("robot_offline", f"{summary['name']} is offline")
        c = self.credentials
        device = DreameVacuumDevice(
            summary["name"], None, " ", None, c["user"], c["password"], c["country"],
            True, ACCOUNT_TYPE, did, self.refresh_token,
        )  # fmt: skip
        try:
            device.update()
        except DeviceException as ex:
            device.disconnect()
            if ex.translation_key == "cloud_unreachable":
                # The cloud flag can say online while the robot doesn't answer (cloud error 80001).
                raise HelperError("robot_offline", f"{summary['name']} isn't responding") from ex
            raise HelperError("request_failed", f"Could not connect to the robot: {ex}") from ex
        device.schedule_update()  # keep refreshing in the background, like the HA coordinator does
        self.device = device
        self.summary = summary
        return summary

    def status(self) -> dict:
        device = self._device()
        status = {}
        for key, (prop, enum) in STATUS_PROPERTIES.items():
            value = device.get_property(prop)
            if value is None:
                status[key] = None
            elif key == "cleaningMode":
                status[key] = cleaning_mode_value(value)
            elif enum is None:
                status[key] = value
            else:
                status[key] = enum_value(value, enum)
        current_map = device.status.current_map
        robot = current_map.robot_position if current_map else None
        status["robot"] = self.map_transform(robot) if robot and self.map_transform else None
        return status

    def action(self, name: str) -> dict:
        device = self._device()
        method = choice(ACTIONS, name, "action")
        self._run(lambda: method(device))
        return {}

    def rooms(self) -> list[dict]:
        device = self._device()
        deadline = time.monotonic() + ROOMS_TIMEOUT
        while not device.status.segments and time.monotonic() < deadline:
            time.sleep(0.5)
        segments = device.status.segments or {}
        return [
            {"id": int(segment_id), "name": segment.custom_name or segment.name or f"Room {segment_id}", "type": segment.type}
            for segment_id, segment in sorted(segments.items())
        ]

    def map(self) -> dict:
        device = self._device()
        deadline = time.monotonic() + ROOMS_TIMEOUT
        while not (device.status.selected_map and device.status.selected_map.pixel_type is not None):
            if time.monotonic() > deadline:
                raise HelperError("request_failed", "The map isn't available yet")
            time.sleep(0.5)
        saved = device.status.selected_map

        # pixel_type is indexed [x, y] with y pointing up; the image wants rows from the top.
        image = saved.pixel_type[:, ::-1].T
        filled = np.argwhere(image != 0)
        (top, left), (bottom, right) = filled.min(axis=0), filled.max(axis=0)
        image = image[top : bottom + 1, left : right + 1]
        quarter_turns = (int(saved.rotation or 0) // 90) % 4
        transform = MapTransform(saved.dimensions, int(left), int(top), image.shape[1], image.shape[0], quarter_turns)
        image = np.ascontiguousarray(np.rot90(image, quarter_turns), dtype=np.uint8)
        self.map_transform = transform

        rooms = []
        for segment_id, segment in sorted((saved.segments or {}).items()):
            center = transform(type("P", (), {"x": segment.x, "y": segment.y})) if segment.x is not None else None
            rooms.append({"id": int(segment_id), "name": segment.custom_name or segment.name, **(center or {})})
        return {
            "mapID": saved.map_id,
            "width": image.shape[1],
            "height": image.shape[0],
            "pixels": base64.b64encode(image.tobytes()).decode(),
            "rooms": rooms,
            "charger": transform(saved.charger_position) if saved.charger_position else None,
        }

    def cleanRooms(self, rooms: list[int], mode: str | None = None, suction: str | None = None, repeats: int = 1) -> dict:
        device = self._device()
        if not rooms:
            raise HelperError("invalid_request", "No rooms given")
        cleaning_mode = choice(CLEANING_MODES, mode, "mode")
        suction_level = choice(SUCTION_LEVELS, suction, "suction")
        if cleaning_mode is not None and device.status.cleaning_mode != cleaning_mode:
            self._run(lambda: device.set_cleaning_mode(cleaning_mode.value))
        self._run(
            lambda: device.clean_segment(
                rooms,
                max(1, int(repeats)),
                suction_level.value if suction_level is not None else None,
                None,
            )
        )
        return {}

    def _run(self, operation) -> None:
        try:
            operation()
        except DeviceException as ex:
            raise HelperError("request_failed", str(ex)) from ex

    def _device(self) -> DreameVacuumDevice:
        if self.credentials is None:
            raise HelperError("not_logged_in", "Not logged in")
        if self.device is None:
            raise HelperError("no_device", "No device selected")
        return self.device

    def _disconnect(self) -> None:
        if self.device is not None:
            self.device.disconnect()
            self.device = None
            self.summary = None


def handle(session: Session, request: dict):
    methods = {
        "login": session.login,
        "select": session.select,
        "status": session.status,
        "action": session.action,
        "rooms": session.rooms,
        "map": session.map,
        "cleanRooms": session.cleanRooms,
    }
    method = methods.get(request.get("method"))
    if method is None:
        raise HelperError("unknown_method", f"Unknown method {request.get('method')}")
    params = request.get("params") or {}
    try:
        return method(**params)
    except TypeError as ex:
        raise HelperError("invalid_request", str(ex)) from ex


def main() -> None:
    logging.basicConfig(stream=sys.stderr, level=logging.WARNING, format="%(asctime)s %(levelname)s %(name)s: %(message)s")
    # Commands sent to the robot ("Send action ...") and our own request log. The protocol logger stays
    # at WARNING; it deals with tokens.
    for name in ("dreame_helper", "dreame.device"):
        logging.getLogger(name).setLevel(logging.INFO)
    session = Session()
    try:
        for line in sys.stdin:
            if not line.strip():
                continue
            request_id = None
            try:
                request = json.loads(line)
                request_id = request.get("id")
                method = request.get("method")
                # Never log login params (password, refresh token).
                _LOGGER.info("Request %s %s", method, "" if method == "login" else request.get("params") or "")
                response = {"id": request_id, "result": handle(session, request)}
            except json.JSONDecodeError as ex:
                response = {"id": None, "error": {"code": "invalid_request", "message": f"Invalid JSON: {ex}"}}
            except HelperError as ex:
                _LOGGER.warning("Request failed: %s %s", ex.code, ex)
                response = {"id": request_id, "error": {"code": ex.code, "message": str(ex)}}
            except Exception as ex:
                _LOGGER.exception("Request failed")
                response = {"id": request_id, "error": {"code": "internal", "message": str(ex)}}
            sys.stdout.write(json.dumps(response) + "\n")
            sys.stdout.flush()
    finally:
        session._disconnect()


if __name__ == "__main__":
    main()
