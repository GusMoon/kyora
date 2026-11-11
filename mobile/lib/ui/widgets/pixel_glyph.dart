import 'package:flutter/material.dart';

/// Un icono de la app: ahora es un icono redondeado de Material (el nombre `PixelGlyph` se conserva para no tocar a quien lo usa).
@immutable
class PixelGlyph {
  const PixelGlyph(this.icon);

  final IconData icon;

  @override
  bool operator ==(Object other) => other is PixelGlyph && other.icon == icon;

  @override
  int get hashCode => icon.hashCode;
}

/// Los iconos con nombre de la app.
abstract final class PixelGlyphs {
  static const generic = PixelGlyph(Icons.circle_outlined);
  static const add = PixelGlyph(Icons.add_rounded);
  static const all = PixelGlyph(Icons.select_all_rounded);
  static const arrow = PixelGlyph(Icons.arrow_forward_rounded);
  static const arrowUp = PixelGlyph(Icons.arrow_upward_rounded);
  static const attach = PixelGlyph(Icons.attach_file_rounded);
  static const battery = PixelGlyph(Icons.battery_full_rounded);
  static const batteryAlert = PixelGlyph(Icons.battery_alert_rounded);
  static const boxChecked = PixelGlyph(Icons.check_circle_rounded);
  static const boxEmpty = PixelGlyph(Icons.radio_button_unchecked_rounded);
  static const calendar = PixelGlyph(Icons.calendar_month_rounded);
  static const camera = PixelGlyph(Icons.photo_camera_rounded);
  static const chat = PixelGlyph(Icons.chat_bubble_rounded);
  static const check = PixelGlyph(Icons.check_rounded);
  static const chevronDown = PixelGlyph(Icons.keyboard_arrow_down_rounded);
  static const chevronLeft = PixelGlyph(Icons.chevron_left_rounded);
  static const chevronUp = PixelGlyph(Icons.keyboard_arrow_up_rounded);
  static const city = PixelGlyph(Icons.location_city_rounded);
  static const clock = PixelGlyph(Icons.schedule_rounded);
  static const contacts = PixelGlyph(Icons.contacts_rounded);
  static const close = PixelGlyph(Icons.close_rounded);
  static const cloud = PixelGlyph(Icons.cloud_rounded);
  static const cloudDone = PixelGlyph(Icons.cloud_done_rounded);
  static const cloudOff = PixelGlyph(Icons.cloud_off_rounded);
  static const cloudSync = PixelGlyph(Icons.cloud_sync_rounded);
  static const cloudUp = PixelGlyph(Icons.cloud_upload_rounded);
  static const copy = PixelGlyph(Icons.content_copy_rounded);
  static const day = PixelGlyph(Icons.today_rounded);
  static const disc = PixelGlyph(Icons.album_rounded);
  static const document = PixelGlyph(Icons.description_rounded);
  static const doneAll = PixelGlyph(Icons.done_all_rounded);
  static const equalizer = PixelGlyph(Icons.equalizer_rounded);
  static const error = PixelGlyph(Icons.error_outline_rounded);
  static const eye = PixelGlyph(Icons.visibility_rounded);
  static const eyeOff = PixelGlyph(Icons.visibility_off_rounded);
  static const file = PixelGlyph(Icons.insert_drive_file_rounded);
  static const fog = PixelGlyph(Icons.foggy);
  static const folder = PixelGlyph(Icons.folder_rounded);
  static const folderMove = PixelGlyph(Icons.drive_file_move_rounded);
  static const folderNew = PixelGlyph(Icons.create_new_folder_rounded);
  static const folderOpen = PixelGlyph(Icons.folder_open_rounded);
  static const folderZip = PixelGlyph(Icons.folder_zip_rounded);
  static const habit = PixelGlyph(Icons.published_with_changes_rounded);
  static const headphones = PixelGlyph(Icons.headphones_rounded);
  static const heart = PixelGlyph(Icons.favorite_border_rounded);
  static const heartFull = PixelGlyph(Icons.favorite_rounded);
  static const home = PixelGlyph(Icons.grid_view_rounded);
  static const image = PixelGlyph(Icons.image_rounded);
  static const imageBroken = PixelGlyph(Icons.broken_image_rounded);
  static const imageHidden = PixelGlyph(Icons.hide_image_rounded);
  static const logout = PixelGlyph(Icons.logout_rounded);
  static const more = PixelGlyph(Icons.more_vert_rounded);
  static const music = PixelGlyph(Icons.music_note_rounded);
  static const next = PixelGlyph(Icons.skip_next_rounded);
  static const partly = PixelGlyph(Icons.wb_cloudy_rounded);
  static const pause = PixelGlyph(Icons.pause_rounded);
  static const pdf = PixelGlyph(Icons.picture_as_pdf_rounded);
  static const person = PixelGlyph(Icons.person_rounded);
  static const phone = PixelGlyph(Icons.smartphone_rounded);
  static const play = PixelGlyph(Icons.play_arrow_rounded);
  static const previous = PixelGlyph(Icons.skip_previous_rounded);
  static const radio = PixelGlyph(Icons.radio_button_unchecked_rounded);
  static const radioChecked = PixelGlyph(Icons.radio_button_checked_rounded);
  static const rain = PixelGlyph(Icons.water_drop_rounded);
  static const reminder = PixelGlyph(Icons.notifications_rounded);
  static const repeat = PixelGlyph(Icons.repeat_rounded);
  static const repeatOne = PixelGlyph(Icons.repeat_one_rounded);
  static const selectAll = PixelGlyph(Icons.select_all_rounded);
  static const settings = PixelGlyph(Icons.tune_rounded);
  static const shuffle = PixelGlyph(Icons.shuffle_rounded);
  static const snow = PixelGlyph(Icons.ac_unit_rounded);
  static const storm = PixelGlyph(Icons.thunderstorm_rounded);
  static const sun = PixelGlyph(Icons.wb_sunny_rounded);
  static const task = PixelGlyph(Icons.task_alt_rounded);
  static const trash = PixelGlyph(Icons.delete_outline_rounded);
  static const tune = PixelGlyph(Icons.tune_rounded);
  static const vault = PixelGlyph(Icons.inventory_2_rounded);
  static const video = PixelGlyph(Icons.videocam_rounded);
}

