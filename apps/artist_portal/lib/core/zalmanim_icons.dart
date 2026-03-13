import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Zalmanim-themed icons: aliens, jellyfish, squids style.
class ZalmanimIcons {
  ZalmanimIcons._();

  static const String alien = 'assets/icons/alien.svg';
  static const String jellyfish = 'assets/icons/jellyfish.svg';
  static const String squid = 'assets/icons/squid.svg';

  static Widget svg(
    String assetPath, {
    double? size,
    Color? color,
  }) {
    return SvgPicture.asset(
      assetPath,
      width: size ?? 24,
      height: size ?? 24,
      colorFilter: color != null
          ? ColorFilter.mode(color, BlendMode.srcIn)
          : null,
    );
  }

  static Widget alienIcon({double size = 24, Color? color}) =>
      svg(alien, size: size, color: color);

  static Widget jellyfishIcon({double size = 24, Color? color}) =>
      svg(jellyfish, size: size, color: color);

  static Widget squidIcon({double size = 24, Color? color}) =>
      svg(squid, size: size, color: color);

  static const IconData account = Icons.account_circle_rounded;
  static const IconData logout = Icons.logout_rounded;
  static const IconData copy = Icons.copy_rounded;
  static const IconData arrowBack = Icons.arrow_back_rounded;
  static const IconData email = Icons.email_rounded;
  static const IconData lock = Icons.lock_rounded;
  static const IconData errorOutline = Icons.error_outline_rounded;
  static const IconData visibility = Icons.visibility_rounded;
  static const IconData visibilityOff = Icons.visibility_off_rounded;
  static const IconData send = Icons.send_rounded;
  static const IconData music = Icons.music_note_rounded;
  static const IconData upload = Icons.upload_rounded;
  static const IconData folder = Icons.folder_rounded;
  static const IconData download = Icons.download_rounded;
  static const IconData delete = Icons.delete_rounded;
  static const IconData taskAlt = Icons.task_alt_rounded;
  static const IconData markEmailRead = Icons.mark_email_read_rounded;
  static const IconData campaign = Icons.campaign_rounded;
  static const IconData block = Icons.block_rounded;
}
