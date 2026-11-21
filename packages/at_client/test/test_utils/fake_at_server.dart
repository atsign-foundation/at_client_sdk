import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:at_auth/at_auth.dart' show authenticatorForPrivateKey;
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:uuid/uuid.dart';

/// An [AtTransport] the [FakeAtServer] drives, over a real single-subscription
/// [StreamController] so pause, resume, done and error are real events.
class FakeAtServerSocket implements AtTransport {
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
  Stream<List<int>> get inbound => _inbound.stream;

  @override
  void add(List<int> data) {
    if (destroyed) {
      throw AtIOException('write to a socket this client destroyed');
    }
    final command = utf8.decode(data);
    written.add(command);
    _onWrite(this, command);
  }

  @override
  Future<void> flush() async {}

  @override
  bool get isOpen => !destroyed;

  @override
  void destroy() {
    destroyed = true;
    if (!_inbound.isClosed) _inbound.close();
  }

  @override
  String get description => '127.0.0.66:6464';
}

/// An atServer a test can make misbehave: refuse connections, refuse
/// authentication, reject `monitor:`, go quiet, drop the connection, fault it,
/// or send something unparseable.
///
/// Hands out the [AtLookUpFactory] a client or a notification service is built
/// on, so everything between the subscriber and the socket is production code.
class FakeAtServer {
  FakeAtServer(
      {this.atSign = '@alice',
      this.pkamPrivateKey,
      this.runsClientAuthenticator = false});

  final String atSign;

  /// When set, every lookup authenticates with at_auth's own authenticator
  /// for this PKAM private key: this server issues each `from:` challenge,
  /// and [pkamRefusal] decides how each `pkam:` is answered.
  final String? pkamPrivateKey;

  /// The whole line the atServer answers each `pkam:` with while set, as an
  /// atServer refusing the credential; null accepts it.
  String? pkamRefusal;

  /// The whole line the atServer answers each `from:` with while set, in
  /// place of the challenge [pkamPrivateKey]'s authenticator signs.
  String? pkamFromAnswer;

  /// Whether the atServer drops each connection on its `from:`, as a network
  /// failing mid-handshake does, while [pkamPrivateKey] is set.
  bool dropOnFrom = false;

  /// Whether each lookup runs the authenticator its caller hands in, whose
  /// `from:` this server answers with a challenge and whose `pkam:` or `cram:`
  /// it accepts, in place of this server's own and of [pkamPrivateKey]'s.
  final bool runsClientAuthenticator;

  /// Every socket this server has handed out, oldest first.
  final List<FakeAtServerSocket> sockets = <FakeAtServerSocket>[];

  /// Every lookup [lookUps] has built, oldest first.
  final List<AtLookUp> lookUpsBuilt = <AtLookUp>[];

  final Map<AtLookUp, List<FakeAtServerSocket>> _socketsOf = Map.identity();

  /// The `from:` commands sent on the connections [lookUp] opened, in order.
  List<String> fromsOn(AtLookUp lookUp) => [
        for (final socket in _socketsOf[lookUp] ?? const <FakeAtServerSocket>[])
          ...socket.written.where((command) => command.startsWith('from:'))
      ];

  /// The `from:` commands every connection sent, in the order the connections
  /// were opened.
  List<String> get froms => [
        for (final socket in sockets)
          ...socket.written.where((command) => command.startsWith('from:'))
      ];

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

  /// Authentications that fail, as an atServer refusing the credential,
  /// when neither [pkamPrivateKey] nor [runsClientAuthenticator] is set.
  int failAuths = 0;

  /// What the client authenticator's `pkam:` or `cram:` on a connection of
  /// the given lookup is answered with in place of success, when it returns
  /// an answer.
  String? Function(AtLookUp? lookUp)? refuseClientAuth;

  /// What the client authenticator's `from:` is answered with in place of
  /// a challenge, when it returns an answer.
  String? Function()? answerClientFrom;

  /// `monitor:` commands answered with an error instead of accepted.
  int rejectMonitors = 0;

  /// Whether the heartbeat probe is answered. False is an atServer that holds
  /// the socket open and says nothing.
  bool answerHeartbeat = true;

