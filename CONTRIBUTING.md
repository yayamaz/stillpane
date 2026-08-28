# Contributing

stillpane is Swift 6, macOS 14+, zero third-party dependencies, and stays that way.

## Build and test

    swift build
    swift test
    ./scripts/build-app.sh    # -> dist/stillpane.app

## Formatting

Code style is enforced by `swift format` (part of the Swift 6 toolchain) with the repo's `.swift-format`.
CI rejects unformatted code; to check or fix locally:

    find Sources Tests -name '*.swift' ! -name 'Wordmark.swift' -print0 \
      | xargs -0 swift format lint --strict --parallel Package.swift
    find Sources Tests -name '*.swift' ! -name 'Wordmark.swift' -print0 \
      | xargs -0 swift format --in-place --parallel Package.swift

`Wordmark.swift` is generated and stays exactly as emitted.

## Ground rules

- Open an issue before a large change so the direction is agreed first.
- Behavior changes come with tests, and `swift test` passes before review.
- No new dependencies.

## License and CLA

Contributions are released under [Apache-2.0](LICENSE) like the rest of the project.
Your first pull request will ask you to sign the contributor license agreement ([CLA.md](CLA.md)).
Signing is a single comment, happens once, and covers all future contributions.
