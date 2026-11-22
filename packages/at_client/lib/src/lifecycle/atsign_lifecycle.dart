import 'dart:async';

import 'package:at_auth/at_auth.dart';
import 'package:at_chops/at_chops.dart' show SigningAlgoType;
import 'package:at_client/src/client/at_client_factory.dart';
import 'package:at_client/src/client/at_client_impl.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/enroll/first_enrollment.dart';
import 'package:at_client/src/enroll/signing_key_mint.dart'
    show mintAdvertisedSigningKey;
import 'package:at_client/src/lifecycle/at_connection.dart';
import 'package:at_client/src/lifecycle/authenticated_lookup.dart';
import 'package:at_client/src/lifecycle/pending_enrollment.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/preference/at_client_particulars.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/preference/client_config.dart';
import 'package:at_client/src/secret_sharing/enrollment_key_package.dart'
    show enrollmentKeyPackageBuilder;
import 'package:at_client/src/secret_sharing/enrollment_symmetric_key.dart'
    show enrollmentApkamSymmetricKeyResolver;
import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';
import 'package:at_utils/at_progress.dart';

/// An empty in-memory key store for a step that files keys the caller then
/// reads back out, such as an enrollment request or an activation. Nothing in
/// it outlives the process, so a client never runs on it.
WrittenAtKeysIo scratchKeysIo() =>
    // ignore: invalid_use_of_visible_for_testing_member
    InMemoryAtKeysIo();

/// Runs [atSign]'s activation, as [AtsignLifecycle.activate] does, without
/// opening a client: files the minted keys in [keys] and returns the new
/// enrollment's id.
///
/// With [completeActivation] false the encryption public key is not
/// published and the CRAM secret is not deleted, so the caller completes the
/// activation later with `completeActivationOf`. Every `from:` the activation
/// sends carries [clientConfig], as [activateAtSign] takes it. See
/// [AtsignLifecycle.activate] for every other parameter.
Future<String> activateWithoutClient(
  Atsign atSign, {
  required String cramSecret,
  required WrittenAtKeysIo keys,
  required AtClientPreference preference,
  String app = firstEnrollmentAppName,
  String device = firstEnrollmentDeviceName,
  bool? mintLegacyMaterial,
  SigningAlgoType? signingAlgo,
  ({String publicKey, String privateKey})? apkamKeyPair,
  Duration? provisioningBudget,
  Duration provisioningPollInterval = RetryOptions.defaultRetryDelay,
  void Function(ProgressEvent event)? onProgress,
  AtLookupMuxable? atLookUp,
  required AtLookUpFactory lookUps,
  required SecondaryAddressFinder secondaryAddressFinder,
  required bool completeActivation,
  required Map<String, dynamic> clientConfig,
}) async {
  final algo = signingAlgo ?? preference.authenticationKeyAlgorithm;
  final pqNative = algo == SigningAlgoType.mldsa65;
  final rootDomain = AtRootDomain(preference.rootDomain, preference.rootPort);
  ({
    SigningAlgoType algorithm,
    String publicKey,
    String privateKey
  })? advertisedSigningKey;
  FutureOr<Map<String, dynamic>?> Function(AtKeysIo)? metadataBuilder;
  if (pqNative) {
    final material = await pqNativeActivationMaterial(
        atSign: atSign,
        dataSigningKeyAlgorithms: preference.dataSigningKeyAlgorithms,
        keyEstablishmentAlgo: preference.keyEstablishmentAlgorithms.first);
    advertisedSigningKey = material.advertisedSigningKey;
    metadataBuilder = material.metadataBuilder;
  }
  // The activation's own connection, built the way the application chose
  // and closed when it is done; a supplied one is the caller's to close.
  final connection = atLookUp ??
      lookUps(
          atSign: atSign,
          rootDomain: rootDomain,
          authenticator: null,
          secondaryAddressFinder: secondaryAddressFinder);
  try {
    return await activateAtSign(
        atSign: atSign,
        cramSecret: cramSecret,
        keys: keys,
        signingAlgo: algo,
        apkamKeyPair: apkamKeyPair,
        rootDomain: rootDomain,
        appName: app,
        deviceName: device,
        mintLegacyMaterial:
            mintLegacyMaterial ?? preference.posture.mintLegacyMaterial,
        metadataBuilder: metadataBuilder,
        advertisedSigningKey: advertisedSigningKey,
        retryOptions: RetryOptions(
            maxRetries: RetryOptions.defaultMaxRetries,
            retryDelay: provisioningPollInterval,
            overallTimeout: provisioningBudget),
        onProgress: onProgress,
        completeActivation: completeActivation,
        atLookUp: connection,
        awaitProvisioning: atLookUp == null,
        clientConfig: clientConfig);
  } finally {
    if (atLookUp == null) await connection.close();
  }
}

