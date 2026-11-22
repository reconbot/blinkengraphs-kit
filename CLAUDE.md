# blinkengraphs-kit

The Swift package the iOS and macOS apps share. Product `BlinkengraphsCore`: Probe stats, Hop Trace, Meter scaling, History, Defaults and the Verdict, Foundation only, so `swift test` runs on Linux. Platform code (Network.framework, IOKit, SwiftUI) stays in the apps. A new module for code both apps share is a new product here, not a new repo (ADR 0001).

The spec repo, reconbot/blinkengraphs, is the authority. It is checked out at `spec/` as a submodule on a release tag; `swift test` runs every vector against this code. Bump the submodule in a PR when the spec releases (spec `docs/sync.md`). An app can test this package against its own spec pin with `BLINKENGRAPHS_SPEC=<path> swift test`.

A rule an app needs starts as a spec PR. A departure one app needs for its normal use (spec ADR 0002) lives in that app, not here.

Project memory lives in the repo: decisions `docs/adr/`. Record learnings there.

Skills (`mattpocock-skills`): `domain-modeling` when a term or decision changes, `codebase-design` when shaping a module interface, `tdd` for features and fixes, `writing-for-agents` for any doc or CLAUDE.md edit.

Comments carry only what code can't: the why, the platform gotcha, the source URL. Prose earns each sentence.

Commits follow Conventional Commits; release-please cuts tags from them, and the apps pin a tag. A change to a public API that breaks an app is `feat!:`.

Commits, PRs and comments stay free of session links and personal or employer details; the repo is public.

Never force-push `main` once the repo has a release.

Release PRs (release-please) merge only after the owner has reviewed them and said so. Feature PRs merge when tests pass.
