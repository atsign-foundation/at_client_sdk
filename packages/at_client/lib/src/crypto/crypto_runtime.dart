import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/legacy/legacy_crypto_provider.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_logger.dart';

final AtSignLogger _logger = AtSignLogger('CryptoRuntime');

/// Routes encryption/decryption to the [CryptoProvider] named by an [AtKey]'s
/// `appMetadata.providerId`.
class CryptoRuntime {
  static const String legacyProviderId = legacyCryptoProviderId;

  final AtClient _atClient;

  CryptoRuntime(this._atClient);

  /// The resolve/stamp/prepare sequence every encrypting write path runs
  /// before composing anything: resolves the provider this write will use
  /// ([providerIdFor]), stamps it into the key's `appMetadata` when the key
  /// carries none, and gives the provider its pre-write step
  /// ([prepareForPut]). Returns the resolved provider id.
  ///
  /// A provider that has to write a record of its own — a key conveyance —
  /// cannot do it from inside `encrypt`, which is called part-way through
  /// building a verb builder; this runs while nothing is in flight.
  ///
  /// [useRemoteAtServer] carries how this write is being routed, so a record
  /// the provider writes travels the same route as the write that will cite
  /// it. A notification passes `true` unconditionally: it is remote-only by
  /// construction, so a conveyance left to reach the atServer by sync would
  /// be announced before it exists.
  ///
  /// [stampProviderId] exists for the one caller that must NOT stamp early:
  /// the put pre-pass, whose catch may re-route the write to legacy when the
  /// prepare step finds the recipient has no post-quantum key. A key already
  /// stamped with the provider that then declined would claim a scheme its
  /// value was never sealed under.
  Future<String> prepareWrite(AtKey atKey,
      {String? requestedProviderId,
      bool? useRemoteAtServer,
      bool stampProviderId = true}) async {
    final providerId =
        providerIdFor(_atClient, requestedProviderId, atKey: atKey);
    if (stampProviderId) {
      atKey.metadata.appMetadata ??= AppMetadata(providerId: providerId);
    }
    await prepareForPut(atKey, providerId,
        useRemoteAtServer: useRemoteAtServer);
    return providerId;
  }

  /// Give the provider that will handle this write a chance to act *before* the
  /// pipeline starts — see [PreparesWrites]. Providers that do not implement it
  /// are skipped, which is nearly all of them.
  ///
  /// [providerId] is resolved from the request options rather than from the
  /// key's `appMetadata`, because at this point nothing has stamped it yet.
  ///
  /// [useRemoteAtServer] carries how this write is being routed, so a provider
  /// writing a record the write will depend on can route it the same way.
  Future<void> prepareForPut(AtKey atKey, String providerId,
      {bool? useRemoteAtServer}) async {
    final config = CryptoConfig.forClient(_atClient);
    final provider = config.lookup(providerId);
    if (provider is PreparesWrites) {
      await (provider as PreparesWrites).prepareForWrite(_context(), atKey,
          useRemoteAtServer: useRemoteAtServer);
    }
  }

  /// Whether a write to [atSign] in [namespace] can go out under this client's
  /// default scheme, asked *before* anything is composed.
  ///
  /// A post-quantum share needs the recipient to have published a key for the
  /// namespace, and there is no fallback that keeps it post-quantum. An app
  /// that asks first can say "@bob hasn't enabled this yet" up front, instead
  /// of discovering it when the send fails. Schemes with no such precondition —
  /// legacy among them — answer true.
  ///
  /// Throws if the answer cannot be established (an unreachable atServer is not
  /// the same as an unready recipient), and — like every other read of a peer's
  /// advertised key — if what came back cannot be verified as theirs.
  Future<bool> isReadyFor(String atSign, String namespace) async {
    final config = CryptoConfig.forClient(_atClient);
    final provider = config.lookup(config.defaultProviderId);
    if (provider is! ReportsReadiness) return true;
    return await (provider as ReportsReadiness)
        .isReadyFor(_context(), atSign, namespace);
  }

