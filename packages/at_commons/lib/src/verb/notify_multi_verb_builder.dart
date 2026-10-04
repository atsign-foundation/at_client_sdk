import 'package:at_commons/src/verb/abstract_verb_builder.dart';
import 'package:at_commons/src/verb/verb_util.dart';

/// Builds a `notify:multi` command: one key-type value and its metadata,
/// notified to each of [recipients] by a single request.
///
/// It is a pure notification: always an update, with no ttr or ccd, so no
/// recipient's atServer writes or removes a cached record.
class NotifyMultiVerbBuilder extends AbstractVerbBuilder {
  /// The atSigns to notify.
  List<String> recipients = [];

  /// The value every recipient is sent.
  dynamic value;

  /// Time in milliseconds after which the notifications expire.
  int? ttln;

  /// When the notifications expire, written as `eAtn`; set this or [ttln].
  DateTime? notificationExpiresAt;

  /// Whether no atServer persists the notifications, written as a bare `eph`.
  bool ephemeral = false;

  @override
  String buildCommand() {
    final sharedBy = atKey.sharedBy;
    if (recipients.isEmpty || sharedBy == null) {
      throw ArgumentError(
          'notify:multi needs at least one recipient and a sharedBy atSign');
    }
    if (atKey.metadata.ttr != null || atKey.metadata.ccd != null) {
      throw ArgumentError('notify:multi carries no ttr or ccd');
    }
    final sb = StringBuffer('notify:multi');
    sb.write(VerbUtil.notificationLifetime(
        ttln: ttln, expiresAt: notificationExpiresAt, ephemeral: ephemeral));
    sb.write(atKey.metadata.toAtProtocolFragment());
    sb.write(':${recipients.map(VerbUtil.formatAtSign).join(',')}');
    final namespace = atKey.namespace;
    sb.write(namespace == null || namespace.isEmpty
        ? ':${atKey.key}'
        : ':${atKey.key}.$namespace');
    sb.write(VerbUtil.formatAtSign(sharedBy));
    if (value != null) {
      sb.write(':$value');
    }
    sb.write('\n');
    return sb.toString();
  }

  @override
  bool checkParams() =>
      recipients.isNotEmpty &&
      atKey.key.isNotEmpty &&
      atKey.sharedBy != null &&
      atKey.metadata.ttr == null &&
      atKey.metadata.ccd == null;
}
