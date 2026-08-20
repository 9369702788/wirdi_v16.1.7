import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/radio_station.dart';
import '../data/radio_stations.dart';

enum RadioState { stopped, loading, playing, error }
enum RadioSource { fallback, dataRosy, uthumany, islamicApp }

class RadioService extends ChangeNotifier {
  RadioService._();
  static final RadioService instance = RadioService._();

  final AudioPlayer _player = AudioPlayer();
  RadioState _state = RadioState.stopped;
  RadioStation? _currentStation;
  String? _errorMessage;
  Timer? _sleepTimer;
  Timer? _sleepCountdown;
  int? _sleepMinutesRemaining;
  Set<String> _favoriteIds = {};
  bool _initialized = false;
  List<RadioStation> _stations = kFallbackStations;
  bool _loadingStations = false;
  RadioSource _activeSource = RadioSource.fallback;

  static const _favsKey = 'radio_favorites';

  RadioState get state             => _state;
  RadioStation? get currentStation => _currentStation;
  String? get errorMessage         => _errorMessage;
  bool get isPlaying               => _state == RadioState.playing;
  bool get isLoading               => _state == RadioState.loading;
  int? get sleepMinutesRemaining   => _sleepMinutesRemaining;
  bool get hasSleepTimer           => _sleepTimer != null;
  bool get loadingStations         => _loadingStations;
  RadioSource get activeSource     => _activeSource;
  bool isFavorite(String id)       => _favoriteIds.contains(id);
  List<RadioStation> get stations  => _stations;
  List<RadioStation> get favoriteStations =>
      _stations.where((s) => _favoriteIds.contains(s.id)).toList();

  String get sourceLabel {
    switch (_activeSource) {
      case RadioSource.dataRosy:   return 'data-rosy (verified Islamic)';
      case RadioSource.uthumany:   return 'uthumany Islamic Radio API';
      case RadioSource.islamicApp: return 'islamic.app Radio API';
      case RadioSource.fallback:   return 'Built-in fallback';
    }
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadFavorites();
    _player.onPlayerStateChanged.listen((ps) {
      debugPrint('[Radio] PlayerState: \$ps');
      if (ps == PlayerState.playing) {
        _state = RadioState.playing;
      } else if (ps == PlayerState.stopped || ps == PlayerState.completed) {
        if (_state != RadioState.error) _state = RadioState.stopped;
      }
      notifyListeners();
    });
    _fetchStations();
  }

  Future<void> _fetchStations() async {
    _loadingStations = true;
    notifyListeners();
    if (await _tryDataRosy()) { _done(); return; }
    if (await _tryUthumany()) { _done(); return; }
    if (await _tryIslamicApp()) { _done(); return; }
    _activeSource = RadioSource.fallback;
    _done();
  }

  void _done() { _loadingStations = false; notifyListeners(); }

  Future<bool> _tryDataRosy() async {
    try {
      final r = await http.get(
        Uri.parse('https://data-rosy.vercel.app/radio.json'),
        headers: {'User-Agent': 'WirdiApp/1.51'},
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final data = jsonDecode(r.body) as List;
        final s = data.map((j) => RadioStation.fromDataRosy(j as Map<String, dynamic>))
            .where((s) => s.streamUrl.isNotEmpty).toList();
        if (s.isNotEmpty) { _stations = s; _activeSource = RadioSource.dataRosy; return true; }
      }
    } catch (e) { debugPrint('[Radio] data-rosy failed: \$e'); }
    return false;
  }

  Future<bool> _tryUthumany() async {
    try {
      final r = await http.get(
        Uri.parse('https://raw.githubusercontent.com/uthumany/radio-api/main/client/public/api/stations.json'),
        headers: {'User-Agent': 'WirdiApp/1.51'},
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final decoded = jsonDecode(r.body);
        final List data = decoded is List ? decoded
            : (decoded is Map && decoded.containsKey('stations'))
                ? decoded['stations'] as List : [];
        final s = data.map((j) => RadioStation.fromUthumany(j as Map<String, dynamic>))
            .where((s) => s.streamUrl.isNotEmpty).toList();
        if (s.isNotEmpty) { _stations = s; _activeSource = RadioSource.uthumany; return true; }
      }
    } catch (e) { debugPrint('[Radio] uthumany failed: \$e'); }
    return false;
  }

