import 'dart:async';
import 'dart:convert'
    show base64Decode, base64Encode, jsonDecode, jsonEncode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:at_chops/at_chops.dart'
    show PqOpenException, XWingPureDartAlgo, pqOpen, pqSeal;
import 'package:at_client/at_client.dart'
    show
        AtKey,
        AtNotification,
        AtValue,
        DeleteRequestOptions,
        GetRequestOptions,
        NotificationParams,
        PutRequestOptions,
        SyncDirection,
        SyncProgress,
        SyncProgressListener;
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_client/src/secret_sharing/key_package.dart';
import 'package:at_client/src/secret_sharing/key_package_registration.dart';
import 'package:at_client/src/secret_sharing/secret_envelope.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart';
import 'package:uuid/uuid.dart' show Uuid;
import 'package:meta/meta.dart' show experimental;

/// A decrypted, signature-verified payload received from another APKAM
/// keypair of the same atSign.
@experimental
class ReceivedEnvelope {
  /// The sender's key-package id ([KeyPackage.kpid]).
  final String fromKpid;
  final String fromEnrollmentId;

  /// The application namespace the envelope was addressed through (and which
  /// the atServer authorized the recipient's enrollment for).
  final String appNamespace;

  final Map<String, dynamic> payload;

  ReceivedEnvelope({
    required this.fromKpid,
    required this.fromEnrollmentId,
    required this.appNamespace,
    required this.payload,
  });
}

/// A [Secret] another APKAM keypair of this atSign shared with this client.
@experimental
class ReceivedSecret {
  final Secret secret;
  final String fromKpid;
  final String fromEnrollmentId;

  ReceivedSecret({
    required this.secret,
    required this.fromKpid,
    required this.fromEnrollmentId,
  });
}

/// Decides whether to answer an inbound `kind:'request'` secret pull from
/// [requester] (already resolved + authorized as a key package of the
/// request's namespace). Return `true` to share the requested held secrets,
/// `false` to ignore. Set [PairwiseSecretSharing.answerSecretRequests] to
/// override the default (answer any authorized same-atSign requester — the
/// atServer already gates deliverability by namespace).
@experimental
typedef SecretRequestPolicy = FutureOr<bool> Function(
    ReceivedEnvelope request, KeyPackage requester);

