import 'package:at_commons/src/verb/abstract_verb_builder.dart';
import 'package:at_commons/src/verb/verb_util.dart';

import 'operation_enum.dart';

/// Builds a `notify:multi` command: one key-type value and its metadata,
/// notified to each of [recipients] by a single request.
///
/// An atServer that does not implement the verb refuses it outright, so
/// metadata can never be mistaken there for a recipient list.
class NotifyMultiVerbBuilder extends AbstractVerbBuilder {
  /// The atSigns to notify.
  List<String> recipients = [];

  /// The value every recipient is sent.
  dynamic value;

  /// Time in milliseconds after which the notifications expire.
  int? ttln;

  OperationEnum? operation;

  @override
  String buildCommand() {
    final sharedBy = atKey.sharedBy;
    if (recipients.isEmpty || sharedBy == null) {
      throw ArgumentError(
          'notify:multi needs at least one recipient and a sharedBy atSign');
    }
    final sb = StringBuffer('notify:multi');
    if (operation != null) {
      sb.write(':${getOperationName(operation)}');
    }
    if (ttln != null) {
      sb.write(':ttln:$ttln');
    }
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
      recipients.isNotEmpty && atKey.key.isNotEmpty && atKey.sharedBy != null;
}
