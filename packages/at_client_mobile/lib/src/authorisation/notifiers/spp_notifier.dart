import 'package:flutter/cupertino.dart';

import '../models/models.dart';
import '../services/authorisation_service.dart';

class SppNotifier extends ChangeNotifier {
  SppNotifier(this._service) {
    fetchSpp();
  }

  final AuthorisationService _service;

  bool _isLoading = false;
  String? _fetchError;
  String? _saveError;
  Otp? _spp;

  /// If the notifier is currently loading data.
  bool get isLoading => _isLoading;

  /// Current error message when fetching, if any.
  String? get fetchError => _fetchError;

  /// Current error message when saving, if any.
  String? get saveError => _saveError;

  /// If the user has not set an SPP, this will be null.
  Otp? get spp => _spp;

  /// Fetch the SPP from the server.
  Future<void> fetchSpp() async {
    try {
      _fetchError = null;
      _isLoading = true;
      notifyListeners();
      final currentSpp = await _service.getActiveSpp();
      _spp = currentSpp;
    } catch (e) {
      _fetchError = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set the SPP on the server.
  /// Optionally, you can provide a duration for how long the SPP should be active.
  Future<void> setSpp(String spp, Duration duration) async {
    try {
      _saveError = null;
      _isLoading = true;
      notifyListeners();
      final newSpp = await _service.setSpp(
        spp: spp,
        sppExpiry: duration,
      );
      _spp = newSpp;
    } catch (e) {
      _saveError = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
