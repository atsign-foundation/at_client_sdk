import 'dart:convert';
import 'dart:typed_data' show Uint8List;

import 'package:at_auth/at_auth.dart'
    show ApskSigningKey, AtKeysIo, apskSigningKeys, publicKeyKidOfBase64;
import 'package:at_chops/at_chops.dart'
    show MlDsa65PureDartAlgo, SigningAlgoType;
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/crypto/nskey/pq_signing_root.dart'
    show PqSigningRoot;
import 'package:at_client/src/mixins/apkam_signing.dart'
    show rememberOwnLinkedKids;
import 'package:at_client/src/mixins/envelope_signing.dart'
    show EnvelopeSigning, WithdrawnSigningKeyException, withdrawnApskLocation;
import 'package:at_client/src/signing/envelope_signature.dart'
    as envelope_signature show apskUri;
import 'package:at_client/src/signing/envelope_signature.dart'
    show
        ApkamSigningKeys,
        EnvelopeType,
        SignedEnvelope,
        signEnvelope,
        signableTextOf,
        signsUnder;
import 'package:at_commons/at_builders.dart' show EnrollVerbBuilder;
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart' show AtSignLogger;
import 'package:collection/collection.dart' show DeepCollectionEquality;
import 'package:meta/meta.dart' show experimental;

/// How far up the chain a walk from one key got.
@experimental
enum ChainVerdict {
  /// Reached a root link that verifies against the atSign's signing root.
  anchored,

  /// Every link walked verified, but a key on the way carries none, so the
  /// walk stopped below the root.
  chained,

  /// The key the walk started from carries no link.
  unsigned,

  /// A link was present and wrong: a failed signature, a link naming another
  /// key, a cycle, or a chain too long to walk.
  ///
  /// Distinct from [unsigned]: an absent link means nobody has vouched yet, a
  /// bad one means something claimed to and the claim does not hold.
  broken,

  /// A key the walk depends on belongs to an enrollment that was revoked or
  /// superseded: the atServer moved its `_apsk` to `.r.__e`.
  revoked,

  /// A key the walk depends on belongs to an enrollment that was deleted or
  /// expired: the atServer moved its `_apsk` to `.d.__e`.
  deleted,
}

/// What a walk found.
@experimental
class ChainResult {
  final ChainVerdict verdict;

  /// The enrollments walked, starting with the one asked about.
  final List<String> path;

  /// Why the walk stopped, when that is not self-evident.
  final String? reason;

  /// The key the verdict is about: the one the walk started from, or the key
  /// that failed when the verdict is an enrollment's. Null when no key was
  /// walked.
  final String? kid;

  /// The keys walked, as `<enrollmentId>/<kid>`, in order.
  final List<String> keysWalked;

  ChainResult(this.verdict, this.path, this.reason,
      {this.kid, this.keysWalked = const []});

  /// How an approver's view shows this result: `anchored`, `unsigned`, or
  /// the verdict, followed by the [kid] it is about when there is one.
  String get summary => switch (verdict) {
        ChainVerdict.anchored => 'anchored',
        ChainVerdict.unsigned => 'unsigned',
        _ => kid == null ? verdict.name : '${verdict.name} $kid',
      };

  @override
  String toString() => 'ChainResult(${verdict.name}, path: $path'
      '${kid == null ? '' : ', kid: $kid'}'
      '${reason == null ? '' : ', $reason'})';
}

/// One enrollment's `_apsk` record as a walk or a voucher reads it: the keys
/// it lists and the links stored on it.
@experimental
class ApskRecord {
  /// The enrollment the record belongs to.
  final String enrollmentId;

  /// The record's value, verbatim.
  final String value;

  /// Every listed key this build can read and whose status still vouches for
  /// what it signed, in listed order. A bare value is one `rsa2048` key.
  final List<ApskSigningKey> keys;

