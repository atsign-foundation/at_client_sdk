import 'package:at_auth/at_auth.dart' show AtKeysIo;
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/nskey/ck_manager.dart';
import 'package:at_client/src/crypto/nskey/content_key.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_client/src/crypto/nskey/nskey_provider.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show symmetricAesGcmCryptoProviderId;
import 'package:at_client/src/crypto/nskey/symmetric_aes_gcm_provider.dart';
import 'package:at_client/src/secret_sharing/algo_ids.dart'
    show SecretSharingAlgos;
import 'package:at_commons/at_commons.dart';
import 'package:meta/meta.dart' show visibleForTesting;

// The nskey data path is part of this library's public surface: it is what
// `CryptoConfig.nskey` takes and returns, and what a caller catches and names.
// Importing without re-exporting left `NskeyKeyRing` — a *required* parameter
// on an exported factory — and `ContentKeyUnavailableException`, which the
// CHANGELOG tells callers to catch, unreachable through the package barrel.
export 'package:at_client/src/crypto/nskey/ck_manager.dart';
export 'package:at_client/src/crypto/nskey/content_key.dart';
export 'package:at_client/src/crypto/nskey/content_key_eviction.dart';
export 'package:at_client/src/crypto/nskey/conveyed_key_collection.dart';
export 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
export 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
export 'package:at_client/src/crypto/nskey/nskey_provider.dart';
// Of the wire vocabulary, only the advertisement builder and the provider
// ids are public surface (readers address the published record; callers and
// the CHANGELOG name providers by id). The record-name constants and the
// other builders stay internal.
export 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show
        mlKemNskeyCryptoProviderId,
        nskeyAdvertisementKey,
        nskeyCryptoProviderId,
        nskeyProviderFamily,
        symmetricAesGcmCryptoProviderId;
export 'package:at_client/src/crypto/nskey/nskey_resolver.dart';
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
/// Not a failure of anything: the data path worked, the destination is simply
/// only reachable under a scheme a quantum computer will one day open. An app
/// that catches this can tell its user the recipient cannot be reached
/// securely — which is the whole point of asking to be refused rather than
/// silently downgraded.
class LegacyEncryptionRefusedException extends AtEncryptionException {
  /// The record that would have been written legacy.
  final String key;

  LegacyEncryptionRefusedException(this.key, String reason)
      : super('refusing to encrypt $key with the legacy provider: $reason. '
            'This client sets disallowLegacyEncryption, so a destination no '
            'post-quantum scheme can reach is refused rather than written in '
            'one that can be harvested now and opened later.');
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

  const CryptoConfig({
    required this.defaultProviderId,
    this.providers = const [],
  });

  /// Legacy-only — the default for un-migrated apps.
  const CryptoConfig.legacy()
      : defaultProviderId = legacyCryptoProviderId,
        providers = const [];

  /// The nskey data path: application data under `at/symmetric/AES/GCM`, content
  /// keys conveyed by `at/nskey`, and the CK manager that mints one the first
  /// time a destination is written to.
  ///
  /// The SDK assembles it because the parts are not independent — the manager
  /// and both providers must share **one** [ContentKeyCache], or a conveyance
  /// caches a CK the data provider then cannot find. Leaving that to callers
  /// makes a silent misconfiguration easy and a working one boilerplate.
  ///
  /// Returns a **fresh set per call**, so give each atSign its own: these
  /// providers hold per-atSign state, which is the case
  /// [CryptoConfig.providers] documents as needing a per-atSign instance.
  ///
  /// [keyRing] supplies the namespace key material. Until the secret-sharing
  /// substrate delivers it, that is a fixture.
  factory CryptoConfig.nskey({required NskeyKeyRing keyRing}) =>
      _nskeySet(keyRing, symmetricAesGcmCryptoProviderId);

  /// The nskey providers wired for **reading**, with writes still going out
  /// under [legacyCryptoProviderId].
  ///
  /// This is the final-3.x era shape, and the release sequence is what makes it
  /// the right one: a 3.x client *reads* PQ records, mints and publishes its
  /// namespace keys and its signing root, and still writes legacy; 4.x is what
  /// makes PQ the write default. Registering the provider set without moving
  /// [defaultProviderId] is exactly that sentence in code.
  ///
  /// The asymmetry is deliberate rather than transitional sloppiness. Reading
  /// is *additive* — a record arrives stamped with the provider that wrote it,
  /// so a client that cannot resolve that id fails on data someone already
  /// sent it. Writing is a fleet-wide commitment: the first client to write PQ
  /// produces records every other client must already be able to read. So the
  /// read side goes first everywhere, and the write side flips once.
  factory CryptoConfig.readsNskeyWritesLegacy(
          {required NskeyKeyRing keyRing}) =>
      _nskeySet(keyRing, legacyCryptoProviderId);

