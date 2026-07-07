import 'package:at_commons/at_commons.dart';

class KeyProtection {
  final String keyRef;
  final String algorithm;
  final String iv;

  const KeyProtection({
    required this.keyRef,
    required this.algorithm,
    required this.iv,
  });

  factory KeyProtection.fromJson(Map<String, dynamic> json) => KeyProtection(
        keyRef: json['keyRef'],
        algorithm: json['algorithm'],
        iv: json['iv'],
      );
  Map<String, dynamic> toJson() => {
        'keyRef': keyRef,
        'algorithm': algorithm,
        'iv': iv,
      };
}

sealed class AtKeysMaterial {
  const AtKeysMaterial();

  String get id;
  String get algorithm;
  AtBytes get bytes;
  List<String> get operations;
}

final class AtSymmetricKey extends AtKeysMaterial {
  @override
  final String id;
  @override
  final String algorithm;
  @override
  final AtBytes bytes;
  @override
  final List<String> operations;
  final KeyProtection? protection;
  const AtSymmetricKey({
    required this.id,
    required this.algorithm,
    required this.bytes,
    this.protection,
    this.operations = const [],
  });
}

final class AtPublicKey extends AtKeysMaterial {
  final String pairId;
  @override
  String get id => pairId; // pairId serves as it's id
  @override
  final String algorithm;
  @override
  final AtBytes bytes;
  @override
  final List<String> operations;
  const AtPublicKey({
    required this.pairId,
    required this.algorithm,
    required this.bytes,
    this.operations = const [],
  });
}

final class AtPrivateKey extends AtKeysMaterial {
  final String pairId;
  @override
  String get id => pairId; // pairId serves as it's id
  @override
  final String algorithm;
  @override
  final AtBytes bytes;
  @override
  final List<String> operations;
  final KeyProtection? protection;
  const AtPrivateKey({
    required this.pairId,
    required this.algorithm,
    required this.bytes,
    this.protection,
    this.operations = const [],
  });
}

final class AtKeyPackage extends AtKeysMaterial {
  // required in cases where we strictly share only half of this package.
  final String pairId;
  final String enrollmentId;
  @override
  String get id => enrollmentId; // enrollmentId serves as it's id
  @override
  final String algorithm;
  @override

  /// equivalent to AtKeysPackage.secret
  final AtBytes bytes;
  final AtBytes publicKey;
  AtBytes get secret => bytes;
  @override
  final List<String> operations;
  final KeyProtection? secretProtection;
  const AtKeyPackage({
    required this.pairId,
    required this.enrollmentId,
    required this.algorithm,
    required this.bytes,
    this.secretProtection,
    this.operations = const [],
    required this.publicKey,
  });
}