  /// The links stored on the record, keyed by the `kid` each vouches for.
  final Map<String, Map<String, Object?>> links;

  ApskRecord(this.enrollmentId, this.value, this.keys, this.links);

  /// Reads [value] and the link map in [appMetadata] for [enrollmentId].
  factory ApskRecord.parse(
      String enrollmentId, String value, AppMetadata? appMetadata) {
    final stored = appMetadata?.additional?[PqSigningChain.linksField];
    return ApskRecord(enrollmentId, value, _keysOf(value), {
      if (stored is Map)
        for (final entry in stored.entries)
          if (entry.key is String && entry.value is Map)
            entry.key as String: (entry.value as Map).cast<String, Object?>()
    });
  }

  static List<ApskSigningKey> _keysOf(String value) {
    if (!value.trimLeft().startsWith('{')) {
      try {
        return [
          ApskSigningKey(
              kid: publicKeyKidOfBase64(value),
              alg: SigningAlgoType.rsa2048,
              pub: value)
        ];
      } on FormatException {
        return const [];
      }
    }
    try {
      final decoded = jsonDecode(value);
      if (decoded is! Map<String, dynamic>) return const [];
      return apskSigningKeys(decoded)
          .where((k) => k.vouchesForPastOperations)
          .toList();
    } on FormatException {
      return const [];
    }
  }
}

/// A link this client has signed for one key, with the link it found on that
/// key when it read the record, or null when it found none.
typedef LinkWrite = ({Map<String, Object?> link, Map<String, Object?>? expect});

/// What a client vouches for another key with: the signing root's private
/// key, or one of its own keys that already has a link.
@experimental
class LinkVoucher {
  /// A voucher signing root links with the root private named by [kid].
  LinkVoucher.root({required Uint8List private, required String kid})
      : _rootPrivate = private,
        _rootKid = kid,
        _key = null,
        _enrollmentId = null,
        keysWalked = const [];

  /// A voucher signing chain links with [key], which [enrollmentId] lists and
  /// which walks to the root through [keysWalked].
  LinkVoucher.chain(
      {required ApkamSigningKeys key,
      required String enrollmentId,
      required this.keysWalked})
      : _key = key,
        _enrollmentId = enrollmentId,
        _rootPrivate = null,
        _rootKid = null;

  final Uint8List? _rootPrivate;
  final String? _rootKid;
  final ApkamSigningKeys? _key;
  final String? _enrollmentId;

  /// The keys this voucher's own key chains through, as
  /// `<enrollmentId>/<kid>`; empty for a root voucher.
  final List<String> keysWalked;

  /// Whether this voucher signs root links.
  bool get isRoot => _rootPrivate != null;

  /// A link over [payload], signed as this voucher signs.
  Future<Map<String, Object?>> sign(Map<String, Object?> payload) async {
    final rootPrivate = _rootPrivate;
    if (rootPrivate != null) {
      return PqSigningChain.signRootLink(payload,
          rootPrivate: rootPrivate, rootKid: _rootKid!);
    }
    return PqSigningChain.signChainLink(payload,
        key: _key!, signerEnrollmentId: _enrollmentId!);
  }
}

/// The links that vouch for each key an enrollment's `_apsk` lists, and the
/// walk from a key up to the atSign's signing root.
///
/// A link names one key, `{v: 2, enrollmentId, kid, alg, pub}`, and the `kid`
/// of the key that signed it. When that `kid` is a key of the signing root it
/// is a root link, checked against that key only; otherwise it is a chain link
/// signed by a key of another enrollment, and the walk goes on from that key.
/// Links are stored in the record's `appMetadata` under [linksField], and
/// written only through `enroll:link`.
@experimental
class PqSigningChain {
  /// One chain view per client; the wire vocabulary stays static because it
  /// belongs to the protocol rather than to any client.
  PqSigningChain(this._atClient)
      : _logger =
            AtSignLogger('PqSigningChain (${_atClient.getCurrentAtSign()})');

