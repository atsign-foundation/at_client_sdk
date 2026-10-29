import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_lookup/src/connection/at_connection.dart';

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

/// Builds the connection a client uses to reach an atServer: what an
/// application hands the entry points so that every connection the client
/// opens - its own, its sync's, its monitor's - travels the way the
/// application chose.
///
/// The factory captures **how bytes travel**: the transport and its settings,
/// or a different [AtLookUp] implementation altogether. Each call names
/// **what the connection is for**: [atSign] is whose atServer, [rootDomain]
/// is where the atDirectory that finds it is, [authenticator] is how the
/// connection authenticates (null for one that never does),
/// and [secondaryAddressFinder] replaces the atDirectory lookup when the
/// caller holds one. What a connection announces about the client travels in
/// its authenticator's `from:`. The default is `secureSocketLookUps` in
/// `package:at_lookup/at_lookup_io.dart`.
typedef AtLookUpFactory = AtLookupMuxable Function({
  required String atSign,
  required AtRootDomain rootDomain,
  required AtAuthenticator? authenticator,
  SecondaryAddressFinder? secondaryAddressFinder,
});

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
  /// [withTransport] is the same factory under a transport-neutral name, for a
  /// [transport] that is not a socket.
  ///
  /// [authenticator] is required and nullable, which is not an oversight: null
  /// means *this connection never authenticates*, and that is a real mode —
  /// `at_status_impl` holds no key material at all, and an OTP enrolment
  /// request goes out unauthenticated. Requiring it forces the caller to say
  /// which it meant.
  ///
  /// [transport] is required, and deliberately has no default. A default
  /// naming an implementation pulls that implementation's imports in whatever
  /// the caller injects, which is what makes a transport swap fail silently
  /// rather than loudly. The socket transport is `secureSocketTransport` in
  /// `package:at_lookup/at_lookup_io.dart`, so naming it is also what selects
  /// the library that carries it.
  ///
  /// It carries its own configuration, which is why no socket settings appear
  /// here: a caller wanting the TLS defaults writes
  /// `secureSocketTransport(SecureSocketConfig())` and thereby states it,
  /// while a caller on another transport says nothing about TLS at all.
  ///
  /// [secondaryAddressFinder] is required for the same reason: the neutral
  /// barrel cannot name a native implementation, so the caller supplies one.
  ///
  /// [onConnect] runs on every connection this lookup opens, once it is up
  /// and before anything else is sent on it: a proxy that needs `from:` first
  /// to learn which atServer the connection is for is the case it exists for.
  /// It talks only through the executor it is handed, since a call back into
  /// the lookup waits for it to finish, and a connection whose [onConnect]
  /// fails is closed.
  static AtLookupMuxable withSecureSocket({
    required String atSign,
    required AtRootDomain rootDomain,
    required AtAuthenticator? authenticator,
    required AtLookupTransport transport,
    required SecondaryAddressFinder secondaryAddressFinder,
    Future<void> Function(AtCommandExecutor connection)? onConnect,
  }) =>
      withTransport(
        atSign: atSign,
        rootDomain: rootDomain,
        authenticator: authenticator,
        transport: transport,
        secondaryAddressFinder: secondaryAddressFinder,
        onConnect: onConnect,
      );

  /// Build a lookup over [transport]; every parameter means what it means on
  /// [withSecureSocket].
  static AtLookupMuxable withTransport({
    required String atSign,
    required AtRootDomain rootDomain,
    required AtAuthenticator? authenticator,
    required AtLookupTransport transport,
    required SecondaryAddressFinder secondaryAddressFinder,
    Future<void> Function(AtCommandExecutor connection)? onConnect,
  }) {
    return AtLookupImpl(
      atSign,
      rootDomain.rootDomain,
      rootDomain.rootPort,
      secondaryAddressFinder: secondaryAddressFinder,
      transportFactory: transport.transportFactory,
      socketListenerFactory: transport.listenerFactory,
      outboundConnectionFactory: transport.connectionFactory,
      onConnect: onConnect,
    )..authenticator = authenticator;
  }

  /// Runs [builder]'s command on the atServer, authenticating the connection
  /// first when the verb needs it, and returns the atServer's response.
  Future<String?> executeVerb(VerbBuilder builder);

  /// Sends [command] as written and returns the atServer's response; [auth]
  /// authenticates the connection first.
  Future<String?> executeCommand(String command, {bool auth = false});

  /// Authenticates this lookup's connection with its authenticator, opening
  /// the connection when there is none, and returns true once it has. A
  /// connection logged in by another authenticator is closed, and the
  /// authenticator logs in on a new one.
  ///
  /// A connection lost before the authentication finishes is replaced, and
  /// the authenticator runs again on the new one, once; a second loss throws
  /// [ConnectionInvalidException].
  ///
  /// The connection records the enrollment named by the `pkam:` the atServer
  /// accepted, as [AtConnectionMetaData.authenticatedAsEnrollmentId].
  Future<bool> pkamAuthenticate();

  /// Closes this lookup's connection: the next call opens a new one and
  /// authenticates again as the same atSign, with the credentials the lookup
  /// holds at that moment.
  ///
  /// A request waiting on the connection fails at once. An [AtLookupMuxable]
  /// also stops its notifications, so nothing reconnects until a caller sends
  /// a command. [stop] is what ends a lookup for good.
  Future<void> close();

  AtConnection? get connection;

  /// Authenticates each connection this lookup opens. With none set, a
  /// command that needs authentication fails.
  ///
  /// A login serves only the authenticator that made it: once this changes,
  /// the next command that needs authentication closes the connection and
  /// logs in on a new one with the authenticator set then.
  AtAuthenticator? get authenticator;
  set authenticator(AtAuthenticator? value);

  /// Ends this lookup: closes its connection, and stops its notifications
  /// when it has any.
  ///
  /// Work in flight fails with [StoppedException], and so does every later
  /// call, without touching the network; [close] afterwards changes nothing.
  /// Calling this again waits for the first stop.
  Future<void> stop();

  SecondaryAddressFinder get secondaryAddressFinder;
}

