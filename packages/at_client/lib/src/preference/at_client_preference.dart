import 'package:at_chops/at_chops.dart';
import 'package:meta/meta.dart' show internal, visibleForTesting;
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/crypto/nskey/nskey_records.dart'
    show pqCryptoProviderIds;
import 'package:at_client/src/client/pq_client_bootstrap.dart'
    show PqStartupGates;
import 'package:at_client/src/preference/pq_posture.dart';
import 'package:at_client/src/secret_sharing/algo_ids.dart';
import 'package:at_client/src/signing/envelope_signature.dart'
    show canSignEnvelopeWith;
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_client/src/service/sync_service.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_client/src/preference/at_client_particulars.dart';
import 'package:version/version.dart';

/// Class to hold attributes for client preferences.
/// Set the preferences for your application and pass it to
/// `AtClientManager.setCurrentAtSign`.
class AtClientPreference {
  /// Never encrypt *new* data with the legacy (pre-post-quantum) provider:
  /// take a post-quantum path, or refuse the write.
  ///
  /// ⚠️ Set by [posture] alone — no constructor argument and no setter — and
  /// it overrides [allowLegacyCryptoFallback], which says the opposite.
  final bool disallowLegacyEncryption;

  /// How far into the post-quantum rollout this client runs — every rollout
  /// axis set as a group, and a floor an explicit axis may raise but not lower.
  ///
  /// ⚠️ An existing enrollment holding an authentication key weaker than this
  /// asks for is retrofitted at the next start, with no opt-out; an app that
  /// must not move names [PqPosture.legacy].
  final PqPosture posture;

  /// Which of the post-quantum startup's steps this client runs, or null to
  /// let [posture] decide — every step when it configures post-quantum
  /// providers, none when it does not.
  ///
  /// ⚠️ Read once, by a startup the client's constructor fires unawaited, so
  /// naming a set here is the only way to change it: a set handed to a client
  /// that is already running cannot be applied, which is why
  /// [rolloutDifferencesFrom] reports it.
  @visibleForTesting
  final PqStartupGates? pqStartupGates;

  /// Which post-quantum startup steps this client's bootstrap runs: the set
  /// [pqStartupGates] names, else every step when [posture] configures the
  /// post-quantum providers and none when it does not.
  ///
  /// The one home for that rule — a client reads this rather than deriving it,
  /// and it resolves [pqStartupGates] here because only this library may.
  @internal
  PqStartupGates get resolvedPqStartupGates =>
      pqStartupGates ??
      (posture.configuresPqProviders
          ? const PqStartupGates()
          : const PqStartupGates.inert());

  /// Which algorithms this client keeps an **active signing key** for — the
  /// keys that sign what its enrollment attests to, which is a different job
  /// from the APKAM authentication key that proves possession on a connection.
  ///
  /// ⚠️ Empty is not "unsigned": the enrollment signs with its APKAM
  /// authentication key, whose public half stays published as its signing key.
  final Set<SigningAlgoType> dataSigningKeyAlgorithms;

  /// The algorithm this client's APKAM **authentication** key is minted under
  /// when a retrofit names none — the key that proves possession on a
  /// connection, which only the atServer verifies.
  ///
  /// Not to be confused with [dataSigningKeyAlgorithms], which is what the
  /// enrollment signs *content* with and which every peer verifies.
  final SigningAlgoType authenticationKeyAlgorithm;

  /// The key-establishment algorithms this client will **seal to**, strongest
  /// first — which of a recipient's advertised keys it is willing to use, where
  /// [keyEstablishmentAlgorithms] is what this atSign publishes.
  ///
  /// ⚠️ Narrowing it is choosing to refuse: a recipient advertising only a
  /// dropped algorithm is refused rather than downgraded.
  final List<String> sealsToKeyAlgorithms;

