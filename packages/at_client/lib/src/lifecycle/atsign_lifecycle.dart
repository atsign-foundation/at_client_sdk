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
import 'package:at_client/src/lifecycle/pending_enrollment.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/preference/at_client_preference.dart';
import 'package:at_client/src/secret_sharing/enrollment_key_package.dart'
    show enrollmentKeyPackageBuilder;
import 'package:at_client/src/secret_sharing/enrollment_symmetric_key.dart'
    show enrollmentApkamSymmetricKeyResolver;
import 'package:at_client/src/storage/at_client_storage.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup_io.dart';
import 'package:at_utils/at_progress.dart';

/// The verbs an application reaches a working client through, on the atSign
/// it holds keys for.
///
/// ```dart
/// final client = await Atsign('@alice').open(
///     keys: FileAtKeysIo(), preference: AtClientPreference());
/// client.connection.current;          // online, offline or refused
/// client.connection.changes.listen((state) { ... });
/// AtClientManager.getInstance().use(client);
///
/// final pending = await Atsign('@alice').enroll(otp: otp, app: 'wavi',
///     device: 'phone', namespaces: {'wavi': 'rw'}, keys: FileAtKeysIo(),
///     preference: preference);
/// final client = await pending.client(preference);
/// // after a restart:
/// final resumed = await Atsign('@alice').resumeEnrollment(app: 'wavi',
///     device: 'phone', keys: FileAtKeysIo(), preference: preference);
/// ```
extension AtsignLifecycle on Atsign {
  /// Builds a client for this atSign from [keys], tries once to reach the
  /// atServer within [connectBudget], and hands the client back with
  /// `connection.current` saying how that went. The caller owns the client
  /// and ends it with `stop()`.
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
  /// Keys that hold nothing but an enrollment awaiting approval are refused
  /// with [AtEnrollmentPendingException]: [resumeEnrollment] picks that up.
  ///
  /// [namespace] defaults to the preference's. [storage] is the client's
  /// local storage, borrowed unless it was built with `closedByClient: true`;
  /// with none, a Hive store opens under `preference.hiveStoragePath`.
  /// [atLookUp] is a connection to use instead of one built from the
  /// preference, for a caller that already holds one. [serviceFactory]
  /// supplies the client's notification, sync and enrollment services in
  /// place of the defaults; a process that must not sync hands in a factory
  /// whose sync service does nothing.
  ///
  /// Refuses, as `buildAtClient` does, while a client for this atSign is
  /// live in this process.
  Future<AtClient> open({
    required AtKeysIo keys,
    required AtClientPreference preference,
    String? namespace,
    AtClientStorage? storage,
    AtLookUp? atLookUp,
    AtServiceFactory? serviceFactory,
    Duration connectBudget = AtConnection.defaultBudget,
  }) async {
    await _refuseKeysStillPending(keys);
    final client = await buildAtClient(
      atSign: this,
      namespace: namespace ?? preference.namespace,
      preference: preference,
      storage: storage,
      atKeysIo: keys,
      atLookUp: atLookUp,
      notificationServiceBuilder: serviceFactory == null
          ? null
          : (client) => serviceFactory.notificationService(
              client, AtClientManager.getInstance()),
      syncServiceBuilder: serviceFactory == null
          ? null
          : (client) => serviceFactory.syncService(client,
              AtClientManager.getInstance(), client.notificationService),
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
  /// posture's answer. [onProgress] hears each step of the activation.
  ///
  /// A newly registered atSign can take minutes to be provisioned: the
  /// activation asks up to [provisioningRetries] times,
  /// [provisioningPollInterval] apart, before giving up.
  ///
  /// See [open] for [namespace], [storage], [atLookUp] and [connectBudget];
  /// a supplied [atLookUp] serves the activation too, and is taken as having
  /// already reached the atServer, so the provisioning wait is skipped.
  Future<AtClient> activate({
    required String cramSecret,
    required WrittenAtKeysIo keys,
    required AtClientPreference preference,
    String? namespace,
    AtClientStorage? storage,
    String app = firstEnrollmentAppName,
    String device = firstEnrollmentDeviceName,
    bool? mintLegacyMaterial,
    SigningAlgoType? signingAlgo,
    int provisioningRetries = RetryOptions.defaultMaxRetries,
    Duration provisioningPollInterval = RetryOptions.defaultRetryDelay,
    void Function(ProgressEvent event)? onProgress,
    AtLookUp? atLookUp,
    Duration connectBudget = AtConnection.defaultBudget,
  }) async {
    final algo = signingAlgo ?? preference.authenticationKeyAlgorithm;
    final pqNative = algo == SigningAlgoType.mldsa65;
    ({
      SigningAlgoType algorithm,
      String publicKey,
      String privateKey
    })? advertisedSigningKey;
    FutureOr<Map<String, dynamic>?> Function(AtKeysIo)? metadataBuilder;
    if (pqNative) {
      final material = await pqNativeActivationMaterial(
          atSign: this,
          dataSigningKeyAlgorithms: preference.dataSigningKeyAlgorithms,
          keyEstablishmentAlgo: preference.keyEstablishmentAlgorithms.first);
      advertisedSigningKey = material.advertisedSigningKey;
      metadataBuilder = material.metadataBuilder;
    }
    await activateAtSign(
        atSign: this,
        cramSecret: cramSecret,
        keys: keys,
        signingAlgo: algo,
        rootDomain: AtRootDomain(preference.rootDomain, preference.rootPort),
        appName: app,
        deviceName: device,
        mintLegacyMaterial:
            mintLegacyMaterial ?? preference.posture.mintLegacyMaterial,
        metadataBuilder: metadataBuilder,
        advertisedSigningKey: advertisedSigningKey,
        retryOptions: RetryOptions(
            maxRetries: provisioningRetries,
            retryDelay: provisioningPollInterval),
        onProgress: onProgress,
        atLookUp: atLookUp);

    final client = await open(
        keys: keys,
        preference: preference,
        namespace: namespace,
        storage: storage,
        atLookUp: atLookUp,
        connectBudget: connectBudget);
    if (pqNative) {
      await mintSigningRootAfterActivation(client, atKeysIo: keys);
    }
    return client;
  }

  /// Asks the atSign's manager to enrol this device as [app] on [device] with
  /// [namespaces], quoting [otp], and files the keys the request minted in
  /// [keys] as pending under the new enrollment.
  ///
  /// Returns at once with a [PendingEnrollment]: its `client` waits for the
  /// decision, and after a restart [resumeEnrollment] finds the same request
  /// in [keys]. [keys] must hold nothing live for this atSign; a store that
  /// already holds a pending enrollment for the same app and device is
  /// refused in favour of resuming it.
  ///
  /// [signingAlgo] is the APKAM algorithm the enrollment authenticates with
  /// and [keyExchangeMode] how its symmetric key travels; both default to the
  /// preference's posture. [apkamKeysExpiry] asks the atServer to expire the
  /// enrollment's keys after that long. [atLookUp] is a connection to submit
  /// on, for a caller that already holds one; the request itself travels
  /// unauthenticated, since this device holds no credential yet.
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
    AtLookUp? atLookUp,
  }) async {
    final rootDomain = AtRootDomain(preference.rootDomain, preference.rootPort);
    final algo = signingAlgo ?? preference.authenticationKeyAlgorithm;
    final mode = keyExchangeMode ?? preference.posture.keyExchangeMode;
    await _refuseUnlessEnrollable(keys, app, device);

    // NOTE: the enrollment owns its signing key from its first byte: `_apsk`
    // advertises it and the key package is signed with it, so minting it at a
    // later start would publish a record naming one key beside a package
    // signed by another.
    final advertisedSigningKey =
        await mintAdvertisedSigningKey(preference.dataSigningKeyAlgorithms);
    final session = AtAuthSession(
        atSign: this, rootDomain: rootDomain, atKeysIo: InMemoryAtKeysIo());
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
        AtLookUp.withSecureSocket(
            atSign: this,
            rootDomain: rootDomain,
            transport: secureSocketTransport(SecureSocketConfig()),
            authenticator: null);
    final AtEnrollmentResponse response;
    try {
      response = await AtEnrollment.create().submit(request, lookUp);
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
        atLookUp: atLookUp);
  }

