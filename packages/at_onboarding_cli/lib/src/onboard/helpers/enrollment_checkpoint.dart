import 'dart:convert';
import 'dart:io';

import 'package:at_auth/at_auth.dart';
import 'package:at_onboarding_cli/src/util/at_file_util.dart';
import 'package:at_utils/at_logger.dart';
import 'package:meta/meta.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as path;

/// Manages the enrollment checkpoint file used to resume interrupted enrollments.
///
/// The checkpoint file is named `<hash>.enrollment.checkpoint` where the hash
/// is a SHA-256 digest of the atSign + enrollment parameters. The atSign is
/// intentionally absent from the filename so that the file does not reveal
/// which atSign it belongs to.
class EnrollmentCheckpoint {
  final String _atSign;
  static const Duration defaultCheckpointExpiry = Duration(hours: 24);
  final AtSignLogger _logger = AtSignLogger('EnrollmentCheckpoint');

  EnrollmentCheckpoint(this._atSign);

  /// Returns a deterministic SHA-256 hash used as the checkpoint filename.
  ///
  /// The hash is derived from [atSign], [appName], [deviceName], and
  /// [namespaces] (sorted by key for determinism). Including [atSign] ensures
  /// that two different atSigns enrolling with identical parameters produce
  /// different filenames and cannot interfere with each other's checkpoints.
  ///
  /// The [atSign] is intentionally kept out of the filename itself — it is only
  /// used as hash input — so the resulting filename reveals nothing about which
  /// atSign the checkpoint belongs to.
  static String _paramsHash(String atSign, String appName, String deviceName,
      Map<String, String> namespaces) {
    final sortedNamespaces = (namespaces.entries.toList()
          ..sort((a, b) => a.key.compareTo(b.key)))
        .map((e) => '${e.key}:${e.value}')
        .join(',');
    return sha256
        .convert(utf8.encode('$atSign$appName$deviceName$sortedNamespaces'))
        .toString();
  }

  @visibleForTesting
  File getFile(String appName, String deviceName,
          Map<String, String> namespaces) =>
      File(path.join(Directory.current.path,
          '${_paramsHash(_atSign, appName, deviceName, namespaces)}.enrollment.checkpoint'));

  /// Writes the checkpoint to disk with secure file permissions (chmod 600).
  ///
  /// Maintains expiry for each checkpoint, defaults to [defaultCheckpointExpiry].
  /// Expired checkpoints are invalidated and deleted by [load]
  Future<void> save(
    AtEnrollmentResponse er,
    String appName,
    String deviceName,
    Map<String, String> namespaces, {
    Duration? expiry,
  }) async {
    expiry ??= defaultCheckpointExpiry;

    final Map<String, dynamic> json = er.toJson();
    json.remove('atSign'); // do not reveal which atSign this checkpoint belongs to
    json['atAuthKeys'] = er.atAuthKeys?.toJson();
    json['validTill'] = DateTime.now().add(expiry).millisecondsSinceEpoch;

    final file = getFile(appName, deviceName, namespaces);
    file.writeAsStringSync(jsonEncode(json));
    
    await AtFileUtil.setSecureFilePermissions(file.path);
    _logger.info('Saved checkpoint for ${er.enrollmentId}');
  }

  /// Loads the checkpoint if one exists for the given params and has not
  /// expired. Returns `null` and deletes the file if it is expired or corrupt.
  AtEnrollmentResponse? load(
      String appName, String deviceName, Map<String, String> namespaces) {
    final file = getFile(appName, deviceName, namespaces);
    if (!file.existsSync()) return null;

    try {
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

      final expiresAt =
          DateTime.fromMillisecondsSinceEpoch(data['validTill'] as int);
      if (expiresAt.isBefore(DateTime.now())) {
        file.deleteSync();
        return null;
      }

      final er = AtEnrollmentResponse.fromJson(data);
      if (data['atAuthKeys'] != null) {
        er.atAuthKeys =
            AtKeys.fromJson(data['atAuthKeys'] as Map<String, dynamic>);
      }
      return er;
    } catch (e) {
      _logger.warning('Failed to load checkpoint — deleting: $e');
      file.deleteSync();
      return null;
    }
  }

  /// Deletes the checkpoint for the given params if it exists.
  void delete(
      String appName, String deviceName, Map<String, String> namespaces) {
    final file = getFile(appName, deviceName, namespaces);
    if (file.existsSync()) file.deleteSync();
  }

}
