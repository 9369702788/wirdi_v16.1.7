
import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/radio_station.dart';
import '../data/radio_stations.dart';

enum RadioState { stopped, loading, playing, error }

/// Which curated source is currently serving the station list.
enum RadioSource { dataRosy, uthumany, islamicApp, fallback }

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

  List<RadioStation> _liveStations = [];
  bool _loadingLive = false;
  RadioSource _activeSource = RadioSource.fallback;
  String _sourceLabel = 'Built-in stations';

  static const _favsKey = 'radio_favorites';

  // ── Getters ───────────────────────────────────────────────────────────────
  RadioState get state             => _state;
  RadioStation? get currentStation => _currentStation;
  String? get errorMessage         => _errorMessage;
  bool get isPlaying               => _state == RadioState.playing;
  bool get isLoading               => _state == RadioState.loading;
  int? get sleepMinutesRemaining   => _sleepMinutesRemaining;
  bool get hasSleepTimer           => _sleepTimer != null;
  bool get loadingLive             => _loadingLive;
  bool get loadingStations         => _loadingLive;   // alias used by radio_screen
  RadioSource get activeSource     => _activeSource;
  String get sourceLabel           => _sourceLabel;
  bool isFavorite(String id)       => _favoriteIds.contains(id);

  List<RadioStation> get stations  =>
      _liveStations.isNotEmpty ? _liveStations : kFallbackStations;

  List<RadioStation> get allStations => stations;  // alias

  List<RadioStation> get favoriteStations =>
      stations.where((s) => _favoriteIds.contains(s.id)).toList();

  // ── Init ──────────────────────────────────────────────────────────────────
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadFavorites();
    _player.onPlayerStateChanged.listen((ps) {
      if (ps == PlayerState.playing) {
        _state = RadioState.playing;
      } else if (ps == PlayerState.stopped || ps == PlayerState.completed ||
                 ps == PlayerState.paused) {
        if (_state != RadioState.error) _state = RadioState.stopped;
      }
      notifyListeners();
    });
    _fetchStations();
  }

  // ── Fetch stations — 3-tier curated Islamic sources ───────────────────────
  Future<void> _fetchStations() async {
    _loadingLive = true;
    notifyListeners();

    // Tier 1: data-rosy.vercel.app — 18 curated Quran stations
    if (await _tryDataRosy()) { _loadingLive = false; notifyListeners(); return; }

    // Tier 2: uthumany Islamic Radio API (GitHub CDN, CC0)
    if (await _tryUthumany()) { _loadingLive = false; notifyListeners(); return; }

    // Tier 3: fallback built-in list
    _activeSource = RadioSource.fallback;
    _sourceLabel = 'Built-in stations (offline)';
    _loadingLive = false;
    notifyListeners();
  }

  Future<bool> _tryDataRosy() async {
    try {
      final resp = await http.get(
        Uri.parse('https://data-rosy.vercel.app/radio.json'),
        headers: {'User-Agent': 'WirdiApp/1.51 (Islamic companion)'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return false;
      final List<dynamic> data = jsonDecode(resp.body);
      final stations = data
          .whereType<Map<String, dynamic>>()
          .map(RadioStation.fromDataRosy)
          .where((s) => s.streamUrl.isNotEmpty)
          .toList();
      if (stations.isEmpty) return false;
      _liveStations = stations;
      _activeSource = RadioSource.dataRosy;
      _sourceLabel = 'data-rosy · 18 verified Islamic stations';
      debugPrint('[Radio] Loaded ${stations.length} stations from data-rosy');
      return true;
    } catch (e) {
      debugPrint('[Radio] data-rosy failed: $e');
      return false;
    }
  }

  Future<bool> _tryUthumany() async {
    try {
      final resp = await http.get(
        Uri.parse(
          'https://raw.githubusercontent.com/uthumany/radio-api/main/client/public/api/stations.json'),
        headers: {'User-Agent': 'WirdiApp/1.51'},
      ).timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) return false;
      final List<dynamic> data = jsonDecode(resp.body);
      final stations = data
          .whereType<Map<String, dynamic>>()
          .map(RadioStation.fromUthumany)
          .where((s) => s.streamUrl.isNotEmpty)
          .toList();
      if (stations.isEmpty) return false;
      _liveStations = stations;
      _activeSource = RadioSource.uthumany;
      _sourceLabel = 'Islamic Radio API · curated stations';
      debugPrint('[Radio] Loaded ${stations.length} stations from uthumany');
      return true;
    } catch (e) {
      debugPrint('[Radio] uthumany failed: $e');
      return false;
    }
  }

  Future<void> refreshStations() async {
    _liveStations = [];
    await _fetchStations();
  }

  // ── Playback ──────────────────────────────────────────────────────────────
  Future<void> play(RadioStation station) async {
    try {
      if (_currentStation?.id == station.id && isPlaying) return;
      _state = RadioState.loading;
      _currentStation = station;
      _errorMessage = null;
      notifyListeners();
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.play(UrlSource(station.streamUrl));
    } catch (e) {
      debugPrint('[Radio] play error: ' + e.toString());
      _state = RadioState.error;
      _errorMessage = 'Could not connect. Check your internet connection.';
      notifyListeners();
    }
  }

  Future<void> stop() async {
    try { await _player.stop(); } catch (e) {
      debugPrint('[Radio] stop error: ' + e.toString());
    }
    _state = RadioState.stopped;
    _currentStation = null;
    cancelSleepTimer();
    notifyListeners();
  }

  Future<void> togglePlay(RadioStation station) async {
    if (_currentStation?.id == station.id && isPlaying) {
      await stop();
    } else {
      await play(station);
    }
  }

  // ── Sleep Timer ───────────────────────────────────────────────────────────
  void setSleepTimer(int minutes) {
    cancelSleepTimer();
    _sleepMinutesRemaining = minutes;
    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      await stop();
      _sleepMinutesRemaining = null;
      notifyListeners();
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
    _sleepTimer?.cancel();
    _sleepCountdown?.cancel();
    _sleepTimer = null;
    _sleepCountdown = null;
    _sleepMinutesRemaining = null;
  }

  // ── Favorites ─────────────────────────────────────────────────────────────
  Future<void> toggleFavorite(String stationId) async {
    if (_favoriteIds.contains(stationId)) {
      _favoriteIds.remove(stationId);
    } else {
      _favoriteIds.add(stationId);
    }
    await _saveFavorites();
    notifyListeners();
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
