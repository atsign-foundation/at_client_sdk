import 'package:at_server_status/at_server_status.dart';

void main() async {
  var activationNotStarted = '@small73sepia';
  var readyToActivate = '@bullridingcapable';
  var paired = '@13majorfishtaco';

  Future<AtStatus> getAtStatus(atSign) async {
    AtStatus atStatus;
    AtStatusImpl atStatusImpl;

    // AtStatus atStatus = await atStatusImpl.get(atSign);
    // AtSignStatus atSignStatus = atStatus.status();
    // int httpStatus = atStatus.httpStatus();
    atStatusImpl = AtStatusImpl();
    atStatus = await atStatusImpl.get(atSign);
    print('status for : $atSign');
    print('rootStatus: ${atStatus.rootStatus}');
    print('serverStatus: ${atStatus.serverStatus}');
    print('status: ${atStatus.status()}');
    print('httpStatus: ${atStatus.httpStatus()}');
    print('\n');

    return atStatus;
  }

  await getAtStatus(activationNotStarted);
  await getAtStatus(readyToActivate);
  await getAtStatus(paired);
}
