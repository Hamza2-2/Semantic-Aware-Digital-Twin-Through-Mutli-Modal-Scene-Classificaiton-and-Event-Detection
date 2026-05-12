// file header note
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/glass_container.dart';
import '../services/ip_address_service.dart';
import '../main.dart' show routeObserver;
import '../utils/glass_snackbar.dart';
import '../theme/theme_controller.dart';


const LatLng _islamabadCenter = LatLng(33.6844, 73.0479);
const double _defaultZoom = 11.0;


class EventMapScreen extends StatefulWidget {
  const EventMapScreen({super.key});

  @override
  State<EventMapScreen> createState() => _EventMapScreenState();
}

class _EventMapScreenState extends State<EventMapScreen> with RouteAware {
  final MapController _mapController = MapController();
  final IpAddressService _ipService = IpAddressService();

  String _backendUrl = 'http://localhost:3000';
  bool _loading = true;
  String? _error;

  List<_MapEvent> _events = [];
  _MapEvent? _selectedEvent;

  
  LatLng? _userLocation;
  bool _pickingLocation = false; 
  bool _resolvingIpLocation = false;
  bool _resolvingGpsLocation = false;
  String _locationAccuracy = 'unknown'; 

  
  _MapStyle _mapStyle = _MapStyle.standard;

  
  _MapProvider _mapProvider = _MapProvider.osm;

  
  bool _enableDarkMapTiles = false;

  
  String? _severityFilter;
  final List<String> _severities = ['all', 'critical', 'high', 'medium', 'low'];

  
  _MapEvent? _waypointTarget;
  List<LatLng> _routePoints = [];
  bool _showTraffic = false;
  List<_TrafficSegment> _trafficSegments = [];
  double _routeDistKm = 0;
  double _routeDurationMin = 0;
  bool _fetchingRoute = false;

  
  bool _showDummyEvents = false;

  
  bool _showDetectedEvents = true;

  
  final Set<String> _neutralizedEventIds = {};

  
  final Map<String, Map<String, String>> _resolvedLocations = {};
  final Set<String> _resolvingLocationIds = {};

  @override
  void initState() {
    super.initState();
    _loadSettings().then((_) => _fetchEvents());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    routeObserver.subscribe(this, ModalRoute.of(context)!);
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    super.dispose();
  }

  
  @override
  void didPopNext() {
    _reloadUserLocation();
    _checkDummyToggleChange();
  }

  
  Future<void> _checkDummyToggleChange() async {
    final prefs = await SharedPreferences.getInstance();
    bool needsRefresh = false;

    final newDummyToggle = prefs.getBool('show_dummy_map_events') ?? false;
    if (newDummyToggle != _showDummyEvents) {
      _neutralizedEventIds.removeWhere((id) => id.startsWith('dummy_'));
      _showDummyEvents = newDummyToggle;
      needsRefresh = true;
    }

    final newDetectedToggle =
        prefs.getBool('show_detected_events_on_map') ?? true;
    if (newDetectedToggle != _showDetectedEvents) {
      _showDetectedEvents = newDetectedToggle;
      needsRefresh = true;
    }

    if (needsRefresh) _fetchEvents();
  }

  
  Future<void> _reloadUserLocation() async {
    final prefs = await SharedPreferences.getInstance();
    final uLat = prefs.getDouble('user_location_lat');
    final uLng = prefs.getDouble('user_location_lng');
    if (uLat != null && uLng != null) {
      final newLoc = LatLng(uLat, uLng);
      
      final isDifferent = _userLocation == null ||
          (_userLocation!.latitude != uLat || _userLocation!.longitude != uLng);
      if (isDifferent && mounted) {
        setState(() => _userLocation = newLoc);
        _mapController.move(newLoc, _mapController.camera.zoom);
      }
    }
    
    final darkMapTiles = prefs.getBool('enable_dark_map_tiles') ?? false;
    if (darkMapTiles != _enableDarkMapTiles && mounted) {
      setState(() => _enableDarkMapTiles = darkMapTiles);
    }
  }

  
  
