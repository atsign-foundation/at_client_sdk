import 'dart:async';
import 'dart:convert'
    show base64Decode, base64Encode, jsonDecode, jsonEncode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:at_chops/at_chops.dart'
    show
        AESKey,
        AesGcm256EncryptionAlgo,
        AtChopsUtil,
        InitialisationVector,
        XWingPureDartAlgo;
import 'package:at_client/at_client.dart'
    show
        AtKey,
        AtValue,
        PutRequestOptions,
        SyncDirection,
        SyncProgress,
        SyncProgressListener;
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_client/src/secret_sharing/client_key_package.dart';
import 'package:at_client/src/secret_sharing/pairwise_client_registration.dart';
import 'package:at_client/src/secret_sharing/secret_envelope.dart';
import 'package:at_client/src/secret_sharing/secret_store.dart';
import 'package:uuid/uuid.dart' show Uuid;
import 'package:meta/meta.dart' show experimental;

/// A decrypted, signature-verified payload received from another client of
/// the same atSign.
@experimental
class ReceivedEnvelope {
  final String fromClientId;
  final String fromEnrollmentId;

  /// The application namespace the envelope was addressed through (and which
  /// the atServer authorized the recipient's enrollment for).
  final String appNamespace;

  final Map<String, dynamic> payload;

  ReceivedEnvelope({
    required this.fromClientId,
    required this.fromEnrollmentId,
    required this.appNamespace,
    required this.payload,
  });
}

/// A [Secret] another client of this atSign shared with this client.
@experimental
class ReceivedSecret {
  final Secret secret;
  final String fromClientId;
  final String fromEnrollmentId;

  ReceivedSecret({
    required this.secret,
    required this.fromClientId,
    required this.fromEnrollmentId,
  });
}

