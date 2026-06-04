## 1.2.0

- **DEPRECATED**: This is the final minor release of
  `at_sync_ui_flutter`. New Flutter apps should use `AtCollection<T>` and
  `Query.watch()` from `at_client` instead of foreground sync progress UI.
- **DOCS**: Added migration guidance pointing to the collection CLI examples
  in `packages/at_client/example/bin/collections_*.dart` and the Flutter
  todos reference app in `packages/at_client_flutter/examples/todos`.
- **CHORE**: Added deprecation annotations to the public API surface while
  keeping existing APIs available for compatibility.

## 1.1.0

- chore(deps): at_client ^3.7.0
- chore(deps): at_client_mobile ^3.3.0
- chore(deps): at_common_flutter ^2.1.0 and move to dev_dependencies

## 1.0.14

- **FIX** Replace depreciated `withOpacity` method with `withValues`.
- build[deps]: Upgraded dependencies for the following packages:
  - flutter_lints: 5.0.0

## 1.0.13:

- build[deps]: Upgraded dependencies for the following packages:
  - at_client: 3.2.2
  - at_client_mobile: 3.2.19

## 1.0.12:

- **FIX**: Resolved Static analysis messages
- **CHORE**: Updated dependencies
- **CHORE**: Updated kotlin version number

## 1.0.11:

- **CHORE**: Bumped up dependecy versions
- **CHORE**: Improved pub score

## 1.0.10

- **CHORE**: Updated dependencies
- **CHORE**: Lint fixes

## 1.0.9

- **CHORE**: Bumped all dependency versions
- **REFACTOR**: Deprecated `sync()` method and moved it's implementation to init.
- **CHORE**: Improved pub score

## 1.0.8

- **FEAT**: Provides exit option when sync takes longer

## 1.0.7

- **CHORE**: Updated dependencies and android gradle versions

## 1.0.6

- **FEAT**: Sync progress callback added
- **CHORE**: Package description updated

## 1.0.5

- **FEAT**: Updated dependency

## 1.0.4

- **FEAT**: Added atSyncUIListener, to listen to sync status changes

## 1.0.3

- **FIX**: Lint Fixes according to flutter 3.0

## 1.0.2

- **CHORE**: Updated dependencies
- **DOCS**: Updated documentation

## 1.0.1

- **FEAT**: Added sdk support
- **DOCS**: Updated documentation

## 1.0.0

- Initial release
- **FEAT**: UI widgets that can be used as sync indicators
