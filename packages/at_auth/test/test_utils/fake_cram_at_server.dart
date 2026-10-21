import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

/// An atServer for [atSign] that answers `from:` with a challenge and the
/// `cram:` that follows with [cramReply], reached through a real
/// `AtLookupImpl` over a [SecureSocket] it scripts.
class FakeCramAtServer {
  FakeCramAtServer(this.atSign, {required this.cramReply});

  final String atSign;

  /// The atServer's one-line answer to `cram:`.
  final String cramReply;

  /// Every command the client wrote, in order.
  final List<String> written = <String>[];

  /// A lookup whose only network is this atServer.
  AtLookupMuxable lookUp() => AtLookUp.withSecureSocket(
        atSign: atSign,
        rootDomain: const AtRootDomain('127.0.0.1', 64),
        authenticator: null,
        secondaryAddressFinder: _FixedAddress(),
        transport: AtLookupTransport(
          secureSocketConfig: SecureSocketConfig(),
          socketFactory: _SocketFactory(this),
        ),
      );

  String? _replyTo(String command) {
    if (command.startsWith('from:')) {
      final random = Random.secure();
      String hex() => List.generate(32, (_) => random.nextInt(16))
          .map((n) => n.toRadixString(16))
          .join();
      return 'data:_${hex()}$atSign:${hex()}';
    }
    if (command.startsWith('cram:')) return cramReply;
    return null;
  }
}

class _Socket implements SecureSocket {
  _Socket(this._server);

  final FakeCramAtServer _server;
  final StreamController<Uint8List> _inbound = StreamController<Uint8List>();

  @override
  StreamSubscription<Uint8List> listen(void Function(Uint8List event)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      _inbound.stream.listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  void write(Object? object) => _received('$object');

  @override
  void writeln([Object? object = '']) => _received('$object\n');

  @override
  void add(List<int> data) => _received(utf8.decode(data));

  void _received(String command) {
    _server.written.add(command);
    final reply = _server._replyTo(command);
    if (reply == null) return;
    scheduleMicrotask(() {
      if (!_inbound.isClosed) {
        _inbound.add(Uint8List.fromList(utf8.encode('$reply\n')));
      }
    });
  }

  @override
  Future<void> flush() async {}

  @override
  void destroy() {
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
      '_Socket does not implement ${invocation.memberName}');
}

class _SocketFactory extends AtLookupSecureSocketFactory {
  _SocketFactory(this._server);

  final FakeCramAtServer _server;

  @override
  Future<SecureSocket> createSocket(
          String host, String port, SecureSocketConfig socketConfig,
          {Duration? timeout}) async =>
      _Socket(_server);
}

class _FixedAddress extends SecondaryAddressFinder {
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
          {Duration? timeout}) async =>
      SecondaryAddress('127.0.0.1', 6464);
}
