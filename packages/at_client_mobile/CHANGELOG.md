## 3.2.19
- build[deps]: Upgraded dependencies for the following packages:
    - at_client: 3.2.2
    - at_lookup: 3.0.49
    - at_auth: 2.0.7
    - at_commons: 5.0.0
    - at_chops: 2.0.1
    - at_utils: 3.0.19
## 3.2.18
- fix:  fix: rename enrollment details key to local key
- build[deps]: Upgraded dependencies for the following packages:
    - at_client: 3.0.78
    - at_lookup: 3.0.47
    - at_auth: 2.0.5
    - at_commons: 4.0.11
## 3.2.17
- fix: Export "BackupKeyConstants" and "getEncryptedKeys"
## 3.2.16
- build[deps]: Upgraded dependencies for the following packages:
    - package_info_plus: ^8.0.0
    - at_client: ^3.0.76
    - test: ^1.25.2
    - mocktail: ^1.0.4
- feat: Introduce AtAuthService to replace AtClientService for the following operations
    - authenticate
    - onboard
    - enroll
    - getFinalEnrollmentStatus
    - getSentEnrollmentRequest
## 3.2.15
- build[deps]: Upgraded dependencies for the following packages:
  - at_chops to v2.0.0 
  - at_lookup to v3.0.46
  - at_commons to v4.0.1
  - at_client to v3.0.75
  - package_info_plus: ^5.0.0
# 3.2.14
  build[deps]: Upgraded dependencies for the following packages:
    - at_commons to v4.0.0
    - at_utils to v3.0.16
    - at_lookup to v3.0.44
    - at_chops to v1.0.7
    - at_client to v3.0.73
## 3.2.13
- fix: Introduce the "isOnboarded" function to confirm the successful onboarding of the atSign.
## 3.2.12
- fix: Fixed the issue biometric_storage dependency not working on Windows when using Dart 3
## 3.2.11
- chore: Upgraded biometric_storage dependency to 5.0.0 
- chore: Upgraded package_info_plus dependency to 4.0.2 
## 3.2.10
- fix: Fixed incorrect import statements in at_client_mobile/example which are
  causing analysis errors in dart 3
- chore: Updated at_client to 3.0.61
- chore: Updated at_lookup to 3.0.37
- chore: Updated at_utils to 3.0.13
- chore: Updated at_chops to 1.0.3
- chore: Updated at at_commons to 3.0.47
## 3.2.9
- fix: reverted path dependency to 1.8.2
## 3.2.8
- chore: Upgraded at_client dependency to 3.0.53
- fix: Uptake at_chops changes
## 3.2.7
- chore: Upgraded biometric storage dependency to 4.1.3
## 3.2.6
- chore: update at_client version to 3.0.39 and at_utils version to 3.0.11
## 3.2.5
- fix: Fixed bug authenticate method returns true when invalid atKeys are supplied
## 3.2.4
- fix: fixed bug in windows keychain data storage.
## 3.2.3+1
- docs: Updated CHANGELOG with discontinue notice on versions 3.2.0 to 3.2.2.
## 3.2.3
- fix: Restored the Public API of KeyChainManager.
## 3.2.2
**DO NOT USE**
- This version has been discontinued due to unintended breaking changes in KeyChainManager.
- Please use version constraint "^3.2.3" to ensure that you do not experience these issues.
Changes:
- fix: Format Exception - ChunkedJsonParser.fail
## 3.2.1
**DO NOT USE**
- This version has been discontinued due to unintended breaking changes in KeyChainManager.
- Please use version constraint "^3.2.3" to ensure that you do not experience these issues.
Changes:
- feat: Upgrade lints version to 2.0.0
## 3.2.0
**DO NOT USE**
- This version has been discontinued due to unintended breaking changes in KeyChainManager.
- Please use version constraint "^3.2.3" to ensure that you do not experience these issues.
Changes:
- Updated keychain data structure
## 3.1.19
- at_client dependency upgraded to latest version v3.0.30
- at_lookup dependency upgraded to latest version v3.0.27
- at_commons dependency upgraded to latest version v3.0.19
## 3.1.18
- at_client version upgraded to 3.0.27
## 3.1.17
- at_client version upgrade to v3.0.26 for AtException chaining
- at_commons version upgrade to v3.0.17 for AtException hierarchy
## 3.1.16
- at client version upgrade v3.0.25
- at lookup version upgrade v3.0.24
- at commons version upgrade v3.0.16
## 3.1.15
- at client version upgrade v3.0.23.
## 3.1.14
- migrated to latest version of at_client
## 3.1.13
- at_client version upgrade for generating notification id in SDK
## 3.1.12
- Add keys from keychain to local store on reinstalling the app
- at_client version upgrade for decrypt notification value in SDK.
## 3.1.11
- at_client version upgrade for public key checksum in metadata does not sync to local
## 3.1.10
- at_client version upgrade for chunk based encryption
## 3.1.9
- at_client version change for sync deletion of cached keys to cloud secondary 
- at_lookup version change for increase in outbound connection timeout
## 3.1.8
- at_client version change for automatic sync trigger 
## 3.1.7
- at_client and at_lookup version change for outbound listener bug fix
## 3.1.6
- at_client version change for refactoring put and get methods
- at_lookup version change implementing AtTimeoutException
- at_commons and at_utils version change for AtTimeoutException
## 3.1.5
- at_client version change
- at_lookup version change
- at_commons and at_utils version change
## 3.1.4
- updated readme and  doc changes
- added example app
## 3.1.3
- at_client version change
- at_lookup version change
- at_commons and at_utils version change
## 3.1.2
- **FIX**: Added check to use flutter_keychain only on mobile platforms
## 3.1.1
- at_client version change
## 3.1.0
- moved keys storage from flutter_keychain to biometric_storage
- updated package dependencies
- updated documentation
## 3.0.3
- at_client version change
## 3.0.2
- at_client version change
## 3.0.1
- at_client version change
- at_lookup version change
## 3.0.0
- Resilient SDK uptake for notification, monitor and sync improvements
## 2.0.4
- at_client version change
- removed obsolete self key migration code
## 2.0.3
- at_client version change
## 2.0.2
- Bug fix for type mismatch
## 2.0.1
- Updated dependent packages
## 2.0.0
- Null safety changes
- Dependent package upgrade
## 1.0.0+11
- Provision to request for a new outbound connection.
- Minor bug in stream handlers
- at_client version upgrade
## 1.0.0+10
- Third party package dependency upgrade
- gitflow changes
- Auto restart monitor connection
- Stream encryption
- Bug fixes
## 1.0.0+9
- at_client version change
## 1.0.0+8
- Self keys migration issue fix
## 1.0.0+7
- Self Encryption changes
## 1.0.0+6
- Notification sub system changes
## 1.0.0+5
- Added automatic refresh of monitor connection
## 1.0.0+4
- Provided multiple atsign support in at client SDK. Introduced batch verb to improve sync performance
## 1.0.0+3
- onboarding changes for server activation and deactivation Backup keys implementation sync improvements
## 1.0.0+2
- restore backup keys bug fix
## 1.0.0+1
- at_client version change
## 1.0.0
- Initial version, created by Stagehand
