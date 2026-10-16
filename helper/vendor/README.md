# Vendored code

- `dreame/`: the `dreame` package from https://github.com/Tasshack/dreame-vacuum
  (`custom_components/dreame_vacuum/dreame`), commit f5b8472b8e2e4bb3dff7bc2a81a5fd594eca9585, unmodified.
  MIT license, see `dreame/LICENSE`. It doesn't depend on Home Assistant.
- `miio/`: minimal stub. `dreame.protocol` imports `MiIOProtocol` for the local (non-cloud) protocol,
  which we don't use. Avoids pulling in python-miio.