  Future<bool> _tryIslamicApp() async {
    try {
      final r = await http.get(
        Uri.parse('https://api.islamic.app/v1/radio/stations'),
        headers: {'User-Agent': 'WirdiApp/1.51'},
      ).timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final decoded = jsonDecode(r.body);
        final List data = decoded is List ? decoded
            : (decoded is Map && decoded.containsKey('data'))
                ? decoded['data'] as List : [];
        final s = data.map((j) {
          final m = j as Map<String, dynamic>;
          return RadioStation(
            id: 'ia_\${m["slug"] ?? m["id"] ?? ""}',
            nameAr: m['name_ar'] as String? ?? m['name'] as String? ?? '',
            nameEn: m['name'] as String? ?? '',
            streamUrl: m['stream_url'] as String? ??
                'https://api.islamic.app/v1/radio/stations/\${m["slug"]}/stream',
            country: m['country'] as String? ?? 'International',
            countryCode: m['country_code'] as String? ?? 'INT',
            category: 'quran',
            isOfficial: m['official'] as bool? ?? false,
            imageUrl: m['logo_url'] as String? ?? m['image'] as String?,
          );
        }).where((s) => s.streamUrl.isNotEmpty).toList();
        if (s.isNotEmpty) { _stations = s; _activeSource = RadioSource.islamicApp; return true; }
      }
    } catch (e) { debugPrint('[Radio] islamic.app failed: \$e'); }
    return false;
  }

  Future<void> refreshStations() => _fetchStations();

  Future<void> play(RadioStation station) async {
    debugPrint('[Radio] play: \${station.nameEn} -> \${station.streamUrl}');
    try {
      if (_currentStation?.id == station.id && isPlaying) return;
      _state = RadioState.loading;
      _currentStation = station;
      _errorMessage = null;
      notifyListeners();
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(UrlSource(station.streamUrl));
    } catch (e, st) {
      debugPrint('[Radio] play error: \$e
\$st');
      _state = RadioState.error;
      _errorMessage = 'Error: \$e';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    try { await _player.stop(); } catch (_) {}
    _state = RadioState.stopped;
    _currentStation = null;
    cancelSleepTimer();
    notifyListeners();
  }

  Future<void> togglePlay(RadioStation station) async {
    if (_currentStation?.id == station.id && isPlaying) { await stop(); }
    else { await play(station); }
  }

  void setSleepTimer(int minutes) {
    cancelSleepTimer();
    _sleepMinutesRemaining = minutes;
    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      await stop(); _sleepMinutesRemaining = null; notifyListeners();
    });
    _sleepCountdown = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_sleepMinutesRemaining != null && _sleepMinutesRemaining! > 0) {
        _sleepMinutesRemaining = _sleepMinutesRemaining! - 1;
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel(); _sleepCountdown?.cancel();
    _sleepTimer = null; _sleepCountdown = null; _sleepMinutesRemaining = null;
  }

  Future<void> toggleFavorite(String stationId) async {
    if (_favoriteIds.contains(stationId)) { _favoriteIds.remove(stationId); }
    else { _favoriteIds.add(stationId); }
    await _saveFavorites(); notifyListeners();
  }

  Future<void> _loadFavorites() async {
    final p = await SharedPreferences.getInstance();
    _favoriteIds = (p.getStringList(_favsKey) ?? []).toSet();
  }

  Future<void> _saveFavorites() async {
    final p = await SharedPreferences.getInstance();
    await p.setStringList(_favsKey, _favoriteIds.toList());
  }
}
