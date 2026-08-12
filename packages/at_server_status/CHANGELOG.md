## 1.1.2

- chore: drop the `dart:io` import from `AtStatus` by replacing the five
  `HttpStatus` constants it used (`ok`, `found`, `notFound`,
  `serviceUnavailable`, `internalServerError`) with local `int` constants of
  identical value. `httpStatus()` already returned a plain `int`, so no public
  API or returned value changes — this removes `dart:io` from the package's
  import graph, which is what kept it off a web build graph. Note that
  at_server_status still cannot *run* on the web: `AtStatusImpl` reaches the
  atDirectory and atServer through `AtLookupImpl`, which uses TLS sockets.

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
