import 'dart:convert';

import 'package:at_chops/src/algorithm/algo_type.dart';

/// A class that represents encrypted content, along with metadata such as
/// initialization vector (IV) and the hashing algorithm used.
///
/// This class is used to serialize and deserialize encrypted data for
/// transmission or storage. It provides methods to convert the object
/// to JSON format and parse it back from JSON.
@Deprecated('Use an application-specific encrypted payload model instead. This '
    'compatibility API will be removed in the next major release.')
class AtEncrypted {
  /// The encrypted content, typically represented as a Base64 string.
  String? content;

  /// The initialization vector (IV) used during encryption, which adds randomness
  /// to the encryption process and ensures the same content results in different
  /// ciphertexts.
  String? iv;

  /// The type of hashing algorithm used for encryption, represented by an
  /// enum of type [HashingAlgoType].
  HashingAlgoType? hashingAlgoType;

  /// Converts this [AtEncrypted] instance into a JSON-compatible map.
  ///
  /// The returned map includes the encrypted content, IV, and the name of the
  /// hashing algorithm used. The [hashingAlgoType] is converted to its string name.
  ///
  /// Returns a [Map] representing the encrypted data.
  Map<String, String?> toJson() {
    return {
      'content': content,
      'iv': iv,
      'hashingAlgoType': hashingAlgoType?.name
    };
  }

  /// Creates an [AtEncrypted] instance from a JSON-compatible map.
  ///
  /// This method takes a [Map] as input and assigns the corresponding values
  /// to the [content], [iv], and [hashingAlgoType] fields. If the hashing
  /// algorithm is provided as a string, it is converted back to its enum type
  /// using [HashingAlgoType.fromString].
  ///
  /// Returns an [AtEncrypted] object populated with data from the map.
  static AtEncrypted fromJson(Map<String, dynamic> map) {
    AtEncrypted atEncrypted = AtEncrypted()
      ..content = map['content']
      ..iv = map['iv'];

    if (map['hashingAlgoType'] != null && map['hashingAlgoType']!.isNotEmpty) {
      atEncrypted.hashingAlgoType =
          HashingAlgoType.fromString(map['hashingAlgoType']!);
    }
    return atEncrypted;
  }

  /// Returns the string representation of this [AtEncrypted] instance.
  ///
  /// This method converts the object into its JSON string form by calling
  /// [toJson] and encoding the resulting map using [jsonEncode].
  ///
  /// Returns the JSON string representation of the object.
  @override
  String toString() {
    return jsonEncode(toJson());
  }
}
