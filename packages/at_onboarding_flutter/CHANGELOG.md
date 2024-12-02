## 6.1.9
- build[deps]: Upgraded dependencies for the following packages:
  - at_client: 3.2.2
  - at_client_mobile: 3.2.19
  - at_auth: 2.0.7
  - at_commons: 5.0.0
  - at_utils: 3.0.19
## 6.1.8

- **CHORE**: Updated dependencies
- **CHORE**: Updated kotlin version
- **FIX**: Refactor "onboard" and "authenticate" methods to use "AtAuthService" instead of "AtClientService" which is introduced in at_client_mobile
- **FIX**: atClientServiceMap marked as depreciated
- **FIX**: 'enroll' method added
- **FIX**: lint issues fixes
- **FIX**: file_picker package replaced the use of file_selector on desktop.
- **FIX**: AtOnboarding.reset() functions correctly without requiring app restart.

## 6.1.7

- **CHORE**: Bumped all dependency versions
  - Major version increase of at_commons from ^3.0.55 to ^4.0.1

## 6.1.6

- **FIX**: Fixed file_selector issue on Windows

## 6.1.5

- **CHORE**: Updated tutorial_coach_mark from 1.2.9 to 1.2.11

## 6.1.4

- **CHORE**: Bumped all dependency versions
  - Major version increase of permission_handler from ^10.4.3 to ^11.0.0
  - Major version increase of file_selector from >=0.8.4+3 <=1.0.0 to ^1.1.0

## 6.1.3

- **CHORE**: Updated at_client_mobile package to fix onboarding issue on Windows

## 6.1.2

- **CHORE**: Update to support Dart 3

## 6.1.1

- **FIX**: Updated error messages

## 6.1.0

- **FEAT**: Internationalization support added for French
- **FIX**: Issue fixed in UI theme

## 6.0.3

- **CHORE**: Upgrade dependencies for at_chops uptake

## 6.0.2

- **FIX**: Added assets path in yaml

## 6.0.1

- **FIX**: Fixed issue in atSign activation process
- **CHORE**: Exported at_client_mobile dependency

## 6.0.0

- **CHORE**: Updated file_picker and webview_flutter dependency

## 5.0.5

- **FIX**: Fixed atSign activation issue

## 5.0.4

- **CHORE**: Updated dependencies and readme

## 5.0.3

- **CHORE**: Updated dependencies,readme and gradle version.
- **FIX**: Resolved android build issue.

## 5.0.2

- **CHORE**: Updated dependencies

## 5.0.1

- **FIX**: Windows onboarding issue resolved

## 5.0.0

- **FEAT**: Updated UI flow
- **FEAT**: Updated Keychain data structure dependency

## 4.0.4

- **FIX**: Bug fixes in atSign activation process

## 4.0.3

- **FIX**: Lint Fixes according to flutter 3.0

## 4.0.2

- **FIX**: Added missing fontWeight

## 4.0.1

- **CHORE**: Updated dependencies
- **FEAT**: Added ability to select files without extension.

## 4.0.0

- **CHORE**: Updated dependencies
- **BREAKING CHANGE**: at_backupkey_flutter exposed in this package has breaking change - removed redundant, required parameter `atClientService`.

## 3.1.4

- **DOCS**: Updated documentation
- **CHORE**: Updated dependencies

## 3.1.3

- **FIX**: Fixed [sending OTP inconsistency](https://github.com/atsign-foundation/at_widgets/issues/236) bug.

## 3.1.2

- **FIX**: Fixed at_client dependency issue
- **FIX**: Fixed lint errors

## 3.1.1

- **CHORE**: Update a dependency to the latest release.

## 3.1.0

- **FEAT**: Added support for macos, windows and linux platforms

## 3.0.4

- **FEAT**: Added hide qr scan to hide qr scan in custom dialog

## 3.0.3

- **FIX**: Resolved Qr scanning issue in ios

## 3.0.2

- **FEAT**: Added hide references to hide webpage references in custom dialog

## 3.0.1

- **FIX**: bug fixes

## 3.0.0

- **FEAT**: Resilient SDK changes uptake for monitor, notification, and sync improvements.
- **CHORE**: Removed the domain parameter from the `Onboarding` widget.
- **FEAT**: Added `rootEnvironment` parameter to the `Onboarding` widget.
- **FEAT**: Made API Key mandatory for production environment.

## 2.1.3

- **FEAT**: added QR code screen

## 2.1.2

- **DOCS**: updated README

## 2.1.1

- **CHORE**: updated packages
- **FIX**: authentication bug fix

## 2.1.0

- **CHORE**: changes to get apiKey from app

## 2.0.0

- **FEAT**: supports .zip/.atKeys files of @signs
- **FEAT**: can generate free @signs
- **CHORE**: null-safety migration

## 1.0.0+4

- **CHORE**: upgraded some packages to resolve dependency issues

## 1.0.0+3

- **FIX**: Scan QRcode on app start fix

## 1.0.0+2

- **CHORE**: pubspec dependency upgrade

## 1.0.0+1

- **FIX**: Scanning QRcode fix
- **CHORE**: pubspec dependency upgrade

## 1.0.0

- Initial version
