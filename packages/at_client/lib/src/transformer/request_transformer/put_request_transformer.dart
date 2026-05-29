import 'package:at_chops/at_chops.dart';
import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_client/src/client/request_options.dart';
import 'package:at_client/src/converters/encoder/at_encoder.dart';
import 'package:at_client/src/crypto/crypto_runtime.dart';
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
      // Add metadata for the crypto provider used to route future decrypts.
      updateVerbBuilder.atKey.metadata.appMetadata =
          AppMetadata(_cryptoProviderIdFor(options));
      await _encryptData(updateVerbBuilder);
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

  Future<void> _encryptData(UpdateVerbBuilder updateVerbBuilder) async {
    final result = await CryptoRuntime(_atClient)
        .encryptForPut(updateVerbBuilder.atKey, updateVerbBuilder.value);
    updateVerbBuilder.value = result.ciphertext;
    // using appMetadata from result
    updateVerbBuilder.atKey.metadata.appMetadata = result.metadata;
    updateVerbBuilder.atKey.metadata.isEncrypted = result.isEncrypted;
  }

  String _cryptoProviderIdFor(PutRequestOptions options) {
    return options.cryptoProviderId ??
        _atClient.getPreferences()?.crypto.defaultProviderId ??
        CryptoRuntime.legacyProviderId;
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
