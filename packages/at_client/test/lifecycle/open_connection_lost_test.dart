import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:at_chops/at_chops.dart' show RsaKeyPair;
import 'package:at_client/at_client_io.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

import '../test_utils/hive_store.dart';
import '../test_utils/ml_dsa_keyfile.dart';
import '../test_utils/transport.dart';

/// Catalogue: features/at_client/open_connection_lost.feature
void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('open_connection_lost_');
  });

  tearDown(() async {
    for (final client
        in List<AtClient>.from(AtClientImpl.atClientInstanceMap.values)) {
      await client.stop();
    }
    AtClientImpl.atClientInstanceMap.clear();
    dir.deleteSync(recursive: true);
  });

  Future<int> refusedPort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = socket.port;
    await socket.close();
    return port;
  }

  Future<AtClientPreference> preference() async => AtClientPreference()
    ..rootDomain = InternetAddress.loopbackIPv4.address
    ..rootPort = await refusedPort()
    ..hiveStoragePath = dir.path
    ..namespace = 'lifecycle';

  AtLookUp lookUpOn(_Server server, String atSign,
          {AtAuthenticator? authenticator}) =>
      AtLookUp.withTransport(
          atSign: atSign,
          rootDomain: AtRootDomain(InternetAddress.loopbackIPv4.address, 64),
          authenticator: authenticator,
          transport: AtLookupTransport(transportFactory: server),
          secondaryAddressFinder:
              FixedSecondaryAddressFinder('127.0.0.1', 6464));

  /// Opens [atSign] on [server], whose newest connection closes on each of the
  /// next [closes] reads of the client's keys.
  Future<AtClient> open(String atSign, _Server server,
      {required int closes}) async {
    final keys = _ClosingKeys(server);
    await keyfileHolding(atSign,
        encryptionKeyPair: RsaKeyPair.generate(),
        selfEncryptionKey: testSelfEncryptionKey,
        enrollmentId: 'primary',
        apkamKeyPair: RsaKeyPair.generate(),
        io: keys);
    keys.closes = closes;
    final pref = await preference();
    return Atsign(atSign).open(
        keys: keys,
        preference: pref,
        lookUps: secureSocketLookUps(),
        secondaryAddressFinder: await refusingAtDirectory(),
        atLookUp: lookUpOn(server, atSign),
        storage: hiveStoreFor(Atsign(atSign), pref));
  }

  test(
      'An open whose connection is lost during authentication comes back '
      'online', () async {
    final server = _Server();
    final client = await open('@lostonce', server, closes: 1);

    expect(client.connection.current.isOnline, isTrue,
        reason: '${client.connection.current}');
    expect(server.connections, hasLength(greaterThanOrEqualTo(2)));
    expect(server.connections.first.written, isEmpty,
        reason: 'nothing is written to a connection that has closed');
    expect(server.connections[1].written.take(2).map((c) => c.split(':')[0]),
        ['from', 'pkam']);
  });

  test(
      'An open whose atServer closes every connection during authentication '
      'comes back offline, not refused', () async {
    final server = _Server();
    final client = await open('@lostalways', server, closes: 1 << 20);

    final state = client.connection.current;
    expect(state.isOffline, isTrue, reason: '$state');
    expect(state.cause, AtConnectionCause.unreachable);
    expect(state.error, isA<ConnectionInvalidException>());
    expect(await (client as AtClientImpl).hasBeenOnline(), isFalse);
    expect(server.connections.every((c) => c.written.isEmpty), isTrue);
  });

  test(
      'A connection lost during authentication classifies as one lost during '
      'a read', () async {
    final losesAuthentication = _Server();
    final authenticating = lookUpOn(losesAuthentication, '@alice',
        authenticator: (executor) async {
      await losesAuthentication.connections.last.serverCloses();
      await executor.sendSync('from:@alice\n');
      return true;
    });
    final losesRead = _Server()..closeOn = 'llookup:';
    final reading =
        lookUpOn(losesRead, '@alice', authenticator: (executor) async => true);

    Future<Object> failure(Future<Object?> Function() call) async {
      try {
        await call();
      } catch (e) {
        return e;
      }
      fail('the call succeeded');
    }

    final llookup = LLookupVerbBuilder()
      ..atKey = (AtKey()
        ..key = 'phone'
        ..sharedBy = '@alice');
    final throughVerb = [
      await failure(() => authenticating.executeVerb(llookup)),
      await failure(() => reading.executeVerb(llookup)),
    ];
    final throughCommand = [
      await failure(() =>
          authenticating.executeCommand('llookup:phone@alice\n', auth: true)),
      await failure(
          () => reading.executeCommand('llookup:phone@alice\n', auth: true)),
    ];
    await authenticating.stop();
    await reading.stop();

    for (final pair in [throughVerb, throughCommand]) {
      final states = pair.map(classifyConnectionFailure).toList();
      expect(states.map((s) => (s?.outcome, s?.cause)).toSet(), hasLength(1),
          reason: 'one route, one classification: $pair -> $states');
      expect(states.any((s) => s?.isRefused ?? false), isFalse,
          reason: '$pair -> $states');
    }
    for (final failure in [...throughVerb, ...throughCommand]) {
      final state = classifyConnectionFailure(failure);
      expect(state?.isOffline, isTrue, reason: '$failure -> $state');
      expect(state?.cause, AtConnectionCause.unreachable);
    }
  });
}

