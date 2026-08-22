import 'package:at_auth/src/keys/serialization/assurance.dart';
import 'package:at_auth/src/keys/serialization/atkey_material.dart';
import 'package:at_chops/at_chops.dart' hide AtPublicKey, AtPrivateKey;
import 'package:at_commons/at_commons.dart';
import 'package:at_auth/src/auth_constants.dart' as auth_constants;
import 'package:at_auth/src/exception/at_auth_exceptions.dart';

/// What a keyfile records about one enrollment besides its keys — the
/// snapshot an app reads to say which device a keyfile is for *before*
/// authenticating, which the atServer cannot answer.
///
/// Refreshed from the enrollment record on every authenticated start, so a
/// value here is what was true at the last one. Fields are null on a keyfile
/// written where no enrollment request supplied them — a retrofit, or an
/// onboard handed its keys by the caller — and stay null until that
/// reconciliation runs. An absent `namespaces` therefore means "not yet
/// known", which is why it is not written as an empty map: that would state
/// "no grants".
final class AtKeysEnrollment {
  final String enrollmentId;
  final Map<String, String>? namespaces;
  final String? appName;
  final String? deviceName;

  const AtKeysEnrollment({
    required this.enrollmentId,
    this.namespaces,
    this.appName,
    this.deviceName,
  });
}

/// One enrollment's mutable slot in the document: its snapshot, and the
/// materials it owns keyed by `keyId` then `keyPartType`.
class _EnrollmentSlot {
  _EnrollmentSlot(this.enrollmentId);

  final String enrollmentId;
  Map<String, String>? namespaces;
  String? appName;
  String? deviceName;
  final Map<String, Map<String, CryptographicMaterial>> materialsByKeyId = {};

  AtKeysEnrollment get snapshot => AtKeysEnrollment(
        enrollmentId: enrollmentId,
        namespaces: namespaces == null ? null : Map.unmodifiable(namespaces!),
        appName: appName,
        deviceName: deviceName,
      );
}

/// The in-memory model of an atsign's cryptographic keys.
///
/// An AtKeys instance always holds **plaintext** key material — every
/// at-rest concern (the passphrase envelope, self-encryption of the legacy
/// fields) lives in `FileAtKeysIo`, not here.
///
/// Typed key material ([CryptographicMaterial]) sits in one of two containers, and
/// which one is a statement about who the material belongs to:
///
/// - an **enrollment's** keys — its authentication keypair, its signing keys,
///   its key package — reached with [getKey] / [keysForKeyId] /
///   [keysForEnrollment] and retired with [retireKey], all of which take the
///   enrollment beside the keyId;
/// - the **atSign's** own keys — the signing root, an nskey private — reached
///   with [getAtSignKey] / [atSignKeysForKeyId] and retired with
///   [retireAtSignKey].
///
/// ⚠️ **Identity is `(enrollment, keyId)`, not keyId alone.** Two enrollments
/// may each hold `auth:mldsa65:1`. That is why the lookups are split rather
/// than defaulted: a caller reaching for atSign-scope material with a bare
/// keyId would otherwise compile while searching an enrollment, and find
/// nothing.
///
/// [addKey] is not split, because a material states its own owner: its
/// `enrollmentId` routes it, and a null one means the atSign's container.
class AtKeys {
  static const supportedVersion = 1;
  static const _reservedTopLevelKeys = {
    'version',
    'atsign',
    'enrollments',
    'atsignKeys',
  };

  //todo: make non-nullable and final in v4
  Atsign? atsign;

  final Map<String, _EnrollmentSlot> _enrollments = {};

  // Keyed by keyId, then keyPartType (see CryptographicMaterialRole for the known
  // tokens; unknown tokens are held too).
  final Map<String, Map<String, CryptographicMaterial>>
      _atSignMaterialsByKeyId = {};

  /// Every typed material in the document, both containers, in no particular
  /// order.
  Iterable<CryptographicMaterial> get keys => [
        ..._atSignMaterialsByKeyId.values.expand((byType) => byType.values),
        ..._enrollments.values.expand(
            (slot) => slot.materialsByKeyId.values.expand((b) => b.values)),
      ];

  /// The atSign's own materials — the signing root, nskey privates — with no
  /// enrollment between them and the document.
  Iterable<CryptographicMaterial> get atSignKeys =>
      _atSignMaterialsByKeyId.values.expand((byType) => byType.values);

  /// Every enrollment this keyfile holds. Writers emit one; the reader
  /// tolerates several so that emitting a second never has to break a build
  /// that predates it.
  Iterable<String> get enrollmentIds => _enrollments.keys;

  AtKeys({
    this.atsign,
    List<CryptographicMaterial> keysList = const [],
  }) {
    for (final key in keysList) {
      addKey(key);
    }
  }

  /// The parse's own constructor: files [materials] through [_file], so a
  /// document holding more than one live enrollment is READ rather than
  /// refused.
  ///
  /// The public constructor above is a writer's — app code assembling keys —
  /// and keeps the write-side policy. Sharing one path is what made the
  /// reader inherit the writer's refusal, which is the state this replaces.
  AtKeys._parsed(
      {this.atsign, required List<CryptographicMaterial> materials}) {
    for (final material in materials) {
      _file(material);
    }
  }

  /// What this keyfile records about [enrollmentId] besides its keys, or null
  /// when it holds no such enrollment.
  AtKeysEnrollment? enrollmentInfo(String enrollmentId) =>
      _enrollments[enrollmentId]?.snapshot;

  /// Records the enrollment record's [namespaces] / [appName] / [deviceName]
  /// against [enrollmentId], creating the enrollment slot if this is the
  /// first thing filed for it.
  ///
  /// A null argument leaves that field as it was, so a caller holding only
  /// part of the snapshot does not erase the rest. Writing a field it does
  /// not have is what an empty-placeholder scheme would do, and an empty
  /// `namespaces` states "no grants" rather than "not yet known".
  void recordEnrollmentSnapshot(
    String enrollmentId, {
    Map<String, String>? namespaces,
    String? appName,
    String? deviceName,
  }) {
    final slot = _enrollments.putIfAbsent(
        enrollmentId, () => _EnrollmentSlot(enrollmentId));
    if (namespaces != null) slot.namespaces = Map.of(namespaces);
    if (appName != null) slot.appName = appName;
    if (deviceName != null) slot.deviceName = deviceName;
  }

  /// Looks up one of [enrollmentId]'s materials by `(keyId, keyPartType)` —
  /// [type] is a [CryptographicMaterialRole] token.
  CryptographicMaterial? getKey(
          String enrollmentId, String keyId, String type) =>
      _enrollments[enrollmentId]?.materialsByKeyId[keyId]?[type];

  /// Looks up one of the atSign's own materials by `(keyId, keyPartType)`.
  CryptographicMaterial? getAtSignKey(String keyId, String type) =>
      _atSignMaterialsByKeyId[keyId]?[type];

  /// Every material of [enrollmentId] sharing [keyId] — e.g. the
  /// public+private halves of one keypair.
  ///
  /// Potentially might only contain a half of a keypair. Typically the public one.
  Iterable<CryptographicMaterial> keysForKeyId(
          String enrollmentId, String keyId) =>
      _enrollments[enrollmentId]?.materialsByKeyId[keyId]?.values ?? const [];

