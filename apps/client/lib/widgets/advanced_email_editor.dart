import 'package:flutter/material.dart';
import 'package:html_editor_enhanced/html_editor.dart';

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
  final HtmlEditorController _controller = HtmlEditorController();
  String _lastAppliedValue = '';

  @override
  void initState() {
    super.initState();
    _lastAppliedValue = widget.initialValue;
  }

  @override
  void didUpdateWidget(covariant AdvancedEmailEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialValue != oldWidget.initialValue &&
        widget.initialValue != _lastAppliedValue) {
      _lastAppliedValue = widget.initialValue;
      _controller.setText(widget.initialValue);
    }
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
          child: HtmlEditor(
            controller: _controller,
            hint: widget.hintText,
            initialText: widget.initialValue,
            options: HtmlEditorOptions(
              height: widget.minHeight,
            ),
            callbacks: Callbacks(
              onChange: (String? value) {
                final nextValue = value ?? '';
                _lastAppliedValue = nextValue;
                widget.onChanged(nextValue);
              },
            ),
          ),
        ),
      ],
    );
  }
}
