import 'package:at_auth/at_auth.dart' show AtKeysIo;
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/era_defaults.dart';
import 'package:at_client/src/crypto/nskey/ck_manager.dart';
import 'package:at_client/src/crypto/nskey/content_key.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_client/src/crypto/nskey/nskey_provider.dart';
import 'package:at_client/src/crypto/nskey/rotation_policy.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show symmetricAesGcmCryptoProviderId;
import 'package:at_client/src/crypto/nskey/symmetric_aes_gcm_provider.dart';
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_commons/at_commons.dart';
import 'package:meta/meta.dart' show visibleForTesting;

// NOTE: the nskey data path is public surface — these types are what
// `CryptoConfig.nskey` requires, returns and throws, so they have to reach the
// package barrel.
export 'package:at_client/src/crypto/nskey/ck_manager.dart';
export 'package:at_client/src/crypto/nskey/content_key.dart';
export 'package:at_client/src/crypto/nskey/content_key_eviction.dart';
export 'package:at_client/src/crypto/nskey/conveyed_key_collection.dart';
export 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
export 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
export 'package:at_client/src/crypto/nskey/nskey_provider.dart';
export 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show
        mlKemNskeyCryptoProviderId,
        nskeyAdvertisementKey,
        nskeyCryptoProviderId,
        nskeyProviderFamily,
        pqCryptoProviderIds,
        symmetricAesGcmCryptoProviderId;
export 'package:at_client/src/crypto/nskey/nskey_resolver.dart';
export 'package:at_client/src/crypto/nskey/rotation_policy.dart';
export 'package:at_client/src/crypto/nskey/nskey_rotation.dart';
export 'package:at_client/src/crypto/nskey/pq_signing_chain.dart';
export 'package:at_client/src/crypto/nskey/pq_signing_root.dart';
export 'package:at_client/src/crypto/nskey/published_nskey_key_ring.dart';
export 'package:at_client/src/crypto/nskey/symmetric_aes_gcm_provider.dart';

/// The id of the built-in legacy (pre-pluggable) encryption scheme — the
/// default provider and the fallback for records with no `appMetadata`.
const String legacyCryptoProviderId = 'legacy';

/// A write would have been encrypted with the legacy provider, and this client
/// was told never to do that ([AtClientPreference.disallowLegacyEncryption]).
///
/// The data path did not fail: the destination is simply only reachable under
/// a scheme a quantum computer will one day open, so an app that catches this
/// can tell its user the recipient cannot be reached securely.
class LegacyEncryptionRefusedException extends AtEncryptionException {
  /// The record that would have been written with the legacy provider.
  final String key;

  LegacyEncryptionRefusedException(this.key, String reason)
      : super('refusing to encrypt $key with the legacy provider: $reason. '
            'This client sets disallowLegacyEncryption, so a destination no '
            'post-quantum scheme can reach is refused rather than written in '
            'one that can be harvested now and opened later.');
}

/// A record was sealed to an nskey generation whose private half this client
/// does not hold **yet**.
///
/// Its own type because it is the one decryption failure worth retrying: the
/// private is conveyed to an enrollment at approval and filed asynchronously,
/// so a value that arrives in that gap is openable moments later. Everything
/// else that fails to decrypt is final.
class NskeyPrivateUnavailableException extends AtDecryptionException {
  /// The atSign whose namespace key this is — not necessarily the reader.
  final String owner;
  final String namespace;

  /// Identifies the generation the record was sealed to.
  final String nskeyKid;

  NskeyPrivateUnavailableException(
      this.owner, this.namespace, this.nskeyKid, String reason)
      : super('no nskey private held for $owner:$namespace generation '
            '$nskeyKid — $reason');
}

/// A record identifying one filed nskey private, as [SignalsPrivateFiling]
/// reports it.
typedef FiledNskeyPrivate = ({String owner, String namespace, String nskeyKid});

/// Implemented by an [NskeyKeyRing] that can say when a private half arrives.
///
/// A conveyed private is filed asynchronously, so a notification sealed to that
/// generation can arrive before the key that opens it. The signal fires at the
/// filing point rather than at the arrival of the secret, because a start-time
/// sweep consumes waiting secrets before any per-secret stream exists.
abstract interface class SignalsPrivateFiling {
  /// Fires once per private half filed, after it is stored and readable.
  ///
  /// Broadcast, so a late subscriber misses earlier events.
  Stream<FiledNskeyPrivate> get privatesFiled;
}

/// Selects and configures the crypto providers for an [AtClient].
class CryptoConfig {
  /// Provider used when an [AtKey] carries no `appMetadata.providerId`.
  final String defaultProviderId;