  /// One [ContentKeyCache] shared by the manager and both providers — the
  /// coupling [CryptoConfig.nskey] exists to enforce.
  static CryptoConfig _nskeySet(
      NskeyKeyRing keyRing, String defaultProviderId) {
    final cache = ContentKeyCache();
    return CryptoConfig(
      defaultProviderId: defaultProviderId,
      providers: [
        // One conveyance provider per key-establishment algorithm, each with
        // its own wire id. Reads route by the id the record carries, so a
        // conveyance written under either KEM keeps opening; writes are routed
        // by CkManager from the destination's advertised algorithm. Both are
        // registered on every client regardless of what this atSign mints,
        // because a *recipient's* KEM is the recipient's choice.
        NskeyProvider(
            keyRing: keyRing,
            cache: cache,
            keyAlgo: SecretSharingAlgos.xWing),
        NskeyProvider(
            keyRing: keyRing,
            cache: cache,
            keyAlgo: SecretSharingAlgos.mlKem1024),
        SymmetricAesGcmProvider(
          cache: cache,
          ckManager: CkManager(cache: cache, keyRing: keyRing),
        ),
      ],
    );
  }

  /// The config [atClient] encrypts under — the app's if it named one, else
  /// the SDK's default for this release.
  ///
  /// **The single place the era default lives.** `AtClientPreference.crypto` is
  /// nullable precisely so this decision belongs to the SDK: an app that had to
  /// name a config just to have one would be pinned to whatever was current on
  /// the day it was written, and would sit out the migration it was supposed to
  /// ride. Moving the default is therefore an edit here and nowhere else.
  ///
  /// The era default is now [CryptoConfig.readsNskeyWritesLegacy], built once
  /// per client by [adoptEraDefault] at construction and looked up here. It
  /// stopped being a constant because the nskey providers hold per-atSign state
  /// (a [ContentKeyCache], a key ring bound to one client), so one shared
  /// instance would let two atSigns read each other's cached content keys.
  ///
  /// A client that was never given an era default — one built before
  /// [adoptEraDefault] ran, or a test double — falls back to
  /// [CryptoConfig.legacy] rather than assembling a set here, because building
  /// one needs the client and this is also called *during* construction.
  static CryptoConfig forClient(AtClient? atClient) {
    final named = atClient?.getPreferences()?.crypto;
    if (named != null) return named;
    if (atClient == null) return const CryptoConfig.legacy();
    return _eraDefaults[atClient] ?? const CryptoConfig.legacy();
  }

  /// Per-client era defaults. An [Expando] rather than a field on the
  /// preference object: the SDK must not resolve its own default *into* the
  /// app's preference, because a preference is routinely shared across atSigns
  /// and this value is per-atSign the moment it stops being a const.
  static final Expando<CryptoConfig> _eraDefaults =
      Expando('CryptoConfig.eraDefault');

  /// Gives [atClient] the era's default config, unless the app named its own.
  /// Idempotent — a re-used cached client keeps the set it was built with, so
  /// its content-key cache and key ring survive re-creation.
  static void adoptEraDefault(AtClient atClient, CryptoConfig config) {
    if (atClient.getPreferences()?.crypto != null) return;
    _eraDefaults[atClient] ??= config;
  }

  /// The era default [atClient] holds, or null if it was never given one.
  @visibleForTesting
  static CryptoConfig? eraDefaultFor(AtClient atClient) =>
      _eraDefaults[atClient];

  /// The content-key cache this config's nskey providers share, or null for a
  /// config that has none (the legacy set, or a caller's own providers).
  ///
  /// The cache is deliberately not a field: [_nskeySet] builds one and hands
  /// it to both providers precisely so they cannot drift apart, and exposing a
  /// settable copy alongside them would reintroduce the drift. This reads it
  /// back from the provider that owns it, for the one caller that has to reach
  /// it from outside — the sync listener that evicts a content key when its
  /// conveyance record is deleted.
  ContentKeyCache? get contentKeyCache {
    for (final provider in providers) {
      if (provider is NskeyProvider) return provider.cache;
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
///
/// This is a separate interface rather than a method on [CryptoProvider] so that
/// adding it does not break existing `implements CryptoProvider` code. The SDK
/// checks for it with `is` and skips providers that do not need it.
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
/// `defaultProviderId` applies to *every* encrypted write, including the SDK's
/// own internal keys — which carry no namespace. A scheme scoped to
/// `(owner, namespace)`, as the nskey data path is, genuinely cannot serve those,
/// and silently writing something it cannot read back is worse than declining.
///
/// A provider that declines is skipped **at write-time selection only**: a record
/// already stamped with its id always routes back to it on read, because that is
/// the only thing that can open it.
///
/// Separate from [CryptoProvider] so adding it breaks no existing
/// `implements CryptoProvider`.
abstract interface class HandlesSelectively {
  /// Whether this provider can encrypt [atKey].
  bool canHandle(AtKey atKey);
}

/// Implemented by a [CryptoProvider] whose ability to encrypt for a destination
/// depends on something that destination must have published.
///
/// Without this, an app finds out only when the write fails — after the user
/// has composed and sent. A scheme that seals to a recipient-published key has
/// a real, answerable precondition, so it should be askable *before* the user
/// starts rather than reported as an error afterwards.
///
/// Separate from [CryptoProvider] so adding it breaks no existing
/// `implements CryptoProvider`.
abstract interface class ReportsReadiness {
  /// Whether this provider could encrypt for [atSign] in [namespace] right now.
  ///
  /// Throws rather than answering false when the answer cannot be established —
  /// an unreachable atServer is not the same as a recipient who has not enabled
  /// the namespace, and reporting one as the other would send an app down the
  /// wrong path.
  Future<bool> isReadyFor(
      CryptoContext context, String atSign, String namespace);
}