  AtClientPreference(
      {this.posture = PqPosture.legacy,
      this.pqStartupGates,
      SigningAlgoType? authenticationKeyAlgorithm,
      Set<SigningAlgoType>? dataSigningKeyAlgorithms,
      List<String>? sealsToKeyAlgorithms,
      List<String>? keyEstablishmentAlgorithms})
      : disallowLegacyEncryption = posture.disallowLegacyEncryption,
        authenticationKeyAlgorithm =
            authenticationKeyAlgorithm ?? posture.authenticationKeyAlgorithm,
        dataSigningKeyAlgorithms = _signableOrRefuse(
            dataSigningKeyAlgorithms ?? posture.dataSigningKeyAlgorithms),
        sealsToKeyAlgorithms = _sealableOrRefuse(
            sealsToKeyAlgorithms ?? posture.sealsToKeyAlgorithms),
        keyEstablishmentAlgorithms = _advertisableOrRefuse(
            keyEstablishmentAlgorithms ?? posture.keyEstablishmentAlgorithms) {
    seedNamespaceKeys = posture.seedNamespaceKeys;

    // NOTE: in this body a bare parameter name is the caller's nullable value,
    // null exactly when the caller named none, while `this.`-qualified it is
    // the resolved field.

    if (this.dataSigningKeyAlgorithms.isEmpty &&
        this.authenticationKeyAlgorithm != SigningAlgoType.rsa2048) {
      throw ArgumentError.value(
          this.authenticationKeyAlgorithm,
          'authenticationKeyAlgorithm',
          'an enrollment holding no data signing key signs with its '
              'authentication key, and that key is what `_apsk` advertises — so '
              'it must be one the bare form can state, which is rsa2048. Give '
              'dataSigningKeyAlgorithms a member, or authenticate with rsa2048');
    }

    final asked = authenticationKeyAlgorithm;
    if (asked != null &&
        asked != posture.authenticationKeyAlgorithm &&
        SigningAlgoType.strongestOf(
                {asked, posture.authenticationKeyAlgorithm}) ==
            posture.authenticationKeyAlgorithm) {
      throw ArgumentError.value(
          asked,
          'authenticationKeyAlgorithm',
          'is weaker than ${posture.authenticationKeyAlgorithm.name}, which '
              'this posture names. A posture is a floor: name a posture that '
              'wants ${asked.name}, or PqPosture.legacy to stay where you are');
    }
  }

  /// Where [other] would change what a **running** client does — one line per
  /// differing axis, empty when the two are interchangeable.
  ///
  /// Compared by value rather than identity, and only over the axes fixed at
  /// construction: the mutable [seedNamespaceKeys] and [crypto] are excluded.
  List<String> rolloutDifferencesFrom(AtClientPreference other) {
    final differences = <String>[];

    void compare(String axis, Object? asked, Object? running) {
      if (asked != running)
        differences.add('$axis (asked $asked, running $running)');
    }

    compare('posture.writesPqByDefault', other.posture.writesPqByDefault,
        posture.writesPqByDefault);
    compare('posture.configuresPqProviders',
        other.posture.configuresPqProviders, posture.configuresPqProviders);
    compare('posture.keyExchangeMode', other.posture.keyExchangeMode.name,
        posture.keyExchangeMode.name);
    compare('pqStartupGates', other.pqStartupGates, pqStartupGates);
    compare('authenticationKeyAlgorithm', other.authenticationKeyAlgorithm.name,
        authenticationKeyAlgorithm.name);
    compare('disallowLegacyEncryption', other.disallowLegacyEncryption,
        disallowLegacyEncryption);
    // NOTE: order is meaning in both lists — it picks the algorithm — so they
    // are compared as strings rather than as sets.
    compare('sealsToKeyAlgorithms', '${other.sealsToKeyAlgorithms}',
        '$sealsToKeyAlgorithms');
    compare('keyEstablishmentAlgorithms', '${other.keyEstablishmentAlgorithms}',
        '$keyEstablishmentAlgorithms');

    final asked = other.dataSigningKeyAlgorithms;
    final running = dataSigningKeyAlgorithms;
    if (asked.length != running.length || !asked.containsAll(running)) {
      // NOTE: rendered strongest-first because a Set iterates in insertion
      // order, so two equal sets would otherwise print differently.
      String spell(Set<SigningAlgoType> algorithms) =>
          '{${SigningAlgoType.strongestFirst.where(algorithms.contains).map((a) => a.name).join(', ')}}';
      differences.add('dataSigningKeyAlgorithms (asked ${spell(asked)}, '
          'running ${spell(running)})');
    }
    return differences;
  }

  /// [algorithms] unmodifiable, or an [ArgumentError] naming the first member
  /// this build cannot seal under.
  ///
  /// Unmodifiable because the check runs once, and a list the caller retains
  /// would otherwise be a way past it.
  static List<String> _sealableOrRefuse(List<String> algorithms) {
    for (final algorithm in algorithms) {
      if (!SecretSharingAlgos.keyAlgos.contains(algorithm)) {
        throw ArgumentError.value(algorithm, 'sealsToKeyAlgorithms',
            'this build seals to ${SecretSharingAlgos.keyAlgos.join(', ')}');
      }
    }
    return List.unmodifiable(algorithms);
  }