/// Pairwise encrypted payload exchange between APKAM keypairs of the same
/// atSign.
///
/// To send, a client seals a payload to one of the recipient key package's
/// advertised keys (per the [SecretSharingAlgos.suites] sealing suite), signs
/// the envelope with its APKAM key, and puts it — as a raw-JSON, deliberately
/// un-self-encrypted self key — at
///
///     <msgId>.<recipientKpid>.__ssenv.<appNamespace>@atsign
///
/// The application-namespace suffix is what scopes delivery: the atServer
/// only lets enrollments authorized for `appNamespace` get/scan/sync the
/// envelope. Within that scope the envelope syncs to all of the atSign's
/// clients like any self key, but only the addressed APKAM keypair can decrypt
/// it. The recipient deletes the envelope after consuming it; unconsumed
/// envelopes expire via [envelopeTtl].
@experimental
mixin PairwiseSecretSharing on KeyPackageRegistration {
  /// Marker segment in envelope key names.
  static const String envelopeKeyMarker = '__ssenv';

  /// Domain-separation context bound into every sealed envelope's key
  /// schedule (the `info` argument to at_chops `pqSeal`/`pqOpen`). Ties a
  /// sealed payload to this substrate so it cannot be replayed into another
  /// `pqSeal`-based protocol, and vice versa.
  static final Uint8List _sealInfo =
      Uint8List.fromList(utf8.encode('at_client/secret_sharing/v1'));

  /// How long an unconsumed envelope lives on the atServer.
  Duration envelopeTtl = Duration(days: 7);

  /// How often [startListening] sweeps the local store for envelopes, in
  /// addition to sweeping when sync delivers one.
  Duration sweepInterval = Duration(minutes: 1);

  /// Whether [sendEnvelope] also fires a best-effort wake-up notification
  /// (default on) after the put. Clients that run sync receive envelopes via
  /// sync without it; sync-less clients rely on it (their [startListening]
  /// monitors for it and does a remote sweep). It is best-effort: the
  /// envelope is already durably stored, so a failed wake-up never fails the
  /// send. A future atServer enhancement will emit this notification itself
  /// on a put to an `__ssenv` key, at which point senders can leave it off.
  bool sendWakeUpNotification = true;

  final StreamController<ReceivedEnvelope> _receivedController =
      StreamController<ReceivedEnvelope>.broadcast();
  final StreamController<ReceivedSecret> _receivedSecretsController =
      StreamController<ReceivedSecret>.broadcast();
  Timer? _sweepTimer;
  _EnvelopeSyncListener? _syncListener;
  StreamSubscription<AtNotification>? _wakeUpSubscription;

  /// Envelope keys already emitted on [receivedEnvelopes], so a sweep that
  /// races a slow delete cannot emit a payload twice.
  final Set<String> _consumedEnvelopeKeys = {};

  /// Optional app override for the `kind:'request'` answer decision. Null =
  /// the default policy (answer any requester that resolves to an authorized
  /// key package of the request's namespace).
  SecretRequestPolicy? answerSecretRequests;

  /// Anti-storm floor: the same (requester, secret-name) is answered at most
  /// once per this interval. A burst of duplicate requests collapses to one
  /// share.
  Duration requestAnswerMinInterval = const Duration(seconds: 5);

  /// `'<requesterKpid>:<secretName>' → last answered at`. In-memory; the
  /// cap is best-effort anti-storm, not a security control.
  final Map<String, DateTime> _lastAnsweredRequest = {};

  /// The secrets this client holds: what it created via
  /// [SecretStore.putSecret], plus what other APKAM keypairs shared with it
  /// (received secrets are stored automatically, newest wins).
  ///
  /// One store — and at most one [SecretStore.persistence] — per APKAM
  /// keypair: all consumers of a shared instance (the app, SDK-internal users
  /// such as crypto providers) read and write the same store. Wire persistence
  /// once, when the instance is created (e.g. via
  /// `AtClientSecretSharing.forClient(persistence: ...)`); consumers must not
  /// re-assign it.
  final SecretStore secretStore = SecretStore();

  /// Decrypted, verified payloads addressed to this client.
  /// Listen, then call [startListening].
  Stream<ReceivedEnvelope> get receivedEnvelopes => _receivedController.stream;

  /// Secrets shared with this client by other APKAM keypairs (already
  /// verified, decrypted, and stored in [secretStore]).
  /// Listen, then call [startListening].
  Stream<ReceivedSecret> get receivedSecrets =>
      _receivedSecretsController.stream;

  /// Encrypts [payload] to [to]'s key package and stores it for delivery,
  /// addressed through [appNamespace].
  ///
  /// Both this client's and the recipient's enrollments must be authorized
  /// for [appNamespace] — the atServer enforces this on write (here) and on
  /// read/sync (recipient side) respectively.
  ///
  /// Throws [StateError] if [to] advertises no key with a mutually-supported
  /// algorithm.
  Future<void> sendEnvelope(
    KeyPackage to,
    String appNamespace,
    Map<String, dynamic> payload,
  ) async {
    final PackageKey? recipientKey = to.bestKeyFor(SecretSharingAlgos.keyAlgos);
    if (recipientKey == null) {
      throw StateError(
          'Key package ${to.enrollmentId}/${to.apkamId} advertises no key '
          'with a supported algorithm (supported: '
          '${SecretSharingAlgos.keyAlgos})');
    }

    // X-Wing HPKE: pqSeal encapsulates to the recipient's published key and
    // wraps the payload (AEAD over an HKDF key schedule) into one envelope —
    // nothing secret travels except that sealed envelope.
    final Uint8List sealed = await pqSeal(
      XWingPureDartAlgo.instance,
      base64Decode(recipientKey.pub),
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      info: _sealInfo,
    );

    final envelope = SecretEnvelope(
      fromKpid: kpid,
      fromEnrollmentId: enrollmentId,
      toKpid: recipientKey.kid,
      suite: SecretSharingAlgos.xWingHpke,
      kid: recipientKey.kid,
      sealed: base64Encode(sealed),
    );
    // pqSeal's AEAD authenticates the payload; the APKAM signature over the
    // whole envelope additionally authenticates the SENDER (receivers still
    // verify before decrypting).
    final String signedJson = await wrapAndSignAndJsonEncode(envelope.toJson());

    final atKey = AtKey()
      ..key = '${Uuid().v4()}.${recipientKey.kid}.$envelopeKeyMarker'
      ..namespace = appNamespace
      ..sharedBy = atClient.getCurrentAtSign()
      ..metadata.ttl = envelopeTtl.inMilliseconds;
    // shouldEncrypt=false: the value is already end-to-end encrypted to the
    // recipient; self-key encryption would only obscure that the payload is
    // our own ciphertext. The value is raw JSON (never whole-value base64) so
    // that pre-fix readers' legacy decrypt fallback also returns it untouched.
    await atClient.put(
      atKey,
      signedJson,
      putRequestOptions: PutRequestOptions()..shouldEncrypt = false,
    );
    logger.info('Stored secret envelope $atKey for kpid ${recipientKey.kid}');

    if (sendWakeUpNotification) {
      await _sendWakeUp(atKey, appNamespace);
    }
  }

  /// Fires a best-effort, value-less wake-up notification for [envelopeKey]
  /// addressed to our own atSign (so every client's notification monitor
  /// receives it). The key name carries the recipient kpid and the `__ssenv`
  /// marker, so only the addressed APKAM keypair's [startListening]
  /// subscription reacts. The notification is never the secret itself — it
  /// only nudges a sync-less recipient to remote-sweep — so a failure here is
  /// logged and swallowed.
  Future<void> _sendWakeUp(AtKey envelopeKey, String appNamespace) async {
    final String me = atClient.getCurrentAtSign()!;
    final wakeKey = AtKey()
      ..key = envelopeKey.key
      ..namespace = appNamespace
      ..sharedBy = me
      ..sharedWith = me
      ..metadata.isEncrypted = false
      ..metadata.ttl = envelopeTtl.inMilliseconds;
    try {
      await atClient.notificationService.notify(
        NotificationParams.forUpdate(wakeKey, notificationExpiry: envelopeTtl),
        waitForFinalDeliveryStatus: false,
        checkForFinalDeliveryStatus: false,
        encryptValue: false,
      );
    } catch (e) {
      logger.warning('Wake-up notification for $envelopeKey failed '
          '(envelope is stored; sync clients are unaffected): $e');
    }
  }

  /// Starts watching for envelopes addressed to this client: sweeps the local
  /// store now, after every sync that delivers an envelope key, and every
  /// [sweepInterval]; and subscribes to wake-up notifications, doing a remote
  /// sweep on each (which is how a sync-less client receives envelopes at
  /// all). Requires [register] to have completed.
  Future<void> startListening() async {
    if (_sweepTimer != null) {
      return;
    }
    // Throws StateError if not registered:
    final String marker = '.$kpid.$envelopeKeyMarker.';

    _syncListener = _EnvelopeSyncListener(marker, () {
      unawaited(sweepOnce());
    });
    atClient.syncService.addProgressListener(_syncListener!);
    // A wake-up notification only nudges us; the envelope itself is fetched
    // from the atServer (a sync-less client has no local copy), so the sweep
    // it triggers reads remote.
    _wakeUpSubscription = atClient.notificationService
        .subscribe(
            regex: '\\.$kpid\\.$envelopeKeyMarker\\.', shouldDecrypt: false)
        .listen((_) => unawaited(sweepOnce(fromRemote: true)));
    _sweepTimer = Timer.periodic(sweepInterval, (_) => unawaited(sweepOnce()));
    await sweepOnce();
  }

  /// Stops watching. The [receivedEnvelopes] stream stays open; a later
  /// [startListening] resumes.
  void stopListening() {
    _sweepTimer?.cancel();
    _sweepTimer = null;
    if (_syncListener != null) {
      atClient.syncService.removeProgressListener(_syncListener!);
      _syncListener = null;
    }
    unawaited(_wakeUpSubscription?.cancel());
    _wakeUpSubscription = null;
  }

  /// Scans for envelopes addressed to this client; verifies, decrypts, emits
  /// and deletes each. Returns how many envelopes were consumed. Safe to call
  /// concurrently with the periodic sweep, a sync-triggered sweep, and a
  /// wake-up sweep — each envelope key is claimed synchronously before any
  /// await, so the same payload is never emitted twice.
  ///
  /// [fromRemote] reads (and deletes) against the atServer rather than the
  /// local store; the wake-up path uses it so a sync-less client — which has
  /// no synced local copy — can still receive envelopes.
  Future<int> sweepOnce({bool fromRemote = false}) async {
    final List<AtKey> envelopeKeys = await atClient.getAtKeys(
        regex: '.*\\.$kpid\\.$envelopeKeyMarker\\..*',
        useRemoteAtServer: fromRemote);
    int consumed = 0;
    for (final envelopeKey in envelopeKeys) {
      final keyString = envelopeKey.toString();
      // Claim the key synchronously: Set.add is false if a concurrent sweep
      // already claimed it. This closes the check-then-consume window — the
      // claim is released again (below) if the envelope turns out not to be
      // processable, so a later sweep can retry it.
      if (!_consumedEnvelopeKeys.add(keyString)) {
        continue;
      }
      try {
        final ReceivedEnvelope? received =
            await _consume(envelopeKey, fromRemote: fromRemote);
        if (received == null) {
          // Not (or not yet) processable by this client; leave it for a
          // sibling/upgraded client or for ttl expiry.
          _consumedEnvelopeKeys.remove(keyString);
          continue;
        }
        _receivedController.add(received);
        await _handleSecretPayload(received); // no-op unless kind=='secret'
        await _handleRequestPayload(received); // no-op unless kind=='request'
        consumed++;
      } catch (e) {
        // Includes transient failures (e.g. fetching the signer's _apsk key)
        // — never delete on failure; release the claim so the next sweep
        // retries.
        _consumedEnvelopeKeys.remove(keyString);
        logger.warning('Failed to process envelope $envelopeKey: $e');
        continue;
      }
      try {
        await atClient.delete(envelopeKey,
            deleteRequestOptions: DeleteRequestOptions()
              ..useRemoteAtServer = fromRemote);
      } catch (e) {
        logger.warning('Failed to delete consumed envelope $envelopeKey: $e');
      }
    }
    return consumed;
  }

  /// Verifies and decrypts one envelope. Returns null (after logging) for
  /// envelopes this client cannot or should not process. [fromRemote] fetches
  /// from the atServer rather than the local store (see [sweepOnce]).
  Future<ReceivedEnvelope?> _consume(AtKey envelopeKey,
      {bool fromRemote = false}) async {
    final AtValue av = await atClient.get(envelopeKey,
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = fromRemote);
    final signedEnvelope = jsonDecode(av.value as String) as Map;
    // Verify FIRST: the sealed envelope's AEAD authenticates the payload
    // bytes, but only the APKAM signature authenticates WHO sent it.
    await verifyEnvelopeSignature(signedEnvelope,
        signerAtSign: atClient.getCurrentAtSign()!);
    final envelope = SecretEnvelope.fromJson(signedEnvelope['payload']);

    if (envelope.toKpid != kpid) {
      logger.warning('Envelope $envelopeKey is addressed to '
          '${envelope.toKpid}, not to this client; skipping');
      return null;
    }
    if (signedEnvelope['enrollmentId'] != envelope.fromEnrollmentId) {
      logger.warning('Envelope $envelopeKey: signer enrollment '
          '${signedEnvelope['enrollmentId']} does not match claimed sender '
          'enrollment ${envelope.fromEnrollmentId}; skipping');
      return null;
    }
    if (!SecretSharingAlgos.suites.contains(envelope.suite)) {
      logger.warning('Envelope $envelopeKey uses unsupported sealing suite '
          '${envelope.suite}; skipping');
      return null;
    }
    if (envelope.kid != kpid) {
      logger.warning('Envelope $envelopeKey was encrypted to key '
          '${envelope.kid} which this client does not hold; skipping');
      return null;
    }

    // pqOpen's AEAD authenticates: tampering, a wrong-recipient
    // decapsulation, or mismatched `info` all surface as a PqOpenException.
    // It is deterministic — retrying cannot help — so a failure leaves the
    // envelope for ttl expiry rather than blocking sweeps forever.
    final Uint8List plaintext;
    try {
      plaintext = await pqOpen(
        XWingPureDartAlgo.instance,
        xWingSeed,
        base64Decode(envelope.sealed),
        info: _sealInfo,
      );
    } on PqOpenException catch (e) {
      logger.warning('Envelope $envelopeKey failed to open ($e); skipping');
      return null;
    }

    return ReceivedEnvelope(
      fromKpid: envelope.fromKpid,
      fromEnrollmentId: envelope.fromEnrollmentId,
      appNamespace: _appNamespaceOf(envelopeKey),
      payload: jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>,
    );
  }

  /// The full application namespace of an envelope key: everything between
  /// the `.__ssenv.` marker and the atSign. `AtKey.namespace` only carries
  /// the last dot segment, which would truncate dotted app namespaces
  /// (`examples.demos` would arrive as `demos`).
  String _appNamespaceOf(AtKey envelopeKey) {
    final String keyString = envelopeKey.toString();
    final int markerIndex = keyString.indexOf('.$envelopeKeyMarker.');
    final int atIndex = keyString.lastIndexOf('@');
    if (markerIndex < 0 || atIndex <= markerIndex) {
      return envelopeKey.namespace ?? '';
    }
    return keyString.substring(
        markerIndex + envelopeKeyMarker.length + 2, atIndex);
  }

  /// Payload `kind` marker for envelopes that carry a [Secret].
  ///
  /// `kind` values `secret`, `request` and `response` are reserved for this
  /// library (`request`/`response` drive the secret pull flow). Apps embedding
  /// their own payloads via [sendEnvelope] should use other `kind` values;
  /// unknown kinds are delivered on [receivedEnvelopes] and otherwise ignored.
  static const String secretPayloadKind = 'secret';

  /// Payload `kind` for a pull request: `{kind:'request', want:[name…]}` or
  /// `{kind:'request', namePrefix:'__rk.'}`. The answer is delivered as an
  /// ordinary `secret` envelope (no separate `response` kind is needed — a
  /// shared secret already converges via [SecretStore.putIfNewer] and
  /// resolves any racing [waitForSecret]).
  static const String secretRequestKind = 'request';

  /// Broadcasts a pull request for held secrets to every key package
  /// registered for [namespace] (minus this client). Holders that pass the
  /// answer policy reply by sharing the matching secrets; the caller typically
  /// then [waitForSecret]s. Filter the request by exact [names] and/or a
  /// [namePrefix] (e.g. `__rk.` for epoch keys). [excludeEnrollmentIds] drops
  /// revoked enrollments. Returns the number of key packages the request was
  /// sent to.
  Future<int> requestSecretsFromNamespace(
    String namespace, {
    List<String>? names,
    String? namePrefix,
    Set<String> excludeEnrollmentIds = const {},
  }) async {
    final members = await directory.listForNamespace(namespace,
        excludeEnrollmentIds: excludeEnrollmentIds);
    int sent = 0;
    for (final member in members) {
      for (final to in member.keyPackages) {
        if (to.kpid == kpid) continue; // skip ourselves
        await sendEnvelope(to, namespace, {
          'kind': secretRequestKind,
          if (names != null) 'want': names,
          if (namePrefix != null) 'namePrefix': namePrefix,
        });
        sent++;
      }
    }
    return sent;
  }

  /// Requests a single named secret from the holders in [namespace], then
  /// resolves when it arrives ([waitForSecret]).
  Future<Secret> requestSecret(
    String namespace,
    String name, {
    Duration timeout = const Duration(seconds: 30),
    Set<String> excludeEnrollmentIds = const {},
  }) async {
    await requestSecretsFromNamespace(namespace,
        names: [name], excludeEnrollmentIds: excludeEnrollmentIds);
    return waitForSecret(namespace, name, timeout: timeout);
  }

  /// Answers an inbound `kind:'request'`: resolves + authorizes the requester
  /// (the sender's kpid must be a key package authorized for the request's
  /// namespace — defence in depth over the server's own delivery gate),
  /// consults [answerSecretRequests], then shares each requested secret this
  /// client holds, sealing the reply straight back to the requester's kpid.
  /// Never answers its own request, and rate-caps per (requester, name) via
  /// [requestAnswerMinInterval].
  Future<void> _handleRequestPayload(ReceivedEnvelope received) async {
    if (received.payload['kind'] != secretRequestKind) {
      return;
    }
    if (received.fromKpid == kpid) {
      return; // never answer our own request
    }
    // Resolve the requester's key package by its kpid within the namespace;
    // appearing here also enforces authorization (the verb only returns
    // enrollments approved for the namespace).
    KeyPackage? requester;
    for (final member
        in await directory.listForNamespace(received.appNamespace)) {
      if (member.enrollmentId != received.fromEnrollmentId) {
        continue;
      }
      for (final kp in member.keyPackages) {
        if (kp.kpid == received.fromKpid) {
          requester = kp;
          break;
        }
      }
      if (requester != null) break;
    }
    if (requester == null) {
      logger.info('Ignoring request from kpid ${received.fromKpid}: not an '
          'authorized key package of ${received.appNamespace}');
      return;
    }
    final policy = answerSecretRequests;
    if (policy != null && !(await policy(received, requester))) {
      return;
    }

    final want = (received.payload['want'] as List?)?.cast<String>().toSet();
    final namePrefix = received.payload['namePrefix'] as String?;
    final now = DateTime.now();
    for (final secret in secretStore.listSecrets(
        namespace: received.appNamespace, namePrefix: namePrefix)) {
      if (want != null && !want.contains(secret.name)) {
        continue;
      }
      final rateKey = '${received.fromKpid}:${secret.name}';
      final last = _lastAnsweredRequest[rateKey];
      if (last != null && now.difference(last) < requestAnswerMinInterval) {
        continue;
      }
      _lastAnsweredRequest[rateKey] = now;
      await shareSecretWith(requester, secret);
    }
  }

  /// Returns the secret `(namespace, name)` as soon as this client holds
  /// it: immediately from [secretStore] when already present, otherwise the
  /// first matching arrival on [receivedSecrets] — subscription is set up
  /// *before* the store check, so an arrival between the two cannot be
  /// missed. [startListening] must be active for arrivals to be observed.
  ///
  /// Throws [TimeoutException] when [timeout] elapses first. Intended for
  /// decrypt-style paths that race key distribution (e.g. a crypto provider
  /// waiting for an epoch key another client is sharing).
  Future<Secret> waitForSecret(
    String namespace,
    String name, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final completer = Completer<Secret>();
    final subscription = receivedSecrets.listen((received) {
      if (received.secret.namespace == namespace &&
          received.secret.name == name &&
          !completer.isCompleted) {
        completer.complete(received.secret);
      }
    });
    try {
      final existing = secretStore.getSecret(namespace, name);
      if (existing != null) {
        return existing;
      }
      return await completer.future.timeout(timeout);
    } finally {
      await subscription.cancel();
    }
  }

  /// If [received] carries a secret, stores it in [secretStore]
  /// (newest wins) and emits it on [receivedSecrets].
  Future<void> _handleSecretPayload(ReceivedEnvelope received) async {
    if (received.payload['kind'] != secretPayloadKind) {
      return;
    }
    final Secret secret;
    try {
      secret = Secret.fromJson({
        ...received.payload,
        // the namespace is taken from the (server-authorized) envelope key,
        // not from the payload
        'namespace': received.appNamespace,
      });
    } on FormatException catch (e) {
      logger.warning('Discarding malformed secret payload from '
          'kpid ${received.fromKpid}: $e');
      return;
    }
    final stored = await secretStore.putIfNewer(secret);
    if (!stored) {
      logger.info('Ignoring secret ${secret.namespace}:${secret.name} from '
          'kpid ${received.fromKpid}: already hold a same-or-newer one');
      return;
    }
    _receivedSecretsController.add(ReceivedSecret(
      secret: secret,
      fromKpid: received.fromKpid,
      fromEnrollmentId: received.fromEnrollmentId,
    ));
  }

  /// Shares one secret with one key package.
  Future<void> shareSecretWith(KeyPackage to, Secret secret) =>
      sendEnvelope(to, secret.namespace, {
        'kind': secretPayloadKind,
        'name': secret.name,
        'value': secret.value,
        if (secret.version != null) 'version': secret.version,
        'createdAt': secret.createdAt.toIso8601String(),
      });

  /// Shares every secret in [secretStore] with [to], filtered — when
  /// [approvedNamespaces] is given — to secrets whose namespace that
  /// enrollment is authorized for ([SecretStore.namespaceAuthorizes]).
  ///
  /// The filter is a courtesy, not the enforcement: even without it the
  /// atServer would refuse to deliver an envelope to an enrollment that
  /// lacks the namespace. With it, the material never leaves this client.
  ///
  /// [excludeEnrollmentIds] is a revocation guard: if [to] belongs to an
  /// excluded enrollment, nothing is shared (returns 0).
  ///
  /// Returns the number of secrets shared.
  Future<int> shareAllSecretsWith(
    KeyPackage to, {
    Map<String, dynamic>? approvedNamespaces,
    Set<String>? excludeEnrollmentIds,
  }) async {
    if (excludeEnrollmentIds?.contains(to.enrollmentId) ?? false) {
      return 0;
    }
    int shared = 0;
    for (final secret in secretStore.listSecrets()) {
      if (approvedNamespaces != null &&
          !SecretStore.namespaceAuthorizes(
              approvedNamespaces, secret.namespace)) {
        continue;
      }
      await shareSecretWith(to, secret);
      shared++;
    }
    return shared;
  }

  /// Pushes one [secret] to every key package registered for its namespace
  /// (minus this client). This is the mint/rotation push: it enumerates the
  /// namespace's members via the directory, seals once per key package, and
  /// puts the kpid-addressed envelope. [excludeEnrollmentIds] drops revoked
  /// enrollments. Returns the number of key packages it was pushed to.
  Future<int> pushSecretToNamespaceMembers(
    Secret secret, {
    Set<String> excludeEnrollmentIds = const {},
  }) async {
    final members = await directory.listForNamespace(secret.namespace,
        excludeEnrollmentIds: excludeEnrollmentIds);
    int pushed = 0;
    for (final member in members) {
      for (final to in member.keyPackages) {
        if (to.kpid == kpid) continue; // skip ourselves
        await shareSecretWith(to, secret);
        pushed++;
      }
    }
    return pushed;
  }

  /// For use by an enrollment approver, after approving [enrollmentId] with
  /// [approvedNamespaces] (both available from the enrollment request): shares
  /// with each of the newly-approved enrollment's key packages every held
  /// secret the enrollment's namespaces authorize.
  ///
  /// No polling: the key package is in the enrollment record from
  /// enrollment-request time, so it is discoverable as soon as the enrollment
  /// is approved. Key packages are per-APKAM, not per-namespace, so any
  /// approved namespace yields them. Returns the total number of secrets
  /// shared.
  Future<int> shareAllSecretsWithEnrollment(
    String enrollmentId,
    Map<String, dynamic> approvedNamespaces, {
    Set<String>? excludeEnrollmentIds,
  }) async {
    if (excludeEnrollmentIds?.contains(enrollmentId) ?? false) {
      return 0;
    }
    final byKpid = <String, KeyPackage>{};
    for (final ns in approvedNamespaces.keys) {
      if (ns == '*') continue; // a wildcard isn't a queryable namespace
      for (final member in await directory.listForNamespace(ns)) {
        if (member.enrollmentId != enrollmentId) continue;
        for (final kp in member.keyPackages) {
          final id = kp.kpid;
          if (id != null) byKpid[id] = kp;
        }
      }
      if (byKpid.isNotEmpty) break;
    }
    if (byKpid.isEmpty) {
      logger.warning('No discoverable key package for enrollment $enrollmentId '
          'in ${approvedNamespaces.keys}; no secrets shared');
      return 0;
    }
    int shared = 0;
    for (final kp in byKpid.values) {
      shared += await shareAllSecretsWith(kp,
          approvedNamespaces: approvedNamespaces,
          excludeEnrollmentIds: excludeEnrollmentIds);
    }
    return shared;
  }
}

class _EnvelopeSyncListener extends SyncProgressListener {
  final String marker;
  final void Function() onEnvelopeSynced;

  _EnvelopeSyncListener(this.marker, this.onEnvelopeSynced);

  @override
  void onSyncProgressEvent(SyncProgress syncProgress) {
    final keyInfoList = syncProgress.keyInfoList;
    if (keyInfoList == null) {
      return;
    }
    final delivered = keyInfoList.any((keyInfo) =>
        keyInfo.syncDirection == SyncDirection.remoteToLocal &&
        keyInfo.key.contains(marker));
    if (delivered) {
      onEnvelopeSynced();
    }
  }
}
