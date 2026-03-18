// Shared musical style / genre options for demo submission (portal landing and artist dashboard).

class DemoGenreOption {
  const DemoGenreOption(this.group, this.value);

  final String group;
  final String value;
}

const List<DemoGenreOption> demoGenreOptions = [
  DemoGenreOption('House', 'House'),
  DemoGenreOption('House', 'House / Acid'),
  DemoGenreOption('House', 'House / Soulful'),
  DemoGenreOption('House', 'Jackin House'),
  DemoGenreOption('House', 'Organic House'),
  DemoGenreOption('House', 'Progressive House'),
  DemoGenreOption('House', 'Afro House'),
  DemoGenreOption('House', 'Afro House / Afro Latin'),
  DemoGenreOption('House', 'Afro House / Afro Melodic'),
  DemoGenreOption('House', 'Afro House / 3Step'),
  DemoGenreOption('House', 'Tech House'),
  DemoGenreOption('House', 'Tech House / Latin Tech'),
  DemoGenreOption('House', 'Melodic House & Techno / Melodic House'),
  DemoGenreOption('Techno', 'Hard Techno'),
  DemoGenreOption('Techno', 'Techno (Peak Time / Driving)'),
  DemoGenreOption('Techno', 'Techno / Peak Time'),
  DemoGenreOption('Techno', 'Techno / Driving'),
  DemoGenreOption('Techno', 'Techno / Psy-Techno'),
  DemoGenreOption('Techno', 'Techno (Raw / Deep / Hypnotic)'),
  DemoGenreOption('Techno', 'Techno / Raw'),
  DemoGenreOption('Techno', 'Techno / Deep / Hypnotic'),
  DemoGenreOption('Techno', 'Techno / Dub'),
  DemoGenreOption('Techno', 'Techno / EBM'),
  DemoGenreOption('Techno', 'Techno / Broken'),
  DemoGenreOption('Techno', 'Melodic House & Techno / Melodic Techno'),
  DemoGenreOption('Trance', 'Trance (Main Floor)'),
  DemoGenreOption('Trance', 'Trance / Progressive Trance'),
  DemoGenreOption('Trance', 'Trance / Tech Trance'),
  DemoGenreOption('Trance', 'Trance / Uplifting Trance'),
  DemoGenreOption('Trance', 'Trance / Vocal Trance'),
  DemoGenreOption('Trance', 'Trance / Hard Trance'),
  DemoGenreOption('Trance', 'Trance (Raw / Deep / Hypnotic)'),
  DemoGenreOption('Trance', 'Trance / Raw Trance'),
  DemoGenreOption('Trance', 'Trance / Deep Trance'),
  DemoGenreOption('Trance', 'Trance / Hypnotic Trance'),
  DemoGenreOption('Trance', 'Psy-Trance'),
  DemoGenreOption('Trance', 'Psy-Trance / Full-On'),
  DemoGenreOption('Trance', 'Psy-Trance / Progressive Psy'),
  DemoGenreOption('Trance', 'Psy-Trance / Psychedelic'),
  DemoGenreOption('Trance', 'Psy-Trance / Dark & Forest'),
  DemoGenreOption('Trance', 'Psy-Trance / Goa Trance'),
  DemoGenreOption('Trance', 'Psy-Trance / Psycore & Hi-Tech'),
];

const List<String> demoGenreGroups = ['House', 'Techno', 'Trance'];
