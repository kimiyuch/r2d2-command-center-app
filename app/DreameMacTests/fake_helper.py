"""Stand-in for dreame_helper.py in tests: same JSON-lines contract, canned answers."""

import json
import sys

STATUS = {
    "state": {"raw": 13, "name": "charging_completed"},
    "error": {"raw": 0, "name": "no_error"},
    "battery": 100,
    "charging": {"raw": 1, "name": "charging"},
    "status": {"raw": 6, "name": "charging"},
    "suction": {"raw": 2, "name": "strong"},
    "task": {"raw": 0, "name": "completed"},
    "cleaningMode": {"raw": 3842, "name": "sweeping", "selfClean": 15, "humidity": 0},
}

for line in sys.stdin:
    request = json.loads(line)
    method = request["method"]
    if method == "exit":
        sys.exit(0)
    if method == "status":
        response = {"result": STATUS}
    elif method == "hang":
        continue
    else:
        response = {"error": {"code": "auth_failed", "message": "Login failed"}}
    response["id"] = request["id"]
    sys.stdout.write(json.dumps(response) + "\n")
    sys.stdout.flush()