  /// What a verb this server has no answer of its own for is answered with
  /// in place of `data:ok`, when it returns an answer.
  String? Function(String command)? answerVerb;

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
      }) {
        final transport = _FakeTransportFactory(this);
        final lookUp = AtLookUp.withSecureSocket(
          atSign: atSign,
          rootDomain: rootDomain,
          // NOTE: unless runsClientAuthenticator, this server's own, not the
          // caller's, which would read the client's keystore.
          authenticator: runsClientAuthenticator
              ? authenticator
              : pkamPrivateKey == null
                  ? _authenticate
                  : authenticatorForPrivateKey(atSign, pkamPrivateKey!),
          // NOTE: this server's own, whatever the caller passed: the
          // caller's would ask the real atDirectory.
          secondaryAddressFinder: addressFinder,
          transport: AtLookupTransport(transportFactory: transport),
        );
        transport.owner = lookUp;
        lookUpsBuilt.add(lookUp);
        return lookUp;
      };

  Future<bool> _authenticate(AtCommandExecutor _) async {
    authCount++;
    if (failAuths > 0) {
      failAuths--;
      throw UnAuthenticatedException(
          'Failed connecting to $atSign. The atServer refused the credential');
    }
    return true;
  }

  FakeAtServerSocket _connect(AtLookUp? owner) {
    if (refuseConnects > 0) {
      refuseConnects--;
      throw SecondaryConnectException('the atServer is not reachable');
    }
    connectCount++;
    final socket = FakeAtServerSocket(_onWrite);
    sockets.add(socket);
    if (owner != null) _socketsOf.putIfAbsent(owner, () => []).add(socket);
    return socket;
  }

  void _onWrite(FakeAtServerSocket socket, String command) {
    if (runsClientAuthenticator && command.startsWith('from:')) {
      final answer = answerClientFrom?.call();
      unawaited(socket.serverSends(answer != null
          ? '$answer\n@'
          : 'data:_9e8169dc-5618-44ec-ab43-1a5b2144c581'
              '$atSign:c3d345fc-5691-4f90-bc34-17cba31f060f\n@'));
      return;
    }
    if (runsClientAuthenticator &&
        (command.startsWith('pkam:') || command.startsWith('cram:'))) {
      final owner = _socketsOf.entries
          .where((entry) => entry.value.contains(socket))
          .map((entry) => entry.key)
          .firstOrNull;
      final refusal = refuseClientAuth?.call(owner);
      unawaited(socket.serverSends(
          refusal == null ? 'data:success\n$atSign@' : '$refusal\n@'));
      return;
    }
    if (pkamPrivateKey != null && command.startsWith('from:')) {
      if (dropOnFrom) {
        unawaited(socket.serverCloses());
        return;
      }
      final answer = pkamFromAnswer;
      if (answer != null) {
        unawaited(socket.serverSends('$answer\n@'));
        return;
      }
      const uuid = Uuid();
      unawaited(
          socket.serverSends('data:_${uuid.v4()}$atSign:${uuid.v4()}\n@'));
      return;
    }
    if (pkamPrivateKey != null && command.startsWith('pkam:')) {
      authCount++;
      final refusal = pkamRefusal;
      unawaited(socket.serverSends(
          refusal == null ? 'data:success\n$atSign@' : '$refusal\n@'));
      return;
    }
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
    if (command.startsWith('stats:')) {
      unawaited(socket.serverSends(
          'data:[{"id":"3","name":"lastCommitID","value":"null"}]\n$atSign@'));
      return;
    }
    final answer = answerVerb?.call(command);
    if (answer != null) {
      unawaited(socket.serverSends('$answer\n$atSign@'));
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

class _FakeTransportFactory implements AtTransportFactory {
  _FakeTransportFactory(this._server);

  final FakeAtServer _server;

  /// The lookup this factory connects for.
  AtLookUp? owner;

  @override
  Future<AtTransport> connect(String host, String port,
          {Duration? timeout}) async =>
      _server._connect(owner);
}

class _FixedAddress extends SecondaryAddressFinder {
  _FixedAddress(this.atSign);

  final String atSign;

  @override
  Future<SecondaryAddress> findSecondary(String atSign,
          {Duration? timeout}) async =>
      SecondaryAddress('127.0.0.1', 6464);
}
