/// An abstract class that defines a padding algorithm for AES encryption and decryption.
///
/// The `PaddingAlgorithm` class provides methods to add padding bytes during encryption
/// and to remove padding bytes during decryption. Padding ensures that the input data
/// size is compatible with the block size required by AES encryption algorithms.
abstract class PaddingAlgorithm {
  /// Adds padding bytes to the given [data] to make its length a multiple of the AES block size.
  ///
  /// This method appends padding bytes to the input data so that its length becomes
  /// a multiple of the AES block size (16 bytes). The exact padding scheme is
  /// implementation-dependent.
  ///
  /// - [data]: A list of bytes representing the input data to be padded.
  /// - Returns: A new list of bytes containing the padded data.
  ///
  /// Example usage:
  /// ```dart
  /// PaddingAlgorithm paddingAlgorithm = PKCS7Padding();
  /// List<int> paddedData = paddingAlgorithm.addPadding([0x01, 0x02, 0x03]);
  /// ```
  List<int> addPadding(List<int> data);

  /// Removes padding bytes from the given [data], restoring it to its original unpadded form.
  ///
  /// This method removes any padding bytes that were added during encryption to return
  /// the data to its original state. The exact removal logic depends on the padding
  /// scheme used during encryption.
  ///
  /// - [data]: A list of bytes representing the padded input data.
  /// - Returns: A new list of bytes containing the original unpadded data.
  ///
  /// Example usage:
  /// ```dart
  /// PaddingAlgorithm paddingAlgorithm = PKCS7Padding();
  /// List<int> unpaddedData = paddingAlgorithm.removePadding([0x01, 0x02, 0x03, 0x05, 0x05, 0x05]);
  /// ```
  List<int> removePadding(List<int> data);
}
