import 'dart:async';

import 'package:at_client/src/client/at_client_spec.dart' show AtClient;
import 'package:at_commons/at_commons.dart' show InfoFeature, InfoFeatures;
import 'package:at_utils/at_logger.dart' show AtSignLogger;

final _logger = AtSignLogger('AtServerFeatures');

/// The capabilities a client's atServer lists in its `info` features, read by
/// the rule [InfoFeatures] defines.
///
/// Asked once per connection to the atServer and reused while that connection
/// stays open: an atServer that is upgraded or rolled back restarts, which
/// drops the connection, so an answer is never older than the atServer that
/// gave it. A failure to ask, or an answer that cannot be read, counts as no
/// features and is not kept, so a caller degrades to what every atServer
/// accepts and the next call asks again.
class AtServerFeatures {
  static final Expando<AtServerFeatures> _byClient = Expando();

  /// The features of [atClient]'s atServer, shared by everything using that
  /// client.
  static AtServerFeatures of(AtClient atClient) =>
      _byClient[atClient] ??= AtServerFeatures(atClient);

  final AtClient _atClient;
  InfoFeatures? _features;
  Object? _askedOn;
  Future<InfoFeatures>? _asking;

  AtServerFeatures(this._atClient);

  /// Whether the atServer lists [feature] as present, logging a warning the
  /// first time on a connection that it is used while not `GA`.
  Future<bool> has(String feature) async =>
      (await _current()).has(feature, warn: _logger.warning);

  Future<InfoFeatures> _current() {
    final features = _features;
    if (features != null && identical(_connection, _askedOn)) {
      return Future.value(features);
    }
    return _asking ??= _ask().whenComplete(() => _asking = null);
  }

  Object? get _connection =>
      _atClient.getRemoteSecondary()?.atLookUp.connection;

  Future<InfoFeatures> _ask() async {
    try {
      final response = await _atClient
          .getRemoteSecondary()
          ?.executeCommand('info\n', auth: true);
      final features = response == null ? null : InfoFeatures.parse(response);
      final connection = _connection;
      if (features == null || connection == null) return InfoFeatures(const {});
      _features = features;
      _askedOn = connection;
      return features;
    } catch (_) {
      return InfoFeatures(const {});
    }
  }
}

/// How long an ephemeral notification may live, whatever its sender asked for.
const Duration ephemeralNotificationMaxLifetime = Duration(minutes: 2);

/// What a notification command carries for its lifetime on [atClient]'s
/// atServer: an explicit expiry where the atServer lists
/// [InfoFeature.notifyEAtn], else the relative `ttln` every atServer accepts,
/// and `eph` only where it lists [InfoFeature.notifyEph].
///
/// An ephemeral notification's [expiration] is clamped to
/// [ephemeralNotificationMaxLifetime].
Future<({int? ttln, DateTime? expiresAt, bool ephemeral})>
    notificationLifetimeFor(AtClient atClient,
        {required Duration expiration, bool ephemeral = false}) async {
  final features = AtServerFeatures.of(atClient);
  final sendsEph = ephemeral && await features.has(InfoFeature.notifyEph);
  final lifetime = sendsEph && expiration > ephemeralNotificationMaxLifetime
      ? ephemeralNotificationMaxLifetime
      : expiration;
  if (await features.has(InfoFeature.notifyEAtn)) {
    return (
      ttln: null,
      expiresAt: DateTime.now().toUtc().add(lifetime),
      ephemeral: sendsEph
    );
  }
  return (ttln: lifetime.inMilliseconds, expiresAt: null, ephemeral: sendsEph);
}
