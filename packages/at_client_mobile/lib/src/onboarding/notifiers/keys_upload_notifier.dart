import 'package:flutter/foundation.dart';

class KeysUploadNotifier extends ChangeNotifier {
  String? _keysFile;
  bool _isLoading = false;
  String? _error;

  String? get keysFile => _keysFile;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> filesUpload() async {
    try {
      _isLoading = true;
      notifyListeners();
      // TODO: validate the file and transform into something the app understands.
      _keysFile = await _fileSelectAndValidate();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // TODO: Implement file upload and validation logic.
  Future<String> _fileSelectAndValidate() async {
    await Future.delayed(const Duration(seconds: 2));
    await _validateFile('Some file');
    return Future.value('Some file');
  }

  Future<void> _validateFile(String file) async {
    await Future.delayed(const Duration(seconds: 2));
  }
}
