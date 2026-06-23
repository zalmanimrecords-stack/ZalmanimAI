import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Slim header that sits above the content area, to the right of the sidebar.
///
/// Shows the current page title, an optional subtitle/breadcrumb, KPI stat
/// chips for at-a-glance metrics, and trailing actions (search, notifications,
/// connection indicator, etc.).
class AdminTopBar extends StatelessWidget {
  const AdminTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.stats = const <Widget>[],
    this.actions = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final List<Widget> stats;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(
          bottom: BorderSide(color: AppColors.divider),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Row(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                title,
                style: textTheme.titleLarge,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    subtitle!,
                    style: textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.xl),
          if (stats.isNotEmpty)
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: false,
                child: Row(
                  children: [
                    for (int i = 0; i < stats.length; i++) ...[
                      stats[i],
                      if (i != stats.length - 1)
                        const SizedBox(width: AppSpacing.sm),
                    ],
                  ],
                ),
              ),
            )
          else
            const Spacer(),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.md),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < actions.length; i++) ...[
                  actions[i],
                  if (i != actions.length - 1)
                    const SizedBox(width: AppSpacing.xs),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
