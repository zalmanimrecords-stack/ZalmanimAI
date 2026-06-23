import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Compact pill that shows a label and a value, used in the admin top bar.
///
/// Example: "Demos · 3 in review / 12 pending".
class StatChip extends StatelessWidget {
  const StatChip({
    super.key,
    required this.label,
    required this.value,
    this.icon,
    this.tone = StatChipTone.neutral,
    this.tooltip,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData? icon;
  final StatChipTone tone;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(tone);
    final textTheme = Theme.of(context).textTheme;

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: colors.foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: colors.foreground.withValues(alpha: 0.8),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: textTheme.labelMedium?.copyWith(
              color: colors.foreground,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );

    final wrapped = onTap == null
        ? pill
        : Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: pill,
            ),
          );

    if (tooltip == null) return wrapped;
    return Tooltip(message: tooltip!, child: wrapped);
  }
}

enum StatChipTone { neutral, info, warning, success, danger }

class _ToneColors {
  const _ToneColors({
    required this.surface,
    required this.foreground,
    required this.border,
  });
  final Color surface;
  final Color foreground;
  final Color border;
}

_ToneColors _toneColors(StatChipTone tone) {
  switch (tone) {
    case StatChipTone.neutral:
      return const _ToneColors(
        surface: Colors.white,
        foreground: AppColors.textStrong,
        border: AppColors.outline,
      );
    case StatChipTone.info:
      return const _ToneColors(
        surface: AppColors.infoSurface,
        foreground: AppColors.infoText,
        border: AppColors.infoSurface,
      );
    case StatChipTone.warning:
      return const _ToneColors(
        surface: AppColors.warningSurface,
        foreground: AppColors.warningText,
        border: AppColors.warningSurface,
      );
    case StatChipTone.success:
      return const _ToneColors(
        surface: AppColors.successSurface,
        foreground: AppColors.successText,
        border: AppColors.successSurface,
      );
    case StatChipTone.danger:
      return const _ToneColors(
        surface: AppColors.dangerSurface,
        foreground: AppColors.dangerText,
        border: AppColors.dangerSurface,
      );
  }
}
