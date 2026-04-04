import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speak_dine/utils/city_normalize.dart';
import 'package:speak_dine/utils/toast_helper.dart';

/// Default center: Lahore, Pakistan
const _defaultLat = 31.5204;
const _defaultLng = 74.3587;

/// Picked map point: coordinates, formatted address line, and best-effort city for discovery filters.
typedef OnLocationSelectedCallback = void Function(
  double lat,
  double lng,
  String address,
  String? inferredCity,
);

/// A reusable widget for picking a location on a map.
/// Address text uses Nominatim reverse geocoding with English (`accept-language=en`).
/// Basemap uses Carto Light for Latin-script labels (English-oriented).
class LocationPicker extends StatefulWidget {
  const LocationPicker({
    super.key,
    this.initialLat,
    this.initialLng,
    required this.onLocationSelected,
  });

  final double? initialLat;
  final double? initialLng;
  final OnLocationSelectedCallback onLocationSelected;

  @override
  State<LocationPicker> createState() => _LocationPickerState();
}

class _LocationPickerState extends State<LocationPicker> {
  late MapController _mapController;
  late LatLng _selectedPoint;
  String _address = '';
  String? _inferredCity;
  bool _loadingAddress = false;
  bool _loadingMyLocation = false;
  int _geocodeGeneration = 0;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selectedPoint = LatLng(
      widget.initialLat ?? _defaultLat,
      widget.initialLng ?? _defaultLng,
    );
    _reverseGeocode(_selectedPoint);
  }

  /// Nominatim: English details; never show raw lat/lng in the UI.
  Future<void> _reverseGeocode(LatLng point) async {
    final gen = ++_geocodeGeneration;
    setState(() {
      _loadingAddress = true;
      _inferredCity = null;
    });
    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'lat': '${point.latitude}',
        'lon': '${point.longitude}',
        'format': 'jsonv2',
        'addressdetails': '1',
        'accept-language': 'en',
      });
      final res = await http
          .get(
            uri,
            headers: {
              'User-Agent':
                  'SpeakDine/1.0 (Flutter app; contact via app store listing)',
              'Accept-Language': 'en',
            },
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted || gen != _geocodeGeneration) return;

      if (res.statusCode != 200) {
        setState(() {
          _address =
              'Could not resolve address. Try moving the pin or try again.';
          _inferredCity = null;
          _loadingAddress = false;
        });
        return;
      }

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        setState(() {
          _address = 'Address not available. Try moving the pin slightly.';
          _inferredCity = null;
          _loadingAddress = false;
        });
        return;
      }

      final addr = decoded['address'] as Map<String, dynamic>?;
      final formatted = _formatNominatimAddress(addr);
      final displayName = decoded['display_name'] as String?;
      final line = (formatted != null && formatted.isNotEmpty)
          ? formatted
          : ((displayName != null && displayName.trim().isNotEmpty)
              ? displayName.trim()
              : 'Address not available. Try moving the pin slightly.');

      final city = cityFromNominatimAddress(addr);

      setState(() {
        _address = line;
        _inferredCity = city;
        _loadingAddress = false;
      });
    } catch (e, st) {
      debugPrint('[LocationPicker] reverse geocode: $e\n$st');
      if (!mounted || gen != _geocodeGeneration) return;
      setState(() {
        _address =
            'Could not load address. Check your connection and try again.';
        _inferredCity = null;
        _loadingAddress = false;
      });
    }
  }

  /// Build a single readable line: house number, street, area, city, region, country.
  String? _formatNominatimAddress(Map<String, dynamic>? raw) {
    if (raw == null) return null;
    String? g(String k) {
      final v = raw[k];
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    final line1Parts = <String>[];
    final hn = g('house_number');
    final road = g('road');
    final amenity = g('amenity');
    if (hn != null) line1Parts.add(hn);
    if (road != null) line1Parts.add(road);
    if (line1Parts.isEmpty && amenity != null) line1Parts.add(amenity);

    final area = g('area') ??
        g('neighbourhood') ??
        g('suburb') ??
        g('quarter') ??
        g('district');

    final city = g('city') ??
        g('town') ??
        g('village') ??
        g('municipality');

    final state = g('state') ?? g('region');
    final country = g('country');

    final segments = <String>[];
    if (line1Parts.isNotEmpty) {
      segments.add(line1Parts.join(' '));
    }
    if (area != null) segments.add(area);
    if (city != null) segments.add(city);
    if (state != null && state != city) segments.add(state);
    if (country != null) segments.add(country);

    if (segments.isEmpty) return null;
    return segments.join(', ');
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() => _selectedPoint = point);
    _mapController.move(point, _mapController.camera.zoom);
    _reverseGeocode(point);
  }

  Future<void> _useMyLocation() async {
    setState(() => _loadingMyLocation = true);
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        showAppToast(context, 'Location services are disabled. Please enable them.');
        setState(() => _loadingMyLocation = false);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        showAppToast(
          context,
          'Location permission permanently denied. Please enable in settings.',
        );
        setState(() => _loadingMyLocation = false);
        return;
      }
      if (permission == LocationPermission.denied) {
        if (!mounted) return;
        showAppToast(context, 'Location permission denied.');
        setState(() => _loadingMyLocation = false);
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      final point = LatLng(position.latitude, position.longitude);
      setState(() {
        _selectedPoint = point;
        _loadingMyLocation = false;
      });
      _mapController.move(point, 16.0);
      _reverseGeocode(point);
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        'Could not get your location. Please check permissions and try again.',
      );
      setState(() => _loadingMyLocation = false);
    }
  }

  void _confirmLocation() {
    widget.onLocationSelected(
      _selectedPoint.latitude,
      _selectedPoint.longitude,
      _address,
      _inferredCity,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 280,
          width: double.infinity,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _selectedPoint,
                initialZoom: 14,
                onTap: _onMapTap,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.doubleTapZoom,
                ),
              ),
              children: [
                /// Carto Light: Latin-script / English-oriented labels vs default OSM tiles.
                TileLayer(
                  urlTemplate:
                      'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c', 'd'],
                  userAgentPackageName: 'com.speakdine.app',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: _selectedPoint,
                      width: 48,
                      height: 48,
                      alignment: Alignment.topCenter,
                      child: Icon(
                        RadixIcons.crosshair1,
                        size: 48,
                        color: primary,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '© CARTO © OpenStreetMap contributors',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
        const SizedBox(height: 8),
        if (_loadingAddress)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text('Getting address...', style: TextStyle(color: primary)),
              ],
            ),
          )
        else if (_address.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              _address,
              textAlign: TextAlign.center,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ).muted().small(),
          ),
        if (_inferredCity != null &&
            _inferredCity!.trim().isNotEmpty &&
            !_loadingAddress) ...[
          const SizedBox(height: 6),
          Text(
            'City for discovery: ${_inferredCity!.trim()}',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: primary,
            ),
          ),
        ],
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlineButton(
                onPressed: _loadingMyLocation ? null : _useMyLocation,
                child: _loadingMyLocation
                    ? Center(
                        child: SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: primary,
                          ),
                        ),
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(RadixIcons.crosshair1, size: 16, color: primary),
                            const SizedBox(width: 8),
                            const Text('Use My Location'),
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: PrimaryButton(
                onPressed: _confirmLocation,
                child: const Text('Confirm Location'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
