// Shared by `error_codes_test.dart`, which pins each code (and runs under the
// browser too), and `error_code_inventory_test.dart`, which scans the
// dependency modules (VM only, because it reads files). Nothing here reaches
// `dart:io`, so the browser run can import it.

import 'dart:async';

import 'package:at_auth/at_auth.dart'
    show
        AtAuthenticationException,
        AtAuthErrorReplyException,
        AtEnrollmentResponse,
        AtEnrollmentDeniedException,
        AtEnrollmentExpiredException,
        AtKeysAssuranceException,
        AtKeysEnrollmentException,
        AtKeysFileOverwriteException,
        AtKeysFormatException,
        AtKeysNotInMemoryException,
        AtKeysParseException,
        AtKeysPassphraseException,
        AtKeysProtectionException,
        AtKeysSourceAbsentException,
        AtKeysUnsupportedAlgorithmException,
        AtKeysUnsupportedVersionException,
        AtKeysUnusableCause,
        AtKeysUnusableException,
        AtKeysValidationException;
import 'package:at_auth/passkey.dart'
    show
        PasskeyCeremonyException,
        PasskeyRecordAuthenticationException,
        PrfUnavailableException,
        UnsupportedPasskeyRecordException;
import 'package:at_client/at_client.dart';
import 'package:at_client/at_client_mixins.dart' show KeyPackageStatus;
import 'package:at_client/passkey.dart'
    show
        AtServerAtKeysLockedException,
        AtServerAtKeysWriteException,
        MissingAtKeysDocumentException,
        PasskeyLostException,
        PasskeyOnboardingIncompleteException,
        PkamRefusedException,
        PublicKeyMismatchException;
import 'package:at_client_web/src/exceptions.dart';
import 'package:at_lookup/at_lookup.dart' show AtLookUpException;

const inventorySentinel = 'sentinel-value-7f3a';

final inventoryOfflineState =
    AtConnectionState.offline(AtConnectionCause.unreachable);
final inventoryRefusedState =
    AtConnectionState.refused(AtConnectionCause.revoked);

