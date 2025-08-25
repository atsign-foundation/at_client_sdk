import 'package:at_client/at_client.dart' show AtClient;
import 'package:at_utils/at_logger.dart' show AtSignLogger;

/// Base mixin for a class which does things with an AtClient
mixin AtBase {
  AtClient get atClient;
  AtSignLogger get logger;
}
