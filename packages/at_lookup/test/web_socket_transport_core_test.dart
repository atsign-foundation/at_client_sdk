import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/src/web/web_socket_transport.dart';
import 'package:at_utils/at_logger.dart';
import 'package:test/test.dart';

/// [WebSocketTransport] over a fake [WebSocketPort], on the VM: the bounded
/// inbound buffer, the `bufferedAmount` flush and the closed-socket `add`
/// depend on browser timing that a live socket cannot pin down.
void main() {
  late FakeWebSocketPort port;
  late RecordingHandler logs;

  WebSocketTransport transport({
    int maxInboundBytes = 10,
    Duration flushTimeout = const Duration(seconds: 1),
  }) =>
      WebSocketTransport(port, 'ws://fake',
          maxInboundBytes: maxInboundBytes,
          flushTimeout: flushTimeout,
          flushPollInterval: const Duration(milliseconds: 1),
          logger: AtSignLogger('WebSocketTransport', loggingHandler: logs));

  setUp(() {
    port = FakeWebSocketPort();
    logs = RecordingHandler();
  });

  group('inbound', () {
    test('text and binary frames both arrive as bytes, in order', () async {
      final t = transport();
      final received = <String>[];
      t.inbound.listen((bytes) => received.add(utf8.decode(bytes)));

      port.receive('data:');
      port.receive(Uint8List.fromList(utf8.encode('ok\n')).buffer);
      await pumpEventQueue();

      expect(received, ['data:', 'ok\n']);
    });

    test('a close from the far end completes inbound', () async {
      final t = transport();
      port.closeFromPeer();
      await expectLater(t.inbound.toList(), completion(isEmpty));
    });

    test('frames held while paused are delivered in order on resume', () async {
      final t = transport();
      final received = <String>[];
      final subscription =
          t.inbound.listen((bytes) => received.add(utf8.decode(bytes)));
      subscription.pause();

      port.receive('abcd');
      port.receive('efgh');
      await pumpEventQueue();
      expect(received, isEmpty);

      subscription.resume();
      await pumpEventQueue();
      expect(received, ['abcd', 'efgh']);
      expect(port.closeCalls, 0);
    });

    test(
        'frames held while paused, then a close from the far end, are all '
        'delivered before inbound is done', () async {
      final t = transport(maxInboundBytes: 100);
      final received = <String>[];
      final done = Completer<void>();
      final subscription = t.inbound.listen(
          (bytes) => received.add(utf8.decode(bytes)),
          onDone: done.complete);
      subscription.pause();

      port.receive('abcd');
      port.receive('efgh');
      port.closeFromPeer();
      await pumpEventQueue();
      subscription.resume();
      await done.future;

      expect(received, ['abcd', 'efgh'],
          reason: 'the far end closing ends inbound after what it sent');
    });

    test(
        'a listener that pauses during a drain stops it, and what it left '
        'still counts against the bound', () async {
      final t = transport(maxInboundBytes: 10);
      final received = <String>[];
      late StreamSubscription<List<int>> subscription;
      subscription = t.inbound.listen((bytes) {
        received.add(utf8.decode(bytes));
        subscription.pause();
      });
      subscription.pause();
      port.receive('1234');
      port.receive('5678');
      await pumpEventQueue();

      subscription.resume();
      await pumpEventQueue();
      expect(received, ['1234'], reason: 'the premise: the drain met a pause');
      expect(port.closeCalls, 0);

      port.receive('1234567');
      await pumpEventQueue();

      expect(port.closeCalls, 1,
          reason: '5678 is still held, so 11 bytes are held against a bound '
              'of 10');
    });

    test('exactly the bound may be held, and one byte more closes the socket',
        () async {
      final t = transport(maxInboundBytes: 10);
      final subscription = t.inbound.listen((_) {}, onError: (_) {});
      subscription.pause();

      port.receive('1234567890');
      await pumpEventQueue();
      expect(port.closeCalls, 0, reason: '10 bytes held, a bound of 10');

      port.receive('1');
      await pumpEventQueue();
      expect(port.closeCalls, 1, reason: '11 bytes held, a bound of 10');
    });

    test(
        'held bytes past the bound close the socket and end inbound with '
        'an AtIOException, logged once', () async {
      final t = transport(maxInboundBytes: 10);
      final errors = <Object>[];
      final done = Completer<void>();
      final subscription =
          t.inbound.listen((_) {}, onError: errors.add, onDone: done.complete);
      subscription.pause();

      port.receive('123456');
      port.receive('789012');
      port.receive('345678');
      await pumpEventQueue();

      expect(port.closeCalls, 1, reason: 'the far end is told at once');
      subscription.resume();
      await done.future;
      expect(errors, [isA<AtIOException>()]);
      expect(logs.warnings, hasLength(1));
      expect(() => t.add([1]), throwsA(isA<AtIOException>()));
    });

    test('frames that arrive before anyone listens count against the bound',
        () async {
      final t = transport(maxInboundBytes: 10);
      port.receive('123456');
      port.receive('789012');
      await pumpEventQueue();

      expect(port.closeCalls, 1);
      await expectLater(t.inbound.toList(), throwsA(isA<AtIOException>()));
    });

    test(
        'delivered bytes leave the bound: many small paused spells never '
        'trip it', () async {
      final t = transport(maxInboundBytes: 10);
      final received = <String>[];
      final subscription =
          t.inbound.listen((bytes) => received.add(utf8.decode(bytes)));

      for (var i = 0; i < 5; i++) {
        subscription.pause();
        port.receive('12345678');
        await pumpEventQueue();
        subscription.resume();
        await pumpEventQueue();
      }

      expect(received, hasLength(5));
      expect(port.closeCalls, 0);
      expect(logs.warnings, isEmpty);
    });
  });

  group('flush', () {
    test('completes at once when nothing is buffered', () async {
      await transport().flush();
    });

    test('does not complete while bufferedAmount is above zero', () async {
      final t = transport();
      port.bufferedAmount = 512;
      var flushed = false;
      final flush = t.flush().then((_) => flushed = true);

      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(flushed, isFalse);

      port.bufferedAmount = 0;
      await flush;
      expect(flushed, isTrue);
    });

    test('throws AtTimeoutException when the buffer never drains', () async {
      final t = transport(flushTimeout: const Duration(milliseconds: 30));
      port.bufferedAmount = 512;
      await expectLater(t.flush(), throwsA(isA<AtTimeoutException>()));
    });

    test('throws AtIOException when the socket closes before it drains',
        () async {
      final t = transport();
      port.bufferedAmount = 512;
      final flush = t.flush();
      port.closeFromPeer();
      await expectLater(flush, throwsA(isA<AtIOException>()));
    });
  });

  group('add', () {
    test('sends the bytes as one binary frame', () {
      transport().add(utf8.encode('noop:0\n'));
      expect(port.sent.map(utf8.decode), ['noop:0\n']);
    });

    test('after destroy throws AtIOException and sends nothing', () {
      final t = transport()..destroy();
      expect(() => t.add([1]), throwsA(isA<AtIOException>()));
      expect(port.sent, isEmpty);
    });

    test('once the far end has closed throws AtIOException and sends nothing',
        () async {
      final t = transport();
      port.closeFromPeer();
      await pumpEventQueue();
      expect(() => t.add([1]), throwsA(isA<AtIOException>()));
      expect(port.sent, isEmpty);
    });

    test('while the socket is not OPEN throws AtIOException', () {
      final t = transport();
      port.isOpen = false;
      expect(() => t.add([1]), throwsA(isA<AtIOException>()));
      expect(port.sent, isEmpty);
    });
  });

  test('destroy closes the socket once and completes inbound', () async {
    final t = transport()
      ..destroy()
      ..destroy();
    expect(port.closeCalls, 1);
    await expectLater(t.inbound.toList(), completion(isEmpty));
  });
}

class FakeWebSocketPort implements WebSocketPort {
  final _messages = StreamController<Object?>(sync: true);
  final _closes = StreamController<void>.broadcast(sync: true);
  final sent = <List<int>>[];
  int closeCalls = 0;

  @override
  bool isOpen = true;

  @override
  int bufferedAmount = 0;

  @override
  Stream<Object?> get onMessage => _messages.stream;

  @override
  Stream<void> get onClose => _closes.stream;

  @override
  void send(Uint8List bytes) => sent.add(bytes);

  @override
  void close() {
    closeCalls++;
    isOpen = false;
  }

  void receive(Object data) => _messages.add(data);

  void closeFromPeer() {
    isOpen = false;
    _closes.add(null);
  }
}

class RecordingHandler implements LoggingHandler {
  final warnings = <String>[];

  @override
  void call(record) {
    if (record.level.name == 'WARNING') warnings.add(record.message);
  }
}
