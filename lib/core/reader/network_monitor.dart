import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Network status monitor
/// Listens for connectivity changes and provides recommended concurrency
class NetworkMonitor
{
    final Connectivity _connectivity;
    List<ConnectivityResult> _current = [ConnectivityResult.wifi];

    StreamSubscription<List<ConnectivityResult>>? _subscription;

    NetworkMonitor({Connectivity? connectivity})
        : _connectivity = connectivity ?? Connectivity();

    /// Current connectivity results
    List<ConnectivityResult> get current => _current;

    /// Whether device is offline
    bool get isOffline => _current.contains(ConnectivityResult.none) ||
        _current.isEmpty;

    /// Whether using metered connection (mobile data)
    bool get isMetered => _current.contains(ConnectivityResult.mobile);

    /// Whether using WiFi
    bool get isWifi => _current.contains(ConnectivityResult.wifi);

    /// Initialize and start listening
    Future<void> init() async
    {
        try
        {
            _current = await _connectivity.checkConnectivity();
        }
        catch (_) {}

        _subscription = _connectivity.onConnectivityChanged.listen((result)
        {
            _current = result;
        });
    }

    /// Recommended download concurrency based on network state
    int recommendedConcurrency(int userSetting)
    {
        if (isOffline) return 0;
        if (isMetered) return userSetting.clamp(1, 2);
        return userSetting.clamp(1, 10);
    }

    /// Whether preloading is allowed
    bool get allowPreload
    {
        if (isOffline) return false;
        return true;
    }

    /// Connectivity change stream
    Stream<List<ConnectivityResult>> get onConnectivityChanged
    {
        return _connectivity.onConnectivityChanged;
    }

    /// Release listener
    void dispose()
    {
        _subscription?.cancel();
        _subscription = null;
    }
}