/// The verbs an application reaches a working client through, on the atSign
/// it holds keys for.
///
/// ```dart
/// final preference = AtClientPreference();
/// final lookUps = secureSocketLookUps();
/// final finder = CacheableSecondaryAddressFinder(
///     preference.rootDomain, preference.rootPort);
/// final client = await Atsign('@alice').open(
///     keys: FileAtKeysIo(), storage: storage, preference: preference,
///     lookUps: lookUps, secondaryAddressFinder: finder);
/// client.connection.current;          // online, offline or refused
/// client.connection.changes.listen((state) { ... });
/// AtClientManager.getInstance().use(client);
///
/// final pending = await Atsign('@alice').enroll(otp: otp, app: 'wavi',
///     device: 'phone', namespaces: {'wavi': 'rw'}, keys: FileAtKeysIo(),
///     preference: preference, lookUps: lookUps,
///     secondaryAddressFinder: finder);
/// final client = await pending.client(preference, storage: storage);
/// // after a restart:
/// final resumed = await Atsign('@alice').resumeEnrollment(
///     keys: FileAtKeysIo(), preference: preference, lookUps: lookUps,
///     secondaryAddressFinder: finder);
/// ```
///
/// `FileAtKeysIo`, `secureSocketLookUps` and `CacheableSecondaryAddressFinder`
/// are a native program's, from `package:at_client/at_client_io.dart`.
extension AtsignLifecycle on Atsign {
  /// Builds a client for this atSign from [keys], tries once to reach the
  /// atServer within [connectBudget], and hands the client back with
  /// `connection.current` saying how that went. The caller owns the client
  /// and ends it with `stop()`.
  ///
  /// [keys] are read first, and keys that cannot be used throw
  /// [AtKeysUnusableException] before anything is written or any connection
  /// opened, on every device: keys that are absent, that cannot be read, or
  /// that record another atSign (keys that record none are used), or that
  /// hold no keypair the authenticator could sign with.
  /// Keys that hold nothing but an enrollment awaiting approval are refused
  /// with [AtEnrollmentPendingException]: [resumeEnrollment] picks that up.
  /// Keys that hold neither, as a denial, a cancel or an expiry leaves them,
  /// are refused with [AtNoCredentialException]. Both are
  /// [AtKeysUnusableException]s.
  ///
  /// The client comes back whether the atServer was reached or not: offline
  /// it serves everything its local storage holds, and `connection.changes`
  /// reports when that changes. The one exception is the first open of a
  /// principal on a device: with nothing held locally for these keys, a
  /// refusal (revoked, unauthenticated, an expired or unapproved enrollment,
  /// or an atSign the atDirectory has no atServer for) throws
  /// [AtOpenRefusedException] and nothing is handed back, since there would
  /// be nothing for the client to serve. Once a principal has been online on
  /// a device, a refusal comes back as a client in the `refused` state and
  /// the application decides.
  ///
  /// [namespace] defaults to the preference's. [storage] is the client's
  /// local storage, borrowed unless it was built with `closedByClient: true`.
  /// [lookUps] builds every connection the client opens - its own, its
  /// sync's, its monitor's - and is how an application chooses the transport
  /// or a proxy convention. [secondaryAddressFinder] finds the atServer each
  /// of them reaches, and the client remembers its answer in [storage], so a
  /// later start with the atDirectory unreachable still finds it.
  /// [atLookUp] is a connection to use instead of one built, for a caller
  /// that already holds one; the client takes it over and installs its own
  /// credentials on it, so a caller that goes on using it acts as the client;
  /// stopping the client stops it.
  /// [serviceFactory] supplies the client's
  /// notification, sync and enrollment services in place of the defaults; a
  /// process that must not sync hands in a factory whose sync service does
  /// nothing.
  ///
  /// Refuses, as `buildAtClient` does, while a client for this atSign as the
  /// same enrollment is live in this process; another enrollment of the
  /// atSign opens beside it, given a store of its own.
  Future<AtClient> open({
    required AtKeysIo keys,
    required AtClientPreference preference,
    String? namespace,
    required AtClientStorage storage,
    AtLookUp? atLookUp,
    required AtLookUpFactory lookUps,
    required SecondaryAddressFinder secondaryAddressFinder,
    AtServiceFactory? serviceFactory,
    Duration connectBudget = AtConnection.defaultBudget,
  }) async {
    await _refuseUnusableKeys(keys);
    final client = await buildAtClient(
      atSign: this,
      namespace: namespace ?? preference.namespace,
      preference: preference,
      storage: storage,
      atKeysIo: keys,
      atLookUp: atLookUp,
      lookUps: lookUps,
      secondaryAddressFinder: secondaryAddressFinder,
      notificationServiceBuilder: serviceFactory == null
          ? null
          : (client) => serviceFactory.notificationService(client),
      syncServiceBuilder: serviceFactory == null
          ? null
          : (client) => serviceFactory.syncService(client),
      enrollmentServiceBuilder: serviceFactory?.enrollmentService,
    ) as AtClientImpl;

    final state = await client.connection.attempt(budget: connectBudget);
    final refusesFirstOpen =
        state.isRefused || state.cause == AtConnectionCause.noAtServer;
    if (refusesFirstOpen && !await client.hasBeenOnline()) {
      await client.stop();
      throw AtOpenRefusedException(this, state);
    }
    return client;
  }

