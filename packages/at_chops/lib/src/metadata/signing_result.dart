import 'package:at_chops/src/metadata/signing_metadata.dart';

/// Class that contains the signing/verification result with data type [AtSigningResultType] and metadata [AtSigningMetaData]
/// [result] should be base64Encoded string
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

enum AtSigningResultType { bytes, string, bool }