  Future<void> _resolveEventLocation(_MapEvent event) async {
    if (_resolvedLocations.containsKey(event.id)) return;
    if (_resolvingLocationIds.contains(event.id)) return;
    
    if (event.city != 'Unknown' && event.city.isNotEmpty) return;

    _resolvingLocationIds.add(event.id);

    try {
      final uri = Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?format=json&lat=${event.latitude}&lon=${event.longitude}&zoom=14&addressdetails=1');
      final response = await http.get(uri, headers: {
        'User-Agent': 'MVATS/1.0',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final addr = data['address'] as Map<String, dynamic>? ?? {};
        final city = addr['city'] ??
            addr['town'] ??
            addr['village'] ??
            addr['suburb'] ??
            addr['neighbourhood'] ??
            addr['county'] ??
            'Unknown';
        final region = addr['state'] ??
            addr['county'] ??
            addr['state_district'] ??
            'Unknown';
        final country = addr['country'] ?? 'Unknown';

        if (mounted) {
          setState(() {
            _resolvedLocations[event.id] = {
              'city': city,
              'region': region,
              'country': country,
            };
          });
        }
      }
    } catch (e) {
      debugPrint('[EventMap] Reverse geocode failed for ${event.id}: $e');
    } finally {
      _resolvingLocationIds.remove(event.id);
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _backendUrl = prefs.getString('backend_url') ?? 'http://localhost:3000';
    _showDummyEvents = prefs.getBool('show_dummy_map_events') ?? false;
    _showDetectedEvents = prefs.getBool('show_detected_events_on_map') ?? true;

    
    final providerStr = prefs.getString('default_map_provider') ?? 'osm';
    _mapProvider =
        providerStr == 'google' ? _MapProvider.google : _MapProvider.osm;

    
    _enableDarkMapTiles = prefs.getBool('enable_dark_map_tiles') ?? false;

    
    final uLat = prefs.getDouble('user_location_lat');
    final uLng = prefs.getDouble('user_location_lng');
    if (uLat != null && uLng != null) {
      _userLocation = LatLng(uLat, uLng);
    }

    
    if (_userLocation == null) {
      final gpsResult = await _getGpsLocation(silent: true);
      if (gpsResult == null) {
        await _resolveLocationFromIp();
      }
    }
  }

  
  
  
  Future<LatLng?> _getGpsLocation({bool silent = false}) async {
    if (!mounted) return null;
    setState(() => _resolvingGpsLocation = true);

    try {
      
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!silent && mounted) {
          showGlassSnackBar(
            context,
            'Location services disabled. Enable GPS in system settings.',
            isError: true,
          );
        }
        if (mounted) setState(() => _resolvingGpsLocation = false);
        return null;
      }

      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          if (!silent && mounted) {
            showGlassSnackBar(
              context,
              'Location permission denied. Grant permission for GPS.',
              isError: true,
            );
          }
          if (mounted) setState(() => _resolvingGpsLocation = false);
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        if (!silent && mounted) {
          showGlassSnackBar(
            context,
            'Location permanently denied. Enable in system settings.',
            isError: true,
          );
        }
        if (mounted) setState(() => _resolvingGpsLocation = false);
        return null;
      }

      
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      final location = LatLng(position.latitude, position.longitude);

      
      _userLocation = location;
      _locationAccuracy = 'gps_precise';
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('user_location_lat', position.latitude);
      await prefs.setDouble('user_location_lng', position.longitude);

      
      String areaName = '';
      try {
        final geoResp = await http
            .get(Uri.parse(
                '$_backendUrl/locations/reverse-geocode?lat=${position.latitude}&lng=${position.longitude}'))
            .timeout(const Duration(seconds: 8));
        if (geoResp.statusCode == 200) {
          final geoData = json.decode(geoResp.body);
          if (geoData['success'] == true) {
            final d = geoData['data'];
            final parts = <String>[
              if ((d['neighbourhood'] ?? '').isNotEmpty) d['neighbourhood'],
              if ((d['city'] ?? '').isNotEmpty) d['city'],
            ];
            areaName = parts.join(', ');
          }
        }
      } catch (_) {}

      if (mounted) {
        setState(() => _resolvingGpsLocation = false);
        final accuracy = position.accuracy.toStringAsFixed(0);
        final locationDesc = areaName.isNotEmpty
            ? areaName
            : '${position.latitude.toStringAsFixed(5)}, ${position.longitude.toStringAsFixed(5)}';
        showGlassSnackBar(
          context,
          'GPS: $locationDesc (\u00b1${accuracy}m)',
          icon: Icons.gps_fixed_rounded,
          iconColor: Colors.green,
        );
      }

      return location;
    } catch (e) {
      if (!silent && mounted) {
        showGlassSnackBar(
          context,
          'GPS failed: ${e.toString().split(':').last.trim()}',
          isError: true,
        );
      }
    }

