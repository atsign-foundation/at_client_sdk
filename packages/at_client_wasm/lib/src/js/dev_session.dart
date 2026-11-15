import 'dart:async';

import 'package:at_client/at_client.dart';

/// A decrypted notification as the dev harness hands it to a page.
typedef DevNotification = ({
  String from,
  String key,
  String? value,
  int epochMillis,
});

/// String values under self keys of one app, plus shared-key notifications:
/// the dev harness's whole surface.
abstract interface class DevSession {
  Future<void> put(String key, String value);

  /// The value under [key], or null when there is none.
  Future<String?> get(String key);

  Future<void> delete(String key);

  /// Notifies [to] of [value] under the shared key `<to>:<key>.<namespace>@<me>`,
  /// encrypted for [to]; throws unless the atServer reports it delivered.
  Future<void> notify(String to, String key, String namespace, String value,
      {Duration? expiry});

  /// Calls [onEvent] with each decrypted notification whose key matches
  /// [regex], starting the monitor; the returned function unsubscribes.
  void Function() onNotification(
      String regex, void Function(DevNotification) onEvent);

  /// Stops the session; a second call does nothing.
  Future<void> close();
}

/// A [DevSession] on [AtClient], keying each value as `<key>.<app>@<atSign>`.
class AtClientDevSession implements DevSession {
  final AtClient _client;
  final String _app;
  bool _closed = false;

  AtClientDevSession(this._client, {required String app}) : _app = app;

  AtKey _atKey(String key) =>
      AtKey.self(key, namespace: _app, sharedBy: _client.getCurrentAtSign()!)
          .build();

  @override
  Future<void> put(String key, String value) => _client.put(_atKey(key), value);

  @override
  Future<String?> get(String key) async {
    try {
      return (await _client.get(_atKey(key))).value as String?;
    } on KeyNotFoundException {
      return null;
    }
  }

  @override
  Future<void> delete(String key) => _client.delete(_atKey(key));

  @override
  Future<void> notify(String to, String key, String namespace, String value,
      {Duration? expiry}) async {
    // Not namespace-aware: at_client would otherwise fold [namespace] into the
    // session's app namespace (`attalk.ai6bh` -> `attalk.ai6bh.<app>`), and a
    // peer subscribed to the caller's namespace would never see it.
    final atKey = (AtKey.shared(key,
            namespace: namespace, sharedBy: _client.getCurrentAtSign()!)
          ..sharedWith(to))
        .build()
      ..metadata.namespaceAware = false;
    final result = await _client.notificationService.notify(
        NotificationParams.forUpdate(atKey,
            value: value, notificationExpiry: expiry));
    if (result.notificationStatusEnum != NotificationStatusEnum.delivered) {
      // at_client's final-status switch has no default: expired, errored and
      // error:… replies all come back as undelivered with no exception, so
      // ask for the raw status. A failed query is named, not thrown: the
      // undelivered notification is the error the caller needs to see.
      if (result.atClientException case final cause?) throw cause;
      final id = result.notificationID;
      final status = await _client
          .notifyStatus(id)
          .catchError((Object e) => 'unknown ($e)');
      throw StateError('notification $id not delivered (status $status)');
    }
  }

  @override
  void Function() onNotification(
      String regex, void Function(DevNotification) onEvent) {
    final service = _client.notificationService;
    final subscription = service
        .subscribe(regex: regex, shouldDecrypt: true)
        .listen((n) => onEvent((
              from: n.from,
              key: n.key,
              value: n.value,
              epochMillis: n.epochMillis,
            )));
    service.startListening();
    return () => unawaited(subscription.cancel());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _client.stop();
  }
}
