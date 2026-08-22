## 1.1.2-rc1

- refactor: builds its lookup with `AtLookUp.withSecureSocket`, passing
  `authenticator: null` - every call it makes is `auth: false` and it holds no
  key material at all.
- refactor: drops `AtLookupImpl.findSecondary` for
  `CacheableSecondaryAddressFinder`, which that deprecated static was a thin
  wrapper over. The finder is constructed **inside** the future deliberately:
  the wrapper did its own `rootDomain!`, so a null root domain surfaced as a
  rejected future and became `RootStatus.unavailable`. Asserting at the call
  site instead would throw before `catchError` is attached and turn an
  unavailable root into an uncaught exception.
- build: `at_lookup` `^3.0.49` -> `^3.7.0-rc1`, and `at_commons` becomes a direct
  dependency. Both were needed by the change above and both were being
  satisfied by workspace resolution, which hides the problem locally: a
  consumer resolving the published package would have got an at_lookup with no
  `withSecureSocket` in it.

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
