## 3.0.27
- Upgraded to version 3.0.28 of at_persistence_secondary_server
## 3.0.26
- Uptake AtException hierarchy
- Introduce exception chaining
- Fix for Server stuck on old value even though syncing is happening. at_server Issue #721
- Export notification_service.dart file
## 3.0.25
- Fix for regex issue in notification service. Issue #523
- Fix for namespace issue in notify method.Issue #527
- Fix for handling empty sync responses from server. App issue #624
## 3.0.24
- Update the @platform logo
- Default the AtKey.sharedBy to currentAtSign
## 3.0.23
- Fix for at_client issue #508 - getLastNotificationTime bug while trying to decrypt old data
## 3.0.22
- Fix for getKeys in local secondary not returning keys
## 3.0.21
- Cache secondary url returned by root server
## 3.0.20
- Remove print statements
## 3.0.19
- Update at_commons,at_persistence and at_lookup version to remove print statements
## 3.0.18
- Generate Notification id in SDK
## 3.0.17
- Fix self encryption key not found
- Fix for _getLastNotificationTime method returning null
- Added heartbeats to Notifications Monitor to detect and recover from
  dead socket. Heartbeat interval is customizable via AtClientPreference
- Fix for os write permission issue: give app option to pass the path where
  the encrypted file will be saved on disk
## 3.0.16
- Decrypt notification value in SDK
- Support for shared key and public key checksum in notify
- Deprecated methods related to filebin
## 3.0.15
- Fix public key checksum in metadata does not sync to local.
## 3.0.14
- Support for shared key and public key checksum in metadata
- Chunk based encryption/decryption for files up to 1GB
- Change in pubspec to fetch the exact version of atsign packages
## 3.0.13
- Sync deleted cached keys to cloud secondary
- at_lookup version upgrade for increase in outbound connection timeout
## 3.0.12
- Fix automatic sync not working
## 3.0.11
- at_lookup version upgrade for outbound listener bug fix
- added functional test to verify outbound listener bug fix
## 3.0.10
- Uptake at_persistence_secondary_server changes
- Uptake at_lookup changes for AtTimeoutException
- Handle error responses from server
- Refactor put method to use request and response transformers
- Provide callback for sync progress
## 3.0.9
- Uptake at_persistence_secondary_server changes
- Refactor decryption service
- Introduce request response transformers
- Refactor get method to use request response transformers
## 3.0.8
- Updated readme and documentation improvements
## 3.0.7
- Uptake at_persistence_secondary_server changes
- Resolve dart analyzer issues
- Run dart formatter
## 3.0.6
- Uptake AtKey validations
## 3.0.5
- Uptake at_persistence_secondary_server changes
## 3.0.4
- Uptake Hive Lazy Box changes
## 3.0.3
- Sync pagination limit in preference
## 3.0.2
- Expose isSyncInProgress in SyncService
## 3.0.1
- Reduce wait time on monitor connection
- at_lookup version upgrade
## 3.0.0
- Resilient SDK changes and bug fixes
## 2.0.4
- Improve notification service
- Improve monitor
- sync on a dedicated connection
## 2.0.3
- at_commons version upgrade
## 2.0.2
- filebin upload changes
## 2.0.1
- at_commons version upgrade
## 2.0.0
- Null safety upgrade
## 1.0.1+10
- Provision to request for a new outbound connection.
- Minor bug in stream handlers
## 1.0.1+9
- Third party package dependency upgrade
- gitflow changes
- Auto restart monitor connection
- Stream encryption
- Bug fixes
## 1.0.1+8
- Delete cached keys
- Encrypt Stream data
## 1.0.1+7
- Self keys migration issue fix
## 1.0.1+6
- Notification sub system introduced
## 1.0.1+5
- Added automatic refresh of monitor connection
## 1.0.1+4
- Provided multiple atsign support in at client SDK. Introduced batch verb to improve sync performance
## 1.0.1+3
- onboarding changes for server activation and deactivation Backup keys implementation sync improvements
## 1.0.1+2
- sync improvements and at_utils, at_commons, at_lookup version changes
## 1.0.1+1
- Minor changes in at_persistence_spec and at_persistence_secondary_server
## 1.0.1
- pubspec dependencies version changes
## 1.0.0
- Initial version, created by Stagehand
