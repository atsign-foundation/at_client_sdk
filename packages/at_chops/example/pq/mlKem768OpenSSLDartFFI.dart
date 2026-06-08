import 'package:at_chops/at_chops.dart';

Future<void> main() async {
  final DynamicLibrary? lib = tryLoadLibCrypto();
  if(lib == null) {
    return;
  }
  MlKem768FfiAlgo mlKem768FfiAlgo = MlKem768FfiAlgo.fromLib(lib);
}
