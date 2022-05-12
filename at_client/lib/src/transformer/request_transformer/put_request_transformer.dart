import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_client/at_client.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_client/src/exception/at_client_error_codes.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_utils/at_utils.dart';

/// Class responsible for transforming the put request from [AtKey] to [VerbBuilder]
class PutRequestTransformer
    extends RequestTransformer<Tuple<AtKey, dynamic>, VerbBuilder> {
  @override
  Future<UpdateVerbBuilder> transform(Tuple<AtKey, dynamic> tuple,
      {RequestOptions? requestOptions}) async {
    // Set the default metadata if not already set.
    tuple.one.metadata ??= Metadata();
    // Set sharedBy to currentAtSign if not set.
    tuple.one.sharedBy ??=
        AtClientManager.getInstance().atClient.getCurrentAtSign();
    tuple.one.sharedBy = AtUtils.formatAtSign(tuple.one.sharedBy);
    // Populate the update verb builder
    UpdateVerbBuilder updateVerbBuilder = _populateUpdateVerbBuilder(tuple.one);
    // If atKey.metadata.isBinary is true, encode the data; else set the value.
    // By default, in populatedUpdateVerbBuilder,tuple.one.metadata.isBinary
    // will be set to false .
    if (tuple.one.metadata!.isBinary!) {
      if (tuple.two is! List<int>) {
        throw AtClientException(atClientErrorCodes['AtClientException'],
            'List<int> is expected when isBinary in metadata is set to true');
      }
      if (tuple.two != null &&
          tuple.two.length >
              AtClientManager.getInstance()
                  .atClient
                  .getPreferences()!
                  .maxDataSize) {
        throw AtClientException('AT0005', 'BufferOverFlowException');
      }
      updateVerbBuilder.value = _encodeBinaryData(tuple.two);
    } else {
      updateVerbBuilder.value = tuple.two;
    }
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

  /// Encode the binary data
  String _encodeBinaryData(List<int> value) {
    return Base2e15.encode(value);
  }
}
