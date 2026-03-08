import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api_client.dart';

/// Shows API connection status in the app bar (green = connected, red = disconnected).
/// When connection is restored after being lost, [onConnectionRestored] is called so the page can refresh data.
class ApiConnectionIndicator extends StatefulWidget {
  const ApiConnectionIndicator({
    super.key,
    required this.apiClient,
    this.onConnectionRestored,
  });

  final ApiClient apiClient;
  /// Called when connection transitions from disconnected to connected (e.g. to refresh dashboard data).
  final VoidCallback? onConnectionRestored;

  @override
  State<ApiConnectionIndicator> createState() => _ApiConnectionIndicatorState();
}

class _ApiConnectionIndicatorState extends State<ApiConnectionIndicator> {
  bool? _connected;
  Timer? _timer;

  static const _retryWhenDisconnectedSeconds = 10;
  static const _checkWhenConnectedSeconds = 15;

  @override
  void initState() {
    super.initState();
    _check(); // initial check
    _scheduleCheck();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _scheduleCheck() {
    _timer?.cancel();
    final seconds = _connected == false
        ? _retryWhenDisconnectedSeconds
        : _checkWhenConnectedSeconds;
    _timer = Timer(Duration(seconds: seconds), () async {
      await _check();
      if (mounted) _scheduleCheck();
    });
  }

  Future<void> _check() async {
    final ok = await widget.apiClient.checkConnection();
    if (mounted) {
      final wasDisconnected = _connected == false;
      final changed = _connected != ok;
      setState(() => _connected = ok);
      if (changed) _scheduleCheck();
      if (wasDisconnected && ok) widget.onConnectionRestored?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final connected = _connected;
    return Tooltip(
      message: connected == null
          ? 'Checking API...'
          : connected
              ? 'API connected (${widget.apiClient.baseUrl})'
              : 'API disconnected (${widget.apiClient.baseUrl})',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: connected == null
            ? const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                connected ? Icons.cloud_done : Icons.cloud_off,
                color: connected ? Colors.greenAccent : Colors.redAccent,
                size: 22,
              ),
      ),
    );
  }
}
