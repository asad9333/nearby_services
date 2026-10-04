import 'dart:math';
import 'package:geolocator/geolocator.dart';

double haversineKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a = pow(sin(dLat / 2), 2) +
      cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * pow(sin(dLng / 2), 2);
  return 2 * r * asin(sqrt(min(1.0, a.toDouble())));
}

String fmtDist(double km) =>
    km < 1 ? '${(km * 1000).round()} m' : '${km.toStringAsFixed(1)} km';

class GeoResult {
  final double? lat;
  final double? lng;
  final String? error;
  GeoResult({this.lat, this.lng, this.error});
}

Future<GeoResult> currentLocation() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return GeoResult(error: 'gps_off');
    }
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied) {
      p = await Geolocator.requestPermission();
    }
    if (p == LocationPermission.denied) return GeoResult(error: 'perm_denied');
    if (p == LocationPermission.deniedForever) {
      return GeoResult(error: 'perm_forever');
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 25),
      ),
    );
    return GeoResult(lat: pos.latitude, lng: pos.longitude);
  } catch (e) {
    try {
      final l = await Geolocator.getLastKnownPosition();
      if (l != null) return GeoResult(lat: l.latitude, lng: l.longitude);
    } catch (_) {}
    return GeoResult(error: 'loc_fail');
  }
}

Future<void> openLocationSettings() async {
  try {
    await Geolocator.openLocationSettings();
  } catch (_) {}
}

Future<void> openAppSettings() async {
  try {
    await Geolocator.openAppSettings();
  } catch (_) {}
}
