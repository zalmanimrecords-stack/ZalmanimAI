import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url] in external app; on failure copies to clipboard and shows SnackBar if [context] is mounted.
Future<void> openUrlOrCopy(BuildContext? context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null || !uri.isAbsolute) return;
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      await Clipboard.setData(ClipboardData(text: url));
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Link copied: $url')),
        );
      }
    }
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: url));
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Link copied: $url')),
      );
    }
  }
}
