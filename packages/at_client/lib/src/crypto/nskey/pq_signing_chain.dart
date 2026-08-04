import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:at_client/at_client.dart';
import 'package:at_auth/at_auth.dart' show AtKeysIo;
import 'package:at_chops/at_chops.dart' show MlDsa65PureDartAlgo;
import 'package:at_client/at_client_mixins.dart' show EnvelopeSigning;
import 'package:at_client/src/signing/envelope_signature.dart'
    show signableTextOf;
import 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart'
    show AtClientSecretSharing;
import 'package:at_client/src/secret_sharing/pairwise_secret_sharing.dart'
    show PairwiseSecretSharing;
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:meta/meta.dart' show experimental;

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
/// [decisions.md 22.2b]: ../../../../../docs/projects/pq/decisions.md
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

@experimental
class PqSigningChain {
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

  /// Signature algorithm marker on a root link.
  static const String rootLinkAlgo = 'mldsa65';

  static final AtSignLogger _logger = AtSignLogger('PqSigningChain');

  /// `public:_apsk.<enrollmentId>.a.__e@<atSign>` — where an enrollment's
  /// APKAM public key lives, and the one record its own connection may write.
  static String apskUri(String atSign, String enrollmentId) => 'public:'
      '_apsk.$enrollmentId.${EnrollmentConstants.perEnrollmentApproved}'
      '$atSign';

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
  static Future<Map<String, Object?>?> signLinkFor(
    AtClient atClient,
    EnvelopeSigning signer,
    String childEnrollmentId,
  ) async {
    final atSign = atClient.getCurrentAtSign()!;
    final String childKey;
    try {
      final value = await atClient.get(
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

  /// Stamps a conveyed [link] onto this enrollment's own `_apsk`.
  ///
  /// Rewrites the record with its value unchanged and the link added to
  /// `appMetadata.additional`. The value has to be re-sent because a put
  /// replaces the record; re-reading it first means the key published is the
  /// one already there rather than one this client believes it should be.
  ///
  /// The provider id is the legacy one, which is accurate rather than a
  /// placeholder: `_apsk` is a public plaintext key and no provider encrypts
  /// it. Only `additional` carries anything new.
  static Future<void> publishLink(
    AtClient atClient,
    String enrollmentId,
    Map<String, Object?> link,
  ) async {
    await _publishInto(atClient, enrollmentId, linkField, link);
    _logger.info('Published chain link for $enrollmentId, signed by enrollment '
        '${link['enrollmentId']}');
  }

  /// Adds [value] under [field] in this enrollment's `_apsk` `appMetadata`,
  /// leaving the record's value and any other field alone.
  ///
  /// The value is re-read and re-sent because a put replaces the record;
  /// sending back what is already there means the key published stays the one
  /// every verifier resolves rather than one this client believes it should be.
  ///
  /// Existing `additional` entries are carried forward, so the chain link and
  /// the root link coexist on the same record instead of overwriting each
  /// other.
  static Future<void> _publishInto(
    AtClient atClient,
    String enrollmentId,
    String field,
    Map<String, Object?> value,
  ) async {
    final atSign = atClient.getCurrentAtSign()!;
    final uri = apskUri(atSign, enrollmentId);

    final AtValue current = await atClient.get(
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

    await atClient.put(
      atKey,
      current.value,
      putRequestOptions: PutRequestOptions()..useRemoteAtServer = true,
    );
  }

  /// The chain link an enrollment has published, or null if it has none.
  ///
  /// An absent link is ordinary — the enrollment has not run since approval,
  /// or predates the chain — so this reports absence rather than failing.
  static Future<Map<String, Object?>?> readLink(
    AtClient atClient,
    String enrollmentId,
  ) async =>
      _readField(atClient, enrollmentId, linkField);

  static Future<Map<String, Object?>?> _readField(
    AtClient atClient,
    String enrollmentId,
    String field,
  ) async {
    final atSign = atClient.getCurrentAtSign()!;
    try {
      final value = await atClient.get(
        AtKey.fromString(apskUri(atSign, enrollmentId)),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      final link = value.metadata?.appMetadata?.additional?[field];
      if (link is Map) return link.cast<String, Object?>();
      return null;
    } catch (e) {
      _logger.info('No _apsk readable for enrollment $enrollmentId: $e');
      return null;
    }
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
  static Future<bool> publishOwnRootLink(
    AtClient atClient, {
    required Future<bool> Function() isFullyPrivileged,
    AtKeysIo? keysIo,
  }) async {
    final atSign = atClient.getCurrentAtSign()!;
    final enrollmentId = AtClientSecretSharing.forClient(atClient).enrollmentId;

    // Possession is checked first because it is a local `AtKeys` read, where
    // establishing privilege costs a round trip. An enrollment holding no root
    // private cannot anchor itself whatever its privileges, so the cheap gate
    // is also the one that eliminates almost every client at start.
    final private =
        await PqSigningRoot(atClient, keysIo: keysIo).privateHalf(atSign);
    if (private == null) return false;

    if (!await isFullyPrivileged()) {
      _logger.warning('This enrollment holds the signing root private but is '
          'not fully privileged, so it is not anchoring itself. The two should '
          'never diverge; that they have is worth investigating.');
      return false;
    }

    final AtValue current;
    try {
      current = await atClient.get(
        AtKey.fromString(apskUri(atSign, enrollmentId)),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
    } catch (e) {
      _logger.info('No _apsk published for $enrollmentId yet, so there is '
          'nothing to anchor: $e');
      return false;
    }

    final existing = await readRootLink(atClient, enrollmentId);
    if (existing != null) return false;

    final payload = linkPayload(
      childEnrollmentId: enrollmentId,
      childApkamPublicKey: current.value as String,
    );
    final signature = await MlDsa65PureDartAlgo().signBytes(
      Uint8List.fromList(utf8.encode(signableTextOf(payload))),
      secretKey: private,
    );

    await _publishInto(atClient, enrollmentId, rootLinkField, {
      'v': 1,
      'alg': rootLinkAlgo,
      'payload': payload,
      'signature': base64Encode(signature),
    });
    _logger.info('Anchored $enrollmentId to the signing root');
    return true;
  }

  /// The root link an enrollment has published, or null if it has none.
  static Future<Map<String, Object?>?> readRootLink(
    AtClient atClient,
    String enrollmentId,
  ) async =>
      _readField(atClient, enrollmentId, rootLinkField);

  /// Publishes the chain link this enrollment was conveyed, if one is waiting
  /// and its key does not already carry it. Returns whether it published.
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
  static Future<bool> publishPendingLink(AtClient atClient) async {
    final sharing = AtClientSecretSharing.forClient(atClient);
    final atSign = atClient.getCurrentAtSign()!;
    final enrollmentId = sharing.enrollmentId;

    final secret = sharing.secretStore
        .listSecrets()
        .where((s) => s.name == linkSecretName)
        .firstOrNull;
    if (secret == null) return false;

    final Map<String, Object?> link;
    final Map payload;
    try {
      link = decodeConveyedLink(secret.value);
      payload = link['payload'] as Map;
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
      current = await atClient.get(
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

    final existing = await readLink(atClient, enrollmentId);
    if (existing != null && existing['signature'] == link['signature']) {
      return false;
    }

    await publishLink(atClient, enrollmentId, link);
    return true;
  }

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
  static Future<ChainResult> verifyChain(
    AtClient atClient,
    EnvelopeSigning verifier,
    String enrollmentId, {
    int maxDepth = 16,
  }) async {
    final atSign = atClient.getCurrentAtSign()!;
    final path = <String>[];
    final seen = <String>{};
    String current = enrollmentId;

    while (true) {
      if (!seen.add(current)) {
        return ChainResult(ChainVerdict.broken, path,
            'the chain revisits enrollment $current, so it does not terminate');
      }
      path.add(current);

      final rootLink = await readRootLink(atClient, current);
      if (rootLink != null) {
        return await _checkRootLink(atClient, atSign, current, rootLink, path);
      }

      final link = await readLink(atClient, current);
      if (link == null) {
        return ChainResult(
            path.length == 1 ? ChainVerdict.unsigned : ChainVerdict.chained,
            path,
            'enrollment $current publishes no link, so the walk stops below '
            'the root');
      }

      final failure =
          await _checkChainLink(atClient, verifier, atSign, current, link);
      if (failure != null) {
        return ChainResult(ChainVerdict.broken, path, failure);
      }

      final parent = link['enrollmentId'];
      if (parent is! String || parent.isEmpty) {
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
  static Future<String?> _checkChainLink(
    AtClient atClient,
    EnvelopeSigning verifier,
    String atSign,
    String enrollmentId,
    Map<String, Object?> link,
  ) async {
    try {
      await verifier.verifyEnvelopeSignature(link, signerAtSign: atSign);
    } catch (e) {
      return 'the link on $enrollmentId does not verify against the '
          'enrollment it names as signer: $e';
    }
    final payload = link['payload'];
    if (payload is! Map) return 'the link on $enrollmentId has no payload';
    if (payload['childEnrollmentId'] != enrollmentId) {
      return 'the link on $enrollmentId vouches for '
          '${payload['childEnrollmentId']} instead';
    }
    // The signature proves the parent said something; this proves it said it
    // about the key actually published. Without it a genuine link could sit
    // over a key it never covered.
    final published = await _publishedKey(atClient, atSign, enrollmentId);
    if (published != payload['apkamPublicKey']) {
      return 'the link on $enrollmentId vouches for a key other than the one '
          'published for it';
    }
    return null;
  }

  static Future<ChainResult> _checkRootLink(
    AtClient atClient,
    String atSign,
    String enrollmentId,
    Map<String, Object?> link,
    List<String> path,
  ) async {
    final rootKey = await _rootPublicKey(atClient, atSign);
    if (rootKey == null) {
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
            await _publishedKey(atClient, atSign, enrollmentId)) {
      return ChainResult(
          ChainVerdict.broken,
          path,
          'the root link on $enrollmentId does not describe that '
          "enrollment's published key");
    }
    final bool ok;
    try {
      ok = await MlDsa65PureDartAlgo().verifyBytes(
        Uint8List.fromList(utf8.encode(signableTextOf(payload))),
        signature: base64Decode(link['signature'] as String),
        publicKey: rootKey,
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

  static Future<String?> _publishedKey(
      AtClient atClient, String atSign, String enrollmentId) async {
    try {
      final value = await atClient.get(
        AtKey.fromString(apskUri(atSign, enrollmentId)),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      return value.value as String?;
    } catch (e) {
      return null;
    }
  }

  static Future<Uint8List?> _rootPublicKey(
      AtClient atClient, String atSign) async {
    try {
      final value = await atClient.get(
        AtKey.fromString('public:${PqSigningRoot.recordName}$atSign'),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
      final record = jsonDecode(value.value as String) as Map;
      return base64Decode((record['keys'] as List).first as String);
    } catch (e) {
      _logger.info('No readable signing root for $atSign: $e');
      return null;
    }
  }

  /// Decodes a link that arrived over the substrate as a [Secret] value.
  static Map<String, Object?> decodeConveyedLink(String secretValue) =>
      (jsonDecode(secretValue) as Map).cast<String, Object?>();

  /// Encodes a link for conveyance as a [Secret] value.
  static String encodeLink(Map<String, Object?> link) => jsonEncode(link);
}
