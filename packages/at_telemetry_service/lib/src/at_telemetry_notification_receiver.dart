import 'dart:async';

import 'package:at_client/at_client.dart' show AtNotification;
import 'package:at_telemetry/at_telemetry.dart';
import 'package:at_telemetry/at_telemetry_otel.dart';

import 'at_telemetry_ingestor.dart';
import 'at_telemetry_producer_authenticator.dart';
import 'at_telemetry_producer_identity.dart';

enum AtTelemetryNotificationOutcome {
  accepted,
  unauthorized,
  invalid,
  failed,
}

typedef AtTelemetryNotificationOutcomeHandler = void Function(
  AtNotification notification,
  AtTelemetryNotificationOutcome outcome,
);

final class AtTelemetryNotificationReceiver {
  static const int defaultMaxPayloadCharacters = 4 * ((1024 * 1024 + 2) ~/ 3);

  final AtTelemetryProducerAuthenticator _authenticator;
  final AtTelemetryIngestor _ingestor;
  final AtTelemetryNotificationCodec _codec;
  final int _maxPayloadCharacters;
  final AtTelemetryNotificationOutcomeHandler? _onOutcome;

  AtTelemetryNotificationReceiver({
    required AtTelemetryProducerAuthenticator authenticator,
    required AtTelemetryIngestor ingestor,
    AtTelemetryNotificationCodec codec = const AtTelemetryNotificationCodec(),
    int maxPayloadCharacters = defaultMaxPayloadCharacters,
    AtTelemetryNotificationOutcomeHandler? onOutcome,
  })  : _authenticator = authenticator,
        _ingestor = ingestor,
        _codec = codec,
        _maxPayloadCharacters = maxPayloadCharacters,
        _onOutcome = onOutcome {
    if (maxPayloadCharacters <= 0) {
      throw RangeError.value(
        maxPayloadCharacters,
        'maxPayloadCharacters',
        'must be greater than zero',
      );
    }
  }

  StreamSubscription<AtTelemetryNotificationOutcome> listen(
    Stream<AtNotification> notifications,
  ) {
    return notifications
        .asyncMap<AtTelemetryNotificationOutcome>(handle)
        .listen(null);
  }

  Future<AtTelemetryNotificationOutcome> handle(
    AtNotification notification,
  ) async {
    final AtTelemetryNotificationOutcome outcome = await _handle(notification);
    _onOutcome?.call(notification, outcome);
    return outcome;
  }

  Future<AtTelemetryNotificationOutcome> _handle(
    AtNotification notification,
  ) async {
    final AtTelemetryProducerIdentity? producer;
    try {
      producer = await _authenticator.authenticate(notification.from);
    } on Object {
      return AtTelemetryNotificationOutcome.failed;
    }
    if (producer == null) {
      return AtTelemetryNotificationOutcome.unauthorized;
    }

    final String? payload = notification.value;
    if (payload == null ||
        payload.isEmpty ||
        payload.length > _maxPayloadCharacters) {
      return AtTelemetryNotificationOutcome.invalid;
    }

    final List<AtTelemetryEvent> events;
    try {
      events = _codec.decode(payload);
    } on FormatException {
      return AtTelemetryNotificationOutcome.invalid;
    }

    try {
      await _ingestor.ingest(producer: producer, events: events);
    } on Object {
      return AtTelemetryNotificationOutcome.failed;
    }
    return AtTelemetryNotificationOutcome.accepted;
  }
}
