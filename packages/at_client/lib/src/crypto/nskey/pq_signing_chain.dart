import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:at_client/src/client/at_client_spec.dart';
import 'package:collection/collection.dart' show DeepCollectionEquality;
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_auth/at_auth.dart' show ApskSigningKey, AtKeysIo;
import 'package:at_chops/at_chops.dart' show MlDsa65PureDartAlgo;
import 'package:at_client/src/mixins/envelope_signing.dart'
    show EnvelopeSigning;
import 'package:at_client/src/signing/envelope_signature.dart'
    as envelope_signature show apskUri;
import 'package:at_client/src/signing/envelope_signature.dart'
    show SignedEnvelope, signableTextOf;
import 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart'
    show AtClientSecretSharing;
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show PairwiseSecretSharing;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

/// How far up the approval chain a verifier got.
///
/// Graded rather than boolean because a bare `_apsk` is deliberately tolerated
/// during the changeover: a boolean would force every caller either to reject
/// enrollments that are valid today, or to lose the distinction that starts
/// mattering the moment the changeover ends.
@experimental
enum ChainVerdict {
  /// Reached a root link that verifies against the atSign's signing root.
  anchored,

  /// Every link walked verified, but the chain ran out before the root.
  chained,

  /// The starting enrollment publishes no link at all.
  unsigned,

  /// A link was present and wrong — a failed signature, a link describing
  /// another enrollment or another key, a cycle, or a chain too long to walk.
  ///
  /// Deliberately not folded into [chained]. An absent link means nobody has
  /// vouched yet; a bad one means something claimed to and the claim does not
  /// hold, and reporting the second as the first would hide it.
  broken,
}

/// What [PqSigningChain.verifyChain] found.
@experimental
class ChainResult {
  final ChainVerdict verdict;

  /// The enrollments walked, starting with the one asked about.
  final List<String> path;

  /// Why the walk stopped, when that is not self-evident.
  final String? reason;

  ChainResult(this.verdict, this.path, this.reason);

  @override
  String toString() => 'ChainResult(${verdict.name}, path: $path'
      '${reason == null ? '' : ', $reason'})';
}

/// The approval chain: every enrollment's APKAM public key is signed by the
/// enrollment that approved it, up to the atSign's signing root.
///
/// The link is a plain APKAM-signed envelope, which is what makes the chain
/// self-describing: the envelope already names the enrollment that signed it,
/// and verifying it already resolves that enrollment's published `_apsk`. So a
/// verifier walks upward without any approval graph having been published, and
/// a forged parent claim simply fails the signature check against the parent it
/// names.
///
/// **The parent signs and the child publishes** ([decisions.md 22.2b][] ruling
/// 7). `_apsk` writes are restricted to the owning enrollment's own
/// authenticated connection, so the signer is not a permitted writer: the
/// approver conveys the link over the substrate, and the child stamps it onto
/// its own record on first run. Until the child runs, verifiers see a bare key,
/// which the transition rule already tolerates.
///
/// [decisions.md 22.2b]: ../../../../../../docs/projects/pq/decisions.md
@experimental
class PqSigningChain {
  /// One chain view per client. The wire vocabulary (the field names, the
  /// secret name, [apskUri], the codecs) stays static — it belongs to the
  /// protocol, not to any client.
  PqSigningChain(this._atClient)
      : _logger = AtSignLogger(
            'PqSigningChain (${_atClient.getCurrentAtSign()})');

  final AtClient _atClient;
  final AtSignLogger _logger;

  /// Reserved [Secret] name for a conveyed chain link.
  ///
  /// Per-enrollment, so it is never forwarded on: a link vouches for one
  /// enrollment's key and means nothing attached to another's.
  static const String linkSecretName =
      '${PairwiseSecretSharing.perEnrollmentSecretPrefix}apskChainLink';

  /// The `appMetadata.additional` field the child stamps the link into.
  static const String linkField = 'apskChainLink';

  /// The `appMetadata.additional` field a **root** link lives in.
  ///
  /// Its own field rather than a variant of [linkField]. A root link is not
  /// another link with a different signer: it is ML-DSA-65 verified against
  /// `public:pq_signing_root@<atSign>`, where every other link is RSA verified
  /// against an `_apsk`. Different algorithm, different key source, different
  /// lookup — so the field name settles which of the two a verifier is holding
  /// before it reads anything else.
  static const String rootLinkField = 'apskRootLink';

