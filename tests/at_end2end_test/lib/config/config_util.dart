import 'package:at_utils/at_utils_io.dart';
import 'package:yaml/yaml.dart';

class ConfigUtil {
  static final ApplicationConfiguration appConfig =
      ApplicationConfiguration('config/config.yaml');

  static YamlMap getYaml() {
    return appConfig.getYaml()!;
  }
}
