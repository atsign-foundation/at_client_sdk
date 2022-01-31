import 'package:at_client/src/client/verb_builder_manager.dart';
import 'package:at_client/src/manager/at_client_manager.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart';

/// Class responsible for transforming the Get Request
/// Transforms [AtKey] to [VerbBuilder]
class GetRequestTransformer implements Transformer<AtKey, VerbBuilder> {
  @override
  VerbBuilder transform(AtKey atKey) {
    // Set the default metadata if not already set.
    atKey.metadata ??= Metadata();
    // Set sharedBy to currentAtSign if not set.
    atKey.sharedBy ??= AtUtils.formatAtSign(
        AtClientManager.getInstance().atClient.getCurrentAtSign()!);
    // Get the verb builder for the given atKey
    VerbBuilder verbBuilder = LookUpBuilderManager.get(
        atKey, AtClientManager.getInstance().atClient.getCurrentAtSign()!);
    return verbBuilder;
  }
}
