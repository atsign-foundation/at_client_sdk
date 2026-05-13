import 'package:at_commons/at_commons.dart';

class SchemeRegistry {
  final Map<String, CryptoScheme> _schemes = <String, CryptoScheme>{};

  void register(String name, CryptoScheme scheme) {
    _schemes[name] = scheme;
    scheme.register();
  }

  /// Lookup in the scheme registry
  /// throws a [CryptoSchemeNotRegistered] if not registered
  ///
  /// there exists a default cryptoscheme:
  /// 'legacy' -> legacy cryptographic scheme, controlled by us
  CryptoScheme lookup(String name) {
    try {
      return _schemes[name]!;
    } catch (_) {
      throw CryptoSchemeNotRegistered(
          'Could not find registered cryptographic scheme with name $name');
    }
  }

  bool contains(String name) {
    return _schemes.containsKey(name);
  }

  List<String> get registeredNames {
    return _schemes.keys.toList(growable: false);
  }
}
