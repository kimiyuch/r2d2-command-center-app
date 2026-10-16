# R2D2 Command Center

A native macOS app (SwiftUI) for the Dreame X50 Ultra robot vacuum: status, controls, room presets,
a menu-bar extra, keyboard shortcuts and Shortcuts/Siri actions.

> Unofficial. Not affiliated with or endorsed by Dreame. Uses the undocumented Dreamehome cloud API,
> which can change at any time.

## How it works

The SwiftUI app (`app/`) starts a small Python helper (`helper/dreame_helper.py`) and talks to it over
JSON lines on stdin/stdout. The helper uses the `dreame` package from
[Tasshack/dreame-vacuum](https://github.com/Tasshack/dreame-vacuum) (MIT, vendored in `helper/vendor/`)
for the Dreamehome cloud protocol, map decoding and room cleaning. Credentials live in the macOS Keychain.

See [HANDOFF.md](HANDOFF.md) for the architecture, decisions and open items.

## Setup

Requires macOS 15+, Xcode, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and an arm64 Python 3.

```sh
# Python helper
cd helper
/opt/homebrew/bin/python3 -m venv .venv
.venv/bin/pip install -r requirements.txt

# App (set DEVELOPMENT_TEAM in app/project.yml to your own team first)
cd ../app
xcodegen generate
xcodebuild -scheme DreameMac -derivedDataPath build build
open "build/Build/Products/Debug/R2D2 Command Center.app"
```

The app runs the helper straight from the repo (path set at build time), so it only works on the
machine it was built on. Log in with your Dreamehome account (email + password, not Apple/Google sign-in).
Note that Dreame locks the account after 5 wrong passwords.
