import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';

/// Item rendered in the admin sidebar.
class AdminNavItem {
  const AdminNavItem({
    required this.icon,
    required this.label,
    this.badge,
    this.tooltip,
  });

  final IconData icon;
  final String label;

  /// Optional small numeric/text badge (e.g. unread count).
  final String? badge;

  /// Optional hover tooltip; defaults to label.
  final String? tooltip;
}

/// Left sidebar navigation for the admin dashboard.
///
/// Renders a brand header, a vertical list of nav items, and a footer with
/// the current user and a logout action. Designed to match a professional
/// management-console look while keeping the brand's light/warm palette.
class AdminSidebar extends StatelessWidget {
  const AdminSidebar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onItemSelected,
    required this.brandTitle,
    required this.brandSubtitle,
    this.brandLogo,
    this.userName,
    this.userEmail,
    this.userRole,
    this.onAccountPressed,
    this.onLogoutPressed,
    this.width = 232,
  });

  final List<AdminNavItem> items;
  final int selectedIndex;
  final ValueChanged<int> onItemSelected;

  final String brandTitle;
  final String brandSubtitle;
  final Widget? brandLogo;

  final String? userName;
  final String? userEmail;
  final String? userRole;
  final VoidCallback? onAccountPressed;
  final VoidCallback? onLogoutPressed;

  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: const BoxDecoration(
        color: AppColors.sidebarSurface,
        border: Border(
          right: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SidebarHeader(
            title: brandTitle,
            subtitle: brandSubtitle,
            logo: brandLogo,
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md,
                horizontal: AppSpacing.sm,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _SidebarTile(
                  item: item,
                  selected: index == selectedIndex,
                  onTap: () => onItemSelected(index),
                );
              },
            ),
          ),
          const Divider(height: 1),
          _SidebarFooter(
            userName: userName,
            userEmail: userEmail,
            userRole: userRole,
            onAccountPressed: onAccountPressed,
            onLogoutPressed: onLogoutPressed,
          ),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  const _SidebarHeader({
    required this.title,
    required this.subtitle,
    this.logo,
  });

  final String title;
  final String subtitle;
  final Widget? logo;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          if (logo != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(width: 32, height: 32, child: logo),
            ),
            const SizedBox(width: AppSpacing.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.textStrong,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: textTheme.labelSmall?.copyWith(
                    color: AppColors.textMuted,
                    letterSpacing: 0.6,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarTile extends StatelessWidget {
  const _SidebarTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AdminNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? AppColors.primary : AppColors.textMuted;
    final bg = selected ? AppColors.sidebarSelected : Colors.transparent;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Tooltip(
        message: item.tooltip ?? item.label,
        waitDuration: const Duration(milliseconds: 600),
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadii.control),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadii.control),
            hoverColor: AppColors.hoverTint,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 10,
              ),
              child: Row(
                children: [
                  Icon(item.icon, size: 20, color: color),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: color,
                        letterSpacing: 0.1,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (item.badge != null) _NavBadge(text: item.badge!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavBadge extends StatelessWidget {
  const _NavBadge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.tertiary,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      constraints: const BoxConstraints(minWidth: 20),
      alignment: Alignment.center,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.2,
        ),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  const _SidebarFooter({
    this.userName,
    this.userEmail,
    this.userRole,
    this.onAccountPressed,
    this.onLogoutPressed,
  });

  final String? userName;
  final String? userEmail;
  final String? userRole;
  final VoidCallback? onAccountPressed;
  final VoidCallback? onLogoutPressed;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final displayName = (userName?.trim().isNotEmpty ?? false)
        ? userName!.trim()
        : (userEmail ?? 'Account');
    final secondary = userRole?.toUpperCase();
    final initials = _initialsFrom(displayName);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onAccountPressed,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.outline),
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall,
                ),
                if (secondary != null && secondary.isNotEmpty)
                  Text(
                    secondary,
                    style: textTheme.labelSmall?.copyWith(
                      color: AppColors.textFaint,
                      letterSpacing: 0.6,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onLogoutPressed,
            tooltip: 'Log out',
            icon: const Icon(Icons.logout_rounded, size: 18),
            style: IconButton.styleFrom(
              minimumSize: const Size(32, 32),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  static String _initialsFrom(String name) {
    final parts = name.trim().split(RegExp(r'\s+|@|\.'));
    final letters = parts
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0].toUpperCase())
        .join();
    return letters.isEmpty ? '?' : letters;
  }
}
