
import 'package:at_client/at_client.dart';

void main() {
  final connectivityListener = ConnectivityListener();
  print('subscribing');
  connectivityListener.subscribe().listen((isConnected) {
    if(isConnected) {
      print('connected');
    } else {
      print('disconnected');
    }
  });
  print('listening');
}