  /// Reserved [Secret] name for a conveyed **root** link.
  ///
  /// Its own name for the same reason [rootLinkField] is its own field: which
  /// flavour arrived decides which validation runs and which field is
  /// stamped, and the name settles that before anything is decoded.
  static const String rootLinkSecretName =
      '${PairwiseSecretSharing.perEnrollmentSecretPrefix}apskRootLink';

  /// Signature algorithm marker on a root link — the same `mldsa65` the root
  /// record and the keyfile use.
  ///
  /// ⚠️ This said the record carried a hyphenated `ml-dsa-65` and that "both
  /// spellings are frozen … the pins hold the two apart on purpose". That
  /// stopped being true when the root record adopted the `_apsk` vocabulary:
  /// [PqSigningRoot.rootKeyAlgo] is `SigningAlgoType.mldsa65`, and the pin in
  /// `test/wire_literal_pins_test.dart` now asserts the opposite of what this
  /// paragraph claimed it asserted — ML-DSA-65 has ONE spelling on the wire.
  ///
  /// Write-only today: both root-link verifiers dispatch through
  /// `PqSigningRoot.verifierFor` on the algorithm of the *advertised entry*
  /// they are checking against, not on this field.
  static const String rootLinkAlgo = 'mldsa65';

  /// `public:_apsk.<enrollmentId>.a.__e@<atSign>` — where an enrollment's
  /// APKAM public key lives, and the one record its own connection may write.
  static String apskUri(String atSign, String enrollmentId) =>
      envelope_signature.apskUri(atSign, enrollmentId);

  /// The payload a parent signs to vouch for [childEnrollmentId].
  ///
  /// Both fields are bound in, not just the key: a signature over the key
  /// alone would verify equally well if replayed onto a different
  /// enrollment's record, and the whole point of the link is to say *which*
  /// enrollment this approver vouched for.
  static Map<String, Object?> linkPayload({
    required String childEnrollmentId,
    required String childApkamPublicKey,
  }) =>
      {
        'v': 1,
        'childEnrollmentId': childEnrollmentId,
        'apkamPublicKey': childApkamPublicKey,
      };