  /// Every atSign-scope material sharing [keyId].
  Iterable<CryptographicMaterial> atSignKeysForKeyId(String keyId) =>
      _atSignMaterialsByKeyId[keyId]?.values ?? const [];

  /// Returns every material tagged with [enrollmentId].
  Iterable<CryptographicMaterial> keysForEnrollment(String enrollmentId) =>
      _enrollments[enrollmentId]
          ?.materialsByKeyId
          .values
          .expand((byType) => byType.values) ??
      const [];

  /// Files [material] in the container its own `enrollmentId` names — that
  /// enrollment's when it has one, the atSign's when it is null.
  ///
  /// This is the **write** path, so it refuses a second live enrollment: one
  /// per install is what this build produces. Reading does not, and the
  /// asymmetry is deliberate — see
  /// [AtKeysAssurance.refuseSecondLiveEnrollment].
  void addKey(CryptographicMaterial material) {
    const AtKeysAssurance()
        .refuseSecondLiveEnrollment(existing: keys, candidate: material);
    _file(material);
  }

  /// [addKey] without the write-only policy: the structural invariants only.
  ///
  /// What the parse files through. A document is evidence of what some build
  /// wrote, not a request for this one to write something, so the rules that
  /// apply to it are the ones about whether it is *coherent* — no duplicate
  /// `(owner, keyId, part)`, no two active keys of one role and algorithm in
  /// one enrollment — and not the ones about what this build chooses to emit.
  void _file(CryptographicMaterial material) {
    const AtKeysAssurance().validateAddKey(existing: keys, candidate: material);
    _containerFor(material.enrollmentId)
        .putIfAbsent(material.keyId, () => {})[material.keyPartType] = material;
  }

  Map<String, Map<String, CryptographicMaterial>> _containerFor(
      String? enrollmentId) {
    if (enrollmentId == null) return _atSignMaterialsByKeyId;
    return _enrollments
        .putIfAbsent(enrollmentId, () => _EnrollmentSlot(enrollmentId))
        .materialsByKeyId;
  }

  /// Files a freshly minted APKAM keypair as an enrollment's
  /// **authentication** material, under the keyId
  /// `auth:<algorithm>:<generation>`.
  ///
  /// This is the one place that id shape is written. The enrollment is stated
  /// by the container the material lands in, not by the id: two stored copies
  /// of one fact can disagree with nothing to arbitrate. The generation suffix
  /// is what lets one enrollment hold more than one APKAM keypair of an
  /// algorithm over its life — a rotation retires the previous generation and
  /// files the next, and the retired bytes stay in the file because they are
  /// still needed to verify what they signed. The algorithm is in the id
  /// because an enrollment moving from one to another holds both at once, and
  /// they must not collide.
  ///
  /// [algorithm] is a [CryptographicMaterialAlgorithm] token, which is also the enrollment
  /// `signingAlgo` spelling — the keyfile and the wire use the same strings.
  /// Both halves are filed and share one creation timestamp: the private one
  /// is what PKAM signs with, and the public one is what a reader checks this
  /// enrollment's server-side record against.
  ///
  /// Filed as `privateAuthentication` / `publicAuthentication`, NOT as
  /// signing material: this keypair authenticates, and an enrollment's
  /// signing keys are separate material with their own lifecycle.
  void fileApkamMaterial({
    required String enrollmentId,
    required String algorithm,
    required String publicKey,
    required String privateKey,
  }) {
    final now = DateTime.now().toUtc();
    final keyId = keyIdPrefix('auth', algorithm) +
        '${nextAuthenticationGeneration(enrollmentId, algorithm)}';
    addKey(CryptographicMaterial(
        keyId: keyId,
        enrollmentId: enrollmentId,
        keyPartType: CryptographicMaterialRole.privateAuthentication,
        keyAlgorithmType: algorithm,
        bytes: AtBytes.fromString(privateKey),
        createdAt: now));
    addKey(CryptographicMaterial(
        keyId: keyId,
        enrollmentId: enrollmentId,
        keyPartType: CryptographicMaterialRole.publicAuthentication,
        keyAlgorithmType: algorithm,
        bytes: AtBytes.fromString(publicKey),
        createdAt: now));
  }

  /// The generation number [fileApkamMaterial] will use next for
  /// [enrollmentId]'s [algorithm] — one past the highest already filed, or 1.
  ///
  /// Derived from the keyIds present rather than counted separately, so it
  /// cannot drift from what the file actually holds. An id whose suffix is
  /// not a number is ignored rather than rejected: a keyfile written by a
  /// build that spells generations differently must still be readable.
  int nextAuthenticationGeneration(String enrollmentId, String algorithm) =>
      _nextGeneration(
          _enrollments[enrollmentId]?.materialsByKeyId.keys ?? const [],
          keyIdPrefix('auth', algorithm));

  /// Files a signing keypair for [enrollmentId] under
  /// `sign:<algorithm>:<generation>`.
  ///
  /// Algorithm leads the suffix because algorithm is what a verifier selects
  /// on: an enrollment holds one active signing key per algorithm, and an
  /// envelope's signature names which one produced it. The generation allows
  /// rotating a signing key within its algorithm.
  void fileSigningMaterial({
    required String enrollmentId,
    required String algorithm,
    required String publicKey,
    required String privateKey,
  }) {
    final now = DateTime.now().toUtc();
    final keyId = keyIdPrefix('sign', algorithm) +
        '${nextSigningGeneration(enrollmentId, algorithm)}';
    addKey(CryptographicMaterial(
        keyId: keyId,
        enrollmentId: enrollmentId,
        keyPartType: CryptographicMaterialRole.privateSigning,
        keyAlgorithmType: algorithm,
        bytes: AtBytes.fromString(privateKey),
        createdAt: now));
    addKey(CryptographicMaterial(
        keyId: keyId,
        enrollmentId: enrollmentId,
        keyPartType: CryptographicMaterialRole.publicVerification,
        keyAlgorithmType: algorithm,
        bytes: AtBytes.fromString(publicKey),
        createdAt: now));
  }

  /// The generation [fileSigningMaterial] will use next for [enrollmentId]'s
  /// [algorithm] — one past the highest already filed, or 1.
  int nextSigningGeneration(String enrollmentId, String algorithm) =>
      _nextGeneration(
          _enrollments[enrollmentId]?.materialsByKeyId.keys ?? const [],
          keyIdPrefix('sign', algorithm));

  /// The generation an atSign-scope keypair of [role] and [algorithm] should
  /// be filed under next — one past the highest already there, or 1.
  ///
  /// The generation IS the slot. A pair that lost a mint race is retired in
  /// place and keeps its generation forever, so the next mint lands beside it
  /// rather than over it; `addKey` refuses a duplicate keyId, which is what
  /// makes that safe rather than merely tidy.
  int nextAtSignGeneration(String role, String algorithm) => _nextGeneration(
      _atSignMaterialsByKeyId.keys, keyIdPrefix(role, algorithm));

  /// The keyId prefix a [role]/[algorithm] pair is filed under —
  /// `<role>:<algorithm>:`, completed by a generation number.
  ///
  /// The grammar has one definition, here, because a keyId is composed in one
  /// place and parsed in another: [isRoleKeyId] reads exactly what this
  /// writes, and a caller assembling the string itself would be holding a
  /// second copy of a shape that has to agree with this one.
  ///
  /// Roles in use: `auth` (an enrollment's APKAM keypair), `sign` (its own
  /// signing keypair) and `root` (the atSign's signing root, filed by
  /// at_client — atSign-scope material rather than an enrollment's).
  static String keyIdPrefix(String role, String algorithm) =>
      '$role:$algorithm:';

