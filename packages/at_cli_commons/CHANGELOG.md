## 1.2.1
- fix: fix impl of `standardAtClientStoragePath`

## 1.2.0
- feat: Add `standardAtClientStoragePath` and `standardAtClientStorageDir` 
  to utils.dart

## 1.1.0

- feat: Add `maxConnectAttempts` parameter to CLIBase. The default is 20,
  i.e. 20 attempts to connect, with a 3-second delay between attempts. When 
  used in scripts this is important, as the previous behaviour (retry 
  forever) is usually not what is required.

## 1.0.5

- fix: Make CLIBase write progress messages to stderr, not stdout

## 1.0.4

- fix: handle malformed atsigns (no leading `@`) in CLIBase constructor
- build: updated dependencies

## 1.0.3

- Added `example/` package, moved code samples from `bin/` to `example/`

## 1.0.2

- docs: Added some code samples in bin/ directory
- docs: Added some class and method documentation to CLIBase
- docs: Updated README
- feat: Added static `fromCommandLineArgs` factory method to CLIBase

## 1.0.1

- Small edits to README

## 1.0.0

- Initial version.
