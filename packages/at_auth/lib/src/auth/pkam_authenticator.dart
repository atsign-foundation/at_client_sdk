import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

final _logger = AtSignLogger('PkamAuthenticator');

class PkamAuthenticator {
  PkamAuthenticator();

  /// Runs [atLookup]'s PKAM exchange; a failure throws
  /// [UnAuthenticatedException] saying why, and its stack trace is logged at
  /// fine.
  Future<bool> authenticate(String atSign, AtLookUp atLookup) async {
    try {
      return await atLookup.pkamAuthenticate();
    } catch (e, s) {
      _logger.logger.fine('pkam auth failed for $atSign', e, s);
      throw UnAuthenticatedException('pkam auth failed for $atSign - $e');
    }
  }
}
