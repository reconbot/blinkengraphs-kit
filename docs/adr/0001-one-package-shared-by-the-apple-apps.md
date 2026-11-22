# One Swift package, shared by the iOS and macOS apps

**Status:** accepted

`BlinkengraphsCore` began inside blinkengraphs-ios. The macOS app needs the same Verdict, Probe stats, Hop Trace and History code, in the same language. It moved here, with its history, so both apps import one copy.

- **One repo, several products.** Code both apps share becomes a new library product in this package. Every product versions under one tag, so an app never mixes versions of the shared code.
- **Foundation only in `BlinkengraphsCore`.** `swift test` then runs every spec vector on Linux. A product that needs Apple frameworks, such as Network.framework probes, is a separate product so the core stays portable.
- **The spec's "no shared code" stance still holds across languages.** [spec `docs/cross-platform.md`](https://github.com/reconbot/blinkengraphs/blob/main/docs/cross-platform.md) rejects a Rust core behind FFI; sharing Swift between two Swift apps carries no FFI cost.

## Considered options

- **The macOS app depends on blinkengraphs-ios.** Rejected: every macOS release would move with an iOS tag, and the package would drag an app repo along.
- **Each app keeps its own copy.** Rejected: two copies of the same Swift to keep passing the same vectors.

## Consequences

- An app pins a kit tag and a spec tag. Its CI runs this package's tests against its own spec pin (`BLINKENGRAPHS_SPEC`), so the two never drift unnoticed.
- A spec release reaches the apps in two steps: a kit PR that bumps `spec/` and passes the vectors, then an app PR that bumps both pins.
