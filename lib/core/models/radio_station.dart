class RadioStation {
  final String id;
  final String nameAr;
  final String nameEn;
  final String streamUrl;
  final String country;
  final String countryCode;
  final String category;
  final bool isOfficial;
  final String? imageUrl;
  final String? stationUuid;

  const RadioStation({
    required this.id, required this.nameAr, required this.nameEn,
    required this.streamUrl, required this.country, required this.countryCode,
    required this.category, this.isOfficial = false,
    this.imageUrl, this.stationUuid,
  });

  factory RadioStation.fromDataRosy(Map<String, dynamic> j) {
    final name = j['name'] as String? ?? '';
    return RadioStation(
      id: 'dr_\${j["id"]}',
      nameAr: name, nameEn: name,
      streamUrl: j['radio_url'] as String? ?? '',
      country: _guessCountry(name),
      countryCode: _guessCountryCode(name),
      category: 'quran',
      isOfficial: name.contains('إذاعة'),
      imageUrl: j['image_url'] as String?,
    );
  }

  factory RadioStation.fromUthumany(Map<String, dynamic> j) {
    final name = (j["name"] as String?) ?? "";
    final safeId = name.toLowerCase()
        .replaceAll(" ", "_")
        .replaceAll(RegExp("[^a-z0-9_]"), "");
    return RadioStation(
      id: "ut_$safeId",
      nameAr: name,
      nameEn: name,
      streamUrl: (j["stream_url"] as String?) ?? "",
      country: _guessCountry(name),
      countryCode: _guessCountryCode(name),
      category: _guessCategory(name),
      isOfficial: name.contains("إذاعة"),
    );
  }

  static String _guessCountry(String n) {
    if (n.contains('القاهرة') || n.contains('مصر')) return 'Egypt';
    if (n.contains('السعودية') || n.contains('مكة')) return 'Saudi Arabia';
    if (n.contains('الكويت')) return 'Kuwait';
    if (n.contains('المغرب')) return 'Morocco';
    if (n.contains('الجزائر')) return 'Algeria';
    if (n.contains('تونس')) return 'Tunisia';
    if (n.contains('قطر')) return 'Qatar';
    if (n.contains('الشارقة') || n.contains('الإمارات')) return 'UAE';
    return 'International';
  }

  static String _guessCountryCode(String n) {
    if (n.contains('القاهرة') || n.contains('مصر')) return 'EG';
    if (n.contains('السعودية') || n.contains('مكة')) return 'SA';
    if (n.contains('الكويت')) return 'KW';
    if (n.contains('المغرب')) return 'MA';
    if (n.contains('الجزائر')) return 'DZ';
    if (n.contains('تونس')) return 'TN';
    if (n.contains('قطر')) return 'QA';
    if (n.contains('الشارقة') || n.contains('الإمارات')) return 'AE';
    return 'INT';
  }

  static String _guessCategory(String n) {
    if (n.contains('محاضر') || n.contains('درس')) return 'lectures';
    if (n.contains('أناشيد') || n.contains('nasheed')) return 'nasheed';
    if (n.contains('مكة') || n.contains('صلاة')) return 'prayers';
    return 'quran';
  }
}