  /// The provider id a write will use, before anything has stamped the key.
  ///
  /// When [atKey] is supplied and the selected provider declines it
  /// ([HandlesSelectively]), a *defaulted* id falls back to legacy — the nskey
  /// data path is `(owner, namespace)`-scoped and cannot serve the SDK's
  /// namespace-less internal keys, and writing something it could not read back
  /// is worse than declining. An *explicitly requested* id does not fall back:
  /// the caller asked for a scheme that cannot handle this key, and quietly
  /// doing something else is how you end up thinking data is PQ when it is not.
  static String providerIdFor(AtClient atClient, String? requested,
      {AtKey? atKey}) {
    final config = CryptoConfig.forClient(atClient);
    final id = requested ?? config.defaultProviderId;
    if (atKey == null) return id;
    if (id == legacyProviderId) {
      refuseLegacyIfDisallowed(atClient, atKey, id,
          because: requested != null
              ? 'it was requested explicitly'
              : 'this client is configured to write legacy');
      return id;
    }

    final provider = config.lookup(id);
    if (provider is HandlesSelectively &&
        !(provider as HandlesSelectively).canHandle(atKey)) {
      if (requested != null) {
        throw AtEncryptionException(
            'Crypto provider "$id" cannot handle ${atKey.key} — it was '
            'requested explicitly, so no fallback was applied.');
      }
      refuseLegacyIfDisallowed(atClient, atKey, legacyProviderId,
          because: 'the configured provider "$id" cannot handle this key, and '
              'the fallback is legacy');
      _logger.finer(
          'default provider "$id" declined ${atKey.key}; using $legacyProviderId');
      return legacyProviderId;
    }
    return id;
  }

  /// Throw if [providerId] is the legacy provider and [atClient] set
  /// [AtClientPreference.disallowLegacyEncryption].
  ///
  /// Called at selection time ([providerIdFor]), where the error is actionable
  /// and nothing is in flight, **and** again at encryption time. The second is
  /// not redundant: it is the point every encrypting write passes through
  /// however the id was chosen, so the guarantee does not depend on each call
  /// path having remembered to ask.
  static void refuseLegacyIfDisallowed(
      AtClient atClient, AtKey atKey, String providerId,
      {required String because}) {
    if (providerId != legacyProviderId) return;
    // A `local:` record is never transmitted, so the harvest-now-decrypt-later
    // premise this flag exists for has no referent: there is no destination,
    // and no ciphertext an adversary can capture to open later. What "legacy"
    // resolves to for such a key is [SelfKeyEncryption] — AES-256-CTR under a
    // key that never leaves the device — which is not Shor-vulnerable anyway.
    //
    // Deliberately keyed on `isLocal` and not on "lands on SelfKeyEncryption":
    // a *synced* self key IS held by the atServer and so IS harvestable, and
    // what to do about those belongs to the retirement of the legacy self and
    // shared key material, not here.
    if (atKey.isLocal) return;
    if (atClient.getPreferences()?.disallowLegacyEncryption != true) return;
    throw LegacyEncryptionRefusedException(atKey.key, because);
  }

  Future<String> encryptForPut(AtKey atKey, dynamic value) async {
    try {
      final provider = _provider(atKey, 'put');
      refuseLegacyIfDisallowed(_atClient, atKey, provider.id,
          because: 'the write reached encryption still routed to legacy');
      final ciphertext =
          await provider.encrypt(_context(), atKey, _requireString(value));
      return _stampEncrypted(atKey, provider, ciphertext);
    } on AtException catch (e) {
      e.stack(
        AtChainedException(
          Intent.shareData,
          ExceptionScenario.encryptionFailed,
          'Failed to encrypt the data',
        ),
      );
      rethrow;
    }
  }