  /// Whether [keyId] names a keypair of [role] — `<role>:<algo>:<generation>`
  /// exactly, the shape [keyIdPrefix] composes and every generation parse
  /// reads.
  ///
  /// The **shape** is the filter, not the material's part type, which is
  /// ambiguous in both directions: an enrollment can hold `privateSigning`
  /// material under more than one keyId, and the atSign's signing root is
  /// `privateSigning` too while belonging to no enrollment.
  ///
  /// The algorithm is not matched. A caller asking "is this a root slot"
  /// wants every generation of every algorithm, because that is what makes a
  /// key of one algorithm replaceable by a key of another.
  static bool isRoleKeyId(String keyId, String role) {
    final prefix = '$role:';
    if (!keyId.startsWith(prefix)) return false;
    final suffix = keyId.substring(prefix.length).split(':');
    return suffix.length == 2 && int.tryParse(suffix[1]) != null;
  }

  /// One past the highest numeric suffix among [keyIds] starting with
  /// [prefix], or 1. An id whose suffix is not a number is ignored rather
  /// than rejected: a keyfile written by a build that spells generations
  /// differently must still be readable.
  static int _nextGeneration(Iterable<String> keyIds, String prefix) {
    var highest = 0;
    for (final keyId in keyIds) {
      if (!keyId.startsWith(prefix)) continue;
      final generation = int.tryParse(keyId.substring(prefix.length));
      if (generation != null && generation > highest) {
        highest = generation;
      }
    }
    return highest + 1;
  }

  /// Every active signing keypair [enrollmentId] holds, strongest algorithm
  /// first — one entry per algorithm, which is what a multi-signature writer
  /// iterates and what a `_apsk` array is composed from.
  ///
  /// Selected by the keyId shape [fileSigningMaterial] writes, **not** by the
  /// `privateSigning` role, which an enrollment can hold for more than one
  /// reason. The atSign-wide signing root shares that role and is no longer a
  /// hazard here — it lives in the atSign's own container and this method
  /// never looks there — but the shape filter is what keeps any future
  /// `privateSigning` material of an enrollment's from being advertised as a
  /// signing key it can be asked to produce signatures with.
  ///
  /// Both halves must be present and active. A private with no published
  /// public cannot be verified against anything, and a public with no private
  /// cannot sign.
  ///
  /// An entry naming an algorithm [SigningAlgoType] does not know is skipped
  /// rather than refused — a keyfile written by a newer client holds keys this
  /// build cannot sign with, and its other keys are still usable. Skipping is
  /// safe here in a way it is not in [authenticationFor]: an unusable signing
  /// key costs one signature, while an unusable authentication key would send
  /// the caller to the flat fields and sign the PKAM challenge as somebody
  /// else.
  List<({SigningAlgoType algorithm, String publicKey, String privateKey})>
      signingKeysFor(String enrollmentId) {
    final held =
        <({SigningAlgoType algorithm, String publicKey, String privateKey})>[];
    for (final keyId in _enrollments[enrollmentId]?.materialsByKeyId.keys ??
        const <String>[]) {
      if (!isRoleKeyId(keyId, 'sign')) continue;

      final private =
          getKey(enrollmentId, keyId, CryptographicMaterialRole.privateSigning);
      final public = getKey(
          enrollmentId, keyId, CryptographicMaterialRole.publicVerification);
      if (private == null || public == null) continue;
      if (private.status != KeyPartStatus.active ||
          public.status != KeyPartStatus.active) {
        continue;
      }
      // Halves that disagree about their algorithm are not a keypair, and
      // nothing refuses the combination on the way in: the invariants are per
      // `(keyPartType, keyAlgorithmType)`, so a keyId's two halves are never
      // compared with each other and a document can carry it. Taking the
      // algorithm from one half and the public bytes from the other would
      // sign under one algorithm while advertising the other's public key, so
      // every signature would fail verification with nothing naming the
      // keyfile as the cause.
      if (private.keyAlgorithmType != public.keyAlgorithmType) continue;

      final algorithm = SigningAlgoType.values
          .where((a) => a.name == private.keyAlgorithmType)
          .firstOrNull;
      if (algorithm == null) continue;

      held.add((
        algorithm: algorithm,
        publicKey: public.bytes.toString(),
        privateKey: private.bytes.toString(),
      ));
    }
    held.sort((a, b) => _strongestFirst(a.algorithm, b.algorithm));
    return held;
  }

  /// The **public** half of every signing keypair [enrollmentId] has
  /// withdrawn from signing, strongest algorithm first, each with the status
  /// the keyfile gives it — the entries an `_apsk` advertisement carries
  /// alongside the active ones, so that envelopes signed before a key was
  /// withdrawn still verify.
  ///
  /// **Public-only, deliberately.** A retired key exists to verify what it
  /// already signed and must never sign again, so handing back its private
  /// half would only invite that. For the same reason the private half is not
  /// required to be *present*: a build that wipes a withdrawn key's private
  /// material is doing the hygienic thing, and dropping the advertisement
  /// entry when it does would retroactively unverify everything that key
  /// signed — the precise loss retention exists to prevent.
  ///
  /// Selected on **not active and not [KeyPartStatus.dead]**, and the token
  /// itself is carried out rather than replaced. `dead` material was never
  /// adopted and has nothing to verify, so it stays out.
  ///
  /// This read "selected on exactly [KeyPartStatus.retired]" until 2026-08-22,
  /// skipping a status this build had never seen on the grounds that
  /// advertising such a key would state something about it this build does not
  /// know. That was right while the advertisement could only say `active` or
  /// `retired`; now that its `status` is an open token the entry can carry the
  /// keyfile's own word for it, so nothing is guessed — and skipping is not the
  /// cautious option it looks like. The advertisement is rewritten whole on
  /// every publish, so an omitted entry is a **withdrawal**: it erases both the
  /// key that verifies what it signed and whatever its owner last said about
  /// it.
  ///
  /// Same keyId shape and same unknown-algorithm skip as [signingKeysFor]; an
  /// enrollment's other `privateSigning` material is not a signing key of its
  /// own and is not advertised as one.
  List<({SigningAlgoType algorithm, String publicKey, String status})>
      withdrawnSigningKeysFor(String enrollmentId) {
    final withdrawn =
        <({SigningAlgoType algorithm, String publicKey, String status})>[];
    for (final keyId in _enrollments[enrollmentId]?.materialsByKeyId.keys ??
        const <String>[]) {
      if (!isRoleKeyId(keyId, 'sign')) continue;

      final public = getKey(
          enrollmentId, keyId, CryptographicMaterialRole.publicVerification);
      if (public == null ||
          public.status == KeyPartStatus.active ||
          public.status == KeyPartStatus.dead) {
        continue;
      }

      final algorithm = SigningAlgoType.values
          .where((a) => a.name == public.keyAlgorithmType)
          .firstOrNull;
      if (algorithm == null) continue;

      withdrawn.add((
        algorithm: algorithm,
        publicKey: public.bytes.toString(),
        status: public.status,
      ));
    }
    withdrawn.sort((a, b) => _strongestFirst(a.algorithm, b.algorithm));
    return withdrawn;
  }

