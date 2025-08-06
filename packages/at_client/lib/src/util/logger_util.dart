import 'package:at_client/src/preference/at_client_particulars.dart';
import 'package:at_client/src/util/at_client_util.dart';
import 'package:at_utils/at_logger.dart';

extension AtClientLogging on AtSignLogger {
  String getLogMessageWithClientParticulars(
      AtClientParticulars atClientParticulars, String logMessage) {
    StringBuffer stringBuffer = StringBuffer();
    stringBuffer.write('${atClientParticulars.clientId}|');
    if (atClientParticulars.appName.isNotNull) {
      stringBuffer.write('${atClientParticulars.appName}|');
    }
    if (atClientParticulars.appVersion.isNotNull) {
      stringBuffer.write('${atClientParticulars.appVersion}|');
    }
    if (atClientParticulars.platform.isNotNull) {
      stringBuffer.write('${atClientParticulars.platform}|');
    }
    stringBuffer.write(logMessage);
    return stringBuffer.toString();
  }
}
