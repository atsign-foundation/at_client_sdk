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

  /// Groups the keys produced by a single enrollment (formerly an
  /// `AtKeyPackage`). Null for keys that are not enrollment-specific, e.g. the
  /// default encryption keypair shared across enrollments.
  String? get enrollmentId;
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
  @override
  final String? enrollmentId;
  final KeyProtection? protection;
  const AtSymmetricKey({
    required this.id,
    required this.algorithm,
    required this.bytes,
    this.protection,
    this.operations = const [],
    this.enrollmentId,
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
  @override
  final String? enrollmentId;
  const AtPublicKey({
    required this.pairId,
    required this.algorithm,
    required this.bytes,
    this.operations = const [],
    this.enrollmentId,
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
  @override
  final String? enrollmentId;
  final KeyProtection? protection;
  const AtPrivateKey({
    required this.pairId,
    required this.algorithm,
    required this.bytes,
    this.protection,
    this.operations = const [],
    this.enrollmentId,
  });
}
