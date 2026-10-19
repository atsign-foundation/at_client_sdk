import 'package:at_auth/at_auth.dart'
    show
        CryptographicMaterialAlgorithm,
        KeyEntryStatus,
        WrittenAtKeysIo,
        publicKeyKidOfBase64;
import 'package:at_chops/at_chops.dart'
    show MlDsa65KeyPair, RsaKeyPair, SigningAlgoType;
import 'package:at_client/src/enroll/at_sign_credential.dart';
import 'package:at_client/src/enroll/enrollment_update_request.dart';
import 'package:at_client/src/enroll/enrollment_updater.dart';
import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_client/src/crypto/nskey/pq_signing_chain.dart'
    show ChainVerdict, PqSigningChain;
import 'package:at_client/src/mixins/apkam_signing.dart'
    show ApkamSigning, serialiseApskWrite;
import 'package:at_client/src/signing/apsk_composition.dart'
    show apskEntries, apskValueOf, bareApskValueOf;
import 'package:at_client/src/secret_sharing/at_client_secret_sharing.dart'
    show AtClientSecretSharing;
import 'package:at_client/src/signing/envelope_signature.dart'
    show ApkamSigningKeys;
import 'package:at_commons/at_commons.dart' show StoppedException;
import 'package:at_commons/atsign.dart' show AtsignString;
import 'package:at_utils/at_utils.dart' show AtSignLogger, AtUtils;

/// Brings an enrollment's signing keys into line with
/// [AtClientPreference.dataSigningKeyAlgorithms] — minting one for every
/// algorithm the set names and the enrollment does not hold, and retiring
/// every one it holds that the set no longer names.
///
/// A key is filed before it is published, so a stop between the two leaves
/// the keyfile holding it and the next start's `_apsk` republish advertises
/// it; the other order could leave a key advertised that nothing holds. A
/// signer in between signs under a key the advertisement names only once the
/// publish lands. A withdrawal from service is filed after the publish, so an
/// outgoing key is never unadvertised while it is still what signs. A minted
/// key is linked once it is published, by a key this enrollment already has
/// linked, before any outgoing key is retired; an outgoing key with a link
/// stays in service until every key kept has one.
class SigningKeyMinting with ApkamSigning {
  /// Reconciles [atClient]'s signing keys, publishing through [updater] when
  /// one is supplied and a fresh [EnrollmentUpdater] otherwise.
  SigningKeyMinting(this.atClient, {EnrollmentUpdater? updater})
      : _updater = updater ?? EnrollmentUpdater();

  @override
  final AtClient atClient;

  @override
  final AtSignLogger logger = AtSignLogger('SigningKeyMinting');

  final EnrollmentUpdater _updater;