  /// Authenticates once as the enrollment [keys] name, closes the
  /// connection, and hands back that enrollment id, `primary` for a keyfile
  /// that predates enrollments. No client is built and nothing is stored.
  /// A refusal throws [AtCredentialRefusedException] carrying the cause
  /// `open` would have reported; a failure to reach the atServer is thrown
  /// as it is.
  ///
  /// [lookUps] builds the connection, which finds the atServer through
  /// [secondaryAddressFinder].
  ///
  /// [particulars] name the app on the connection's `from:`, as a client's
  /// `AtClientPreference.atClientParticulars` do.
  Future<String> authenticatesAs({
    required AtKeysIo keys,
    required AtRootDomain rootDomain,
    required AtLookUpFactory lookUps,
    required SecondaryAddressFinder secondaryAddressFinder,
    AtClientParticulars? particulars,
  }) async {
    final enrollmentId = (await keys.read(this)).enrollmentToAuthenticateAs();
    final AtLookUp lookUp;
    try {
      lookUp = await authenticatedLookUp(this, keys, rootDomain,
          enrollmentId: enrollmentId,
          lookUps: lookUps,
          secondaryAddressFinder: secondaryAddressFinder,
          clientConfig: clientConfigOf(particulars));
    } catch (e) {
      final state = classifyConnectionFailure(e);
      if (state != null && state.isRefused) {
        throw AtCredentialRefusedException(this, state);
      }
      rethrow;
    }
    await lookUp.close();
    return enrollmentId;
  }