  /// The provider instances the SDK resolves against, in addition to the
  /// built-in legacy provider.
  ///
  /// Providers are stateless, so an instance is normally safe to share. Supply
  /// a fresh instance per atSign only if your provider holds per-atSign state —
  /// the same config can back any client that reuses this preference.
  final List<CryptoProvider> providers;

  /// The namespace key material these providers share, when there is any.
  ///
  /// Held on the config as well as inside the providers so that a collaborator
  /// outside the crypto path can reach it — [SignalsPrivateFiling] included —
  /// without depending on which providers happen to be registered.
  final NskeyKeyRing? keyRing;

  /// Asked, on the write path, whether the content key for a destination and
  /// namespace should be replaced before anything else is written under it.
  ///
  /// Answered per namespace, and independently of [nskeyRotationPolicy].
  /// Defaults to [rotateCkAfterOneWeek].
  final CkRotationPolicy ckRotationPolicy;

  /// Asked whether a namespace key this atSign owns should be replaced.
  ///
  /// Defaults to [neverRotateNskey]: replacing one costs a conveyance to every
  /// authorised enrollment and makes every peer cut a fresh content key, so
  /// nothing in the SDK fires it on a schedule.
  final NskeyRotationPolicy nskeyRotationPolicy;

  const CryptoConfig({
    required this.defaultProviderId,
    this.providers = const [],
    this.keyRing,
    this.ckRotationPolicy = rotateCkAfterOneWeek,
    this.nskeyRotationPolicy = neverRotateNskey,
  });

  /// Legacy-only — the default for un-migrated apps.
  const CryptoConfig.legacy()
      : defaultProviderId = legacyCryptoProviderId,
        providers = const [],
        keyRing = null,
        ckRotationPolicy = rotateCkAfterOneWeek,
        nskeyRotationPolicy = neverRotateNskey;

  /// The distinguished "the app named nothing" marker — the default value of
  /// [AtClientPreference.crypto].
  ///
  /// The field is non-nullable, so this const instance is how the SDK tells
  /// "the app chose a config" from "the app left the default": [forClient]
  /// treats it as no choice and resolves the per-client era default instead,
  /// while assigning any other config — [CryptoConfig.legacy] included — is an
  /// explicit opt-out. Read directly rather than through [forClient], it
  /// behaves exactly as [CryptoConfig.legacy].
  const factory CryptoConfig.eraDefault() = _EraDefaultSentinel;

  /// The nskey data path: application data under `at/symmetric/AES/GCM`, content
  /// keys conveyed by `at/nskey`, and the CK manager that mints one the first
  /// time a destination is written to.
  ///
  /// The SDK assembles the set because the parts are not independent — the
  /// manager and both providers must share **one** [ContentKeyCache], or a
  /// conveyance caches a CK the data provider then cannot find. A fresh set
  /// comes back per call, and each atSign needs its own, because that cache is
  /// per-atSign state.
  ///
  /// [keyRing] supplies the namespace key material. [sealsToKeyAlgorithms] is
  /// which of a destination's advertised KEM keys this client will seal to —
  /// `AtClientPreference.sealsToKeyAlgorithms` — defaulted to everything this
  /// build can seal under, which refuses nobody.
  factory CryptoConfig.nskey(
          {required NskeyKeyRing keyRing,
          List<String> sealsToKeyAlgorithms = SecretSharingAlgos.keyAlgos,
          CkRotationPolicy ckRotationPolicy = rotateCkAfterOneWeek,
          NskeyRotationPolicy nskeyRotationPolicy = neverRotateNskey}) =>
      _nskeySet(keyRing, symmetricAesGcmCryptoProviderId, sealsToKeyAlgorithms,
          ckRotationPolicy, nskeyRotationPolicy);

  /// The nskey providers wired for **reading**, with writes still going out
  /// under [legacyCryptoProviderId].
  ///
  /// Reading is *additive* — a record routes to the provider stamped on it,
  /// so a client that cannot resolve that id fails on data someone already
  /// sent it — while moving the write default is a fleet-wide commitment,
  /// since the first client to write post-quantum produces records every
  /// other client must already be able to read.
  factory CryptoConfig.readsNskeyWritesLegacy(
          {required NskeyKeyRing keyRing,
          List<String> sealsToKeyAlgorithms = SecretSharingAlgos.keyAlgos,
          CkRotationPolicy ckRotationPolicy = rotateCkAfterOneWeek,
          NskeyRotationPolicy nskeyRotationPolicy = neverRotateNskey}) =>
      _nskeySet(keyRing, legacyCryptoProviderId, sealsToKeyAlgorithms,
          ckRotationPolicy, nskeyRotationPolicy);

