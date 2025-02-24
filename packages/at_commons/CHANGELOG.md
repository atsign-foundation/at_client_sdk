## 5.2.0
- feat: add Atsign string extensions
## 5.1.2
- fix: remove isPaginated check in SyncVerbBuilder and always set from: and limit: since sync:from verb
  expects these params to be set.
## 5.1.1
- fix: Introduce IV params for apkam enrollment flow
## 5.1.0
- feat: Introduce skipDeletesUntil for sync:from verb
## 5.0.2
- fix: Add "publicKeyHash" and "hashingAlgo" type to metadata.
- build[deps]: Upgraded the following package:
  - json_annotation to v4.9.0
  - meta to v1.16.0
  - build_runner to v2.4.13
  - json_serializable to v6.9.0
  - lints to v5.0.0
  - test to v1.25.8
  - test_process to v2.1.0
## 5.0.1
- fix: export regex utils class
## 5.0.0
- [Breaking Change]feat: Emit the isEncrypted value in the metadata if it is false
- fix: update pkam regex to accept sha512 as hashing algo
## 4.1.2
- feat: Add "expiry" enroll params to support apkam keys to auto expiry after specified time duration
## 4.1.1
- feat: Add "delete" operation to the enroll verb to allow deletion of denied enrollments
## 4.1.0
- feat: Add "unrevoke" operation to the enroll verb to restore revoked APKAM keys
- fix: Add isEncrypted flag to notify command for both true and false
## 4.0.11
- chore: deprecate MessageTypeEnum.text
- fix: remove deprecated annotation from Metadata.pubKeyCS
## 4.0.10
- fix: Add a "force" variable to enroll_verb_builder to propagate enroll:revoke:force value
- fix: Deprecate apkam in PkamAuthMode enum
## 4.0.9
- feat: enroll verb syntax change for enroll:revoke:force and added new exception AtEnrollmentRevokeException
## 4.0.8
- fix: Add shared_key.atsign@atsign to reservedKey regex
## 4.0.7
- fix: Add fetch operation to enroll verb to get the enrollment details
## 4.0.6
- fix: max key length validation changes
- fix: PublicKey toString method should return 'cached:' when isCached is set in metadata
## 4.0.5
- feat: Enhance enroll:list to enable filtering based on enrollment status
## 4.0.3
- fix: "toJson()" invoked on "pubKeyHash" leads to NullPointerException.
## 4.0.2
- feat: changes to replace md5 checksum - deprecated pubKeyCS in AtKey and introduced new class PublicKeyHash
## 4.0.1
- fix: Add "InvalidPinException" which is thrown when an invalid Semi Permanent Passcode is submitted.
## 4.0.0
- [Breaking Change] fix: Updated regex for Reserved keys (Internal keys used by the server)
- fix: Add "put" operation to OTP verb to store semi-permanent pass codes
- Remove attributes related to AtKey and metadata in verb builders. Instead, use AtKey instance. 
## 3.0.58
- fix: Deprecate encryptedDefaultEncryptedPrivateKey in EnrollParams and introduce encryptedDefaultEncryptedPrivateKey for readability
- fix: Replace encryptedDefaultEncryptedPrivateKey with encryptedDefaultEncryptionPrivateKey in EnrollVerbBuilder
## 3.0.57
- feat: Introduced TTL(Time to Live) for OTP verb to configure OTP expiry
## 3.0.56
- feat: Introduce "AtInvalidEnrollmentException" which is thrown when an enrollment is expired or invalid
- feat: Introduce error code 'AT0030' for Invalid Enrollment Status
- chore: Deprecated all variables in `src/at_constants.dart`, use `AtConstants.<variable-name>` instead
## 3.0.55
- feat: Introduce "AtThrottleLimitExceeded" exception which is thrown when enrollment request exceeds the limit
- feat: Introduce new error codes for apkam enrollments
## 3.0.54
- fix: Modify "totp" verb regex to include alphanumeric characters
- feat: Introduce "EnrollResponse" class which represents the enrollment response.
## 3.0.53
- feat: Modify "enroll" verb regex.
- feat: Introduce "EnrollParams" class to encapsulate enrollment attributes.
## 3.0.52
- fix: Add revoke and list operations to "enroll" verb
- fix: Modify "keys" verb regex and verb builder
## 3.0.51
- feat: added exception class for enrollment exception
## 3.0.50
- feat: add self notification flag in monitor syntax for APKAM feature
## 3.0.49
- feat: added syntax and verb builder for keys verb
- feat: introduced verb builder for enroll and pkam verbs
- chore: Moved this package to a new repo & updated repository URL
## 3.0.48
- feat: totp support in enroll verb
## 3.0.47
- fix: Enhance stats verb to allow regex for stats:15
- feat: Add syntax and verb builder for APKAM enroll verb
## 3.0.46
- fix: Modify emoji list to allow variation selector Unicode
## 3.0.45
- fix: Add constants for AtClientParticulars
## 3.0.44
- feat: introduce enum for pkam authentication mode
## 3.0.43
- feat: Enhanced the monitor verb syntax
  1. added `strict` flag to allow client to request that only regex-matching notifications are sent -
     e.g. do not send other 'control' type notifications like the 'statsNotifications'
  2. added `multiplexed` flag to allow client to indicate that
     this socket is also being used for request-response interactions
