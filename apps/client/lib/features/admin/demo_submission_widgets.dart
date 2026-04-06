import 'package:flutter/material.dart';

/// Label + value row for the demo details dialog (selectable value).
class DemoSubmissionInfoRow extends StatelessWidget {
  const DemoSubmissionInfoRow(
    this.label,
    this.value, {
    super.key,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          const SizedBox(height: 2),
          SelectableText(value.isEmpty ? '-' : value),
        ],
      ),
    );
  }
}
