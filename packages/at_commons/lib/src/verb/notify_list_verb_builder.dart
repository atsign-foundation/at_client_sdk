import 'package:at_commons/at_builders.dart';

class NotifyListVerbBuilder implements VerbBuilder {
  String? fromDate;
  String? toDate;
  String? regex;

  @override
  String buildCommand() {
    StringBuffer serverCommandBuffer = StringBuffer('notify:list');

    if (fromDate != null) {
      serverCommandBuffer.write(':$fromDate');
    }
    if (toDate != null) {
      serverCommandBuffer.write(':$toDate');
    }
    if (regex != null) {
      serverCommandBuffer.write(':$regex');
    }
    return (serverCommandBuffer..write('\n')).toString();
  }

  @override
  bool checkParams() {
    var isValid = true;
    try {
      if (DateTime.parse(toDate!).millisecondsSinceEpoch <
          DateTime.parse(fromDate!).millisecondsSinceEpoch) {
        isValid = false;
      }
    } on Exception {
      isValid = false;
    }
    return isValid;
  }
}
