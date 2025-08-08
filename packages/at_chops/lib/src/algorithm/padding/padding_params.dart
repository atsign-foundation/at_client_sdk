/// A class that defines parameters for padding algorithms used in AES encryption.
///
/// The `PaddingParams` class provides configurable parameters required for
/// padding algorithms, such as the block size. These parameters are used to
/// ensure that data conforms to the block size required by AES encryption.
class PaddingParams {
  /// The block size (in bytes) used for padding.
  ///
  /// The default value is `16`, which corresponds to the block size of AES encryption.
  /// This value determines the size to which input data will be padded to ensure
  /// compatibility with the encryption algorithm.
  int blockSize = 16;
}