  final AtClient _atClient;
  final AtSignLogger _logger;

  /// The `appMetadata.additional` field holding an `_apsk` record's links,
  /// keyed by the `kid` each vouches for.
  static const String linksField = 'apskLinks';

  /// The version of the link payload.
  static const int linkVersion = 2;

  /// Signature algorithm marker on a root link: the same `mldsa65` the root
  /// record and the keyfile use.
  static const String rootLinkAlgo = 'mldsa65';

  /// Top-level field of a root link naming the root key that signed it.
  static const String rootLinkKidField = 'kid';

  /// The domain tag a root link's signature covers, ahead of the payload, so a
  /// root link's signature is bytes no other thing this build signs can
  /// produce. Frozen, and pinned in `test/wire_literal_pins_test.dart`.
  static const String rootLinkDomain = 'at-root-link:';

  /// The longest walk, in keys, before a chain reads [ChainVerdict.broken].
  static const int maxDepth = 16;

  /// The exact bytes a root link's signature covers.
  static Uint8List rootLinkSignableBytes(Map<String, Object?> payload) =>
      Uint8List.fromList(
          utf8.encode('$rootLinkDomain${signableTextOf(payload)}'));

  /// `public:_apsk.<enrollmentId>.a.__e@<atSign>`.
  static String apskUri(String atSign, String enrollmentId) =>
      envelope_signature.apskUri(atSign, enrollmentId);

  /// The payload a link signs to vouch that [key] belongs to [enrollmentId].
  static Map<String, Object?> linkPayload(
          String enrollmentId, ApskSigningKey key) =>
      {
        'v': linkVersion,
        'enrollmentId': enrollmentId,
        'kid': key.kid,
        'alg': key.alg.name,
        'pub': key.pub,
      };

  /// A root link over [payload], signed with [rootPrivate], the root key
  /// [rootKid] names.
  static Future<Map<String, Object?>> signRootLink(
    Map<String, Object?> payload, {
    required Uint8List rootPrivate,
    required String rootKid,
  }) async {
    final signature = await MlDsa65PureDartAlgo()
        .signBytes(rootLinkSignableBytes(payload), secretKey: rootPrivate);
    return {
      'v': linkVersion,
      'alg': rootLinkAlgo,
      rootLinkKidField: rootKid,
      'payload': payload,
      'signature': base64Encode(signature),
    };
  }

  /// A chain link over [payload], signed with [key] alone, which
  /// [signerEnrollmentId]'s `_apsk` lists.
  static Map<String, Object?> signChainLink(
    Map<String, Object?> payload, {
    required ApkamSigningKeys key,
    required String signerEnrollmentId,
  }) =>
      signEnvelope(payload,
              keys: [key],
              type: EnvelopeType.chainLink,
              enrollmentId: signerEnrollmentId)
          .toJson();

  /// The payload [link] signs, or null when it carries none that reads.
  static Map<String, Object?>? payloadOf(Map<String, Object?> link) {
    final payload = link['payload'];
    if (payload is Map) return payload.cast<String, Object?>();
    try {
      final decoded = SignedEnvelope.fromJson(link).payload;
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } on AtSigningVerificationException {
      return null;
    }
  }

  /// Whether [payload] names [key] as one of [enrollmentId]'s.
  static bool names(Map<String, Object?>? payload, String enrollmentId,
          ApskSigningKey key) =>
      payload != null &&
      payload['v'] == linkVersion &&
      payload['enrollmentId'] == enrollmentId &&
      payload['kid'] == key.kid &&
      payload['alg'] == key.alg.name &&
      payload['pub'] == key.pub;

  String get _atSign => _atClient.getCurrentAtSign()!;