    if (mounted) setState(() => _resolvingGpsLocation = false);
    return null;
  }

  
  Future<void> _hybridLocate() async {
    if (!mounted) return;
    
    final gpsLoc = await _getGpsLocation();
    if (gpsLoc != null) {
      if (mounted) _mapController.move(gpsLoc, 15);
      return;
    }
    
    final ipResult = await _resolveLocationFromIp();
    if (ipResult.location != null && mounted) {
      _mapController.move(ipResult.location!, 13);
      showGlassSnackBar(
        context,
        'GPS unavailable. Using IP (~city level)',
        icon: Icons.language,
        iconColor: Colors.orange,
      );
    }
  }

  
  
  Future<({LatLng? location, String city})> _resolveLocationFromIp() async {
    if (!mounted) return (location: null, city: '');
    setState(() => _resolvingIpLocation = true);
    LatLng? resolvedLocation;
    String resolvedCity = '';
    String? errorMsg;

    try {
      
      final prefs = await SharedPreferences.getInstance();
      String? ip = prefs.getString('my_location_ip');

      
      if (ip == null || ip.isEmpty) {
        await _ipService.load();
        if (_ipService.devices.isNotEmpty) {
          ip = _ipService.devices.first.address.split(':').first; 
        }
      } else {
        ip = ip.split(':').first; 
      }

      if (ip == null || ip.isEmpty) {
        errorMsg = 'No IP address configured. Set one in Settings.';
      } else {
        
        final isPrivate = ip.startsWith('192.168.') ||
            ip.startsWith('10.') ||
            ip.startsWith('172.16.') ||
            ip.startsWith('172.17.') ||
            ip.startsWith('172.18.') ||
            ip.startsWith('172.19.') ||
            ip.startsWith('172.2') ||
            ip.startsWith('172.30.') ||
            ip.startsWith('172.31.') ||
            ip == '127.0.0.1' ||
            ip == 'localhost';

        if (isPrivate) {
          errorMsg = 'Private IP ($ip) cannot be geolocated. Use a public IP.';
        } else {
          final resp = await http
              .get(Uri.parse('$_backendUrl/locations/geolocate/$ip'))
              .timeout(const Duration(seconds: 10));
          if (resp.statusCode == 200) {
            final data = json.decode(resp.body);
            if (data['success'] == true) {
              final d = data['data'];
              final lat = (d['latitude'] as num).toDouble();
              final lng = (d['longitude'] as num).toDouble();
              resolvedCity = d['city'] ?? 'Unknown';
              if (lat != 0 || lng != 0) {
                resolvedLocation = LatLng(lat, lng);
                
                _userLocation = resolvedLocation;
                await prefs.setDouble('user_location_lat', lat);
                await prefs.setDouble('user_location_lng', lng);
              } else {
                errorMsg = 'IP resolved to invalid coordinates (0,0)';
              }
            } else {
              errorMsg = data['message'] ?? 'Geolocation failed';
            }
          } else if (resp.statusCode == 404) {
            errorMsg = 'Could not geolocate IP: $ip';
          } else {
            errorMsg = 'Backend error: ${resp.statusCode}';
          }
        }
      }
    } catch (e) {
      errorMsg = 'Network error: $e';
    }

    if (mounted) {
      setState(() => _resolvingIpLocation = false);
      if (errorMsg != null) {
        showGlassSnackBar(context, errorMsg, isError: true);
      }
    }
    return (location: resolvedLocation, city: resolvedCity);
  }

  
  
  Future<({LatLng? location, String city})> _autoDetectLocation() async {
    if (!mounted) return (location: null, city: '');
    setState(() => _resolvingIpLocation = true);
    LatLng? resolvedLocation;
    String resolvedCity = '';
    String? errorMsg;

    try {
      final resp = await http
          .get(Uri.parse('$_backendUrl/locations/geolocate-me'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data['success'] == true) {
          final d = data['data'];
          final lat = (d['latitude'] as num).toDouble();
          final lng = (d['longitude'] as num).toDouble();
          resolvedCity = d['city'] ?? 'Unknown';
          if (lat != 0 || lng != 0) {
            resolvedLocation = LatLng(lat, lng);
            _userLocation = resolvedLocation;
            final prefs = await SharedPreferences.getInstance();
            await prefs.setDouble('user_location_lat', lat);
            await prefs.setDouble('user_location_lng', lng);
          } else {
            errorMsg = 'Auto-detect resolved to invalid coordinates';
          }
        } else {
          errorMsg = data['error'] ?? 'Auto-detect failed';
        }
      } else {
        errorMsg = 'Auto-detect error: ${resp.statusCode}';
      }
    } catch (e) {
      errorMsg = 'Network error: $e';
    }

    if (mounted) {
      setState(() => _resolvingIpLocation = false);
      if (errorMsg != null) {
        showGlassSnackBar(context, errorMsg, isError: true);
      }
    }
    return (location: resolvedLocation, city: resolvedCity);
  }

  
  LatLng get _origin => _userLocation ?? _islamabadCenter;

  
  
  
  Future<void> _fetchEvents() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    
    
    if (!_showDetectedEvents) {
      final events = <_MapEvent>[];
      if (_showDummyEvents) events.addAll(_dummyEvents());
      events.removeWhere((e) => _neutralizedEventIds.contains(e.id));
      if (mounted) {
        setState(() {
          _events = events;
          _loading = false;
        });
      }
      return;
    }

    try {
      String url = '$_backendUrl/events?limit=200';
      if (_severityFilter != null && _severityFilter != 'all') {
        url += '&severity=$_severityFilter';
      }

      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List list = data['data'] ?? [];

        final events = <_MapEvent>[];
        for (final e in list) {
          final loc = e['locationId'];
          if (loc == null) continue;
          double lat = 0, lng = 0;
          final coords = loc['coordinates'];
          if (coords is List && coords.length == 2) {
            lng = (coords[0] as num).toDouble();
            lat = (coords[1] as num).toDouble();
          }
          if (lat == 0 && lng == 0) continue;

          events.add(_MapEvent(
            id: e['id'] ?? '',
            eventType: e['eventType'] ?? 'unknown',
            severity: e['severity'] ?? 'medium',
            predictedClass: e['predictedClass'] ?? '',
            confidence: (e['confidence'] ?? 0).toDouble(),
            status: e['status'] ?? 'detected',
            latitude: lat,
            longitude: lng,
            city: loc['city'] ?? '',
            region: loc['region'] ?? '',
            country: loc['country'] ?? '',
            accuracy: loc['accuracy'] ?? 'unknown',
            ipAddress: loc['ipAddress'] ?? '',
            streamUrl: e['streamUrl'] ?? '',
            createdAt: e['createdAt'] ?? '',
          ));
        }

        if (_showDummyEvents) events.addAll(_dummyEvents());
        
        events.removeWhere((e) => _neutralizedEventIds.contains(e.id));
        if (!mounted) return;
        setState(() {
          _events = events;
          _loading = false;
        });
      } else {
        if (_showDummyEvents) {
          final dummies = _dummyEvents();
          dummies.removeWhere((e) => _neutralizedEventIds.contains(e.id));
          if (!mounted) return;
          setState(() {
            _events = dummies;
            _loading = false;
            _error = null;
          });
        } else {
          if (!mounted) return;
          setState(() {
            _error = 'Server returned ${response.statusCode}';
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (_showDummyEvents) {
        final dummies = _dummyEvents();
        dummies.removeWhere((ev) => _neutralizedEventIds.contains(ev.id));
        if (!mounted) return;
        setState(() {
          _events = dummies;
          _loading = false;
          _error = null;
        });
      } else {
        if (!mounted) return;
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  
  
  
  List<_MapEvent> _dummyEvents() => [
        _MapEvent(
            id: 'dummy_1',
            eventType: 'explosion',
            severity: 'high',
            predictedClass: 'street_traffic',
            confidence: 0.87,
            status: 'detected',
            latitude: 33.7294,
            longitude: 73.0931,
            city: 'Islamabad',
            region: 'ICT',
            country: 'Pakistan',
            accuracy: 'city_level',
            ipAddress: '203.135.62.10',
            createdAt: DateTime.now().toIso8601String(),
            isDummy: true),
        _MapEvent(
            id: 'dummy_2',
            eventType: 'fire',
            severity: 'critical',
            predictedClass: 'shopping_mall',
            confidence: 0.93,
            status: 'detected',
            latitude: 33.6995,
            longitude: 73.0363,
            city: 'Islamabad',
            region: 'ICT',
            country: 'Pakistan',
            accuracy: 'gps',
            ipAddress: '203.135.62.55',
            createdAt: DateTime.now()
                .subtract(const Duration(minutes: 12))
                .toIso8601String(),
            isDummy: true),
        _MapEvent(
            id: 'dummy_3',
            eventType: 'accident',
            severity: 'medium',
            predictedClass: 'street_traffic',
            confidence: 0.72,
            status: 'investigating',
            latitude: 33.6539,
            longitude: 73.0486,
            city: 'Islamabad',
            region: 'ICT',
            country: 'Pakistan',
            accuracy: 'city_level',
            ipAddress: '39.32.11.4',
            createdAt: DateTime.now()
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
            isDummy: true),
        _MapEvent(
            id: 'dummy_4',
            eventType: 'riot',
            severity: 'high',
            predictedClass: 'public_square',
            confidence: 0.81,
            status: 'detected',
            latitude: 33.7380,
            longitude: 73.0842,
            city: 'Rawalpindi',
            region: 'Punjab',
            country: 'Pakistan',
            accuracy: 'approximate',
            ipAddress: '203.135.62.99',
            createdAt: DateTime.now()
                .subtract(const Duration(minutes: 35))
                .toIso8601String(),
            isDummy: true),
      ];

  
  
  
  Future<void> _startWaypointNavigation(_MapEvent target) async {
    final dest = LatLng(target.latitude, target.longitude);

    setState(() {
      _waypointTarget = target;
      _fetchingRoute = true;
      _selectedEvent = null;
      _routePoints = [];
      _trafficSegments = [];
      _showTraffic = true;
    });

    try {
      final route = await _fetchOsrmRoute(_origin, dest);
      if (route != null && route.isNotEmpty) {
        final traffic = _simulateTraffic(route);
        setState(() {
          _routePoints = route;
          _trafficSegments = traffic;
          _fetchingRoute = false;
        });
      } else {
        
        setState(() {
          _routePoints = [_origin, dest];
          _trafficSegments = [];
          _fetchingRoute = false;
        });
      }
    } catch (_) {
      setState(() {
        _routePoints = [_origin, dest];
        _trafficSegments = [];
        _fetchingRoute = false;
      });
    }

    
    try {
      final pts = [
        _origin,
        LatLng(target.latitude, target.longitude),
        ..._routePoints
      ];
      final bounds = LatLngBounds.fromPoints(pts);
      _mapController.fitCamera(
        CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(60)),
      );
    } catch (_) {}
  }

  
  Future<List<LatLng>?> _fetchOsrmRoute(LatLng from, LatLng to) async {
    final url = 'https://router.project-osrm.org/route/v1/driving/'
        '${from.longitude},${from.latitude};${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson&steps=true';

    final resp =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return null;

    final data = json.decode(resp.body);
    if (data['code'] != 'Ok') return null;

    final route = data['routes']?[0];
    if (route == null) return null;

    
    _routeDistKm = (route['distance'] as num).toDouble() / 1000.0;
    _routeDurationMin = (route['duration'] as num).toDouble() / 60.0;

    
    final coords = route['geometry']?['coordinates'] as List?;
    if (coords == null) return null;

    return coords
        .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
        .toList();
  }

  
  List<_TrafficSegment> _simulateTraffic(List<LatLng> route) {
    final rng = Random(42);
    final segs = <_TrafficSegment>[];
    for (int i = 0; i < route.length - 1; i++) {
      segs.add(_TrafficSegment(
          from: route[i], to: route[i + 1], level: rng.nextInt(4)));
    }
    return segs;
  }

  void _cancelWaypoint() {
    setState(() {
      _waypointTarget = null;
      _routePoints = [];
      _trafficSegments = [];
      _showTraffic = false;
      _routeDistKm = 0;
      _routeDurationMin = 0;
    });
  }

  
  
  
  void _onMapLongPress(TapPosition tapPos, LatLng point) {
    _setUserLocation(point);
  }

  Future<void> _setUserLocation(LatLng point) async {
    if (!mounted) return;
    setState(() {
      _userLocation = point;
      _locationAccuracy = 'manual';
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('user_location_lat', point.latitude);
    await prefs.setDouble('user_location_lng', point.longitude);

    if (mounted) {
      showGlassSnackBar(
        context,
        'Location set: ${point.latitude.toStringAsFixed(5)}, ${point.longitude.toStringAsFixed(5)}',
        icon: Icons.location_on_rounded,
        iconColor: Colors.teal,
      );
    }

    
    if (_waypointTarget != null) {
      _startWaypointNavigation(_waypointTarget!);
    }
  }

  
  Future<void> _neutralizeEvent(_MapEvent event) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1A1A2E)
            : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.verified_rounded, color: const Color(0xFF7C4DFF)),
            const SizedBox(width: 10),
            const Text('Neutralize Event'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure this event has been taken care of?',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _severityColor(event.severity).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(_eventIcon(event.eventType),
                      color: _severityColor(event.severity), size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${event.eventType.replaceAll('_', ' ').toUpperCase()} - ${event.severity.toUpperCase()}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _severityColor(event.severity),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Confirm'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C4DFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _neutralizedEventIds.add(event.id);
        _events.removeWhere((e) => e.id == event.id);
        _selectedEvent = null;
      });
      showGlassSnackBar(
        context,
        'Event neutralized: ${event.eventType.replaceAll('_', ' ')}',
        icon: Icons.verified_rounded,
        iconColor: Colors.green,
      );
    }
  }

  
  
  
  Color _severityColor(String sev) {
    switch (sev) {
      case 'critical':
        return const Color(0xFFFF1744);
      case 'high':
        return const Color(0xFFFF9100);
      case 'medium':
        return const Color(
            0xFFFFB300); 
      case 'low':
        return const Color(0xFF00E676);
      default:
        return const Color(0xFF90A4AE);
    }
  }

  IconData _eventIcon(String type) {
    final t = type.toLowerCase();
    if (t.contains('explosion') || t.contains('blast')) return Icons.flash_on;
    if (t.contains('fire')) return Icons.local_fire_department;
    if (t.contains('gunshot') || t.contains('shooting')) return Icons.gps_fixed;
    if (t.contains('vehicle_crash')) return Icons.car_crash;
    if (t.contains('accident') || t.contains('crash')) return Icons.car_crash;
    if (t.contains('riot')) return Icons.groups;
    if (t.contains('fight')) return Icons.sports_mma;
    if (t.contains('evacuation')) return Icons.directions_run;
    if (t.contains('fire_alarm') || t.contains('alarm')) return Icons.campaign;
    if (t.contains('sudden_brake')) return Icons.warning_amber;
    if (t.contains('siren')) return Icons.notifications_active;
    return Icons.crisis_alert;
  }

  double _circleRadius(String accuracy) {
    switch (accuracy) {
      case 'gps':
      case 'gps_device':
        return 14;
      case 'city_level':
        return 30;
      case 'approximate':
        return 50;
      default:
        return 35;
    }
  }

  String _tileUrl(bool isDark) {
    
    final useDarkTiles = isDark || _enableDarkMapTiles;

    
    if (_mapProvider == _MapProvider.google) {
      
      final trafficSuffix = _showTraffic ? ',traffic' : '';
      switch (_mapStyle) {
        case _MapStyle.satellite:
          
          return 'https://mt1.google.com/vt/lyrs=y$trafficSuffix&x={x}&y={y}&z={z}';
        case _MapStyle.terrain:
          
          return 'https://mt1.google.com/vt/lyrs=p$trafficSuffix&x={x}&y={y}&z={z}';
        case _MapStyle.standard:
          
          if (useDarkTiles) {
            
            return 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
          }
          
          return 'https://mt1.google.com/vt/lyrs=m$trafficSuffix&x={x}&y={y}&z={z}';
      }
    }

    
    switch (_mapStyle) {
      case _MapStyle.satellite:
        return 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';
      case _MapStyle.terrain:
        
        if (useDarkTiles) {
          return 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png';
        }
        return 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png';
      case _MapStyle.standard:
        return useDarkTiles
            ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
            : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    }
  }

  List<String> _tileSubs() {
    
    if (_mapProvider == _MapProvider.google) {
      final useDarkTiles = Theme.of(context).brightness == Brightness.dark ||
          _enableDarkMapTiles;
      if (_mapStyle == _MapStyle.standard && useDarkTiles) {
        return const ['a', 'b', 'c']; 
      }
      return const [];
    }
    switch (_mapStyle) {
      case _MapStyle.satellite:
        return const [];
      case _MapStyle.terrain:
        
        final useDarkTiles = Theme.of(context).brightness == Brightness.dark ||
            _enableDarkMapTiles;
        if (useDarkTiles) {
          return const ['a', 'b', 'c'];
        }
        return const ['a', 'b', 'c'];
      case _MapStyle.standard:
        return const ['a', 'b', 'c'];
    }
  }

  String _fmtDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return '${dt.day}/${dt.month}/${dt.year}  '
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }

  
  
  
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          _buildMap(isDark),

          
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTopBar(scheme, isDark),
                  const SizedBox(height: 8),
                  _buildFilterRow(scheme, isDark),
                ],
              ),
            ),
          ),

          
          Positioned(
            top: MediaQuery.of(context).padding.top + 110,
            right: 16,
            child: Column(
              children: [
                _buildMapStyleToggle(scheme),
                const SizedBox(height: 8),
                _buildTrafficToggle(scheme),
                const SizedBox(height: 8),
                _buildMyLocationButton(scheme),
              ],
            ),
          ),

          
          if (_pickingLocation)
            Positioned(
              top: MediaQuery.of(context).padding.top + 80,
              left: 60,
              right: 60,
              child: GlassContainer(
                opacity: 0.3,
                borderRadius: BorderRadius.circular(12),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.touch_app,
                        size: 16, color: Colors.blueAccent),
                    const SizedBox(width: 6),
                    Text('Tap on the map to set your location',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface)),
                  ],
                ),
              ),
            ),

          
          if (_waypointTarget != null)
            Positioned(
              left: 16,
              right: 16,
              bottom: _selectedEvent != null ? 280 : 24,
              child: _buildWaypointBanner(scheme),
            ),

          
          if (_selectedEvent != null)
            Positioned(
              left: 16,
              right: 70,
              bottom: 24,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.38,
                ),
                child: _buildEventCard(_selectedEvent!, scheme, isDark),
              ),
            ),

          
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null && !_loading)
            Center(
              child: GlassContainer(
                opacity: 0.22,
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_off, size: 48, color: scheme.error),
                    const SizedBox(height: 12),
                    Text('Failed to load events',
                        style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(_error!,
                        style: TextStyle(
                            color: scheme.onSurface.withValues(alpha: 0.7),
                            fontSize: 12)),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                        onPressed: _fetchEvents,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: scheme.onPrimary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        )),
                  ],
                ),
              ),
            ),

          
          Positioned(
            left: 16,
            top: MediaQuery.of(context).padding.top + 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildEventsInfoTile(),
                const SizedBox(height: 8),
                _buildLegend(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  
  
  
  Widget _buildMap(bool isDark) {
    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _userLocation ?? _islamabadCenter,
        initialZoom: _defaultZoom,
        onTap: (tapPos, point) {
          if (_pickingLocation) {
            _setUserLocation(point);
            setState(() => _pickingLocation = false);
          } else {
            setState(() => _selectedEvent = null);
          }
        },
        onLongPress: _onMapLongPress,
      ),
      children: [
        
        TileLayer(
          key:
              ValueKey('tiles_${_mapProvider.name}_${_showTraffic}_$_mapStyle'),
          urlTemplate: _tileUrl(isDark),
          subdomains: _tileSubs(),
          retinaMode: true,
          userAgentPackageName: 'com.mvats.app',
        ),

        
        
        if (_showTraffic && _mapProvider == _MapProvider.osm)
          TileLayer(
            key: const ValueKey('traffic_overlay'),
            urlTemplate:
                'https://mt0.google.com/vt?lyrs=h,traffic&x={x}&y={y}&z={z}',
            retinaMode: true,
            userAgentPackageName: 'com.mvats.app',
            
            tileBuilder: (context, tileWidget, tile) {
              return Opacity(
                opacity: 0.75,
                child: tileWidget,
              );
            },
          ),

        
        if (_routePoints.isNotEmpty)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                strokeWidth: 4.5,
                color: Colors.blueAccent.withValues(alpha: 0.9),
              ),
            ],
          ),

        
        if (_userLocation != null)
          MarkerLayer(markers: [
            Marker(
              point: _userLocation!,
              width: 44,
              height: 44,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 2)
                  ],
                ),
                child: const Icon(Icons.my_location,
                    color: Colors.white, size: 20),
              ),
            ),
          ]),

        
        if (_waypointTarget != null && _userLocation == null)
          MarkerLayer(markers: [
            Marker(
              point: _islamabadCenter,
              width: 42,
              height: 42,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.blue,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2.5),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.blue.withValues(alpha: 0.5),
                        blurRadius: 12,
                        spreadRadius: 2)
                  ],
                ),
                child: const Icon(Icons.my_location,
                    color: Colors.white, size: 20),
              ),
            ),
          ]),

        
        CircleLayer(
          circles: _events.map((e) {
            final c = _severityColor(e.severity);
            return CircleMarker(
              point: LatLng(e.latitude, e.longitude),
              radius: _circleRadius(e.accuracy),
              color: c.withValues(alpha: 0.15),
              borderColor: c.withValues(alpha: 0.5),
              borderStrokeWidth: 1.5,
              useRadiusInMeter: false,
            );
          }).toList(),
        ),

        
        MarkerLayer(
          markers: _events.map((e) {
            final c = _severityColor(e.severity);
            final sel = _selectedEvent?.id == e.id;
            final wp = _waypointTarget?.id == e.id;
            final big = sel || wp;
            return Marker(
              point: LatLng(e.latitude, e.longitude),
              width: big ? 48 : 36,
              height: big ? 48 : 36,
              child: GestureDetector(
                onTap: () {
                  setState(() => _selectedEvent = e);
                  _resolveEventLocation(e); 
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: wp ? Colors.blueAccent : c,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: Colors.white, width: big ? 3 : 1.5),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (wp ? Colors.blueAccent : c).withValues(alpha: 0.6),
                        blurRadius: big ? 16 : 8,
                        spreadRadius: big ? 4 : 1,
                      )
                    ],
                  ),
                  child: Icon(
                    wp ? Icons.navigation_rounded : _eventIcon(e.eventType),
                    color: Colors.white,
                    size: big ? 22 : 16,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  
  
  
  Widget _buildTopBar(ColorScheme scheme, bool isDark) {
    return GlassContainer(
      opacity: 0.22,
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, size: 18),
              onPressed: () => Navigator.pop(context),
              tooltip: 'Back'),
          const SizedBox(width: 4),
          const Icon(Icons.map_rounded, size: 22),
          const SizedBox(width: 8),
          Expanded(
              child: Text('Event Map',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface))),
          
          _buildMapProviderToggle(scheme),
          const SizedBox(width: 4),
          
          IconButton(
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
            ),
            onPressed: () => ThemeController.instance.toggleTheme(),
            tooltip: isDark ? 'Light Mode' : 'Dark Mode',
          ),
          IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 20),
              onPressed: _fetchEvents,
              tooltip: 'Refresh'),
        ],
      ),
    );
  }

  
  
  
  Widget _buildMapProviderToggle(ColorScheme scheme) {
    final isGoogle = _mapProvider == _MapProvider.google;
    return Tooltip(
      message: isGoogle ? 'Switch to OpenStreetMap' : 'Switch to Google Maps',
      child: IconButton(
        icon: Icon(
          isGoogle ? Icons.map_rounded : Icons.public_rounded,
          color: scheme.onSurface.withValues(alpha: 0.85),
        ),
        onPressed: () {
          setState(() {
            _mapProvider = isGoogle ? _MapProvider.osm : _MapProvider.google;
          });
        },
      ),
    );
  }

  
  
  
  Widget _buildFilterRow(ColorScheme scheme, bool isDark) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: _severities.map((s) {
          final active =
              (_severityFilter == s) || (s == 'all' && _severityFilter == null);
          final color = s == 'all' ? scheme.primary : _severityColor(s);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text(s[0].toUpperCase() + s.substring(1),
                  style: TextStyle(
                      fontSize: 12,
                      color: active ? Colors.white : scheme.onSurface)),
              selected: active,
              onSelected: (_) {
                setState(() => _severityFilter = s == 'all' ? null : s);
                _fetchEvents();
              },
              selectedColor: color,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.06),
              showCheckmark: false,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18)),
            ),
          );
        }).toList(),
      ),
    );
  }

  
  
  
  Widget _buildMapStyleToggle(ColorScheme scheme) {
    return GlassContainer(
      opacity: 0.22,
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _styleBtn(Icons.map_outlined, 'Standard', _MapStyle.standard, scheme),
          const SizedBox(height: 4),
          _styleBtn(
              Icons.terrain_rounded, 'Terrain', _MapStyle.terrain, scheme),
          const SizedBox(height: 4),
          _styleBtn(
              Icons.satellite_alt, 'Satellite', _MapStyle.satellite, scheme),
        ],
      ),
    );
  }

  Widget _styleBtn(
      IconData icon, String tip, _MapStyle style, ColorScheme scheme) {
    final active = _mapStyle == style;
    return Tooltip(
      message: tip,
      child: GestureDetector(
        onTap: () => setState(() => _mapStyle = style),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: active
                ? scheme.primary.withValues(alpha: 0.25)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              size: 20,
              color: active
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.7)),
        ),
      ),
    );
  }

  
  
  
  Widget _buildTrafficToggle(ColorScheme scheme) {
    return Tooltip(
      message: _showTraffic ? 'Hide traffic' : 'Show traffic',
      child: GlassContainer(
        opacity: 0.22,
        borderRadius: BorderRadius.circular(14),
        padding: const EdgeInsets.all(6),
        child: GestureDetector(
          onTap: () => setState(() => _showTraffic = !_showTraffic),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _showTraffic
                  ? scheme.primary.withValues(alpha: 0.25)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.traffic_rounded,
              size: 20,
              color: _showTraffic
                  ? scheme.primary
                  : scheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ),
      ),
    );
  }

  
  
  
  Widget _buildMyLocationButton(ColorScheme scheme) {
    return GlassContainer(
      opacity: 0.22,
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          
          Tooltip(
            message: _pickingLocation ? 'Cancel pick' : 'Set my location',
            child: GestureDetector(
              onTap: () => setState(() => _pickingLocation = !_pickingLocation),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _pickingLocation
                      ? Colors.blueAccent.withValues(alpha: 0.25)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.add_location_alt_rounded,
                    size: 20,
                    color: _pickingLocation
                        ? Colors.blueAccent
                        : scheme.onSurface.withValues(alpha: 0.7)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          
          if (_userLocation != null)
            Tooltip(
              message: 'Go to my location',
              child: GestureDetector(
                onTap: () => _mapController.move(_userLocation!, 14),
                child: Container(
                  width: 38,
                  height: 38,
                  decoration:
                      BoxDecoration(borderRadius: BorderRadius.circular(10)),
                  child: Icon(Icons.my_location,
                      size: 20,
                      color: Colors.blueAccent.withValues(alpha: 0.9)),
                ),
              ),
            ),
          const SizedBox(height: 4),
          
          Tooltip(
            message: 'Get GPS location (precise)',
            child: GestureDetector(
              onTap: (_resolvingGpsLocation || _resolvingIpLocation)
                  ? null
                  : () async {
                      final loc = await _getGpsLocation();
                      if (loc != null && mounted) {
                        _mapController.move(loc, 15);
                      }
                    },
              child: Container(
                width: 38,
                height: 38,
                decoration:
                    BoxDecoration(borderRadius: BorderRadius.circular(10)),
                child: _resolvingGpsLocation
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.gps_fixed_rounded,
                        size: 20, color: scheme.primary.withValues(alpha: 0.9)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          
          Tooltip(
            message: 'Smart locate (GPS → IP fallback)',
            child: GestureDetector(
              onTap: (_resolvingGpsLocation || _resolvingIpLocation)
                  ? null
                  : () => _hybridLocate(),
              child: Container(
                width: 38,
                height: 38,
                decoration:
                    BoxDecoration(borderRadius: BorderRadius.circular(10)),
                child: (_resolvingGpsLocation || _resolvingIpLocation)
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Icon(Icons.explore_rounded,
                        size: 20,
                        color: Colors.deepPurple.withValues(alpha: 0.8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  
  
  
  Widget _buildWaypointBanner(ColorScheme scheme) {
    final t = _waypointTarget!;
    final dist = _routeDistKm > 0
        ? _routeDistKm
        : const Distance()
            .as(LengthUnit.Kilometer, _origin, LatLng(t.latitude, t.longitude));
    final etaMin = _routeDurationMin > 0
        ? _routeDurationMin.round()
        : (dist / 40 * 60).round();

    final jams = _trafficSegments.where((s) => s.level == 3).length;
    final slows = _trafficSegments.where((s) => s.level == 2).length;
    String tLabel;
    Color tColor;
    if (jams > 3) {
      tLabel = 'Heavy traffic';
      tColor = Colors.red;
    } else if (slows > 3) {
      tLabel = 'Moderate traffic';
      tColor = Colors.orange;
    } else {
      tLabel = 'Light traffic';
      tColor = Colors.green;
    }

    return GlassContainer(
      opacity: 0.26,
      borderRadius: BorderRadius.circular(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          
          if (_fetchingRoute)
            const SizedBox(
              width: 36,
              height: 36,
              child: Padding(
                padding: EdgeInsets.all(6),
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF7C4DFF),
                ),
              ),
            )
          else
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.navigation_rounded,
                  color: Color(0xFF7C4DFF), size: 20),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                    _fetchingRoute
                        ? 'Fetching route → ${t.eventType.replaceAll('_', ' ').toUpperCase()}'
                        : 'Navigate → ${t.eventType.replaceAll('_', ' ').toUpperCase()}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface)),
                if (!_fetchingRoute) ...[
                  const SizedBox(height: 2),
                  Text('${dist.toStringAsFixed(1)} km  •  ~$etaMin min',
                      style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withValues(alpha: 0.7))),
                  const SizedBox(height: 2),
                  Row(children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: tColor, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(tLabel,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: tColor)),
                    const Text('  •  Road route',
                        style:
                            TextStyle(fontSize: 10, color: Color(0xFF7C4DFF))),
                  ]),
                ] else ...[
                  const SizedBox(height: 2),
                  Text('Calculating road route...',
                      style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withValues(alpha: 0.6))),
                ],
              ],
            ),
          ),
          if (!_fetchingRoute)
            IconButton(
              icon: Icon(Icons.traffic,
                  color: _showTraffic
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.5),
                  size: 20),
              tooltip: _showTraffic ? 'Hide traffic' : 'Show traffic',
              onPressed: () => setState(() => _showTraffic = !_showTraffic),
            ),
          IconButton(
            icon: const Icon(Icons.close_rounded,
                size: 20, color: Colors.redAccent),
            tooltip: 'Cancel navigation',
            onPressed: _cancelWaypoint,
          ),
        ],
      ),
    );
  }

  
  
  
  Widget _buildEventCard(_MapEvent event, ColorScheme scheme, bool isDark) {
    final color = _severityColor(event.severity);
    return GlassContainer(
      opacity: 0.28,
      borderRadius: BorderRadius.circular(20),
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                  width: 40,
                  height: 40,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                  child: Icon(_eventIcon(event.eventType),
                      color: Colors.white, size: 20)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                        child: Text(
                            event.eventType.replaceAll('_', ' ').toUpperCase(),
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface))),
                    if (event.isDummy)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: Colors.purple.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(6)),
                        child: const Text('DUMMY',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.purple)),
                      ),
                  ]),
                  Text(
                      '${event.severity.toUpperCase()} severity  •  ${(event.confidence * 100).toStringAsFixed(1)}%',
                      style: TextStyle(
                          fontSize: 12,
                          color: color,
                          fontWeight: FontWeight.w600)),
                ],
              )),
              IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => setState(() => _selectedEvent = null)),
            ]),
            const SizedBox(height: 12),
            
            Builder(builder: (context) {
              final resolved = _resolvedLocations[event.id];
              final city = resolved?['city'] ?? event.city;
              final region = resolved?['region'] ?? event.region;
              final country = resolved?['country'] ?? event.country;
              final locationText = (city == 'Unknown' &&
                      _resolvingLocationIds.contains(event.id))
                  ? 'Resolving location...'
                  : '$city, $region, $country';
              return _info(Icons.location_on, locationText);
            }),
            const SizedBox(height: 4),
            _info(Icons.my_location,
                '${event.latitude.toStringAsFixed(5)}, ${event.longitude.toStringAsFixed(5)}'),
            const SizedBox(height: 4),
            
            Builder(builder: (context) {
              String ip = event.ipAddress;
              if (ip.isEmpty && event.streamUrl.isNotEmpty) {
                final uri = Uri.tryParse(event.streamUrl);
                if (uri != null && uri.host.isNotEmpty) {
                  ip = uri.host;
                }
              }
              return _info(Icons.language, 'IP: ${ip.isNotEmpty ? ip : "N/A"}');
            }),
            const SizedBox(height: 4),
            _info(
                Icons.access_time,
                event.createdAt.isNotEmpty
                    ? _fmtDate(event.createdAt)
                    : 'Unknown'),
            const SizedBox(height: 4),
            _info(Icons.radar, 'Accuracy: ${event.accuracy}'),
            if (event.predictedClass.isNotEmpty) ...[
              const SizedBox(height: 4),
              _info(Icons.category, 'Scene: ${event.predictedClass}'),
            ],
            const SizedBox(height: 12),
            
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: color.withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ]),
                  child: Text(event.status.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ),
                
                _HoverPill(
                  onTap: () => _neutralizeEvent(event),
                  icon: Icons.verified_rounded,
                  label: 'Neutralize',
                  color: Colors.green,
                ),
                
                _HoverPill(
                  onTap: () => _startWaypointNavigation(event),
                  icon: Icons.navigation_rounded,
                  label: 'Navigate',
                  color: Colors.blueAccent,
                ),
                
                _HoverPill(
                  onTap: () => _mapController.move(
                      LatLng(event.latitude, event.longitude), 14),
                  icon: Icons.center_focus_strong,
                  label: 'Focus',
                  color: const Color(0xFF607D8B),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Row(children: [
      Icon(icon, size: 14, color: scheme.onSurface.withValues(alpha: 0.6)),
      const SizedBox(width: 8),
      Expanded(
          child: Text(text,
              style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurface.withValues(alpha: 0.85)),
              overflow: TextOverflow.ellipsis)),
    ]);
  }

  
  
  
  Widget _buildLegend() {
    final scheme = Theme.of(context).colorScheme;
    return GlassContainer(
      opacity: 0.22,
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Severity',
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface)),
          const SizedBox(height: 6),
          _dot('Critical', const Color(0xFFFF1744)),
          _dot('High', const Color(0xFFFF9100)),
          _dot('Medium', const Color(0xFFFFB300)),
          _dot('Low', const Color(0xFF00E676)),
          if (_waypointTarget != null) ...[
            const SizedBox(height: 8),
            Text('Traffic',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface)),
            const SizedBox(height: 4),
            _dot('Free', Colors.green),
            _dot('Moderate', Colors.yellow),
            _dot('Slow', Colors.orange),
            _dot('Jam', Colors.red),
          ],
        ],
      ),
    );
  }

  Widget _dot(String label, Color color) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 10, color: scheme.onSurface.withValues(alpha: 0.8))),
      ]),
    );
  }

  
  
  
  Widget _buildEventsInfoTile() {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    
    int critical = 0, high = 0, medium = 0, low = 0;
    String? mostSevereType;
    int mostSevereSeverity = 0;

    for (final event in _events) {
      final sev = event.severity.toLowerCase();
      if (sev == 'critical') {
        critical++;
        if (mostSevereSeverity < 4) {
          mostSevereSeverity = 4;
          mostSevereType = event.eventType;
        }
      } else if (sev == 'high') {
        high++;
        if (mostSevereSeverity < 3) {
          mostSevereSeverity = 3;
          mostSevereType = event.eventType;
        }
      } else if (sev == 'medium') {
        medium++;
        if (mostSevereSeverity < 2) {
          mostSevereSeverity = 2;
          mostSevereType = event.eventType;
        }
      } else {
        low++;
        if (mostSevereSeverity < 1) {
          mostSevereSeverity = 1;
          mostSevereType = event.eventType;
        }
      }
    }

    final mostSevereColor = mostSevereSeverity == 4
        ? const Color(0xFFFF1744)
        : mostSevereSeverity == 3
            ? const Color(0xFFFF9100)
            : mostSevereSeverity == 2
                ? const Color(0xFFFFB300)
                : const Color(0xFF00E676);

    return GlassContainer(
      opacity: 0.22,
      borderRadius: BorderRadius.circular(14),
      padding: const EdgeInsets.all(14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.warning_amber_rounded,
                  size: 18, color: scheme.primary),
              const SizedBox(width: 6),
              Text('Events',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('${_events.length} TOTAL',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white)),
          ),
          const SizedBox(height: 10),
          
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (critical > 0)
                _miniStatSolid('$critical CRITICAL', const Color(0xFFFF1744)),
              if (high > 0)
                _miniStatSolid('$high HIGH', const Color(0xFFFF9100)),
              if (medium > 0)
                _miniStatSolid('$medium MEDIUM', const Color(0xFFFFB300)),
              if (low > 0) _miniStatSolid('$low LOW', const Color(0xFF00E676)),
            ],
          ),
          if (mostSevereType != null) ...[
            const SizedBox(height: 6),
            const SizedBox(height: 8),
            Text('Most Severe',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface.withValues(alpha: 0.7))),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: mostSevereColor,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: mostSevereColor.withValues(alpha: 0.4),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.priority_high_rounded,
                      size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    mostSevereType.replaceAll('_', ' ').toUpperCase(),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniStatSolid(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.4),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
      ),
    );
  }
}





