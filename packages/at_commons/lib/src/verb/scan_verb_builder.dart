import 'package:at_commons/src/at_constants.dart';
import 'package:at_commons/src/verb/verb_builder.dart';
import 'package:at_commons/src/verb/verb_util.dart';

/// Scan verb builder generates a command to scan keys of current atSign(with ot without auth).
/// If a [regex] is set, keys matching the regex are returned.
/// If a [sharedBy] is set, then a scan command is send to the secondary server of the [sharedBy].
/// If a [sharedWith] is set, gets the keys shared to [sharedWith] atSign from the current atSign.
/// ```
/// // Scans keys for the self in an unauthenticated way
///  var builder = ScanVerbBuilder();
///
///  // Scans keys for the self in an authenticated way
///  var builder = ScanVerbBuilder()..auth=true;
///
///  // Scans keys shared by @alice to self in an authenticated way
///  var builder = ScanVerbBuilder()..auth=true..forAtSign='alice';
///
///  // Scans keys shared with @alice by self in an authenticated way
///  var builder = ScanVerbBuilder()..auth=true..regex='@alice';
///  ```
class ScanVerbBuilder implements VerbBuilder {
  /// atSign of another secondary server on which scan is run.
  /// If [sharedBy] is set then [auth] has to be true.
  String? sharedBy;

  /// atSign to whom the current atClient user has shared the keys.
  /// If [sharedWith] is set then [auth] has to be true.
  String? sharedWith;

  /// If set to true, then all keys(public, private, protected) are returned.
  /// If set to false, only the public keys of current atSign are returned.
  bool auth = false;

  /// Regular expression to filter keys.
  String? regex;

  /// If set to true, the hidden keys will displayed.
  /// Defaulted to false.
  bool showHiddenKeys = false;

  @override
  String buildCommand() {
    StringBuffer serverCommandBuffer = StringBuffer('scan');

    if (showHiddenKeys) {
      serverCommandBuffer.write(':${AtConstants.showHidden}:true');
    }
    if (sharedBy != null) {
      serverCommandBuffer.write(':${VerbUtil.formatAtSign(sharedBy)}');
    }
    if (regex != null) {
      serverCommandBuffer.write(' $regex');
    }
    return (serverCommandBuffer..write('\n')).toString();
  }

  @override
  bool checkParams() {
    return true;
  }
}
