import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

/// A [SecureSocket] the [FakeAtServer] drives, over a real single-subscription
/// [StreamController] so pause, resume, done and error are real events.
///
/// Anything not implemented throws [UnimplementedError] naming the member, so
/// an unsupported call fails loudly rather than answering null into a
/// non-nullable type.
class FakeAtServerSocket implements SecureSocket {
  FakeAtServerSocket(this._onWrite);

  final void Function(FakeAtServerSocket socket, String command) _onWrite;

  late final StreamController<Uint8List> _inbound = StreamController<Uint8List>(
    onPause: () => pauseCount++,
    onResume: () => resumeCount++,
  );

  /// Everything the client wrote, in order.
  final List<String> written = <String>[];

  int pauseCount = 0;
  int resumeCount = 0;
  bool destroyed = false;

  StreamSubscription<Uint8List>? _subscription;

  /// True while the listener's subscription is paused, which is how
  /// back-pressure reaches this end.
  bool get isPaused => _subscription?.isPaused ?? false;

  /// Pushes bytes at the client as the atServer would, then lets the event
  /// loop deliver them.
  Future<void> serverSends(String data) async {
    if (destroyed || _inbound.isClosed) return;
    _inbound.add(Uint8List.fromList(utf8.encode(data)));
    await settle();
  }

  /// The far end went away: the client's listener sees `onDone`.
  Future<void> serverCloses() async {
    if (!_inbound.isClosed) await _inbound.close();
    await settle();
  }

  /// The far end faulted: the client's listener sees `onError`.
  Future<void> serverErrors(Object error) async {
    if (_inbound.isClosed) return;
    _inbound.addError(error);
    await settle();
  }