  /// Retires every active signing keypair [enrollmentId] holds for
  /// [algorithm], returning the keyIds it moved — empty when it holds none,
  /// which is the ordinary case on a client whose in-use set has not changed.
  ///
  /// The caller names an **algorithm** rather than a keyId, because the
  /// algorithm is the unit a signing key leaves service in: a client's in-use
  /// set names algorithms, a verifier selects on them, and the generation a
  /// key happens to sit under is this class's own grammar. A caller that had
  /// to reconstruct `sign:<algo>:<n>` would be holding a second copy of that
  /// grammar, and the two would drift.
  ///
  /// [algorithm] is a [CryptographicMaterialAlgorithm] token — the same spelling
  /// [fileSigningMaterial] files under and [signingKeysFor] reads back.
  ///
  /// Retires the keypair rather than removing it, and **both halves**. The
  /// public half is what [withdrawnSigningKeysFor] reads back so the
  /// enrollment can go on advertising it as `retired`, which is what keeps
  /// envelopes signed before the withdrawal verifiable; the private half stays
  /// because nothing in this file is ever deleted.
  ///
  /// Selects exactly what [signingKeysFor] would have returned for
  /// [algorithm]: the `sign:<algo>:<n>` shape, not the `privateSigning` role,
  /// which an enrollment can hold material for under more than one keyId.
  /// Withdrawing a signing key must not withdraw anything else that happens to
  /// sign.
  List<String> retireSigningKeys(String enrollmentId, String algorithm,
      {String to = KeyPartStatus.retired}) {
    final Map<String, Map<String, CryptographicMaterial>> byKeyId =
        _enrollments[enrollmentId]?.materialsByKeyId ?? const {};
    final keyIds = [
      for (final entry in byKeyId.entries)
        if (isRoleKeyId(entry.key, 'sign') &&
            entry.value.values.any((material) =>
                material.status == KeyPartStatus.active &&
                material.keyAlgorithmType == algorithm))
          entry.key
    ];
    for (final keyId in keyIds) {
      retireKey(enrollmentId, keyId, to: to);
    }
    return keyIds;
  }

  static int _strongestFirst(SigningAlgoType a, SigningAlgoType b) =>
      SigningAlgoType.strongestFirst
          .indexOf(a)
          .compareTo(SigningAlgoType.strongestFirst.indexOf(b));

  /// Adopts [materials] — what an enrollment request's metadataBuilder filed
  /// into the construction keys it was handed — tagged with the enrollment id
  /// they now belong to.
  ///
  /// Every other field rides across untouched, `createdAt` and `status`
  /// included: at_auth carries key material and does not interpret it, so the
  /// only thing an adoption may change is whose enrollment it is.
  void adoptMaterials(Iterable<CryptographicMaterial> materials,
      {required String enrollmentId}) {
    for (final material in materials.toList()) {
      addKey(CryptographicMaterial(
          keyId: material.keyId,
          enrollmentId: enrollmentId,
          keyPartType: material.keyPartType,
          keyAlgorithmType: material.keyAlgorithmType,
          bytes: material.bytes,
          operations: material.operations,
          createdAt: material.createdAt,
          status: material.status));
    }
  }

  /// Marks every material of [enrollmentId]'s [keyId] as [to]
  /// ([KeyPartStatus.retired] by default). Key material is never removed —
  /// retired/dead bytes are still needed to decrypt data they protected — so
  /// this is the delete operation. Status only moves forward (active →
  /// retired → dead): a same-status call is a no-op and a backward transition
  /// throws, as does an unknown [keyId] or `to: KeyPartStatus.active`.
  void retireKey(String enrollmentId, String keyId,
          {String to = KeyPartStatus.retired}) =>
      _retire(_enrollments[enrollmentId]?.materialsByKeyId, keyId, to,
          'enrollment "$enrollmentId"');

  /// [retireKey] for the atSign's own material — the signing root, an nskey
  /// private.
  void retireAtSignKey(String keyId, {String to = KeyPartStatus.retired}) =>
      _retire(_atSignMaterialsByKeyId, keyId, to, 'the atSign');

  void _retire(Map<String, Map<String, CryptographicMaterial>>? container,
      String keyId, String to, String ownerLabel) {
    if (to == KeyPartStatus.active) {
      throw ArgumentError.value(to, 'to', 'retireKey cannot reactivate a key');
    }
    final toRank = KeyPartStatus.rankOf(to);
    if (toRank == null) {
      throw ArgumentError.value(
          to, 'to', 'not a status this build knows how to move a key to');
    }
    final byType = container?[keyId];
    if (byType == null) {
      throw ArgumentError.value(
          keyId, 'keyId', 'AtKeys holds no such keyId for $ownerLabel');
    }
    for (final material in byType.values) {
      final fromRank = KeyPartStatus.rankOf(material.status);
      // A status this build has never heard of is not behind or ahead of
      // anything — it is incomparable, and moving a key off one would be
      // guessing a direction. Refused rather than treated as position zero,
      // which is what would let a future value be silently reactivated.
      if (fromRank == null) {
        throw ArgumentError.value(
            to,
            'to',
            'keyId "$keyId" holds status "${material.status}", which this '
                'build does not know: refusing to move a key whose position '
                'in the forward order it cannot determine');
      }
      if (fromRank > toRank) {
        throw ArgumentError.value(to, 'to',
            'cannot move keyId "$keyId" backward from ${material.status}');
      }
    }
    byType.updateAll((_, material) => material.withStatus(to));
  }

  /// Retires [keyId] and files [replacements] in one call — a key rotation,
  /// as a single operation rather than two the caller has to sequence.
  ///
  /// The order is forced and it is the only order that works. The invariants
  /// permit one ACTIVE material per (enrollment, role, **algorithm**), so a
  /// replacement spelled in the same algorithm as the outgoing key needs that
  /// key retired first; add-then-retire is rejected by [addKey] before the
  /// retire ever runs.
  ///
  /// ⚠️ **The algorithm is part of the rule, and this sentence used to omit
  /// it** — which reads as "an enrollment holds one active key per role", and
  /// would say that agility is impossible. It is not: an enrollment holds one
  /// active signing key *per algorithm it signs with*, and one active
  /// encapsulation key *per KEM it advertises*. Adding a key under an
  /// algorithm the enrollment does not yet hold needs no rotation and does not
  /// belong here — call [addKey]. Use this only when the incoming key takes an
  /// outgoing one's slot. Leaving callers to
  /// sequence that themselves means a keyfile flush can land between the two
  /// steps, and a crash there leaves an enrollment with no active key of that
  /// role at all.
  ///
  /// Rolls back if any replacement is refused, so a rejected rotation leaves
  /// the outgoing key active rather than retiring it and then failing to
  /// install its successor — which would be worse than not rotating.
  ///
  /// [to] is how far the outgoing material moves: `retired` by default,
  /// `dead` when it should no longer be used even to verify history.
  ///
  /// Enrollment-scoped only. The atSign's own material has no rotation of
  /// this shape: a signing-root pair that lost its mint race is retired where
  /// it stands while the winner is filed under the next generation, and a
  /// successor root is added beside its retired predecessor rather than
  /// replacing it — the predecessor is what verifies everything it signed.
  void replaceKey(String enrollmentId, String keyId,
      Iterable<CryptographicMaterial> replacements,
      {String to = KeyPartStatus.retired}) {
    final outgoing = keysForKeyId(enrollmentId, keyId).toList();
    if (outgoing.isEmpty) {
      throw ArgumentError.value(keyId, 'keyId',
          'AtKeys holds no such keyId for enrollment "$enrollmentId"');
    }
    retireKey(enrollmentId, keyId, to: to);
    final filed = <CryptographicMaterial>[];
    try {
      for (final replacement in replacements) {
        addKey(replacement);
        filed.add(replacement);
      }
    } on Object {
      // Undo, so a refused rotation is a no-op rather than a keyfile with the
      // old key retired and no new one in its place. Each material is undone
      // in the container its own enrollmentId names, which is where addKey
      // put it — a replacement naming a different owner is a caller error,
      // but it must still be taken back out of wherever it landed.
      for (final material in filed) {
        final container = _containerFor(material.enrollmentId);
        container[material.keyId]?.remove(material.keyPartType);
        if (container[material.keyId]?.isEmpty ?? false) {
          container.remove(material.keyId);
        }
      }
      final container = _containerFor(outgoing.first.enrollmentId);
      for (final material in outgoing) {
        container[material.keyId]![material.keyPartType] = material;
      }
      rethrow;
    }
  }

