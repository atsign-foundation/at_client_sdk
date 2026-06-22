import 'package:at_chops/src/metadata/signing_metadata.dart';

/// Class that contains the signing/verification result with data type [AtSigningResultType] and metadata [AtSigningMetaData]
/// [result] should be base64Encoded string
@Deprecated('Use the direct signing algorithm result bytes instead. This '
    'compatibility API will be removed in the next major release.')
class AtSigningResult {
  late AtSigningResultType atSigningResultType;

  dynamic result;
  late AtSigningMetaData atSigningMetaData;

  @override
  toString() {
    return 'ResultType: ${atSigningResultType.name}, '
        'Result: ${result.toString()}, '
        'SigningMetadata: {${atSigningMetaData.toString()}}';
  }
}

@Deprecated('Use the direct signing algorithm result bytes instead. This '
    'compatibility API will be removed in the next major release.')
enum AtSigningResultType { bytes, string, bool }
