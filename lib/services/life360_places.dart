// life360_places.dart
//
// Feature 1: Saved Places (Home / School / College / Gym / custom).
//
// Dependencies (pubspec.yaml), on top of what you already have:
//   geocoding: ^3.0.0   // address -> lat/lng search

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';

import '../core/data/user_profile_provider.dart';

// ---------------------------------------------------------------------------
// MODEL
// ---------------------------------------------------------------------------

enum PlaceIcon { home, school, college, gym, custom }

class SavedPlace {
  final String id;
  final String label;
  final PlaceIcon icon;
  final String? address;
  final double latitude;
  final double longitude;
  final double radiusM;

  const SavedPlace({
    required this.id,
    required this.label,
    required this.icon,
    required this.latitude,
    required this.longitude,
    required this.radiusM,
    this.address,
  });

  LatLng get position => LatLng(latitude, longitude);

  IconData get iconData {
    switch (icon) {
      case PlaceIcon.home:
        return Icons.home;
      case PlaceIcon.school:
        return Icons.school;
      case PlaceIcon.college:
        return Icons.account_balance;
      case PlaceIcon.gym:
        return Icons.fitness_center;
      case PlaceIcon.custom:
        return Icons.place;
    }
  }

  factory SavedPlace.fromRow(Map<String, dynamic> row) => SavedPlace(
    id: row['id'] as String,
    label: row['label'] as String,
    icon: PlaceIcon.values.firstWhere(
      (e) => e.name == row['icon'],
      orElse: () => PlaceIcon.custom,
    ),
    address: row['address'] as String?,
    latitude: (row['latitude'] as num).toDouble(),
    longitude: (row['longitude'] as num).toDouble(),
    radiusM: (row['radius_m'] as num?)?.toDouble() ?? 150,
  );
}

// ---------------------------------------------------------------------------
// REPOSITORY
// ---------------------------------------------------------------------------

class PlacesRepository {
  PlacesRepository(this._supabase);

  final SupabaseClient _supabase;

  // Future<List<SavedPlace>> fetchPlaces(
  //   String familyId, {
  //   String? userId,
  // }) async {
  //   final rows = await _supabase
  //       .from('saved_places')
  //       .select()
  //       .eq('family_id', familyId)
  //       .order('created_at');
  //   return rows.map((r) => SavedPlace.fromRow(r)).toList();
  // }
  Future<List<SavedPlace>> fetchPlaces(
    String familyId, {
    String? userId, // new
  }) async {
    var query = _supabase
        .from('saved_places')
        .select()
        .eq('family_id', familyId);

    if (userId != null) {
      query = query.eq('created_by', userId);
    }

    final rows = await query.order('created_at');
    return rows.map((r) => SavedPlace.fromRow(r)).toList();
  }

