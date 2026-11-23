import 'package:at_auth/src/exception/at_auth_exceptions.dart';
import 'package:at_commons/at_commons.dart';
import 'package:at_lookup/at_lookup.dart';
import 'package:at_utils/at_logger.dart';

final _logger = AtSignLogger('PkamAuthenticator');

/// Logs a lookup's connection in by PKAM.
class PkamAuthenticator {
  PkamAuthenticator();

  /// Logs [atLookup]'s connection in by PKAM and returns whether it did.
  ///
  /// A failure is thrown as an [UnAuthenticatedException] naming [atSign]
  /// and carrying what failed, an [AtAuthErrorReplyException] with its code
  /// when the atServer's reply ended it; its stack trace is logged at fine.
  /// A [StoppedException] from a lookup its owner has stopped is rethrown as
  /// it is.
  Future<bool> authenticate(String atSign, AtLookUp atLookup) async {
    try {
      return await atLookup.pkamAuthenticate();
    } on StoppedException {
      rethrow;
    } catch (e, s) {
      _logger.logger.fine('pkam auth failed for $atSign', e, s);
      final message = 'pkam auth failed for $atSign - $e';
      throw e is AtAuthErrorReplyException
          ? AtAuthErrorReplyException(message, errorCode: e.errorCode)
          : UnAuthenticatedException(message);
    }
  }
}