/// El glifo de un icono de Material: el mismo icono.
PixelGlyph glyphFor(IconData icon) => PixelGlyph(icon);

/// El icono del estado del cielo (códigos WMO de Open-Meteo).
PixelGlyph pixelWeatherGlyph(int code) {
  if (code == 0 || code == 1) return PixelGlyphs.sun;
  if (code == 2) return PixelGlyphs.partly;
  if (code == 3) return PixelGlyphs.cloud;
  if (code == 45 || code == 48) return PixelGlyphs.fog;
  if (code >= 51 && code <= 67 || code >= 80 && code <= 82) return PixelGlyphs.rain;
  if (code >= 71 && code <= 77 || code == 85 || code == 86) return PixelGlyphs.snow;
  if (code >= 95) return PixelGlyphs.storm;
  return PixelGlyphs.cloud;
}

/// Un [PixelGlyph] pintado como icono.
class PixelIcon extends StatelessWidget {
  const PixelIcon(this.glyph, {super.key, this.size = 24, this.color, this.semanticLabel});

  final PixelGlyph glyph;
  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Icon(glyph.icon, size: size, color: color, semanticLabel: semanticLabel);
}

/// El sustituto de `Icon` en toda la app. Guarda el `icon` para poder buscarlo.
class LcdIcon extends StatelessWidget {
  const LcdIcon(this.icon, {super.key, this.size, this.color, this.semanticLabel});

  final IconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => Icon(icon, size: size, color: color, semanticLabel: semanticLabel);
}
