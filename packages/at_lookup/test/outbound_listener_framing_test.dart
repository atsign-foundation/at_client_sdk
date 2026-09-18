/// Framing when a verb reply and a notification share one connection.
///
/// The notification connection carries verb traffic - the heartbeat probes it
/// with `noop:0` - so the listener has to keep the kinds apart in one byte
/// stream. Two properties of the protocol make that deterministic: every
/// message from the atServer ends at a newline, and the atServer writes one
/// message at a time. A line is therefore a message, and what it begins with -
/// once the prompt that may precede it is off - says which kind it is, so
/// neither kind can consume the other whatever order they arrive in.
///
/// Every case here is a real arrival pattern, and only those: the atServer
/// writes each message with a single write, so one never appears INSIDE
/// another. What TCP is free to do is split a write anywhere and coalesce
/// adjacent ones, so two whole messages can reach the client in one chunk, or
/// one across several - which is what these cover, along with the prompt for
/// the next command arriving in the same flow as the end of the last message.
library;

import 'dart:async';

import 'package:at_lookup/src/connection/outbound_connection_impl.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:test/test.dart';

import 'fake_at_server_transport.dart';

void main() {
  /// Feeds [chunks] to a listener in order and reports what it emitted.
  Future<({String? reply, Object? error, List<String> notifications})> drive(
      List<String> chunks) async {
    final transport = FakeAtServerTransport();
    final connection = OutboundConnectionImpl(transport);
    final listener = OutboundMessageListener(connection);
    final notifications = <String>[];
    listener.onNotification = notifications.add;
    listener.listen();

    String? reply;
    Object? error;
    final reading = listener
        .read(maxWaitMilliSeconds: 400)
        .then<void>((r) => reply = r)
        .catchError((Object e) => error = e);

    for (final chunk in chunks) {
      await transport.serverSends(chunk);
    }
    await reading;
    return (reply: reply, error: error, notifications: notifications);
  }

  const notif = 'notification: {"id":"n"}';
  const reply = 'data:ok';

  group('a reply and a notification in one stream', () {
    test('a whole notification before the reply keeps both', () async {
      final out = await drive(['$notif\n', '$reply\n@alice@']);

      expect(out.notifications, [notif]);
      expect(out.reply, reply);
    });

    test('a notification split across chunks keeps both', () async {
      final out =
          await drive(['notification: {"id"', ':"n"}\n', '$reply\n@alice@']);

      expect(out.notifications, [notif]);
      expect(out.reply, reply);
    });

    test('a notification and a reply coalesced into one chunk keep both',
        () async {
      final out = await drive(['$notif\n$reply\n@alice@']);

      expect(out.notifications, [notif]);
      expect(out.reply, reply);
    });

    test('a reply the atServer never terminated does not hide what follows',
        () async {
      // The shape this is about: anything the atServer says on a monitor
      // connection that is not a notification and never gets its prompt - an
      // error line, a banner, half a reply. It used to sit in front of every
      // notification after it, so none of them were recognised: the caller
      // went deaf on a connection that stayed up, until some later prompt
      // cleared the buffer.
      final out =
          await drive(['error:AT0011-Internal server error\n', '$notif\n']);

      expect(out.notifications, [notif],
          reason: 'the notification is a line of its own, whatever is stuck '
              'in front of it');
    });

    test('and that line is still there for the reply it belongs to', () async {
      final out = await drive(
          ['error:AT0011-Internal server error\n', '$notif\n', '@alice@']);

      expect(out.notifications, [notif]);
      expect(out.reply, contains('AT0011'),
          reason: 'the notification is taken out of the buffer, not the line '
              'in front of it: that one belongs to whatever reply the next '
              'prompt completes');
    });

    test('a reply, its prompt and a notification in one chunk keep both',
        () async {
      final out = await drive(['$reply\n@alice@$notif\n']);

      expect(out.notifications, [notif],
          reason: 'the prompt sits at the start of the notification, and a '
              'message is recognised by what it begins with once that is off');
      expect(out.reply, reply,
          reason: 'the reply ended at its own newline, so the prompt that '
              'followed it in the same chunk belongs to the notification and '
              'takes nothing with it');
    });

    test('a value carrying @ signs keeps them', () async {
      // The control on stripping the prompt: only one at the START of the
      // message comes off, so a value full of them is still the value.
      const withAts = 'data:@bob:key@alice';
      final out = await drive(['$withAts\n@alice@']);

      expect(out.reply, withAts,
          reason: 'the @ signs are inside the message, not in front of it');
      expect(out.notifications, isEmpty);
    });
  });
}
