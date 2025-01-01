import 'package:apkam_example/authorisation/models/models.dart';
import 'package:apkam_example/authorisation/services/authorisation_service.dart';
import 'package:flutter/cupertino.dart';

class SppNotifier extends ChangeNotifier {
  SppNotifier(this._service) {
    fetchSpp();
  }

  final AuthorisationService _service;

  bool _isLoading = false;
  String? _error;
  Otp? _spp;

  /// If the notifier is currently loading data.
  bool get isLoading => _isLoading;

  /// Current error message, if any.
  String? get error => _error;

  /// If the user has not set an SPP, this will be null.
  Otp? get spp => _spp;

  /// Fetch the SPP from the server.
  Future<void> fetchSpp() async {
    try {
      _isLoading = true;
      notifyListeners();
      final currentSpp = await _service.getActiveSpp();
      print('Current spp: $currentSpp');
      _spp = currentSpp;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set the SPP on the server.
  Future<void> setSpp(String spp) async {
    try {
      _isLoading = true;
      notifyListeners();
      final newSpp = await _service.setSpp(spp: spp);
      _spp = newSpp;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