/// An [AtLookUp] that also carries the atServer's asynchronous notification
/// stream, so one class reads every kind of message the atServer sends.
///
/// Every message ends at a newline and the atServer writes one at a time, so
/// each line is a message: the prompt it may carry at the start comes off, and
/// what is left says where it goes — `data:` and `error:` answer a request
/// this client made, `notification:` answers nothing. Everything that read the
/// atServer has, until now, been written twice.
///
/// ## Sharing a connection between the two
///
/// A notification arriving between a command and its reply is routed as the
/// message it is and the reply still arrives, so the kinds cannot corrupt one
/// another on one socket.
///
/// `MonitorVerbBuilder.multiplexed` documents itself as telling the atServer
/// that a connection carries both, so that "the server will only send
/// notifications once there is no request currently in progress". **No
/// atServer implements it.** Measured against `at_server` `origin/trunk`:
/// zero occurrences of the string in the entire repository, against a probe
/// proven positive on `selfNotifications`, which returns 16. The monitor
/// verb's syntax — shared by both sides, in at_commons — *does* capture
/// `multiplexed` as a named group, so the atServer parses the flag, ignores
/// it, and does not refuse it. Setting it buys nothing and reports success —
/// and the interleaving it was meant to prevent is not what breaks a client
/// reading whole lines.
///
/// ⚠️ at_client's `Monitor` still takes a connection of its own, for a reason
/// of its own: it pauses the connection while handing a notification on, so on
/// a shared one a handler that writes would wait for its reply on the socket
/// it has just paused.
abstract interface class AtLookupMuxable implements AtLookUp {
  /// Notifications from the atServer, as the raw lines it sent.
  ///
  /// **Single-subscription, deliberately.** A broadcast stream does not
  /// buffer, ignores `pause()`, and drops anything arriving before a listener
  /// attaches. Every one of those is data loss on a notification, and a
  /// dropped notification is indistinguishable from one the atServer never
  /// sent — so the failure gets attributed to the sender.
  ///
  /// Pausing this stream stops reading the transport. On a TLS socket,
  /// back-pressure reaches the atServer through TCP. A WebSocket cannot be
  /// paused, so its transport holds frames up to a bound and past it closes
  /// the connection.
  ///
  /// Listen as soon as you read it: until a listener arrives, notifications
  /// are held without bound, and none of that back-pressure applies.
  Stream<String> get notifications;

  /// Ask the atServer to start sending notifications on this connection.
  ///
  /// Connects and authenticates if required, then sends `monitor:`. Safe to
  /// call when already notifying: it returns without re-sending.
  Future<void> startNotifications({
    String? regex,
    Future<int?> Function()? getLastNotificationTime,
    bool selfNotificationsEnabled = true,
  });

  /// Stop notifications by dropping the connection carrying them.
  ///
  /// There is no verb that turns `monitor:` off — the atServer streams until
  /// the connection goes away — so this closes it. [notifications] is closed
  /// too, because a stream that can never produce another event should say so
  /// rather than hang, and so is [notificationConnectionUp].
  ///
  /// Both are replaced on the next [startNotifications], so a caller that
  /// restarts must take fresh subscriptions: the ones it held are closed and
  /// will report nothing about the new connection.
  Future<void> stopNotifications();

  /// Whether [startNotifications] is in force.
  bool get isNotifying;

  /// Closes the current connection and fails what was waiting on it, leaving
  /// this lookup usable: the next call opens a new connection.
  ///
  /// While notifying, this is a lost connection like any other and is
  /// reconnected. [stop] is what ends the lookup.
  Future<void> dropConnection();

  /// Whether a usable connection is currently open.
  ///
  /// A caller closing down needs this to avoid closing what was never opened,
  /// and it too was reached only by casting.
  bool isConnectionAvailable();

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
  ///
  /// ⚠️ **[stopNotifications] closes this stream**, so a subscription does not
  /// survive a stop: a caller that stops and starts again is holding a closed
  /// stream and will never see the new connection come up. Read this getter
  /// again after each [startNotifications] rather than once for the life of
  /// the object.
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
/// Nothing here names a socket any more. [AtTransportFactory] returns an
/// [AtTransport], `AtConnection` speaks `inbound`/`add`, and the settings a
/// TLS socket needs live inside the factory that opens one — so a WebSocket
/// implementation is a value passed to [transportFactory] rather than a
/// change to any type on this path.
class AtLookupTransport {
  /// Opens the byte channel. Required and undefaulted for the same reason
  /// [AtLookUp.withSecureSocket]'s `transport` is: a default naming an
  /// implementation imports that implementation into every caller.
  final AtTransportFactory transportFactory;

  final AtLookupOutboundConnectionFactory connectionFactory;
  final AtLookupMessageListenerFactory listenerFactory;

  const AtLookupTransport({
    required this.transportFactory,
    this.connectionFactory = const AtLookupOutboundConnectionFactory(),
    this.listenerFactory = const AtLookupMessageListenerFactory(),
  });
}