  /// Signs a link vouching for [childEnrollmentId], for the approver to convey.
  ///
  /// Reads the child's APKAM public key from the record the **atServer**
  /// published at approval rather than from the enrollment request, so what is
  /// signed is exactly what a verifier will later resolve. Signing a key taken
  /// from anywhere else would leave the two free to disagree.
  ///
  /// Returns null when the child's `_apsk` is not readable, which is not worth
  /// failing an approval over — the chain link is additive, and an enrollment
  /// without one is simply unsigned, which verifiers already tolerate.
  Future<SignedEnvelope?> signLinkFor(
    EnvelopeSigning signer,
    String childEnrollmentId,
  ) async {
    final atSign = _atClient.getCurrentAtSign()!;
    final String childKey;
    try {
      final value = await _atClient.get(
        AtKey.fromString(apskUri(atSign, childEnrollmentId)),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      childKey = value.value as String;
    } catch (e) {
      _logger.warning('No readable _apsk for enrollment $childEnrollmentId, '
          'so no chain link was signed for it; it stays unsigned: $e');
      return null;
    }

    return await signer.wrapAndSign(linkPayload(
      childEnrollmentId: childEnrollmentId,
      childApkamPublicKey: childKey,
    ));
  }

  /// Signs a **root** link vouching for [childEnrollmentId], for a fully
  /// privileged client to convey.
  ///
  /// The class that signs root links is decided by *privilege*, not by
  /// possession: any fully privileged enrollment (`rw` on `*` and
  /// `__manage`) anchors the enrollments it vouches for directly to the
  /// signing root — one hop, verified against the published root — rather
  /// than signing chain links attributed to itself. The caller supplies
  /// [rootPrivate] because privilege is its gate and possession is its
  /// responsibility; a privileged client that has not yet received the
  /// private heals that by pulling, not by demoting to a chain link.
  ///
  /// Reads the child's key from the record the **atServer** published,
  /// exactly as [signLinkFor] does and for the same reason. Returns null
  /// when the child's `_apsk` is not readable.
  Future<Map<String, Object?>?> signRootLinkFor(
    String childEnrollmentId, {
    required Uint8List rootPrivate,
  }) async {
    final atSign = _atClient.getCurrentAtSign()!;
    final String childKey;
    try {
      final value = await _atClient.get(
        AtKey.fromString(apskUri(atSign, childEnrollmentId)),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      childKey = value.value as String;
    } catch (e) {
      _logger.warning('No readable _apsk for enrollment $childEnrollmentId, '
          'so no root link was signed for it; it stays unsigned: $e');
      return null;
    }

    return _rootLinkOver(
      linkPayload(
        childEnrollmentId: childEnrollmentId,
        childApkamPublicKey: childKey,
      ),
      rootPrivate,
    );
  }

  /// The published root-link shape over [payload]: the one codec
  /// [publishOwnRootLink], [signRootLinkFor] and [_checkRootLink] agree on.
  static Future<Map<String, Object?>> _rootLinkOver(
    Map<String, Object?> payload,
    Uint8List rootPrivate,
  ) async {
    final signature = await MlDsa65PureDartAlgo().signBytes(
      Uint8List.fromList(utf8.encode(signableTextOf(payload))),
      secretKey: rootPrivate,
    );
    return {
      'v': 1,
      'alg': rootLinkAlgo,
      'payload': payload,
      'signature': base64Encode(signature),
    };
  }

  /// Stamps a conveyed [link] onto this enrollment's own `_apsk`.
  ///
  /// Rewrites the record with its value unchanged and the link added to
  /// `appMetadata.additional`. The value has to be re-sent because a put
  /// replaces the record; what is sent back is the record's current state —
  /// [current] when the caller already read it, else read here — so the key
  /// published is the one already there rather than one this client believes
  /// it should be.
  ///
  /// The provider id is the legacy one, which is accurate rather than a
  /// placeholder: `_apsk` is a public plaintext key and no provider encrypts
  /// it. Only `additional` carries anything new.
  Future<void> publishLink(
    String enrollmentId,
    SignedEnvelope link, {
    AtValue? current,
  }) async {
    // Resolved before the write: a link so malformed its signer cannot be
    // read is refused here rather than published and then logged broken.
    final signer = link.signerEnrollmentId;
    await _publishInto(enrollmentId, linkField, link.toJson(),
        current: current);
    _logger.info('Published chain link for $enrollmentId, signed by enrollment '
        '$signer');
  }

  /// Adds [value] under [field] in this enrollment's `_apsk` `appMetadata`,
  /// leaving the record's value and any other field alone.
  ///
  /// The record's current state is re-sent because a put replaces the record;
  /// sending back what is already there means the key published stays the one
  /// every verifier resolves rather than one this client believes it should
  /// be. A caller that already read the record passes it as [current], so the
  /// checks it made and the write here come from ONE snapshot — a separate
  /// read would let the record change in between.
  ///
  /// Existing `additional` entries are carried forward, so the chain link and
  /// the root link coexist on the same record instead of overwriting each
  /// other.
  Future<void> _publishInto(
    String enrollmentId,
    String field,
    Map<String, Object?> value, {
    AtValue? current,
  }) async {
    final atSign = _atClient.getCurrentAtSign()!;
    final uri = apskUri(atSign, enrollmentId);

    current ??= await _atClient.get(
      AtKey.fromString(uri),
      getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
    );

    final atKey = AtKey.fromString(uri);
    atKey.metadata.appMetadata = AppMetadata(
      providerId: CryptoRuntime.legacyProviderId,
      additional: {
        ...?current.metadata?.appMetadata?.additional,
        field: value,
      },
    );

    await _atClient.put(
      atKey,
      current.value,
      putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
    );
  }

  /// The chain link an enrollment has published, or null if it has none.
  ///
  /// An absent link is ordinary — the enrollment has not run since approval,
  /// or predates the chain — so this reports absence rather than failing.
  Future<SignedEnvelope?> readLink(
    String enrollmentId,
  ) async {
    final field = await _readField(enrollmentId, linkField);
    return field == null ? null : SignedEnvelope.fromJson(field);
  }

  Future<Map<String, Object?>?> _readField(
    String enrollmentId,
    String field,
  ) async {
    final atSign = _atClient.getCurrentAtSign()!;
    try {
      final value = await _atClient.get(
        AtKey.fromString(apskUri(atSign, enrollmentId)),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      return _fieldFrom(value, field);
    } catch (e) {
      _logger.info('No _apsk readable for enrollment $enrollmentId: $e');
      return null;
    }
  }

  /// The link under [field] in an already-read `_apsk` [value], or null.
  /// The in-hand flavour of [_readField], for callers that must make every
  /// check against one snapshot of the record.
  static Map<String, Object?>? _fieldFrom(AtValue value, String field) {
    final link = value.metadata?.appMetadata?.additional?[field];
    if (link is Map) return link.cast<String, Object?>();
    return null;
  }

  /// Signs and publishes this enrollment's **root** link, if it is entitled to
  /// one and does not already have it. Returns whether it published.
  ///
  /// Self-signed rather than conveyed: [PqSigningRoot] puts the private in
  /// every fully privileged enrollment, and those are exactly the enrollments
  /// that get a root link — so the signer is always the record's own writer and
  /// `_apsk`'s writes-only-from-its-own-connection rule never bites here. That
  /// is the difference from a chain link, where the signer can never be the
  /// writer.
  ///
  /// [isFullyPrivileged] is required rather than inferred from holding the
  /// private. The two should never diverge, and checking keeps the invariant —
  /// only that class carries a root link — true if they ever do.
  ///
  /// Runs at mint and at every start. That one rule covers the minter, a
  /// privileged peer that predates the root, one approved afterwards, one
  /// approved by a non-root-holding approver, and a root minted late: the retro
  /// case needs no migration because it is not a special case.
  Future<bool> publishOwnRootLink( {
    required Future<bool> Function() isFullyPrivileged,
    AtKeysIo? keysIo,
  }) async {
    final atSign = _atClient.getCurrentAtSign()!;
    final enrollmentId = AtClientSecretSharing.forClient(_atClient).enrollmentId;

    // Possession is checked first because it is a local `AtKeys` read, where
    // establishing privilege costs a round trip. An enrollment holding no root
    // private cannot anchor itself whatever its privileges, so the cheap gate
    // is also the one that eliminates almost every client at start.
    final private =
        await PqSigningRoot(_atClient, keysIo: keysIo).privateHalf(atSign);
    if (private == null) return false;

    if (!await isFullyPrivileged()) {
      _logger.warning('This enrollment holds the signing root private but is '
          'not fully privileged, so it is not anchoring itself. The two should '
          'never diverge; that they have is worth investigating.');
      return false;
    }

    final AtValue current;
    try {
      current = await _atClient.get(
        AtKey.fromString(apskUri(atSign, enrollmentId)),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
    } catch (e) {
      _logger.info('No _apsk published for $enrollmentId yet, so there is '
          'nothing to anchor: $e');
      return false;
    }

    if (_fieldFrom(current, rootLinkField) != null) return false;

    final link = await _rootLinkOver(
      linkPayload(
        childEnrollmentId: enrollmentId,
        childApkamPublicKey: current.value as String,
      ),
      private,
    );

    await _publishInto(enrollmentId, rootLinkField, link, current: current);
    _logger.info('Anchored $enrollmentId to the signing root');
    return true;
  }

  /// The root link an enrollment has published, or null if it has none.
  Future<Map<String, Object?>?> readRootLink(
    String enrollmentId,
  ) async =>
      _readField(enrollmentId, rootLinkField);

  /// Publishes the links this enrollment was conveyed — a root link, a chain
  /// link, or both — if any is waiting and its key does not already carry it.
  /// Returns whether anything was published.
  ///
  /// Self-gating: an enrollment nobody vouched for has no link in its store and
  /// this writes nothing, so it costs a client that will never have one an
  /// in-memory lookup at start and no atServer traffic at all.
  ///
  /// A link that arrives *after* this runs is published at the next start
  /// rather than immediately — the same trade the namespace-key seeding makes,
  /// and acceptable for the same reason: until it lands the enrollment is
  /// simply unsigned, which verifiers tolerate during the changeover.
  ///
  /// The two flavours coexist on the record ([linkField], [rootLinkField]) and
  /// a verifier prefers the root one, so stamping both loses nothing.
  Future<bool> publishPendingLink() async {
    final rootPublished = await _publishPendingRootLink();
    final chainPublished = await _publishPendingChainLink();
    return rootPublished || chainPublished;
  }

  /// Stamps a conveyed **root** link, after verifying it the way a downstream
  /// verifier will.
  ///
  /// The conveyance channel authenticates the *sender*, and the sender is not
  /// the root — so the link is verified against the published signing root
  /// before it is stamped, plus the same two checks every link gets: it names
  /// **this** enrollment, and it vouches for the key actually published. A
  /// link that fails any of them is refused rather than published as
  /// something no verifier could follow.
  Future<bool> _publishPendingRootLink() async {
    final sharing = AtClientSecretSharing.forClient(_atClient);
    final atSign = _atClient.getCurrentAtSign()!;
    final enrollmentId = sharing.enrollmentId;

    final secret = sharing.secretStore
        .listSecrets()
        .where((s) => s.name == rootLinkSecretName)
        .firstOrNull;
    if (secret == null) return false;

    final Map<String, Object?> link;
    final Map payload;
    try {
      link = decodeConveyedLink(secret.value);
      payload = link['payload'] as Map;
    } catch (e) {
      _logger.warning('Conveyed root link is malformed; not publishing: $e');
      return false;
    }

    if (payload['childEnrollmentId'] != enrollmentId) {
      _logger.warning('Conveyed root link vouches for enrollment '
          '${payload['childEnrollmentId']}, not for $enrollmentId; not '
          'publishing it here');
      return false;
    }

    final candidates = await _rootCandidates(atSign);
    if (candidates.isEmpty) {
      _logger.warning('A root link was conveyed but $atSign publishes no '
          'signing root to verify it against; not publishing an unverifiable '
          'link');
      return false;
    }
    final bool verifies;
    try {
      verifies = await _verifiesUnderAny(
        Uint8List.fromList(
            utf8.encode(signableTextOf(payload.cast<String, Object?>()))),
        link['signature'] as String,
        candidates,
      );
    } catch (e) {
      _logger.warning('Conveyed root link could not be checked; not '
          'publishing: $e');
      return false;
    }
    if (!verifies) {
      _logger.warning('Conveyed root link does not verify against the '
          "atSign's signing root, so publishing it would advertise a link no "
          'verifier can follow');
      return false;
    }

    final AtValue current;
    try {
      current = await _atClient.get(
        AtKey.fromString(apskUri(atSign, enrollmentId)),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
    } catch (e) {
      _logger.warning('This enrollment has no readable _apsk to publish a '
          'root link onto: $e');
      return false;
    }

    if (payload['apkamPublicKey'] != current.value) {
      _logger.warning('Conveyed root link vouches for a key that is not the '
          'one published for $enrollmentId; not publishing it');
      return false;
    }

    final existing = _fieldFrom(current, rootLinkField);
    if (existing != null && _sameLink(existing, link)) {
      return false;
    }

    await _publishInto(enrollmentId, rootLinkField, link, current: current);
    _logger.info('Anchored $enrollmentId to the signing root via a conveyed '
        'root link');
    return true;
  }

  /// Stamps a conveyed chain link.
  ///
  /// Three things are checked before anything is written, because this record
  /// is the enrollment's published identity and a bad link on it is worse than
  /// no link:
  ///
  /// - the link names **this** enrollment, so one conveyed for a sibling is
  ///   never stamped here;
  /// - it verifies against the parent it names, so a link that could never be
  ///   verified downstream is not published as though it could;
  /// - the key it vouches for is the key actually published, so a link that
  ///   silently covers something else is refused.
  Future<bool> _publishPendingChainLink() async {
    final sharing = AtClientSecretSharing.forClient(_atClient);
    final atSign = _atClient.getCurrentAtSign()!;
    final enrollmentId = sharing.enrollmentId;

    final secret = sharing.secretStore
        .listSecrets()
        .where((s) => s.name == linkSecretName)
        .firstOrNull;
    if (secret == null) return false;

    final SignedEnvelope link;
    final Map payload;
    try {
      link = SignedEnvelope.fromJson(decodeConveyedLink(secret.value));
      payload = link.payload as Map;
    } catch (e) {
      _logger.warning('Conveyed chain link is malformed; not publishing: $e');
      return false;
    }

    if (payload['childEnrollmentId'] != enrollmentId) {
      _logger.warning('Conveyed chain link vouches for enrollment '
          '${payload['childEnrollmentId']}, not for $enrollmentId; not '
          'publishing it here');
      return false;
    }

    try {
      await sharing.verifyEnvelopeSignature(link, signerAtSign: atSign);
    } catch (e) {
      _logger.warning('Conveyed chain link does not verify against the '
          'enrollment it names as signer, so publishing it would advertise a '
          'link no verifier can follow: $e');
      return false;
    }

    final AtValue current;
    try {
      current = await _atClient.get(
        AtKey.fromString(apskUri(atSign, enrollmentId)),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
    } catch (e) {
      _logger.warning('This enrollment has no readable _apsk to publish a '
          'chain link onto: $e');
      return false;
    }

    if (payload['apkamPublicKey'] != current.value) {
      _logger.warning('Conveyed chain link vouches for a key that is not the '
          'one published for $enrollmentId; not publishing it');
      return false;
    }

    final existing = _fieldFrom(current, linkField);
    if (existing != null && _sameLink(existing, link.toJson())) {
      return false;
    }

    await publishLink(enrollmentId, link, current: current);
    return true;
  }

  /// Whether [a] and [b] are the same link, compared whole.
  ///
  /// Used for BOTH link flavours, which is the point. A single-member
  /// comparison of `['signature']` is right for a root link and wrong for a
  /// chain link — the chain link is a signed envelope, whose signature lives
  /// inside its `signatures` array, so the read is null on both sides,
  /// `null == null` holds, and every existing link matches every new one. The
  /// conveyed link is then never published, silently and with nothing to log,
  /// because "already published" and "never published" are the same branch.
  ///
  /// The root-link version of that comparison was correct only because that
  /// format happens to carry a top-level signature. Comparing whole is right
  /// for both without depending on either shape, so the next shape change
  /// cannot reintroduce this by moving a member.
  static bool _sameLink(Map<String, Object?> a, Map<String, Object?> b) =>
      const DeepCollectionEquality().equals(a, b);

  /// Walks upward from [enrollmentId] and reports how far the chain holds.
  ///
  /// Stops at a root link verified against `public:pq_signing_root@<atSign>`.
  /// Failing that it follows chain links from parent to parent, and reports
  /// where it ran out.
  ///
  /// [maxDepth] and the visited set are not defensive padding: the chain is
  /// assembled from records that a compromised enrollment partly controls, so
  /// a cycle or an absurdly long chain is an input to expect rather than an
  /// impossibility. Either ends the walk as [ChainVerdict.broken] — a chain
  /// that cannot be walked is not a chain that is merely unanchored.
  Future<ChainResult> verifyChain(
    EnvelopeSigning verifier,
    String enrollmentId, {
    int maxDepth = 16,
  }) async {
    final atSign = _atClient.getCurrentAtSign()!;
    final path = <String>[];
    final seen = <String>{};
    String current = enrollmentId;

    while (true) {
      if (!seen.add(current)) {
        return ChainResult(ChainVerdict.broken, path,
            'the chain revisits enrollment $current, so it does not terminate');
      }
      path.add(current);

      final rootLink = await readRootLink(current);
      if (rootLink != null) {
        return await _checkRootLink(atSign, current, rootLink, path);
      }

      final link = await readLink(current);
      if (link == null) {
        return ChainResult(
            path.length == 1 ? ChainVerdict.unsigned : ChainVerdict.chained,
            path,
            'enrollment $current publishes no link, so the walk stops below '
            'the root');
      }

      final failure =
          await _checkChainLink(verifier, atSign, current, link);
      if (failure != null) {
        return ChainResult(ChainVerdict.broken, path, failure);
      }

      final parent = link.signerEnrollmentId;
      if (parent == null || parent.isEmpty) {
        return ChainResult(
            ChainVerdict.broken,
            path,
            'enrollment $current names no signer, so there is nowhere to '
            'walk to');
      }
      if (path.length >= maxDepth) {
        return ChainResult(ChainVerdict.broken, path,
            'the chain from $enrollmentId is longer than $maxDepth hops');
      }
      current = parent;
    }
  }

  /// Null when [link] is sound for [enrollmentId]; otherwise why it is not.
  Future<String?> _checkChainLink(
    EnvelopeSigning verifier,
    String atSign,
    String enrollmentId,
    SignedEnvelope link,
  ) async {
    try {
      await verifier.verifyEnvelopeSignature(link, signerAtSign: atSign);
    } catch (e) {
      return 'the link on $enrollmentId does not verify against the '
          'enrollment it names as signer: $e';
    }
    final payload = link.payload;
    if (payload is! Map) return 'the link on $enrollmentId has no payload';
    if (payload['childEnrollmentId'] != enrollmentId) {
      return 'the link on $enrollmentId vouches for '
          '${payload['childEnrollmentId']} instead';
    }
    // The signature proves the parent said something; this proves it said it
    // about the key actually published. Without it a genuine link could sit
    // over a key it never covered.
    final published = await _publishedKey(atSign, enrollmentId);
    if (published != payload['apkamPublicKey']) {
      return 'the link on $enrollmentId vouches for a key other than the one '
          'published for it';
    }
    return null;
  }

  Future<ChainResult> _checkRootLink(
    String atSign,
    String enrollmentId,
    Map<String, Object?> link,
    List<String> path,
  ) async {
    final candidates = await _rootCandidates(atSign);
    if (candidates.isEmpty) {
      return ChainResult(
          ChainVerdict.broken,
          path,
          'enrollment $enrollmentId claims a root link but $atSign publishes '
          'no signing root to check it against');
    }
    final payload = link['payload'];
    if (payload is! Map ||
        payload['childEnrollmentId'] != enrollmentId ||
        payload['apkamPublicKey'] !=
            await _publishedKey(atSign, enrollmentId)) {
      return ChainResult(
          ChainVerdict.broken,
          path,
          'the root link on $enrollmentId does not describe that '
          "enrollment's published key");
    }
    final bool ok;
    try {
      ok = await _verifiesUnderAny(
        Uint8List.fromList(utf8.encode(signableTextOf(payload))),
        link['signature'] as String,
        candidates,
      );
    } catch (e) {
      return ChainResult(ChainVerdict.broken, path,
          'the root link on $enrollmentId could not be checked: $e');
    }
    return ok
        ? ChainResult(ChainVerdict.anchored, path, null)
        : ChainResult(
            ChainVerdict.broken,
            path,
            'the root link on $enrollmentId does not verify against the '
            "atSign's signing root");
  }

  Future<String?> _publishedKey(String atSign, String enrollmentId) async {
    try {
      final value = await _atClient.get(
        AtKey.fromString(apskUri(atSign, enrollmentId)),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      return value.value as String?;
    } catch (e) {
      return null;
    }
  }

  /// Every root the record advertises that this build can check a signature
  /// with — active first, then retired.
  ///
  /// **Retired entries are candidates.** A root link is verified long after it
  /// was signed, and the whole point of keeping a retired entry advertised is
  /// that what it signed goes on verifying. Checking only the active entry
  /// would turn every superseded link into `broken` — reported as tampering —
  /// the moment a successor appeared.
  ///
  /// Empty for absent and unreadable alike: verification wants one answer,
  /// "nothing to check against", and the distinction matters only to code that
  /// mints or retires on it.
  Future<List<ApskSigningKey>> _rootCandidates(String atSign) async {
    try {
      return await PqSigningRoot.publishedRoots(_atClient, atSign);
    } catch (e) {
      _logger.info('No readable signing root for $atSign: $e');
      return const [];
    }
  }

  /// Whether [signature] over [signable] verifies under any of [candidates].
  ///
  /// An entry whose algorithm this build has no verifier for is **skipped**,
  /// not failed: `PqSigningRoot.verifierFor` is the one place
  /// `verifiableRootAlgos` becomes code, and a record may legitimately carry a
  /// root a client predating that algorithm cannot check.
  static Future<bool> _verifiesUnderAny(
    Uint8List signable,
    String signature,
    Iterable<ApskSigningKey> candidates,
  ) async {
    final bytes = base64Decode(signature);
    for (final candidate in candidates) {
      final algo = PqSigningRoot.verifierFor(candidate.alg);
      if (algo == null) continue;
      if (await algo.verifyBytes(signable,
          signature: bytes, publicKey: base64Decode(candidate.pub))) {
        return true;
      }
    }
    return false;
  }

  /// Decodes a link that arrived over the substrate as a [Secret] value.
  static Map<String, Object?> decodeConveyedLink(String secretValue) =>
      (jsonDecode(secretValue) as Map).cast<String, Object?>();

  /// Encodes a link for conveyance as a [Secret] value.
  static String encodeLink(Map<String, Object?> link) => jsonEncode(link);
}
