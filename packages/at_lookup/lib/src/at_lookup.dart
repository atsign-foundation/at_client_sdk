import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_chops/at_chops.dart';
import 'package:at_lookup/at_lookup.dart';

/// Performs one authentication on a connection that is already open, using
/// [executor] to speak to the atServer, and returns whether it succeeded.
///
/// This is the whole of authentication reduced to one value. at_lookup cannot
/// name `AtKeys` or `AtKeysIo` - they live in at_auth, which depends on
/// at_lookup - so the credential, the enrollment and the signing algorithm all
/// stay on the at_auth side of this typedef and none of them reach here.
///
/// Implementations are invoked once per connection that needs authenticating,
/// so a closure held for an instance's life must decide afresh each time what
/// credential applies: an instance that CRAM-onboards and then PKAM-
/// authenticates is one instance and two answers.
typedef AtAuthenticator = Future<bool> Function(AtCommandExecutor executor);

/// The narrow view of a connection that an [AtAuthenticator] is given: enough
/// to run a challenge-response, and nothing else.
abstract interface class AtCommandExecutor {
  /// Sends [command] and returns the atServer's reply.
  ///
  /// "Sync" names the channel, not the Dart semantics: verb responses are the
  /// synchronous side of the connection, the side where a reply belongs to the
  /// command that preceded it. Notifications are the asynchronous side and
  /// never arrive here.
  ///
  /// Called from inside authentication, which already holds the
  /// request/response mutex, so this must not take it again.
  ///
  /// The two budgets are those of `OutboundMessageListener.read` and mean the
  /// same things. They are here because authentication does not want one
  /// answer: the CRAM leg of onboarding waits far less than a verb response
  /// does, on the grounds that a secret is either accepted promptly or not at
  /// all. Omit them and the process-wide defaults apply.
  Future<String> sendSync(String command,
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis});
}

abstract interface class AtLookUp {
  /// Build a lookup that talks to an atServer over TLS.
  ///
  /// This is the entry point. Constructing `AtLookupImpl` directly still
  /// works and is deprecated: it takes a `String, int` root pair rather than
  /// an [AtRootDomain], it accepts key material this class no longer needs,
  /// and it hands back a concrete type where callers only need an interface.
  ///
  /// Static, and that is deliberate — statics are not part of the `implements`
  /// contract, so adding this breaks none of the classes that mock
  /// [AtLookUp]. Widening the interface itself would have: `implements` erases
  /// bodies, so a mock satisfies a new member through `noSuchMethod` and
  /// returns null into a non-nullable type **at runtime only**, with
  /// `dart analyze` clean.
  ///
  /// Named for its transport, so a differently-transported factory can join it
  /// later rather than this one growing a mode flag.
  ///
  /// [authenticator] is required and nullable, which is not an oversight: null
  /// means *this connection never authenticates*, and that is a real mode —
  /// `at_status_impl` holds no key material at all, and an OTP enrolment
  /// request goes out unauthenticated. Requiring it forces the caller to say
  /// which it meant.
  ///
  /// [secureSocketConfig] is required for the same reason: a caller wanting
  /// the defaults writes `SecureSocketConfig()` and thereby states it. One
  /// production site today omits what its neighbour sets.
  static AtLookupMuxable withSecureSocket({
    required String atSign,
    required AtRootDomain rootDomain,
    required SecureSocketConfig secureSocketConfig,
    required AtAuthenticator? authenticator,
    Map<String, dynamic> clientConfig = const {},
    SecondaryAddressFinder? secondaryAddressFinder,
    AtLookupTransport transport = AtLookupTransport.secureSocket,
  }) {
    return AtLookupImpl(
      atSign,
      rootDomain.rootDomain,
      rootDomain.rootPort,
      secureSocketConfig: secureSocketConfig,
      clientConfig: clientConfig,
      secondaryAddressFinder: secondaryAddressFinder,
      secureSocketFactory: transport.socketFactory,
      socketListenerFactory: transport.listenerFactory,
      outboundConnectionFactory: transport.connectionFactory,
    )..authenticator = authenticator;
  }

  /// update
  Future<bool> update(String key, String value,
      {String? sharedWith, Metadata? metadata});

  /// lookup
  Future<String> lookup(String key, String sharedBy,
      {bool auth = true, bool verifyData = false});

  /// plookup
  Future<String> plookup(String key, String sharedBy);

  Future<String> llookup(String key,
      {String? sharedBy, String? sharedWith, bool isPublic = false});

  /// delete
  Future<bool> delete(String key, {String? sharedWith, bool isPublic = false});

