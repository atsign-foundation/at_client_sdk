import 'dart:async';
import 'dart:math' show Random;
import 'dart:convert'
    show base64Decode, base64Encode, jsonDecode, jsonEncode, utf8;
import 'dart:typed_data' show Uint8List;

import 'package:at_chops/at_chops.dart'
    show AtKemAlgorithm, PqOpenException, pqOpen, pqSeal;
import 'package:at_client/src/client/request_options.dart'
    show DeleteRequestOptions, GetRequestOptions, PutRequestOptions;
import 'package:at_client/src/response/at_notification.dart'
    show AtNotification;
import 'package:at_client/src/service/notification_service.dart'
    show NotificationParams;
import 'package:at_client/src/service/sync_service.dart'
    show SyncDirection, SyncProgress, SyncProgressListener;
import 'package:at_commons/at_commons.dart' show AtKey, AtValue;
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_client/src/secret_sharing/enrollment_directory.dart'
    show NamespaceMember;
import 'package:at_client/src/secret_sharing/envelope_addressing.dart';
import 'package:at_client/src/secret_sharing/key_package.dart';
import 'package:at_client/src/secret_sharing/key_package_registration.dart';
import 'package:at_client/src/secret_sharing/secret_envelope.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show envelopePayloadOf, envelopeSignerOf;
import 'package:at_client/src/secret_sharing/secret_store.dart';
import 'package:uuid/uuid.dart' show Uuid;
import 'package:meta/meta.dart' show experimental, visibleForTesting;

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
  /// Marker segment in envelope key names — see [EnvelopeAddressing], which
  /// owns the address format.
  static const String envelopeKeyMarker = EnvelopeAddressing.marker;

  /// Domain-separation context bound into every sealed envelope's key
  /// schedule (the `info` argument to at_chops `pqSeal`/`pqOpen`). Ties a
  /// sealed payload to this substrate so it cannot be replayed into another
  /// `pqSeal`-based protocol, and vice versa.
  static final Uint8List sealInfo =
      Uint8List.fromList(utf8.encode('at_client/secret_sharing/v1'));

  /// How long an unconsumed envelope lives on the atServer.
  Duration envelopeTtl = Duration(days: 7);

  /// How often [startListening] sweeps for envelopes, in addition to sweeping
  /// when sync delivers one. Whether that sweep reads the local store or the
  /// atServer is decided by [clientRunsSync].
  Duration sweepInterval = Duration(minutes: 1);

  /// Whether this client runs sync (default true).
  ///
  /// It decides where [startListening]'s initial and periodic sweeps read
  /// from, and it is not cosmetic: envelopes reach the local store *only* via
  /// sync, so on a client that does not sync, a local sweep is guaranteed to
  /// find nothing every time it runs. Such a client would be left with the
  /// wake-up notification as its only automatic path to an envelope — and a
  /// wake-up missed past its expiry would strand a message that is still
  /// sitting on the atServer, readable, for the rest of [envelopeTtl].
  ///
  /// Set false and the periodic sweep reads the atServer instead, which is the
  /// lazy-fetch path for those clients. Leave it true when sync is running:
  /// sync already delivers envelopes locally, so remote sweeps would be
  /// traffic for nothing.
  bool clientRunsSync = true;

  /// Whether [sendEnvelope] also fires a best-effort wake-up notification
  /// (default on) after the put. Clients that run sync receive envelopes via
  /// sync without it; sync-less clients rely on it (their [startListening]
  /// monitors for it and does a remote sweep). It is best-effort: the
  /// envelope is already on the atServer when this fires — [sendEnvelope]
  /// writes it remote-first for exactly that reason — so a failed wake-up
  /// never fails the send, and a wake-up that arrives never points at a value
  /// that has not landed. A future atServer enhancement will emit this
  /// notification itself on a put to an `__ssenv` key, at which point senders
  /// can leave it off.
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

  /// Decides whether the enrollment behind a request may be handed a
  /// per-enrollment (`__en.`-prefixed) secret — the class that includes the
  /// signing-root private, the key that vouches for every enrollment on the
  /// atSign.
  ///
  /// Namespace authorization, which is all the answer path otherwise checks,
  /// is the wrong bar for these: any enrollment approved for the namespace
  /// clears it, and per-enrollment material must not go to "any enrollment".
  ///
  /// Null — the default — **fails closed**: per-enrollment secrets are never
  /// served on request. `AtClientSecretSharing` wires the production
  /// resolver, which reads the requester's enrollment record off the
  /// atServer and requires full privilege (`rw` on `*` and `__manage`) —
  /// the record, not anything the requester asserts about itself.
  Future<bool> Function(String requesterEnrollmentId)?
      perEnrollmentSecretRequestGate;

  /// Anti-storm floor: the same (requester, secret-name) is answered at most
  /// once per this interval. A burst of duplicate requests collapses to one
  /// share.
  Duration requestAnswerMinInterval = const Duration(seconds: 5);

  /// `'<requesterKpid>:<secretName>' → last answered at`. In-memory; the
  /// cap is best-effort anti-storm, not a security control.
  final Map<String, DateTime> _lastAnsweredRequest = {};

  /// How long a responder waits, uniformly at random within this window,
  /// before answering a pull request.
  ///
  /// Every authorised holder sees the same request and would otherwise answer
  /// at once: N holders, N seals, N writes, for one secret the requester only
  /// needs once. [requestAnswerMinInterval] does not help — it is per
  /// responder, so it stops one holder repeating itself and says nothing about
  /// the crowd. The wait spreads them out so that [_answerAlreadySent] has
  /// something to observe. Set to [Duration.zero] to answer immediately.
  Duration requestAnswerJitter = const Duration(seconds: 2);

  /// Source of the jitter, injectable so a test can make it deterministic.
  @visibleForTesting
  Random requestAnswerRandom = Random();

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

    // Everything about the construction comes from the RECIPIENT, not from
    // this client's own configuration. Which KEM this atSign mints is its own
    // business; what it seals to is decided by the key the recipient published
    // and the suites that recipient says it can open.
    //
    // The candidate list is narrowed to the chosen key's own KEM first, so a
    // suite can never be picked that the key cannot decapsulate — the two are
    // separate fields in the key package and a holder may advertise more than
    // one KEM.
    final AtKemAlgorithm? kem = SecretSharingAlgos.kemFor(recipientKey.alg);
    final String? suite =
        to.bestSuiteFor(SecretSharingAlgos.openableSuitesFor(recipientKey.alg));
    final int? version =
        suite == null ? null : SecretSharingAlgos.sealVersionFor(suite);
    if (kem == null || suite == null || version == null) {
      // Refused rather than sealed under this client's own preference: the
      // recipient would get an envelope it cannot unwrap, and the failure
      // would surface on their side as an opaque AEAD error with nothing to
      // point at.
      throw StateError(
          'No mutually supported construction for key package '
          '${to.enrollmentId}/${to.apkamId}: it advertises a '
          '${recipientKey.alg} key opening ${to.suites}, and this client '
          'produces ${SecretSharingAlgos.suites}');
    }

    // pqSeal encapsulates to the recipient's published key and wraps the
    // payload (AEAD over the suite's key schedule) into one envelope — nothing
    // secret travels except that sealed envelope.
    final Uint8List sealed = await pqSeal(
      kem,
      base64Decode(recipientKey.pub),
      Uint8List.fromList(utf8.encode(jsonEncode(payload))),
      info: sealInfo,
      version: version,
    );

    final envelope = SecretEnvelope(
      fromKpid: kpid,
      fromEnrollmentId: enrollmentId,
      toKpid: recipientKey.kid,
      suite: suite,
      kid: recipientKey.kid,
      sealed: base64Encode(sealed),
    );
    // pqSeal's AEAD authenticates the payload; the APKAM signature over the
    // whole envelope additionally authenticates the SENDER (receivers still
    // verify before decrypting).
    final String signedJson = await wrapAndSignAndJsonEncode(envelope.toJson());

    final atKey = EnvelopeAddressing.envelopeKey(
      msgId: Uuid().v4(),
      recipientKpid: recipientKey.kid,
      appNamespace: appNamespace,
      sharedBy: atClient.getCurrentAtSign(),
      ttl: envelopeTtl,
    );
    // shouldEncrypt=false: the value is already end-to-end encrypted to the
    // recipient; self-key encryption would only obscure that the payload is
    // our own ciphertext. The value is raw JSON (never whole-value base64) so
    // that pre-fix readers' legacy decrypt fallback also returns it untouched.
    //
    // useRemoteAtServer=true: the envelope is a remote-only value — every
    // reader but the writer fetches it from the atServer, and the writer never
    // reads its own. A local-first put would also let the wake-up below
    // outrun it: the notify is a direct remote call while a local-first value
    // waits for a sync cycle, so a sync-less recipient would remote-sweep an
    // atServer that does not hold the envelope yet, and the wake-up is
    // one-shot. Writing remote-first makes the ordering correct by
    // construction. The cost is that an offline sender fails here rather than
    // queueing; the pull path (requestSecret) is the backstop for that.
    await atClient.put(
      atKey,
      signedJson,
      putRequestOptions: PutRequestOptions()
        ..shouldEncrypt = false
        ..useRemoteAtServer = true,
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

  /// Starts watching for envelopes addressed to this client: sweeps now, after
  /// every sync that delivers an envelope key, and every [sweepInterval]; and
  /// subscribes to wake-up notifications, doing a remote sweep on each.
  ///
  /// The initial and periodic sweeps read wherever [clientRunsSync] says
  /// envelopes arrive — the local store when sync is running, the atServer
  /// when it is not. Requires [register] to have completed.
  Future<void> startListening() async {
    if (_sweepTimer != null) {
      return;
    }
    // Throws StateError if not registered:
    final String marker = EnvelopeAddressing.fragmentFor(kpid);

    _syncListener = _EnvelopeSyncListener(marker, () {
      unawaited(sweepOnce());
    });
    atClient.syncService.addProgressListener(_syncListener!);
    // A wake-up notification only nudges us; the envelope itself is fetched
    // from the atServer (a sync-less client has no local copy), so the sweep
    // it triggers reads remote.
    _wakeUpSubscription = atClient.notificationService
        .subscribe(
            regex: EnvelopeAddressing.regexFor(kpid), shouldDecrypt: false)
        .listen((_) => unawaited(sweepOnce(fromRemote: true)));
    // Envelopes only reach the local store via sync, so a client that does
    // not sync must sweep the atServer or its periodic sweep can never find
    // anything — leaving a missed wake-up as an unrecoverable loss of a
    // message that is still sitting on the atServer.
    final bool sweepRemote = !clientRunsSync;
    _sweepTimer = Timer.periodic(
        sweepInterval, (_) => unawaited(sweepOnce(fromRemote: sweepRemote)));
    await sweepOnce(fromRemote: sweepRemote);
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
        regex: EnvelopeAddressing.sweepRegexFor(kpid),
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
      final ReceivedEnvelope? received;
      try {
        received = await _consume(envelopeKey, fromRemote: fromRemote);
      } catch (e) {
        // Includes transient failures (e.g. fetching the signer's _apsk key)
        // — never delete on failure; release the claim so the next sweep
        // retries. Nothing has been emitted yet, so a retry repeats nothing.
        _consumedEnvelopeKeys.remove(keyString);
        logger.warning('Failed to process envelope $envelopeKey: $e');
        continue;
      }
      if (received == null) {
        // Not (or not yet) processable by this client; leave it for a
        // sibling/upgraded client or for ttl expiry.
        _consumedEnvelopeKeys.remove(keyString);
        continue;
      }
      _receivedController.add(received);
      try {
        await _handleSecretPayload(received); // no-op unless kind=='secret'
        await _handleRequestPayload(received); // no-op unless kind=='request'
      } catch (e) {
        // The envelope has been EMITTED: releasing the claim here would hand
        // it to the next sweep for a second emission. Keep the claim and keep
        // the envelope (no delete) — a fresh process, whose stream has no
        // listeners yet, retries the whole thing.
        logger.warning('Envelope $envelopeKey was received but its payload '
            'handler failed; it is kept for a retry at the next start: $e');
        continue;
      }
      consumed++;
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
    final envelope = SecretEnvelope.fromJson(envelopePayloadOf(signedEnvelope));

    if (envelope.toKpid != kpid) {
      logger.warning('Envelope $envelopeKey is addressed to '
          '${envelope.toKpid}, not to this client; skipping');
      return null;
    }
    final signerClaim = envelopeSignerOf(signedEnvelope);
    if (signerClaim != envelope.fromEnrollmentId) {
      logger.warning('Envelope $envelopeKey: signer enrollment '
          '$signerClaim does not match claimed sender '
          'enrollment ${envelope.fromEnrollmentId}; skipping');
      return null;
    }
    // Resolving the KEM doubles as the support check. Testing membership of
    // `SecretSharingAlgos.suites` separately would be a second list that has
    // to agree with this one, and a suite present in that list but absent
    // here would pass the guard and then have no KEM to open with.
    final AtKemAlgorithm? kem =
        SecretSharingAlgos.kemForSuite(envelope.suite);
    if (kem == null) {
      logger.warning('Envelope $envelopeKey uses unsupported sealing suite '
          '${envelope.suite}; skipping');
      return null;
    }
    if (envelope.kid != kpid) {
      logger.warning('Envelope $envelopeKey was encrypted to key '
          '${envelope.kid} which this client does not hold; skipping');
      return null;
    }

    // pqOpen reads the envelope's version byte itself, but the KEM instance is
    // this caller's to supply and the two must agree — a hybrid envelope
    // decapsulated with ML-KEM fails indistinguishably from a tampered one.
    // The suite is what names it, which is why the envelope carries it.
    //
    // pqOpen's AEAD authenticates: tampering, a wrong-recipient
    // decapsulation, or mismatched `info` all surface as a PqOpenException.
    // It is deterministic — retrying cannot help — so a failure leaves the
    // envelope for ttl expiry rather than blocking sweeps forever.
    final Uint8List plaintext;
    try {
      plaintext = await pqOpen(
        kem,
        encSecretKey,
        base64Decode(envelope.sealed),
        info: sealInfo,
      );
    } on PqOpenException catch (e) {
      logger.warning('Envelope $envelopeKey failed to open ($e); skipping');
      return null;
    }

    return ReceivedEnvelope(
      fromKpid: envelope.fromKpid,
      fromEnrollmentId: envelope.fromEnrollmentId,
      appNamespace: EnvelopeAddressing.appNamespaceOf(envelopeKey),
      payload: jsonDecode(utf8.decode(plaintext)) as Map<String, dynamic>,
    );
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

  /// Whether [member] is this client, so a broadcast skips itself.
  ///
  /// Identity is the **enrollment**, not the kpid. Comparing kpids reads a
  /// package's addressing token, and that token is a *reader's* choice —
  /// [KeyPackage.kpid] returns the first key in this build's
  /// [SecretSharingAlgos.keyAlgos] order, so once a package advertises more
  /// than one key two builds with different orderings disagree about the same
  /// package's kpid and a client can fail to recognise itself. It also misses
  /// the drift case with one key: an instance whose enrollment changed under it
  /// holds the old keypair while the directory serves the new package, so the
  /// kpids differ and it sends to an address it is not listening on.
  ///
  /// A client with no enrollment matches nothing, which is right — `enroll:listns`
  /// enumerates enrollments, so a legacy PKAM client is not on the roster it is
  /// comparing against. [selfEnrollmentId] is read once by the caller rather
  /// than per member: the getter warns every time it falls back to `primary`.
  bool _isSelf(NamespaceMember member, String selfEnrollmentId) =>
      member.enrollmentId == selfEnrollmentId;

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
    final String selfId = enrollmentId;
    int sent = 0;
    for (final member in members) {
      final to = member.keyPackage;
      if (to != null && to.kpid != null && !_isSelf(member, selfId)) {
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
      final kp = member.keyPackage;
      if (kp != null && kp.kpid == received.fromKpid) {
        requester = kp;
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

    if (requestAnswerJitter > Duration.zero) {
      await Future.delayed(Duration(
          microseconds:
              requestAnswerRandom.nextInt(requestAnswerJitter.inMicroseconds)));
    }

    if (await _answerAlreadySent(received.fromKpid, received.appNamespace)) {
      logger.info('Not answering kpid ${received.fromKpid}: another holder '
          'already did');
      return;
    }

    final want = (received.payload['want'] as List?)?.cast<String>().toSet();
    final namePrefix = received.payload['namePrefix'] as String?;
    final now = DateTime.now();
    // Resolved at most once per inbound request, not per matching secret —
    // it costs a round trip to the enrollment record.
    bool? requesterMayTakePerEnrollment;
    for (final secret in _candidatesFor(received, want, namePrefix)) {
      if (want != null && !want.contains(secret.name)) {
        continue;
      }
      if (isPerEnrollmentSecretName(secret.name)) {
        final gate = perEnrollmentSecretRequestGate;
        requesterMayTakePerEnrollment ??=
            gate != null && await gate(received.fromEnrollmentId);
        if (!requesterMayTakePerEnrollment) {
          // Warning, not finer: a refused serve must be attributable, or a
          // legitimate privileged puller's failure presents as "the holder
          // never answered" and gets blamed on the wrong side.
          logger.warning('Not serving ${secret.name} to enrollment '
              '${received.fromEnrollmentId} (kpid ${received.fromKpid}): '
              'per-enrollment secrets are served only to fully privileged '
              'enrollments${gate == null ? ', and no privilege resolver is '
                  'wired on this sharing instance' : ''}');
          continue;
        }
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

  /// The store entries an inbound request may be answered from.
  ///
  /// Namespace-scoped, as every ordinary secret is — a request rides one app
  /// namespace and is answered from that namespace's material.
  ///
  /// The exception is **explicitly named per-enrollment secrets**, which are
  /// addressed to an *enrollment* rather than to a namespace. The signing-root
  /// private is the case that matters: it is atSign-level and carries no
  /// namespace of its own, so a holder can only file it under some namespace
  /// it happens to run in. Two privileged enrollments of one atSign
  /// belonging to different apps therefore never match — the holder primed
  /// under its namespace, the requester asks in its own — and the pull that
  /// is the only route to an unrotatable, immutable key would silently never
  /// be answered. Named secrets only: a prefix or bare request still cannot
  /// sweep another namespace's material.
  ///
  /// Widening the search does not widen who is served: the privilege gate
  /// above decides that, and it is stricter for exactly these names.
  Iterable<Secret> _candidatesFor(
      ReceivedEnvelope received, Set<String>? want, String? namePrefix) {
    final scoped = secretStore.listSecrets(
        namespace: received.appNamespace, namePrefix: namePrefix);
    final crossNamespaceNames =
        want?.where(isPerEnrollmentSecretName).toSet() ?? const <String>{};
    if (crossNamespaceNames.isEmpty) return scoped;

    final seen = scoped.map((s) => (s.namespace, s.name)).toSet();
    return [
      ...scoped,
      ...secretStore.listSecrets().where((s) =>
          crossNamespaceNames.contains(s.name) &&
          !seen.contains((s.namespace, s.name))),
    ];
  }

  /// Envelope keys currently addressed to [kpid] in [appNamespace], read from
  /// the atServer — which is where [sendEnvelope] writes them, and where a
  /// holder that does not sync would look.
  Future<Set<String>> _envelopeKeysFor(String kpid, String appNamespace) async {
    try {
      final keys = await atClient.getAtKeys(
          regex: EnvelopeAddressing.namespaceSweepRegexFor(kpid, appNamespace),
          useRemoteAtServer: true);
      return keys.map((k) => k.toString()).toSet();
    } catch (e) {
      // Observation is an optimisation. If it fails, answering anyway costs a
      // duplicate the requester merges away; staying quiet could cost it the
      // secret entirely.
      logger.info('Could not check whether kpid $kpid was already answered, '
          'so answering: $e');
      return const {};
    }
  }

  /// Whether an answer is already waiting for [kpid] in [appNamespace].
  ///
  /// Deliberately coarse on two axes, both sound here.
  ///
  /// It cannot see *what* was answered — the envelope key carries no secret
  /// name and the payload is sealed to the requester. That does not matter,
  /// because a responder answers every matching secret in one pass, so any
  /// single answer is already complete for the request.
  ///
  /// It also cannot tell an answer to *this* request from an unconsumed one
  /// left over from an earlier exchange, because nothing in the key orders it
  /// against the request. Diffing against a snapshot taken when this responder
  /// picked the request up does not help and is strictly worse: a holder that
  /// starts late sees the earlier answer in its own baseline and concludes
  /// nothing has happened, so exactly the responders that should stay quiet
  /// are the ones that answer. Presence alone is the better rule — the
  /// requester deletes each envelope as it consumes it, and it is
  /// demonstrably online, having just sent the request, so anything still
  /// waiting for it is almost certainly a fresh answer. Over-suppressing costs
  /// a retry; under-suppressing costs the storm this exists to stop.
  Future<bool> _answerAlreadySent(String kpid, String appNamespace) async =>
      (await _envelopeKeysFor(kpid, appNamespace)).isNotEmpty;

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
      if (isPerEnrollmentSecretName(secret.name)) {
        continue;
      }
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

  /// Prefix marking a secret addressed to **one** enrollment.
  ///
  /// Distinct from the general `__` reserved space, and the distinction
  /// matters: [SecretStore.putIfNewer] accepts reserved names precisely so
  /// system secrets — namespace rotation keys among them — flow between a
  /// client's enrollments, and a newly approved device needs those. What must
  /// not flow is material addressed to a single enrollment: its own
  /// `apkamSymmetricKey`, its own approval-chain link.
  static const String perEnrollmentSecretPrefix = '__en.';

  /// Whether [name] is addressed to one enrollment, and so must never be
  /// forwarded on.
  ///
  /// A received secret is stored like any other, which is what makes this
  /// necessary rather than merely tidy: an enrollment conveyed its own key
  /// material holds it in the same store [shareAllSecretsWith] iterates, so
  /// without this the next enrollment it approves would be handed the previous
  /// one's. Forwarding is never right for these, whatever the namespace says.
  static bool isPerEnrollmentSecretName(String name) =>
      name.startsWith(perEnrollmentSecretPrefix);

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
    final String selfId = enrollmentId;
    int pushed = 0;
    for (final member in members) {
      final to = member.keyPackage;
      if (to != null && to.kpid != null && !_isSelf(member, selfId)) {
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
        final kp = member.keyPackage;
        if (kp != null) {
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
