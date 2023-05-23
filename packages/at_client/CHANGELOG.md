## 3.0.60
- fix: ensure key exchange functions properly when the sync service is not 
  being used
- feat: Add `useRemoteAtServer` to PutRequestOptions. When set, the update
  request will be sent directly to the remote atServer
- feat: Introduce DeleteRequestOptions
  - Add new optional named parameter `deleteRequestOptions` to AtClient.delete
  - Add `useRemoteAtServer` to DeleteRequestOptions. When set, the delete
    request will be sent directly to the remote atServer
## 3.0.59
- fix: Sync running into infinite loop when an invalid key is present in the entries to sync into client
- fix: Redundant logs generated for an internal key (lastReceivedNotification)
  while sending notifications
- chore: Reduced log_level of AtKey lower case enforcement message from INFO to FINER
- feat: Introduce clientId, appName, appVersion and platform to distinguish requests from several clients in server logs.
## 3.0.58
- chore: upgrade dependencies. at_commons to 3.0.43, at_utils to 3.0.12, at_lookup to 3.0.36 and at_chops to 1.0.3
## 3.0.57
- feat: Initial support of additional encryption metadata enabling encryption future-proofing
- fix: Expose priority, strategy, notifier, latestN and notificationExpiry in NotificationParams
- fix: Fixed issue where NotificationResponseTransformer would duplicate sharedWith and sharedBy
  when logging `AtKey`s
