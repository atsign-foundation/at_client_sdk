import 'package:at_client/src/client/remote_secondary.dart';
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

@experimental
class AtClientParticulars {
  static final AtClientParticulars _singleton = AtClientParticulars._internal();

  AtClientParticulars._internal();

  factory AtClientParticulars.getInstance() {
    return _singleton;
  }

  final String _clientId = Uuid().v4();

  /// A unique identifier to distinguish clients on the server logs.
  String get clientId => _clientId.hashCode.toString();

  /// The name of the app the [AtClient] is associated with. This helps in distinguish
  /// the request sent from the apps in the [RemoteSecondary] logs.
  String? appName;

  /// The version of the app
  String? appVersion;

  /// The platform on which the app is running on.
  String? platform;
}
