# Changelog

## 1.0 – unreleased

First version.

- Volume up/down/mute keys control a Bose ECO2 soundbar (tested: Soundbar 700) while the Mac's output is HDMI
- Soundbar is discovered via Bonjour; reconnects after sleep and network changes
- Soundbar selection in the settings when there are several Bose devices (a fixed choice never falls back to another device)
- Menu bar panel with volume slider (Liquid Glass; uses the macOS 27 expanded status item interface when available)
- Configurable maximum volume and step size; launch at login
- Sound mode switch (e.g. Normal / Dialogue) in the panel, only with modes the soundbar supports
- Quiet hours: a lower maximum in a daily time window; a louder soundbar is turned down when they begin
- On-screen volume indicator in the style of macOS 26: top right, bottom center or off
- Sign-in on Bose's own page in a small web window (the app does not read the form), sign-out; automatic token refresh
- English and German
