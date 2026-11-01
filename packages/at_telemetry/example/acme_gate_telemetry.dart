import 'package:at_telemetry/at_telemetry.dart';

final class AcmeGateTelemetry {
  static const String serviceName = 'acme_gate';

  static const String unlockedEvent = 'acme_gate.door.unlocked';
  static const String refusedEvent = 'acme_gate.door.refused';
  static const String failedEvent = 'acme_gate.door.failed';
  static const String recoveredEvent = 'acme_gate.door.recovered';
  static const String deskUnresponsiveEvent = 'acme_gate.desk.unresponsive';
  static const String deskRecoveredEvent = 'acme_gate.desk.recovered';

  static const String doorAttribute = 'acme_gate.door.id';
  static const String requestedByAttribute = 'acme_gate.command.from';
  static const String durationAttribute = 'acme_gate.unlock.duration_ms';
  static const String refusedReasonAttribute = 'acme_gate.refused.reason';
  static const String failedCommandsAttribute =
      'acme_gate.door.failed_commands';
  static const String deskAttribute = 'acme_gate.desk';
  static const String unansweredAttribute = 'acme_gate.desk.unanswered_updates';
  static const String anomalyKindAttribute = 'anomaly.kind';
  static const String anomalyMessageAttribute = 'anomaly.message';

  static const String deviceFault = 'device_fault';
  static const String peerUnresponsive = 'peer_unresponsive';

  static const int unansweredLimit = 3;

  final AtTelemetry _telemetry;
  final Map<String, int> _failedCommands = <String, int>{};
  final Map<String, int> _unansweredUpdates = <String, int>{};

  AcmeGateTelemetry(this._telemetry);

  void doorUnlocked({
    required String door,
    required String requestedBy,
    required Duration took,
    required String commandNotificationId,
  }) {
    final int? failedCommands = _failedCommands.remove(door);
    if (failedCommands != null) {
      _telemetry.event(
        recoveredEvent,
        severity: AtTelemetrySeverity.info,
        attributes: <String, Object?>{
          doorAttribute: door,
          failedCommandsAttribute: failedCommands,
        },
      );
    }
    _telemetry.event(
      unlockedEvent,
      severity: AtTelemetrySeverity.info,
      attributes: <String, Object?>{
        doorAttribute: door,
        requestedByAttribute: requestedBy,
        durationAttribute: took.inMilliseconds,
      },
      notificationIds: <String>[commandNotificationId],
    );
  }

  void doorRefused({
    required String door,
    required String requestedBy,
    required String reason,
    required String commandNotificationId,
  }) {
    _telemetry.event(
      refusedEvent,
      severity: AtTelemetrySeverity.warn,
      attributes: <String, Object?>{
        doorAttribute: door,
        requestedByAttribute: requestedBy,
        refusedReasonAttribute: reason,
      },
      notificationIds: <String>[commandNotificationId],
    );
  }

  void doorFailed({
    required String door,
    required String requestedBy,
    required String commandNotificationId,
  }) {
    final int failedCommands = (_failedCommands[door] ?? 0) + 1;
    _failedCommands[door] = failedCommands;
    if (failedCommands > 1) {
      return;
    }
    _telemetry.event(
      failedEvent,
      severity: AtTelemetrySeverity.error,
      attributes: <String, Object?>{
        doorAttribute: door,
        requestedByAttribute: requestedBy,
        anomalyKindAttribute: deviceFault,
        anomalyMessageAttribute: 'The $door door did not open when '
            '$requestedBy unlocked it. Check the door motor and its power.',
      },
      notificationIds: <String>[commandNotificationId],
    );
  }

  void statusUnanswered({required String desk}) {
    final int unanswered = (_unansweredUpdates[desk] ?? 0) + 1;
    _unansweredUpdates[desk] = unanswered;
    if (unanswered != unansweredLimit) {
      return;
    }
    _telemetry.event(
      deskUnresponsiveEvent,
      severity: AtTelemetrySeverity.error,
      attributes: <String, Object?>{
        deskAttribute: desk,
        unansweredAttribute: unanswered,
        anomalyKindAttribute: peerUnresponsive,
        anomalyMessageAttribute: '$desk has not answered the last $unanswered '
            'door status updates. Check that the front desk app is running.',
      },
    );
  }

  void statusAnswered({required String desk}) {
    final int? unanswered = _unansweredUpdates.remove(desk);
    if (unanswered == null || unanswered < unansweredLimit) {
      return;
    }
    _telemetry.event(
      deskRecoveredEvent,
      severity: AtTelemetrySeverity.info,
      attributes: <String, Object?>{
        deskAttribute: desk,
        unansweredAttribute: unanswered,
      },
    );
  }
}