  /// Mints, advertises and files what the in-use set names and the enrollment
  /// lacks; retires what it holds and the set no longer names, leaving a
  /// retired key advertised so that what it already signed still verifies.
  ///
  /// Returns both lists, each empty when there was nothing to do — as with an
  /// empty in-use set, which is inert, or a client with no key source.
  Future<({List<SigningAlgoType> minted, List<SigningAlgoType> retired})>
      reconcileSigningKeys() async {
    const nothing = (minted: <SigningAlgoType>[], retired: <SigningAlgoType>[]);

    final wanted = atClient.getPreferences()?.dataSigningKeyAlgorithms ??
        const <SigningAlgoType>{};
    if (wanted.isEmpty) return nothing;

    final atSign = atClient.getCurrentAtSign();
    final io = atClient.atKeysIo;
    if (atSign == null || io == null) return nothing;
    if (io is! WrittenAtKeysIo) {
      logger.warning('Not minting signing keys for $atSign: this AtKeysIo '
          'cannot persist, so the key would be published and then lost at the '
          'next start, leaving an advertisement nothing can sign under');
      return nothing;
    }

    final held = await heldSigningKeys;
    // NOTE: scoped to rsa2048, because that is the only case where one keypair
    // does both jobs — a legacy keyfile's flat fields, which AtKeys cannot read
    // back as typed signing material. Excluding whatever algorithm the
    // authentication keypair reports would instead stop an mldsa65 signing key
    // from ever being minted.
    final authenticationIsAlsoTheSigningKey = held.isEmpty &&
        (await authenticationSigningKey)?.algorithm == SigningAlgoType.rsa2048;
    final missing = [
      for (final algorithm in SigningAlgoType.strongestFirst)
        if (wanted.contains(algorithm) &&
            !held.any((key) => key.algorithm == algorithm) &&
            !(authenticationIsAlsoTheSigningKey &&
                algorithm == SigningAlgoType.rsa2048))
          algorithm
    ];
    final superseded = [
      for (final key in held)
        if (!wanted.contains(key.algorithm)) key
    ];
    if (missing.isEmpty && superseded.isEmpty) return nothing;

    final minted = [for (final algorithm in missing) await _mint(algorithm)];
    final keeping = [
      for (final key in held)
        if (wanted.contains(key.algorithm)) key
    ];
    if (missing.isNotEmpty) {
      logger.info('Minted ${missing.map((a) => a.name).join(', ')} signing '
          'key(s) for $enrollmentId; filing before publishing');
    }

    // NOTE: file, publish and retire are one critical section, so no other
    // `_apsk` writer in this process composes from the keyfile half way.
    late final List<ApkamSigningKeys> retired;
    await serialiseApskWrite(atClient, () async {
      for (final key in minted) {
        await _file(io, atSign, key);
      }
      retired = await _publishLinkAndRetire(io, atSign,
          minted: minted, keeping: keeping, superseded: superseded, held: held);
    });
    return (
      minted: missing,
      retired: [for (final key in retired) key.algorithm]
    );
  }

  /// Publishes the keys this reconcile keeps, links those whose link does not
  /// walk to the root, and retires [superseded]; returns the keys it retired.
  ///
  /// A superseded key whose link walks to the root stays advertised and in
  /// service while a key kept has no such link, so that it can vouch for that
  /// key: it retires on a later reconcile, once every key kept has one. Any
  /// other superseded key retires at once, and a key the advertisement already
  /// lists as retired is never published in service again. When the record
  /// cannot be read, every superseded key stays in service.
  Future<List<ApkamSigningKeys>> _publishLinkAndRetire(
      WrittenAtKeysIo io, String atSign,
      {required List<ApkamSigningKeys> minted,
      required List<ApkamSigningKeys> keeping,
      required List<ApkamSigningKeys> superseded,
      required List<ApkamSigningKeys> held}) async {
    final kept = [...minted, ...keeping];
    final own = await _ownLinkState();
    bool walks(ApkamSigningKeys key) =>
        own == null || own.anchored.contains(_kidOf(key));
    final vouching = [
      for (final key in superseded)
        if (own == null ||
            (walks(key) && !own.listedRetired.contains(_kidOf(key))))
          key
    ];
    final needsLinks = minted.isNotEmpty || keeping.any((key) => !walks(key));

    if (vouching.isEmpty || !needsLinks) {
      await _publish(_strongestFirst(kept, (key) => key.algorithm),
          retiring: superseded);
      if (needsLinks) await _linkKept(handingOn: held);
      await _retireAll(io, atSign, superseded);
      return superseded;
    }

    final retiringNow = [
      for (final key in superseded)
        if (!vouching.contains(key)) key
    ];
    await _publish(
        _strongestFirst([...kept, ...vouching], (key) => key.algorithm),
        retiring: retiringNow);
    final linkedNow = await _linkKept(handingOn: held);
    final walking = {...?own?.anchored, ...linkedNow};
    if (kept.every((key) => walking.contains(_kidOf(key)))) {
      await _publish(_strongestFirst(kept, (key) => key.algorithm),
          retiring: superseded);
      await _retireAll(io, atSign, superseded);
      return superseded;
    }
    logger.warning('Keeping the '
        '${vouching.map((k) => k.algorithm.name).join(', ')} client data '
        'signing key(s) of $enrollmentId in service, though the in-use set no '
        'longer names them: a key it keeps has no link that walks to the root '
        'yet, and a later start links it with them before retiring them');
    await _retireAll(io, atSign, retiringNow);
    return retiringNow;
  }

