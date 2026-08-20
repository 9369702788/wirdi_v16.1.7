import 'dart:async';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/radio_station.dart';
import '../data/radio_stations.dart';

enum RadioState { stopped, loading, playing, error }

class RadioService extends ChangeNotifier {
  RadioService._();
  static final RadioService instance = RadioService._();

  AudioPlayer _player = AudioPlayer();
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
  String _sourceLabel = '';

  static const _favsKey = 'radio_favorites';

  RadioState get state => _state;
  RadioStation? get currentStation => _currentStation;
  String? get errorMessage => _errorMessage;
  bool get isPlaying => _state == RadioState.playing;
  bool get isLoading => _state == RadioState.loading;
  int? get sleepMinutesRemaining => _sleepMinutesRemaining;
  bool get hasSleepTimer => _sleepTimer != null;
  bool get loadingLive => _loadingLive;
  String get sourceLabel => _sourceLabel;
  bool isFavorite(String id) => _favoriteIds.contains(id);

  List<RadioStation> get allStations =>
      _liveStations.isNotEmpty ? _liveStations : kFallbackStations;

  List<RadioStation> get favoriteStations =>
      allStations.where((s) => _favoriteIds.contains(s.id)).toList();

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    await _loadFavorites();
    _player.onPlayerStateChanged.listen((ps) {
      if (ps == PlayerState.playing) {
        _state = RadioState.playing;
      } else if (ps == PlayerState.stopped ||
          ps == PlayerState.completed ||
          ps == PlayerState.paused) {
        if (_state != RadioState.error) _state = RadioState.stopped;
      }
      notifyListeners();
    });
    _fetchStations();
  }

  Future<void> refreshStations() => _fetchStations();

  Future<void> _fetchStations() async {
    _loadingLive = true;
    notifyListeners();
    try {
      // Tier 1: data-rosy.vercel.app — 18 curated Islamic stations
      final r1 = await http.get(
        Uri.parse('https://data-rosy.vercel.app/radio.json'),
        headers: {'User-Agent': 'WirdiApp/1.51'},
      ).timeout(const Duration(seconds: 10));
      if (r1.statusCode == 200) {
        final List<dynamic> data = jsonDecode(r1.body);
        final stations = data
            .map((j) => RadioStation.fromDataRosy(j as Map<String, dynamic>))
            .where((s) => s.streamUrl.isNotEmpty)
            .toList();
        if (stations.isNotEmpty) {
          _liveStations = stations;
          _sourceLabel = 'data-rosy';
          _loadingLive = false;
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint('[RadioService] Tier 1 failed: $e');
    }
    try {
      // Tier 2: uthumany Islamic Radio API (GitHub CDN)
      final r2 = await http.get(
        Uri.parse('https://raw.githubusercontent.com/uthumany/radio-api/main/client/public/api/stations.json'),
        headers: {'User-Agent': 'WirdiApp/1.51'},
      ).timeout(const Duration(seconds: 10));
      if (r2.statusCode == 200) {
        final List<dynamic> data = jsonDecode(r2.body);
        final stations = data
            .map((j) => RadioStation.fromUthumany(j as Map<String, dynamic>))
            .where((s) => s.streamUrl.isNotEmpty)
            .toList();
        if (stations.isNotEmpty) {
          _liveStations = stations;
          _sourceLabel = 'uthumany';
          _loadingLive = false;
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint('[RadioService] Tier 2 failed: $e');
    }
    try {
      // Tier 3: radio-browser.info — quran tag, verified streams
      final r3 = await http.get(
        Uri.parse('https://de1.api.radio-browser.info/json/stations/search'
            '?tag=quran&limit=30&hidebroken=true&order=votes&reverse=true'),
        headers: {'User-Agent': 'WirdiApp/1.51', 'Accept': 'application/json'},
      ).timeout(const Duration(seconds: 12));
      if (r3.statusCode == 200) {
        final List<dynamic> data = jsonDecode(r3.body);
        final stations = data
            .map((j) => RadioStation.fromRadioBrowser(j as Map<String, dynamic>))
            .where((s) => s.streamUrl.isNotEmpty)
            .toList();
        if (stations.isNotEmpty) {
          _liveStations = stations;
          _sourceLabel = 'radio-browser';
          _loadingLive = false;
          notifyListeners();
          return;
        }
      }
    } catch (e) {
      debugPrint('[RadioService] Tier 3 failed: $e');
    }
    // Tier 4: built-in fallback
    _liveStations = [];
    _sourceLabel = 'fallback';
    _loadingLive = false;
    notifyListeners();
  }

  Future<void> play(RadioStation station) async {
    debugPrint('[RadioService] play: ' + station.nameEn + ' -> ' + station.streamUrl);
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
      debugPrint('[RadioService] play error: ' + e.toString());
      _state = RadioState.error;
      _errorMessage = 'Error: ' + e.toString();
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
    if (_currentStation?.id == station.id && isPlaying) {
      await stop();
    } else {
      await play(station);
    }
  }

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
