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
    show EnvelopeType, SignedEnvelope, signableTextOf;
import 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart'
    show AtClientSecretSharing;
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show PairwiseSecretSharing;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

/// How far up the approval chain a verifier got.
///
/// Graded rather than boolean because a bare `_apsk` is tolerated during the
/// changeover, and a caller has to be able to tell that apart from a chain
/// that failed.
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
  /// Distinct from [chained]: an absent link means nobody has vouched yet, a
  /// bad one means something claimed to and the claim does not hold.
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

/// The approval chain: every enrollment's published `_apsk` value is signed
/// by the enrollment that approved it, up to the atSign's signing root.
///
/// The parent signs and the child publishes, because `_apsk` writes are
/// restricted to the owning enrollment's own authenticated connection: the
/// approver conveys the link over the substrate, and until the child stamps
/// it onto its own record verifiers see a bare key.
@experimental
class PqSigningChain {
  /// One chain view per client; the wire vocabulary stays static because it
  /// belongs to the protocol rather than to any client.
  PqSigningChain(this._atClient)
      : _logger =
            AtSignLogger('PqSigningChain (${_atClient.getCurrentAtSign()})');

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
  /// Its own field, not a variant of [linkField]: a root link is ML-DSA-65
  /// verified against `public:pq_signing_root@<atSign>` where a chain link is
  /// RSA verified against an `_apsk`, so the field name settles which of the
  /// two a verifier is holding before it reads anything else.
  static const String rootLinkField = 'apskRootLink';

  /// Reserved [Secret] name for a conveyed **root** link.
  ///
  /// Which flavour arrived decides which validation runs and which field is
  /// stamped, and the name settles that before anything is decoded.
  static const String rootLinkSecretName =
      '${PairwiseSecretSharing.perEnrollmentSecretPrefix}apskRootLink';

  /// Signature algorithm marker on a root link — the same `mldsa65` the root
  /// record and the keyfile use.
  ///
  /// Write-only: both root-link verifiers dispatch through
  /// `PqSigningRoot.verifierFor` on the algorithm of the *advertised entry*
  /// they are checking against, not on this field.
  static const String rootLinkAlgo = 'mldsa65';

  /// Top-level field naming the advertised root entry that signed the link.
  ///
  /// It sits beside `alg` and never inside `payload`, which is the signed
  /// region shared verbatim with the chain link ([linkPayload]), and it is
  /// omitted rather than null or empty when the signer cannot name its own
  /// key.
  static const String rootLinkKidField = 'kid';

  /// The domain tag a root link's signature covers, ahead of the payload.
  ///
  /// A prefix on the signed bytes rather than a field in `payload`, which is
  /// shared verbatim with the chain link ([linkPayload]), so a root link's
  /// signature is bytes no other thing this build signs can produce. Frozen,
  /// and pinned in `test/wire_literal_pins_test.dart`.
  static const String rootLinkDomain = 'at-root-link:';

  /// The exact bytes a root link's signature covers, for the signer and both
  /// verifiers alike.
  static Uint8List rootLinkSignableBytes(Map<String, Object?> payload) =>
      Uint8List.fromList(
          utf8.encode('$rootLinkDomain${signableTextOf(payload)}'));

  /// `public:_apsk.<enrollmentId>.a.__e@<atSign>` — where an enrollment's
  /// signing advertisement lives, and the one record its own connection may
  /// write.
  static String apskUri(String atSign, String enrollmentId) =>
      envelope_signature.apskUri(atSign, enrollmentId);

  /// The payload a parent signs to vouch for [childEnrollmentId], binding the
  /// enrollment id in alongside the key so the signature cannot be replayed
  /// onto another enrollment's record.
  ///
  /// ⚠️ `apkamPublicKey` is a misleading name — the field carries the child's
  /// whole `_apsk` record value — and it cannot be corrected, because it is a
  /// member of the signed preimage and renaming it changes what verifies.
  static Map<String, Object?> linkPayload({
    required String childEnrollmentId,
    required String childApkamPublicKey,
  }) =>
      {
        'v': 1,
        'childEnrollmentId': childEnrollmentId,
        'apkamPublicKey': childApkamPublicKey,
      };

  /// Signs a link vouching for [childEnrollmentId], over the child's published
  /// `_apsk` value rather than the enrollment request, for the approver to
  /// convey.
  ///
  /// Returns null when that value is not readable, leaving the enrollment
  /// unsigned rather than failing the approval.
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