  /// Which keys this enrollment's own `_apsk` record has a link for that
  /// walks to the root, and which it lists as retired: none of either for the
  /// atSign's own credential, which takes no link, and null when the record
  /// cannot be read.
  Future<({Set<String> anchored, Set<String> listedRetired})?>
      _ownLinkState() async {
    if (isAtSignCredential(atClient.enrollmentId)) {
      return (anchored: const <String>{}, listedRetired: const <String>{});
    }
    try {
      final chain = PqSigningChain(atClient);
      final own = await chain.readRecord(enrollmentId);
      if (own == null) {
        return (anchored: const <String>{}, listedRetired: const <String>{});
      }
      final verifier = AtClientSecretSharing.forClient(atClient);
      return (
        anchored: {
          for (final key in own.keys)
            if (own.links.containsKey(key.kid) &&
                (await chain.walkFrom(verifier, own, key)).verdict ==
                    ChainVerdict.anchored)
              key.kid
        },
        listedRetired: {
          for (final key in own.keys)
            if (!key.offeredForNewOperations) key.kid
        },
      );
    } on Exception catch (e) {
      if (e is StoppedException) rethrow;
      logger.warning('Could not read which client data signing keys of '
          '$enrollmentId have a link, so any it would retire stay in service: '
          '$e');
      return null;
    }
  }

  static String _kidOf(ApkamSigningKeys key) =>
      publicKeyKidOfBase64(key.publicKey);

  Future<void> _retireAll(
      WrittenAtKeysIo io, String atSign, List<ApkamSigningKeys> keys) async {
    if (keys.isEmpty) return;
    logger.info('Retiring ${keys.map((k) => k.algorithm.name).join(', ')} '
        'signing key(s) for $enrollmentId: the in-use set no longer names '
        'them. They stay advertised as retired, so what they signed still '
        'verifies');
    for (final key in keys) {
      await _retire(io, atSign, key.algorithm);
    }
  }

  /// [keys] ordered by [SigningAlgoType.strongestFirst], the order an
  /// advertisement lists them in.
  static List<T> _strongestFirst<T>(
          Iterable<T> keys, SigningAlgoType Function(T) algorithmOf) =>
      [
        for (final algorithm in SigningAlgoType.strongestFirst)
          ...keys.where((key) => algorithmOf(key) == algorithm)
      ];

  Future<ApkamSigningKeys> _mint(SigningAlgoType algorithm) async {
    switch (algorithm) {
      case SigningAlgoType.mldsa65:
        final pair = await MlDsa65KeyPair.generate();
        return ApkamSigningKeys(
            algorithm: algorithm,
            publicKey: pair.atPublicKey.publicKey,
            privateKey: pair.atPrivateKey.privateKey);
      case SigningAlgoType.rsa2048:
        final pair = RsaKeyPair.generate();
        return ApkamSigningKeys(
            algorithm: algorithm,
            publicKey: pair.atPublicKey.publicKey,
            privateKey: pair.atPrivateKey.privateKey);
      default:
        throw ArgumentError.value(algorithm.name, 'algorithm',
            'no minting routine, though the preference accepted it');
    }
  }

