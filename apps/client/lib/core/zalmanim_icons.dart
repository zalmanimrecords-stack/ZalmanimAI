import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Zalmanim-themed icons: aliens, jellyfish, squids style.
/// Use for navigation, sections, and decorative elements.
class ZalmanimIcons {
  ZalmanimIcons._();

  // ----- Custom creature SVG paths (relative to assets/icons/) -----
  static const String alien = 'assets/icons/alien.svg';
  static const String jellyfish = 'assets/icons/jellyfish.svg';
  static const String squid = 'assets/icons/squid.svg';

  /// Builds an SVG icon from asset path with optional size and color.
  static Widget svg(
    String assetPath, {
    double? size,
    Color? color,
  }) {
    final w = SvgPicture.asset(
      assetPath,
      width: size ?? 24,
      height: size ?? 24,
      colorFilter: color != null
          ? ColorFilter.mode(color, BlendMode.srcIn)
          : null,
    );
    return w;
  }

  /// Creature icons as widgets for tabs and headers.
  static Widget alienIcon({double size = 24, Color? color}) =>
      svg(alien, size: size, color: color);

  static Widget jellyfishIcon({double size = 24, Color? color}) =>
      svg(jellyfish, size: size, color: color);

  static Widget squidIcon({double size = 24, Color? color}) =>
      svg(squid, size: size, color: color);

  // ----- Themed Material Icons (organic / underwater / soft feel) -----
  static const IconData artists = Icons.face_rounded;
  static const IconData demos = Icons.bubble_chart_rounded;
  static const IconData releases = Icons.album_rounded;
  static const IconData campaigns = Icons.campaign_rounded;
  static const IconData campaignRequests = Icons.mark_email_unread_rounded;
  static const IconData audience = Icons.groups_rounded;
  static const IconData reports = Icons.assessment_rounded;
  static const IconData users = Icons.person_rounded;

  static const IconData settings = Icons.tune_rounded;
  static const IconData account = Icons.account_circle_rounded;
  static const IconData logout = Icons.logout_rounded;
  static const IconData search = Icons.search_rounded;
  static const IconData add = Icons.add_circle_outline_rounded;
  static const IconData merge = Icons.merge_type_rounded;
  static const IconData copy = Icons.copy_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData edit = Icons.edit_rounded;
  static const IconData delete = Icons.delete_rounded;
  static const IconData email = Icons.email_rounded;
  static const IconData send = Icons.send_rounded;
  static const IconData music = Icons.music_note_rounded;
  static const IconData upload = Icons.upload_rounded;
  static const IconData sync = Icons.sync_rounded;
  static const IconData personAdd = Icons.person_add_rounded;
  static const IconData refresh = Icons.refresh_rounded;
  static const IconData visibility = Icons.visibility_rounded;
  static const IconData visibilityOff = Icons.visibility_off_rounded;
  static const IconData cloudDone = Icons.cloud_done_rounded;
  static const IconData cloudOff = Icons.cloud_off_rounded;
  static const IconData arrowUp = Icons.arrow_upward_rounded;
  static const IconData arrowDown = Icons.arrow_downward_rounded;
  static const IconData arrowBack = Icons.arrow_back_rounded;
  static const IconData folder = Icons.folder_rounded;
  static const IconData download = Icons.download_rounded;
  static const IconData taskAlt = Icons.task_alt_rounded;
  static const IconData lockReset = Icons.lock_reset_rounded;
  static const IconData chevronRight = Icons.chevron_right_rounded;
  static const IconData save = Icons.save_rounded;
  static const IconData backup = Icons.backup_rounded;
  static const IconData restore = Icons.restore_rounded;
  static const IconData addPhoto = Icons.add_photo_alternate_rounded;
  static const IconData brokenImage = Icons.broken_image_rounded;
  static const IconData clear = Icons.clear_rounded;
  static const IconData history = Icons.history_rounded;
  static const IconData info = Icons.info_outline_rounded;
  static const IconData editNote = Icons.edit_note_rounded;
  static const IconData lock = Icons.lock_rounded;
  static const IconData personOff = Icons.person_off_rounded;
  static const IconData moreVert = Icons.more_vert_rounded;
  static const IconData moreHoriz = Icons.more_horiz_rounded;
  static const IconData adminPanel = Icons.admin_panel_settings_rounded;
  static const IconData graphicEq = Icons.graphic_eq_rounded;
  static const IconData alternateEmail = Icons.alternate_email_rounded;
  static const IconData networkCheck = Icons.network_check_rounded;
  static const IconData markEmailRead = Icons.mark_email_read_rounded;
  static const IconData link = Icons.link_rounded;
  static const IconData arrowDropUp = Icons.arrow_drop_up;
  static const IconData arrowDropDown = Icons.arrow_drop_down;
}