  /// [enrollmentId]'s `_apsk` record, or null when the atServer holds none at
  /// `.a.__e`.
  Future<ApskRecord?> readRecord(String enrollmentId) async {
    final AtValue value;
    try {
      value = await _atClient.get(
        AtKey.fromString(apskUri(_atSign, enrollmentId)),
        getRequestOptions: GetRequestOptions()..useRemoteAtServer = true,
      );
    } on AtKeyNotFoundException {
      return null;
    } on KeyNotFoundException {
      return null;
    }
    final text = value.value;
    if (text is! String) return null;
    return ApskRecord.parse(enrollmentId, text, value.metadata?.appMetadata);
  }

  /// Walks from [key], one of [record]'s keys, up to the signing root.
  ///
  /// Each link is checked against the key it is stored on, `kid`, `alg` and
  /// `pub` alike. A cycle, or a chain longer than [maxDepth] keys, reads
  /// [ChainVerdict.broken].
  Future<ChainResult> walkFrom(
      EnvelopeSigning verifier, ApskRecord record, ApskSigningKey key) async {
    final path = <String>[];
    final walked = <String>[];
    List<ApskSigningKey>? roots;
    var current = record;
    var currentKey = key;

    ChainResult result(ChainVerdict verdict, String? reason) =>
        ChainResult(verdict, List.of(path), reason,
            kid: key.kid, keysWalked: List.of(walked));

    while (true) {
      final at = '${current.enrollmentId}/${currentKey.kid}';
      final where = 'key ${currentKey.kid} of enrollment '
          '${current.enrollmentId}';
      if (walked.contains(at)) {
        return result(ChainVerdict.broken,
            'the chain revisits $where, so it does not terminate');
      }
      if (walked.length >= maxDepth) {
        return result(ChainVerdict.broken,
            'the chain from key ${key.kid} is longer than $maxDepth keys');
      }
      walked.add(at);
      if (path.lastOrNull != current.enrollmentId) {
        path.add(current.enrollmentId);
      }

      final link = current.links[currentKey.kid];
      if (link == null) {
        return result(
            walked.length == 1 ? ChainVerdict.unsigned : ChainVerdict.chained,
            '$where carries no link, so the walk stops below the root');
      }
      if (!names(payloadOf(link), current.enrollmentId, currentKey)) {
        return result(
            ChainVerdict.broken,
            'the link on $where does not name that key: its payload must '
            'carry this enrollment and the kid, alg and pub the record lists');
      }

      final rootShaped = link['payload'] is Map;
      SignedEnvelope? envelope;
      if (!rootShaped) {
        try {
          envelope = SignedEnvelope.fromJson(link);
        } on AtSigningVerificationException catch (e) {
          return result(
              ChainVerdict.broken, 'the link on $where is not a link: $e');
        }
        if (envelope.signatures.length != 1) {
          return result(
              ChainVerdict.broken,
              'the link on $where carries ${envelope.signatures.length} '
              'signatures, and a link carries the one its signer made');
        }
      }
      final signerKid =
          rootShaped ? link[rootLinkKidField] : envelope!.signature.kid;
      if (signerKid is! String || signerKid.isEmpty) {
        return result(
            ChainVerdict.broken, 'the link on $where names no signer key');
      }

      roots ??= await _rootCandidates();
      final root = roots.where((r) => r.kid == signerKid).firstOrNull;
      if (root != null) {
        if (!rootShaped) {
          return result(
              ChainVerdict.broken,
              'the link on $where names root key $signerKid but is not a '
              'root link, so it cannot be checked against that key');
        }
        return await _rootLinkVerifies(link, root)
            ? result(ChainVerdict.anchored, null)
            : result(
                ChainVerdict.broken,
                'the link on $where does not verify against root key '
                '$signerKid');
      }
      if (rootShaped) {
        return result(
            ChainVerdict.broken,
            'the link on $where names key $signerKid, which is no key of the '
            'signing root, and names no signer enrollment');
      }

      final signerId = envelope!.signerEnrollmentId;
      if (signerId == null || signerId.isEmpty) {
        return result(ChainVerdict.broken,
            'the link on $where names no signer enrollment');
      }
      try {
        await verifier.verifyEnvelopeSignature(envelope,
            signerAtSign: _atSign,
            signerEnrollmentId: signerId,
            expecting: EnvelopeType.chainLink);
      } on WithdrawnSigningKeyException catch (e) {
        return result(_verdictFor(e.location),
            'the link on $where was signed by enrollment $signerId: ${e.message}');
      } on AtSigningVerificationException catch (e) {
        return result(
            ChainVerdict.broken,
            'the link on $where does not verify against enrollment '
            '$signerId: ${e.message}');
      } on AtKeyNotFoundException {
        return result(
            ChainVerdict.broken,
            'the link on $where names enrollment $signerId, which publishes no '
            '_apsk');
      } on KeyNotFoundException {
        return result(
            ChainVerdict.broken,
            'the link on $where names enrollment $signerId, which publishes no '
            '_apsk');
      }

      final signerRecord = await readRecord(signerId);
      final signerKey = signerRecord?.keys
          .where((k) =>
              k.kid == signerKid && signsUnder(k.alg, envelope!.signature.alg))
          .firstOrNull;
      if (signerRecord == null || signerKey == null) {
        return result(
            ChainVerdict.broken,
            'the link on $where names key $signerKid of enrollment $signerId, '
            'which that enrollment does not list');
      }
      current = signerRecord;
      currentKey = signerKey;
    }
  }