  /// Every enrollment holding active authentication material — the ones this
  /// keyfile could authenticate as.
  ///
  /// Whatever algorithm it names, including one this build cannot sign with:
  /// whether an enrollment HAS an authentication key is a different question
  /// from whether this build can use it, and answering "none" for the second
  /// would send a caller to the flat fields, which on a retrofitted keyfile
  /// belong to somebody else.
  Iterable<String> get authenticatableEnrollmentIds => _enrollments.values
      .where((slot) => slot.materialsByKeyId.values.any((byType) =>
          byType[CryptographicMaterialRole.privateAuthentication]?.status ==
          KeyPartStatus.active))
      .map((slot) => slot.enrollmentId);

  /// The one enrollment this keyfile authenticates as, for a caller that has
  /// no id of its own to supply — a cold start holding nothing but the file.
  ///
  /// Null when the file holds no typed authentication material at all: a
  /// legacy keyfile, whose APKAM keypair lives in the flat fields, and whose
  /// enrollment is the flat [enrollmentId].
  ///
  /// **Throws when several qualify**, naming them. It is deliberately not a
  /// first-wins default: a keyfile holding two live enrollments is a state
  /// the writer refuses to create, so meeting one means something else is
  /// wrong, and picking one silently is how a client ends up authenticating
  /// as the wrong principal with nothing to point at. The selection stays the
  /// caller's — this offers the candidates, not a verdict.
  String? resolveAuthenticatingEnrollment() {
    final candidates = authenticatableEnrollmentIds.toList();
    if (candidates.isEmpty) return null;
    if (candidates.length > 1) {
      throw AtKeysEnrollmentException(
          'This keyfile holds active authentication material for '
          '${candidates.length} enrollments (${candidates.join(', ')}), so '
          'which one it authenticates as is not derivable. The caller must '
          'name the enrollment it means.');
    }
    return candidates.single;
  }

  /// Decodes the typed-keys document shape (`version`, `atsign`,
  /// `atsignKeys`, `enrollments`, plus legacy fields flat at the top level).
  /// Json without a `version` field is accepted as the legacy flat shape
  /// (delegates to [_fromLegacyJson]); a `version` other than
  /// [supportedVersion] throws [AtKeysUnsupportedVersionException]. Each
  /// container's entries are parsed and validated by [parseAtKeysDocument],
  /// which returns the flattened [CryptographicMaterial]s that are actually stored.
  ///
  /// Several `enrollments` entries are read, and the caller says which one it
  /// authenticates as (or asks [resolveAuthenticatingEnrollment]). Writers
  /// emit one; tolerating more here is what lets a later build emit a second
  /// without breaking every build that predates it.
  factory AtKeys.fromJson(Map<String, dynamic> json) {
    const assurance = AtKeysAssurance();
    // Legacy files have no version field - accept them as legacy.
    if (!json.containsKey('version')) {
      return AtKeys._fromLegacyJson(json);
    }
    final version = assurance.expectInt(json['version'], 'version');
    if (version != supportedVersion) {
      throw AtKeysUnsupportedVersionException(
          'Unsupported atKeys version: $version');
    }
    // A top-level `keys` array predates the enrollments[]/atsignKeys[] split.
    //
    // Refused only when it CARRIES something. A populated one cannot be read
    // here silently: `keys` is no longer a reserved field, so the array would
    // be swept into [metadata] as a legacy value, the document would read as
    // holding no typed material at all, and the caller would authenticate
    // from the flat block — as the legacy enrollment — while the live
    // enrollment's credentials sat unread beside it.
    //
    // An EMPTY one is accepted, because that is the only shape any released
    // build ever wrote. The version that introduced `keys` never populated
    // it: `addKey` has no caller outside `AtKeys` itself there, so every
    // keyfile it onboarded carries `"keys": []` with the real material in the
    // flat block below. Refusing those would strand every keyfile a released
    // build produced, to guard against mis-filing an array holding nothing.
    // Measured, not assumed: a keyfile written by the published version was
    // read back here, and it differs from one this build accepts by exactly
    // this empty array.
    if (json.containsKey('keys')) {
      final legacyKeys = json['keys'];
      if (legacyKeys is! List || legacyKeys.isNotEmpty) {
        throw AtKeysValidationException(
            'This keyfile carries a non-empty top-level "keys" array, the '
            'shape that preceded enrollments[]/atsignKeys[]. It must be '
            'regenerated; reading it here would file its key material as '
            'legacy metadata and authenticate as the wrong enrollment.');
      }
      // Dropped rather than carried, so it does not reach [metadata] and get
      // written back out on the next save.
      json = Map<String, dynamic>.from(json)..remove('keys');
    }

    final atsign =
        assurance.expectNonEmptyString(json['atsign'], 'atsign').toAtsign();

    final materials = <CryptographicMaterial>[];
    if (json.containsKey('atsignKeys')) {
      materials.addAll(parseAtKeysDocument(
          assurance.expectList(json['atsignKeys'], 'atsignKeys'),
          fieldPrefix: 'atsignKeys'));
    }

    final snapshots = <AtKeysEnrollment>[];
    if (json.containsKey('enrollments')) {
      final enrollmentsJson =
          assurance.expectList(json['enrollments'], 'enrollments');
      for (final entry in enrollmentsJson.asMap().entries) {
        final prefix = 'enrollments[${entry.key}]';
        final entryJson = assurance.expectMap(entry.value, prefix);
        final enrollmentId = assurance.expectNonEmptyString(
            entryJson['enrollmentId'], '$prefix.enrollmentId');
        snapshots.add(AtKeysEnrollment(
          enrollmentId: enrollmentId,
          namespaces: _namespacesOf(entryJson['namespaces'], prefix),
          appName:
              assurance.optionalString(entryJson['appName'], '$prefix.appName'),
          deviceName: assurance.optionalString(
              entryJson['deviceName'], '$prefix.deviceName'),
        ));
        materials.addAll(parseAtKeysDocument(
            assurance.expectList(entryJson['keys'], '$prefix.keys'),
            enrollmentId: enrollmentId,
            fieldPrefix: '$prefix.keys'));
      }
    }
    assurance.validateKeyMaterials(materials);

    final legacyJson = {
      for (final entry in json.entries)
        if (!_reservedTopLevelKeys.contains(entry.key)) entry.key: entry.value,
    };

    //form the new AtKeys
    AtKeys atKeys = AtKeys._parsed(
      atsign: atsign,
      materials: materials,
    );
    // After the materials, so an enrollment carrying a snapshot and no keys
    // still gets its slot, and one carrying keys keeps the snapshot beside
    // them.
    for (final snapshot in snapshots) {
      atKeys.recordEnrollmentSnapshot(
        snapshot.enrollmentId,
        namespaces: snapshot.namespaces,
        appName: snapshot.appName,
        deviceName: snapshot.deviceName,
      );
    }

    // join them with the legacy format
    return AtKeys._fromLegacyJson(legacyJson, existing: atKeys);
  }