  /// Activates this atSign with its one-time [cramSecret], writing the keys
  /// the activation mints into [keys], and opens a client on them that the
  /// caller owns.
  ///
  /// The activation is the atSign's first enrollment, named [app] on
  /// [device] and granted everything. Its APKAM algorithm is [signingAlgo],
  /// defaulting to the preference's `authenticationKeyAlgorithm`; `mldsa65`
  /// makes the atSign post-quantum from birth, with a data signing key and a
  /// key package on the request that creates the record, and the signing
  /// root minted once the client is up. [mintLegacyMaterial] cuts the RSA
  /// encryption keypair and the self-encryption key, and defaults to the
  /// posture's answer. Without them `AtClient.put` of a public value throws
  /// `AtPrivateKeyNotFoundException`, since it signs the value with the RSA
  /// encryption private key. [onProgress] hears each step of the activation.
  ///
  /// [apkamKeyPair] is an APKAM keypair the caller already holds, enrolled
  /// instead of a minted one. It must sign under the activation's algorithm,
  /// or the activation throws `AtSigningException` before enrolling.
  /// If the activation fails after the enrollment is accepted (the PKAM login or
  /// the keyfile write), retrying with the same pair is refused by the atServer
  /// while that enrollment's record exists: retry with a different pair, or with
  /// none so one is minted. The CRAM secret stays valid until an activation
  /// completes.
  ///
  /// A newly registered atSign can take minutes to be provisioned: the
  /// activation polls every [provisioningPollInterval] until the atServer
  /// answers or [provisioningBudget] is spent, five minutes with none, and
  /// then throws [AtTimeoutException].
  ///
  /// See [open] for [namespace], [storage], [lookUps],
  /// [secondaryAddressFinder], [atLookUp] and [connectBudget]; the activation
  /// runs on a connection [lookUps] builds to the atServer
  /// [secondaryAddressFinder] finds,
  /// or on a supplied [atLookUp], which is taken as having already reached
  /// the atServer, so the provisioning wait is skipped. A supplied [atLookUp]
  /// that its caller stops during the activation ends it with
  /// [StoppedException], and no client is left running. A stop after the
  /// PKAM has succeeded leaves [keys] written and, if it lands before the
  /// encryption public key is published and the CRAM secret deleted, the
  /// activation incomplete; `completeActivationOf` finishes it.
  Future<AtClient> activate({
    required String cramSecret,
    required WrittenAtKeysIo keys,
    required AtClientPreference preference,
    String? namespace,
    required AtClientStorage storage,
    String app = firstEnrollmentAppName,
    String device = firstEnrollmentDeviceName,
    bool? mintLegacyMaterial,
    SigningAlgoType? signingAlgo,
    ({String publicKey, String privateKey})? apkamKeyPair,
    Duration? provisioningBudget,
    Duration provisioningPollInterval = RetryOptions.defaultRetryDelay,
    void Function(ProgressEvent event)? onProgress,
    AtLookupMuxable? atLookUp,
    required AtLookUpFactory lookUps,
    required SecondaryAddressFinder secondaryAddressFinder,
    Duration connectBudget = AtConnection.defaultBudget,
  }) async {
    await activateWithoutClient(this,
        cramSecret: cramSecret,
        keys: keys,
        preference: preference,
        app: app,
        device: device,
        mintLegacyMaterial: mintLegacyMaterial,
        signingAlgo: signingAlgo,
        apkamKeyPair: apkamKeyPair,
        provisioningBudget: provisioningBudget,
        provisioningPollInterval: provisioningPollInterval,
        onProgress: onProgress,
        atLookUp: atLookUp,
        lookUps: lookUps,
        secondaryAddressFinder: secondaryAddressFinder,
        completeActivation: true,
        clientConfig: clientConfigOf(preference.atClientParticulars));
    final pqNative = (signingAlgo ?? preference.authenticationKeyAlgorithm) ==
        SigningAlgoType.mldsa65;

    final client = await open(
        keys: keys,
        preference: preference,
        namespace: namespace,
        storage: storage,
        atLookUp: atLookUp,
        lookUps: lookUps,
        secondaryAddressFinder: secondaryAddressFinder,
        connectBudget: connectBudget);
    // NOTE: open reports a stop during its first connect as an offline
    // client, and mintSigningRootAfterActivation rethrows a stop but swallows
    // every other error; a stop anywhere in the activation ends it as
    // documented, with the client stopped.
    try {
      final stopped = client.connection.current.error;
      if (stopped is StoppedException) throw stopped;
      if (pqNative) {
        await mintSigningRootAfterActivation(client, atKeysIo: keys);
      }
    } on StoppedException {
      await client.stop();
      rethrow;
    }
    return client;
  }

