import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_config.dart';
import 'zalmanim_icons.dart';

/// Shared loading view: centered progress + optional label.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, required this.primary, this.label});

  final Color primary;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: primary),
          const SizedBox(height: 16),
          Text(
            label ?? AppConfig.labelName,
            style: TextStyle(color: primary, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Shared error view: icon, selectable message, copy button, optional retry.
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    this.onRetry,
  });

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(ZalmanimIcons.errorOutline, size: 48, color: Colors.grey[600]),
            const SizedBox(height: 16),
            SelectableText(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(ZalmanimIcons.copy),
                  tooltip: 'Copy',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: message));
                  },
                ),
                if (onRetry != null) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 20),
                    label: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
