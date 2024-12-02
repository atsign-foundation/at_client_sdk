import 'dart:convert';

import 'package:at_commons/at_commons.dart';

/// Represents hash of an atsign's public encryption key and the hashing algorithm used
class PublicKeyHash {
  // Holds the hashed value of the data.
  String hash;

  // Holds the algorithm used to the hash the data.
  String hashingAlgo;

  PublicKeyHash(this.hash, this.hashingAlgo);

  @override
  String toString() {
    return jsonEncode(toJson());
  }

  Map toJson() {
    var map = {};
    map[AtConstants.sharedWithPublicKeyHashValue] = hash;
    map[AtConstants.sharedWithPublicKeyHashingAlgo] = hashingAlgo;
    return map;
  }

  static PublicKeyHash? fromJson(Map? json) {
    if (json == null) {
      return null;
    }
    return PublicKeyHash(json[AtConstants.sharedWithPublicKeyHashValue],
        json[AtConstants.sharedWithPublicKeyHashingAlgo]);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PublicKeyHash &&
          runtimeType == other.runtimeType &&
          hash == other.hash &&
          hashingAlgo == other.hashingAlgo;

  @override
  int get hashCode => hash.hashCode ^ hashingAlgo.hashCode;
}
