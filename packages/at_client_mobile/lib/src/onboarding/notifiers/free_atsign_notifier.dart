import 'dart:math';

import 'package:flutter/foundation.dart';

class FreeAtsignNotifier extends ChangeNotifier {
  FreeAtsignNotifier();

  // TODO: Pass in registrar service.

  String? _atSign;
  bool _isFetching = false;
  String? _error;

  String? get freeAtsign => _atSign;
  bool get isFetching => _isFetching;
  String? get error => _error;

  final List<String> _fakeAtsigns = ['orangepuppet22', 'bluepuppet22', 'greenpuppet22'];

  Future<void> fetchFreeAtsign() async {
    try {
      _isFetching = true;
      notifyListeners();
      await Future.delayed(const Duration(seconds: 2));
      final atSign = await Future.value(_fakeAtsigns[Random().nextInt(_fakeAtsigns.length)]);
      _atSign = atSign;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    } finally {
      _isFetching = false;
      notifyListeners();
    }
  }
}