  Future<void> addPlace({
    required String familyId,
    required String label,
    required PlaceIcon icon,
    required double latitude,
    required double longitude,
    String? address,
    double radiusM = 150,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    await _supabase.from('saved_places').insert({
      'family_id': familyId,
      'created_by': userId,
      'label': label,
      'icon': icon.name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'radius_m': radiusM,
    });
  }

  Future<bool> deletePlace(BuildContext context, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'Delete Saved Place?',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        content: const Text(
          'Are you sure you want to delete this saved place?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    try {
      await _supabase
          .from('saved_location_presence')
          .delete()
          .eq('saved_place_id', id);

      await _supabase.from('saved_places').delete().eq('id', id);

      return true;
    } catch (e) {
      debugPrint('Delete place failed: $e');
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// LIST SCREEN
// ---------------------------------------------------------------------------

class PlacesListScreen extends StatefulWidget {
  const PlacesListScreen({
    super.key,
    required this.familyId,
    required this.showAllMembers,
    required this.repository,
  });

  final String familyId;
  final bool showAllMembers;
  final PlacesRepository repository;

  @override
  State<PlacesListScreen> createState() => _PlacesListScreenState();
}

class _PlacesListScreenState extends State<PlacesListScreen> {
  List<SavedPlace> _places = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final places = await widget.repository.fetchPlaces(
      widget.familyId,
      userId: widget.showAllMembers ? null : userId,
    );
    setState(() {
      _places = places;
      _loading = false;
    });
  }

  Future<void> _openAddPlace() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddPlaceScreen(
          familyId: widget.familyId,
          showAllMembers: widget.showAllMembers,
          repository: widget.repository,
        ),
      ),
    );
    if (added == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 2,
        backgroundColor: Colors.white,
        shadowColor: Colors.grey.shade200,
        titleSpacing: 0,
        title: const Text('Saved Places', style: TextStyle(fontSize: 20)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddPlace,
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _places.isEmpty
          ? const Center(child: Text('No saved places yet'))
          : ListView.builder(
              itemCount: _places.length,
              itemBuilder: (context, i) {
                final p = _places[i];
                return ListTile(
                  leading: CircleAvatar(child: Icon(p.iconData)),
                  title: Text(p.label),
                  subtitle: Text(p.address ?? '${p.latitude}, ${p.longitude}'),
                  trailing: GestureDetector(
                    onTap: () async {
                      final deleted = await widget.repository.deletePlace(
                        context,
                        p.id,
                      );

                      if (deleted == true && mounted) {
                        await _load();
                      }
                    },
                    child: Container(
                      padding: EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        boxShadow: [
                          BoxShadow(color: Colors.grey.shade300, blurRadius: 5),
                        ],
                        //   borderRadius: BorderRadius.circular(12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.delete,
                        color: Colors.red,
                        size: 16,
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// ADD PLACE SCREEN (search + map pin picker)
// ---------------------------------------------------------------------------

class AddPlaceScreen extends ConsumerStatefulWidget {
  const AddPlaceScreen({
    super.key,
    required this.familyId,
    required this.showAllMembers,
    required this.repository,
  });

  final String familyId;
  final bool showAllMembers;
  final PlacesRepository repository;

  @override
  ConsumerState<AddPlaceScreen> createState() => _AddPlaceScreenState();
}

class _AddPlaceScreenState extends ConsumerState<AddPlaceScreen> {
  final _labelController = TextEditingController();
  final _searchController = TextEditingController();
  PlaceIcon _icon = PlaceIcon.custom;
  LatLng _pin = const LatLng(9.9252, 78.1198); // default: Madurai
  String? _resolvedAddress;
  GoogleMapController? _mapController;
  bool _saving = false;
  final Geocoding _geocoding = Geocoding();

  static const _presets = [
    (PlaceIcon.home, 'Home'),
    (PlaceIcon.school, 'School'),
    (PlaceIcon.college, 'College'),
    (PlaceIcon.gym, 'Gym'),
  ];

  Future<void> _searchAddress(String query) async {
    if (query.trim().isEmpty) return;
    try {
      final results = await _geocoding.locationFromAddress(query);

      if (results.isEmpty) return;
      final loc = results.first;
      final newPin = LatLng(loc.latitude, loc.longitude);
      setState(() {
        _pin = newPin;
        _resolvedAddress = query;
      });
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(newPin, 16));
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Address not found')));
      }
    }
  }

  Future<void> _save() async {
    if (_labelController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please enter label name")));
      return;
    }

    setState(() => _saving = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;

      final existingPlaces = await widget.repository.fetchPlaces(
        widget.familyId,
        userId: widget.showAllMembers ? null : userId,
      );
      final newLabel = _labelController.text.trim().toLowerCase();
      final alreadyExists = existingPlaces.any(
        (p) => p.label.trim().toLowerCase() == newLabel,
      );

      if (alreadyExists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '"${_labelController.text.trim()}" already exists. Use a different label.',
              ),
            ),
          );
        }
        return; // finally{} resets _saving
      }

      String address = '';

      try {
        final geocodingPlace = Geocoding();
        // 1. Call via top-level function directly rather than creating local instances
        final placemarks = await geocodingPlace.placemarkFromCoordinates(
          _pin.latitude,
          _pin.longitude,
        );

        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          address =
              [
                    place.name,
                    place.subLocality,
                    place.locality,
                    place.administrativeArea,
                    place.postalCode,
                    place.country,
                  ]
                  .where((value) => value != null && value.trim().isNotEmpty)
                  .toSet()
                  .join(', ');
        }
      } on PlatformException catch (e) {
        // 2. Catch the internal platform channel teardown safely
        print("Geocoding platform channel exception caught: ${e.message}");
      } catch (e) {
        print("General geocoding exception: $e");
      }

      // Save place with resolved address
      await widget.repository.addPlace(
        familyId: widget.familyId,
        label: _labelController.text.trim(),
        icon: _icon,
        latitude: _pin.latitude,
        longitude: _pin.longitude,
        address: address.isNotEmpty ? address : _resolvedAddress,
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved successfully')));
      }

      final members = await Supabase.instance.client
          .from('family_members')
          .select('user_id, role')
          .eq('family_id', widget.familyId);

      // Run push notifications for all relevant family members completely
      for (final m in members) {
        final targetUserId = m['user_id'];

        if (targetUserId == userId ||
            (m['role'] != "leader" && m['role'] != "monitor")) {
          continue;
        }
        try {
          final profile = await ref.read(currentUserProfileProvider.future);
          if (profile == null) throw Exception('No profile');

          await Supabase.instance.client.functions.invoke(
            'push-router',
            body: {
              "target_user_id": targetUserId,
              "title": "${profile.fullName} Saved location",
              "body": "called $address",
              "action": "check_in",
            },
          );
        } catch (e) {
          print("Push failed: $e");
        }
      }

      // 3. FIX: Pop the screen only AFTER the loop finishes executing its async calls
      if (mounted) {
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Failed to save place')));
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _openSavedPlaces() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => PlacesListScreen(
          familyId: widget.familyId,
          showAllMembers: widget.showAllMembers,
          repository: widget.repository,
        ),
      ),
    );

    if (result == true && mounted) {
      final saved = await widget.repository.fetchPlaces(widget.familyId);

      setState(() {
        // _savedPlaces = saved;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        elevation: 3,
        shadowColor: Colors.grey.shade300,
        title: const Text('Save place', style: TextStyle(fontSize: 20)),
        actions: [
          GestureDetector(
            onTap: _openSavedPlaces,
            child: Icon(Icons.bookmark_add_rounded),
          ),
          GestureDetector(
            onTap: _saving ? null : _save,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: EdgeInsets.symmetric(horizontal: 12, vertical: 0),

              //  alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ShieldColors.activeTeal,
                // border: Border.all(color: ShieldColors.activeTeal),
                borderRadius: BorderRadius.circular(12),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          //
          // Padding(
          //   padding: const EdgeInsets.all(12),
          //   child: TextField(
          //     controller: _searchController,
          //     decoration: InputDecoration(
          //       hintText: 'Search address...',
          //       prefixIcon: const Icon(Icons.search),
          //       border: OutlineInputBorder(
          //         borderRadius: BorderRadius.circular(12),
          //       ),
          //     ),
          //     onSubmitted: _searchAddress,
          //   ),
          // ),
          // Expanded(
          //   child: Stack(
          //     alignment: Alignment.center,
          //     children: [
          //       GoogleMap(
          //         initialCameraPosition: CameraPosition(target: _pin, zoom: 14),
          //         onMapCreated: (c) => _mapController = c,
          //         onCameraMove: (pos) => _pin = pos.target,
          //         onCameraIdle: () => setState(() {}),
          //       ),
          //       const Icon(Icons.location_pin, size: 44, color: Colors.red),
          //     ],
          //   ),
          // ),
          Expanded(
            child: Stack(
              alignment: Alignment.center,
              children: [
                GoogleMap(
                  initialCameraPosition: CameraPosition(target: _pin, zoom: 16),
                  onMapCreated: (c) => _mapController = c,
                  onCameraMove: (pos) => _pin = pos.target,
                  onCameraIdle: () => setState(() {}),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: true,
                  zoomControlsEnabled: false,
                ),

                // Pin: the tip points at the exact map center.
                Transform.translate(
                  offset: const Offset(0, -22),
                  child: const Icon(
                    Icons.location_pin,
                    size: 44,
                    color: Colors.red,
                    shadows: [Shadow(color: Colors.black38, blurRadius: 6)],
                  ),
                ),

                // Hint bubble at the top.
                Positioned(
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Move the map to place the pin',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  children: _presets.map((preset) {
                    final selected = _icon == preset.$1;
                    return ChoiceChip(
                      label: Text(preset.$2),
                      selected: selected,
                      onSelected: (_) {
                        setState(() {
                          _icon = preset.$1;
                          _labelController.text = preset.$2;
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _labelController,
                  decoration: InputDecoration(
                    labelText: 'Label',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: (_) => setState(() => _icon = PlaceIcon.custom),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