  /// scan
  Future<List<String>> scan({String? regex, String? sharedBy});

  Future<String?> executeVerb(VerbBuilder builder,
      {@Deprecated('Inert: nothing reads it. The verb always executes '
          'on the remote atServer; there is no sync behaviour here '
          'to control. Removed in 4.0.')
      bool sync = false});

  Future<String?> executeCommand(String command, {bool auth = false});

  /// Performs a PKAM authentication using private key on the client side and public key on secondary server
  ///
  /// Pkam private key should be set in  [atChops.atChopsKeys]
  ///
  /// Default signing algorithm for pkam signature is [SigningAlgoType.rsa2048] and default hashing algorithm is [HashingAlgoType.sha256]
  ///
  /// Optionally pass enrollmentId if the client is enrolled using APKAM
  Future<bool> pkamAuthenticate({String? enrollmentId});

  /// Generates digest using from verb response and [secret] and performs a
  /// CRAM authentication to secondary server
  Future<bool> cramAuthenticate(String secret);

  /// Terminates the underlying connection to the atServer
  /// used by this instance of AtLookup
  Future<void> close();

  /// set an instance of  [AtChops] for signing and verification operations.
  ///
  /// Deprecated as a *credential*. Authentication runs through an injected
  /// [AtAuthenticator] instead, so at_lookup no longer needs to hold key
  /// material to authenticate. Callers that read this for crypto which is not
  /// authentication should be handed their own [AtChops] - that is what
  /// at_auth EnrollmentApprover.approve takes an approverChops for.
  @Deprecated('Pass an AtAuthenticator to AtLookUp.withSecureSocket '
      'instead - at_auth builds one with authenticatorForChops(). '
      'Removed with the credential ladder in the next major release.')
  set atChops(AtChops? atChops);

  OutboundConnection? get connection;

  @Deprecated('Pass an AtAuthenticator to AtLookUp.withSecureSocket '
      'instead - at_auth builds one with authenticatorForChops(). '
      'Removed with the credential ladder in the next major release.')
  AtChops? get atChops;

  set secondaryAddressFinder(SecondaryAddressFinder secondaryAddressFinder);

  SecondaryAddressFinder get secondaryAddressFinder;

  /// Signing algorithm for pkam signature
  ///
  /// Deprecated together with [hashingAlgoType]: the two are read on the same
  /// lines when the PKAM signature is built, so they are one setting and they
  /// move together.
  @Deprecated('Pass the signing algorithm to the AtAuthenticator that at_auth '
      'builds - authenticatorForChops() takes signingAlgo and hashingAlgo. '
      'Removed with the credential ladder in the next major release.')
  set signingAlgoType(SigningAlgoType signingAlgoType);

  @Deprecated('Pass the signing algorithm to the AtAuthenticator that at_auth '
      'builds - authenticatorForChops() takes signingAlgo and hashingAlgo. '
      'Removed with the credential ladder in the next major release.')
  SigningAlgoType get signingAlgoType;

  /// Hashing algorithm for pkam signature
  ///
  /// Deprecated together with [signingAlgoType]; see the note there.
  @Deprecated('Pass the hashing algorithm to the AtAuthenticator that at_auth '
      'builds - authenticatorForChops() takes signingAlgo and hashingAlgo. '
      'Removed with the credential ladder in the next major release.')
  set hashingAlgoType(HashingAlgoType hashingAlgoType);

  @Deprecated('Pass the hashing algorithm to the AtAuthenticator that at_auth '
      'builds - authenticatorForChops() takes signingAlgo and hashingAlgo. '
      'Removed with the credential ladder in the next major release.')
  HashingAlgoType get hashingAlgoType;

  /// EnrollmentId has to be set for clients that are enrolled through APKAM.
  ///
  /// This is the enrollment the *next* authentication will use, which is
  /// deliberately not [AtConnectionMetaData.authenticatedAsEnrollmentId] -
  /// what a live socket actually authenticated as. That distinction survives
  /// the deprecation; the two are not interchangeable.
  @Deprecated('Pass the enrollment id to the AtAuthenticator that at_auth '
      'builds. To ask "which enrollment am I", read your own client state - '
      'not this field, and not '
      'AtConnectionMetaData.authenticatedAsEnrollmentId, which is what the '
      'live connection authenticated as rather than what the next '
      'authentication will use. '
      'Removed with the credential ladder in the next major release.')
  set enrollmentId(String? enrollmentId);

