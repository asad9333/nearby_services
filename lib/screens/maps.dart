import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import '../common.dart';

const String kTileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const LatLng kDefaultCenter = LatLng(28.4212, 70.2989); // Rahim Yar Khan

class MapPickerScreen extends StatefulWidget {
  final LatLng initial;
  const MapPickerScreen({super.key, required this.initial});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final MapController ctrl = MapController();
  late LatLng center = widget.initial;
  bool busy = false;

  Future<void> _me() async {
    setState(() => busy = true);
    final r = await currentLocation();
    if (!mounted) return;
    setState(() => busy = false);
    if (r.lat != null) {
      final p = LatLng(r.lat!, r.lng!);
      center = p;
      ctrl.move(p, 16);
    } else {
      showMsg(context, geoErrorText(r.error));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(context, 'pick_on_map'))),
      body: Stack(children: [
        FlutterMap(
          mapController: ctrl,
          options: MapOptions(
            initialCenter: widget.initial,
            initialZoom: 15,
            onPositionChanged: (camera, hasGesture) {
              center = camera.center;
            },
          ),
          children: [
            TileLayer(urlTemplate: kTileUrl, userAgentPackageName: 'com.nearby.services'),
          ],
        ),
        const Center(
          child: Padding(
            padding: EdgeInsets.only(bottom: 40),
            child: Icon(Icons.location_pin, color: Colors.red, size: 48),
          ),
        ),
        Positioned(
          right: 12,
          bottom: 90,
          child: FloatingActionButton.small(
            heroTag: 'me',
            onPressed: busy ? null : _me,
            child: busy
                ? const SizedBox(
                    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 20,
          child: FilledButton.icon(
            onPressed: () => Navigator.pop(context, center),
            icon: const Icon(Icons.check),
            label: Text(tr(context, 'confirm_location')),
          ),
        ),
      ]),
    );
  }
}

class WorkersMap extends StatelessWidget {
  final double lat;
  final double lng;
  final List<Rec> workers;
  final void Function(Rec w) onTap;
  const WorkersMap(
      {super.key, required this.lat, required this.lng, required this.workers, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final markers = <Marker>[
      Marker(
        point: LatLng(lat, lng),
        width: 44,
        height: 44,
        child: const Icon(Icons.my_location, color: Colors.blue, size: 34),
      ),
      for (final w in workers)
        Marker(
          point: LatLng(numOf(w['latitude']), numOf(w['longitude'])),
          width: 80,
          height: 66,
          child: GestureDetector(
            onTap: () => onTap(w),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.black26),
                ),
                child: Text(fmtDist(w['distance'] as double),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
              const Icon(Icons.location_pin, color: Colors.red, size: 36),
            ]),
          ),
        ),
    ];
    return FlutterMap(
      options: MapOptions(initialCenter: LatLng(lat, lng), initialZoom: 13),
      children: [
        TileLayer(urlTemplate: kTileUrl, userAgentPackageName: 'com.nearby.services'),
        MarkerLayer(markers: markers),
      ],
    );
  }
}