  /// Asks the atSign's manager to enrol this device as [app] on [device] with
  /// [namespaces], quoting [otp], and files the keys the request minted in
  /// [keys] as pending under the new enrollment.
  ///
  /// Returns at once with a [PendingEnrollment]: its `client` waits for the
  /// decision, and after a restart [resumeEnrollment] finds the same request
  /// in [keys]. [keys] must hold nothing live and nothing pending for this
  /// atSign: a store that already holds a pending enrollment, whatever its
  /// app and device, is refused with [AtEnrollmentException] naming it,
  /// before anything is sent, in favour of resuming it. The check is made
  /// again inside the store's [WrittenAtKeysIo.update] as the request is
  /// filed, so of two enrolls into one store at once only one is filed
  /// wherever that update is one operation, as a keyfile's is across
  /// processes and a keychain's within one isolate; the other throws
  /// [AtEnrollmentException] naming the enrollment it sent, which the
  /// atSign's manager can deny.
  ///
  /// [signingAlgo] is the APKAM algorithm the enrollment authenticates with
  /// and [keyExchangeMode] how its symmetric key travels; both default to the
  /// preference's posture. [apkamKeysExpiry] asks the atServer to expire the
  /// enrollment's keys after that long. [lookUps] builds the connection the
  /// request goes out on and every one the enrollment opens after it, each to
  /// the atServer [secondaryAddressFinder] finds;
  /// [atLookUp] is one to submit on instead, for a caller that already holds
  /// one, and the client the enrollment opens takes it over as [open] does.
  /// The request itself travels unauthenticated, since this device holds no
  /// credential yet.
  ///
  /// It takes no storage: the request goes out first, and the
  /// [PendingEnrollment]'s `client` waits for the decision and then opens on
  /// the storage it is given.
  Future<PendingEnrollment> enroll({
    required String otp,
    required String app,
    required String device,
    required Map<String, String> namespaces,
    required WrittenAtKeysIo keys,
    required AtClientPreference preference,
    SigningAlgoType? signingAlgo,
    EnrollmentKeyExchangeMode? keyExchangeMode,
    Duration? apkamKeysExpiry,
    AtLookupMuxable? atLookUp,
    required AtLookUpFactory lookUps,
    required SecondaryAddressFinder secondaryAddressFinder,
  }) async {
    final rootDomain = AtRootDomain(preference.rootDomain, preference.rootPort);
    final algo = signingAlgo ?? preference.authenticationKeyAlgorithm;
    final mode = keyExchangeMode ?? preference.posture.keyExchangeMode;
    await _refuseUnlessEnrollable(keys);

    // NOTE: the enrollment owns its signing key from its first byte: `_apsk`
    // advertises it and the key package is signed with it, so minting it at a
    // later start would publish a record naming one key beside a package
    // signed by another.
    final advertisedSigningKey =
        await mintAdvertisedSigningKey(preference.dataSigningKeyAlgorithms);
    // NOTE: a scratch store; the enrollment's keys are filed into [keys].
    final session = AtAuthSession(
        atSign: this, rootDomain: rootDomain, atKeysIo: scratchKeysIo());
    final AtEnrollmentRequest request;
    if (mode == EnrollmentKeyExchangeMode.pq) {
      request = AtEnrollmentRequest.pq(
          session: session,
          appName: app,
          deviceName: device,
          namespaces: namespaces,
          otp: otp,
          signingAlgo: algo,
          advertisedSigningKey: advertisedSigningKey,
          metadataBuilder: enrollmentKeyPackageBuilder(this,
              signingAlgo: algo,
              advertisedSigningKey: advertisedSigningKey,
              keyEstablishmentAlgo:
                  preference.keyEstablishmentAlgorithms.first),
          apkamSymmetricKeyResolver: enrollmentApkamSymmetricKeyResolver(this));
    } else {
      request = AtEnrollmentRequest(
          session: session,
          appName: app,
          deviceName: device,
          namespaces: namespaces,
          otp: otp,
          signingAlgo: algo,
          advertisedSigningKey: advertisedSigningKey);
    }
    request.apkamKeysExpiryDuration = apkamKeysExpiry;

    final lookUp = atLookUp ??
        lookUps(
            atSign: this,
            rootDomain: rootDomain,
            authenticator: null,
            secondaryAddressFinder: secondaryAddressFinder);
    final AtEnrollmentResponse response;
    try {
      response = await enrollmentFor(preference.atClientParticulars)
          .submit(request, lookUp);
    } finally {
      if (atLookUp == null) await lookUp.close();
    }

    // ignore: deprecated_member_use
    final minted = response.atAuthKeys!;
    await _fileAsPending(keys,
        minted: minted,
        enrollmentId: response.enrollmentId,
        algorithm: algo,
        app: app,
        device: device,
        namespaces: namespaces);
    return PendingEnrollment(
        atSign: this,
        enrollmentId: response.enrollmentId,
        app: app,
        device: device,
        namespaces: namespaces,
        keys: keys,
        rootDomain: rootDomain,
        signingAlgo: algo,
        keyExchangeMode: mode,
        atLookUp: atLookUp,
        particulars: preference.atClientParticulars,
        lookUps: lookUps,
        secondaryAddressFinder: secondaryAddressFinder);
  }

