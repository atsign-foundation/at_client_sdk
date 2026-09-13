import 'package:at_auth/at_auth.dart' show authenticatorForCramSecret;
import 'package:at_commons/at_commons.dart' show AtRootDomain;
import 'package:at_lookup/at_lookup_io.dart';

void main(List<String> arguments) async {
  lookItUp('@jagan');
  print('hello');
}

void lookItUp(String atSign) async {
  var cramSecret =
      '0f0ecff314fc3183baea1e94f125e268005557b4763dc744ea41c5693161084d8127d768566613313b1dff887c87be6a80a1fc6fc09d5234fcad093cea82d855';
  // CRAM is the authenticator; the first command that needs it runs it.
  final lookUp = secureSocketLookUps()(
      atSign: atSign,
      rootDomain: AtRootDomain('test.do-sf2.atsign.zone', 64),
      authenticator: authenticatorForCramSecret(atSign, cramSecret));
  var result = await lookUp.scan();
  print(result);
  await lookUp.close();
}