  /// An enrollment's `namespaces` map, or null when it is absent — which
  /// means "not yet reconciled", a different thing from an empty map's "no
  /// grants".
  static Map<String, String>? _namespacesOf(Object? value, String prefix) {
    if (value == null) return null;
    const assurance = AtKeysAssurance();
    final json = assurance.expectMap(value, '$prefix.namespaces');
    return {
      for (final entry in json.entries)
        entry.key: assurance.expectNonEmptyString(
            entry.value, '$prefix.namespaces.${entry.key}'),
    };
  }

  /// Encodes this [AtKeys] to the typed-keys document shape. Legacy fields
  /// merge flatly into the top level alongside
  /// `version`/`atsign`/`atsignKeys`/`enrollments` — upgrading a legacy file
  /// is additive, not a format swap. Falls back to the legacy flat shape (see
  /// [_toLegacyJson]) when there's no atsign and no typed key material.
  ///
  /// All values are emitted plaintext; at-rest self-encryption of the legacy
  /// portion (and the optional passphrase envelope) is `FileAtKeysIo`'s job.
  Map<String, dynamic> toJson() {
    // An enrollment slot can exist with a snapshot and no keys yet, so
    // "carries typed content" is both containers, not just the materials.
    final hasTypedContent =
        _enrollments.isNotEmpty || _atSignMaterialsByKeyId.isNotEmpty;
    if (atsign == null) {
      if (hasTypedContent) {
        throw AtKeysValidationException(
            'atsign is required to serialize typed atKeys material');
      }
      return _toLegacyJson();
    }
    if (!hasTypedContent) {
      // A keyfile holding no typed material comes back exactly as it went in,
      // byte for byte. The version marker describes what the document
      // CONTAINS, and a `version: 1` document with no enrollments and no
      // atSign keys says nothing a legacy file does not — so emitting one
      // would stamp every file a new build merely opened, producing a diff on
      // files nobody meant to change. The marker appears the moment there is
      // typed material to mark.
      return _toLegacyJson();
    }
    return {
      ..._toLegacyJson(),
      'version': supportedVersion,
      'atsign': atsign.toString(),
      if (_atSignMaterialsByKeyId.isNotEmpty)
        'atsignKeys': encodeAtKeysDocument(atSignKeys),
      if (_enrollments.isNotEmpty)
        'enrollments': [
          for (final slot in _enrollments.values)
            {
              'enrollmentId': slot.enrollmentId,
              // Omitted rather than emitted empty: absent means "not yet
              // reconciled from the enrollment record", and an empty
              // namespaces map would state "no grants" instead.
              if (slot.namespaces != null) 'namespaces': slot.namespaces,
              if (slot.appName != null) 'appName': slot.appName,
              if (slot.deviceName != null) 'deviceName': slot.deviceName,
              'keys': encodeAtKeysDocument(slot.materialsByKeyId.values
                  .expand((byType) => byType.values)),
            },
        ],
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! AtKeys) return false;
    return atsign == other.atsign &&
        enrollmentId == other.enrollmentId &&
        apkamPublicKey == other.apkamPublicKey &&
        apkamPrivateKey == other.apkamPrivateKey &&
        defaultEncryptionPublicKey == other.defaultEncryptionPublicKey &&
        defaultEncryptionPrivateKey == other.defaultEncryptionPrivateKey &&
        defaultSelfEncryptionKey == other.defaultSelfEncryptionKey &&
        apkamSymmetricKey == other.apkamSymmetricKey &&
        _mapEquals(metadata, other.metadata) &&
        _materialsEqual(other);
  }

  /// Order-insensitive: two AtKeys holding the same materials are equal no
  /// matter the order they were added in.
  ///
  /// Looked up by owner as well as keyId. Two enrollments may each hold
  /// `auth:mldsa65:1`, so a keyId-only lookup would answer with whichever
  /// enrollment's copy it met first and call two different documents equal.
  bool _materialsEqual(AtKeys other) {
    final materials = keys.toList();
    if (materials.length != other.keys.length) {
      return false;
    }
    return materials.every((material) {
      final counterpart = material.enrollmentId == null
          ? other.getAtSignKey(material.keyId, material.keyPartType)
          : other.getKey(
              material.enrollmentId!, material.keyId, material.keyPartType);
      return counterpart == material;
    });
  }

  @override
  int get hashCode => Object.hash(
        atsign,
        enrollmentId,
        apkamPublicKey,
        apkamPrivateKey,
        defaultEncryptionPublicKey,
        defaultEncryptionPrivateKey,
        defaultSelfEncryptionKey,
        apkamSymmetricKey,
        _metadataHash(metadata),
        // Commutative fold so hashCode matches the order-insensitive equality.
        keys.fold<int>(0, (acc, material) => acc ^ material.hashCode),
      );

  // ───── Legacy flat fields ─────
  // A legacy .atKeys file is a flat JSON object of the six fields below plus
  // enrollmentId and arbitrary metadata. They stay readable/writable (and
  // merge flatly into the typed-keys document) so existing files keep working.

  @Deprecated('hard-coded keys are legacy, see new methods')
  AtBytes? apkamPublicKey;
  @Deprecated('hard-coded keys are legacy, see new methods')
  AtBytes? apkamPrivateKey;
  @Deprecated('hard-coded keys are legacy, see new methods')
  AtBytes? defaultEncryptionPublicKey;
  @Deprecated('hard-coded keys are legacy, see new methods')
  AtBytes? defaultEncryptionPrivateKey;
  @Deprecated('hard-coded keys are legacy, see new methods')
  AtBytes? defaultSelfEncryptionKey;
  @Deprecated('hard-coded keys are legacy, see new methods')
  AtBytes? apkamSymmetricKey;
  @Deprecated('hard-coded keys are legacy, see new methods')
  String? enrollmentId;
  @Deprecated('hard-coded keys are legacy, see new methods')
  Map<String, dynamic> metadata = {};

  /// Encodes just the legacy flat shape — the hard-coded fields plus
  /// [metadata] — with no `version`/`atsign`/`keys`.
  Map<String, dynamic> _toLegacyJson() {
    return {
      auth_constants.apkamPublicKey: apkamPublicKey?.toString(),
      auth_constants.apkamPrivateKey: apkamPrivateKey?.toString(),
      auth_constants.defaultEncryptionPublicKey:
          defaultEncryptionPublicKey?.toString(),
      auth_constants.defaultEncryptionPrivateKey:
          defaultEncryptionPrivateKey?.toString(),
      auth_constants.defaultSelfEncryptionKey:
          defaultSelfEncryptionKey?.toString(),
      auth_constants.apkamSymmetricKey: apkamSymmetricKey?.toString(),
      'enrollmentId': enrollmentId,
      for (var entry in metadata.entries)
        if (!auth_constants.keySchemaList.contains(entry.key))
          entry.key: entry.value
    };
  }