/// An atServer that answers `from:` with a challenge naming the atSign asked
/// for, `pkam:` with success and anything else with not found, and that
/// closes the connection instead of answering a command starting [closeOn].
class _Server implements AtTransportFactory {
  /// Every connection made to this server, oldest first.
  final List<_Connection> connections = [];

  String? closeOn;

  @override
  Future<AtTransport> connect(String host, String port,
      {Duration? timeout}) async {
    final connection = _Connection(this);
    connections.add(connection);
    return connection;
  }
}

class _Connection implements AtTransport {
  final _Server _server;
  final _inbound = StreamController<List<int>>();

  /// Everything the client wrote, in order.
  final List<String> written = [];
  bool destroyed = false;

  _Connection(this._server);

  @override
  String get description => '127.0.0.1:6464';

  @override
  Stream<List<int>> get inbound => _inbound.stream;

  @override
  void add(List<int> bytes) {
    final command = utf8.decode(bytes);
    written.add(command.trim());
    if (_server.closeOn case final prefix? when command.startsWith(prefix)) {
      unawaited(serverCloses());
      return;
    }
    final String reply;
    if (command.startsWith('from:')) {
      final atSign = command.substring(5).trim().split(':').first;
      reply = 'data:_03fe0ff2-ac50-4c80-8f43-88480beba888$atSign'
          ':c3d345fc-5691-4f90-bc34-17cba31f060f';
    } else if (command.startsWith('pkam:')) {
      reply = 'data:success';
    } else {
      reply = 'error:{"errorCode":"AT0015","errorDescription":"not found"}';
    }
    Timer.run(() {
      if (!_inbound.isClosed) _inbound.add(utf8.encode('$reply\n'));
    });
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

  /// The far end goes away, and the client's listener sees it.
  Future<void> serverCloses() async {
    if (!_inbound.isClosed) await _inbound.close();
    for (var i = 0; i < 3; i++) {
      await Future.delayed(Duration.zero);
    }
  }
}

/// Keys whose read, while [closes] is above zero and a connection is open,
/// has the atServer close the newest connection: the window between the
/// connect and the authenticator's first command.
class _ClosingKeys extends InMemoryAtKeysIo {
  final _Server _server;
  int closes = 0;

  _ClosingKeys(this._server);

  @override
  FutureOr<AtKeys> read(String atsign) async {
    if (closes > 0 &&
        _server.connections.isNotEmpty &&
        !_server.connections.last._inbound.isClosed) {
      closes--;
      await _server.connections.last.serverCloses();
    }
    return super.read(atsign);
  }
}
