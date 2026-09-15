/// Framing when a verb reply and a notification share one connection.
///
/// The notification connection carries verb traffic - the heartbeat probes it
/// with `noop:0` - so the listener has to keep two frame shapes apart in one
/// byte stream: a
/// notification is a line ending `\n`, a reply ends `\n@<prompt>@`. Neither
/// may consume the other.
///
/// Every case here is a real arrival pattern, and only those: the atServer
/// writes each frame with a single write, so one frame never appears INSIDE
/// another. What TCP is free to do is split a write anywhere and coalesce
/// adjacent ones, so two whole frames can reach the client in one chunk, or
/// one frame across several - which is what these cover.
///
/// ⛔ NOT covered, and known broken: a complete reply followed by a
/// notification in ONE chunk loses both. The scan over everything before a
/// chunk's last newline looks only for notifications, never for the `\n@`
/// reply terminator - deliberately, because a `data:` value may contain
/// `\n@` and inspecting those bytes would truncate it (the last test here is
/// that control). Disambiguating the two needs a delimiter the protocol does
/// not have yet - an atServer that terminated every notification the way it
/// terminates a reply would supply one. Measured shape, for whoever picks it
/// up: `data:ok\n@alice@notification: {...}\n` in a single chunk yields no
/// reply and no notification.
library;

import 'dart:async';

import 'package:at_lookup/src/connection/outbound_connection_impl.dart';
import 'package:at_lookup/src/connection/outbound_message_listener.dart';
import 'package:test/test.dart';

import 'fake_at_server_socket.dart';

void main() {
  /// Feeds [chunks] to a listener in order and reports what it emitted.
  Future<({String? reply, Object? error, List<String> notifications})> drive(
      List<String> chunks) async {
    final socket = FakeAtServerSocket();
    final connection = OutboundConnectionImpl(socket);
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
      await socket.serverSends(chunk);
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

    test('a multi-line reply value containing a prompt is NOT truncated',
        () async {
      // The control, and the reason the framing is careful: a `data:` value
      // may itself contain `\n@`, which must not be mistaken for the end of
      // the response. If a fix for the cases above breaks this, it has traded
      // one truncation for another.
      const multiline = 'data:first\n@bob:key@alice';
      final out = await drive(['$multiline\n@alice@']);

      expect(out.reply, multiline,
          reason: 'the inner `\\n@` belongs to the value, and only the final '
              'one terminates the response');
      expect(out.notifications, isEmpty);
    });
  });
}
