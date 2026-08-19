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

  Future<String?> executeVerb(VerbBuilder builder, {bool sync = false});

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
  @Deprecated('Supply an AtAuthenticator via AtLookupImpl.authenticator '
      'instead - at_auth builds one with authenticatorForChops(). '
      'Removed with the credential ladder in the next major release.')
  set atChops(AtChops? atChops);

  OutboundConnection? get connection;

  @Deprecated('Supply an AtAuthenticator via AtLookupImpl.authenticator '
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
}
