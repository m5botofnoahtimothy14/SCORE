// Connectivity status provider (connectivity_plus).
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Emits true when the device has any network path.
final isOnlineProvider = StreamProvider<bool>((ref) {
  final connectivity = Connectivity();
  return connectivity.onConnectivityChanged.map(
    (results) => !results.contains(ConnectivityResult.none),
  );
});
