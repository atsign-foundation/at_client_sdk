import 'package:package_info_plus/package_info_plus.dart';

const _atKeysStoreName = '@atsigns';
const _enrollmentStoreName = '@enrollment';
const _sppStoreName = '@spp';
String? _packageInfo;

Future<String> getPackageName() async {
  _packageInfo ??= (await PackageInfo.fromPlatform()).packageName;
  return _packageInfo!;
}

sealed class KeychainStore {
  const KeychainStore();
}

class AtKeysStore extends KeychainStore {
  const AtKeysStore();
  static Future<String> getName() async {
    String packageName = await getPackageName();
    return '$_atKeysStoreName:$packageName';
  }

  // Pre-1.1.6 store name (used `_` instead of `:`).
  static Future<String> getImproperName() async {
    String packageName = await getPackageName();
    return '${_atKeysStoreName}_$packageName';
  }
}

class EnrollmentStore extends KeychainStore {
  final String atSign;
  const EnrollmentStore(this.atSign);
  String getName() {
    return '${atSign}_$_enrollmentStoreName';
  }
}

class SppStore extends KeychainStore {
  final String atSign;
  const SppStore(this.atSign);
  String getName() {
    return '${atSign}_$_sppStoreName';
  }
}
