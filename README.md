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

## Screen sizes

The dashboard picks its layout from the available width, not the device, so a
12.9" in portrait and a 10.2" in landscape get the same treatment:

| Width | Layout | Typical |
| --- | --- | --- |
| ≥ 1150pt | three columns | 12.9" / 11" landscape |
| ≥ 800pt | two columns, page scrolls | 12.9" portrait, 9.7" / 10.2" landscape |
| < 800pt | single column | smaller iPads in portrait |

Anything back to an iPad Air 2 or iPad mini 4 will run it — those are the oldest
models that reach iPadOS 15. An iPad Air 1 or iPad 4 and older cap out at
iOS 12 and cannot.

## Install without a current Mac

Building and installing are separate problems, and only building needs a
modern Mac — which CI provides. `.github/workflows/build.yml` builds on a
GitHub macOS runner on every push. What it produces depends on whether signing
secrets are configured.

### Ad hoc signed (paid developer account) — best for a wall device

With an Apple Developer Program membership, CI signs the `.ipa` for the
specific iPads registered in the profile. It installs by dragging it onto the
iPad in Finder, stays valid for a year, and needs no AltStore, no weekly
refresh and no Developer Mode.

The membership doesn't have to be yours, and its holder doesn't have to be
anywhere near the iPad — everything on their side happens in a browser, and the
private key never leaves your Mac:

1. **You:** copy the iPad's UDID from Finder (click the grey line under the
   device name until it shows the UDID). Create a certificate signing request
   in Keychain Access › Certificate Assistant › *Request a Certificate From a
   Certificate Authority* › *Saved to disk*. Send both — neither is secret.
2. **Account holder, on developer.apple.com:** register the UDID under
   *Devices*; create an explicit App ID under *Identifiers*; create an
   *Apple Distribution* certificate from your CSR; create an *Ad Hoc* profile
   for that App ID, certificate and device. Send back the `.cer` and the
   `.mobileprovision` — neither is secret without your private key.
3. **You:** double-click the `.cer` to pair it with your key, then in Keychain
   Access › *My Certificates* export it as a `.p12` with a password.
4. **Add three repository secrets** (*Settings › Secrets and variables ›
   Actions*):

   ```sh
   base64 -i Certificates.p12 | pbcopy          # paste as SIGNING_CERT_P12
   base64 -i HomeHub_AdHoc.mobileprovision | pbcopy   # paste as ADHOC_PROFILE
   ```

   plus `SIGNING_CERT_PASSWORD`. The team and bundle IDs are read from the
   profile, so there is nothing else to keep in sync.

The next build uploads `HomeHub-adhoc-ipa`. Renew once a year by repeating
steps 1–4. If the profile carries the HomeKit entitlement, HomeKit is compiled
in automatically. Releases stay unsigned: a signed `.ipa` embeds its profile,
which lists the registered devices.

### Unsigned + AltStore (free Apple ID)

Without secrets CI builds *unsigned*, and [AltStore](https://altstore.io)
re-signs the app with your own Apple ID at install time, renewing the 7-day
signature over Wi-Fi while AltServer runs on the same network.
[SideStore](https://sidestore.io) does the refresh on-device instead.

**This needs AltServer 1.7.6 or newer, and AltServer 1.7+ requires macOS 11.**
Since early September 2026 Apple's sign-in servers reject older AltServer
builds with *"The data is not in the correct format"*. AltServer 1.6.2 — the
last release for macOS 10.14 and 10.15 — cannot sign in any more, so a Mac on
Catalina can't use this route. A Windows PC with a current AltServer can.

HomeKit is not available this way: its entitlement is only issued to paid
developer accounts.

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
