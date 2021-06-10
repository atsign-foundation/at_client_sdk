
import 'package:at_client/at_client.dart';

import 'test_util.dart';

void main() async {
  var preference = MonitorPreference()..keepAlive=true;
  var clientPreference = TestUtil.getAlicePreference();
  var service = MonitorService(_notificationCallback, _errorCallback, 'alice', clientPreference, preference);
  service.startMonitor();
}

void _notificationCallback(notification) {
  print('got notification callback:');
  print(notification);
}

void _errorCallback(error) {
  print('main error callback');
  print(error);
}