  /// The enrollment [enroll] filed in [keys] for [app] on [device] and has not
  /// yet completed, or null when there is none: the way an application picks
  /// up an enrollment it submitted before a restart.
  ///
  /// [preference] supplies the root domain; [atLookUp] a connection for the
  /// approval handshake, for a caller that already holds one.
  Future<PendingEnrollment?> resumeEnrollment({
    required String app,
    required String device,
    required WrittenAtKeysIo keys,
    required AtClientPreference preference,
    AtLookUp? atLookUp,
  }) async {
    final AtKeys stored;
    try {
      stored = await keys.read(this);
    } on AtKeysSourceAbsentException {
      return null;
    }
    for (final enrollmentId in stored.pendingEnrollmentIds) {
      final info = stored.enrollmentInfo(enrollmentId);
      if (info?.appName != app || info?.deviceName != device) continue;
      final apkam = stored
          .keysForEnrollment(enrollmentId)
          .where((m) =>
              m.role == CryptographicMaterialRole.privateAuthentication &&
              m.status == CryptographicMaterialStatus.pending)
          .first;
      return PendingEnrollment(
          atSign: this,
          enrollmentId: enrollmentId,
          app: app,
          device: device,
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
          atLookUp: atLookUp);
    }
    return null;
  }

  Future<void> _refuseKeysStillPending(AtKeysIo keys) async {
    final AtKeys stored;
    try {
      stored = await keys.read(this);
    } on Exception {
      // Absent or unreadable keys are the client's to report as it always has.
      return;
    }
    final pending = stored.pendingEnrollmentIds.toList();
    if (!stored.holdsAuthenticationMaterial && pending.isNotEmpty) {
      throw AtEnrollmentPendingException(this, pending);
    }
  }