  /// Advertises [active] plus this enrollment's retired signing keys —
  /// [retiring], which this call is about to withdraw from service, and the
  /// ones it withdrew earlier.
  ///
  /// The publish rewrites the whole record, so anything left out is withdrawn
  /// from the advertisement; [retiring] is passed in rather than read back
  /// because the keyfile still holds those keys as active at this point.
  Future<void> _publish(List<ApkamSigningKeys> active,
      {required List<ApkamSigningKeys> retiring}) async {
    final entries = apskEntries(
        signing: active,
        withdrawn: _strongestFirst([
          for (final key in retiring)
            (
              algorithm: key.algorithm,
              publicKey: key.publicKey,
              status: KeyEntryStatus.retired,
            ),
          ...await withdrawnSigningKeys,
        ], (key) => key.algorithm),
        authentication: await authenticationSigningKey);
    final atLookUp = atClient.getRemoteSecondary()?.atLookUp;

    if (isAtSignCredential(atClient.enrollmentId)) {
      // NOTE: the unlocked variant — the caller holds the lock for the whole
      // publish-then-file section, and re-acquiring it here deadlocks.
      await publishPublicSigningKeyLocked(value: apskValueOf(entries));
      return;
    }
    final bare = bareApskValueOf(entries);
    await _updater.update(
        EnrollmentUpdateRequest(
            enrollmentId: atClient.enrollmentId!,
            signingKeys: bare == null ? entries : null,
            apskLegacy: bare),
        atLookUp!);
  }

  /// Links the keys this enrollment advertises that lack a link, signing with
  /// one whose link walks to the root; [handingOn] may vouch although the
  /// advertisement lists it as retired. Returns the `kid`s linked.
  ///
  /// A failure leaves them unlinked and is logged; the caller decides what
  /// stays in service meanwhile.
  Future<List<String>> _linkKept(
      {required List<ApkamSigningKeys> handingOn}) async {
    try {
      // NOTE: a chain voucher alone, never the signing root.
      return await PqSigningChain(atClient).linkOwnKeys(
          AtClientSecretSharing.forClient(atClient),
          isFullyPrivileged: null,
          alsoVouchWith: handingOn);
    } on Exception catch (e) {
      if (e is StoppedException) rethrow;
      logger.warning('Could not link the client data signing key(s) of '
          '$enrollmentId that have no link; a later start tries again: $e');
      return const [];
    }
  }

  Future<void> _file(
      WrittenAtKeysIo io, String atSign, ApkamSigningKeys key) async {
    // NOTE: the store's atomic update, never a hand-rolled read-mutate-write —
    // a sibling writer on the same keyfile would drop this addition.
    await io.update(AtUtils.fixAtSign(atSign).toAtsign(), (keys) {
      keys.fileSigningMaterial(
          enrollmentId: enrollmentId,
          algorithm: _materialAlgorithmOf(key.algorithm),
          publicKey: key.publicKey,
          privateKey: key.privateKey);
      return true;
    });
  }

  /// Withdraws this enrollment's [algorithm] signing keypair from service: both
  /// halves move to `retired` and neither is removed, so that what the public
  /// one signed still verifies.
  ///
  /// Through the store's atomic update, like [_file]; with nothing to retire
  /// the write is abandoned.
  Future<void> _retire(
      WrittenAtKeysIo io, String atSign, SigningAlgoType algorithm) async {
    await io.update(AtUtils.fixAtSign(atSign).toAtsign(), (keys) {
      final retired =
          keys.retireSigningKeys(enrollmentId, _materialAlgorithmOf(algorithm));
      if (retired.isEmpty) {
        logger.warning('Nothing to retire for $enrollmentId under '
            '${algorithm.name}, though it was held a moment ago — leaving the '
            'keyfile alone. The advertisement already published lists it as '
            'retired, so nothing verifies differently, and the next start '
            'reconciles again');
        return false;
      }
      return true;
    });
  }

  /// The keyfile's spelling of [algorithm]. It matches [SigningAlgoType]'s
  /// member name for both, and `AtKeys.signingKeysFor` reads it back by that
  /// name — a second spelling here would file material the reader skips.
  CryptographicMaterialAlgorithm _materialAlgorithmOf(
          SigningAlgoType algorithm) =>
      switch (algorithm) {
        SigningAlgoType.mldsa65 => CryptographicMaterialAlgorithm.mlDsa65,
        SigningAlgoType.rsa2048 => CryptographicMaterialAlgorithm.rsa2048,
        _ => CryptographicMaterialAlgorithm.of(algorithm.name),
      };
}
