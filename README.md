# Home Hub

A wall-panel dashboard for an iPad, built as a native SwiftUI app so it can be
sideloaded onto an old device and left plugged in forever.

Built and tested against a 12.9" iPad Pro. The deployment target is **iOS 15.0**,
which covers both the 1st-gen 12.9" (stuck on iPadOS 16.7) and the 2nd-gen
(iPadOS 17.x).

## What's on the screen

| Panel | Source | Needs |
| --- | --- | --- |
| Clock | on-device | — |
| Weather (now, 12h, 5-day) | [Open-Meteo](https://open-meteo.com) | nothing — no account, no API key |
| Agenda | EventKit | calendar permission on the iPad |
| Home | Home Assistant REST API | base URL + long-lived access token |
| Home | HomeKit | opt-in build flag + a **paid** Apple Developer account |
| Chores | local JSON file | — |
| Notes | local JSON file | — |
| Assistant | Google Gemini | an API key from [aistudio.google.com](https://aistudio.google.com) |
| Screensaver | PhotoKit | photo permission |

The assistant is a full-screen ask-anything panel. It is handed a short summary
of what the hub currently knows — time, weather, the next few calendar events,
open chores — so household questions ("do I need a jacket?", "what's on today?")
get answered against real data instead of guesses.

## Install without a Mac (or with an old one)

A Mac that can't run Xcode 15 — anything pre-2014, which caps out at macOS
Catalina — can still put this on an iPad. Building and installing are separate
problems, and only the first one needs a modern Mac.

1. **CI builds the `.ipa`.** `.github/workflows/build.yml` builds on a GitHub
   macOS runner and uploads the result as an artifact. It builds *unsigned* on
   purpose — no certificates, no secrets. Grab it from the run's Artifacts
   section, or push a `v*` tag to get it attached to a Release as a plain
   download link.
2. **[AltStore](https://altstore.io) installs it.** AltServer runs on macOS
   10.14.4+, so Catalina is fine. It re-signs the app with your own Apple ID at
   install time, which is why the CI build doesn't need to sign anything.
3. **It refreshes itself.** AltStore renews the 7-day signature over Wi-Fi as
   long as AltServer is running on the same network. If that machine is a
   home server that's always on, the app just keeps working — no cable, no
   monthly ritual, no $99.

[SideStore](https://sidestore.io) does the same refresh on-device with no
computer at all after a one-time pairing, if you'd rather not depend on a Mac
being awake.

The catch: HomeKit needs an entitlement only issued to paid developer accounts,
and AltStore can't conjure one. Home Assistant covers the same ground through
its API, so in practice you lose little.

## Build and install with Xcode

You need a Mac with Xcode 15 or newer, and a Lightning/USB-C cable.

### 1. Generate the Xcode project

The `.xcodeproj` is generated rather than hand-maintained. Pick a bundle
identifier that is unique to you — `com.example.homehub` will collide with
somebody and refuse to sign.

```sh
python3 Scripts/generate_project.py --bundle-id com.yourname.homehub
open HomeHub.xcodeproj
```

Re-run the same command any time you add or delete a source file.

### 2. Sign it

In Xcode: select the **HomeHub** target → **Signing & Capabilities** →
tick *Automatically manage signing* and choose your team.

- **Free Apple ID** — works, but the app stops launching after **7 days** and
  you have to rebuild. Free accounts also cannot use the HomeKit entitlement.
- **Paid Apple Developer Program** ($99/yr) — signs for a year, and unlocks
  HomeKit.

### 3. Run it on the iPad

1. Plug the iPad in, unlock it, tap **Trust This Computer**.
2. Pick the iPad from Xcode's device menu and press ⌘R.
3. First launch will fail with an untrusted-developer error. On the iPad go to
   **Settings › General › VPN & Device Management**, tap your developer
   certificate, and **Trust** it. Launch again.

Older iPads can take a few minutes on the first install while Xcode copies over
symbol files. That's normal and only happens once per iOS version.

### 4. Enable HomeKit (optional, paid account only)

```sh
python3 Scripts/generate_project.py --bundle-id com.yourname.homehub --homekit
```

The CI workflow takes the same option — run it manually from the Actions tab
and tick *homekit*.

Then in Xcode add the **HomeKit** capability to the target. The flag sets
`HOMEHUB_HOMEKIT`, which compiles in `HomeKitService` and the HomeKit tiles;
without it, none of that code is built, so a free-account sideload still works.

## Set it up

Everything is configured on-device — tap the gear in the top right.

- **Weather** — search for your town; it stores the coordinates, not the name.
- **Home Assistant** — base URL is the LAN one, e.g.
  `http://homeassistant.local:8123`. Create the token in Home Assistant under
  your profile → *Security* → *Long-lived access tokens*. Hit **Test
  connection**, then pick which entities get a tile.
- **Assistant** — paste a Gemini API key. Default model is
  `gemini-2.5-flash`; change it in the same section.
- **Screensaver** — name an album (or leave it blank for the whole library) and
  set the idle delay. `0` disables it.

Tokens and API keys go in the iPad's Keychain, not `UserDefaults`. That still
means anyone holding the unlocked iPad can use them, which is fine for a device
on your own wall — but put a spending cap on the Gemini key, and give the Home
Assistant token only the access you're comfortable with.

## Leaving it on a wall

- **Settings › Display & Brightness › Auto-Lock → Never.** The app also sets
  `isIdleTimerDisabled`, but the system setting is the reliable one.
- **Guided Access** (Settings › Accessibility) locks the iPad to this one app so
  a guest can't wander off into Safari. Triple-click the side button to arm it.
- Leave it on a charger. A permanently-plugged old iPad will swell its battery
  eventually; if the device is a spare, that's the trade.
- The hub polls Home Assistant every 5 seconds and refreshes weather every 10
  minutes, so it wants Wi-Fi but survives losing it — panels keep their last
  values and the tiles show `offline`.

## Layout of the code

```
.github/workflows/
  build.yml             builds an unsigned .ipa on a macOS runner
HomeHub/
  HomeHubApp.swift        app entry, keeps the screen awake
  RootView.swift          three-column dashboard, refresh heartbeat, screensaver
  Theme.swift             colors and the shared panel chrome
  Config/                 settings model, settings UI, Keychain wrapper
  Models/                 chores, notes, weather, Home Assistant entities
  Services/               one per backend: weather, calendar, HA, HomeKit,
                          Gemini, photos, local board storage
  Panels/                 one file per panel on the dashboard
  Resources/              Info.plist, entitlements, asset catalog
Scripts/
  generate_project.py     writes HomeHub.xcodeproj
  make_icon.py            renders the app icon set from code
```

`make_icon.py` regenerates every icon size from a few polygons — no binary
design file to lose. Run it if you want to change the icon:

```sh
python3 Scripts/make_icon.py
```
