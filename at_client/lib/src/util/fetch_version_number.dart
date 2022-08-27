import 'package:at_client/at_client.dart';
import 'package:at_utils/at_utils.dart';

/// The function reads the at_client version from the [pubspec.yaml] file and prints to console
/// This is used by github action's at_client_sdk.yaml to automatically update the at_client version
/// number.
void main() {
  var applicationConfig = ApplicationConfiguration('pubspec.yaml');
  var yamlMap = applicationConfig.getYaml();
  print('${yamlMap![VERSION]}');
}
