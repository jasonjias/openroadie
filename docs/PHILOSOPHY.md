# OpenRoadie Philosophy

This document explains what game OpenRoadie is playing, so contributors and
users can decide whether to invest in it with full information. These are
settled decisions, not open questions.

## What is open, and why

**OpenRoadie Core** — the reusable driving-context machinery — is open source
(Apache 2.0): location and GPS context, trip state and recording, local
storage and data formats, driving primitives, context interfaces, and the
eventual tool/plugin protocol and SDK. Today Core lives inside this repo as an
architectural boundary (`Driving/`, `Storage/` know nothing about UI or AI);
it becomes a separate public Swift package when a second consumer or outside
developer actually needs one, not before.

**The OpenRoadie app** — the flagship consumer driving copilot — is also open
source, permanently. It is a complete, useful product, and simultaneously:

- the reference implementation proving what Core can do
- the privacy proof: for an app that watches your location, "read the source"
  beats "trust our policy"
- the project's distribution: for an open project, GitHub, word of mouth, and
  trust are the acquisition channel

## No crippleware

The open app is never artificially limited to manufacture a reason to pay.
OpenRoadie is free, useful, local-first software: use it forever, fork it,
build on it. Anything paid must be something that *naturally* costs money or
solves a genuinely different problem — hosting and sync, operations, App Store
convenience, or specialized commercial products.

## Your data is yours

Driving data stays on your device by default. Nothing is uploaded unless you
explicitly choose it, and anything you store is yours to export or delete.
This is an architectural commitment, not a settings toggle.

## Commercial children

Core is a foundation other products can grow from — a fleet copilot, an OEM
integration, enterprise products, or things nobody has thought of yet. Each
child makes its own licensing decision based on where its value lives; the
flagship being open does not obligate its siblings, and some children may
benefit from being open themselves. The rule of thumb:

- Same user, same workflow → a feature or mode of the app.
- Different customer, different workflow, different economics → potentially a
  separate product.

Third-party developers are welcome to build their own children on Core,
open or closed, subject only to the Apache 2.0 license terms.

## The decision rule

Open what increases adoption, extension, inspection, and trust.
Commercialize where genuine economic value is created — operations, services,
and specialized products — never by closing what the community already relies
on. The goal is not to maximize closed code; it is to use openness as
distribution, trust, and opportunity discovery, and to build honest businesses
around the valuable problems that surface.

## Naming

The code is Apache 2.0; the OpenRoadie name identifies this project and its
official builds. Forks are welcome and expected — under their own names.
