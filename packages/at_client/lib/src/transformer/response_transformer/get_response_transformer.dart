import 'dart:async';

import 'package:at_client/src/client/at_client_spec.dart';
import 'package:at_base2e15/at_base2e15.dart';
import 'package:at_client/src/converters/decoder/at_decoder.dart';
import 'package:at_client/src/decryption_service/decryption_manager.dart';
import 'package:at_client/src/response/default_response_parser.dart';
import 'package:at_client/src/response/json_utils.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_client/src/transformer/at_transformer.dart';
import 'package:at_commons/at_commons.dart';

/// Class responsible for transforming the Get response
/// Transform's the Get Response to [AtValue]
///
/// Decodes the binary data and decrypts the encrypted data
class GetResponseTransformer
    implements Transformer<Tuple<AtKey, String>, AtValue> {
  late final AtClient _atClient;

  GetResponseTransformer(this._atClient);

  @override
  FutureOr<AtValue> transform(Tuple<AtKey, String> tuple) async {
    var atValue = AtValue();
    var decodedResponse =
        JsonUtils.decodeJson(DefaultResponseParser().parse(tuple.two).response);

    atValue.value = decodedResponse['data'];
    // parse metadata
    if (decodedResponse['metaData'] != null) {
      final metadata = AtClientUtil.prepareMetadata(
          decodedResponse['metaData'], _isKeyPublic(decodedResponse['key']));
      atValue.metadata = metadata;
      tuple.one.metadata = metadata;
    }

    // For public and cached public keys, data is not encrypted.
    // Decrypt the data, for other keys
    if (!(decodedResponse['key'].startsWith('public:')) &&
        !(decodedResponse['key'].startsWith('cached:public:'))) {
      var decryptionService =
          AtKeyDecryptionManager(_atClient).get(tuple.one, _atClient.getCurrentAtSign()!);
      try {
        atValue.value =
            await decryptionService.decrypt(tuple.one, atValue.value) as String;
      } on AtException catch (e) {
        e.stack(AtChainedException(Intent.fetchData,
            ExceptionScenario.decryptionFailed, 'Failed to decrypt the data'));
        rethrow;
      }
    }

    if (((decodedResponse['key'].startsWith('public:')) ||
            (decodedResponse['key'].startsWith('cached:public:'))) &&
        (atValue.metadata!.encoding.isNotNull)) {
      atValue.value = AtDecoderImpl()
          .decodeData(atValue.value, atValue.metadata!.encoding!);
    }

    // After decrypting the data, if data is binary, decode the data
    // For cached keys, isBinary is not on server-side. Hence getting
    // isBinary from AtKey.
    if (tuple.one.metadata != null &&
        tuple.one.metadata!.isBinary != null &&
        tuple.one.metadata!.isBinary!) {
      atValue.value = Base2e15.decode(atValue.value);
    }
    return atValue;
  }

  /// Return true if key is a public key or a cached public key
  /// Else returns false
  bool _isKeyPublic(String key) {
    return key.startsWith('public:') || key.startsWith('cached:public:');
  }
}