  /// One [ContentKeyCache] shared by the manager and both providers.
  static CryptoConfig _nskeySet(
      NskeyKeyRing keyRing,
      String defaultProviderId,
      List<String> sealsToKeyAlgorithms,
      CkRotationPolicy ckRotationPolicy,
      NskeyRotationPolicy nskeyRotationPolicy) {
    final cache = ContentKeyCache();
    return CryptoConfig(
      defaultProviderId: defaultProviderId,
      keyRing: keyRing,
      ckRotationPolicy: ckRotationPolicy,
      nskeyRotationPolicy: nskeyRotationPolicy,
      providers: [
        // NOTE: both KEM providers are registered on every client whatever
        // this atSign mints — the KEM is the recipient's choice, and a read
        // routes by the id the record carries.
        NskeyProvider(
            keyRing: keyRing, cache: cache, keyAlgo: SecretSharingAlgos.xWing),
        NskeyProvider(
            keyRing: keyRing,
            cache: cache,
            keyAlgo: SecretSharingAlgos.mlKem1024),
        SymmetricAesGcmProvider(
          cache: cache,
          ckManager: CkManager(
              cache: cache,
              keyRing: keyRing,
              sealsToKeyAlgorithms: sealsToKeyAlgorithms,
              ckRotationPolicy: ckRotationPolicy),
        ),
      ],
    );
  }

  /// The config [atClient] encrypts under — the app's if it named one, else
  /// the SDK's default for this release.
  ///
  /// The era default is chosen from the client's `PqPosture` at construction
  /// and adopted by [adoptEraDefault]: [CryptoConfig.legacy] where
  /// `configuresPqProviders` is false, [CryptoConfig.readsNskeyWritesLegacy]
  /// where `writesPqByDefault` is false, and [CryptoConfig.nskey] otherwise.
  /// A client that was never given one falls back to [CryptoConfig.legacy]
  /// rather than assembling a set here, because building one needs the client
  /// and this is also called *during* construction.
  static CryptoConfig forClient(AtClient? atClient) {
    final named = atClient?.getPreferences()?.crypto;
    if (named != null && named is! _EraDefaultSentinel) return named;
    if (atClient == null) return const CryptoConfig.legacy();
    return _eraDefaults.of(atClient) ?? const CryptoConfig.legacy();
  }

  /// Per-client era defaults, held beside the client and never resolved into
  /// the shared preference object.
  static final EraDefaults<CryptoConfig> _eraDefaults =
      EraDefaults<CryptoConfig>();

  /// Gives [atClient] the era's default config, unless the app named its own.
  /// Idempotent — a re-used cached client keeps the set it was built with, so
  /// its content-key cache and key ring survive re-creation.
  static void adoptEraDefault(AtClient atClient, CryptoConfig config) {
    final named = atClient.getPreferences()?.crypto;
    if (named != null && named is! _EraDefaultSentinel) return;
    _eraDefaults.adoptIfAbsent(atClient, config);
  }

  /// The era default [atClient] holds, or null if it was never given one.
  @visibleForTesting
  static CryptoConfig? eraDefaultFor(AtClient atClient) =>
      _eraDefaults.of(atClient);

  /// Forgets [atClient]'s era default, so a test can rebuild a client's
  /// crypto world from scratch.
  @visibleForTesting
  static void clearEraDefault(AtClient atClient) =>
      _eraDefaults.clear(atClient);

  /// The content-key cache this config's nskey providers share, or null for a
  /// config that has none (the legacy set, or a caller's own providers).
  ///
  /// Read back from the provider that owns it rather than held as a field, so
  /// that the providers built together cannot drift onto different caches.
  ContentKeyCache? get contentKeyCache {
    for (final provider in providers) {
      if (provider is NskeyProvider) return provider.cache;
    }
    return null;
  }

  /// The [CkManager] the configured providers share, or null if this config
  /// has no nskey data path.
  CkManager? get ckManager {
    for (final provider in providers) {
      if (provider is SymmetricAesGcmProvider) return provider.ckManager;
    }
    return null;
  }

  /// The configured provider with [id], or null if none matches.
  ///
  /// The built-in legacy provider is not in [providers]; the SDK supplies it as
  /// a fallback for [legacyCryptoProviderId], so a null result for that id
  /// still resolves.
  CryptoProvider? lookup(String id) {
    for (final provider in providers) {
      if (provider.id == id) return provider;
    }
    return null;
  }
}

/// The marker type behind [CryptoConfig.eraDefault], private so that the type
/// check can never collide with a caller-built config.
class _EraDefaultSentinel extends CryptoConfig {
  const _EraDefaultSentinel()
      : super(defaultProviderId: legacyCryptoProviderId);
}

/// What a [CryptoProvider] is handed per operation.
class CryptoContext {
  /// The fully-wired client. A provider uses it to fetch whatever it needs to
  /// complete an operation — a recipient's public key, a shared key, a
  /// namespace key from the secondary, etc. The current atSign is
  /// `atClient.getCurrentAtSign()`.
  final AtClient atClient;

