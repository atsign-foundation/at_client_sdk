
import 'package:at_client/at_client.dart';
import 'package:at_client/src/service/notification_service.dart';
import 'package:at_commons/at_commons.dart';

class NotificationServiceImpl implements NotificationService {
  Map<String, NotificationService> instances = {};
  Map<String, Function> listeners = {};
  final EMPTY_REGEX = '';

  late AtClient atClient;

  NotificationService? getInstance() {
    _loadSubscriptions();
    return instances[atClient.getCurrentAtSign()];
  }

  void _loadSubscriptions() async {
    // Remember the subscriptions beyond the app restart
    // jagan. have to validate whether below will work since we are retrieving dart object from hive
   var subscriptions = atClient.get(AtKey()..key='_nf_listeners');


    //String lastReceivedNotification = atClient.put("_latestNotificationId", notification.id);

    final lastNotificationTimeMillis = await _getLastNotificationTime ();
    //jagan.should we iterate through subscriptions and start monitor for each subscription ?
    // Start Monitor
//    Monitor.start(lastReceivedNotification);
//
//    // If the monitor could not be started.. make sure that no exception is thrown and the code here
//    while(!Monitor.isRunning) {
//      Future.delayed(_tryLater , Seconds.3);
//    }
  }

  Future<int?> _getLastNotificationTime() async {
    final atValue = await atClient.get(AtKey()..key='_latestNotificationTime');
    if(atValue != null) {
      return int.parse(atValue.value);
    }
    return null;
  }

  @override
  void listen(Function notificationCallback, {String? regex}) {
    regex ??= EMPTY_REGEX;

    listeners[regex] =  notificationCallback;
    // Remember the subscription
    // Jagan. listener is a dart map object. not sure whether this will work in hive like
    // java serialization/deserialization
    atClient.put(AtKey()..key='_nf_listeners', listeners);
    // Jagan. should a monitor be started here?
    // should listen method return a Stream or StreamSubscription ? similar to socket.listen ?
  }

  @override
  void notify(NotificationParams notificationParams, onSuccessCallback, onErrorCallback) {
    // TODO: implement notify
  }

}