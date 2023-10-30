// ignore_for_file: depend_on_referenced_packages

import 'package:at_utils/at_utils.dart';
import 'package:yaml/yaml.dart';

class ConfigUtil {
  static final ApplicationConfiguration appConfig =
      ApplicationConfiguration('config/config.yaml');

  static YamlMap getYaml() {
    return appConfig.getYaml()!;
  }
}