    return await signer.wrapAndSign(
      linkPayload(
        childEnrollmentId: childEnrollmentId,
        childApkamPublicKey: childKey,
      ),
      type: EnvelopeType.chainLink,
    );
  }

  /// Signs a **root** link vouching for [childEnrollmentId], over the child's
  /// key as the atServer published it, anchoring that enrollment to the
  /// signing root in one hop for a fully privileged client to convey.
  ///
  /// Returns null when the child's `_apsk` is not readable; [rootKid] names
  /// the advertised root entry [rootPrivate] is, and must name the key that
  /// actually signed rather than whichever the record advertises.
  Future<Map<String, Object?>?> signRootLinkFor(
    String childEnrollmentId, {
    required Uint8List rootPrivate,
    String? rootKid,
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
      kid: rootKid,
    );
  }

  /// The published root-link shape over [payload].
  static Future<Map<String, Object?>> _rootLinkOver(
    Map<String, Object?> payload,
    Uint8List rootPrivate, {
    String? kid,
  }) async {
    final signature = await MlDsa65PureDartAlgo().signBytes(
      rootLinkSignableBytes(payload),
      secretKey: rootPrivate,
    );
    return {
      'v': 1,
      'alg': rootLinkAlgo,
      if (kid != null && kid.isNotEmpty) rootLinkKidField: kid,
      'payload': payload,
      'signature': base64Encode(signature),
    };
  }

  /// Stamps a conveyed [link] onto this enrollment's own `_apsk`, rewriting
  /// the record with its value unchanged and the link added to
  /// `appMetadata.additional`.
  ///
  /// A caller that has already read the record passes it as [current], so its
  /// checks and this write come from one snapshot.
  Future<void> publishLink(
    String enrollmentId,
    SignedEnvelope link, {
    AtValue? current,
  }) async {
    final signer = link.signerEnrollmentId;
    await _publishInto(enrollmentId, linkField, link.toJson(),
        current: current);
    _logger.info('Published chain link for $enrollmentId, signed by enrollment '
        '$signer');
  }

  /// Adds [value] under [field] in this enrollment's `_apsk` `appMetadata`,
  /// leaving the record's value and any other field alone.
  ///
  /// A put replaces the record, so its current state is re-sent: [current]
  /// when the caller has already read it, so its checks and this write come
  /// from one snapshot, else a read here.
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
  /// An absent link is ordinary, so this reports absence rather than failing.
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
  static Map<String, Object?>? _fieldFrom(AtValue value, String field) {
    final link = value.metadata?.appMetadata?.additional?[field];
    if (link is Map) return link.cast<String, Object?>();
    return null;
  }

  /// Signs and publishes this enrollment's **root** link if it is entitled to
  /// one and does not already have it, returning whether it published.
  ///
  /// [isFullyPrivileged] is required rather than inferred from holding the
  /// root private, so the invariant that only a fully privileged enrollment
  /// carries a root link holds even if the two ever diverge.
  Future<bool> publishOwnRootLink({
    required Future<bool> Function() isFullyPrivileged,
    AtKeysIo? keysIo,
  }) async {
    final atSign = _atClient.getCurrentAtSign()!;
    final enrollmentId =
        AtClientSecretSharing.forClient(_atClient).enrollmentId;

    final signer =
        await PqSigningRoot(_atClient, keysIo: keysIo).signingKey(atSign);
    if (signer == null) return false;

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

    final existing = _fieldFrom(current, rootLinkField);
    if (existing != null &&
        await _rootLinkStillHolds(atSign, enrollmentId, existing, current)) {
      return false;
    }
    if (existing != null) {
      _logger.warning('The root link on $enrollmentId no longer holds, so this '
          'enrollment is re-anchoring itself');
    }

    final link = await _rootLinkOver(
      linkPayload(
        childEnrollmentId: enrollmentId,
        childApkamPublicKey: current.value as String,
      ),
      signer.private,
      kid: signer.kid,
    );

    await _publishInto(enrollmentId, rootLinkField, link, current: current);
    _logger.info('Anchored $enrollmentId to the signing root');
    return true;
  }

  /// Whether the root link already on this enrollment's record is one a
  /// verifier can still follow: it describes the key [current] publishes, and
  /// its signature checks out under a root the atSign still advertises.
  ///
  /// Only a definite failure answers false; an unreadable root record answers
  /// true, since that is a fact about the read rather than about the link.
  Future<bool> _rootLinkStillHolds(
    String atSign,
    String enrollmentId,
    Map<String, Object?> link,
    AtValue current,
  ) async {
    final payload = link['payload'];
    if (payload is! Map ||
        payload['childEnrollmentId'] != enrollmentId ||
        payload['apkamPublicKey'] != current.value) {
      return false;
    }

    final candidates = await _rootCandidates(atSign);
    if (candidates.isEmpty) return true;

    try {
      return await _verifiesUnderAny(
        rootLinkSignableBytes(payload.cast<String, Object?>()),
        link['signature'] as String,
        _narrowedTo(link, candidates),
      );
    } catch (e) {
      _logger.info('Could not check the root link already on $enrollmentId, so '
          'leaving it alone: $e');
      return true;
    }
  }

  /// The root link an enrollment has published, or null if it has none.
  Future<Map<String, Object?>?> readRootLink(
    String enrollmentId,
  ) async =>
      _readField(enrollmentId, rootLinkField);

  /// Publishes the links this enrollment was conveyed — a root link, a chain
  /// link, or both — if any is waiting and its key does not already carry it,
  /// returning whether anything was published.
  ///
  /// A link that arrives *after* this runs is stamped at the next start rather
  /// than immediately; until it lands the enrollment is simply unsigned.
  Future<bool> publishPendingLink() async {
    final rootPublished = await _publishPendingRootLink();
    final chainPublished = await _publishPendingChainLink();
    return rootPublished || chainPublished;
  }

  /// Stamps a conveyed **root** link, after verifying it the way a downstream
  /// verifier will.
  ///
  /// The conveyance channel authenticates the *sender*, and the sender is not
  /// the root, so the link is verified against the published signing root
  /// before it is stamped, plus the same two checks every link gets: it names
  /// **this** enrollment, and it vouches for the key actually published.
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
        rootLinkSignableBytes(payload.cast<String, Object?>()),
        link['signature'] as String,
        _narrowedTo(link, candidates),
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
  /// Refused unless all three hold: the link names **this** enrollment, it
  /// verifies against the parent it names, and it vouches for the key actually
  /// published.
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
      await sharing.verifyEnvelopeSignature(link,
          signerAtSign: atSign, expecting: EnvelopeType.chainLink);
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
  /// Whole rather than by a signature member, because this serves both link
  /// flavours: a chain link's signature lives inside its `signatures` array,
  /// where a top-level `['signature']` comparison reads null on both sides and
  /// silently makes every existing link match every new one.
  static bool _sameLink(Map<String, Object?> a, Map<String, Object?> b) =>
      const DeepCollectionEquality().equals(a, b);

  /// Walks upward from [enrollmentId] — stopping at a root link verified
  /// against `public:pq_signing_root@<atSign>`, else following chain links
  /// from parent to parent — and reports how far the chain holds.
  ///
  /// A cycle, or a chain longer than [maxDepth], ends the walk as
  /// [ChainVerdict.broken] rather than as merely unanchored.
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

      final failure = await _checkChainLink(verifier, atSign, current, link);
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
      await verifier.verifyEnvelopeSignature(link,
          signerAtSign: atSign, expecting: EnvelopeType.chainLink);
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
        rootLinkSignableBytes(payload.cast<String, Object?>()),
        link['signature'] as String,
        _narrowedTo(link, candidates),
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
  /// with — active first, then retired, since a root link is checked long
  /// after it was signed.
  ///
  /// An entry whose status this build does not understand is not a candidate,
  /// which is the fail-closed answer, and the list is empty for absent and
  /// unreadable alike.
  Future<List<ApskSigningKey>> _rootCandidates(String atSign) async {
    try {
      final roots = await PqSigningRoot.publishedRoots(_atClient, atSign);
      return roots.where((r) => r.vouchesForPastOperations).toList();
    } catch (e) {
      _logger.info('No readable signing root for $atSign: $e');
      return const [];
    }
  }

  /// The candidates a link narrows itself to.
  ///
  /// A [rootLinkKidField] names the key that signed the link, so only that
  /// entry is tried and an unmatched kid narrows to nothing rather than
  /// falling back to trying everything; a link with no kid is tried against
  /// every candidate.
  static Iterable<ApskSigningKey> _narrowedTo(
    Map<String, Object?> link,
    Iterable<ApskSigningKey> candidates,
  ) {
    final kid = link[rootLinkKidField];
    if (kid is! String || kid.isEmpty) return candidates;
    return candidates.where((c) => c.kid == kid);
  }

  /// Whether [signature] over [signable] verifies under any of [candidates].
  ///
  /// An entry whose algorithm this build has no verifier for is skipped, not
  /// failed: a record may legitimately carry a root that a client predating
  /// that algorithm cannot check.
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