/// Pairwise encrypted payload exchange between clients of the same atSign.
///
/// To send, a client encrypts a payload to one of the recipient's published
/// [ClientKeyPackage] keys (content key wrapped per the bundle key's alg,
/// payload encrypted per [SecretSharingAlgos.encAlgos]), signs the envelope
/// with its APKAM key, and puts it — as a raw-JSON, deliberately
/// un-self-encrypted self key — at
///
///     <msgId>.<recipientClientId>.__ssenv.<appNamespace>@atsign
///
/// The application-namespace suffix is what scopes delivery: the atServer
/// only lets enrollments authorized for `appNamespace` get/scan/sync the
/// envelope. Within that scope the envelope syncs to all of the atSign's
/// clients like any self key, but only the addressed client can decrypt it.
/// The recipient deletes the envelope after consuming it; unconsumed
/// envelopes expire via [envelopeTtl].
@experimental
mixin PairwiseSecretSharing on PairwiseClientRegistration {
  /// Marker segment in envelope key names.
  static const String envelopeKeyMarker = '__ssenv';

  /// How long an unconsumed envelope lives on the atServer.
  Duration envelopeTtl = Duration(days: 7);

  /// How often [startListening] sweeps the local store for envelopes, in
  /// addition to sweeping when sync delivers one.
  Duration sweepInterval = Duration(minutes: 1);

  final StreamController<ReceivedEnvelope> _receivedController =
      StreamController<ReceivedEnvelope>.broadcast();
  final StreamController<ReceivedSecret> _receivedSecretsController =
      StreamController<ReceivedSecret>.broadcast();
  Timer? _sweepTimer;
  _EnvelopeSyncListener? _syncListener;

  /// Envelope keys already emitted on [receivedEnvelopes], so a sweep that
  /// races a slow delete cannot emit a payload twice.
  final Set<String> _consumedEnvelopeKeys = {};

  /// The secrets this client holds: what it created via
  /// [SecretStore.putSecret], plus what other clients shared with it
  /// (received secrets are stored automatically, newest-createdAt wins).
  ///
  /// One store — and at most one [SecretStore.persistence] — per client
  /// identity: all consumers of a shared instance (the app, SDK-internal
  /// users such as crypto providers) read and write the same store. Wire
  /// persistence once, when the instance is created (e.g. via
  /// `AtClientSecretSharing.forClient(persistence: ...)`); consumers must
  /// not re-assign it.
  final SecretStore secretStore = SecretStore();

  /// Decrypted, verified payloads addressed to this client.
  /// Listen, then call [startListening].
  Stream<ReceivedEnvelope> get receivedEnvelopes => _receivedController.stream;

  /// Secrets shared with this client by other clients (already verified,
  /// decrypted, and stored in [secretStore]).
  /// Listen, then call [startListening].
  Stream<ReceivedSecret> get receivedSecrets =>
      _receivedSecretsController.stream;

  /// Encrypts [payload] to [to]'s published bundle and stores it for
  /// delivery, addressed through [appNamespace].
  ///
  /// Both this client's and the recipient's enrollments must be authorized
  /// for [appNamespace] — the atServer enforces this on write (here) and on
  /// read/sync (recipient side) respectively.
  ///
  /// Throws [StateError] if [to] advertises no key with a mutually-supported
  /// algorithm.
  Future<void> sendEnvelope(
    ClientKeyPackage to,
    String appNamespace,
    Map<String, dynamic> payload,
  ) async {
    final PackageKey? recipientKey = to.bestKeyFor(SecretSharingAlgos.keyAlgos);
    if (recipientKey == null) {
      throw StateError(
          'Client ${to.clientId} advertises no key with a supported '
          'algorithm (supported: ${SecretSharingAlgos.keyAlgos})');
    }

    // X-Wing KEM: the encapsulated 32-byte shared secret IS the content
    // key — nothing secret travels except the KEM ciphertext.
    final (ciphertext: kemCiphertext, sharedSecret: contentKey) =
        await XWingPureDartAlgo.instance
            .encapsulate(base64Decode(recipientKey.pub));
    final InitialisationVector nonce =
        AtChopsUtil.generateRandomIV(AesGcm256EncryptionAlgo.nonceLength);
    final Uint8List ciphertext =
        await AesGcm256EncryptionAlgo(AESKey(base64Encode(contentKey))).encrypt(
            Uint8List.fromList(utf8.encode(jsonEncode(payload))),
            iv: nonce);

    final envelope = SecretEnvelope(
      fromClientId: clientId,
      fromEnrollmentId: enrollmentId,
      to: to.clientId,
      keyAlg: recipientKey.alg,
      kid: recipientKey.kid,
      encryptedKey: base64Encode(kemCiphertext),
      encAlg: SecretSharingAlgos.aes256Gcm,
      iv: base64Encode(nonce.ivBytes),
      ciphertext: base64Encode(ciphertext),
    );
    // GCM authenticates the payload; the APKAM signature over the whole
    // envelope additionally authenticates the SENDER (receivers still
    // verify before decrypting).
    final String signedJson = await wrapAndSignAndJsonEncode(envelope.toJson());

    final atKey = AtKey()
      ..key = '${Uuid().v4()}.${to.clientId}.$envelopeKeyMarker'
      ..namespace = appNamespace
      ..sharedBy = atClient.getCurrentAtSign()
      ..metadata.ttl = envelopeTtl.inMilliseconds;
    // shouldEncrypt=false: the value is already end-to-end encrypted to the
    // recipient client; self-key encryption would only obscure that the
    // payload is our own ciphertext. The value is raw JSON (never
    // whole-value base64) so that pre-fix readers' legacy decrypt fallback
    // also returns it untouched.
    await atClient.put(
      atKey,
      signedJson,
      putRequestOptions: PutRequestOptions()..shouldEncrypt = false,
    );
    logger.info('Stored secret envelope $atKey for client ${to.clientId}');
  }

  /// Starts watching for envelopes addressed to this client: sweeps now,
  /// after every sync that delivers an envelope key, and every
  /// [sweepInterval]. Requires [registerClient] to have completed.
  Future<void> startListening() async {
    if (_sweepTimer != null) {
      return;
    }
    // Throws StateError if not registered:
    final String marker = '.$clientId.$envelopeKeyMarker.';

    _syncListener = _EnvelopeSyncListener(marker, () {
      unawaited(sweepOnce());
    });
    atClient.syncService.addProgressListener(_syncListener!);
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
  }

  /// Scans the local store once for envelopes addressed to this client;
  /// verifies, decrypts, emits and deletes each. Returns how many envelopes
  /// were consumed. Safe to call concurrently with the periodic sweep —
  /// consumed envelopes are tracked and never emitted twice.
  Future<int> sweepOnce() async {
    final List<AtKey> envelopeKeys = await atClient.getAtKeys(
        regex: '.*\\.$clientId\\.$envelopeKeyMarker\\..*');
    int consumed = 0;
    for (final envelopeKey in envelopeKeys) {
      final keyString = envelopeKey.toString();
      if (_consumedEnvelopeKeys.contains(keyString)) {
        continue;
      }
      try {
        final ReceivedEnvelope? received = await _consume(envelopeKey);
        if (received == null) {
          // Not (or not yet) processable by this client; leave it for a
          // sibling/upgraded client or for ttl expiry.
          continue;
        }
        _consumedEnvelopeKeys.add(keyString);
        _receivedController.add(received);
        await _handleSecretPayload(received);
        consumed++;
      } catch (e) {
        // Includes transient failures (e.g. fetching the signer's _apsk key)
        // — never delete on failure, the next sweep retries.
        logger.warning('Failed to process envelope $envelopeKey: $e');
        continue;
      }
      try {
        await atClient.delete(envelopeKey);
      } catch (e) {
        logger.warning('Failed to delete consumed envelope $envelopeKey: $e');
      }
    }
    return consumed;
  }

  /// Verifies and decrypts one envelope. Returns null (after logging) for
  /// envelopes this client cannot or should not process.
  Future<ReceivedEnvelope?> _consume(AtKey envelopeKey) async {
    final AtValue av = await atClient.get(envelopeKey);
    final signedEnvelope = jsonDecode(av.value as String) as Map;
    // Verify FIRST: GCM authenticates the payload bytes, but only the
    // APKAM signature authenticates WHO sent the envelope.
    await verifyEnvelopeSignature(signedEnvelope,
        signerAtSign: atClient.getCurrentAtSign()!);
    final envelope = SecretEnvelope.fromJson(signedEnvelope['payload']);

    if (envelope.to != clientId) {
      logger.warning('Envelope $envelopeKey is addressed to '
          '${envelope.to}, not to this client; skipping');
      return null;
    }
    if (signedEnvelope['enrollmentId'] != envelope.fromEnrollmentId) {
      logger.warning('Envelope $envelopeKey: signer enrollment '
          '${signedEnvelope['enrollmentId']} does not match claimed sender '
          'enrollment ${envelope.fromEnrollmentId}; skipping');
      return null;
    }
    if (envelope.keyAlg != SecretSharingAlgos.xWing ||
        envelope.encAlg != SecretSharingAlgos.aes256Gcm) {
      logger.warning('Envelope $envelopeKey uses unsupported algorithms '
          '(keyAlg: ${envelope.keyAlg}, encAlg: ${envelope.encAlg}); '
          'skipping');
      return null;
    }
    final String myKid = PackageKey.computeKid(base64Encode(xWingPublicKey));
    if (envelope.kid != myKid) {
      logger.warning('Envelope $envelopeKey was encrypted to key '
          '${envelope.kid} which this client does not hold; skipping');
      return null;
    }

    final Uint8List contentKey = await XWingPureDartAlgo.instance
        .decapsulate(xWingSeed, base64Decode(envelope.encryptedKey));
    // GCM decryption authenticates: tampering (or a wrong-recipient
    // decapsulation, which yields a different key) throws here.
    final Uint8List plaintext =
        await AesGcm256EncryptionAlgo(AESKey(base64Encode(contentKey))).decrypt(
            base64Decode(envelope.ciphertext),
            iv: InitialisationVector(base64Decode(envelope.iv)));

    return ReceivedEnvelope(
      fromClientId: envelope.fromClientId,
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
  /// library (`request`/`response` for the planned pull flow — see
  /// docs/crypto-roadmap.md step 3). Apps embedding their own payloads via
  /// [sendEnvelope] should use other `kind` values; unknown kinds are
  /// delivered on [receivedEnvelopes] and otherwise ignored.
  static const String secretPayloadKind = 'secret';

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
  /// (newest-createdAt wins) and emits it on [receivedSecrets].
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
          '${received.fromClientId}: $e');
      return;
    }
    final stored = await secretStore.putIfNewer(secret);
    if (!stored) {
      logger.info('Ignoring secret ${secret.namespace}:${secret.name} from '
          '${received.fromClientId}: already hold a same-or-newer one');
      return;
    }
    _receivedSecretsController.add(ReceivedSecret(
      secret: secret,
      fromClientId: received.fromClientId,
      fromEnrollmentId: received.fromEnrollmentId,
    ));
  }

  /// Shares one secret with one client.
  Future<void> shareSecretWith(ClientKeyPackage to, Secret secret) =>
      sendEnvelope(to, secret.namespace, {
        'kind': secretPayloadKind,
        'name': secret.name,
        'value': secret.value,
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
  /// Returns the number of secrets shared.
  Future<int> shareAllSecretsWith(
    ClientKeyPackage to, {
    Map<String, dynamic>? approvedNamespaces,
  }) async {
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

  /// For use by an enrollment approver, after approving [enrollmentId] with
  /// [approvedNamespaces] (both available from the enrollment request):
  /// waits for the newly-approved enrollment's client(s) to publish their
  /// key bundles, then shares with each of them every held secret the
  /// enrollment's namespaces authorize.
  ///
  /// Polls every [pollInterval] until at least one bundle is found or
  /// [timeout] elapses (a freshly approved client must authenticate and
  /// register before it is discoverable). Returns the total number of
  /// secrets shared (0 on timeout).
  Future<int> shareAllSecretsWithEnrollment(
    String enrollmentId,
    Map<String, dynamic> approvedNamespaces, {
    Duration timeout = const Duration(minutes: 5),
    Duration pollInterval = const Duration(seconds: 10),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final bundles = await discoverClients(enrollmentId: enrollmentId);
      if (bundles.isNotEmpty) {
        int shared = 0;
        for (final bundle in bundles) {
          shared += await shareAllSecretsWith(bundle,
              approvedNamespaces: approvedNamespaces);
        }
        return shared;
      }
      if (DateTime.now().isAfter(deadline)) {
        logger.warning('No client of enrollment $enrollmentId published a '
            'key bundle within $timeout; no secrets shared');
        return 0;
      }
      await Future.delayed(pollInterval);
    }
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
