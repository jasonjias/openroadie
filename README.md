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
