import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/converters/encoder/at_encoder.dart';
import 'package:at_client/src/encryption_service/encryption_manager.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_commons/at_builders.dart';
import 'package:at_commons/at_commons.dart';

/// Class responsible for transforming the put request from [AtKey] to [VerbBuilder]
class PutRequestTransformer
    extends RequestTransformer<Tuple<AtKey, dynamic>, VerbBuilder> {
  late final AtClient _atClient;

  set atClient(AtClient value) {
    _atClient = value;
  }

  /// the default encoding when the value contains a new line character.
  EncodingType encodingType = EncodingType.base64;

  static final PutRequestOptions defaultOptions = PutRequestOptions();

  @override
  // ignore: avoid_renaming_method_parameters
  Future<UpdateVerbBuilder> transform(Tuple<AtKey, dynamic> tuple,
      {String? encryptionPrivateKey, RequestOptions? requestOptions}) async {
    PutRequestOptions options = (requestOptions != null
        ? requestOptions as PutRequestOptions
        : defaultOptions);

    UpdateVerbBuilder updateVerbBuilder = UpdateVerbBuilder();
    updateVerbBuilder.atKey = tuple.one;
    // Append '@' to the atSign if missed.
    AtClientUtil.fixAtSign(updateVerbBuilder.atKey.sharedWith);
    AtClientUtil.fixAtSign(updateVerbBuilder.atKey.sharedBy);
    // Setting updateVerbBuilder.value
    updateVerbBuilder.value = tuple.two;
    final atKey = updateVerbBuilder.atKey;
    final metadata = atKey.metadata;
    // Check if the data needs to be encrypted for non-public keys
    if (!_isPublicKey(metadata) && options.shouldEncrypt) {
      await _encryptData(updateVerbBuilder, options);
    } else {
      // Sign the data for public keys
      if (_isPublicKey(metadata)) {
        _signPublicData(updateVerbBuilder, encryptionPrivateKey);
      }
      // Encode the data if it contains new line characters
      _encodeIfValueContainsNewLine(updateVerbBuilder);
    }

    return updateVerbBuilder;
  }

  Future<void> _encryptData(
      UpdateVerbBuilder updateVerbBuilder, PutRequestOptions options) async {
    var encryptionService = AtKeyEncryptionManager(_atClient)
        .get(updateVerbBuilder.atKey, _atClient.getCurrentAtSign()!);
    try {
      updateVerbBuilder.value = await encryptionService.encrypt(
          updateVerbBuilder.atKey, updateVerbBuilder.value,
          storeSharedKeyEncryptedWithData:
              options.storeSharedKeyEncryptedMetadata);
      updateVerbBuilder.atKey.metadata.isEncrypted = true;
    } on AtException catch (e) {
      e.stack(AtChainedException(Intent.shareData,
          ExceptionScenario.encryptionFailed, 'Failed to encrypt the data'));
      rethrow;
    }
  }

  void _signPublicData(
      UpdateVerbBuilder updateVerbBuilder, String? encryptionPrivateKey) {
    if (encryptionPrivateKey.isNull) {
      throw AtPrivateKeyNotFoundException('Failed to sign the public data');
    }
    final atSigningInput = AtSigningInput(updateVerbBuilder.value)
      ..signingMode = AtSigningMode.data;
    final signingResult = _atClient.atChops!.sign(atSigningInput);
    updateVerbBuilder.atKey.metadata.dataSignature = signingResult.result;
  }

  void _encodeIfValueContainsNewLine(UpdateVerbBuilder updateVerbBuilder) {
    if (updateVerbBuilder.value.contains('\n')) {
      updateVerbBuilder.value =
          AtEncoderImpl().encodeData(updateVerbBuilder.value, encodingType);
      updateVerbBuilder.atKey.metadata.encoding = encodingType.toShortString();
    }
  }

  bool _isPublicKey(Metadata metadata) => metadata.isPublic;
}
