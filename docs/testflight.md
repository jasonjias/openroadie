# Shipping OpenRoadie to TestFlight

This is the exact path from the repo to a TestFlight build. OpenRoadie is an
iPhone app with a Watch app and a widget extension, so it ships through
TestFlight and the App Store, not notarization.

## The one real blocker: a paid Apple Developer account

A local Release archive builds and signs fine with a **development**
identity. An **App Store export fails**:

```
error: exportArchive No Accounts
error: exportArchive No profiles for 'com.openroadie.OpenRoadie' were found
```

TestFlight needs an **Apple Distribution** certificate and App Store
provisioning profiles. Those exist only with a paid **Apple Developer
Program** membership ($99/year). A free personal team can install to your
own device for 7 days but cannot use TestFlight at all.

So step 1 is non-negotiable and only you can do it.

## What you must do (in order)

1. **Enroll in the Apple Developer Program.** developer.apple.com/programs,
   $99/year. Approval is usually same day, sometimes up to 48 hours. Use the
   Apple ID that owns your developer team.

2. **Sign in to Xcode.** Xcode > Settings > Accounts > add that Apple ID.
   This is what fixes the "No Accounts" error above and lets Xcode create
   the distribution certificate and App Store profiles automatically.

3. **Create the app record in App Store Connect.**
   appstoreconnect.apple.com > Apps > +.
   - Platform: iOS
   - Name: OpenRoadie (must be globally unique on the App Store)
   - Primary language: English (U.S.)
   - Bundle ID: `com.openroadie.OpenRoadie` (pick it from the list; if it is
     not there, Certificates, Identifiers & Profiles > Identifiers > + first,
     or let Xcode register it on the first upload)
   - SKU: any stable string, e.g. `openroadie-ios`

4. **Fill the required metadata.** TestFlight internal testing needs less
   than a full App Store submission, but you still need:
   - **Privacy policy URL** (required). A short page is enough. Suggested
     text is in the appendix below.
   - **App Privacy answers** (App Store Connect > App Privacy). Suggested
     answers in the appendix. Short version: OpenRoadie does not collect
     data. Everything stays on device.
   - **Export compliance:** already handled. `ITSAppUsesNonExemptEncryption`
     is set to `false` in Info.plist (the app uses only standard HTTPS,
     which is exempt), so no yearly compliance document is needed.

5. **Archive and upload from Xcode.**
   - Open `OpenRoadie.xcodeproj`, scheme OpenRoadie, Any iOS Device.
   - Product > Archive.
   - In Organizer: Distribute App > TestFlight & App Store Connect > Upload.
   - Automatic signing will create the distribution cert and profiles the
     first time.

6. **Add internal testers.** App Store Connect > your app > TestFlight >
   Internal Testing. Up to 100 internal testers, no App Review wait. They
   install the TestFlight app and accept the invite. External testing (wider
   group) does need a short review first.

**Do not** let anyone upload on your behalf. The upload is your account's
action and your go.

## What is already done in the repo

Verified and fixed on 2026-10-01 so the build is submission-clean:

- **App icons flattened.** Both the iPhone and Watch `AppIcon.png` had an
  alpha channel, which App Store Connect rejects. Both are now opaque
  1024x1024, artwork unchanged.
- **Encryption compliance key set.** `ITSAppUsesNonExemptEncryption = false`
  in `OpenRoadie/Info.plist`.
- **Privacy usage strings** are all present and in plain language:
  location (when-in-use and always), motion, microphone, speech
  recognition, photo library, Health (read only), Apple Music.
- **Background modes:** `location` and `audio`.
- **Bundle IDs:** `com.openroadie.OpenRoadie`, `.watchkitapp`, `.Widgets`.
- **Team:** `DEVELOPMENT_TEAM` lives in `Config/Local.xcconfig`
  (gitignored). A fresh clone recreates that file with its own team ID,
  same as the README says for device builds.
- **Release archive builds clean** with automatic signing.

### App Group: not needed

The widget is a Live Activity (ActivityKit). The app passes it state
directly through ActivityKit, so it does not read the app's data store and
no App Group is required. If a future Home Screen widget needs to read trip
data, that is when to add an App Group.

## Appendix: suggested privacy answers

**App Privacy questionnaire.** Data collection: "No, we do not collect data
from this app." OpenRoadie stores drives, walks, notes, and settings only on
the device. It sends an approximate coordinate to open map and weather
services (OpenStreetMap Overpass, Open-Meteo, the U.S. National Weather
Service) to look up roads, speed limits, and conditions, but keeps no server
account and uploads no personal data. If App Store Connect insists on listing
these, mark "Precise Location" used for "App Functionality," not linked to
identity, not used for tracking.

**Privacy policy, short form:**

> OpenRoadie keeps your driving data on your iPhone. Trips, routes, walks,
> notes, and settings are stored on the device and are never uploaded to us,
> because there is no "us": OpenRoadie has no server account and no backend
> for your data. To show the road you are on, speed limits, nearby places,
> and weather, the app sends your approximate location to public services
> (OpenStreetMap, Open-Meteo, the U.S. National Weather Service). The app
> reads workouts and sleep from Apple Health and photos from your library
> only to show them alongside your drives, on the device, and never copies or
> uploads them. You can delete any trip, and deleting the app removes
> everything.

Host it anywhere stable (a GitHub Pages page in this repo works) and put the
URL in App Store Connect.
