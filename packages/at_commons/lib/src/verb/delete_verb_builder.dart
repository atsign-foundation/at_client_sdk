import 'package:at_commons/src/at_constants.dart';
import 'package:at_commons/src/exception/at_client_exceptions.dart';
import 'package:at_commons/src/utils/string_utils.dart';
import 'package:at_commons/src/verb/abstract_verb_builder.dart';
import 'package:at_commons/src/verb/syntax.dart';
import 'package:at_commons/src/verb/verb_util.dart';

/// Delete verb builder generates a command to delete a [atKey] from the secondary server.
/// ```
/// // @bob deleting a public phone key
///    var deleteBuilder = DeleteVerbBuilder()..key = 'public:phone@bob';
/// // @bob deleting the key “phone” shared with @alice
///    var deleteBuilder = DeleteVerbBuilder()..key = '@alice:phone@bob';
/// ```
class DeleteVerbBuilder extends AbstractVerbBuilder {
  bool force = false;

  @override
  String buildCommand() {
    StringBuffer serverCommandBuffer = StringBuffer('delete:');
    if (force) {
      serverCommandBuffer.write('force:');
    }
    serverCommandBuffer.write('${buildKey()}\n');
    return serverCommandBuffer.toString();
  }

  /// Returns a builder instance from a delete command
  static DeleteVerbBuilder getBuilder(String command) {
    var builder = DeleteVerbBuilder();
    var verbParams = VerbUtil.getVerbParam(VerbSyntax.delete, command)!;

    builder.atKey.metadata.isPublic =
        verbParams[AtConstants.publicScopeParam] == 'public';
    builder.force = verbParams[AtConstants.force] == AtConstants.force;
    builder.atKey.sharedWith =
        VerbUtil.formatAtSign(verbParams[AtConstants.forAtSign]);
    builder.atKey.sharedBy =
        VerbUtil.formatAtSign(verbParams[AtConstants.atSign]);
    if (verbParams[AtConstants.atKey] == null) {
      throw AtKeyException('Key cannot be null or empty');
    }
    builder.atKey.key = verbParams[AtConstants.atKey]!;

    builder.validateKey();

    return builder;
  }

  @override
  bool checkParams() {
    return atKey.key.isNotNullOrEmpty;
  }

  String buildKey() {
    validateKey();
    return atKey.toString();
  }
}
