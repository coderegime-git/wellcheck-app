// life360_checkin.dart
//
// Check-In feature, matching Life360's actual Check In screen:
//   - Search bar for any address/location name (Google Places Autocomplete)
//   - "Nearby places" list combining the user's saved places (Home, work, etc.)
//     with live nearby results from Google Places
//   - Tapping any result inserts a check_ins row and closes the screen
//
// Dependencies (pubspec.yaml), on top of what you already have:
//   http: ^1.2.0
//
// Requires a Google Places API key with "Places API" enabled in Cloud
// Console (separate toggle from Maps SDK for Android/iOS — same project,
// different API). You can reuse the same API key as Maps as long as this
// API is enabled for it and its restrictions allow it.
//
// Requires: life360_places.dart (SavedPlace, PlacesRepository)

import 'dart:async';
import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';

import '../main.dart';
import 'life360_places.dart'
    show SavedPlace, PlacesRepository, PlacesListScreen;

// ---------------------------------------------------------------------------
// CHECK-IN SERVICE (insert into check_ins)
// ---------------------------------------------------------------------------

class CheckInService {
  CheckInService(this._supabase);

  final SupabaseClient _supabase;

  Future<void> checkIn({
    required String familyId,
    required double latitude,
    required double longitude,
    String statusMessage = 'Manual check-in',
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    int level = 100;
    // Safe default for simulators and aggressive background iOS policies
    try {
      final battery = Battery();
      level = await battery.batteryLevel;
    } catch (e) {
      debugPrint('Battery info not available over isolate, using default: $e');
    }
    final prefs = await SharedPreferences.getInstance();
    final userName = prefs.getString('last_user_name') ?? '';
    final persistentUserRole = prefs.getString('last_user_role');

    await logWellEvent(Supabase.instance.client, {
      'family_id': familyId,
      'user_id': userId,
      'user_name': userName,
      'event_type': 'check_in',
      'title': 'Status Check-In',
      'description': 'checked in.',
      'latitude': latitude,
      'longitude': longitude,
      'battery_level': level, // Platform battery TBD
      // 'created_by': profile.userId,
    });
    await _supabase.from('check_ins').insert({
      'family_id': familyId,
      'user_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'status_message': statusMessage,
    });
    final response =
        await Supabase.instance.client.from('live_locations').upsert({
          'user_id': userId,
          'family_id': familyId,
          'user_name': userName,
          'role': persistentUserRole,
          'latitude': latitude,
          'longitude': longitude,
          'battery_level': level,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id').select();
    final members = await Supabase.instance.client
        .from('family_members')
        .select('user_id, role')
        .eq('family_id', familyId);

    for (final m in members) {
      final targetUserId = m['user_id'];

      if (targetUserId == userId ||
          (m['role'] != "leader" && m['role'] != "monitor")) {
        continue;
      }
      try {
        final prefs = await SharedPreferences.getInstance();
        final userName = prefs.getString('last_user_name') ?? '';
        await Supabase.instance.client.functions.invoke(
          'push-router',
          body: {
            "target_user_id": targetUserId,
            "title": "Check-In",
            "body": "$userName $statusMessage",
            "action": "check_in",
          },
        );
      } catch (e) {
        print("Push failed: $e");
      } //
    }
  }
}

// ---------------------------------------------------------------------------
// GOOGLE PLACES SEARCH (autocomplete + nearby, no extra plugin needed)
// ---------------------------------------------------------------------------

class PlaceSearchResult {
  final String name;
  final String? address;
  final String placeId;

  const PlaceSearchResult({
    required this.name,
    required this.placeId,
    this.address,
  });
}

class GooglePlacesSearch {
  GooglePlacesSearch(this._apiKey);

  final String _apiKey;

  /// Text search — used both for typed queries and for the default
  /// "nearby places" list (biased to the given lat/lng, empty query).
  // Future<List<PlaceSearchResult>> search(
  //   String query, {
  //   double? lat,
  //   double? lng,
  // }) async {
  //   final uri =
  //       Uri.https('maps.googleapis.com', '/maps/api/place/textsearch/json', {
  //         'query': query.isEmpty ? 'places near me' : query,
  //         if (lat != null && lng != null) 'location': '$lat,$lng',
  //         if (lat != null && lng != null) 'radius': '3000',
  //         'key': _apiKey,
  //       });
  //   final res = await http.get(uri);
  //   if (res.statusCode != 200) return [];
  //   final data = jsonDecode(res.body) as Map<String, dynamic>;
  //   final results = (data['results'] as List?) ?? [];
  //   return results
  //       .map(
  //         (r) => PlaceSearchResult(
  //           name: r['name'] as String? ?? '',
  //           address: r['formatted_address'] as String?,
  //           placeId: r['place_id'] as String? ?? '',
  //         ),
  //       )
  //       .toList();
  // }
  Future<List<PlaceSearchResult>> search(
    String query, {
    double? lat,
    double? lng,
  }) async {
    final uri =
        Uri.https('maps.googleapis.com', '/maps/api/place/textsearch/json', {
          'query': query.trim().isEmpty ? 'places' : query.trim(),
          if (lat != null && lng != null) 'location': '$lat,$lng',
          if (lat != null && lng != null) 'radius': '300',
          'key': _apiKey,
        });

    debugPrint('PLACES URL: $uri');

    try {
      final res = await http.get(uri);

      debugPrint('PLACES HTTP STATUS: ${res.statusCode}');
      debugPrint('PLACES RESPONSE: ${res.body}');

      if (res.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;

      final apiStatus = data['status'];
      debugPrint('PLACES API STATUS: $apiStatus');

      if (apiStatus != 'OK' && apiStatus != 'ZERO_RESULTS') {
        debugPrint('PLACES API ERROR: ${data['error_message']}');
        return [];
      }

      final results = (data['results'] as List?) ?? [];

      return results.map((r) {
        final map = r as Map<String, dynamic>;

        return PlaceSearchResult(
          name: map['name'] as String? ?? '',
          address: map['formatted_address'] as String?,
          placeId: map['place_id'] as String? ?? '',
        );
      }).toList();
    } catch (e) {
      debugPrint('PLACES SEARCH EXCEPTION: $e');
      return [];
    }
  }

  /// Resolves a place_id (from a search result) into lat/lng for check-in.
  Future<({double lat, double lng})?> resolveLatLng(String placeId) async {
    final uri = Uri.https(
      'maps.googleapis.com',
      '/maps/api/place/details/json',
      {'place_id': placeId, 'fields': 'geometry', 'key': _apiKey},
    );
    final res = await http.get(uri);
    if (res.statusCode != 200) return null;
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final loc = data['result']?['geometry']?['location'];
    if (loc == null) return null;
    return (
      lat: (loc['lat'] as num).toDouble(),
      lng: (loc['lng'] as num).toDouble(),
    );
  }
}

// ---------------------------------------------------------------------------
// CHECK-IN SCREEN
// ---------------------------------------------------------------------------

class CheckInScreen extends StatefulWidget {
  const CheckInScreen({
    super.key,
    required this.familyId,
    required this.showAllMembers,
    required this.placesRepository,
    required this.checkInService,
    required this.placesSearch,
    this.currentLat,
    this.currentLng,
  });

  final String familyId;
  final bool showAllMembers;
  final PlacesRepository placesRepository;
  final CheckInService checkInService;
  final GooglePlacesSearch placesSearch;

  /// Used to bias "nearby" results — pass the member's current position.
  final double? currentLat;
  final double? currentLng;

  @override
  State<CheckInScreen> createState() => _CheckInScreenState();
}

class _CheckInScreenState extends State<CheckInScreen> {
  final _searchController = TextEditingController();
  List<SavedPlace> _savedPlaces = [];
  List<PlaceSearchResult> _searchResults = [];
  bool _loading = true;
  bool _checkingIn = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final saved = await widget.placesRepository.fetchPlaces(
      widget.familyId,
      userId: widget.showAllMembers ? null : userId,
    );
    final nearby = await widget.placesSearch.search(
      '',
      lat: widget.currentLat,
      lng: widget.currentLng,
    );
    if (!mounted) return;
    setState(() {
      _savedPlaces = saved;
      _searchResults = nearby;
      _loading = false;
    });
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      setState(() => _loading = true);
      final results = await widget.placesSearch.search(
        query,
        lat: widget.currentLat,
        lng: widget.currentLng,
      );
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        _loading = false;
      });
    });
  }

  Future<void> _checkInAtSavedPlace(SavedPlace place) async {
    setState(() => _checkingIn = true);
    await widget.checkInService.checkIn(
      familyId: widget.familyId,
      latitude: place.latitude,
      longitude: place.longitude,
      statusMessage: 'Checked in at ${place.label}',
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _checkInAtSearchResult(PlaceSearchResult result) async {
    setState(() => _checkingIn = true);
    final latLng = await widget.placesSearch.resolveLatLng(result.placeId);
    if (latLng == null) {
      setState(() => _checkingIn = false);
      return;
    }

    await widget.checkInService.checkIn(
      familyId: widget.familyId,
      latitude: latLng.lat,
      longitude: latLng.lng,
      statusMessage: 'Checked in at ${result.name}',
    );
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _openSavedPlaces() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PlacesListScreen(
          familyId: widget.familyId,
          showAllMembers: widget.showAllMembers,
          repository: widget.placesRepository,
        ),
      ),
    );

    if (result == true && mounted) {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      final saved = await widget.placesRepository.fetchPlaces(
        widget.familyId,
        userId: widget.showAllMembers ? null : userId,
      );

      setState(() {
        _savedPlaces = saved;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showingSearch = _searchController.text.trim().isNotEmpty;

    return GestureDetector(
      onTap: () {
        FocusManager.instance.primaryFocus?.unfocus();
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              // Header: X close + title, matching Life360's layout.
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: _checkingIn ? null : () => Navigator.pop(context),
                      child: Container(
                        padding: EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.grey.shade700,
                              //offset: Offset(0, 04),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(Icons.close, size: 16),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Check In',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge,
                      ),
                    ),
                    GestureDetector(
                      onTap: _checkingIn ? null : _openSavedPlaces,
                      child: const Icon(
                        Icons.bookmark_add_outlined,
                        color: ShieldColors.activeTeal,
                        size: 20,
                      ),
                    ),
                    //  const SizedBox(width: 48), // balances the close button
                  ],
                ),
              ),

              // Search field.
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search address or location name',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(15)),
                    ),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
              const SizedBox(height: 10),

              if (_checkingIn) const LinearProgressIndicator(minHeight: 2),

              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : ListView(
                        children: [
                          if (!showingSearch) ...[
                            Container(
                              width: double.infinity,
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.4),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Text(
                                'Nearby places',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: theme.hintColor,
                                ),
                              ),
                            ),
                            // Saved places first — no address subtitle, like
                            // "HIL Technologies" / "Home" in the reference UI.
                            ..._savedPlaces.map(
                              (p) => ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: ShieldColors.activeTeal
                                      .withValues(alpha: 0.12),
                                  child: Icon(
                                    p.iconData,
                                    color: ShieldColors.activeTeal,
                                    size: 20,
                                  ),
                                ),
                                title: Text(
                                  p.label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                onTap: _checkingIn
                                    ? null
                                    : () => _checkInAtSavedPlace(p),
                              ),
                            ),
                          ],
                          // Nearby / search results — with address subtitle.
                          ..._searchResults.map(
                            (r) => ListTile(
                              leading: CircleAvatar(
                                backgroundColor: ShieldColors.activeTeal
                                    .withValues(alpha: 0.12),
                                child: const Icon(
                                  Icons.location_pin,
                                  color: ShieldColors.activeTeal,
                                  size: 20,
                                ),
                              ),
                              title: Text(
                                r.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: r.address != null
                                  ? Text(r.address!)
                                  : null,
                              onTap: _checkingIn
                                  ? null
                                  : () => _checkInAtSearchResult(r),
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

//
