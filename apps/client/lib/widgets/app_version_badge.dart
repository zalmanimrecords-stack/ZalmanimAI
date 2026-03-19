import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionBadge extends StatefulWidget {
  const AppVersionBadge({
    super.key,
    this.tooltipPrefix = 'App version',
    this.textStyle,
    this.backgroundColor,
    this.borderColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  });

  final String tooltipPrefix;
  final TextStyle? textStyle;
  final Color? backgroundColor;
  final Color? borderColor;
  final EdgeInsetsGeometry padding;

  @override
  State<AppVersionBadge> createState() => _AppVersionBadgeState();
}

class _AppVersionBadgeState extends State<AppVersionBadge> {
  String? _versionLabel;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _versionLabel = 'v${info.version}+${info.buildNumber}');
  }

  @override
  Widget build(BuildContext context) {
    final versionLabel = _versionLabel;
    if (versionLabel == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Tooltip(
      message: '${widget.tooltipPrefix}: $versionLabel',
      child: Container(
        padding: widget.padding,
        decoration: BoxDecoration(
          color: widget.backgroundColor ??
              theme.colorScheme.primaryContainer.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: widget.borderColor ??
                theme.colorScheme.primary.withValues(alpha: 0.14),
          ),
        ),
        child: Text(
          versionLabel,
          style: widget.textStyle ??
              theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
        ),
      ),
    );
  }
}
