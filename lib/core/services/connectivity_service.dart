import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  final Connectivity _connectivity;
  StreamSubscription? _sub;
  bool _isOnline = true;

  bool get isOnline => _isOnline;

  ConnectivityService(this._connectivity) {
    _init();
  }

  Future<void> _init() async {
    final result = await _connectivity.checkConnectivity();
    _isOnline = _isConnected(result);
    notifyListeners();

    _sub = _connectivity.onConnectivityChanged.listen((results) {
      final wasOnline = _isOnline;
      _isOnline = _isConnected(results);
      if (wasOnline != _isOnline) notifyListeners();
    });
  }

  bool _isConnected(List<ConnectivityResult> results) {
    return results.any((r) => r != ConnectivityResult.none);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}