  /// Whether [enrollmentId] is anchored: every key it signs with walks to the
  /// root.
  ///
  /// The keys it signs with are its active keys that carry a link; with none,
  /// it reads [ChainVerdict.unsigned]. Otherwise the verdict is
  /// [ChainVerdict.anchored], or the first failing key's, naming that key.
  Future<ChainResult> verifyChain(
      EnvelopeSigning verifier, String enrollmentId) async {
    final record = await readRecord(enrollmentId);
    if (record == null) {
      final location =
          await withdrawnApskLocation(_atClient, _atSign, enrollmentId);
      if (location != null) {
        return ChainResult(
            _verdictFor(location),
            [enrollmentId],
            'enrollment $enrollmentId\'s keys are no longer published: the '
            'atServer moved its _apsk to .$location');
      }
      return ChainResult(ChainVerdict.unsigned, [enrollmentId],
          'enrollment $enrollmentId publishes no _apsk');
    }
    final signing = [
      for (final key in record.keys)
        if (key.offeredForNewOperations && record.links.containsKey(key.kid))
          key
    ];
    if (signing.isEmpty) {
      return ChainResult(ChainVerdict.unsigned, [enrollmentId],
          'enrollment $enrollmentId has no active key that carries a link');
    }
    for (final key in signing) {
      final walk = await walkFrom(verifier, record, key);
      if (walk.verdict != ChainVerdict.anchored) return walk;
    }
    return ChainResult(ChainVerdict.anchored, [enrollmentId], null);
  }

