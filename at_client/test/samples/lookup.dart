
import 'package:at_lookup/at_lookup.dart';

void main(List<String> arguments)  async {
await lookItUp('@jagan');
 print('hello');
}

void lookItUp (String atSign) async {
  var _atLookup = AtLookupImpl(atSign, 'test.do-sf2.atsign.zone', 64 );
  var cram_secret = '0f0ecff314fc3183baea1e94f125e268005557b4763dc744ea41c5693161084d8127d768566613313b1dff887c87be6a80a1fc6fc09d5234fcad093cea82d855';
  await _atLookup.authenticate_cram(cram_secret);
  var result = await _atLookup.scan();
  print(result);
  await _atLookup.close();
}