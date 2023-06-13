import 'package:at_utils/at_utils.dart';
import 'package:yaml/yaml.dart';

class ConfigUtil {
  static final ApplicationConfiguration appConfig =
      ApplicationConfiguration('config/config12.yaml');

  static YamlMap getYaml() {
    return appConfig.getYaml()!;
  }
}
