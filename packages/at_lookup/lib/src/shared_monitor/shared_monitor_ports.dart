/// The three platform seams a shared monitor stands on, and the messages the
/// tabs sharing it exchange.
///
/// A browser gives these as the Web Locks API, a `BroadcastChannel` and the
/// page's visibility, pageshow and online events (`at_lookup_web.dart`). A
/// test gives an in-memory rig. Nothing here names `package:web`, so the
/// role machine in `tab_muxable.dart` is tested on the VM.
library;

import 'dart:async';
import 'dart:convert';

/// Mutual exclusion among the tabs of one origin: whoever holds the lock for
/// a name is the one tab that keeps a monitor connection open for it.
abstract interface class MonitorLock {
  /// Asks for the lock called [name]. The request is granted once every
  /// earlier requester has released it, or at once with [steal], which takes
  /// the lock from its current holder (whose grant then reports [LockGrant.lost]).
  ///
  /// A request not yet granted is withdrawn with [LockRequest.abort].
  LockRequest request(String name, {bool steal = false});
}

/// A pending or granted [MonitorLock.request].
abstract interface class LockRequest {
  /// Completes with the grant; with a [LockRequestAborted] when [abort] came
  /// first.
  Future<LockGrant> get granted;

  /// Withdraws a request not yet granted. No effect once granted.
  void abort();
}

/// A held lock.
abstract interface class LockGrant {
  /// Completes when the lock was taken away by a [MonitorLock.request] with
  /// `steal: true`. Never completes for a lock given up with [release].
  Future<void> get lost;

  /// Gives the lock up, so the next requester is granted.
  Future<void> release();
}

/// Thrown into [LockRequest.granted] when the request was aborted first.
class LockRequestAborted implements Exception {
  const LockRequestAborted(this.name);

  final String name;

  @override
  String toString() => 'LockRequestAborted($name)';
}

/// A message bus among the tabs of one origin, one per name: a message
/// posted on one channel reaches every *other* open channel of the same
/// name, never the poster.
abstract interface class MonitorChannel {
  void post(String message);

  Stream<String> get messages;

  void close();
}

/// Opens the [MonitorChannel] called [name].
typedef MonitorChannelFactory = MonitorChannel Function(String name);

/// What a page learns about its own state that bears on a monitor connection.
enum PageEvent {
  /// The page became visible.
  visible,

  /// The page was shown, restored from the back-forward cache included.
  pageShow,

  /// The browser regained network connectivity.
  online,
}

abstract interface class PageLifecycle {
  Stream<PageEvent> get events;
}

/// What the tabs sharing one monitor say to each other, as the text that
/// travels on a [MonitorChannel].
///
/// A [LineMessage] is the raw `notification:` line as the atServer sent it,
/// ciphertext included; every tab decrypts for itself.
sealed class MonitorMessage {
  const MonitorMessage();

  /// Decodes [text]; `null` for text no tab of this version sent, so an
  /// older or newer tab on the same channel is ignored, not a failure.
  static MonitorMessage? decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException {
      return null;
    }
    if (json is! Map) return null;
    switch (json['t']) {
      case 'line':
        final line = json['v'];
        return line is String ? LineMessage(line) : null;
      case 'up':
        final up = json['v'];
        return up is bool ? UpMessage(up) : null;
      case 'hello':
        return const HelloMessage();
      case 'beacon':
        return const BeaconMessage();
      default:
        return null;
    }
  }

  String encode() => jsonEncode(_json);

  Map<String, Object?> get _json;
}

/// A notification the leader's connection received.
final class LineMessage extends MonitorMessage {
  const LineMessage(this.line);

  final String line;

  @override
  Map<String, Object?> get _json => {'t': 'line', 'v': line};
}

/// The leader's connection came up (`true`) or went down (`false`).
final class UpMessage extends MonitorMessage {
  const UpMessage(this.up);

  final bool up;

  @override
  Map<String, Object?> get _json => {'t': 'up', 'v': up};
}

/// A follower asks the leader to announce itself: it answers with an
/// [UpMessage] and a [BeaconMessage].
final class HelloMessage extends MonitorMessage {
  const HelloMessage();

  @override
  Map<String, Object?> get _json => const {'t': 'hello'};
}

/// The leader is alive; sent every beacon interval.
final class BeaconMessage extends MonitorMessage {
  const BeaconMessage();

  @override
  Map<String, Object?> get _json => const {'t': 'beacon'};
}
