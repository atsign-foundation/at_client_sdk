import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';

/// An atServer for [atSign] that answers `from:` with a challenge and the
/// `cram:` that follows with [cramReply], reached through a real
/// `AtLookupImpl` over an [AtTransport] it scripts.
///
/// It accepts the rest of an activation too: a `lookup:publickey` finds no
/// key, the first enrollment is approved, every `pkam:` succeeds and every
/// `update:` and `delete:` is done.
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
          transportFactory: _TransportFactory(this),
        ),
      );

  /// The `from:` commands the client wrote, in order.
  Iterable<String> get froms => written.where((c) => c.startsWith('from:'));

  String? _replyTo(String command) {
    if (command.startsWith('from:')) {
      final random = Random.secure();
      String hex(int length) => List.generate(length, (_) => random.nextInt(16))
          .map((n) => n.toRadixString(16))
          .join();
      String uuid() => '${hex(8)}-${hex(4)}-${hex(4)}-${hex(4)}-${hex(12)}';
      return 'data:_${uuid()}$atSign:${uuid()}';
    }
    if (command.startsWith('cram:')) return cramReply;
    if (command.startsWith('lookup:publickey')) return 'data:null';
    if (command.startsWith('enroll:request:')) {
      return 'data:{"enrollmentId":"e-1","status":"approved"}';
    }
    if (command.startsWith('pkam:')) return 'data:success';
    if (command.startsWith('update:') || command.startsWith('delete:')) {
      return 'data:1';
    }
    return null;
  }
}

class _Transport implements AtTransport {
  _Transport(this._server);

  final FakeCramAtServer _server;
  final StreamController<List<int>> _inbound = StreamController<List<int>>();

  @override
  String get description => '127.0.0.66:6464';

  @override
  Stream<List<int>> get inbound => _inbound.stream;

  @override
  void add(List<int> bytes) {
    final command = utf8.decode(bytes);
    _server.written.add(command);
    final reply = _server._replyTo(command);
    if (reply == null) return;
    scheduleMicrotask(() {
      if (!_inbound.isClosed) _inbound.add(utf8.encode('$reply\n'));
    });
  }

  @override
  Future<void> flush() async {}

  @override
  bool get isOpen => !_inbound.isClosed;

  @override
  void destroy() {
    if (!_inbound.isClosed) _inbound.close();
  }
}

class _TransportFactory implements AtTransportFactory {
  _TransportFactory(this._server);

  final FakeCramAtServer _server;

  @override
  Future<AtTransport> connect(String host, String port,
          {Duration? timeout}) async =>
      _Transport(_server);
}

class _FixedAddress extends SecondaryAddressFinder {
  @override
  Future<SecondaryAddress> findSecondary(String atSign,
          {Duration? timeout}) async =>
      SecondaryAddress('127.0.0.1', 6464);
}
