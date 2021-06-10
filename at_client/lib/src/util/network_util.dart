import 'package:at_utils/at_logger.dart';
import 'package:data_connection_checker/data_connection_checker.dart';

class NetworkUtil {
  static final _logger = AtSignLogger('NetworkUtil');

  static Future<bool> isNetworkAvailable() async {
    var result = await DataConnectionChecker().hasConnection;
    if (!result) {
      _logger.finer(
          'Unable to connect to internet: ${DataConnectionChecker().lastTryResults}');
    }
    return result;
  }
}