## 3.0.42
- fix: Tightened the validation of 'public' key names. Keys like this: `public:@bob:foo.bar@alice` will now correctly be identified as not being valid.
## 3.0.41
- fix: Add 'configkey' to list of reserved keys for key validation purposes
## 3.0.40
- fix: Add notification expiry to the notify verb builder.
## 3.0.39
- feat: add new exceptions for at_chops operations.
## 3.0.38
- fix: add hashing algorithm to pkam syntax.
## 3.0.37
- fix: change signing algo in pkam syntax from rsa256 to sha256.
- fix: pub score issues.
## 3.0.36
- feat: change is pkam syntax to support different signing algorithms.
- fix: pub score issues.
## 3.0.35
- feat: enforce lowercase on AtKey(all key types included)
- fix: incorrect behaviour of cached:public keys in AtKey.fromString()
- feat: Added new fields to Metadata
- feat: Added new encryption metadata to the syntax for notify, update and update:meta verbs
## 3.0.34
- feat: New server-side exception ServerIsPausedException, error code AT0024
## 3.0.33
- fix: Deprecate AtCompactionConfig class
## 3.0.32
- fix: Enable deletion of a local key
## 3.0.31
- feat: Added AtTelemetryService. Marked @experimental while the feature is in early stages.
## 3.0.30
* fix: Add key validations to Update and llookup verb builders
## 3.0.29
* fix: AtKey.fromString() sets incorrect value in sharedWith attribute for public keys.
## 3.0.28
* feat: Introduce the local key type
## 3.0.27
* feat: Implement the `==` and `hashCode` methods for AtKey, AtValue and Metadata classes
## 3.0.26
* feat: Introduce notifyFetch verb
* fix: bug in at_exception_stack.dart
## 3.0.25
* fix: update regex to correctly parse negative values in ttl and ttb
* feat: add clientConfig to from verb syntax
## 3.0.24
* fix:  add error code for InvalidAtKeyException
## 3.0.23
* fix: bug fixes to AtKey.fromString static method and various toString instance methods
* feat: When validating AtKeys, allow _namespace_ to be optional, for legacy app code which depends on keys without namespaces
* feat: Added _getKeyType_ to AtKey

## 3.0.22
- Add ENCODING to update verb regex, update verb builder and Metadata to support encoding of new line character
- Add AtKeyNotFoundException for non-existent keys in secondary
- Add documentation around the Metadata fields
## 3.0.21
- Add constant for stats notification id
## 3.0.20
- Enhance notify verb to include the isEncrypted field
- Add intent and exception scenario to AtException subclasses
- Introducing class SecureSocketConfig to store config params to create security context for secure sockets.
## 3.0.19
- Rename byPassCache to bypassCache in lookup, plookup verb builders and at_constants
## 3.0.18
- Add 'showHidden' to scan regex to display hidden keys when set to true
## 3.0.17
- Introduce exception hierarchy and new AtException subclasses
## 3.0.16
- Hide at_client_exceptions.dart to prevent at_client_exception being referred from at_commons
## 3.0.15
- FEAT: support to bypass cache in lookup and plookup verbs
## 3.0.14
- Remove unnecessary print statements
## 3.0.13
- Generate default notification id
## 3.0.12
- Added optional parameter to info verb. Valid syntax is now either 'info' or 'info:brief'
## 3.0.11
- Rename 'NotifyDelete' to 'NotifyRemove' since 'notify:delete' is already in use.
## 3.0.10
- Added syntax regex for 'notifyDelete' verb
## 3.0.9
- Bug fix in notify verb syntax
## 3.0.8
- Support for encryption shared key and public key in notify verb
## 3.0.7
- Added encryption shared key and public key checksum to metadata
## 3.0.6
- Added syntax regexes for new verbs 'info' and 'noop'
## 3.0.5
- Rename TimeoutException to AtTimeoutException to prevent confusion with Dart async's TimeoutException
## 3.0.4
- Add TimeoutException
## 3.0.3
- Add static factor methods for AtKey creation
## 3.0.2
- added constants for compaction and notification expiry
## 3.0.1
- Add AtKey validations
## 3.0.0
- sync pagination changes
## 2.0.5
- version 2.0.4 update issue
## 2.0.4
- Shared key status in metadata
- Add last notification time to Monitor
## 2.0.3
- Syntax change in stream verb to support resume
## 2.0.2
- Fix regex issue in Notify verb
## 2.0.1
- Remove trailing space in StatsVerbBuilder
## 2.0.0
- Null safety upgrade
## 1.0.1+8
- Refactor code with dart lint rules
## 1.0.1+7
- Third party package dependency upgrade
## 1.0.1+6
- Replace ByteBuffer with ByteBuilder
## 1.0.1+5
- Notification sub system changes
## 1.0.1+4
- added createdAt and updatedAt to metadata
  Introduced batch verb for sync
## 1.0.1+3
- Notify verb builder and update verb syntax changes
## 1.0.1+2
- Update verb builder changes
## 1.0.1+1
- Stream verb syntax changes
## 1.0.1
- Initial version, created by Stagehand
