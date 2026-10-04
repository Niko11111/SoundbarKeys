# SoundbarKeys

Use your Mac's volume keys to control a **Bose soundbar** that is connected through your TV.

If your Mac is connected to a TV via HDMI and the TV passes the sound on to a soundbar (ARC/eARC), macOS cannot change the soundbar's volume – Macs don't support HDMI-CEC. SoundbarKeys fixes that: it intercepts the volume keys while the HDMI output is active and talks to the soundbar directly over your local network.

- 🔊 Volume up / down / mute keys control the soundbar
- 🎚 Menu bar panel with a volume slider and the sound mode (e.g. Normal / Dialogue), in Liquid Glass
- 🛡 Configurable **maximum volume** – no more accidental "very loud"
- 🌙 **Quiet hours**: a lower maximum at night; a soundbar that is too loud is turned down when they begin
- 🪟 On-screen volume indicator in the style of macOS 26 (top right, bottom center or off)
- 🔁 Finds the soundbar automatically (or the one you pick), reconnects after sleep, refreshes its sign-in token by itself
- 🌍 English and German

> **Not affiliated with Bose.** SoundbarKeys is an independent project and is not affiliated with, endorsed by or sponsored by Bose Corporation. Bose is a trademark of Bose Corporation. It uses an **unofficial, undocumented** local API of the soundbar that may change or stop working with any firmware update.

## Requirements

- macOS 26 (Tahoe) or later
- A Bose soundbar of the "Bose Music" generation (ECO2), e.g. Soundbar 500 / 700 / 900 / Ultra. Tested with the **Soundbar 700**.
- The soundbar is set up with the Bose app, connected to your network and to the TV via HDMI ARC/eARC
- A Bose account (the same one you use in the Bose app)

## Installation

### Download

1. Download `SoundbarKeys-<version>.dmg` from the [latest release](https://github.com/Niko11111/SoundbarKeys/releases/latest).
2. Open it and drag **SoundbarKeys** into **Applications**.
3. Open SoundbarKeys. The first time, macOS blocks it: the app is not notarized by Apple (that needs a paid developer account). To allow it once:
   - System Settings → **Privacy & Security** → scroll down → **Open Anyway** next to "SoundbarKeys was blocked", then confirm.

Runs on Apple Silicon and Intel Macs with macOS 26 or later.

**After an update (or if the volume keys do nothing):** macOS ties the Accessibility permission to the exact app build, and the switch in the list may still belong to the old one. In System Settings → Privacy & Security → **Accessibility**, remove every "SoundbarKeys" entry with **−**, quit and restart SoundbarKeys, and allow it again. The exclamation mark on the menu bar icon disappears once it works.

### Build from source

```sh
xcode-select --install          # Command Line Tools (Swift) if not installed yet
git clone https://github.com/Niko11111/SoundbarKeys.git
cd SoundbarKeys
App/make_app.sh                 # builds, signs and installs /Applications/SoundbarKeys.app
App/make_dmg.sh                 # or: builds the distributable DMG (Apple Silicon + Intel) in App/build/
```

The app icon is compiled with `actool` if Xcode is installed; otherwise the precompiled icon in `App/Resources/CompiledIcon` is used.

`make_app.sh` signs with an "Apple Development" certificate if your Keychain has one; without it the app is signed ad hoc, and macOS asks for the Accessibility permission again after every rebuild. `make_dmg.sh` signs with a "Developer ID Application" certificate if available (and notarizes with `NOTARY_PROFILE=<notarytool profile>`), otherwise ad hoc.

### Sign in once

The soundbar only accepts commands with a token from your Bose account. On first start SoundbarKeys opens **Bose's own sign-in page** in a small window (Settings → Account), the same page the Bose app shows. Sign in there with the account you use in the Bose app; codes and password reset work as on the web.

SoundbarKeys does not read what you type there. The resulting tokens are saved in your macOS Keychain (service `SoundbarKeys`) and refreshed automatically. You only need to sign in again if Bose invalidates them (e.g. after a password change).

For developers there is also a Python login tool (3.10+):

```sh
cd tools
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/python login.py
```

### First start

1. Open SoundbarKeys from /Applications – a speaker icon appears in the menu bar and the sign-in window opens.
2. Allow **Accessibility** access when asked (System Settings → Privacy & Security → Accessibility). It is needed to intercept the volume keys.
3. Allow **Local Network** access when asked. It is needed to find and talk to the soundbar.
4. Optional: Settings → *Launch at login*.

## How it works

- The volume keys are only intercepted while the Mac's audio output is an **HDMI** device. With any other output (built-in speakers, headphones, AirPlay …) macOS handles them as usual.
- The panel controls the soundbar over the network, so it works whatever the Mac's output is.
- The soundbar is found via Bonjour (`_bose-passport._tcp`) and controlled through its local WebSocket API (port 8082), the same way the Bose app does it.
- macOS also has its own digital volume for HDMI outputs (the slider in Control Center). It is independent of the soundbar volume; SoundbarKeys leaves it alone.

## Privacy

- No analytics, no tracking.
- Network traffic: the local connection to your soundbar, plus Bose's sign-in servers to refresh the token (the same servers the Bose app uses).
- A diagnostic log is written to `~/Library/Logs/SoundbarKeys.log`. For a short time after a volume key press it records *where* key presses go and which modifier keys are held – never which keys or characters you type.

## Tools

`tools/volume.py` is a small command line tool for testing: `get`, `set N`, `up`, `down`, `mute`, `unmute`, `listen`, `refresh`.

## Development

See [CONTRIBUTING.md](CONTRIBUTING.md) for the coding rules. Before a commit:

```sh
python3 tools/check_conventions.py   # convention check
cd App && swift test                  # unit tests of the pure logic (requires Xcode)
```

## Credits

The soundbar API and the Bose sign-in flow were documented by [pybose](https://github.com/cavefire/pybose) (GPLv3), which the login tool uses.

## License

[GNU General Public License v3.0](LICENSE)

## Support

If SoundbarKeys is useful to you, you can [buy me a coffee on Ko-fi](https://ko-fi.com/niko11111) ☕
