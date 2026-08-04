import 'package:at_chops/at_chops.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/preference/at_client_particulars.dart';
import 'package:version/version.dart';

/// Class to hold attributes for client preferences.
/// Set the preferences for your application and pass it to [AtClientManager.setCurrentAtSign].
class AtClientPreference {
  /// Never encrypt *new* data with the legacy (pre-post-quantum) provider:
  /// take a post-quantum path, or refuse the write.
  ///
  /// **Default false in 3.x, true in 4.0.** Set it early to be certain nothing
  /// this app writes is harvestable today and decryptable by a quantum
  /// computer later; leave it alone to keep the SDK's own migration schedule.
  ///
  /// What it governs is exactly one thing: **legacy encryption of new data.**
  /// - Legacy **reads** are always available. History has to keep opening, and
  ///   upgrading only ever adds read capability.
  /// - `shouldEncrypt = false` — the app-accessible no-crypto path — is
  ///   unaffected. This is not a "must be encrypted" switch.
  /// - Public keys are unaffected; they are signed, not encrypted.
  ///
  /// A destination that only legacy can reach is therefore **refused**, never
  /// silently written legacy — which is also why
  /// [allowLegacyCryptoFallback] does not survive this being set. The two
  /// switches say opposite things ("reach this recipient however you can" and
  /// "never write legacy") and this one wins.
  ///
  /// **Final at construction.** There is no setter, and the value cannot be
  /// changed for a live client: a flag that governs what a client is allowed
  /// to write must not be flippable mid-run, or "was that record written under
  /// the guarantee?" has no answer.
  ///
  /// Expect refusals in 3.x. The SDK still writes several of its own records
  /// under the legacy provider — a shared key for a legacy recipient most
  /// obviously — and those are retired by the projects that follow, not by
  /// this flag.
  final bool disallowLegacyEncryption;

  AtClientPreference({this.disallowLegacyEncryption = false});

  /// Local device path of hive storage
  String? hiveStoragePath;

  /// Local device path of commit log
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

  /// signing algorithm to use for pkam authentication
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
  /// **Leave this null** unless the app genuinely needs its own providers.
  /// Null means "whatever this SDK release encrypts with by default", which is
  /// what almost every app wants: the default is the SDK's to move as the
  /// post-quantum migration proceeds, and an app that pinned
  /// `CryptoConfig.legacy()` only because it had to name something would find
  /// itself pinned to the old scheme after the release that changed it.
  /// [CryptoConfig.forClient] is where that resolution happens.
  ///
  /// Set it to opt out — to register a custom provider, or to hold a specific
  /// scheme deliberately. Custom providers are initialised by [AtClientImpl]
  /// before sync and notification services start.
  CryptoConfig? crypto;

  /// Whether a write that cannot go out under [crypto]'s scheme may fall back
  /// to legacy encryption instead of failing.
  ///
  /// This exists for one case: a post-quantum write to a destination that has
  /// never used or authorised the namespace, so has no key to seal to. There is
  /// no post-quantum fallback — the only atSign-level key is a signing root,
  /// which cannot receive an encapsulation — so the alternatives are legacy or
  /// [NamespaceKeyUnavailableException].
  ///
  /// **Off by default, and deliberately awkward to turn on.** A silent
  /// downgrade to RSA is what the post-quantum work exists to prevent: the
  /// write succeeds, the app looks healthy, and the data is harvestable. Only
  /// an app that knowingly accepts that — an invitation flow reaching a
  /// first-contact recipient, during the migration — should set it.
  ///
  /// The fallback is **forward-only**, because the check runs per write: the
  /// first write after the destination publishes a key is post-quantum, with no
  /// flag to flip. Records already written under the fallback stay legacy;
  /// re-encrypting them is an explicit migration, never a side effect of a put.
  ///
  /// It ends with the post-quantum-by-default release, where cold start throws
  /// whatever this says.
  bool allowLegacyCryptoFallback = false;

  /// Whether this client performs the rollout actions at start: publishing the
  /// capability marker for each namespace it is authorised for, and minting
  /// and publishing the namespace keys.
  ///
  /// Seeding is a **rollout** action, not a crypto-path one, which is why it
  /// is its own knob rather than following [crypto]. The release sequence has
  /// clients minting and publishing *while still writing legacy*, so that by
  /// the time post-quantum writes are switched on the keys are already
  /// everywhere; gating it on the PQ path being active would seed nothing
  /// until the very moment seeding stopped being useful.
  ///
  /// The marker rides the same knob because it is the same step seen from the
  /// other side of a write: the key is what a sender seals to, the marker is
  /// what tells that sender whether it may. It goes up saying **legacy only**
  /// — an upgraded client cannot speak for its siblings — and stays that way
  /// until an operator declares readiness through `CryptoRollout`.
  ///
  /// Off by default while the data path is experimental — both publish a
  /// permanent, discoverable record on the atSign, which is not something to
  /// start doing behind an app's back.
  bool seedNamespaceKeys = false;
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
