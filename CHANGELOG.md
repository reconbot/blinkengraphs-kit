# Changelog

## [2.0.0](https://github.com/reconbot/blinkengraphs-kit/compare/v1.0.0...v2.0.0) (2026-11-23)


### ⚠ BREAKING CHANGES

* VerdictInput.sample is a Sample, not [String: Double].

### Features

* History that crashes launch twice in a row is deleted (reconbot/blinkengraphs-ios[#44](https://github.com/reconbot/blinkengraphs-kit/issues/44)) ([091a784](https://github.com/reconbot/blinkengraphs-kit/commit/091a7840aada1a78d03df883a553338f1f776b1e))
* the Local rules read platform-neutral Metrics (spec 6.0.0) ([#2](https://github.com/reconbot/blinkengraphs-kit/issues/2)) ([4703f0a](https://github.com/reconbot/blinkengraphs-kit/commit/4703f0a90d4b5e1a96e0f5ec4319d87b8c682f76))


### Bug Fixes

* launch no longer crashes when no History is saved yet (reconbot/blinkengraphs-ios[#42](https://github.com/reconbot/blinkengraphs-kit/issues/42)) ([300ef01](https://github.com/reconbot/blinkengraphs-kit/commit/300ef01e3ab983e933dfda9db388b786e3ea5ecd))

## 1.0.0 (2026-11-23)


### Features

* BlinkengraphsCore as a standalone package, shared by the iOS and macOS apps ([9496f3a](https://github.com/reconbot/blinkengraphs-kit/commit/9496f3ad86ec891f04b2119e02d01372f235de53))
