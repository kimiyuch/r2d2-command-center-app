"""Step 0 spike: prove the Dreamehome cloud route works for our account.

Logs in, lists devices, reads the robot's status and (on request) sends a command.
Password and refresh token live in the macOS Keychain (service "dreame-mac"), never in files.

Usage:
  ../helper/.venv/bin/python dreame_spike.py --user you@example.com --country eu            # devices + status (read-only)
  ../helper/.venv/bin/python dreame_spike.py --user you@example.com --country eu start      # start / pause / dock / locate
  ../helper/.venv/bin/python dreame_spike.py --user you@example.com --forget                # remove stored secrets
"""

import argparse
import getpass
import logging
import sys
from enum import IntEnum
from pathlib import Path

import keyring

sys.path.insert(0, str(Path(__file__).parent.parent / "helper" / "vendor"))

from dreame.protocol import DreameVacuumDreameHomeCloudProtocol  # noqa: E402
from dreame.types import (  # noqa: E402
    DreameVacuumChargingStatus,
    DreameVacuumCleaningMode,
    DreameVacuumErrorCode,
    DreameVacuumState,
    DreameVacuumStatus,
    DreameVacuumSuctionLevel,
    DreameVacuumTaskStatus,
)

KEYCHAIN_SERVICE = "dreame-mac"

# (label, siid, piid, enum for display)
STATUS_PROPERTIES = [
    ("state", 2, 1, DreameVacuumState),
    ("error", 2, 2, DreameVacuumErrorCode),
    ("battery", 3, 1, None),
    ("charging", 3, 2, DreameVacuumChargingStatus),
    ("status", 4, 1, DreameVacuumStatus),
    ("suction", 4, 4, DreameVacuumSuctionLevel),
    ("task", 4, 7, DreameVacuumTaskStatus),
    ("cleaning mode", 4, 23, "cleaning_mode"),
]

# Models with mop pad lifting (like the X50) pack several settings into the cleaning mode value
# (see DreameVacuumDevice.split_group_value / _cleaning_mode_changed in dreame_vacuum):
# bits 0-1 mode, bits 8-15 self-clean interval, bits 16+ mop humidity.
GROUPED_CLEANING_MODES = {
    0: DreameVacuumCleaningMode.SWEEPING_AND_MOPPING,
    1: DreameVacuumCleaningMode.MOPPING,
    2: DreameVacuumCleaningMode.SWEEPING,
    3: DreameVacuumCleaningMode.MOPPING_AFTER_SWEEPING,
}


def cleaning_mode_label(value: int) -> str:
    mode = GROUPED_CLEANING_MODES[value & 0x03]
    self_clean = (value >> 8) & ~0x300
    return f"{mode.name.lower()} (raw {value}: self-clean {self_clean}, humidity {value >> 16})"

# command -> (siid, aiid)
ACTIONS = {
    "start": (2, 1),
    "pause": (2, 2),
    "dock": (3, 1),
    "stop": (4, 2),
    "locate": (7, 1),
}


def refresh_token_key(user: str) -> str:
    return f"{user}:refresh-token"


def login(user: str, country: str) -> DreameVacuumDreameHomeCloudProtocol:
    password = keyring.get_password(KEYCHAIN_SERVICE, user)
    if password is None:
        password = getpass.getpass(f"Dreamehome password for {user}: ")
    refresh_token = keyring.get_password(KEYCHAIN_SERVICE, refresh_token_key(user))

    cloud = DreameVacuumDreameHomeCloudProtocol(user, password, "dreame", country, refresh_token)
    if not cloud.login():
        sys.exit("Login failed. Check password and country/region (--country).")

    # Only persist secrets once they're proven to work.
    keyring.set_password(KEYCHAIN_SERVICE, user, password)
    if cloud.auth_key:
        keyring.set_password(KEYCHAIN_SERVICE, refresh_token_key(user), cloud.auth_key)
    print(f"Logged in (region {country}).")
    return cloud


def pick_device(cloud: DreameVacuumDreameHomeCloudProtocol, did: str | None) -> dict:
    response = cloud.get_devices()
    if not response:
        sys.exit("Could not fetch device list.")
    records = response["page"]["records"]
    print(f"\n{len(records)} device(s):")
    for d in records:
        name = d.get("customName") or d.get("deviceInfo", {}).get("displayName")
        print(f"  - {name}  model={d.get('model')}  did={d.get('did')}")

    vacuums = [d for d in records if ".vacuum." in str(d.get("model"))]
    if did:
        vacuums = [d for d in vacuums if str(d.get("did")) == did]
    if not vacuums:
        sys.exit("No matching vacuum found.")
    if len(vacuums) > 1:
        sys.exit("Several vacuums found, choose one with --did.")
    return vacuums[0]


def label(value, enum: type[IntEnum] | str | None) -> str:
    if enum == "cleaning_mode":
        return cleaning_mode_label(value)
    if enum is None:
        return str(value)
    try:
        return f"{enum(value).name.lower()} ({value})"
    except ValueError:
        return f"unknown ({value})"


def print_status(cloud: DreameVacuumDreameHomeCloudProtocol, did: str) -> None:
    params = [{"did": did, "siid": siid, "piid": piid} for _, siid, piid, _ in STATUS_PROPERTIES]
    result = cloud.send("get_properties", params)
    if result is None:
        sys.exit("Reading status failed.")
    values = {(r["siid"], r["piid"]): r for r in result}
    print("\nStatus:")
    for name, siid, piid, enum in STATUS_PROPERTIES:
        r = values.get((siid, piid), {})
        if r.get("code", 0) != 0 or "value" not in r:
            print(f"  {name:14} n/a (code {r.get('code')})")
        else:
            print(f"  {name:14} {label(r['value'], enum)}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", nargs="?", choices=sorted(ACTIONS), help="optional command to send")
    parser.add_argument("--user", required=True, help="Dreamehome account email")
    parser.add_argument("--country", default="eu", help="cloud region: eu, us, cn, sg, ru, kr, in (default: eu)")
    parser.add_argument("--did", help="device id, if the account has several vacuums")
    parser.add_argument("--forget", action="store_true", help="delete stored password and token from the Keychain")
    parser.add_argument("--debug", action="store_true", help="verbose protocol logging")
    args = parser.parse_args()

    logging.basicConfig(level=logging.DEBUG if args.debug else logging.WARNING)

    if args.forget:
        for key in (args.user, refresh_token_key(args.user)):
            try:
                keyring.delete_password(KEYCHAIN_SERVICE, key)
            except keyring.errors.PasswordDeleteError:
                pass
        print("Stored secrets removed.")
        return

    cloud = login(args.user, args.country)
    device = pick_device(cloud, args.did)
    did = str(device["did"])

    cloud._did = did  # the protocol class expects the device id to be set before fetching device info
    if not cloud.get_device_info():
        sys.exit("Could not fetch device info.")

    print_status(cloud, did)

    if args.command:
        siid, aiid = ACTIONS[args.command]
        result = cloud.send("action", {"did": did, "siid": siid, "aiid": aiid, "in": []})
        print(f"\nCommand '{args.command}': {'sent' if result is not None else 'FAILED'} ({result})")

    cloud.disconnect()


if __name__ == "__main__":
    main()
