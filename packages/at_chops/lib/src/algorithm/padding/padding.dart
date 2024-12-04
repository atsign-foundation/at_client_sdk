import 'package:at_chops/src/algorithm/padding/padding_params.dart';

abstract class PaddingAlgorithm {
  List<int> addPadding(List<int> data);
  List<int> removePadding(List<int> data);
}