  /// [algorithms] unmodifiable, or an [ArgumentError] — naming the first
  /// member this build cannot mint a key for, or refusing an empty list.
  ///
  /// Empty is refused where [_sealableOrRefuse] permits it: a client that seals
  /// to nothing writes to nobody, while an atSign advertising nothing can
  /// **receive** nothing and looks like a working enrollment that silently
  /// never gets its data.
  static List<String> _advertisableOrRefuse(List<String> algorithms) {
    if (algorithms.isEmpty) {
      throw ArgumentError.value(
          algorithms,
          'keyEstablishmentAlgorithms',
          'an atSign advertising no key-establishment key can receive nothing '
              'sealed to it. Name at least one of '
              '${SecretSharingAlgos.keyAlgos.join(', ')}');
    }
    for (final algorithm in algorithms) {
      if (!SecretSharingAlgos.keyAlgos.contains(algorithm)) {
        throw ArgumentError.value(algorithm, 'keyEstablishmentAlgorithms',
            'this build mints ${SecretSharingAlgos.keyAlgos.join(', ')}');
      }
    }
    return List.unmodifiable(algorithms);
  }

  /// [algorithms] unmodifiable, or an [ArgumentError] naming the first member
  /// this build produces no envelope signature for.
  ///
  /// Unmodifiable because the field is only as final as its contents: an app
  /// holding the set it passed could otherwise add an algorithm afterwards and
  /// get past the check.
  static Set<SigningAlgoType> _signableOrRefuse(
      Set<SigningAlgoType> algorithms) {
    for (final algorithm in algorithms) {
      if (!canSignEnvelopeWith(algorithm)) {
        final signable = SigningAlgoType.strongestFirst
            .where(canSignEnvelopeWith)
            .map((signableAlgorithm) => signableAlgorithm.name)
            .join(', ');
        throw ArgumentError.value(algorithm.name, 'dataSigningKeyAlgorithms',
            'this build signs under $signable');
      }
    }
    return Set.unmodifiable(algorithms);
  }

  /// Local device path of hive storage, used when no [AtClientStorage] is
  /// supplied to [buildAtClient] or [AtClientManager.setCurrentAtSign].
  ///
  /// Setting this leaves the client owning its store: it opens the store and
  /// closes it again when it stops. Supplying a bundle instead chooses the
  /// backend as well as the location, and can hand the lifetime back with
  /// `closedByClient: true`, so nothing is given up by supplying one.
  @Deprecated('Supply an AtClientStorage instead, which chooses the backend as '
      'well as the location; pass closedByClient: true to keep having the '
      'client close it. Will be removed in the next major release.')
  String? hiveStoragePath;

  /// Local device path of commit log.
  ///
  /// Read by nothing: the client keeps no commit log of its own, so whatever
  /// is set here has no effect.
  @Deprecated('Nothing reads this; the client is commit-log-free. Will be '
      'removed in the next major release.')
  String? commitLogPath;

  /// Syncing strategy of the client [SyncStrategy]
  /// [Deprecated] Use [SyncService]
  @Deprecated("Use [SyncService]")
  SyncStrategy? syncStrategy;

  bool _isLocalStoreRequired = true;

  bool get isLocalStoreRequired => _isLocalStoreRequired;

  @Deprecated("LocalStore is always required")
  set isLocalStoreRequired(bool b) => _isLocalStoreRequired = b;

  /// Shared secret of the atSign
  String? cramSecret;

  /// Private key of the atSign
  String? privateKey;

  /// Specifies the namespace of an app.
  String? namespace;

  /// Secret key to encrypt keystore data
  List<int>? keyStoreSecret;

  /// Domain of the root server. Defaults to root.atsign.org
  String rootDomain = 'root.atsign.org';

  /// Port of the root server. Defaults to 64
  int rootPort = 64;

  /// Frequency of sync task to run in minutes. Defaults to 10 minutes.
  int syncIntervalMins = 10;

  /// Idle time in milliseconds of connection to secondary server. Default to 10 minutes.
  int outboundConnectionTimeout = 600000;

