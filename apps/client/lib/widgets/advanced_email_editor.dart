import 'package:flutter/material.dart';

/// Reusable HTML email editor wrapper for admin mail/template screens.
class AdvancedEmailEditor extends StatefulWidget {
  const AdvancedEmailEditor({
    super.key,
    required this.initialValue,
    required this.onChanged,
    this.label = 'Body',
    this.hintText = 'Write the email body...',
    this.minHeight = 320,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;
  final String label;
  final String hintText;
  final double minHeight;

  @override
  State<AdvancedEmailEditor> createState() => _AdvancedEmailEditorState();
}

class _AdvancedEmailEditorState extends State<AdvancedEmailEditor> {
  late final TextEditingController _controller;
  String _lastAppliedValue = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _lastAppliedValue = widget.initialValue;
  }

  @override
  void didUpdateWidget(covariant AdvancedEmailEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != _lastAppliedValue) {
      _lastAppliedValue = widget.initialValue;
      _controller.value = TextEditingValue(
        text: widget.initialValue,
        selection: TextSelection.collapsed(offset: widget.initialValue.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          widget.label,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: Theme.of(context).dividerColor),
            borderRadius: BorderRadius.circular(8),
          ),
          child: TextField(
            controller: _controller,
            minLines: (widget.minHeight / 24).ceil().clamp(8, 40),
            maxLines: null,
            decoration: InputDecoration(
              hintText: widget.hintText,
              contentPadding: const EdgeInsets.all(16),
              border: InputBorder.none,
            ),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
            keyboardType: TextInputType.multiline,
            onChanged: (value) {
              _lastAppliedValue = value;
              widget.onChanged(value);
            },
          ),
        ),
      ],
    );
  }
}
