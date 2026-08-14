import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/crypto/crypto.dart';
import 'package:at_client/src/preference/release_posture.dart';
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

  /// The post-quantum rollout posture this client runs under — the five
  /// rollout flags set as a group. Defaults to [ReleasePosture.migration],
  /// the 3.x posture; pass [ReleasePosture.postQuantum] to run the 4.0
  /// defaults today.
  ///
  /// Individual flags still win: an explicit [disallowLegacyEncryption] or
  /// [inUseSigningAlgorithms] argument, an assigned [crypto], or a per-call
  /// algorithm each override the posture's value for that one axis.
  ///
  /// Final at construction, like [disallowLegacyEncryption] and for the same
  /// reason: what a client writes must not change meaning mid-run. A client
  /// that already exists keeps the posture it was built under, and a caller
  /// asking for it with a preference naming a different one is **refused** —
  /// see [rolloutDifferencesFrom]. It used to be ignored, which left the
  /// caller running on the stage it thought it had left.
  final ReleasePosture posture;

  /// Which algorithms this client keeps an **active signing key** for — the
  /// keys that sign what its enrollment attests to, which is a different job
  /// from the APKAM authentication key that proves possession on a connection.
  ///
  /// Not to be confused with [signingAlgoType], which is that authentication
  /// key's algorithm and is resolved from the key material rather than chosen.
  ///
  /// **Empty in 3.x, `{mldsa65}` in 4.0** ([ReleasePosture]). Empty is not
  /// "unsigned": with no signing key of its own an enrollment signs with its
  /// APKAM authentication key, whose public half is published as this
  /// enrollment's signing key and stays published afterwards, because it is
  /// what verifies every envelope signed before the two jobs were separated.
  ///
  /// Naming an algorithm this build cannot sign an envelope under is
  /// **refused at construction**. Skipping it quietly would leave an app that
  /// asked for a post-quantum signature believing it had one while every
  /// signature it produced was classical.
  ///
  /// **Final at construction**, like [disallowLegacyEncryption]: an app that
  /// could change it mid-run would leave "which key signed this, and does it
  /// still exist?" without an answer. A [Set] rather than a list because
  /// membership is the whole of the meaning — the order signatures are emitted
  /// in is the strongest-first order the keyfile is read in, never this one.
  final Set<SigningAlgoType> inUseSigningAlgorithms;

  /// Where this client stands in the rollout that separates an enrollment's
  /// signing keys from its APKAM authentication key — a **position**, and the
  /// source of [inUseSigningAlgorithms]' default.
  ///
  /// [SigningRollout.rollout1] is the value a deployment sets here rather than
  /// on the posture: it says the fleet's readers have upgraded, which no client
  /// can observe for itself, and it changes nothing this client writes.
  ///
  /// **When both this and [inUseSigningAlgorithms] are given explicitly, the
  /// set is what the client obeys.** Only the stage's default reaches
  /// behaviour, so naming both is naming a mixture on purpose — the same
  /// contract every other axis has, where an explicitly set flag beats the
  /// group it came from.
  final SigningRollout signingRollout;

  AtClientPreference(
      {this.posture = const ReleasePosture.migration(),
      bool? disallowLegacyEncryption,
      SigningRollout? signingRollout,
      Set<SigningAlgoType>? inUseSigningAlgorithms})
      : disallowLegacyEncryption =
            disallowLegacyEncryption ?? posture.disallowLegacyEncryption,
        signingRollout = signingRollout ?? posture.signingRollout,
        inUseSigningAlgorithms = _signableOrRefuse(inUseSigningAlgorithms ??
            (signingRollout ?? posture.signingRollout)
                .defaultInUseSigningAlgorithms);

  /// Where [other] would change what a **running** client does — one line per
  /// differing axis, empty when the two are interchangeable.
  ///
  /// This is what a caller asking for a client that already exists is checked
  /// against. Every axis below is final at construction precisely because what
  /// a client writes must not change meaning mid-run, so a second preference
  /// naming a different one cannot be adopted; before this existed it was
  /// silently ignored, and the caller ran on the stage it thought it had left
  /// behind. Post-rollout that is not a flag being ignored but a **key**: the
  /// stage decides which algorithm an enrollment authenticates and signs under.
  ///
  /// **Compared by value, never by identity.** Repeated
  /// `setCurrentAtSign(atSign, namespace, TestPreferences.getPreference(…))`
  /// calls hand over a fresh, equal preference object every time — an identity
  /// test would refuse every one of them.
  ///
  /// ⚠️ **The posture is compared by what it MEANS, not as an object**, for
  /// the same reason one step further down: [ReleasePosture] declares no `==`,
  /// so comparing two of them is an identity test, and a caller writing
  /// `ReleasePosture.migration()` without `const` gets an instance that is not
  /// the canonical one. Two behaviourally identical postures would then read as
  /// a mismatch. What is compared is the pair of posture fields nothing else
  /// carries — [ReleasePosture.writesPqByDefault] and
  /// [ReleasePosture.keyExchangeMode] — beside the three effective axes, which
  /// is the whole of what a posture can change.
  ///
  /// [crypto] is deliberately **not** here: it is adopted from the incoming
  /// preference rather than refused, so that a provider registered after first
  /// construction takes effect.
  List<String> rolloutDifferencesFrom(AtClientPreference other) {
    final differences = <String>[];

    // Each line reads "asked for X, running on Y", since the caller is the one
    // holding a preference it expected to take effect.
    void compare(String axis, Object? asked, Object? running) {
      if (asked != running) differences.add('$axis (asked $asked, running $running)');
    }

    compare('posture.writesPqByDefault', other.posture.writesPqByDefault,
        posture.writesPqByDefault);
    compare('posture.keyExchangeMode', other.posture.keyExchangeMode.name,
        posture.keyExchangeMode.name);
    compare('signingRollout', other.signingRollout.name, signingRollout.name);
    compare('disallowLegacyEncryption', other.disallowLegacyEncryption,
        disallowLegacyEncryption);

    final asked = other.inUseSigningAlgorithms;
    final running = inUseSigningAlgorithms;
    if (asked.length != running.length || !asked.containsAll(running)) {
      // Rendered strongest-first so both sides read in one order — a Set
      // iterates in insertion order, so two equal sets built by different
      // routes would otherwise print differently and read as a difference.
      String spell(Set<SigningAlgoType> algorithms) =>
          '{${SigningAlgoType.strongestFirst.where(algorithms.contains).map((a) => a.name).join(', ')}}';
      differences.add('inUseSigningAlgorithms (asked ${spell(asked)}, '
          'running ${spell(running)})');
    }
    return differences;
  }

  /// [algorithms] unmodifiable, or an [ArgumentError] naming the first member
  /// this build produces no envelope signature for.
  ///
  /// Unmodifiable because the field is only as final as its contents: an app
  /// holding the set it passed could otherwise add an algorithm afterwards and
  /// get past this check.
  static Set<SigningAlgoType> _signableOrRefuse(
      Set<SigningAlgoType> algorithms) {
    for (final algorithm in algorithms) {
      if (!canSignEnvelopeWith(algorithm)) {
        final signable = SigningAlgoType.strongestFirst
            .where(canSignEnvelopeWith)
            .map((signableAlgorithm) => signableAlgorithm.name)
            .join(', ');
        throw ArgumentError.value(algorithm.name, 'inUseSigningAlgorithms',
            'this build signs under $signable');
      }
    }
    return Set.unmodifiable(algorithms);
  }

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

  /// Signing algorithm to use for pkam authentication.
  ///
  /// Consulted only for a legacy enrollment whose keyfile carries no typed
  /// signing material: the algorithm is a fact about the key material — you
  /// cannot sign ML-DSA with an RSA key — so the client resolves it from the
  /// keyfile whenever typed material exists, and this value never overrides
  /// that resolution.
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
  /// **Leave this alone** unless the app genuinely needs its own providers.
  /// The default, [CryptoConfig.eraDefault], means "whatever this SDK release
  /// encrypts with by default", which is what almost every app wants: the
  /// default is the SDK's to move as the post-quantum migration proceeds, and
  /// an app that pinned `CryptoConfig.legacy()` only because it had to name
  /// something would find itself pinned to the old scheme after the release
  /// that changed it. [CryptoConfig.forClient] is where that resolution
  /// happens.
  ///
  /// Assign a config to opt out — to register a custom provider, or to hold a
  /// specific scheme deliberately. Custom providers are initialised by the
  /// client implementation before sync and notification services start.
  CryptoConfig crypto = const CryptoConfig.eraDefault();

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

  /// Whether this client mints and publishes namespace keys at start.
  ///
  /// Seeding is a **rollout** action, not a crypto-path one, which is why it
  /// is its own knob rather than following [crypto]. The release sequence has
  /// clients minting and publishing *while still writing legacy*, so that by
  /// the time post-quantum writes are switched on the keys are already
  /// everywhere; gating it on the PQ path being active would seed nothing
  /// until the very moment seeding stopped being useful.
  ///
  /// Off by default while the data path is experimental — minting publishes a
  /// permanent, discoverable record on the atSign, which is not something to
  /// start doing behind an app's back.
  bool seedNamespaceKeys = false;

  /// Which key-establishment algorithm this atSign **mints and advertises** —
  /// an id from [SecretSharingAlgos.keyAlgos].
  ///
  /// Two options, and the choice is a deployment's rather than a message's:
  ///
  /// - [SecretSharingAlgos.xWing] (the default) — the ML-KEM-768 + X25519
  ///   hybrid, which keeps a classical hedge covering exactly one scenario:
  ///   ML-KEM falling to *classical* cryptanalysis before a quantum computer
  ///   exists. Its combiner is specified only in an IETF draft.
  /// - [SecretSharingAlgos.mlKem1024] — FIPS 203 alone, no combiner and no
  ///   draft anywhere in its specification chain, which is what answers a
  ///   "FIPS-approved algorithms only" questionnaire. It is also CNSA 2.0's
  ///   mandated parameter set, and CNSA 2.0 treats hybrids as non-compliant.
  ///
  /// **This does not restrict who this client can talk to.** It decides what
  /// this atSign publishes; a *sender* always follows what the recipient
  /// advertised, and every build can produce and open both suites. An atSign
  /// configured for ML-KEM-1024 still seals to a hybrid peer, because refusing
  /// would leave the two unable to communicate while protecting nothing — the
  /// peer's key is the peer's decision.
  ///
  /// **Configuration rather than negotiation, and the reason is NIST's.**
  /// SP 800-227 §4.6.3 warns that composite schemes "introduce additional
  /// choices in protocols, which could also introduce vulnerabilities (e.g. in
  /// the form of downgrade attacks)". Each atSign advertises one KEM and there
  /// is no per-message negotiation to attack.
  ///
  /// Changing it does not re-key anything already published. Keys are minted
  /// per generation, so an atSign moves to the other option by rotating —
  /// which is the only moment the advertised algorithm can change.
  String keyEstablishmentAlgo = SecretSharingAlgos.xWing;
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
