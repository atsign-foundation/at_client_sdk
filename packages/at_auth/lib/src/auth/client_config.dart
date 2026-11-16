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
/// [appVersion], the SDK's [sdkName] and [sdkVersion], and [version] when
/// the caller gives one.
///
/// A value of the four that is null, empty or only whitespace takes
/// at_auth's: the name of the program file ("unknown" where there is none),
/// "unknown", "atsign.dart.at_auth" and at_auth's version. [version] has no
/// such default: one that is null, empty or only whitespace is not sent. Each
/// value is then made sendable: a line or paragraph separator becomes a
/// space, and the value is cut to its first 64 UTF-16 code units, never
/// leaving half of a surrogate pair.
Map<String, String> clientConfigFor({
  String? appName,
  String? appVersion,
  String? sdkName,
  String? sdkVersion,
  String? version,
}) =>
    {
      AtConstants.appName: _sendableOr(appName, derivedProgramName),
      AtConstants.appVersion:
          _sendableOr(appVersion, () => unknownClientConfigValue),
      sdkNameKey: _sendableOr(sdkName, () => atAuthSdkName),
      sdkVersionKey: _sendableOr(sdkVersion, () => packageVersion),
      if (version != null && version.trim().isNotEmpty)
        AtConstants.version: _sendable(version),
    };

/// [config] made sendable, with the four values [clientConfigFor] names
/// filled.
///
/// Every string value, under any key, is made sendable as [clientConfigFor]
/// makes its values. One of the four that is not a string is sent as its
/// `toString()`, and one that is absent, empty or only whitespace takes
/// at_auth's. A value of any other key that is not a string is passed through
/// unchanged. A `version` is sent only when [config] holds one, made sendable
/// when it is a string and unchanged when it is not; at_auth adds none.
Map<String, dynamic> withClientConfigDefaults(Map<String, dynamic> config) {
  String? given(String key) => config[key]?.toString();
  return {
    for (final MapEntry(:key, :value) in config.entries)
      key: value is String ? _sendable(value) : value,
    ...clientConfigFor(
        appName: given(AtConstants.appName),
        appVersion: given(AtConstants.appVersion),
        sdkName: given(sdkNameKey),
        sdkVersion: given(sdkVersionKey)),
  };
}

String _sendableOr(String? value, String Function() fallback) =>
    _sendable(value == null || value.trim().isEmpty ? fallback() : value);

String _sendable(String value) {
  final oneLine = value.replaceAll(_lineSeparators, ' ');
  if (oneLine.length <= maxClientConfigValueLength) return oneLine;
  final end =
      _isHighSurrogate(oneLine.codeUnitAt(maxClientConfigValueLength - 1))
          ? maxClientConfigValueLength - 1
          : maxClientConfigValueLength;
  return oneLine.substring(0, end);
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;
