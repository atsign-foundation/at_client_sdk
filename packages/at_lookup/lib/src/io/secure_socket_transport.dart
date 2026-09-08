import 'dart:io';

import 'package:at_commons/at_commons.dart';

import '../transport/at_transport.dart';
import 'secure_socket_util.dart';

/// TLS over TCP — the [AtTransport] `at_lookup` has always used, now behind the
/// interface.
///
/// The constructor takes [Socket] rather than [SecureSocket] because every
/// member below is plain socket delegation; the TLS lives entirely in
/// [SecureSocketTransportFactory], which is the only thing that constructs one.
class SecureSocketTransport implements AtTransport {
  final Socket _socket;

  @override
  final String description;

  SecureSocketTransport(Socket socket)
      : _socket = socket,
        description = '${socket.remoteAddress.address}:${socket.remotePort}';

  /// The socket itself, never a re-broadcast of it.
  ///
  /// `Socket implements Stream<Uint8List>`, so pausing this subscription
  /// pauses the TCP receive window. A `StreamController` in between would
  /// answer the pause out of a local buffer and the far end would keep sending.
  @override
  Stream<List<int>> get inbound => _socket;

  @override
  void add(List<int> bytes) => _socket.add(bytes);

  @override
  Future<void> flush() => _socket.flush();

  @override
  void destroy() => _socket.destroy();
}

/// Opens [SecureSocketTransport]s, carrying the TLS settings they are opened
/// with.
///
/// The config lives here rather than on the transport because it is an input to
/// connecting and means nothing to an open channel.
class SecureSocketTransportFactory implements AtTransportFactory {
  final SecureSocketConfig secureSocketConfig;

  const SecureSocketTransportFactory({required this.secureSocketConfig});

  /// Both a refused connection ([SocketException]) and a failed or rejected
  /// handshake ([TlsException]) surface as [SecondaryConnectException]; the
  /// cause is kept in the message. The caller supplies whose atServer this was.
  @override
  Future<AtTransport> connect(String host, String port,
      {Duration? timeout}) async {
    try {
      return SecureSocketTransport(await SecureSocketUtil.createSecureSocket(
          host, port, secureSocketConfig,
          timeout: timeout));
    } on SocketException catch (e) {
      throw _unreachable(host, port, e);
    } on TlsException catch (e) {
      throw _unreachable(host, port, e);
    }
  }

  SecondaryConnectException _unreachable(String host, String port, Object e) =>
      SecondaryConnectException('unable to connect to atServer on $host:$port'
          ' - $e');
}