  @Deprecated('Pass the enrollment id to the AtAuthenticator that at_auth '
      'builds. To ask "which enrollment am I", read your own client state - '
      'not this field, and not '
      'AtConnectionMetaData.authenticatedAsEnrollmentId, which is what the '
      'live connection authenticated as rather than what the next '
      'authentication will use. '
      'Removed with the credential ladder in the next major release.')
  String? get enrollmentId;
}

/// An [AtLookUp] that also carries the atServer's asynchronous notification
/// stream, so one class knows both of the atServer's framings.
///
/// A verb response ends `\n@<atSign>@` — the newline, then the prompt saying
/// the atServer is ready for the next command. A notification is not a reply
/// to anything, so no prompt follows it and it ends at a bare `\n`. Everything
/// that reads one of those framings has, until now, been written twice.
///
/// ## This does NOT make one connection safe for both
///
/// ⚠️ **Give this a connection of its own.** The notification stream and verb
/// request-response must not share a socket today, and the flag that was
/// supposed to make that safe does not work.
///
/// `MonitorVerbBuilder.multiplexed` documents itself as telling the atServer
/// that a connection carries both, so that "the server will only send
/// notifications once there is no request currently in progress". **No
/// atServer implements it.** Measured against `at_server` `origin/trunk`:
/// zero occurrences of the string in the entire repository, against a probe
/// proven positive on `selfNotifications`, which returns 16. The monitor
/// verb's syntax — shared by both sides, in at_commons — *does* capture
/// `multiplexed` as a named group, so the atServer parses the flag, ignores
/// it, and does not refuse it. Setting it buys nothing and reports success.
///
/// The consequence is concrete: the atServer's monitor handler subscribes to
/// its notification stream and writes each notification to the connection as
/// it arrives, with nothing gating that write on a request being in flight. A
/// notification landing mid-response is appended to a buffer whose prefix is
/// already `data:`, so the framing check — which tests that prefix — will not
/// route it, and it is absorbed into the verb response instead. Corruption,
/// not a dropped message, and only under concurrency.
abstract interface class AtLookupMuxable implements AtLookUp {
  /// Notifications from the atServer, as the raw lines it sent.
  ///
  /// **Single-subscription, deliberately.** A broadcast stream does not
  /// buffer, ignores `pause()`, and drops anything arriving before a listener
  /// attaches. Every one of those is data loss on a notification, and a
  /// dropped notification is indistinguishable from one the atServer never
  /// sent — so the failure gets attributed to the sender.
  ///
  /// Pausing this stream stops reading the socket, so back-pressure reaches
  /// the atServer through TCP rather than being absorbed by an unbounded
  /// buffer in this process.
  Stream<String> get notifications;

  /// Ask the atServer to start sending notifications on this connection.
  ///
  /// Connects and authenticates if required, then sends `monitor:`. Safe to
  /// call when already notifying: it returns without re-sending.
  Future<void> startNotifications({
    String? regex,
    int? lastNotificationTime,
    bool selfNotificationsEnabled = true,
  });

  /// Stop notifications by dropping the connection carrying them.
  ///
  /// There is no verb that turns `monitor:` off — the atServer streams until
  /// the connection goes away — so this closes it. [notifications] is closed
  /// too, because a stream that can never produce another event should say so
  /// rather than hang.
  Future<void> stopNotifications();

  /// Whether [startNotifications] is in force.
  bool get isNotifying;

  // The two places `AtLookupImpl` accepts more than `AtLookUp` does, restated
  // here so a caller can hold this interface without losing anything.
  //
  // Found with the analyzer, not by reading: a hand-written comparison of the
  // two signature lists missed `scan` entirely, because nested generics in
  // `Future<List<String>>` broke its return-type pattern. A probe that calls
  // each method through the interface reports exactly what is missing, and
  // carries `scan(auth:)` as a control that must be reported.
  //
  // They go HERE rather than on `AtLookUp` because that interface is frozen:
  // adding a parameter to one of its methods forces every `implements
  // AtLookUp` to redeclare it, which breaks the six mocks and any external
  // implementer at compile time. This interface is new, and `AtLookupImpl` is
  // its only implementer.

  /// As [AtLookUp.scan], and additionally [auth] - whether to scan as the
  /// authenticated atSign. `at_server_status` scans unauthenticated.
  @override
  Future<List<String>> scan({String? regex, String? sharedBy, bool auth = true});

  /// As [AtLookUp.lookup], and additionally [metadata].
  @override
  Future<String> lookup(String key, String sharedBy,
      {bool auth = true, bool verifyData = false, bool metadata = false});