  /// The process-wide default network timeout: the maximum wall-clock the SDK
  /// will spend reaching/using the atServer (connect + retries + waiting for a
  /// response) before giving up. When set on the `AtClientPreference` used to
  /// create an `AtClient`, it becomes `AtNetworkTimeouts.defaultTimeout` for the
  /// whole process (capped at `AtNetworkTimeouts.maxAllowed`, 60s). When null,
  /// the existing default (30s) applies. This supersedes the misleadingly-named
  /// [outboundConnectionTimeout], which is a socket idle time, not an
  /// operation/connect timeout, and does not bound onboarding/auth.
  Duration? networkTimeout;

  /// The maximum size of the value that a secondary server can store.
  /// [BufferOverFlowException] is thrown when size of the value exceeds the [maxDataSize]
  int maxDataSize = 10230000;

  /// Default path to download stream files
  String? downloadPath;

  /// regex to perform sync
  String? syncRegex;

  /// Number of keys to batch for sync to secondary server
  int syncBatchSize = 5;

  /// The number of keys to pull from cloud secondary to local secondary in a single call.
  int syncPageLimit = 25;

  /// Default chunk size for file encryption and decryption
  int fileEncryptionChunkSize = 4096;

  /// The NotificationService maintains a connection which monitors for new
  /// notifications being delivered from the atServer. Because network weather
  /// is real, and because it is generally essential for client programs to
  /// receive notifications consistently, a heartbeat `no-op` command is sent
  /// to the atServer periodically, at this interval
  Duration monitorHeartbeatInterval = Duration(seconds: 59);

  /// When a heartbeat is sent by the notifications monitor, we wait for this
  /// length of time to receive a response. If no response is received, then
  /// the connection is closed, and the notifications monitor will reconnect.
  ///
  /// See also [monitorHeartbeatInterval]
  Duration monitorHeartbeatResponseTimeout = Duration(seconds: 10);

  /// How long the notifications monitor tolerates a connection that answers
  /// heartbeats while delivering nothing, before rebuilding it.
  ///
  /// A heartbeat proves the socket is alive, not that notifications are still
  /// arriving on it; without this a client can sit reporting
  /// [NotificationListenerState.listening] while permanently deaf. The
  /// atServer writes a stats notification to every monitor connection on its
  /// own timer, so a healthy connection is never silent for long.
  ///
  /// [Duration.zero] turns the check off, which is what an atServer
  /// configured to send no stats notifications needs - against one of those,
  /// silence is normal and this would rebuild a healthy connection.
  Duration monitorSilenceTimeout = Duration(seconds: 60);

  /// - when true, then the notifications monitor will be started either the
  /// first time that [NotificationService.subscribe] is called by the
  /// application code, or 30 seconds after creation of the
  /// [NotificationService] if there have been no subscriptions.
  /// - when false, then the notifications monitor
  /// will not be started until explicitly requested to do so by the
  /// application calling [NotificationService.startListening]
  bool monitorAutoStart = true;

  /// Time interval for the scheduled task that removes expired keys from local keyStore
  ///
  /// Please provide duration ONLY in minutes e.g. Duration(minutes: x) [x should be between 1 and 59]
  Duration expiryCheckTimeInterval = Duration(minutes: 10);

  ///[OptionalParameter] when set to true logs TLS Keys to file.
  bool decryptPackets = false;

  ///[OptionalParameter] location where the TLS keys will be saved when [decryptPackets] is set to true
  String? tlsKeysSavePath;

  ///[OptionalParameter] path to trusted certificates. Required to create security context.
  String? pathToCerts;

  /// [AtClient.put] uses this parameter to decide whether to check for presence of a namespace in the
  /// string representation of the AtKey.
  /// * When set to true, keys such as public:foo@alice or @bob:foo@alice will be rejected
  /// because they do not have a namespace. But keys such as public:foo.bar@alice of @bob:foo.bar.baz.bash@alice will be accepted.
  /// * When set to false keys such as public:foo@alice or @bob:foo@alice will not be rejected
  /// * Defaults to true, as applications should always be placing keys within a namespace
  @Deprecated(
      "namespace presence will become mandatory in next major version of the SDK")
  bool enforceNamespace = true;

  /// Fetch the notifications received when the client is offline. Defaults to true.
  /// Set to false to ignore the notifications received when device is offline.
  bool fetchOfflineNotifications = true;

  @Deprecated('No longer needed. at_chops will be used by default')
  bool useAtChops = true;