  /// Lets queued events and the work they cause run.
  Future<void> settle([int turns = 6]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
      {Function? onError, void Function()? onDone, bool? cancelOnError}) {
    return _subscription = _inbound.stream.listen(onData,
        onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  void write(Object? object) => _record('$object');

  @override
  void writeln([Object? object = '']) => _record('$object\n');

  @override
  void add(List<int> data) => _record(utf8.decode(data));

  void _record(String command) {
    if (destroyed) {
      throw SocketException('write to a socket this client destroyed');
    }
    written.add(command);
    _onWrite(this, command);
  }

  @override
  Future<void> flush() async {}

  @override
  void destroy() {
    destroyed = true;
    if (!_inbound.isClosed) _inbound.close();
  }

  @override
  Future<void> close() async => destroy();

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  InternetAddress get remoteAddress => InternetAddress('127.0.0.66');

  @override
  int get remotePort => 6464;

  @override
  InternetAddress get address => InternetAddress('127.0.0.1');

  @override
  int get port => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError(
      'FakeAtServerSocket does not implement ${invocation.memberName}. '
      'Add it here rather than working around it.');
}

/// An atServer a test can make misbehave: refuse connections, refuse
/// authentication, reject `monitor:`, go quiet, drop the connection, fault it,
/// or send something unparseable.
///
/// Hands out the [AtLookUpFactory] a client or a notification service is built
/// on, so everything between the subscriber and the socket is production code.
class FakeAtServer {
  FakeAtServer({this.atSign = '@alice'});

  final String atSign;

  /// Every socket this server has handed out, oldest first.
  final List<FakeAtServerSocket> sockets = <FakeAtServerSocket>[];

  /// The connection the client is on now.
  FakeAtServerSocket get socket => sockets.last;

  /// How many connects, authentications, `monitor:` commands and heartbeat
  /// probes this server has seen.
  int connectCount = 0;
  int authCount = 0;
  int monitorCount = 0;
  int heartbeatCount = 0;

  /// The `monitor:` commands received, so a test can read the watermark and
  /// regex each carried.
  final List<String> monitorCommands = <String>[];

  /// Connects that fail before there is a socket, as an unreachable atServer.
  int refuseConnects = 0;

  /// Authentications that fail, as an atServer refusing the credential.
  int failAuths = 0;

  /// `monitor:` commands answered with an error instead of accepted.
  int rejectMonitors = 0;

  /// Whether the heartbeat probe is answered. False is an atServer that holds
  /// the socket open and says nothing.
  bool answerHeartbeat = true;

  /// The atDirectory answer for every lookup: this server, wherever it is
  /// asked about.
  late final SecondaryAddressFinder addressFinder = _FixedAddress(atSign);

  /// The factory that builds every lookup, so this server is the only network
  /// the code under test has.
  AtLookUpFactory get lookUps => ({
        required String atSign,
        required AtRootDomain rootDomain,
        required AtAuthenticator? authenticator,
        SecondaryAddressFinder? secondaryAddressFinder,
        Map<String, dynamic> clientConfig = const {},
      }) =>
          AtLookUp.withSecureSocket(
            atSign: atSign,
            rootDomain: rootDomain,
            // NOTE: this server's own, not the caller's. The caller's would
            // sign a real PKAM challenge; this one decides whether the
            // atServer accepts the credential at all.
            authenticator: _authenticate,
            // NOTE: this server's own, whatever the caller passed: the
            // caller's would ask the real atDirectory.
            secondaryAddressFinder: addressFinder,
            clientConfig: clientConfig,
            transport: AtLookupTransport(
                secureSocketConfig: SecureSocketConfig(),
                socketFactory: _FakeSocketFactory(this)),
          );

  Future<bool> _authenticate(AtCommandExecutor _) async {
    authCount++;
    if (failAuths > 0) {
      failAuths--;
      throw UnAuthenticatedException(
          'Failed connecting to $atSign. The atServer refused the credential');
    }
    return true;
  }

  FakeAtServerSocket _connect() {
    if (refuseConnects > 0) {
      refuseConnects--;
      throw SocketException('the atServer is not reachable');
    }
    connectCount++;
    final socket = FakeAtServerSocket(_onWrite);
    sockets.add(socket);
    return socket;
  }

  void _onWrite(FakeAtServerSocket socket, String command) {
    if (command.startsWith('monitor:')) {
      monitorCount++;
      monitorCommands.add(command.trim());
      if (rejectMonitors > 0) {
        rejectMonitors--;
        unawaited(socket.serverSends('error:AT0003-Invalid syntax\n'
            '$atSign@'));
      }
      return;
    }
    if (command.startsWith('noop:')) {
      heartbeatCount++;
      if (answerHeartbeat) {
        unawaited(socket.serverSends('data:ok\n$atSign@'));
      }
      return;
    }
    // Everything else is answered the way the atServer answers a verb it
    // understands, so an unexpected command cannot read as a hung socket.
    unawaited(socket.serverSends('data:ok\n$atSign@'));
  }

  /// Sends [json] as a notification, framed as the atServer frames it.
  Future<void> sendNotification(String json) =>
      socket.serverSends('notification: $json\n');

  /// Sends a notification carrying [id], for [key].
  Future<void> notify(String id,
      {String key = 'test.resilience@alice', String? value}) {
    final millis = DateTime.now().millisecondsSinceEpoch;
    return sendNotification('{"id":"$id","from":"$atSign","to":"$atSign",'
        '"key":"$key","value":${value == null ? 'null' : '"$value"'},'
        '"operation":"update","epochMillis":$millis,'
        '"messageType":"MessageType.key","isEncrypted":false}');
  }

  /// The far end goes away, as a dropped network does.
  Future<void> drop() => socket.serverCloses();

  /// The far end faults, as a reset connection does.
  Future<void> fault([Object? error]) =>
      socket.serverErrors(error ?? SocketException('connection reset by peer'));

  /// Waits until [test] holds, or fails after [within].
  Future<void> waitUntil(bool Function() test,
      {Duration within = const Duration(seconds: 5),
      String what = 'the condition'}) async {
    final deadline = DateTime.now().add(within);
    while (!test()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('$what did not happen within $within');
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}

class _FakeSocketFactory extends AtLookupSecureSocketFactory {
  _FakeSocketFactory(this._server);

  final FakeAtServer _server;

  @override
  Future<SecureSocket> createSocket(
          String host, String port, SecureSocketConfig socketConfig,
          {Duration? timeout}) async =>
      _server._connect();
}

class _FixedAddress extends SecondaryAddressFinder {
  _FixedAddress(this.atSign);

  final String atSign;

  @override
  Future<SecondaryAddress> findSecondary(String atSign,
          {Duration? timeout}) async =>
      SecondaryAddress('127.0.0.1', 6464);
}