  /// The enrollment [enroll] filed in [keys] and has not yet completed, or
  /// null when there is none: the way an application picks up an enrollment
  /// it submitted before a restart, to wait for its approval or cancel it.
  ///
  /// A key store holds at most one pending enrollment, and this returns it
  /// whatever app and device it was filed under. A store holding more, which
  /// only a merge, a restore or a hand edit makes, gives the one its
  /// `enrollmentId` field names, else the first, and logs a warning;
  /// cancelling each in turn clears the rest.
  ///
  /// [preference] supplies the root domain; [lookUps] builds the connections
  /// the enrollment opens, to the atServer [secondaryAddressFinder] finds,
  /// and [atLookUp] is one for the approval handshake,
  /// for a caller that already holds one, which the client the enrollment
  /// opens takes over as [open] does.
  Future<PendingEnrollment?> resumeEnrollment({
    @Deprecated('Ignored: a key store holds at most one pending enrollment, '
        'which is returned whatever app it was filed under')
    String? app,
    @Deprecated('Ignored: a key store holds at most one pending enrollment, '
        'which is returned whatever device it was filed under')
    String? device,
    required WrittenAtKeysIo keys,
    required AtClientPreference preference,
    AtLookupMuxable? atLookUp,
    required AtLookUpFactory lookUps,
    required SecondaryAddressFinder secondaryAddressFinder,
  }) async {
    final AtKeys stored;
    try {
      stored = await keys.read(this);
    } on AtKeysSourceAbsentException {
      return null;
    }
    final enrollmentId = _pendingToResume(stored);
    if (enrollmentId == null) return null;
    final count = stored.pendingEnrollmentIds.length;
    if (count > 1) {
      AtSignLogger('AtsignLifecycle ($this)').warning(
          '${theAtKeysStore(keys.describeSource(this))} holds $count pending '
          'enrollments of $this, where an AtKeys store holds at most one: '
          'resuming '
          '"${clipForMessage(enrollmentId, quote: '"')}"');
    }
    final info = stored.enrollmentInfo(enrollmentId);
    final apkam = stored
        .keysForEnrollment(enrollmentId)
        .where((m) =>
            m.role == CryptographicMaterialRole.privateAuthentication &&
            m.status == CryptographicMaterialStatus.pending)
        .first;
    return PendingEnrollment(
        atSign: this,
        enrollmentId: enrollmentId,
        app: info?.appName ?? '',
        device: info?.deviceName ?? '',
        namespaces: info?.namespaces ?? const {},
        keys: keys,
        rootDomain: AtRootDomain(preference.rootDomain, preference.rootPort),
        signingAlgo: SigningAlgoType.values
            .firstWhere((a) => a.name == apkam.algorithm.toString()),
        // A legacy request carries its own symmetric key in; a pq request
        // has none until the approver encapsulates one to its key package.
        // ignore: deprecated_member_use
        keyExchangeMode: stored.apkamSymmetricKey == null
            ? EnrollmentKeyExchangeMode.pq
            : EnrollmentKeyExchangeMode.legacy,
        atLookUp: atLookUp,
        particulars: preference.atClientParticulars,
        lookUps: lookUps,
        secondaryAddressFinder: secondaryAddressFinder);
  }

  /// Throws [AtKeysUnusableException] unless [keys] hold a credential for
  /// this atSign.
  Future<void> _refuseUnusableKeys(AtKeysIo keys) async {
    final AtKeys stored;
    try {
      stored = await keys.read(this);
    } on AtKeysSourceAbsentException catch (e, stackTrace) {
      _refuse(
          AtKeysUnusableException.absent(this,
              source: keys.describeSource(this), error: e),
          stackTrace);
    } catch (e, stackTrace) {
      _refuse(
          AtKeysUnusableException.unreadable(this,
              source: keys.describeSource(this), error: e),
          stackTrace);
    }
    final recorded = stored.atsign;
    if (recorded != null && recorded.toAtsign() != toAtsign()) {
      throw AtKeysUnusableException.anotherAtsign(this, recorded,
          source: keys.describeSource(this));
    }
    if (!stored.holdsAuthenticationMaterial) {
      final pending = stored.pendingEnrollmentIds.toList();
      if (pending.isNotEmpty) {
        throw AtEnrollmentPendingException(this, pending,
            source: keys.describeSource(this));
      }
      throw AtNoCredentialException(this, source: keys.describeSource(this));
    }
    try {
      // NOTE: the keypair the authenticator signs with, resolved as it
      // resolves it, so keys it cannot sign with are refused here.
      final keyPair =
          stored.authenticationKeyPairFor(stored.enrollmentToAuthenticateAs());
      if (keyPair == null) {
        throw AtKeyNotFoundException('AtKeys holds no authentication keypair '
            'for the enrollment it authenticates as, so there is nothing to '
            'sign with');
      }
    } catch (e, stackTrace) {
      _refuse(
          AtKeysUnusableException.noAuthenticationKeypair(this,
              source: keys.describeSource(this), error: e),
          stackTrace);
    }
  }

  /// Throws [unusable] with the [stackTrace] of what made the keys unusable.
  Never _refuse(AtKeysUnusableException unusable, StackTrace stackTrace) =>
      Error.throwWithStackTrace(unusable, stackTrace);

  /// A store [enroll] may write into: one holding nothing live and nothing
  /// pending for this atSign. Live keys are refused, since enrolling again
  /// would overwrite the credential this device already has, and so is any
  /// pending enrollment, whatever its app and device, which is resumed
  /// rather than joined by another.
  Future<void> _refuseUnlessEnrollable(WrittenAtKeysIo keys) async {
    final AtKeys existing;
    try {
      existing = await keys.read(this);
    } on AtKeysSourceAbsentException {
      return;
    }
    _refuseFilingOver(existing, source: keys.describeSource(this));
  }

  /// Throws [AtEnrollmentException] unless [existing], read from the store
  /// [source] describes, holds nothing live and nothing pending. [sent] is
  /// the enrollment already sent, when the check is made again as it is
  /// filed.
  void _refuseFilingOver(AtKeys existing,
      {required String source, String? sent}) {
    String quoted(String text) => '"${clipForMessage(text, quote: '"')}"';
    // NOTE: the instruction comes first, so a message clipped at 180
    // characters still says what to do.
    String notFiled(String gained) =>
        "the atSign's manager can deny enrollment ${quoted(sent!)} of $this, "
        'which is not filed: $this gained $gained while it was being sent';
    if (existing.holdsAuthenticationMaterial) {
      final store = theAtKeysStore(source);
      throw AtEnrollmentException(sent == null
          ? '$this already holds live keys in $store, and enrolling again '
              'would overwrite the credential this device has: give a new '
              'enrollment an AtKeys store of its own'
          : notFiled('live keys in $store'));
    }
    final pendingId = _pendingToResume(existing);
    if (pendingId != null) {
      final info = existing.enrollmentInfo(pendingId);
      final app = info?.appName;
      final device = info?.deviceName;
      final held = 'the pending enrollment ${quoted(pendingId)}'
          '${app == null ? '' : ' for ${quoted(app)}'}'
          '${device == null ? '' : ' on ${quoted(device)}'}';
      throw AtEnrollmentException(sent == null
          ? '$this already holds $held: resume it with resumeEnrollment '
              'rather than submitting another'
          : notFiled(held));
    }
  }

  /// Files what the submission minted under [enrollmentId] as pending, with
  /// the app, device and namespaces asked for, so a restart can find it.
  ///
  /// The APKAM keypair is filed as typed material whatever its algorithm, and
  /// **not** in the flat fields every published reader authenticates from:
  /// the store must read as holding no credential until the atServer has
  /// accepted the enrollment. The flat fields the approval will need are
  /// carried: the encryption public key, the symmetric key a legacy request
  /// wraps, and the enrollment id.
  ///
  /// The filing is the store's one update, which refuses as
  /// [_refuseFilingOver] does whatever was filed while the request was being
  /// sent; a store with no document yet is created by a write, which refuses
  /// one created meanwhile.
  Future<void> _fileAsPending(
    WrittenAtKeysIo keys, {
    required AtKeys minted,
    required String enrollmentId,
    required SigningAlgoType algorithm,
    required String app,
    required String device,
    required Map<String, String> namespaces,
  }) async {
    AtKeys fileInto(AtKeys pending) {
      // NOTE: both flat fields are set, null included: they name this
      // request, whatever the document held before.
      // ignore: deprecated_member_use
      pending.enrollmentId = enrollmentId;
      // ignore: deprecated_member_use
      pending.apkamSymmetricKey = switch (minted.enrollmentSymmetricKey?.key) {
        final String key => AtBytes.fromString(key),
        null => null,
      };
      for (final material in minted.keysForEnrollment(enrollmentId)) {
        pending
            .addKey(material.withStatus(CryptographicMaterialStatus.pending));
      }
      // NOTE: the atSign's encryption public key rides here typed, not in its
      // flat field: a file store self-encrypts that field under a key this
      // device is only given at approval, so a flat copy cannot be written
      // yet. The completion copies it into the flat field for legacy readers.
      // ignore: deprecated_member_use
      final encryptionPublicKey = minted.defaultEncryptionPublicKey;
      if (encryptionPublicKey != null) {
        pending.addKey(CryptographicMaterial(
            keyId:
                '${AtKeys.keyIdPrefix('enc', CryptographicMaterialAlgorithm.rsa2048)}1',
            enrollmentId: enrollmentId,
            role: CryptographicMaterialRole.publicEncryption,
            algorithm: CryptographicMaterialAlgorithm.rsa2048,
            bytes: encryptionPublicKey,
            createdAt: DateTime.now().toUtc(),
            status: CryptographicMaterialStatus.pending));
      }
      final apkamFiled = pending.keysForEnrollment(enrollmentId).any(
          (m) => m.role == CryptographicMaterialRole.privateAuthentication);
      if (!apkamFiled) {
        // An rsa2048 keypair rides the flat fields of what the submission
        // minted; it is filed typed here so that pending has one shape.
        final materialAlgorithm =
            CryptographicMaterialAlgorithm.of(algorithm.name);
        final keyId = '${AtKeys.keyIdPrefix('auth', materialAlgorithm)}1';
        final now = DateTime.now().toUtc();
        final mintedPair = minted.authenticationKeyPairFor(null)!;
        for (final (role, bytes) in [
          (
            CryptographicMaterialRole.privateAuthentication,
            AtBytes.fromString(mintedPair.privateKey)
          ),
          (
            CryptographicMaterialRole.publicAuthentication,
            AtBytes.fromString(mintedPair.publicKey)
          ),
        ]) {
          pending.addKey(CryptographicMaterial(
              keyId: keyId,
              enrollmentId: enrollmentId,
              role: role,
              algorithm: materialAlgorithm,
              bytes: bytes,
              createdAt: now,
              status: CryptographicMaterialStatus.pending));
        }
      }
      pending.recordEnrollmentSnapshot(enrollmentId,
          namespaces: namespaces, appName: app, deviceName: device);
      return pending;
    }

    bool refile(AtKeys stored) {
      _refuseFilingOver(stored,
          source: keys.describeSource(this), sent: enrollmentId);
      fileInto(stored);
      return true;
    }

    try {
      await keys.update(this, refile);
    } on AtKeysSourceAbsentException {
      try {
        await keys.write(this, fileInto(AtKeys(atsign: this)));
      } on AtKeysFileOverwriteException {
        await keys.update(this, refile);
      }
    }
  }
}

/// The pending enrollment of [stored] to resume, or to name in a refusal: the
/// one its flat enrollment id names, whose symmetric key the flat fields hold,
/// else the first.
String? _pendingToResume(AtKeys stored) {
  final pending = stored.pendingEnrollmentIds.toList();
  final flat = stored.storedEnrollmentId;
  return pending.contains(flat) ? flat : pending.firstOrNull;
}