  /// What this client vouches with: the signing root when it holds the root's
  /// private key and [isFullyPrivileged] says so, else the strongest of its
  /// own active client data signing keys that walks to the root, else null.
  /// A null [isFullyPrivileged] asks for a chain voucher alone.
  ///
  /// [signer] is this client's own: its keyfile supplies the keys, and an
  /// authentication key is never one of them. [alsoVouchWith] are keys the
  /// caller holds that may vouch although the record already lists them as
  /// retired: a key handing its link on to the key replacing it. The root's
  /// private key is read from [keysIo], else from the client's own.
  Future<LinkVoucher?> voucher(EnvelopeSigning signer,
      {required Future<bool> Function()? isFullyPrivileged,
      List<ApkamSigningKeys> alsoVouchWith = const [],
      AtKeysIo? keysIo}) async {
    final root = isFullyPrivileged == null
        ? null
        : await PqSigningRoot(_atClient, keysIo: keysIo ?? _atClient.atKeysIo)
            .signingKey(_atSign);
    if (root != null) {
      final kid = root.kid;
      if (kid == null) {
        _logger.warning('This client holds the signing root private but no '
            'public half beside it, so it cannot name the root key a root link '
            'is signed with, and signs none');
      } else if (await isFullyPrivileged!()) {
        return LinkVoucher.root(private: root.private, kid: kid);
      } else {
        _logger.warning('This enrollment holds the signing root private but is '
            'not fully privileged, so it signs no root link with it');
      }
    }

    final ownId = _atClient.enrollmentId;
    if (ownId == null) return null;
    final own = await readRecord(ownId);
    if (own == null) return null;
    final handingOn = {for (final key in alsoVouchWith) key.publicKey};
    for (final held in [...await signer.heldSigningKeys, ...alsoVouchWith]) {
      final kid = publicKeyKidOfBase64(held.publicKey);
      final listed = own.keys
          .where((k) =>
              k.kid == kid &&
              k.pub == held.publicKey &&
              k.alg == held.algorithm &&
              (k.offeredForNewOperations || handingOn.contains(k.pub)))
          .firstOrNull;
      if (listed == null || !own.links.containsKey(kid)) continue;
      final walk = await walkFrom(signer, own, listed);
      if (walk.verdict == ChainVerdict.anchored) {
        return LinkVoucher.chain(
            key: held, enrollmentId: ownId, keysWalked: walk.keysWalked);
      }
    }
    return null;
  }

  /// Reads this enrollment's own `_apsk` and records which of its keys have a
  /// link, for content signing to prefer; returns the record, or null when it
  /// has none.
  Future<ApskRecord?> refreshOwnLinks() async {
    final id = _atClient.enrollmentId;
    if (id == null) return null;
    final own = await readRecord(id);
    rememberOwnLinkedKids(_atClient, {...?own?.links.keys});
    return own;
  }

  /// Links this enrollment's own keys with what this client vouches with,
  /// as [linkKeysOf] decides, and returns the `kid`s linked.
  ///
  /// [signer] is this client's own; [alsoVouchWith] and [keysIo] are as
  /// [voucher] takes them.
  Future<List<String>> linkOwnKeys(EnvelopeSigning signer,
      {required Future<bool> Function()? isFullyPrivileged,
      List<ApkamSigningKeys> alsoVouchWith = const [],
      AtKeysIo? keysIo}) async {
    final own = await refreshOwnLinks();
    if (own == null) return const [];
    final by = await voucher(signer,
        isFullyPrivileged: isFullyPrivileged,
        alsoVouchWith: alsoVouchWith,
        keysIo: keysIo);
    if (by == null) return const [];
    final linked = await linkKeysOf(own, by,
        authenticationKey: (await signer.authenticationSigningKey)?.publicKey,
        verifier: signer);
    if (linked.isNotEmpty) await refreshOwnLinks();
    return linked;
  }

