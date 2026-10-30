import 'package:at_chops/src/algorithm/algo_type.dart';

/// Class which represents metadata for data signing.
@Deprecated(
    'Use direct signing algorithm results and your own metadata instead. This '
    'compatibility API will be removed in the next major release.')
class AtSigningMetaData {
  HashingAlgoType? hashingAlgoType;
  SigningAlgoType? signingAlgoType;

  ///Timestamp of signature creation in UTC
  DateTime signatureTimestamp;

  AtSigningMetaData(
      this.signingAlgoType, this.hashingAlgoType, this.signatureTimestamp);

  @override
  toString() {
    return 'HashingAlgo: ${hashingAlgoType?.name}, '
        'SigningAlgo: ${signingAlgoType?.name}, '
        'SignatureTimestamp: ${signatureTimestamp.toString()}';
  }
}
