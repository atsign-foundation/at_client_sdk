import 'package:at_chops/src/algorithm/padding/padding.dart';
import 'package:at_chops/src/algorithm/padding/padding_params.dart';
import 'package:at_commons/at_commons.dart';

class PKCS7Padding implements PaddingAlgorithm {
  final PaddingParams _paddingParams;
  PKCS7Padding(this._paddingParams);
  @override
  List<int> addPadding(List<int> data) {
    if (_paddingParams.blockSize == null ||
        _paddingParams.blockSize! <= 0 ||
        _paddingParams.blockSize! > 255) {
      throw AtEncryptionException('Block size must be between 1 and 255.');
    }

    // Calculate the number of padding bytes needed
    int padding =
        _paddingParams.blockSize! - (data.length % _paddingParams.blockSize!);

    // Add padding bytes to the data
    List<int> paddedData = List.from(data);
    paddedData.addAll(List.filled(padding, padding));

    return paddedData;
  }

  @override
  List<int> removePadding(List<int> data) {
    if (data.isEmpty) {
      throw AtDecryptionException('Encrypted data cannot be empty');
    }

    // Get the value of the last byte (padding length)
    int paddingLength = data.last;

    // Validate padding length
    if (paddingLength <= 0 || paddingLength > data.length) {
      throw AtDecryptionException('Invalid padding length');
    }

    // Check if all padding bytes are valid
    for (int i = data.length - paddingLength; i < data.length; i++) {
      if (data[i] != paddingLength) {
        throw AtDecryptionException('Invalid PKCS7 padding');
      }
    }

    // Return the data without padding
    return data.sublist(0, data.length - paddingLength);
  }
}
