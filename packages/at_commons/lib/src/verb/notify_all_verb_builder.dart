import 'package:at_commons/src/verb/abstract_verb_builder.dart';
import 'package:at_commons/src/verb/operation_enum.dart';
import 'package:at_commons/src/verb/verb_util.dart';

class NotifyAllVerbBuilder extends AbstractVerbBuilder {
  /// Value of the key typically in string format. Images, files, etc.,
  /// must be converted to unicode string before storing.
  dynamic value;

  /// AtSign to whom [atKey] has to be shared.
  List? sharedWithList;

  OperationEnum? operation;

  @override
  String buildCommand() {
    StringBuffer serverCommandBuffer = StringBuffer('notify:');

    if (operation != null) {
      serverCommandBuffer.write('${getOperationName(operation)}:');
    }
    if (atKey.metadata.ttl != null) {
      serverCommandBuffer.write('ttl:${atKey.metadata.ttl}:');
    }
    if (atKey.metadata.ttb != null) {
      serverCommandBuffer.write('ttb:${atKey.metadata.ttb}:');
    }
    if (atKey.metadata.ttr != null) {
      atKey.metadata.ccd ??= false;
      serverCommandBuffer
          .write('ttr:${atKey.metadata.ttr}:ccd:${atKey.metadata.ccd}:');
    }
    if (sharedWithList != null && sharedWithList!.isNotEmpty) {
      var sharedWith = sharedWithList!.join(',');
      serverCommandBuffer.write('${VerbUtil.formatAtSign(sharedWith)}:');
    }
    if (atKey.metadata.isPublic == true) {
      serverCommandBuffer.write('public:');
    }
    serverCommandBuffer.write(atKey.toString());
    if (atKey.sharedBy != null) {
      serverCommandBuffer.write('${VerbUtil.formatAtSign(atKey.sharedBy)}');
    }
    if (value != null) {
      serverCommandBuffer.write(':$value');
    }
    return (serverCommandBuffer..write('\n')).toString();
  }

  @override
  bool checkParams() {
    var isValid = true;
    if ((atKey.key.isNotEmpty) ||
        (atKey.metadata.isPublic == true && sharedWithList != null)) {
      isValid = false;
    }
    return isValid;
  }
}
