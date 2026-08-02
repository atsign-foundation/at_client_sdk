import 'package:at_auth/at_auth.dart' show AtKeysIo;
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_commons/at_commons.dart';

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
  Future<void> prepareForWrite(CryptoContext context, AtKey atKey);
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
