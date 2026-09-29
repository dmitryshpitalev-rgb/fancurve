# FanCurve

A fan controller for the 16-inch MacBook Pro 2019 (A2141) with the Radeon Pro 5500M — the `MacBookPro16,1` model — on macOS 15 Sequoia.

## The problem

macOS keeps this machine quiet at the price of heat. Under load the CPU sits at 95–100 °C and throttles; on battery the fans spin up late. FanCurve replaces that policy with one curve of your own: fan speed follows the hotter of the two dies, CPU or Radeon, and both fans move together — the way MSI Afterburner drives a GPU fan.

## What it does

- A root daemon reads the SMC every 500 ms and sets both fans from your curve: temperature of the hotter die → percent of the fan range. A power (watts) curve pre-empts the ramp under a load spike; an optional chassis curve can be switched on.
- At 95 °C or more on either die the fans go to 100 %, whatever the curve says.
- Smoothing: ramp-up rate, hold after a peak, ramp-down rate, a deadband against needless writes.
- The daemon hands the fans back to macOS on sleep, on exit, and when the SMC refuses writes. A separate watchdog process does the same about 5 s after the daemon's last sign of life.
- A menubar app: a wheel that shows the fan speed with the hot die's temperature beside it; a popup with the four readings, 5/15/60-minute charts of temperatures, fan speed and power; a curve editor with draggable points and the smoothing settings; a switch that keeps the Radeon active on the charger (`pmset gpuswitch`), undone on uninstall.
- `fancurvectl` for the terminal: status, history as CSV, get and set the config, enable/disable, gpu on/off.
- Russian, Ukrainian or English, after the system language; any other language gets English.

## Install

Requirements: macOS 15 Sequoia, a `MacBookPro16,1` (the installer refuses any other model or an older macOS), an administrator account.

Download `FanCurve-1.0.1.zip` from Releases, unzip it and run:

```
cd FanCurve-1.0.1
sudo bash scripts/install.sh
```

From source (Swift 6.1 command-line tools, `xcode-select --install`):

```
./scripts/build-app.sh
sudo bash scripts/install.sh
```

The installer puts the daemon and its watchdog into `/Library/PrivilegedHelperTools/local.fancurve` with launchd plists in `/Library/LaunchDaemons`, the app into `/Applications` with a LaunchAgent for your user, and `fancurvectl` into `/usr/local/bin`. macOS then reports new background items; FanCurve's must stay switched on in System Settings → General → Login Items & Extensions → Allow in the Background. Installing again over a running installation updates it.

Uninstall: `sudo /Library/PrivilegedHelperTools/local.fancurve/uninstall.sh` (the installer leaves a copy there; `sudo ./scripts/uninstall.sh` from the download does the same) removes everything and returns the fans and graphics switching to macOS.

## Notes

- Tested on macOS 15.7 and 15.8 Sequoia on one A2141. The daemon refuses any other Mac model: it checks the model identifier and the SMC keys it needs.
- macOS 26 Tahoe is untested; whether the SMC behaves the same there is unknown. On the A2141 Tahoe is not recommended anyway: the Radeon Pro 5500M performs poorly on it and the laptop feels sluggish.
- Nothing is notarized (there is no Apple developer certificate; everything is signed ad hoc), so Gatekeeper would refuse a downloaded copy: the installer removes the quarantine flag the download carries, and `bash scripts/install.sh` runs the script without Gatekeeper looking at it. If you would rather not trust a download, build from source.
- Design notes and the hardware acceptance records are in `docs/` (in Russian).

## Disclaimer

FanCurve writes to the SMC fan-control keys. It is provided as is, without warranty of any kind, and you use it at your own risk. Fan control is part of the machine's protection against heat: a wrong curve can let it run hotter or louder than macOS would. The author runs it daily on his own laptop and cannot promise it suits yours.

## License

MIT — see `LICENSE`.
