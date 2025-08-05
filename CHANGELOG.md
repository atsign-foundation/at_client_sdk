# Change Log

All notable changes to this project will be documented in this file.
See [Conventional Commits](https://conventionalcommits.org) for commit guidelines.

## 2025-08-05

### Changes

---

Packages with breaking changes:

 - There are no breaking changes in this release.

Packages with other changes:

 - [`at_commons` - `v5.5.0`](#at_commons---v550)

---

#### `at_commons` - `v5.5.0`

 - chore: bump at_commons to version 5.5.0

 - **REFACTOR**: rename method _removeNonApplicableElements -> _removeElements in EnrollVerbHandler.
 - **FIX**: Add unrevoke operation to enroll verb.
 - **FIX**: NotifyVerbBuilder.buildCommand: preserve behaviour for MessageTypeEnum.text.
 - **FIX**: `NotifyVerbBuilder.buildCommand()` uses `AtKey.toString()` instead of doing its own thing.
 - **FIX**: removed enable/disable from self notification flag.
 - **FIX**: APKAM revoke changes.
 - **FIX**: Update pubspec.yaml and CHANGELOG.md.
 - **FIX**: change log for at_commons publish.
 - **FIX**: changes to enroll syntax.
 - **FIX**: Add code comments.
 - **FIX**: Modify the enroll verb syntax.
 - **FIX**: review comment.
 - **FIX**: add sync verb params constants.
 - **FIX**: remove deprecation for limit param.
 - **FIX**: modify changelog.
 - **FIX**: removed isPaginated logic.
 - **FIX**: fix unit tests for sync verb builder.
 - **FIX**: changes in at_commons.
 - **FIX**: at_commons 5.1.1 publish changes.
 - **FIX**: added constants for IVs.
 - **FIX**: add IV params in EnrollParams and enroll verb builder.
 - **FIX**: review comments.
 - **FIX**: In unit test modify hash to pubKeyHash to be inline with syntax.
 - **FIX**: Changes in at_commons related to public key hash and implement sha512 hashing algo in at_chops.
 - **FIX**: renamed skipDeletes to skipDeletesUntil.
 - **FIX**: modified changelog and pubspec.
 - **FIX**: sync syntax issue fix.
 - **FIX**: sync kip deletes syntax change and unit test.
 - **FIX**: publish at_commons 5.0.1.
 - **FIX**: export at_key_regex utils.
 - **FIX**: Update enroll verb.
 - **FIX**: review comments in changelog.
 - **FIX**: change pubspec to major version.
 - **FIX**: analyzer issue.
 - **FIX**: added changelog for at_commons.
 - **FIX**: update pkam verb syntax to include SHA512 as hashing algo (#622).
 - **FIX**: Update the version in pubspec.yaml and CHANGELOG.md.
 - **FIX**: Include apkamKeysExpiryDuration in enroll_verb_builder_test.dart.
 - **FIX**: APKAM keys expiry feature changes in at_commons.
 - **FIX**: Update totp verb.
 - **FIX**: change version to 4.1.0.
 - **FIX**: changelog and pubspec.
 - **FIX**: add unit tests for update verb builder isEncrypted.
 - **FIX**: Rename TOTP to OTP.
 - **FIX**: Update the at_commons version to 4.1.0 and CHANGELOG.md.
 - **FIX**: Remove unnecessary spaces in CHANGELOG.md.
 - **FIX**: Update at_commons version in pubspec.yaml and CHANGELOG.md.
 - **FIX**: NotifyVerbBuilder.buildCommand: add a field to prevent this being a breaking change.
 - **FIX**: replace double quotes with single quotes in error description.
 - **FIX**: remove deprecated annotation from `Metadata.pubKeyCS`.
 - **FIX**: Update at_commons CHANGELOG.md.
 - **FIX**: Add force flag to enroll_verb_builder.dart.
 - **FIX**: add changelog and pubspec.
 - **FIX**: remove apkam auth mode from doc.
 - **FIX**: deprecate apkam auth mode.
 - **FIX**: deprecate MessageTypeEnum.text.
 - **FIX**: changelog for publish.
 - **FIX**: added exception invalid enroll revoke.
 - **FIX**: error code for AtEnrollmentException.
 - **FIX**: added fetch param which was missed in the commit.
 - **FIX**: replace double quotes with single quotes in error description.
 - **FIX**: reverted mention of apkamEncryptedSymmetricKey in CHANGELOG.
 - **FIX**: reverted change in at_constants to apkamEncryptedSymmetricKey.
 - **FIX**: correct the change to the reservedKey regex, add another test case.
 - **FIX**: Add shared_key.atsign@atsign to reservedKey regex.
 - **FIX**: Add fetch operation to enroll verb.
 - **FIX**: pub score issue.
 - **FIX**: added unit tests for toString and removed toString from child class.
 - **FIX**: add unit tests for public key toString.
 - **FIX**: key length validation changes.
 - **FIX**: NotifyVerbBuilder.buildCommand: add an optional parameter to prevent this being a breaking change.
 - **FIX**: default EnrollVerbBuilder.enrollmentStatusFilter to null.
 - **FIX**: default EnrollParams.enrollmentStatusFilter to null.
 - **FIX**: Use new variables references in the deprecate message.
 - **FIX**: Add dart documentation.
 - **FIX**: Add default values to enrollment status filter and add enrollment status filter only when operation is list.
 - **FIX**: optionally add enrollmentStatusFilter through enroll_verb_builder.
 - **FIX**: make EnrollParams.enrollmentStatusFilter nullable.
 - **FIX**: removed commented code.
 - **FIX**: removed commented code.
 - **FIX**: change String? approvalStatusFilter -> List<String> enrollmentStatusFilter.
 - **FIX**: Remove validate operation from OTP.
 - **FIX**: Replace use of deprecated variables.
 - **FIX**: Update at_commons version to 4.0.3.
 - **FIX**: Changing the version to 4.0.2.
 - **FIX**: Add ignore to fix dart analyze issue.
 - **FIX**: Add fields to the existing unit tests.
 - **FIX**: Add unit tests for metadata.
 - **FIX**: Null pointer exception when pubKeyHash is null.
 - **FIX**: null check if public key hash jsonmap is empty.
 - **FIX**: add variable for blocklist in AtConstants.
 - **FIX**: export public key hash.
 - **FIX**: update regex for reserved keys.
 - **FIX**: modify tests to validate new regex.
 - **FIX**: use a partial match for reserved keys regex.
 - **FIX**: more changes to regex and more tests.
 - **FIX**: Remove metadata fields in verb builders.
 - **FIX**: deprecate/replace encryptedDefaultEncryptedPrivateKey.
 - **FIX**: Remove the deprecated exceptions from at_commons.dart and run dart formatter.
 - **FIX**: Remove deprecated methods and fields and rename enrollStatus field.
 - **FIX**: enroll verb builder backward compatibility.
 - **FIX**: Update at_commons CHANGELOG.md and run dart formatter.
 - **FEAT**: map AtInvalidEnrollmentException -> AT0029.
 - **FEAT**: monitor verb builder changes.
 - **FEAT**: self notifications flag in monitor.
 - **FEAT**: add encryptData intent.
 - **FEAT**: Add InvalidPinException thrown when an invalid Semi Permanent Passcode is submitted.
 - **FEAT**: replace md5 checksum.
 - **FEAT**: review comments and unit tests.
 - **FEAT**: update enroll regex -> enroll:list accepts optional params.
 - **FEAT**: add new field in EnrollParams named 'approvalStatusFilter'.
 - **FEAT**: Modify the OTP syntax for client to set the expire duration.
 - **FEAT**: at_commons: Add `EnrollmentConstants`.
 - **FEAT**: added exception for enrollment.
 - **FEAT**: add `immutable` to Metadata and `force:` flag to DeleteVerbBuilder.
 - **FEAT**: Add put operation to OTP syntax for SPP.
 - **FEAT**: force flag for enroll:revoke.
 - **FEAT**: change to keys verb syntax.
 - **FEAT**: add error code AT0030 - Invalid enrollment status.
 - **FEAT**: add update to enroll verb syntax.
 - **FEAT**: Update error message.
 - **FEAT**: Add error code and error message.
 - **FEAT**: Introduce AtThrottleLimitExceeded exception.
 - **FEAT**: add new enrollment status 'expired'.
 - **FEAT**: introduce new error code for apkam enrollment expiry.
 - **FEAT**: add isEncrypted is set to false or true in notify command.
 - **FEAT**: Add "EnrollResponse" class for enrollment response.
 - **FEAT**: add delete option to enroll verb (#654).
 - **FEAT**: remove newly introduced exceptions for apkam.
 - **FEAT**: added `AtConstants.atServerReservedNamespace`.
 - **FEAT**: introduce new error codes for apkam.
 - **FEAT**: update verb builder isencrypted.
 - **FEAT**: add skipDeletes to sync syntax.
 - **FEAT**(atcommons): Atsign string extensions.
 - **FEAT**: add AtServerEvent interface and AtSignPKChangedEvent class.
 - **FEAT**: have atSignPKChangedEvent constructor use the new toAtsign function from the new AtsignString extension. Add unit tests to cover.
 - **FEAT**: introduce new exceptions for apkam.
 - **DOCS**: Added doc for AtServerEvent interface.
 - **DOCS**: add 4.0.12 to at_commons CHANGELOG.
 - **DOCS**: update pubspec and changelog.
 - **DOCS**: update changelog.
 - **DOCS**: update docs + add test.
 - **DOCS**: updated changelog and pubspec.
 - **DOCS**: Update README.md logo.

