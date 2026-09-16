/// The step-2 proof that `AtTransport` is implementable without a socket.
///
/// It reaches no platform library on purpose: a fake that satisfies the
/// interface here is a fake that compiles for the browser, which is the whole
/// claim the transport seam exists to make.
library;

import 'dart:async';
import 'dart:convert';

import 'package:at_lookup/at_lookup.dart';
import 'package:test/test.dart';

/// An [AtTransport] with nothing behind it.
class FakeTransport implements AtTransport {
  late final StreamController<List<int>> _inbound = StreamController(
    onPause: () => paused = true,
    onResume: () => paused = false,
  );

  final written = <List<int>>[];
  var flushes = 0;
  var destroyed = false;
  var paused = false;

  @override
  Stream<List<int>> get inbound => _inbound.stream;

  @override
  void add(List<int> bytes) => written.add(bytes);

  @override
  Future<void> flush() async => flushes++;

  @override
  void destroy() {
    destroyed = true;
    written.clear();
  }

  @override
  String get description => 'fake';

  /// Puts [bytes] on [inbound] as if the far end had sent them.
  void deliver(String bytes) => _inbound.add(utf8.encode(bytes));
}

class FakeTransportFactory implements AtTransportFactory {
  final created = <FakeTransport>[];
  final requested = <String>[];

  @override
  Future<AtTransport> connect(
    String host,
    String port, {
    Duration? timeout,
  }) async {
    requested.add('$host:$port');
    final transport = FakeTransport();
    created.add(transport);
    return transport;
  }
}

void main() {
  group('AtTransport', () {
    test('carries bytes in both directions', () async {
      final factory = FakeTransportFactory();
      final transport =
          await factory.connect('root.atsign.org', '64') as FakeTransport;

      expect(factory.requested, ['root.atsign.org:64']);

      final received = <List<int>>[];
      transport.inbound.listen(received.add);

      transport.add(utf8.encode('scan\n'));
      await transport.flush();
      expect(transport.written, [utf8.encode('scan\n')]);
      expect(transport.flushes, 1);

      transport.deliver('data:@alice\n');
      await Future<void>.delayed(Duration.zero);
      expect(received, [utf8.encode('data:@alice\n')]);

      transport.destroy();
      expect(transport.destroyed, isTrue);
    });

    test('pausing inbound reaches the source', () async {
      final transport = FakeTransport();
      final subscription = transport.inbound.listen((_) {});

      subscription.pause();
      await Future<void>.delayed(Duration.zero);
      expect(transport.paused, isTrue,
          reason: 'inbound must expose the source stream, not a '
              'StreamController re-broadcast of it - a controller answers the '
              'pause from a local buffer and the far end never hears it');

      subscription.resume();
      await Future<void>.delayed(Duration.zero);
      expect(transport.paused, isFalse);

      await subscription.cancel();
    });

    test('description is available without a socket', () {
      expect(FakeTransport().description, 'fake');
    });
  });
}