  /// The client's key source (ratified atsign-foundation/at_client_sdk#2045):
  /// an `AtKeysIo` (`package:at_auth`) whose `read(atSign)` yields the
  /// client's `AtKeys`. Sourced from [AtClient.atKeysIo], injected at client
  /// construction (`AtClientImpl.create(atKeysIo:)`). Null until an app
  /// injects one — store wiring (so this is populated by default) lands in a
  /// later project. The built-in legacy provider deliberately does not read
  /// this yet.
  final AtKeysIo? atKeysIo;

  const CryptoContext({required this.atClient, this.atKeysIo});
}

/// The contract every encryption scheme implements. The SDK routes each
/// [AtKey] to a provider by its `appMetadata.providerId`.
///
/// Providers are **stateless**: everything they need is handed in per call via
/// [context] (the client) and [atKey] (the record and its metadata), so a
/// single instance is safely shared across atSigns.
abstract class CryptoProvider {
  /// Stable wire id, stamped into `appMetadata.providerId`.
  String get id;

  /// Encrypt [plaintext] for [atKey], returning the wire ciphertext.
  ///
  /// The SDK owns routing metadata: after this returns it stamps
  /// `atKey.metadata.appMetadata.providerId` (to this provider's [id]) and sets
  /// `isEncrypted`, so you can't accidentally break read-routing. To carry
  /// per-record data you'll need on [decrypt] (an IV, a key id, a format
  /// version, …), set `atKey.metadata.appMetadata` with those entries in
  /// [AppMetadata.additional]; they travel with the record (as atServer-visible
  /// plaintext metadata) and are readable on [decrypt].
  ///
  /// [plaintext] is opaque: for binary records it is a `Base2e15`-encoded
  /// string, not human-readable text — treat it as bytes, don't assume UTF-8.
  /// [context] gives access to the client (and, later, key material). Throw an
  /// [AtException] subclass (e.g. [AtEncryptionException]) on failure so the SDK
  /// can chain diagnostics.
  Future<String> encrypt(CryptoContext context, AtKey atKey, String plaintext);

  /// Decrypt wire [ciphertext] for [atKey], returning the plaintext.
  ///
  /// Read any per-record data you stored on [encrypt] from
  /// `atKey.metadata.appMetadata.additional`. The returned plaintext is opaque
  /// (a `Base2e15`-encoded string for binary records). Throw an [AtException]
  /// subclass (e.g. [AtDecryptionException]) on failure.
  Future<String> decrypt(CryptoContext context, AtKey atKey, String ciphertext);
}

/// Implemented by a [CryptoProvider] that needs to do work — including writing
/// records of its own — *before* the write pipeline starts.
///
/// [CryptoProvider.encrypt] runs inside the request transformer, part-way
/// through building a verb builder, so a provider cannot issue its own `put`
/// from there without re-entering the pipeline on a half-built request. The SDK
/// calls [prepareForWrite] ahead of that, with the fully resolved [AtKey] and
/// nothing yet in flight.
abstract interface class PreparesWrites {
  /// Prepare for a write of [atKey].
  ///
  /// A provider issuing a write from here must ensure that write does not
  /// itself need preparing, or the recursion will not terminate.
  ///
  /// [useRemoteAtServer] is how the *outer* write is being routed. A provider
  /// writing a record the outer value will depend on must route it the same
  /// way: a local-first record cannot satisfy a value that went straight to
  /// the atServer, because it does not arrive until the next sync. Null means
  /// the caller expressed no preference and the client default applies.
  Future<void> prepareForWrite(CryptoContext context, AtKey atKey,
      {bool? useRemoteAtServer});
}

/// Implemented by a [CryptoProvider] that can only handle some keys.
///
/// A provider that declines is skipped **at write-time selection only**: a
/// record already stamped with its id always routes back to it on read, because
/// that is the only thing that can open it.
abstract interface class HandlesSelectively {
  /// Whether this provider can encrypt [atKey].
  bool canHandle(AtKey atKey);
}

/// Implemented by a [CryptoProvider] whose ability to encrypt for a destination
/// depends on something that destination must have published.
///
/// Sealing to a recipient-published key has an answerable precondition, so an
/// app can ask before the user composes rather than reporting a failed write
/// afterwards.
abstract interface class ReportsReadiness {
  /// Whether this provider could encrypt for [atSign] in [namespace] right now.
  ///
  /// Throws rather than answering false when the answer cannot be established:
  /// an unreachable atServer is not the same as a recipient who has not enabled
  /// the namespace.
  Future<bool> isReadyFor(
      CryptoContext context, String atSign, String namespace);
}
