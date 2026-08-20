import '../models/radio_station.dart';

/// Built-in fallback — shown immediately before API loads.
/// Stream URLs use radiojar.com CDN (same as data-rosy source).
const List<RadioStation> kFallbackStations = [
  RadioStation(id:'dr_1', nameAr:'إذاعة القرآن الكريم من القاهرة',
    nameEn:'Holy Quran Radio Cairo',
    streamUrl:'https://stream.radiojar.com/8s5u5tpdtwzuv',
    country:'Egypt', countryCode:'EG', category:'quran', isOfficial:true,
    imageUrl:'https://i.postimg.cc/d1kdrLkx/quran.jpg'),
  RadioStation(id:'dr_2', nameAr:'إذاعة القرآن الكريم السعودية',
    nameEn:'Saudi Holy Quran Radio',
    streamUrl:'https://n12.radiojar.com/0tpy1h0kxtzuv',
    country:'Saudi Arabia', countryCode:'SA', category:'quran', isOfficial:true,
    imageUrl:'https://i.postimg.cc/ZYSprKr8/download.png'),
  RadioStation(id:'dr_3', nameAr:'إذاعة القرآن الكريم من المغرب',
    nameEn:'Morocco Holy Quran Radio',
    streamUrl:'https://snrt-live.scdn.co/snrt-quran/index.m3u8',
    country:'Morocco', countryCode:'MA', category:'quran', isOfficial:true),
  RadioStation(id:'dr_4', nameAr:'إذاعة القرآن الكريم من الجزائر',
    nameEn:'Algeria Holy Quran Radio',
    streamUrl:'https://live.algerian-radio.dz/quran-128k.mp3',
    country:'Algeria', countryCode:'DZ', category:'quran', isOfficial:true),
];

const Map<String, Map<String, String>> kRadioCategories = {
  'quran':   {'ar':'القرآن الكريم','en':'Holy Quran','de':'Heiliger Quran','tr':'Kutsal Kuran','fr':'Saint Coran','es':'Sagrado Corán','id':'Al-Quran'},
  'prayers': {'ar':'الصلوات المباشرة','en':'Live Prayers','de':'Live-Gebete','tr':'Canlı Namaz','fr':'Prières en direct','es':'Oraciones en vivo','id':'Shalat Langsung'},
  'lectures':{'ar':'محاضرات ودروس','en':'Lectures','de':'Vorlesungen','tr':'Dersler','fr':'Conférences','es':'Conferencias','id':'Ceramah'},
  'nasheed': {'ar':'أناشيد إسلامية','en':'Nasheed','de':'Nasheed','tr':'Neşid','fr':'Nasheed','es':'Nasheed','id':'Nasyid'},
};
