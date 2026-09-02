import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

class TrackPage extends StatefulWidget {
  const TrackPage({super.key});

  @override
  State<TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends State<TrackPage> {
  LatLng? currentLocation;
  final MapController _mapController = MapController();
  StreamSubscription<Position>? _positionStream;
  bool _isMapReady = false;

  @override
  void initState() {
    super.initState();
    _initLocationTracking();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initLocationTracking() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      // Handle disabled service
      return;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    // 1. Get Initial Position
    Position position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    if (mounted) {
      setState(() {
        currentLocation = LatLng(position.latitude, position.longitude);
      });
    }

    // 2. Continuous Tracking Settings
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation, // Highest accuracy
      distanceFilter: 2, // Update every 2 meters
    );

    // 3. Listen to the Stream
    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings)
            .listen((Position position) {
      if (!mounted) return;

      final newLatLng = LatLng(position.latitude, position.longitude);

      setState(() {
        currentLocation = newLatLng;
      });

      // Move the map to the new position
      if (_isMapReady) {
        _mapController.move(newLatLng, 16);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title:
            const Text("Live Tracking", style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.orange),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: currentLocation == null
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: currentLocation!,
                initialZoom: 16,
                onMapReady: () => _isMapReady = true,
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                  userAgentPackageName: 'com.yourname.live_tracking_app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: currentLocation!,
                      width: 60,
                      height: 60,
                      child: const Icon(
                        Icons.motorcycle,
                        color: Colors.orange,
                        size: 45,
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}
