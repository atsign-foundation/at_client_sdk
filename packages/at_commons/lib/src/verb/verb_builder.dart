/// VerbBuilder is used to build @protocol command that can be executed by a secondary server.
abstract class VerbBuilder {
  /// Build the @ command to be sent to remote secondary for execution.
  String buildCommand();

  /// Checks whether all params required by the verb builder are set. Returns false if
  /// required params are not set.
  bool checkParams();
}