  static AtKeys _fromLegacyJson(Map<String, dynamic> json, {AtKeys? existing}) {
    var keys = existing ?? AtKeys();
    keys
      ..apkamPublicKey = _existsAndNotNull(json, auth_constants.apkamPublicKey)
          ? AtBytes.fromString(json[auth_constants.apkamPublicKey])
          : null
      ..apkamPrivateKey =
          _existsAndNotNull(json, auth_constants.apkamPrivateKey)
              ? AtBytes.fromString(json[auth_constants.apkamPrivateKey])
              : null
      ..defaultEncryptionPublicKey = _existsAndNotNull(
              json, auth_constants.defaultEncryptionPublicKey)
          ? AtBytes.fromString(json[auth_constants.defaultEncryptionPublicKey])
          : null
      ..defaultEncryptionPrivateKey = _existsAndNotNull(
              json, auth_constants.defaultEncryptionPrivateKey)
          ? AtBytes.fromString(json[auth_constants.defaultEncryptionPrivateKey])
          : null
      ..defaultSelfEncryptionKey = _existsAndNotNull(
              json, auth_constants.defaultSelfEncryptionKey)
          ? AtBytes.fromString(json[auth_constants.defaultSelfEncryptionKey])
          : null
      ..apkamSymmetricKey =
          _existsAndNotNull(json, auth_constants.apkamSymmetricKey)
              ? AtBytes.fromString(json[auth_constants.apkamSymmetricKey])
              : null
      ..enrollmentId =
          _existsAndNotNull(json, 'enrollmentId') ? json['enrollmentId'] : null;
    for (var entry in json.entries) {
      if (!auth_constants.keySchemaList.contains(entry.key)) {
        keys.metadata[entry.key] = entry.value;
      }
    }
    return keys;
  }

  @Deprecated('AtChops is being deprecated, by extension this method as well')
  AtChops toAtChops() {
    //if the keys contain an apkamSymmetricKey, they're a apkam key
    return switch (apkamSymmetricKey) {
      AtBytes() => _createApkamChops(this),
      null => _createPkamChops(this),
    };
  }

  /// AtChops for [enrollmentId]'s typed signing material, sharing the
  /// keyfile's flat encryption and self-encryption keys.
  ///
  /// This is how a second enrollment held in the same keyfile — a
  /// self-retrofit's, whose APKAM keypair lives in its own `enrollments[]`
  /// entry while the flat fields keep carrying the original enrollment's —
  /// becomes able to authenticate at all; [toAtChops] reads only the flat
  /// fields and cannot see it.
  ///
  /// The signing keypair rides the String-typed pkam slot as base64 of the
  /// raw key bytes. A caller authenticating over at_lookup must also set
  /// `signingAlgoType` to what [signingAlgorithmForEnrollment] reports, or
  /// the signature is produced by the wrong routine.
  AtChops toAtChopsForEnrollment(String enrollmentId) {
    final materials = keysForEnrollment(enrollmentId);
    // Named for the authentication role they hold, not for the pkam slot they
    // ride in: this method reaches the APKAM keypair only. An enrollment's
    // attestation signing keys are a different, per-algorithm set that nothing
    // here enumerates.
    final privateAuthentication = materials
        .where((m) =>
            m.keyPartType == CryptographicMaterialRole.privateAuthentication &&
            m.status == KeyPartStatus.active)
        .firstOrNull;
    final publicAuthentication = materials
        .where((m) =>
            m.keyPartType == CryptographicMaterialRole.publicAuthentication &&
            m.status == KeyPartStatus.active)
        .firstOrNull;
    if (privateAuthentication == null || publicAuthentication == null) {
      throw AtKeyNotFoundException(
          'AtKeys holds no active authentication keypair for enrollment '
          '$enrollmentId');
    }

    final atChopsKeys = AtChopsKeys.create(
        AtEncryptionKeyPair.create(
          defaultEncryptionPublicKey?.toString() ?? '',
          defaultEncryptionPrivateKey?.toString() ?? '',
        ),
        AtPkamKeyPair.create(publicAuthentication.bytes.toString(),
            privateAuthentication.bytes.toString()));
    if (defaultSelfEncryptionKey != null) {
      atChopsKeys.selfEncryptionKey =
          AESKey(defaultSelfEncryptionKey!.toString());
    }
    return AtChopsImpl(atChopsKeys);
  }

  /// The algorithm of [enrollmentId]'s active **authentication** material —
  /// what PKAM must sign with — or null when the enrollment has no typed
  /// authentication material this build recognises (a legacy flat-fields
  /// enrollment reports null: its RSA keypair lives in the flat fields, not
  /// the typed section).
  ///
  /// Named for signing because that is what `SigningAlgoType` calls it and
  /// what the wire's `signingAlgo` field carries; the key it describes is the
  /// authentication keypair, not the enrollment's attestation signing keys.
  SigningAlgoType? signingAlgorithmForEnrollment(String enrollmentId) {
    final material = _activeAuthenticationMaterial(enrollmentId);
    if (material == null) return null;
    return SigningAlgoType.values
        .where((a) => a.name == material.keyAlgorithmType)
        .firstOrNull;
  }

  /// [enrollmentId]'s active private authentication material, whatever
  /// algorithm it names — including one this build does not recognise.
  ///
  /// Whether the enrollment HAS typed material is a different question from
  /// whether this build can sign with it, and [authenticationFor] has to tell
  /// them apart: a keyfile written by a newer client still holds that
  /// enrollment's key, so answering "none" for it would send the caller to the
  /// flat fields, which on a retrofitted keyfile belong to somebody else.
  CryptographicMaterial? _activeAuthenticationMaterial(String enrollmentId) =>
      keysForEnrollment(enrollmentId)
          .where((m) =>
              m.keyPartType ==
                  CryptographicMaterialRole.privateAuthentication &&
              m.status == KeyPartStatus.active)
          .firstOrNull;