enum _MapStyle { standard, terrain, satellite }

enum _MapProvider { osm, google }

class _TrafficSegment {
  final LatLng from;
  final LatLng to;
  final int level; 

  _TrafficSegment({required this.from, required this.to, required this.level});

  Color get color {
    switch (level) {
      case 0:
        return Colors.green;
      case 1:
        return Colors.yellow;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}

class _MapEvent {
  final String id;
  final String eventType;
  final String severity;
  final String predictedClass;
  final double confidence;
  final String status;
  final double latitude;
  final double longitude;
  final String city;
  final String region;
  final String country;
  final String accuracy;
  final String ipAddress;
  final String streamUrl;
  final String createdAt;
  final bool isDummy;

  _MapEvent({
    required this.id,
    required this.eventType,
    required this.severity,
    required this.predictedClass,
    required this.confidence,
    required this.status,
    required this.latitude,
    required this.longitude,
    required this.city,
    required this.region,
    required this.country,
    required this.accuracy,
    required this.ipAddress,
    this.streamUrl = '',
    required this.createdAt,
    this.isDummy = false,
  });
}


class _HoverPill extends StatefulWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final Color color;

  const _HoverPill({
    required this.onTap,
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  State<_HoverPill> createState() => _HoverPillState();
}

class _HoverPillState extends State<_HoverPill> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final double scale = _pressed
        ? 0.93
        : _hovered
            ? 1.07
            : 1.0;
    final double brightness = _pressed
        ? 0.8
        : _hovered
            ? 1.1
            : 1.0;

    
    final bgColor = HSLColor.fromColor(widget.color)
        .withLightness((HSLColor.fromColor(widget.color).lightness * brightness)
            .clamp(0.0, 1.0))
        .toColor();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) {
          setState(() => _pressed = false);
          widget.onTap();
        },
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: scale,
          duration: const Duration(milliseconds: 120),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: widget.color.withValues(alpha: 0.4),
                  blurRadius: _hovered ? 6 : 3,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 14, color: Colors.white),
                const SizedBox(width: 5),
                Text(
                  widget.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
