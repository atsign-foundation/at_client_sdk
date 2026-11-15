import 'package:at_auth/src/auth/program_name.dart';
import 'package:at_auth/src/auth/program_name_stub.dart'
    if (dart.library.io) 'package:at_auth/src/auth/program_name_io.dart';
import 'package:at_auth/src/version.dart';
import 'package:at_commons/at_commons.dart' show AtConstants;

/// The clientConfig key naming the SDK that sent a `from:`.
const String sdkNameKey = 'sdkName';

/// The clientConfig key carrying the version of the SDK that sent a `from:`.
const String sdkVersionKey = 'sdkVersion';

/// The SDK a `from:` names when its caller names none.
const String atAuthSdkName = 'atsign.dart.at_auth';

/// The most of each clientConfig value a `from:` carries, in UTF-16 code
/// units, as the atServer counts what it keeps.
const int maxClientConfigValueLength = 64;

final RegExp _lineSeparators = RegExp(r'[\u2028\u2029]');

/// The clientConfig a `from:` carries: the program's [appName] and
/// [appVersion], and the SDK's [sdkName] and [sdkVersion].
///
/// A value that is null or empty takes at_auth's: the name of the program
/// file ("unknown" where there is none), "unknown", "atsign.dart.at_auth" and
/// at_auth's version. In each value a line or paragraph separator becomes a
/// space, and the value is then cut to its first 64 UTF-16 code units, never
/// leaving half of a surrogate pair.
Map<String, String> clientConfigFor({
  String? appName,
  String? appVersion,
  String? sdkName,
  String? sdkVersion,
}) =>
    {
      AtConstants.appName: _sendable(appName, derivedProgramName),
      AtConstants.appVersion:
          _sendable(appVersion, () => unknownClientConfigValue),
      sdkNameKey: _sendable(sdkName, () => atAuthSdkName),
      sdkVersionKey: _sendable(sdkVersion, () => packageVersion),
    };

/// [config] with the four values [clientConfigFor] names made sendable: each
/// one [config] holds as a string is cut as given, and the rest are filled.
/// Every other key is passed through unchanged.
Map<String, dynamic> withClientConfigDefaults(Map<String, dynamic> config) {
  String? given(String key) => switch (config[key]) {
        final String value => value,
        _ => null,
      };
  return {
    ...config,
    ...clientConfigFor(
        appName: given(AtConstants.appName),
        appVersion: given(AtConstants.appVersion),
        sdkName: given(sdkNameKey),
        sdkVersion: given(sdkVersionKey)),
  };
}

String _sendable(String? value, String Function() fallback) {
  final chosen = value == null || value.isEmpty ? fallback() : value;
  final oneLine = chosen.replaceAll(_lineSeparators, ' ');
  if (oneLine.length <= maxClientConfigValueLength) return oneLine;
  final end =
      _isHighSurrogate(oneLine.codeUnitAt(maxClientConfigValueLength - 1))
          ? maxClientConfigValueLength - 1
          : maxClientConfigValueLength;
  return oneLine.substring(0, end);
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;