  /// Poorly named variable which used to control some aspects of at_client's
  /// default data encryption. Is now fully ignored.
  @Deprecated('Ignored. Will be removed in next major version')
  Version atProtocolEmitted = Version(2, 0, 0);

  AtClientParticulars atClientParticulars = AtClientParticulars();

  /// Signing algorithm to use for pkam authentication.
  ///
  /// Consulted only for a legacy enrollment whose keyfile carries no typed
  /// signing material; where typed material exists the client resolves the
  /// algorithm from the keyfile and this value never overrides it.
  @Deprecated('The signing algorithm is resolved from the enrollment\'s key '
      'material; this value is only a fallback for legacy keyfiles with no '
      'typed signing material')
  SigningAlgoType signingAlgoType = SigningAlgoType.rsa2048;

  /// hashing algorithm to use for pkam authentication
  HashingAlgoType hashingAlgoType = HashingAlgoType.sha256;

  /// Set this to [RemoteLocalPref.remoteOnly]
  /// if you require all data operations (get / put / delete) to be performed
  /// on the remote atServer rather than on local storage. (When operations are
  /// performed locally, we depend on sync to get eventual consistency between
  /// local and remote.
  RemoteLocalPref remoteLocalPref = RemoteLocalPref.localOnly;

  /// Configures the crypto providers used for encrypted puts and reads.
  ///
  /// The default, [CryptoConfig.eraDefault], is whatever this SDK release
  /// encrypts with; assign one only to register a custom provider or to hold a
  /// named scheme deliberately.
  ///
  /// ⚠️ Assigning a config that registers a [pqCryptoProviderIds] provider is
  /// refused when [posture] configures none, and the check runs at assignment
  /// only — [CryptoConfig.providers] is held by reference.
  CryptoConfig get crypto => _crypto;

  set crypto(CryptoConfig config) {
    if (!posture.configuresPqProviders) {
      final refused =
          config.providers.map((p) => p.id).where(pqCryptoProviderIds.contains);
      if (refused.isNotEmpty) {
        throw ArgumentError.value(
            refused.join(', '),
            'crypto',
            'this preference runs a posture that configures no post-quantum '
                'providers, and this config registers them. A client cannot '
                'both stand in for a build that predates these schemes and be '
                'given them. Name a posture that configures them, or a config '
                'that does not register them');
      }
    }
    _crypto = config;
  }

  CryptoConfig _crypto = const CryptoConfig.eraDefault();

  /// Whether a write that cannot go out under [crypto]'s scheme may fall back
  /// to legacy encryption instead of failing with
  /// [NamespaceKeyUnavailableException].
  ///
  /// ⚠️ Off by default: the fallback is a silent downgrade to RSA, and it is
  /// forward-only — the first write after the destination publishes a key is
  /// post-quantum, but records already written under it stay legacy.
  bool allowLegacyCryptoFallback = false;

  /// Whether this client mints and publishes namespace keys at start.
  ///
  /// Defaulted from [posture] and assignable afterwards, unlike the axes fixed
  /// at construction; minting publishes a permanent, discoverable record.
  bool seedNamespaceKeys = false;

  /// Which key-establishment algorithms this atSign **mints and advertises** —
  /// ids from [SecretSharingAlgos.keyAlgos], strongest-preferred first, where
  /// [sealsToKeyAlgorithms] is which of a recipient's this client will use.
  ///
  /// ⚠️ The first entry is the one anything minting a single key takes, so
  /// reordering changes what this atSign mints at its next start; dropping an
  /// entry retires that key rather than deleting it.
  final List<String> keyEstablishmentAlgorithms;
}

/// Default preference on how to handle get, put and delete requests with
/// regards to use of local storage vs the remote atServer.
enum RemoteLocalPref {
  /// The default - operate on local storage, and rely on the background
  /// sync processing to push changes to the remote atServer.
  localOnly,

  // /// Operate on remote first. If there is an exception, rethrow it back to
  // /// application code. If remote operation was successful, then perform the
  // /// operation on local storage.
  // remoteFirst,
  //
  /// Operate on remote only - i.e. do not interact with local storage at all.
  /// Note that if the application is syncing, then the change will be pulled
  /// to local from remote as part of the sync process.
  remoteOnly,
}

@Deprecated("Use SyncService")
enum SyncStrategy {
  /// Sync local keys immediately to secondary server for update and delete commands.
  immediate,
  onDemand,

  /// Sync periodically once every time interval specified by [AtClientPreference.syncIntervalMins].
  scheduled
}
