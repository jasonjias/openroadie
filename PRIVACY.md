# OpenRoadie Privacy

Short version: your driving data stays on your iPhone. OpenRoadie has no
account and no server for your data. Nothing about your trips is uploaded to
the developer, because there is nowhere for it to go.

This document is checked against the source code in this repository. Every
claim below is something you can verify by reading the code.

## What stays on your phone

Everything OpenRoadie records about you lives only on the device, in a local
database (SwiftData) and in the app's settings:

- Trips: routes, speed, distance, the road and its speed limit, events like
  hard braking.
- Walks and stops, and the breadcrumb trails of walks the app recorded.
- Weather and air quality stamped on each drive.
- Driving notes you dictate.
- Your settings.

None of this is sent to the developer. There is no OpenRoadie account, no
login, and no backend that receives your trips.

## What leaves your phone, to whom, and why

OpenRoadie talks to a few public services to look things up. In each case it
sends an approximate location (and sometimes a date), and gets back public
information. It does not send your name, an account ID, or your stored trips.

| Service | Host | What is sent | Why |
|---|---|---|---|
| OpenStreetMap (Overpass) | overpass-api.de, overpass.kumi.systems, overpass.private.coffee | a map area around you | the road you are on, speed limits, nearby places |
| Open-Meteo | api.open-meteo.com, archive-api.open-meteo.com, air-quality-api.open-meteo.com | a coordinate and a date | weather and air quality for a drive |
| U.S. National Weather Service | api.weather.gov | a coordinate | severe-weather alerts while driving |
| Apple (reverse geocoding) | Apple's servers (CLGeocoder) | a coordinate | the name of a place you stopped |
| Apple (place search) | Apple's servers (MKLocalSearch) | a search term and area | nearby food, coffee, gas, chargers |

Each of these can be turned off and the rest of the app keeps working. Road
and weather lookups have Settings toggles. With them off, OpenRoadie makes no
network calls of its own.

### The AI assistant (Roadie)

By default, Roadie runs on Apple's on-device model. Your questions are
answered on the phone and are not sent anywhere.

You can optionally point Roadie at your own AI endpoint (any
OpenAI-compatible service). If you do, your question text goes to the
endpoint you configure, and the API key you enter is stored in the device
Keychain, not in the app's files. This is off unless you set it up.

Voice ("Hey Roadie") is transcribed on the device using Apple's on-device
speech recognition. Your voice is not uploaded.

## Sensors and permissions, and exactly how they are used

- **Location (While Using, and optionally Always).** Live speed, heading, and
  trip distance; drawing your route. With Always access, OpenRoadie can start
  recording a drive on its own and keep a continuous breadcrumb trail. You can
  use While Using only, or turn drive detection off.
- **Motion & Fitness.** To tell driving from walking, to notice hard braking
  and cornering, and to read step count and distance for walks. Read on the
  device.
- **Microphone and Speech Recognition.** Only for "Hey Roadie" voice. Off by
  default. Transcribed on the device.
- **Photos.** Read only. To show photos you took during a drive on the trip
  map, placed where you took them. Photos are never copied or uploaded.
- **Apple Health.** Read only. To show your workouts and sleep in the Sessions
  timeline next to your drives. Read on the device.
- **Apple Music.** To search your music library when you ask Roadie to play a
  song.

## No tracking, no analytics, no ads

OpenRoadie contains no analytics, no crash reporting, no advertising, and no
third-party tracking SDKs. The app has zero third-party package dependencies.
It does not track you across apps or websites, and it collects no advertising
identifier.

## Logs

OpenRoadie writes only to the standard on-device system log (Apple's unified
logging), for its own diagnostics. These logs stay on the device and are not
sent to the developer.

## Deleting your data

Delete any trip from inside the app. Deleting the app removes everything
OpenRoadie stored, because it was all on the device.

## Contact

Questions about privacy: [@jasonjias on X](https://x.com/jasonjias).
