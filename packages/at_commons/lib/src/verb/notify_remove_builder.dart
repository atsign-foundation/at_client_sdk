import 'package:at_commons/at_builders.dart';

class NotifyRemoveVerbBuilder implements VerbBuilder {
  late String id;

  @override
  String buildCommand() {
    return 'notify:remove:$id\n';
  }

  @override
  bool checkParams() {
    // Returns false if id is not set
    return id.isNotEmpty;
  }
}
