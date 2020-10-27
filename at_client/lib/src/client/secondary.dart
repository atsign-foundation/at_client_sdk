import 'package:at_commons/at_builders.dart';

abstract class Secondary {
  Future<String> executeVerb(VerbBuilder builder,{bool sync});
}