## 3.7.0

 - **REFACTOR**: refactored collection static functions and updated docs and unit test.
 - **REFACTOR**: change some method names.
 - **REFACTOR**: Moved at_telemtry.dart into at_commons package. Changed code here accordingly.
 - **REFACTOR**: remove unused stuff from remote_secondary_test.dart.
 - **REFACTOR**: remove unused NetworkUtil class and file network_util.dart.
 - **REFACTOR**: remove unused networkUtil instance variable from SyncServiceImpl (not part of public interface of that class, only used for testing.
 - **REFACTOR**: Make sync unit tests simulate atServer unreachable by throwing AtConnectExceptions where previously they relied on having calls to a mockNetworkUtil.isNetworkAvailable return false.
 - **REFACTOR**: AtCollectionModelFactory removed from static variables, tests updated.
 - **REFACTOR**: refactored collection static functions and updated docs and unit test.
 - **REFACTOR**: Removed direct use of AtClientManager.syncService and AtClientManager.notificationService now that both of them are available via the AtClient (AtClient.syncService and AtClient.notificationService). Removed the AtClientManager.notificationService and AtClientManager.syncService instance variables.
 - **REFACTOR**: lastReceivedNotificationKey converted to lower case.
 - **REFACTOR**: Extract the code in _putInternal, which ensures the atKey has only lowercase in its `key` and `namespace`, into its own method.
 - **REFACTOR**: AtCollectionModelFactory removed from static variables, tests updated.
 - **FIX**: replace deprecated used of AtLookup.authenticate_cram() with cramAuthenticate().
 - **FIX**: Remove the network check on executeVerb.
 - **FIX**: LocalSecondary.isEnrollmentAuthorizedForOperation now checks if the key in question is a `local` key, in which case the answer is always yes.
 - **FIX**: Enable the same atSign to be used on both sides (client and server) of an AtRpc interaction.
 - **FIX**: better output from Monitor _messageHandler if it encounters a failure.
 - **FIX**: Have AtCollectionQueryOperationsImpl deal correctly with responses from `AtClient.get` which have `AtValue.value == null` (which means expired or not yet born).
 - **FIX**: add retries to at_client_bindings.notify (3 by default).
 - **FIX**: wherever we are parsing data: or error: responses from atServer, use replaceFirst(RegExp(r'^data:'), '') or replaceFirst(RegExp(r'^error:'), '').
 - **FIX**: formatting issue.
 - **FIX**: In at_notification.dart check for "publicKeyHash" for null check.
 - **FIX**: changelog.
 - **FIX**: remove at_commons dependency overrides.
 - **FIX**: add changelog.
 - **FIX**: revoke removing limit param in sync service impl.
 - **FIX**: change at_lookup depedency override to at_commons.
 - **FIX**: Modify existing functional tests to assert on publicKeyHash.
 - **FIX**: Update the unit tests and version in pubspec.yaml.
 - **FIX**: remove sync verb builder deprecated params.
 - **FIX**: pubspec and changelog.
 - **FIX**: isInSync bug.
 - **FIX**: method rename.
 - **FIX**: replace at_commons dependency overrides.
 - **FIX**: put try-catch around most of the `SyncServiceImpl._checkConflict` method so a WARNING is logged but sync is not impeded if.
 - **FIX**: review comments.
 - **FIX**: unit tests for skip deletes.
 - **FIX**: added functional tests.
 - **FIX**: bug fix in intialsync flag put method.
 - **FIX**: isError called on null monitorResponse.
 - **FIX**: added check for skip deletes.
 - **FIX**: set skip deletes in sync verb builder.
 - **FIX**: update CHANGELOG.md.
 - **FIX**: removed depdendency overrides.
 - **FIX**: review comments.
 - **FIX**: change at_lookup branch in dependency overrides.
 - **FIX**: actions failure.
 - **FIX**: added unit tests for get response transformer.
 - **FIX**: analyzer issue.
 - **FIX**: comment putmeta code to check functional test failure.
 - **FIX**: review comments.
 - **FIX**: added functional test.
 - **FIX**: response transformer refactoring.
 - **FIX**: functional test fix.
 - **FIX**: run dart formatter and fix syntax test.
 - **FIX**: changelog for dependency version upgrade.
 - **FIX**: upgrade packages and remove dependency overrides.
 - **FIX**: analyzer issue.
 - **FIX**: review comments.
 - **FIX**: added changes to publish.
 - **FIX**: added functional test.
 - **FIX**: added unit test.
 - **FIX**: add stack trace info when NotificationServiceImpl gets mysterious exceptions.
 - **FIX**: add stack trace info when NotificationServiceImpl gets mysterious exceptions.
 - **FIX**: invalid pad block issue.
 - **FIX**: review comments - add shouldDecrypt check.
 - **FIX**: analyzer issue.
 - **FIX**: review comments.
 - **FIX**: dart doc minor changes.
 - **FIX**: skip decrypting notification key if isEncrypted is explicitly set to false.
 - **FIX**: publish at_client 3.0.77+1.
 - **FIX**: remove 3.0.78 version from changelog.
 - **FIX**: response transformer handle isEncrypted false.
 - **FIX**: Add "sharedKeyEnc" to the metadata.
 - **FIX**: pubspec and changelog.
 - **FIX**: rename key from __manage to local key for storing enrollment details to local storage.
 - **FIX**: add dart docs.
 - **FIX**: update conditions for deleteExpiredKeys job schedule.
 - **FIX**: Remove visibleForTesting annotation on "isEnrollmentAuthorizedForOperation" method.
 - **FIX**: Add unit tests for assert enrollmentAuthorizationCheck.
 - **FIX**: Failing unit tests in enrollment_service_test.dart.
 - **FIX**: Add unit test to assert the changes.
 - **FIX**: Update archive package dependency.
 - **FIX**: Skip cached public keys and cached shared keys from enrollment authorization check.
 - **FIX**: update the dart docs.
 - **FIX**: Update the log statments.
 - **FIX**: Setting log level to finer and more log statements for test failure debugging purpose.
 - **FIX**: Remove skip tag and modify log statements.
 - **FIX**: Fix collection_test.dart failures.
 - **FIX**: Skip cached shared key and cached public key from enrollment authorization check.
 - **FIX**: Set at_auth package version to 2.0.4.
 - **FIX**: add sync unit test cases.
 - **FIX**: Add enrollment_teardown to clean up the enrollment requests after test run.
 - **FIX**: Skip authorization check for local keys.
 - **FIX**: Set skipCommit to true when caching the enrollment details.
 - **FIX**: deprecate NotificationParams.forText and messageType getter.
 - **FIX**: Add check in sync service to continue sync process if key is unauthorized.
 - **FIX**: Remove EnrollmentDetails and reuse Enrollment class.
 - **FIX**: Add enroll:fetch to get the enrollment details from remote secondary.
 - **FIX**: Remove mock remote secondary and store enrollment info into local secondary to fix unit tests.
 - **FIX**: Fix functional test failure.
 - **FIX**: Fix dart analyze issue.
 - **FIX**: sync running into loop on invalid keys.
 - **FIX**: Update the comments.
 - **FIX**: Remove unused imports.
 - **FIX**: Fetch SelfKeyEncryption changes from local secondary if in atChops is null.
 - **FIX**: removed dependency overrides for at_commons.
 - **FIX**: added unit test.
 - **FIX**: Remove unused variable and run dart format.
 - **FIX**: unit test for max length in local secondary.
 - **FIX**: added ignore linter rule for depend_on_referenced_packages.
 - **FIX**: update at_auth package version to 2.0.0.
 - **FIX**: Update at_auth version and remove dependency overrides.
 - **FIX**: minor refactoring.
 - **FIX**: add stacktrace to exception.
 - **FIX**: Dart analyze issues.
 - **FIX**: Update the dependency_overrides of at_auth to trunk branch.
 - **FIX**: Change the exception type to AtEnrollmentException at_auth_service_impl.dart.
 - **FIX**: add stacktrace to exception.
 - **FIX**: improved enrollment test, fixed atAuth compile issue in atClient.
 - **FIX**: Run dart formatter.
 - **FIX**: dart analyze changes.
 - **FIX**: remove deprecation for private key since it causes analyzer issue in github actions.
 - **FIX**: change in AtClientPreference: expiryCheckTimeIntervalMins(type int) -> expiryCheckTimeInterval(type Duration).
 - **FIX**: Dart analyze issues.
 - **FIX**: Change commitlog time interval from int to duration.
 - **FIX**: Fix intermittent failing compaction job test in functional test.
 - **FIX**: Set the enrollmentId in AtClient._() method.
 - **FIX**: Include exceptions in dart docs and update at_lookup package version.
 - **FIX**: Set enrollmentId in at_client_impl.dart and fix unit tests.
 - **FIX**: revert encryption service changes.
 - **FIX**: removed unused methods in encryption_service.
 - **FIX**: make `Monitor.start()` catch Errors as well as Exceptions, so it calls `_handleError(e)` if it encounters either.
 - **FIX**: Fixes https://github.com/atsign-foundation/at_client_sdk/issues/770.
 - **FIX**: remove commented code.
 - **FIX**: replace default encryption with rsa encryption in abstract_atkey_encryption.dart.
 - **FIX**: uptake at_chops major version.
 - **FIX**: formatting issue.
 - **FIX**: analyzer issues.
 - **FIX**: stopAllSubscriptions, in addition to stopping any connectivity listener subscriptions, also sets _connectivityListener to null so that subsequently, if this notification service becomes active again, we will set up a new connectivity listener subscription.
 - **FIX**: In delete method when atkey.namespace is unset default to namespace from at_client preferences and assign AtKey to UpdateVerbBuilder directly.
 - **FIX**: monitorIsPaused and _startMonitor.
 - **FIX**: analyzer issue.
 - **FIX**: review comments.
 - **FIX**: unit tests for self key encryption and shared key encryption.
 - **FIX**: Update the null check condition in shared_key_decryption.dart.
 - **FIX**: Update the version in at_client.
 - **FIX**: review comments.
 - **FIX**: end2end test failure.
 - **FIX**: add network connection check in executeVerb in remote_secondary.dart.
 - **FIX**: fixed name of the Monitor.getQueueResponse method's maxWaitTimeInMillis parameter, and made it actually operate as milliseconds. Safe change as Monitor.getQueueResponse method is visible only for testing, and the parameter is only used in testing.
 - **FIX**: delete local key.
 - **FIX**: analyzer issue.
 - **FIX**: replace encryption util  methods in local key decryption.
 - **FIX**: invalid pad block issue.
 - **FIX**: remove singleton nature for encryption/decryption manager class.
 - **FIX**: review comments.
 - **FIX**: added unit test for negative scenario.
 - **FIX**: add getLatestCommitEntry to sync util.
 - **FIX**: namespace in atkey overrides the namespace in preference.
 - **FIX**: added unit test.
 - **FIX**: review comments.
 - **FIX**: use enrollmentId from atClient in sync/notification service.
 - **FIX**: pass enrollmentId to notification and sync service through default service factory.
 - **FIX**: change at chops setter in at_client_impl.
 - **FIX**: replaced deprecated constants, changes for publishing.
 - **FIX**: fix failing unit tests in notification_service_test.dart.
 - **FIX**: resolved functional test issues.
 - **FIX**: switch atsign remove progress listeners.
 - **FIX**: remove static nature of sync progress listener.
 - **FIX**: namespace not mandatory for local keys.
 - **FIX**: review comments - remove enrollmentId from preference and inject to setCurrentAtSign.
 - **FIX**: analyzer issue.
 - **FIX**: changed set type to list for syncProgressListener.
 - **FIX**: upgrade pubspec dependencies.
 - **FIX**: git#865 - fixes notifying the switch atSign event multiple times.
 - **FIX**: AtClientManager: Changed `late String _atSign;` to `String? _atSign` to prevent uninitialized field error when trying to set previousAtSign so we can later log that we have switched from previousAtSign to _atSign.
 - **FIX**: ensure that namespaces in `notify` requests aren't messed up by multipart namespaces in AtClientPreference (e.g. namespace of `foo.bar`).
 - **FIX**: Remove isActive flag and remove inactive change listeners.
 - **FIX**: typo.
 - **FIX**: jumping through some hoops so we don't have to do a major version upgrade on at_commons.
 - **FIX**: Remove isActive flag from KeyStreamMixin.
 - **FIX**: Rename the variable in notifyListener method.
 - **FIX**: notify_request_transformer.dart: preserve behaviour for type `text` (which is deprecated and obsolete, but we haven't removed it yet).
 - **FIX**: change dependencies to published version. changes to publish at_client.
 - **FIX**: add unit tests and dart docs.
 - **FIX**: update the dart docs.
 - **FIX**: Remove duplicate listeners on switch atSign.
 - **FIX**: remove previous atsign listener.
 - **FIX**: resolve merge conflicts.
 - **FIX**: Fix bug in AtRpc.sendRequest.
 - **FIX**: clear sync requests in the queue in unit tests.
 - **FIX**: Rename the variable to lastReceivedServerCommitId and added unit tests for adding sync request to queue.
 - **FIX**: correct the CHANGELOG.md.
 - **FIX**: Run dart formatter.
 - **FIX**: Modify encryptedSharedKey matching Regular expression and add unit tests.
 - **FIX**: Modify the IF condition with regular expression.
 - **FIX**: skip reserved keys from sync conflict.
 - **FIX**: Add experimental annotation.
 - **FIX**: Restructure code and run dart analyzer.
 - **FIX**: Restructure code and run dart analyzer.
 - **FIX**: Implement getModelsSharedWithAnyAtSign.
 - **FIX**: ensure that namespace is preserved if it happens to be repeated in a notification's key (e.g. `@bob:foo.my_app.my_app@alice` ).
 - **FIX**: Remove the network check on executeVerb.
 - **FIX**: failing unit tests.
 - **FIX**: Added check to SwitchAtSignEvent constructor to prevent events being created when the atClients are the same.
 - **FIX**: removed singleton from collectionMethodImpl.
 - **FIX**: fixed issues with future test cases.
 - **FIX**: remove connection.close in SyncServiceImpl.dart.
 - **FIX**: Remove duplicate listeners on switch atSign.
 - **FIX**: remove previous atsign listener.
 - **FIX**: resolve merge conflicts.
 - **FIX**: correct the CHANGELOG.md.
 - **FIX**: failing unit tests.
 - **FIX**: modify removing inactive listeners.
 - **FIX**: update pubspec.yaml and CHANGELOG.md.
 - **FIX**: update pubspec.yaml and CHANGELOG.md.
 - **FIX**: Fixed merge issues.
 - **FIX**: Remove the network check on executeVerb.
 - **FIX**: remove unused imports.
 - **FIX**: resolve merge conflicts.
 - **FIX**: Move commit log compaction to AtClientImpl.
 - **FIX**: add unit test to verify if cron job is scheduled.
 - **FIX**: update dart docs.
 - **FIX**: Add functional and e2e tests for commit log compaction.
 - **FIX**: Add functional and e2e tests for commit log compaction.
 - **FIX**: Update CHANGELOG.md and pubspec.yaml.
 - **FIX**: Remove duplicate listeners on switch atSign.
 - **FIX**: remove previous atsign listener.
 - **FIX**: added message to toJson and fromJson in AtRpcResp.
 - **FIX**: fix a late uninitialized error.
 - **FIX**: resolve merge conflicts.
 - **FIX**: correct the CHANGELOG.md.
 - **FIX**: Added additional defensive code around 'their' copy of shared symmetric key. We now delete 'their' copy (1) from local storage if we don't find 'our' copy in local storage, and (2) from the remote atServer when we are creating and sharing a new symmetric key.
 - **FIX**: Update E2E tests.
 - **FIX**: Update unit tests.
 - **FIX**: Add unit tests for conflictInfo.
 - **FIX**: Fix dart analyze issues.
 - **FIX**: Add AtClientException in SyncProgress and return exception on invalid sync regex.
 - **FIX**: revert version 3.0.61 to 3.0.60 since 3.0.60 is yet to be published.
 - **FIX**: ConflictInfo does not populate local and remove value.
 - **FIX**: changelog and pubspec for sync/monitor bug fix.
 - **FIX**: add unit test for monitor and atchops.
 - **FIX**: removed logging statements.
 - **FIX**: removed setting signing and hashing algo in sync service.
 - **FIX**: removed setting signing and hashing algo in at_client_impl.
 - **FIX**: changed logging text in sync service.
 - **FIX**: added logging statement to debug.
 - **FIX**: added logging for signing and hashing algo in remote secondary.
 - **FIX**: set hashing and signing algo type in at_lookup from preferences.
 - **FIX**: at_chops secure element bug in sync.
 - **FIX**: at_chops secure element - monitor bug.
 - **FIX**: Update the code comments.
 - **FIX**: Incorrect commitId gets updated against commit entry when a batch skips an entry.
 - **FIX**: failing unit tests.
 - **FIX**: Remove duplicate listeners on switch atSign.
 - **FIX**: ensured 'data:' is stripped from responses from lookups of encrypted symmetric keys.
 - **FIX**: resolves #1041.
 - **FIX**: remove previous atsign listener.
 - **FIX**: Rename "listOfCommitEntriesToSync" to "listOfCommitEntriesFromServer".
 - **FIX**: Implement getModelsSharedWithAnyAtSign.
 - **FIX**: resolve merge conflicts.
 - **FIX**: failing unit tests.
 - **FIX**: Sync missing entries when running with multiple clients and add e2e test.
 - **FIX**: Remove unused import.
 - **FIX**: Run dart formatter.
 - **FIX**: Introduce AtClientLogging.
 - **FIX**: Run dart formatter.
 - **FIX**: Enhance the AtConnection log messages.
 - **FIX**: failing unit test.
 - **FIX**: Add AtClientParticulars to enhance logging.
 - **FIX**: Add conditions to prevent lastReceivedServerCommitId being updated when commit-id is -1.
 - **FIX**: Update lastReceivedServerCommitId when uncommitted entries are synced.
 - **FIX**: modify removing inactive listeners.
 - **FIX**: update pubspec.yaml and CHANGELOG.md.
 - **FIX**: resolve merge conflicts.
 - **FIX**: Add unit test to ensure sync do not stuck in infinite loop.
 - **FIX**: Replace KeyNotFoundException with AtKeyNotFoundException.
 - **FIX**: Add mock response to atClient.get method to pass unit tests.
 - **FIX**: Add mock response to atClient.get method to pass unit tests.
 - **FIX**: Refactor getLastReceivedServerCommitId method.
 - **FIX**: Failing unit test in sync_service_test.dart.
 - **FIX**: Invalid key in sync causes infinite loop.
 - **FIX**: Move commit log compaction to AtClientImpl.
 - **FIX**: strip the 'data:' prefix before storing.
 - **FIX**: Run dart run format.
 - **FIX**: Set isCached to true in metadata for cached keys.
 - **FIX**: add unit test to verify if cron job is scheduled.
 - **FIX**: update dart docs.
 - **FIX**: Replace deprecated methods with new methods.
 - **FIX**: Run dart format.
 - **FIX**: Improve exception messages for readability.
 - **FIX**: Add validation to executeCommand and update dart docs in AtClientPreference.
 - **FIX**: Failing unit test.
 - **FIX**: Add validation for sharedBy atSign for notifications.
 - **FIX**: Add value validations.
 - **FIX**: Add value validations.
 - **FIX**: Upgrade at_commons version.
 - **FIX**: Formatting to allow format test to pass.
 - **FIX**: Add a functional test on notification expiry.
 - **FIX**: fix failing tests.
 - **FIX**: Invalid atKey in notification_response_transformer.dart.
 - **FIX**: expose notification params.
 - **FIX**: allow deleted cached keys to be synced to secondary.
 - **FIX**: update at_client version.
 - **FIX**: debugging.
 - **FIX**: Add functional and e2e tests for commit log compaction.
 - **FIX**: Check the uppercase check regex against both the key and the namespace separately. But only if they are not null.
 - **FIX**: Apply the uppercase regex to atKey.toString() instead of key and namespace separately. AtKey.toString() handles namespace whether null or not.
 - **FIX**: null check error.
 - **FIX**: run dart format.
 - **FIX**: add optional params to forUpdate method.
 - **FIX**: update at_client version.
 - **FIX**: resolve changelog inconsistency.
 - **FIX**: update regex which looks for uppercase in key.
 - **FIX**: add deprecate tag to sync method in sync_service.dart.
 - **FIX**: Update CHANGELOG.md and pubspec.yaml.
 - **FIX**: update CHANGELOG.md and pubspec.yaml.
 - **FIX**: expose notification params.
 - **FIX**: reintroduce StatsAtKeyMatcher in notification_service_test.dart.
 - **FIX**: Pull trunk branch changes into commit log compaction.
 - **FIX**: fix build error.
 - **FIX**: Sync to local fails to delete a cached key.
 - **FIX**: Simplified Monitor's response handler. Lesson taught for the umpteenth time: always write the unit test first.
 - **FIX**: Amend monitor's socket message handler so that it separates responses for every newline received.
 - **FIX**: refactor sync unit tests to use SyncProgress.
 - **FIX**: add commitOp to KeyInfo and refactor tests.
 - **FIX**: add atChops as optional argument in AtServiceFactory.atClient.
 - **FIX**: when fetching `public:publickey` of another atSign from atServer, cache it in local storage instead of depending on sync to take care of that.
 - **FIX**: changed log severity in SyncServiceImpl from severe to warning because sync failures can happen for a whole bunch of mundane reasons.
 - **FIX**: Oops copy-paste snafu.
 - **FIX**: Update e2e and functional tests.
 - **FIX**: check if shared_enc_key exists in the cache.
 - **FIX**: removed singleton from collectionMethodImpl.
 - **FIX**: fixed issues with future test cases.
 - **FIX**: add timeout to e2e tests.
 - **FIX**: update CHANGELOG.md and pubspec.yaml.
 - **FIX**: Changed lifecycle management in AtClientImpl. The static create() factory method now starts the compaction job and calls atClientManager.listenToAtSignChange, whether the AtClientImpl is found in the static instance cache map, or has been newly constructed and _init()-ed. Removed call to atClientManager.listenToAtSignChange from _init() method. _startCompactionJob() method now only calls "scheduleCompaction" if there is not already a compaction job running. Removed the call to atClientInstanceMap.remove(getCurrentAtSign()) from listenToAtSignChange().
 - **FEAT**: adding method return types.
 - **FEAT**: uptake notify fetch changes.
 - **FEAT**: added validate methods in collection util.
 - **FEAT**: added atcollectionmodel checks and refactored static methods.
 - **FEAT**: Add tests.
 - **FEAT**: added collection model factory manager and updated test cases.
 - **FEAT**: Have Monitor use its AtChops to sign the PKAM response, if AtClientPreference.useAtChops is true.
 - **FEAT**: Add AtChops? parameter to AtClientManager.setCurrentAtSign so that it can be injected into the AtClient instance.
 - **FEAT**: Inject AtChops? instance into RemoteSecondary, so that it can pass it to any AtLookupImpl's it creates. Also inject AtChops? instance into Monitor so that it can inject into the RemoteSecondary instance it creates. NotificationServiceImpl and SyncServiceImpl use their AtClient's AtChops? instance when creating their Monitor and RemoteSecondary objects.
 - **FEAT**: deprecate the (misleadingly named) `AtClientPreference.atProtocolEmitted` and change its default value from 1.5.0 to 2.0.0.
 - **FEAT**: fetch various atKeys keys from atChops if we have it (which we always do, now) instead of going to the keyStore.
 - **FEAT**: added id formatter and docs.
 - **FEAT**: deprecate some obsolete functions in the `AtClient` interface.
 - **FEAT**: add `atLookUp` parameter to AtClientManager.setCurrentAtSign, AtClientImpl.create, etc so we can inject an existing AtLookUp instance if we have one rather than having to create a new one and authenticate again.
 - **FEAT**: Initial support of additional encryption metadata enabling encryption future-proofing.
 - **FEAT**: Added PutRequestOptions to AtClient's put(), putText() and putBinary() to allow to specify whether to include the encrypted shared key in shared records' metadata.
 - **FEAT**: Uptake public key hash changes.
 - **FEAT**: sync skip deletes until.
 - **FEAT**: add the AtClientBindings mixin to this package. This mixin was initially added in the noports_core package, but has broader applicability.
 - **FEAT**: prototype telemetry service to support diagnostics.
 - **FEAT**: Add `useRemoteAtServer` to PutRequestOptions. When set, the update.
 - **FEAT**: export the telemetry class.
 - **FEAT**: client commit log compaction.
 - **FEAT**: export sync_service interface.
 - **FEAT**: Implemented desired logic for 'their' copy of the shared symmetric key as laid out in #1041.
 - **FEAT**: client commit log compaction.
 - **FEAT**: enable client to set isEncrypted=false for atClient put.
 - **FEAT**: Add AtRpc - A simple rpc request-response API which uses atProtocol notifications under the hood.
 - **FEAT**: export AtRpc stuff from at_client.dart.
 - **FEAT**: Added AtCollectionModelSpec and its impl.
 - **FEAT**: Added static getAllData method.
 - **FEAT**: client commit log compaction.
 - **FEAT**: Main change in this PR - added optional AtServiceFactory param to AtClientManager.setCurrentAtSign. An AtServiceFactory is responsible for creating instances of AtClient, NotificationService and SyncService. This allows use of AtClientManager with implementations of AtClient, NotificationService and SyncService other than AtClientImpl, NotificationServiceImpl and SyncServiceImpl and in turn this allows setCurrentAtSign functionality to be more easily tested.
 - **FEAT**: Added plain implementaion of non-static methods in AtCollectionImpl.
 - **FEAT**: Added group of saving an object tests cases.
 - **FEAT**: Added group of retreiving, sharing, deleting and unsharing an object tests cases.
 - **FEAT**: code separation b/w stream and future classes.
 - **FEAT**: Modified at_collection_impl_test test cases to use Matcher classes.
 - **FEAT**: Added testing series of operations test cases for at_collection_impl_test.
 - **FEAT**: Added AtCollectionGetterRepository and getAll and getById methods.
 - **FEAT**: Added test case to test a series of operations on an object.
 - **FEAT**: Changed static methods implementation for AtCollectionGetterRepository.
 - **FEAT**: changed getting collectionName approach.
 - **FEAT**: Added test cases for static methods and updated few test cases.
 - **FEAT**: Changed AtCollectionGetterRepository to AtCollectionRepository.
 - **FEAT**: added end to end test for collections future and streams methods.
 - **FEAT**: made AtCollectionModel abstract and removed unused code.
 - **FEAT**: code separation b/w stream and future classes.
 - **FEAT**: added id formatter and docs.
 - **FEAT**: add `allowAll` flag (defaults to false) to AtRpc.
 - **FEAT**: added util file and refactore code.
 - **FEAT**: added end to end test for collections future and streams methods.
 - **FEAT**: client commit log compaction.
 - **FEAT**: added validate methods in collection util.
 - **FEAT**: added atcollectionmodel checks and refactored static methods.
 - **FEAT**: added collection model factory manager and updated test cases.
 - **FEAT**: Sync test with multiple clients.
 - **FEAT**: marked AtRpc as @experimental.
 - **FEAT**: In Monitor, wrap call to `socket.listen()` in runZonedGuarded.
 - **FEAT**: deprecated RemoteSecondary.isAvailable() method (which is completely unused).
 - **FEAT**: client commit log compaction.
 - **FEAT**: removed network availability check from Monitor.
 - **FEAT**: removed NotificationServiceImpl's use of ConnectivityListener.
 - **FEAT**: Remove SyncServiceImpl's unnecessary usage of NetworkUtil.isNetworkAvailable.
 - **FEAT**: remove `AtClientValidation.validateAtKey`'s unnecessary check for existence of an atSign.
 - **FEAT**: remove `AtClientValidation.validateAtKey`'s unnecessary check for existence of an atSign.
 - **FEAT**: Add hostname, port and a checkInterval as optional parameters to ConnectivityListener constructor and use accordingly.
 - **FEAT**: Deprecate ConnectivityListener class.
 - **FEAT**: Add atSign to AtSignLoggers' names when relevant, so that log messages are clearer. For example in AtClientImpl instead of `final _logger = AtSignLogger('AtClientImpl');` we declare `late final AtSignLogger _logger;` and later, in constructor, `_logger = AtSignLogger('AtClientImpl ($_atSign)');`.
 - **FEAT**: add `useRemoteAtServer` flag to `GetRequestOptions`.
 - **FEAT**: at_client apkam changes.
 - **FEAT**: made AtCollectionModel abstract and removed unused code.
 - **FEAT**: adding method return types.
 - **FEAT**: apkam changes for onboarding_cli.
 - **FEAT**: Upgrade the at_client dependencies.
 - **FEAT**: remove useAtChops references in code.
 - **FEAT**: client commit log compaction.
 - **FEAT**: Changed AtCollectionGetterRepository to AtCollectionRepository.
 - **FEAT**: Added test cases for static methods and updated few test cases.
 - **FEAT**: changed getting collectionName approach.
 - **FEAT**: Changed static methods implementation for AtCollectionGetterRepository.
 - **FEAT**: Added test case to test a series of operations on an object.
 - **FEAT**: refactored tests to inject atchops. removed private key from preferences in test files.
 - **FEAT**: Added AtCollectionGetterRepository and getAll and getById methods.
 - **FEAT**: Added testing series of operations test cases for at_collection_impl_test.
 - **FEAT**: Modified at_collection_impl_test test cases to use Matcher classes.
 - **FEAT**: Added group of retreiving, sharing, deleting and unsharing an object tests cases.
 - **FEAT**: Added group of saving an object tests cases.
 - **FEAT**: Added plain implementaion of non-static methods in AtCollectionImpl.
 - **FEAT**: Added static getAllData method.
 - **FEAT**: Added AtCollectionModelSpec and its impl.
 - **FEAT**: added util file and refactore code.
 - **FEAT**: Introduce a local key to skip statsNotificationId.
 - **FEAT**: add apkam_signing mixin from noports.
 - **FEAT**: implement signing in atclient using at_chops.
 - **FEAT**: have AtRpc send ephemeral notifications.
 - **FEAT**: Add AtRpcClient for a much cleaner AtRpc client developer experience.
 - **FEAT**: Added `toString()` implementations for AtRpcReq and AtRpcResp.
 - **FEAT**: initial commit for at_chops uptake.
 - **FEAT**: add request options to exports.
 - **FEAT**: add variable expiryCheckTimeIntervalMins to at_client_preferences.
 - **FEAT**: schedule job to delete expired keys.
 - **FEAT**: unit tests.
 - **FEAT**: replace encryption util encryption methods with at_chops.
 - **FEAT**: unit tests for encryption related logic.
 - **FEAT**: introduce fetchEnrollmentRequest() and underlying classes.
 - **FEAT**: add new classes to the list of exports.
 - **FEAT**: add setAtChops impl to at_client and at_client_spec.
 - **FEAT**: Introduce methods to set SPP and fetch OTP from the secondary server.
 - **FEAT**: APKAM Enrollment changes.
 - **FEAT**: feature flag for at_chops and unit tests.
 - **FEAT**: initial commit for apkam auth check on at_client.
 - **FEAT**: enhance EnrollmentService.fetchEnrollmentRequests() to accept and use enrollmentStatusFilter.
 - **FEAT**: added unit test and moved authorization check to local secondary.
 - **DOCS**: updated changelog reg relevant changes.
 - **DOCS**: update pubspec version and changelog.
 - **DOCS**: Update README.md logo.
 - **DOCS**: update deprecation message in NotificationParams.
 - **DOCS**: update changelog.
 - **DOCS**: update CHANGELOG.md.
 - **DOCS**: update changelog and pubspec.
 - **DOCS**: removed extraneous `α` symbol from changelog entry so it reads `Dart 3` rather than `Dart 3α`.
 - **DOCS**: updated changelog to include another fix which has been merged to trunk since last release.
 - **DOCS**: updated docs in collection files.
 - **DOCS**: improve clarity of addition to the changelog.
 - **DOCS**: Add documentation of putRequestOptions and deleteRequestOptions to the put and delete methods in AtClient spec.
 - **DOCS**: updated comments.
 - **DOCS**: update comments.
 - **DOCS**: add entries to changelog reg this change.
 - **DOCS**: update logger level for upper-case-key log to FINER.
 - **DOCS**: moved a `@Deprecated` annotation to the place dart format prefers it to be.
 - **DOCS**: modified a log message.
 - **DOCS**: Update homepage URL in pubspec.yaml.
 - **DOCS**: update at_client put documentation to include lowercase related changes.
 - **DOCS**: Fixed broken links and improved wording a little in various READMEs.
 - **DOCS**: Updated comment for AtClientManager.setCurrentAtSign.
 - **DOCS**: updated docs in collection files.
 - **DOCS**: update the location of example.

## 3.7.0

- feat: Add `ApkamSigning` mixin
 
## 3.6.0
- feat: deprecate the (misleadingly named)
  `AtClientPreference.atProtocolEmitted` and change its default value
  from 1.5.0 to 2.0.0

## 3.5.3
- feat: fetch various atKeys keys from atChops if we have it (which we always 
  do, now) instead of going to the keyStore
- refactor: some deprecations for readability / maintainability

## 3.5.2
- fix: ensure that namespaces in `notify` requests aren't messed up by 
  multipart namespaces in AtClientPreference (e.g. namespace of `foo.bar`)

## 3.5.1
- fix: ensure that namespace is preserved if it happens to be repeated in a 
  notification's key (e.g. `@bob:foo.my_app.my_app@alice` )

## 3.5.0
- feat: add `atLookUp` parameter to AtClientManager.setCurrentAtSign,
  AtClientImpl.create, etc. so we can inject an existing AtLookUp instance if 
  we have one rather than having to create a new one and authenticate again

## 3.4.4
- fix[performance]: when fetching `public:publickey` of another atSign from
  atServer, cache it in local storage instead of depending on sync to take
  care of that (since programs can disable sync)

## 3.4.3
- build[deps]: update dependencies including at_persistence major version 
  changes
- fix: tightened up code for handling `AtKeyNotFoundException`s in 
  `AtCollectionQueryOperationsImpl`
- fix: Enable the same atSign to be used on both sides (client and server) 
  of an AtRpc interaction
- fix: LocalSecondary.isEnrollmentAuthorizedForOperation now checks if the 
  key in question is a `local` key, in which case the answer is always yes.

## 3.4.2
- build[deps]: update dependencies (at_commons, at_lookup, at_auth)

## 3.4.1
- fix: potential bug handling atSigns which end in `data` e.g. `@foo_data`

## 3.4.0
- feat: Allows clients to skip delete commits until a specific commitID during initial sync
## 3.3.1
- fix: isInSync bug fix for apkam connection
- fix: remove deprecated isPaginated param from SyncVerbBuilder in SyncServiceImpl
- build[deps]: Upgraded dependencies for the following packages:
  - at_commons to v5.1.2
- feat: Introduce "publicKeyHash" which uses SHA hashing to verify change in the encryption public key
## 3.3.0
- feat: add the AtClientBindings mixin which was initially added to the 
  noports_core package but has broader applicability.

## 3.2.2
- build[deps]: Upgraded dependencies for the following packages:
  - at_commons to v5.0.0
  - at_utils to v3.0.19
  - at_lookup to v3.0.49
  - at_auth to v2.0.7
  - at_persistence_secondary_server to v3.0.64
  - at_chops to v2.0.1
## 3.2.1
- feat: add optional param `encryptValue` to notify method
- build[deps]: Upgraded dependencies for the following packages:
  - at_commons to v4.1.1
  - at_utils to v3.0.18
  - at_lookup to v3.0.48
  - at_auth to v2.0.5
  - at_persistence_secondary_server to v3.0.63
## 3.2.0
- feat: add `allowAll` flag (defaults to false) to AtRpc
## 3.1.0
- feat: add `useRemoteAtServer` flag to `GetRequestOptions` to allow clients 
  to fetch directly from the atServer rather than the client-side synced 
  cache. This flag was added to `PutRequestOptions` and 
  `DeleteRequestOptions` in version 3.0.60
- fix: Ensure that `NotificationResponseTransformer` does not attempt to 
  decrypt when `atNotification.isEncrypted == false`
## 3.0.78
- chore: publish clean version 3.0.78
## 3.0.77+1
- fix: remove incorrect version 3.0.78 from changelog
## 3.0.77
- fix: Fix the keys expiry job not being triggered
- chore: deprecate NotificationParams.forText()
- feat: Store enrollment details in local key
- fix: Add "sharedKeyEnc" to the metadata
## 3.0.76
- feat: Introduce mechanism to identify and delete expired keys
- feat: Introduce enrollment service to support enrollment operations:
  - Submit enrollment request(s)
  - Approve, Deny and Revoke enrollment request(s)
## 3.0.75
- feat: Introduce feature to fetch enrollment requests from the server
## 3.0.74
- build[deps]: Upgraded dependencies for the following packages:
  - at_chops to v2.0.0
  - at_lookup to v3.0.45
## 3.0.73
- build[deps]: Upgraded dependencies for the following packages:
    - at_commons to v4.0.0
    - at_utils to v3.0.16
    - at_lookup to v3.0.44
    - at_chops to v1.0.7
    - at_persistence_secondary_server to v3.0.60
- feat: Replace encryption methods from EncryptionUtils with AtChops method 
## 3.0.72
- chore: Minor change to allow us to support dart 
  versions both before and after 3.2.0 specifically for this
  [Dart breaking change](https://github.com/dart-lang/sdk/issues/52801) 
  which was
  [introduced](https://github.com/dart-lang/sdk/blob/main/CHANGELOG.md)
  in dart 3.2.0
## 3.0.71
- feat: Replace decryption methods from EncryptionUtil with AtChops methods
## 3.0.70
- build[deps]: Upgraded dependencies for the following packages:
  - asn1lib: `>=1.4.1 <=1.5.0`, crypton: `>=2.1.0 <=2.2.1`, encrypt: `>=5.0.1 <=5.0.3`, crypto: `^3.0.3`
## 3.0.69
- feat: Add AtRpcClient for a much cleaner developer experience for sending AtRpc requests
## 3.0.68
- feat: have AtRpc use ephemeral notifications
## 3.0.67
- feat: Make enrollment available to SyncService/NotificationService for authentication
## 3.0.66
- feat: make namespace NOT mandatory for local keys
- feat: deprecate useAtChops experimental flag and remove fallback code using private key from preferences/EncryptionUtil methods
- updated at_commons to `'3.0.57'`, at_chops to `'1.0.5`, at_persistence_secondary_server to `'3.0.59'` 
## 3.0.65
- feat: apkam changes for at_onboarding_cli
- build: updated at_commons to `'3.0.55'`, at_chops to `'1.0.4`, at_lookup to `'3.0.40'` 
## 3.0.64
- Made ConnectivityListener configurable, and removed some unnecessary network 
  availability checks
- fix: wrap Monitor's call to `socket.listen()` in a runZonedGuarded block
## 3.0.63
- fix: Fixed bug in AtRpc.sendRequest which was causing repeat sends of requests
## 3.0.62
- fix: skip reserved keys during sync conflict checking
- build: updated dependency on http package to `'>=0.13.5 <2.0.0'`
## 3.0.61
- fix: ensure key exchange functions properly when the sync service is not
  being used
- feat: Add AtRpc - A simple rpc request-response API which uses atProtocol
  notifications under the hood.
## 3.0.60
- feat: Add `useRemoteAtServer` to PutRequestOptions. When set, the update
  request will be sent directly to the remote atServer
- feat: Introduce DeleteRequestOptions
  - Add new optional named parameter `deleteRequestOptions` to AtClient.delete
  - Add `useRemoteAtServer` to DeleteRequestOptions. When set, the delete
    request will be sent directly to the remote atServer
- fix: Incorrect commitId gets updated against commit entry when a sync-batch skips an entry
- fix: Sync/Monitor bug while running onboarding_cli with at_chops using pkam from secure element
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