  /// The AtChops and the PKAM signing algorithm [enrollmentId] authenticates
  /// with — the one place either half of an APKAM keypair is resolved.
  ///
  /// Typed material wins wherever this keyfile holds it for [enrollmentId].
  /// The flat [apkamPublicKey]/[apkamPrivateKey] answer only when it holds
  /// none, and that is a fallback to where the keypair actually lives rather
  /// than a default: four shipping shapes file no typed authentication
  /// material at all — a keyfile written before the typed section existed, an
  /// `rsa2048` first onboard, an OTP enrollment, and an onboard handed its
  /// keys by the caller.
  ///
  /// Which way round matters on a **retrofitted** keyfile, the one shape that
  /// holds both: the flat fields keep the capped legacy enrollment's RSA
  /// credentials while the typed section carries the live enrollment's.
  /// Reading the flat fields for an enrollment that has typed material of its
  /// own signs the PKAM challenge as the wrong principal, and the atServer
  /// checks that signature against the named enrollment's record — so the
  /// misresolution surfaces as an authentication failure with nothing
  /// pointing at its cause.
  ///
  /// A null [algorithm] means the caller leaves `signingAlgoType` at
  /// at_lookup's default, which is what the flat fields' RSA keypair needs.
  /// A null [enrollmentId] asks for the flat fields directly — callers reach
  /// here having already defaulted it to this keyfile's own [enrollmentId],
  /// which on a retrofitted file is deliberately the legacy one.
  /// Throws [AtKeyNotFoundException] when [enrollmentId] holds typed
  /// authentication material under an algorithm this build cannot sign with.
  /// Falling back to the flat fields there would authenticate as whoever owns
  /// them, and at_lookup's default is `rsa2048`, so the wrong key would be
  /// signed by the wrong routine. A keyfile written by a newer client is the
  /// way this happens.
  ({AtChops chops, SigningAlgoType? algorithm}) authenticationFor(
      String? enrollmentId) {
    final algorithm = authenticationAlgorithmFor(enrollmentId);
    if (algorithm == null) {
      final material = enrollmentId == null
          ? null
          : _activeAuthenticationMaterial(enrollmentId);
      if (material != null) {
        throw AtKeyNotFoundException(
            'Enrollment $enrollmentId authenticates with '
            '"${material.keyAlgorithmType}", which this build cannot sign '
            'with. Its keypair is in this keyfile; the flat fields are a '
            'different enrollment\'s and are not a substitute for it.');
      }
      return (chops: toAtChops(), algorithm: null);
    }
    return (chops: toAtChopsForEnrollment(enrollmentId!), algorithm: algorithm);
  }

  /// The algorithm half of [authenticationFor], without building an AtChops.
  ///
  /// A caller holding an injected AtChops still has to name the algorithm, and
  /// building one it will discard is not free — [toAtChops] throws on a
  /// keyfile that is missing any of the material it needs, so resolving
  /// eagerly would fail a caller that never needed the keypair at all.
  SigningAlgoType? authenticationAlgorithmFor(String? enrollmentId) =>
      enrollmentId == null ? null : signingAlgorithmForEnrollment(enrollmentId);

  @Deprecated('legacy, please use addKey to add additional keys.')
  AtKeys copyWith(AtKeys other) {
    var keys = AtKeys()
      ..apkamPublicKey = other.apkamPublicKey ?? apkamPublicKey
      ..apkamPrivateKey = other.apkamPrivateKey ?? apkamPrivateKey
      ..defaultEncryptionPublicKey =
          other.defaultEncryptionPublicKey ?? defaultEncryptionPublicKey
      ..defaultEncryptionPrivateKey =
          other.defaultEncryptionPrivateKey ?? defaultEncryptionPrivateKey
      ..defaultSelfEncryptionKey =
          other.defaultSelfEncryptionKey ?? defaultSelfEncryptionKey
      ..apkamSymmetricKey = other.apkamSymmetricKey ?? apkamSymmetricKey
      ..enrollmentId = other.enrollmentId ?? enrollmentId;
    if (other.metadata.isNotEmpty) {
      keys.metadata.addAll(other.metadata);
    }
    return keys;
  }
}

// metadata holds JSON-derived values, so nested maps/lists compare by
// identity under ==; compare (and hash) them structurally instead.
bool _mapEquals(Map<String, dynamic> left, Map<String, dynamic> right) {
  return _deepEquals(left, right);
}

bool _deepEquals(Object? left, Object? right) {
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final key in left.keys) {
      if (!right.containsKey(key) || !_deepEquals(left[key], right[key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var i = 0; i < left.length; i++) {
      if (!_deepEquals(left[i], right[i])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

int _metadataHash(Map<String, dynamic> metadata) => _deepHash(metadata);

int _deepHash(Object? value) {
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
    return Object.hashAll(entries.map(
        (entry) => Object.hash(entry.key.toString(), _deepHash(entry.value))));
  }
  if (value is List) {
    return Object.hashAll(value.map(_deepHash));
  }
  return value.hashCode;
}

// Splitting these implementations to improve understanding

/// APKAMChops should contain:
///   - apkamPublicKey
///   - apkamPrivateKey
///   - usual PKAM keys
/// As well as APKAMChops can potentially have two states:
///   - approval
///   - post approval
/// During approval: the enroll will wait to confirm via PKAM
/// post approval: we fetch the defaultEncryptionPrivateKey & defaultSelfEncryptionKey
AtChops _createApkamChops(AtKeys atKeys) {
  if (atKeys.apkamPublicKey == null) {
    throw AtKeyNotFoundException(
        "apkamPublicKey not found in AtKeys, unable to make atChops instance");
  }
  if (atKeys.apkamSymmetricKey == null) {
    throw AtKeyNotFoundException(
        "apkamSymmetricKey not found in AtKeys, unable to make atChops instance");
  }
  final atEncryptionKeyPair = AtEncryptionKeyPair.create(
    atKeys.defaultEncryptionPublicKey!.toString(),
    atKeys.defaultEncryptionPrivateKey == null
        ? ''
        : atKeys.defaultEncryptionPrivateKey!.toString(),
  );

  final atPkamKeyPair = AtPkamKeyPair.create(
    atKeys.apkamPublicKey!.toString(),
    atKeys.apkamPrivateKey!.toString(),
  );

  final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair)
    ..apkamSymmetricKey = AESKey(atKeys.apkamSymmetricKey!.toString());

  if (atKeys.defaultSelfEncryptionKey != null) {
    atChopsKeys.selfEncryptionKey =
        AESKey(atKeys.defaultSelfEncryptionKey!.toString());
  }

  return AtChopsImpl(atChopsKeys);
}

AtChops _createPkamChops(AtKeys atKeys) {
  if (atKeys.defaultEncryptionPrivateKey == null) {
    throw AtPrivateKeyNotFoundException(
        'PKAM mode requires defaultEncryptionPrivateKey');
  }
  if (atKeys.apkamPrivateKey == null) {
    throw AtPrivateKeyNotFoundException('PKAM mode requires apkamPrivateKey');
  }
  if (atKeys.apkamPublicKey == null) {
    throw AtKeyNotFoundException('PKAM mode requires apkamPublicKey');
  }
  if (atKeys.defaultEncryptionPublicKey == null) {
    throw AtKeyNotFoundException(
        'PKAM mode requires defaultEncryptionPublicKey');
  }
  if (atKeys.defaultSelfEncryptionKey == null) {
    throw AtKeyNotFoundException('PKAM mode requires defaultSelfEncryptionKey');
  }

  final atEncryptionKeyPair = AtEncryptionKeyPair.create(
    atKeys.defaultEncryptionPublicKey!.toString(),
    atKeys.defaultEncryptionPrivateKey!.toString(),
  );

  final atPkamKeyPair = AtPkamKeyPair.create(
    atKeys.apkamPublicKey!.toString(),
    atKeys.apkamPrivateKey!.toString(),
  );

  final atChopsKeys = AtChopsKeys.create(atEncryptionKeyPair, atPkamKeyPair)
    ..selfEncryptionKey = AESKey(atKeys.defaultSelfEncryptionKey!.toString());

  return AtChopsImpl(atChopsKeys);
}

bool _existsAndNotNull(Map<String, dynamic> json, String key) {
  return json.containsKey(key) && json[key] != null;
}