  /// A store [enroll] may write into: absent, or emptied by a denial. Live
  /// keys are refused, since enrolling again would overwrite the credential
  /// this device already has, and so is a pending enrollment for the same
  /// app and device, which is resumed rather than repeated.
  Future<void> _refuseUnlessEnrollable(
      WrittenAtKeysIo keys, String app, String device) async {
    final AtKeys existing;
    try {
      existing = await keys.read(this);
    } on AtKeysSourceAbsentException {
      return;
    }
    if (existing.holdsAuthenticationMaterial) {
      throw AtEnrollmentException('$this already holds live keys in this '
          'store, and enrolling again would overwrite the credential this '
          'device has; remove them first if a fresh enrollment is meant');
    }
    for (final enrollmentId in existing.pendingEnrollmentIds) {
      final info = existing.enrollmentInfo(enrollmentId);
      if (info?.appName == app && info?.deviceName == device) {
        throw AtEnrollmentException('$this already holds the pending '
            'enrollment $enrollmentId for $app on $device: resume it with '
            'resumeEnrollment rather than submitting another');
      }
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
  Future<void> _fileAsPending(
    WrittenAtKeysIo keys, {
    required AtKeys minted,
    required String enrollmentId,
    required SigningAlgoType algorithm,
    required String app,
    required String device,
    required Map<String, String> namespaces,
  }) async {
    final pending = AtKeys(atsign: this)
      // ignore: deprecated_member_use
      ..apkamSymmetricKey = minted.apkamSymmetricKey
      // ignore: deprecated_member_use
      ..enrollmentId = enrollmentId;
    for (final material in minted.keysForEnrollment(enrollmentId)) {
      pending.addKey(material.withStatus(CryptographicMaterialStatus.pending));
    }
    // NOTE: the atSign's encryption public key rides here typed, not in its
    // flat field: a file store self-encrypts that field under a key this
    // device is only given at approval, so a flat copy cannot be written yet.
    // The completion copies it into the flat field for legacy readers.
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
    final apkamFiled = pending
        .keysForEnrollment(enrollmentId)
        .any((m) => m.role == CryptographicMaterialRole.privateAuthentication);
    if (!apkamFiled) {
      // An rsa2048 keypair rides the flat fields of what the submission
      // minted; it is filed typed here so that pending has one shape.
      final materialAlgorithm =
          CryptographicMaterialAlgorithm.of(algorithm.name);
      final keyId = '${AtKeys.keyIdPrefix('auth', materialAlgorithm)}1';
      final now = DateTime.now().toUtc();
      for (final (role, bytes) in [
        // ignore: deprecated_member_use
        (
          CryptographicMaterialRole.privateAuthentication,
          minted.apkamPrivateKey!
        ),
        // ignore: deprecated_member_use
        (
          CryptographicMaterialRole.publicAuthentication,
          minted.apkamPublicKey!
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

    try {
      await keys.write(this, pending);
    } on AtKeysFileOverwriteException {
      // The store holds a document with nothing live in it (checked before
      // the request went out), so this pending enrollment goes over it.
      await keys.flush(this, pending);
    }
  }
}
