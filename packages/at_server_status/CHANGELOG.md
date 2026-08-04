## 2.0.0

- breaking: requires `at_lookup: ^4.0.0`. `AtLookupImpl` is no longer exported
  from at_lookup, and its static `findSecondary` is gone: `_getRootStatus` now
  uses `SecondaryUrlFinder.findSecondaryUrl` and `_getServerStatus` builds its
  probe connection with `AtLookUp.legacy`. No public API of this package
  changes — `AtStatusImpl`, `AtStatus` and the three status enums are as they
  were.
- chore: detached from the pub workspace with path overrides on `at_lookup` and
  `at_chops` until both 4.0.0 releases are published; the rest of the repo keeps
  resolving hosted at_server_status 1.x.

## 1.1.1

- fix: Make this work properly with atServer proxy services

## 1.1.0

- chore(deps): remove unused dependencies
- chore(deps): move uuid to dev_dependencies

## 1.0.5

- build[deps]: Upgraded dependencies for the following packages:
  - at_commons to v5.0.0
  - at_utils to v3.0.19
  - at_lookup to v3.0.49

## 1.0.4

- build[deps]: Upgraded dependencies for the following packages:
    - at_commons to v4.0.0
    - at_utils to v3.0.16
    - at_lookup to v3.0.44

## 1.0.3

- rsdk uptake and at_lookup version change.

## 1.0.2

- at_commons version change

## 1.0.1

- at_commons version change

## 1.0.0

- upgrade to null safety

## 0.1.0+2

- upgraded packages to resolve dependency issues

## 0.1.0+1

- changes to ensure example gets found by pub.dev

## 0.1.0

- Initial checkin
