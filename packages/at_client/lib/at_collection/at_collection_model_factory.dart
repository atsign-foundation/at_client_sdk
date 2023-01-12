import 'package:at_client/at_client.dart';

abstract class AtCollectionModelFactory<T extends AtCollectionModel> {
  /// Expected to return an instance of T
  T create();
}
