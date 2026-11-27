import 'dart:ffi';

import 'package:meta/meta.dart';

/// OpenSSL 3.5.1 as `OpenSSL_version_num` encodes it: `0xMNN00PP0`.
const int _openSsl3_5_1 = 0x30500010;

/// Whether [versionNum], an `OpenSSL_version_num` value, is a release that
/// at_chops uses for ML-KEM-768 through FFI: OpenSSL 3.5.1 or later.
@visibleForTesting
bool openSslVersionSupportsMlKem768(int versionNum) =>
    versionNum >= _openSsl3_5_1;

/// Whether [lib]'s OpenSSL release is one that at_chops uses for ML-KEM-768
/// through FFI. `false` if [lib] has no `OpenSSL_version_num`.
bool libCryptoVersionSupportsMlKem768(DynamicLibrary lib) {
  try {
    final versionNum =
        lib.lookupFunction<UnsignedLong Function(), int Function()>(
            'OpenSSL_version_num');
    return openSslVersionSupportsMlKem768(versionNum());
  } catch (_) {
    return false;
  }
}