  Future<String> encryptForNotification(AtKey atKey, dynamic value) async {
    try {
      final provider = _provider(atKey, 'notify');
      refuseLegacyIfDisallowed(_atClient, atKey, provider.id,
          because: 'the notification reached encryption still routed to '
              'legacy');
      final ciphertext =
          await provider.encrypt(_context(), atKey, _requireString(value));
      return _stampEncrypted(atKey, provider, ciphertext);
    } on AtException catch (e) {
      e.stack(
        AtChainedException(
          Intent.notifyData,
          ExceptionScenario.encryptionFailed,
          e.message,
        ),
      );
      rethrow;
    }
  }

  Future<dynamic> decryptForGet(AtKey atKey, dynamic value) =>
      _decrypt(atKey, value, 'get');

  Future<dynamic> decryptForSyncConflict(AtKey atKey, dynamic value) =>
      _decrypt(atKey, value, 'sync conflict');

  Future<dynamic> decryptForNotification(AtKey atKey, dynamic value) async {
    try {
      return await _decrypt(atKey, value, 'notify');
    } on AtException catch (e) {
      e.stack(
        AtChainedException(
          Intent.notifyData,
          ExceptionScenario.encryptionFailed,
          e.message,
        ),
      );
      rethrow;
    }
  }

  Future<dynamic> _decrypt(AtKey atKey, dynamic value, String operation) {
    // A null ciphertext (e.g. a notification with no value) is passed to the
    // provider as '' so it surfaces the provider's own "encrypted value is
    // null" error rather than a raw cast TypeError.
    return _provider(atKey, operation)
        .decrypt(_context(), atKey, (value as String?) ?? '');
  }

  // The built-in fallback, always available for [legacyProviderId] without the
  // app having to list it in CryptoConfig.providers.
  static final LegacyCryptoProvider _legacy = LegacyCryptoProvider();

  CryptoProvider _provider(AtKey atKey, String operation) {
    final providerId =
        atKey.metadata.appMetadata?.providerId ?? legacyProviderId;
    final config = CryptoConfig.forClient(_atClient);
    final provider = config.lookup(providerId);
    if (provider != null) return provider;
    if (providerId == legacyProviderId) return _legacy;
    throw CryptoProviderNotRegistered(
      _notRegisteredMessage(config, providerId, operation),
    );
  }

  String _notRegisteredMessage(
    CryptoConfig config,
    String id,
    String lookupReason,
  ) {
    final ids = [legacyProviderId, ...config.providers.map((p) => p.id)];
    return 'Crypto provider "$id" is not registered. '
        'Lookup reason: $lookupReason. '
        'Registered providers: ${ids.join(', ')}. '
        'Add it to AtClientPreference.crypto.providers.';
  }

  // Read live per operation, matching the live preference.crypto resolution
  // in _provider() above — there is no cached CryptoContext.
  CryptoContext _context() =>
      CryptoContext(atClient: _atClient, atKeysIo: _atClient.atKeysIo);

  // The SDK owns routing metadata: a provider contributes only
  // appMetadata.additional; the runtime stamps the provider id and marks the
  // value encrypted, so neither can be silently forgotten and break the read
  // path (a missing isEncrypted would return ciphertext undecrypted).
  String _stampEncrypted(
    AtKey atKey,
    CryptoProvider provider,
    String ciphertext,
  ) {
    atKey.metadata.appMetadata = AppMetadata(
      providerId: provider.id,
      additional: atKey.metadata.appMetadata?.additional,
    );
    atKey.metadata.isEncrypted = true;
    return ciphertext;
  }

  // The provider contract is String-typed; reject a non-String plaintext at
  // the boundary with the same error the value pipeline gave before, rather
  // than silently stringifying it.
  String _requireString(dynamic value) {
    if (value is! String) {
      throw AtEncryptionException(
        'Invalid value type found: ${value.runtimeType}. '
        'Valid value type is String',
      );
    }
    return value;
  }
}