  /// Links each of [target]'s keys that [voucher] should, through one
  /// `enroll:link`, and returns the `kid`s the atServer reports linked.
  ///
  /// A key equal to [authenticationKey], the target's APKAM authentication
  /// key, or not spelt in padded standard base64, takes no link. Of the rest,
  /// a key with no link gets one; a root voucher replaces anything but a root
  /// link that passes its check; a chain voucher replaces only a chain link
  /// that does not walk to the root, never a root link, and links no key its
  /// own key's chain passes through. A key is linked only when it is the entry
  /// the atServer reads under its `kid`: the first in the record carrying a
  /// string `kid`, `alg` and `pub`, whatever its status. Each link states the
  /// one it found; when the atServer refuses the call, the record is read
  /// again and, if it has changed, the call made once more on what it now
  /// holds.
  Future<List<String>> linkKeysOf(
    ApskRecord target,
    LinkVoucher voucher, {
    required String? authenticationKey,
    required EnvelopeSigning verifier,
  }) async {
    final signed = <String, Map<String, Object?>>{};
    List<ApskSigningKey>? roots;
    Future<List<ApskSigningKey>> rootsOnce() async =>
        roots ??= await _rootCandidates();
    var record = target;
    for (var attempt = 1; attempt <= 2; attempt++) {
      final writes = <String, LinkWrite>{};
      final read = _readByAtServer(record.value);
      for (final key in record.keys) {
        if (read[key.kid] != key.pub) continue;
        if (!_takesLink(record, key, authenticationKey, voucher)) continue;
        final found = record.links[key.kid];
        if (found != null &&
            !await _replaces(
                voucher, record, key, found, verifier, await rootsOnce())) {
          continue;
        }
        final link = signed[key.kid] ??=
            await voucher.sign(linkPayload(record.enrollmentId, key));
        writes[key.kid] = (link: link, expect: found);
      }
      if (writes.isEmpty) return const [];
      try {
        return await writeLinks(record.enrollmentId, writes);
      } on Exception catch (e) {
        if (e is StoppedException) rethrow;
        final reread =
            attempt == 1 ? await readRecord(record.enrollmentId) : null;
        if (reread == null || _sameRecord(reread, record)) {
          _logger.warning('enroll:link for enrollment ${record.enrollmentId} '
              'was refused, so keys ${writes.keys.join(', ')} have no new '
              'link: $e');
          return const [];
        }
        record = reread;
      }
    }
    return const [];
  }

  /// Sends one `enroll:link` for [enrollmentId] carrying [links], and returns
  /// the `kid`s the atServer reports linked.
  ///
  /// Throws when the atServer refuses the call, and when its answer carries no
  /// `linked` list: only a reply naming what it linked counts as success.
  Future<List<String>> writeLinks(
      String enrollmentId, Map<String, LinkWrite> links) async {
    final builder = EnrollVerbBuilder()
      // ignore: experimental_member_use
      ..operation = EnrollOperationEnum.link
      ..enrollmentId = enrollmentId
      // ignore: experimental_member_use
      ..links = {
        for (final entry in links.entries)
          entry.key: {'link': entry.value.link, 'expect': entry.value.expect}
      };
    final response = await _atClient.getRemoteSecondary()!.executeVerb(builder);
    if (!response.startsWith('data:')) {
      throw AtEnrollmentException(
          'enroll:link for enrollment $enrollmentId was refused: $response');
    }
    final decoded = jsonDecode(response.substring('data:'.length).trim());
    final linked = decoded is Map ? decoded['linked'] : null;
    if (linked is! List) {
      throw AtEnrollmentException('enroll:link for enrollment $enrollmentId '
          'was answered without saying what it linked: $response');
    }
    return [
      for (final kid in linked)
        if (kid is String) kid
    ];
  }

  /// Whether [key] on [record] is one [voucher] may link at all.
  bool _takesLink(ApskRecord record, ApskSigningKey key,
      String? authenticationKey, LinkVoucher voucher) {
    if (!_isCanonical(key.pub)) return false;
    if (authenticationKey != null && sameKey(key.pub, authenticationKey)) {
      return false;
    }
    return !voucher.keysWalked.contains('${record.enrollmentId}/${key.kid}');
  }

  /// Whether [voucher]'s link should replace [found], the link on [key];
  /// [roots] are the signing root's keys.
  Future<bool> _replaces(
      LinkVoucher voucher,
      ApskRecord record,
      ApskSigningKey key,
      Map<String, Object?> found,
      EnvelopeSigning verifier,
      List<ApskSigningKey> roots) async {
    final foundIsRoot = _isRootLink(found, roots);
    if (voucher.isRoot) {
      if (!foundIsRoot) return true;
      final walk = await walkFrom(verifier, record, key);
      return walk.verdict != ChainVerdict.anchored;
    }
    if (foundIsRoot) return false;
    final walk = await walkFrom(verifier, record, key);
    return walk.verdict != ChainVerdict.anchored;
  }