## 3.0.56
- fix: AtClient.put() throws null-check error when key's namespace is null
## 3.0.55
- fix: Amend Monitor's socket message handler so that it separates multiple 'simultaneous' responses correctly.
- fix: Sync to local fails to delete a cached key
- feat: Introduce CommitOp(CommitOperation) to the KeyInfo to describe key update or delete upon sync
- feat: consume changes in at_commons v3.0.35 that enforce lowercase on AtKey
- build: upgrade dependency at_persistence_secondary_server to v3.0.46
## 3.0.54
- fix: ensure forText notifications are decrypted successfully when using at_commons 3.0.35 or greater
## 3.0.53
- feat: Introduce commit log compaction to keep size of commit log thin
- fix: Fixed a bug where switch atSign event is notified multiple times
- fix: Add AtChops as optional argument to AtServiceFactory.atClient
## 3.0.52
- feat: Introduce AtServiceFactory to make AtClientManager more reusable and more testable
- feat: Make AtChops instance (if any) available everywhere that it can/should be used
## 3.0.51
- feat: Add atSign to AtSignLoggers' names when relevant, so that log messages are clearer
- feat: Made notificationService and syncService available via AtClient to enable cleaner simpler code elsewhere
- fix: Fixed clearing of sync progress listener while switching atsign.
- fix: Remove the inactive listeners from AtClientManager._changeListeners list.
- fix: Reverted back path,async packages to older version
## 3.0.50
- feat: Introduce commit log compaction to keep size of commit log thin
- feat: changes for at_chops uptake
- chore: upgrade at_persistence_spec, at_persistence_secondary_server, at_commons version
## 3.0.49
- fix: Enable AtKey.namespace overrides the namespace in AtClientPreference in AtClient delete method
- fix: Fixed a bug where initial notifications fails to decrypt - invalid pad block issue
## 3.0.48
- feat: Added `lib/src/client/request_options.dart` to provide access to the `RequestOptions` and `GetRequestOptions` classes.
## 3.0.47
- fix: Enable deletion of local keys
## 3.0.46
- fix: Ensure that we handle any and all exceptions related to sending heartbeat request
- feat: Made NotificationServiceImpl's retry delay into a public instance variable, so it can be set by application code
- feat: Changed NotificationServiceImpl's retry delay (from when monitorRetry() is called to when Monitor.start() is called) from 15 seconds to 5 seconds
- fix: Fixed a bug where client could 'miss' notifications while starting up
- fix: Ensure that exceptions related to sending heartbeat request are always caught correctly
- feat: Added experimental telemetry feature
## 3.0.45
- fix: Fix sync running into infinite loop when invalid keys does not sync into local storage
- fix: Upgrade persistence secondary to version 3.0.43 to fix empty batch request being sent to cloud secondary
## 3.0.44
- feat: Introduce fetch method to NotificationService to fetch the notification using id.
- fix: Replace latestNotificationId with local key to store/fetch last received notification
## 3.0.43
- chore: upgrade persistence secondary to version 3.0.42 and persistence spec to 2.0.9
## 3.0.42
- fix: Improved performance of getKeys (and getAtKeys) when sharedBy is specified, by using the existing 
RemoteSecondary connection rather than creating a new one
- fix: Do not try to decrypt empty or null serverEncryptedValue when generating SyncConflict info
- fix: put try-catch around most of the `SyncServiceImpl._checkConflict` method so sync is not impeded if
_checkConflict encounters an exception
- fix: fix null pointer exception in monitorResponse due to delayed server response
- fix: Skip reserved keys from decryption in the notification callback
- fix: Update at_commons to 3.0.29 which fixes AtKey sharedWith attribute has incorrect value for public keys
## 3.0.41
- chore: upgrade persistence secondary to version 3.0.38 which reverts sync of signing keys and statsNotificationKey
## 3.0.40
- chore: upgrade at_commons to 3.0.26
- fix: check isEncrypted flag in sync conflict
- docs: Fixed broken links
## 3.0.39
- chore: upgrade 3rd party dependencies except hive
- chore: upgrade persistence secondary to version 3.0.36
## 3.0.38
- fix: Add client sending config changes to server
- fix: NotificationService.subscribe to return existing listener on same regex
## 3.0.37
- fix: Revert sending client config changes to server
## 3.0.36
- fix: Add metadata validation to put request on client SDK  
- fix: Added unit tests for sync failure
- fix: Export SyncProgressListener to track the SyncProgress. 
- fix: setCurrentAtsign() throws an exception when an invalid atsign is passed.
- feat: Encode new line characters in public-key value
- feat: Send clientConfig to the cloud secondary 
## 3.0.35
* fix: Reverted dependency on 'meta' package to ^1.7.0 as flutter_test package requires 1.7.0 
## 3.0.34
* fix: Ensure _syncFromServer rethrows caught exceptions once it's handled the exception chaining
* feat: Add enforceNamespace (default value true) to AtClientPreference
## 3.0.33
- feat: Upgrade lints version to 2.0.0 
## 3.0.32
- fix: while syncing keys from server to local if there is an issue syncing a key, continue syncing rest of the keys
- fix: do not sync statsNotificationID from client to server
- feat: KeyStreams
- fix: do not create new instance of CacheableSecondaryAddressFinder in at lookup 
- [optional] Users can set SecureSocket's securityContext and store current session TLS keys through AtClientPreferences
## 3.0.31
- Enhance notify text to send text message encrypted
- Upgrade at_persistence_secondary_server to v3.0.30
- Upgrade at_commons version to v3.0.20 for encrypt notify text message
- Upgrade at_lookup version to v3.0.28 for adding mutex to authenticate methods
- feat: Add to NotificationService.notify() signature:
    * added new optional callback parameter, onSentToSecondary
    * added new optional 'checkForFinalDeliveryStatus' parameter
    * added new optional 'checkForFinalDeliveryStatus' parameter
    * and updated code documentation for NotificationService.notify() method
## 3.0.30
- Added bypassCache option in get method
- Added sync conflict info to sync progress callback
- Added security policy
- Fix for skipping reserved keys while checking for sync conflict
- Upgrade at_lookup to v3.0.27 for outbound message listener timeout enhancement  
## 3.0.29
- Added additional attributes in SyncProgress for improved sync observability
## 3.0.28
- Upgrading dependency at_persistence_secondary_server to version 3.0.29 to sync public hidden keys
- Upgrade at_commons to 3.0.18 to enable scan to display hidden keys when showHiddenKeys set to true
## 3.0.27
- Upgraded dependency at_persistence_secondary_server to version 3.0.28
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
