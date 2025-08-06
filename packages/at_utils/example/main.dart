import 'package:at_utils/at_utils.dart';

void main(List<String> arguments) {
  var logger = AtSignLogger('AtUtilsExample');
  var atSign = '@alice';
  var fixedAtSign = AtUtils.fixAtSign(atSign);
  logger.info(fixedAtSign);
  var atSignSha = AtUtils.getShaForAtSign(atSign);
  logger.finest(atSignSha);
}