  /// Whether [link] is a root link: one whose signer `kid` is one of [roots],
  /// whatever its shape.
  static bool _isRootLink(
      Map<String, Object?> link, List<ApskSigningKey> roots) {
    final Iterable<Object?> kids;
    if (link['payload'] is Map) {
      kids = [link[rootLinkKidField]];
    } else {
      try {
        kids = SignedEnvelope.fromJson(link).signatures.map((s) => s.kid);
      } on AtSigningVerificationException {
        return false;
      }
    }
    return kids.any((kid) => roots.any((r) => r.kid == kid));
  }

  /// The public key the atServer reads under each `kid` of an `_apsk` [value]:
  /// for the list form the first entry carrying a string `kid`, `alg` and
  /// `pub`, whatever its status; for a bare value, that value.
  static Map<String, String> _readByAtServer(String value) {
    if (!value.trimLeft().startsWith('{')) {
      try {
        return {publicKeyKidOfBase64(value): value};
      } on FormatException {
        return const {};
      }
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      return const {};
    }
    final entries = decoded is Map ? decoded['keys'] : null;
    if (entries is! List) return const {};
    final read = <String, String>{};
    for (final entry in entries) {
      if (entry is! Map) continue;
      final kid = entry['kid'], alg = entry['alg'], pub = entry['pub'];
      if (kid is String && alg is String && pub is String) {
        read.putIfAbsent(kid, () => pub);
      }
    }
    return read;
  }

  /// Whether [a] and [b] hold the same value and the same links.
  static bool _sameRecord(ApskRecord a, ApskRecord b) =>
      a.value == b.value &&
      const DeepCollectionEquality().equals(a.links, b.links);

  /// Whether [a] and [b] are one public key: equal bytes when both decode as
  /// base64, in either alphabet, else equal text once trimmed.
  static bool sameKey(String a, String b) {
    final ab = _decoded(a), bb = _decoded(b);
    if (ab != null && bb != null) {
      return const DeepCollectionEquality().equals(ab, bb);
    }
    return a.trim() == b.trim();
  }

  static List<int>? _decoded(String key) {
    try {
      return base64Decode(base64
          .normalize(key.trim().replaceAll('-', '+').replaceAll('_', '/')));
    } on FormatException {
      return null;
    }
  }

  static bool _isCanonical(String pub) {
    try {
      return pub.isNotEmpty && base64Encode(base64Decode(pub)) == pub;
    } on FormatException {
      return false;
    }
  }

  /// The verdict for a key the atServer moved to [location].
  static ChainVerdict _verdictFor(String location) =>
      location == EnrollmentConstants.perEnrollmentRevoked
          ? ChainVerdict.revoked
          : ChainVerdict.deleted;

  /// Every root key the record advertises that this build can check a
  /// signature with, active first, then retired, since a root link is checked
  /// long after it was signed.
  Future<List<ApskSigningKey>> _rootCandidates() async =>
      (await PqSigningRoot.publishedRoots(_atClient, _atSign))
          .where((r) => r.vouchesForPastOperations)
          .toList();

  /// Whether root link [link] verifies against [root].
  static Future<bool> _rootLinkVerifies(
      Map<String, Object?> link, ApskSigningKey root) async {
    final payload = link['payload'];
    final signature = link['signature'];
    final algo = PqSigningRoot.verifierFor(root.alg);
    if (payload is! Map || signature is! String || algo == null) return false;
    try {
      return await algo.verifyBytes(
          rootLinkSignableBytes(payload.cast<String, Object?>()),
          signature: base64Decode(signature),
          publicKey: base64Decode(root.pub));
    } on FormatException {
      return false;
    }
  }
}
