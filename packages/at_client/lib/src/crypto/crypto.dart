import 'package:at_auth/at_auth.dart' show AtKeysIo;
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/nskey/ck_manager.dart';
import 'package:at_client/src/crypto/nskey/content_key.dart';
import 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
import 'package:at_client/src/crypto/nskey/nskey_provider.dart';
import 'package:at_client/src/crypto/nskey/nskey_resolver.dart';
import 'package:at_client/src/crypto/nskey/symmetric_aes_gcm_provider.dart';
import 'package:at_commons/at_commons.dart';

// The nskey data path is part of this library's public surface: it is what
// `CryptoConfig.nskey` takes and returns, and what a caller catches and names.
// Importing without re-exporting left `NskeyKeyRing` — a *required* parameter
// on an exported factory — and `ContentKeyUnavailableException`, which the
// CHANGELOG tells callers to catch, unreachable through the package barrel.
export 'package:at_client/src/crypto/nskey/ck_manager.dart';
export 'package:at_client/src/crypto/nskey/content_key.dart';
export 'package:at_client/src/crypto/nskey/conveyed_key_collection.dart';
export 'package:at_client/src/crypto/nskey/nskey_private_filing.dart';
export 'package:at_client/src/crypto/nskey/nskey_key_ring.dart';
export 'package:at_client/src/crypto/nskey/nskey_provider.dart';
export 'package:at_client/src/crypto/nskey/nskey_resolver.dart';
export 'package:at_client/src/crypto/nskey/pq_signing_chain.dart';
export 'package:at_client/src/crypto/nskey/pq_signing_root.dart';
export 'package:at_client/src/crypto/nskey/published_nskey_key_ring.dart';
export 'package:at_client/src/crypto/nskey/symmetric_aes_gcm_provider.dart';

/// The id of the built-in legacy (pre-pluggable) encryption scheme — the
/// default provider and the fallback for records with no `appMetadata`.
const String legacyCryptoProviderId = 'legacy';

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
  factory CryptoConfig.nskey({required NskeyKeyRing keyRing}) {
    final cache = ContentKeyCache();
    return CryptoConfig(
      defaultProviderId: symmetricAesGcmCryptoProviderId,
      providers: [
        NskeyProvider(keyRing: keyRing, cache: cache),
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
  /// Today that default is [CryptoConfig.legacy]. When it becomes the nskey
  /// data path, this stops being a constant: [CryptoConfig.nskey] holds
  /// per-atSign state and must be built once per client, so the resolution
  /// moves to client construction and this becomes a lookup of what was built.
  /// It is written as a function now so that change lands in one place.
  static CryptoConfig forClient(AtClient? atClient) =>
      atClient?.getPreferences()?.crypto ?? const CryptoConfig.legacy();

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