/// One instance of every exception type a bridge path can be given, whether
/// this package, at_client, at_commons, at_auth or at_lookup declares it, and
/// the browser-side failures too, each with the code it must map to. Every
/// message a constructor takes carries [inventorySentinel], so a test can see
/// it never reaches JS.
///
/// `internal` entries are deliberate: a type that carries nothing the bridge
/// can name (bare `AtException`, `AtClientException` and its generic
/// subclasses, and the client-side response/data checks) is pinned as
/// unexpected. Anything else must name its code here.
final exceptionInventory = <({Object error, String code})>[
  // at_client_web.
  (
    error: InvalidArgumentException('opts', expected: 'an object'),
    code: 'invalid_argument'
  ),
  (
    error: InvalidKeyException.field(
        InvalidArgumentException('key', expected: 'a string')),
    code: 'bad_key'
  ),
  (error: InvalidKeyException(KeyRefusal.atKey), code: 'bad_key'),
  (error: ManageAccessRequiredException(), code: 'unsupported'),
  (error: EnrollmentInFlightException(), code: 'enrollment_in_flight'),
  (error: SessionClosedException(), code: 'closed'),
  (error: AlreadyOpenException(), code: 'already_open'),
  (
    error: PortalSessionOfflineException('@alice', inventoryOfflineState),
    code: 'offline'
  ),
  (error: UnsupportedKeyMaterialException('@alice'), code: 'unsupported'),
  (
    error: UnsupportedOperationException(UnsupportedOperation.secureContext),
    code: 'unsupported'
  ),
  (error: SetupLockTimeoutException(inventorySentinel), code: 'storage_failed'),
  (error: QueueLimitException(16), code: 'invalid_argument'),
  (
    error: IndexedDbException(inventorySentinel,
        browserError: 'QuotaExceededError'),
    code: 'storage_failed'
  ),
  (
    error: JsCollectionsError(CollectionFailure.notFound),
    code: 'COLLECTION_ITEM_NOT_FOUND'
  ),
  // at_client and at_commons.
  (
    error: AtEnrollmentPendingException('@alice', ['eid']),
    code: 'onboarding_incomplete'
  ),
  (
    error: EnrollmentConveyanceException(inventorySentinel,
        response: AtEnrollmentResponse('eid', EnrollmentStatus.approved),
        keyPackageStatus: KeyPackageStatus.rejected),
    code: 'enrollment_conveyance_failed'
  ),
  (error: AtEnrollmentException(inventorySentinel), code: 'enrollment_denied'),
  (
    error: AtInvalidEnrollmentException(inventorySentinel),
    code: 'enrollment_denied'
  ),
  (
    error: AtEnrollmentRevokeException(inventorySentinel),
    code: 'enrollment_denied'
  ),
  (
    error: AtEnrollmentCancelledException(inventorySentinel),
    code: 'enrollment_denied'
  ),
  (
    error: AtOpenRefusedException('@alice', inventoryRefusedState),
    code: 'pkam_refused'
  ),
  (
    error: AtCredentialRefusedException('@alice', inventoryRefusedState),
    code: 'pkam_refused'
  ),
  (
    error: AtStorageInUseException('loc', inventorySentinel),
    code: 'already_open'
  ),
  (error: AtNoCredentialException('@alice'), code: 'bad_key'),
  (error: StoppedException(inventorySentinel), code: 'closed'),
  (error: SecondaryConnectException(inventorySentinel), code: 'offline'),
  (error: AtConnectException(inventorySentinel), code: 'offline'),
  (error: RootServerConnectivityException(inventorySentinel), code: 'offline'),
  (
    error: SecondaryServerConnectivityException(inventorySentinel),
    code: 'offline'
  ),
  (error: SecondaryNotFoundException(inventorySentinel), code: 'offline'),
  (error: HandShakeException(inventorySentinel), code: 'offline'),
  (error: ConnectionInvalidException(inventorySentinel), code: 'offline'),
  (
    error: OutBoundConnectionInvalidException(inventorySentinel),
    code: 'offline'
  ),
  (error: AtIOException(inventorySentinel), code: 'offline'),
  (error: AtCertificateValidationException(inventorySentinel), code: 'offline'),
  (error: BlockedConnectionException(inventorySentinel), code: 'offline'),
  (error: UnAuthorizedException(inventorySentinel), code: 'refused'),
  (error: UnAuthenticatedException(inventorySentinel), code: 'pkam_refused'),
  (error: AtTimeoutException(inventorySentinel), code: 'timeout'),
  (error: TimeoutException(inventorySentinel), code: 'timeout'),
  (error: AtServerException(inventorySentinel), code: 'refused'),
  (error: InternalServerError(inventorySentinel), code: 'refused'),
  (error: InternalServerException(inventorySentinel), code: 'refused'),
  (error: ServerIsPausedException(inventorySentinel), code: 'refused'),
  (error: LookupException(inventorySentinel), code: 'refused'),
  (error: AtThrottleLimitExceeded(inventorySentinel), code: 'refused'),
  (error: InboundConnectionLimitException(inventorySentinel), code: 'refused'),
  (error: OutboundConnectionLimitException(inventorySentinel), code: 'refused'),
  (error: InvalidSyntaxException(inventorySentinel), code: 'refused'),
  (error: InvalidRequestException(inventorySentinel), code: 'refused'),
  (error: IllegalStateException(inventorySentinel), code: 'refused'),
  (error: IllegalArgumentException(inventorySentinel), code: 'refused'),
  // Client-side protocol checks: nothing the bridge can name.
  (error: InvalidResponseException(inventorySentinel), code: 'internal'),
  (error: InvalidDataException(inventorySentinel), code: 'internal'),
  (error: AtException(inventorySentinel), code: 'internal'),
  (error: AtClientException('AT0001', inventorySentinel), code: 'internal'),
  (error: AtValueException(inventorySentinel), code: 'internal'),
  (error: InvalidPinException('AT0014', inventorySentinel), code: 'internal'),
  (error: CryptoProviderNotRegistered(inventorySentinel), code: 'internal'),
  (error: BufferOverFlowException(inventorySentinel), code: 'invalid_argument'),
  (error: AtKeyException(inventorySentinel), code: 'bad_key'),
  (error: AtKeyNotFoundException(inventorySentinel), code: 'bad_key'),
  (error: InvalidAtKeyException(inventorySentinel), code: 'bad_key'),
  (error: KeyNotFoundException(inventorySentinel), code: 'bad_key'),
  (error: AtEncryptionException(inventorySentinel), code: 'bad_key'),
  (error: AtDecryptionException(inventorySentinel), code: 'bad_key'),
  (error: AtPublicKeyChangeException(inventorySentinel), code: 'bad_key'),
  (error: AtPublicKeyNotFoundException(inventorySentinel), code: 'bad_key'),
  (error: AtPrivateKeyNotFoundException(inventorySentinel), code: 'bad_key'),
  (error: SharedKeyNotFoundException(inventorySentinel), code: 'bad_key'),
  (error: SelfKeyNotFoundException(inventorySentinel), code: 'bad_key'),
  (error: AtSigningException(inventorySentinel), code: 'bad_key'),
  (error: AtSigningVerificationException(inventorySentinel), code: 'bad_key'),
  (error: InvalidAtSignException(inventorySentinel), code: 'bad_key'),
  // at_auth.
  (error: AtAuthenticationException(inventorySentinel), code: 'bad_key'),
  (
    error: AtAuthErrorReplyException(inventorySentinel, errorCode: 'AT0401'),
    code: 'pkam_refused'
  ),
  (
    error: AtEnrollmentExpiredException(inventorySentinel),
    code: 'enrollment_denied'
  ),
  (
    error: AtEnrollmentDeniedException(inventorySentinel),
    code: 'enrollment_denied'
  ),
  (error: AtKeysFileOverwriteException(inventorySentinel), code: 'bad_key'),
  (error: AtKeysParseException(inventorySentinel), code: 'bad_key'),
  (
    error: AtKeysFormatException.notAnObject(inventorySentinel),
    code: 'bad_key'
  ),
  (error: AtKeysPassphraseException(inventorySentinel), code: 'bad_key'),
  (error: AtKeysValidationException(inventorySentinel), code: 'bad_key'),
  (
    error: AtKeysUnsupportedVersionException(inventorySentinel),
    code: 'bad_key'
  ),
  (
    error: AtKeysUnsupportedAlgorithmException(inventorySentinel),
    code: 'bad_key'
  ),
  (error: AtKeysProtectionException(inventorySentinel), code: 'bad_key'),
  (error: AtKeysEnrollmentException(inventorySentinel), code: 'bad_key'),
  (error: AtKeysSourceAbsentException(inventorySentinel), code: 'bad_key'),
  (error: AtKeysNotInMemoryException(inventorySentinel), code: 'bad_key'),
  (error: AtKeysAssuranceException(inventorySentinel), code: 'bad_key'),
  (
    error: AtKeysUnusableException(inventorySentinel,
        atSign: '@alice', cause: AtKeysUnusableCause.absent),
    code: 'bad_key'
  ),
  // at_client passkey.
  (error: PkamRefusedException('eid'), code: 'pkam_refused'),
  (error: PasskeyLostException('@alice', inventorySentinel), code: 'bad_key'),
  (
    error: PasskeyOnboardingIncompleteException(Atsign('@alice'),
        cause: Exception(inventorySentinel)),
    code: 'onboarding_incomplete'
  ),
  (error: MissingAtKeysDocumentException('eid'), code: 'onboarding_incomplete'),
  (error: PublicKeyMismatchException(), code: 'bad_key'),
  (
    error: AtServerAtKeysWriteException(inventorySentinel),
    code: 'storage_failed'
  ),
  (
    error: AtServerAtKeysLockedException(inventorySentinel),
    code: 'storage_failed'
  ),
  // at_auth passkey.
  (error: PasskeyCeremonyException(inventorySentinel), code: 'bad_key'),
  (error: PasskeyRecordAuthenticationException(), code: 'bad_key'),
  (error: PrfUnavailableException(inventorySentinel), code: 'unsupported'),
  (
    error: UnsupportedPasskeyRecordException(inventorySentinel),
    code: 'unsupported'
  ),
  // at_lookup.
  (error: AtLookUpException('AT0001', inventorySentinel), code: 'refused'),
  (error: AtLookUpException('AT0021', inventorySentinel), code: 'offline'),
  (error: AtLookUpException('AT0023', inventorySentinel), code: 'timeout'),
  (error: AtLookUpException('AT0401', inventorySentinel), code: 'pkam_refused'),
  (error: AtLookUpException('AT0015', inventorySentinel), code: 'bad_key'),
  (error: AtLookUpException('AT0016', inventorySentinel), code: 'bad_key'),
];

/// The types [exceptionInventory] names, by runtime type.
final inventoryTypes = {
  for (final entry in exceptionInventory) entry.error.runtimeType.toString()
};
