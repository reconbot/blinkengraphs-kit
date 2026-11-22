# blinkengraphs-kit

The Swift package shared by the [iOS](https://github.com/reconbot/blinkengraphs-ios) and [macOS](https://github.com/reconbot/blinkengraphs-mac) apps: the [spec](https://github.com/reconbot/blinkengraphs)'s rules in Swift, verified by its vectors.

## Use

```swift
.package(url: "https://github.com/reconbot/blinkengraphs-kit", exact: "1.0.0"),
// target dependency:
.product(name: "BlinkengraphsCore", package: "blinkengraphs-kit"),
```

## Test

```sh
git submodule update --init
swift test                                   # against the pinned spec
BLINKENGRAPHS_SPEC=../spec swift test        # against another spec checkout
```

Runs on macOS and Linux (Swift 6).

## Repositories

| Repo | Contents |
|---|---|
| [blinkengraphs](https://github.com/reconbot/blinkengraphs) | Landing page and shared spec |
| [blinkengraphs-win](https://github.com/reconbot/blinkengraphs-win) | Windows 11 app (Rust) |
| [blinkengraphs-mac](https://github.com/reconbot/blinkengraphs-mac) | macOS menu bar app (planned) |
| [blinkengraphs-ios](https://github.com/reconbot/blinkengraphs-ios) | iOS network diagnosis app |
| [blinkengraphs-kit](https://github.com/reconbot/blinkengraphs-kit) | Swift package shared by the iOS and macOS apps |
