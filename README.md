# OpenRoadie

**An open-source AI copilot for the road.**

OpenRoadie gives AI awareness of your drive: where you are, what road you're on, how fast you're going, what's around you, and what's happening along the way.

It combines phone telemetry, open map data, local AI, and agent tools to create a driving copilot that works alongside the navigation system you already use.

## The idea

Your phone already knows a lot while you're driving:

- Location
- Speed and heading
- Motion
- Trip duration and distance

Open map data can add:

- Roads and speed limits
- Nearby landmarks
- Restaurants and coffee
- Gas stations
- EV chargers
- Other points of interest

OpenRoadie turns this information into a common driving context that an AI agent can understand and act on.

Ask things like:

> "Where am I?"

> "How fast am I going?"

> "What's around here?"

> "Find a charger nearby."

> "What's that landmark?"

> "Tell me when I'm 10 over the speed limit."

## Principles

- **Open source** — Apache 2.0
- **Local first** — your driving data stays on your device by default
- **Free by default** — use on-device models and open data where possible
- **Model agnostic** — use the system model or bring your own
- **Navigation agnostic** — designed to complement Apple Maps, Google Maps, Waze, and in-car navigation
- **Extensible** — telemetry, maps, models, rules, and integrations should be pluggable

## Status

🚧 **Very early development.**

The first goal is simple:

**Make an iPhone understand the drive, then give an AI access to that context.**

Initial development is focused on iOS using Core Location, Core Motion, OpenStreetMap, and Apple's on-device Foundation Models.

Android and additional integrations can follow as the core architecture develops.

## Building and running

Requirements: Xcode 26 or later, an iPhone running iOS 26 or later (or the iOS 26 simulator).

1. Open `OpenRoadie.xcodeproj` in Xcode.
2. Create `Config/Local.xcconfig` (gitignored) containing `DEVELOPMENT_TEAM = YOURTEAMID` — any free Apple ID's Personal Team works (Xcode → Settings → Accounts). Alternatively pick your team under *Signing & Capabilities*, just don't commit that change.
3. Select your iPhone as the run destination and press Run.
4. Tap **Start Drive** and grant location access ("Allow While Using App") when prompted.

Run the tests with **Product → Test**, or:

```
xcodebuild -project OpenRoadie.xcodeproj -scheme OpenRoadie \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

### Architecture (Milestone 1)

```
CoreLocation ─▶ LocationService ─▶ DriveSessionManager ─▶ DrivingContext ─▶ SwiftUI
                                          │
                                     TripTracker
                              (deterministic, unit-tested)
```

- `Driving/DrivingContext.swift` — the canonical snapshot of what OpenRoadie knows about the drive. Unknown values are `nil`, never invented.
- `Driving/TripTracker.swift` — pure logic that turns raw GPS fixes into a `DrivingContext`: filters poor-accuracy samples, ignores stationary drift and GPS glitches, accumulates distance.
- `Driving/LocationService.swift` — thin wrapper over CoreLocation's session APIs (`CLServiceSession`, `CLBackgroundActivitySession`, `CLLocationUpdate.liveUpdates`). Telemetry continues while another app is foregrounded or the phone is locked during an active drive.
- `Driving/DriveSessionManager.swift` — owns the Start Drive / Stop Drive lifecycle; the single object the UI observes.
- `Driving/ParkDetector.swift` — decides what a stopped car means. Stopping *pauses* a drive; recording continues and moving again resumes the same drive, so a gas stop or a jam can't chop one drive into several. Only a long settled stop ends it.
- `Storage/TripSegmenter.swift`, `Storage/PaceBands.swift` — pure analysis over a finished route: where to split a drive into legs, and where its time actually went. Because these run on read, "was that one trip or two?" is a reversible display decision rather than something recording has to get right live.
- `UI/` — a deliberately simple developer dashboard.

Driving data never leaves the device. There is no backend, no account, and no API key.

## Contributing

OpenRoadie is being built in the open.

Ideas, issues, experiments, integrations, and pull requests are welcome.

Potential areas include:

- Driving telemetry
- OpenStreetMap and routing
- Speed limits and road context
- EV charging
- Traffic and hazards
- Apple Watch / Wear OS
- OBD-II
- CarPlay / Android Auto
- Local and cloud AI models
- Voice
- Driving safety
- Android

## License

Apache License 2.0