  /// Takes over authentication entirely when set.
  ///
  /// On the interface because installing one is the whole point of the seam,
  /// and every installer previously had to write `if (lookUp is
  /// AtLookupImpl)` to reach it — four such casts across at_auth, at_client
  /// and at_onboarding_cli. A cast to a concrete type in order to configure it
  /// is the shape this project exists to remove.
  AtAuthenticator? get authenticator;
  set authenticator(AtAuthenticator? value);

  /// Whether a usable connection is currently open.
  ///
  /// A caller closing down needs this to avoid closing what was never opened,
  /// and it too was reached only by casting.
  bool isConnectionAvailable();

  /// Read one response from the connection, without sending anything first.
  ///
  /// For a caller that has already put bytes on the wire itself — at_client's
  /// file-stream path writes to the socket directly and then waits for
  /// `stream:done`. It previously reached `messageListener.read(...)` through
  /// a cast to the concrete class.
  ///
  /// This is deliberately narrower than exposing the listener: that type is
  /// not in at_lookup's barrel, and putting it on a public interface would
  /// publish it by the back door.
  Future<String> readResponse(
      {int? maxWaitMilliSeconds, int? transientWaitTimeMillis});

  /// Whether the connection dropped and a reconnect is in flight.
  ///
  /// A subscriber otherwise cannot tell a reconnecting stream from a quiet
  /// atServer: both look like no events. at_client's `Monitor` surfaces the
  /// same distinction as a listener state, for the same reason.
  bool get isReconnectingNotifications;

  /// `true` when `monitor:` has been accepted on a live connection, `false`
  /// when that connection is lost or notifications are stopped.
  ///
  /// This exists because the muxable owns reconnection, so it is the only
  /// thing that knows. at_client's `Monitor` re-broadcasts it as a
  /// `NotificationListenerState`, which noports' daemon subscribes to for its
  /// whole life; without this it could only poll [isReconnectingNotifications]
  /// and would learn of an outage a poll interval late.
  ///
  /// `bool` rather than a richer state because the richer type lives in
  /// at_client, which depends on at_lookup - naming it here would invert that.
  ///
  /// **Broadcast**, unlike [notifications], and the difference is deliberate:
  /// this is a state signal whose latest value supersedes the last, so a
  /// dropped event costs a subscriber nothing it cannot re-derive. A dropped
  /// *notification* is gone. ⚠️ A late subscriber does not get the current
  /// state on attach, matching what `Monitor.currentStateStream` has always
  /// done.
  Stream<bool> get notificationConnectionUp;

  /// How often a quiet notification connection is probed, and how long the
  /// probe waits for its answer.
  ///
  /// On the interface because they are the only way to make the notification
  /// connection's liveness behaviour testable, or tunable, without naming the
  /// implementation - which is the thing this project is removing from callers.
  Duration get heartbeatInterval;
  set heartbeatInterval(Duration value);

  Duration get heartbeatResponseTimeout;
  set heartbeatResponseTimeout(Duration value);
}


/// How an [AtLookupMuxable] makes connections: the three factories
/// `AtLookupImpl` has always accepted, bundled into one value.
///
/// This exists because [AtLookUp.withSecureSocket] returns an interface, and
/// an interface cannot be handed a socket. Without it there is no way to give
/// a factory-built muxable a connection it did not open itself — which is
/// invisible while the concrete constructor is still reachable, and becomes
/// total the moment callers stop using it.
///
/// It bundles rather than abstracts, deliberately. These factories are
/// **already injectable**; what blocks a web transport is their **return
/// type** (`SecureSocket`), not their injectability. A parallel abstraction
/// here would be a second seam for that return-type change to reconcile,
/// where bundling leaves exactly one — and the change lands inside it without
/// touching this signature.
///
/// ⚠️ **This is not yet enough for a non-socket transport, and it does not
/// claim to be.** `AtConnection` exposes `Socket getSocket()`, which the
/// listener calls, so a WebSocket implementation needs that member gone —
/// a breaking change for every `implements AtConnection`, and out of scope
/// while this ships as an additive minor.
class AtLookupTransport {
  final AtLookupSecureSocketFactory socketFactory;
  final AtLookupOutboundConnectionFactory connectionFactory;
  final AtLookupSecureSocketListenerFactory listenerFactory;

  const AtLookupTransport({
    this.socketFactory = const AtLookupSecureSocketFactory(),
    this.connectionFactory = const AtLookupOutboundConnectionFactory(),
    this.listenerFactory = const AtLookupSecureSocketListenerFactory(),
  });

  /// TLS over TCP: what every caller gets unless it says otherwise.
  static const AtLookupTransport secureSocket = AtLookupTransport();
}
