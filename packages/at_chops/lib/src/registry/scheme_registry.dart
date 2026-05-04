import 'package:at_chops/at_chops.dart' show CryptoScheme;
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
  /// there exists some default cryptoschemes:
  /// 'legacy' -> legacy cryptographic scheme, controlled by us
  /// 'shared' -> shared key scheme, rsa2048 & aes256
  /// 'aes' -> for self and apkam
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
