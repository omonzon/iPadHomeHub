A wall-panel dashboard for an iPad, built to be sideloaded onto an old device
and left plugged in.

## What's in it

- **Clock and weather** — Open-Meteo, no account and no API key
- **Agenda** — the calendars already on the iPad, via EventKit
- **Home** — Home Assistant tiles over its REST API; HomeKit accessories and
  scenes in builds made with the `--homekit` flag
- **Chores and notes** — a family whiteboard, stored locally as JSON
- **Screensaver** — a photo slideshow with a large clock, after an idle delay
- **Assistant** — a full-screen Gemini panel that receives the hub's current
  state, so "do I need a jacket?" and "what's on today?" answer against real
  data

The layout adapts to the available width: three columns on a 12.9" in
landscape, two below 1150pt, one below 800pt.

## Installing

**The `.ipa` below is unsigned on purpose.** [AltStore](https://altstore.io) or
[SideStore](https://sidestore.io) re-signs it with your own Apple ID at install
time, so there are no certificates to manage and nothing to configure.

- AltStore needs **AltServer 1.7.6 or newer**, which requires macOS 11 or a
  Windows PC. Since September 2026, Apple rejects sign-in from older AltServer
  builds, including 1.6.2, the last one for macOS Catalina.
- AltStore renews the 7-day signature over Wi-Fi while AltServer is running on
  the same network. For an iPad somewhere else, use SideStore, which refreshes
  on-device after a one-time pairing.

Requires **iPadOS 15 or later** — iPad Air 2 and iPad mini 4 are the oldest
models that reach it.

HomeKit is not compiled into this build: its entitlement is only issued to paid
Apple Developer accounts. Home Assistant covers the same accessories.

## First run

Everything is configured on-device from the gear icon — weather location,
Home Assistant URL and token, Gemini API key, screensaver album. Tokens are
stored in the iPad's Keychain.
