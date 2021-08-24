import 'package:at_client/at_client.dart';
import 'package:at_client/src/listener/AtSignChangeListener.dart';

class AtClientManager {
  var _atSign;
  var currenAtClient;
  final _changeListeners = <AtSignChangeListener>[];

  static final AtClientManager _singleton = AtClientManager._internal();

  AtClientManager._internal();

  factory AtClientManager.getInstance() {
    return _singleton;
  }

  void setCurrentAtSign(
      String atSign, String namespace, AtClientPreference preference) {
    _atSign = _atSign;
    currenAtClient = AtClientImpl(_atSign, namespace, preference);
    _notifyListeners(currenAtClient);
  }

  void listenToAtSignChange(AtSignChangeListener listener) {
    _changeListeners.add(listener);
  }

  void _notifyListeners(AtClient atClient) {
    _changeListeners.forEach((listener) {
      listener.listenToAtSignChange(atClient);
    });
  }
}
