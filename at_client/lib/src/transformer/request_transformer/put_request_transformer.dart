import 'package:at_client/at_client.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart';

/// Class responsible for transforming the put request from [AtKey] to [VerbBuilder]
class PutRequestTransformer
    extends Transformer<Tuple<AtKey, dynamic>, VerbBuilder> {
  @override
  Future<UpdateVerbBuilder> transform(Tuple<AtKey, dynamic> tuple) async {
    // Populate the update verb builder
    UpdateVerbBuilder updateVerbBuilder = _populateUpdateVerbBuilder(tuple.one);
    // Setting value to updateVerbBuilder
    updateVerbBuilder.value = tuple.two;
    //Encrypt the data for non public keys
    if (!tuple.one.metadata!.isPublic!) {
      var encryptionService = AtKeyEncryptionManager.get(tuple.one,
          AtClientManager.getInstance().atClient.getCurrentAtSign()!);
      updateVerbBuilder.value =
          await encryptionService.encrypt(tuple.one, updateVerbBuilder.value);
      updateVerbBuilder.sharedKeyEncrypted = tuple.one.metadata!.sharedKeyEnc;
      updateVerbBuilder.pubKeyChecksum = tuple.one.metadata!.pubKeyCS;
    }

    return updateVerbBuilder;
  }

  /// Populated [UpdateVerbBuilder] for the given [AtKey]
  UpdateVerbBuilder _populateUpdateVerbBuilder(AtKey atKey) {
    UpdateVerbBuilder updateVerbBuilder = UpdateVerbBuilder()
      ..atKey = AtClientUtil.getKeyWithNameSpace(atKey)
      ..sharedWith = AtUtils.formatAtSign(atKey.sharedWith)
      ..sharedBy = AtUtils.formatAtSign(atKey.sharedBy)
      ..isPublic =
          (atKey.metadata?.isPublic != null) ? atKey.metadata!.isPublic! : false
      ..isEncrypted = (atKey.metadata?.isEncrypted != null)
          ? atKey.metadata?.isEncrypted!
          : false
      ..isBinary = (atKey.metadata?.isBinary != null)
          ? atKey.metadata?.isBinary!
          : false;

    if (atKey.metadata!.ttl != null) {
      updateVerbBuilder.ttl = atKey.metadata!.ttl;
    }
    if (atKey.metadata!.ttb != null) {
      updateVerbBuilder.ttb = atKey.metadata!.ttb;
    }
    if (atKey.metadata!.ttr != null) {
      updateVerbBuilder.ttr = atKey.metadata!.ttr;
    }
    if (atKey.metadata!.ccd != null) {
      updateVerbBuilder.ccd = atKey.metadata!.ccd;
    }
    updateVerbBuilder.dataSignature = atKey.metadata!.dataSignature;
    return updateVerbBuilder;
  }
}
