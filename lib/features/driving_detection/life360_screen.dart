// // life360_map_screen.dart
// //
// // A Life360-style "family/group map" screen for Flutter.
// //
// // Shows:
// //  - Google Map with a marker per member (colored avatar-style pin)
// //  - Draggable bottom sheet with member details: speed, address,
// //    last updated, battery %, driving/stopped status
// //  - Horizontal member chip list at the top to quickly jump to a member
// //  - Recenter / "show all members" FAB
// //
// // Dependencies (add to pubspec.yaml):
// //   google_maps_flutter: ^2.9.0
// //   geocoding: ^3.0.0         // for reverse-geocoding lat/lng -> address (optional)
// //   intl: ^0.19.0             // for "last updated" time formatting
// //
// // Wire `MemberLocation` up to your own realtime source (Supabase Realtime,
// // Firebase, socket, polling API, etc.) — just push updated MemberLocation
// // objects into `onMembersChanged` / update `_members` and call setState,
// // or convert `_members` to a Stream/ValueNotifier if you prefer.
//
// import 'dart:async';
// import 'dart:io';
// import 'dart:math' as math;
//
// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:intl/intl.dart';
// import 'dart:math' as math;
//
// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:intl/intl.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:supabase_flutter/supabase_flutter.dart';
// import 'package:well_check_v3/core/design/shield_theme.dart';
// import 'package:well_check_v3/features/driving_detection/weekly_stats_driving.dart';
//
// import '../../services/check_in_service.dart';
// import '../../services/life360_places.dart';
//
// // import 'life360_map_screen.dart';
// // import 'life360_places.dart' ;
// // ---------------------------------------------------------------------------
// // MODEL
// // ---------------------------------------------------------------------------
//
// enum MovementStatus { stopped, walking, driving, unknown }
//
// class MemberLocation {
//   final String id;
//   final String name;
//   final String? avatarUrl;
//   final Color color;
//   final double latitude;
//   final double longitude;
//   final double speedKmh; // current speed in km/h
//   final double? headingDegrees; // 0-360, for rotating the marker
//   final double? batteryPercent; // 0-100
//   final DateTime lastUpdated;
//   final String? address; // pre-resolved address, if you have one
//   final MovementStatus status;
//
//   const MemberLocation({
//     required this.id,
//     required this.name,
//     required this.latitude,
//     required this.longitude,
//     required this.speedKmh,
//     required this.lastUpdated,
//     this.avatarUrl,
//     this.color = Colors.blue,
//     this.headingDegrees,
//     this.batteryPercent,
//     this.address,
//     this.status = MovementStatus.unknown,
//   });
//
//   LatLng get position => LatLng(latitude, longitude);
//
//   MovementStatus get effectiveStatus {
//     if (status != MovementStatus.unknown) return status;
//     if (speedKmh < 1) return MovementStatus.stopped;
//     if (speedKmh < 8) return MovementStatus.walking;
//     return MovementStatus.driving;
//   }
// }
//
// // ---------------------------------------------------------------------------
// // SCREEN
// // ---------------------------------------------------------------------------
//
// class Life360MapScreen extends StatefulWidget {
//   const Life360MapScreen({
//     super.key,
//     required this.members,
//     this.onRefresh,
//     this.speedUnitKmh = true,
//   });
//
//   /// Current members to plot on the map. Pass an updated list (e.g. from a
//   /// realtime stream) and this widget will animate/update markers.
//   final List<MemberLocation> members;
//
//   /// Called when the user pulls to refresh / taps the refresh action.
//   final Future<void> Function()? onRefresh;
//
//   /// true = show speed in km/h, false = show mph.
//   final bool speedUnitKmh;
//
//   @override
//   State<Life360MapScreen> createState() => _Life360MapScreenState();
// }
//
// class _Life360MapScreenState extends State<Life360MapScreen> {
//   GoogleMapController? _mapController;
//   String? _selectedMemberId;
//   final DraggableScrollableController _sheetController =
//       DraggableScrollableController();
//
//   @override
//   void didUpdateWidget(covariant Life360MapScreen oldWidget) {
//     super.didUpdateWidget(oldWidget);
//     // Keep selection valid if a member disappears from the list.
//     if (_selectedMemberId != null &&
//         widget.members.every((m) => m.id != _selectedMemberId)) {
//       _selectedMemberId = widget.members.isNotEmpty
//           ? widget.members.first.id
//           : null;
//     } else if (_selectedMemberId == null && widget.members.isNotEmpty) {
//       _selectedMemberId = widget.members.first.id;
//     }
//   }
//
//   @override
//   void initState() {
//     super.initState();
//     if (widget.members.isNotEmpty) {
//       _selectedMemberId = widget.members.first.id;
//     }
//   }
//
//   MemberLocation? get _selectedMember {
//     if (_selectedMemberId == null) return null;
//     try {
//       return widget.members.firstWhere((m) => m.id == _selectedMemberId);
//     } catch (_) {
//       return null;
//     }
//   }
//
//   Future<void> _focusMember(MemberLocation member, {double zoom = 16}) async {
//     setState(() => _selectedMemberId = member.id);
//     await _mapController?.animateCamera(
//       CameraUpdate.newLatLngZoom(member.position, zoom),
//     );
//     _sheetController.animateTo(
//       0.32,
//       duration: const Duration(milliseconds: 250),
//       curve: Curves.easeOut,
//     );
//   }
//
//   Future<void> _fitAllMembers() async {
//     if (widget.members.isEmpty || _mapController == null) return;
//     if (widget.members.length == 1) {
//       await _focusMember(widget.members.first);
//       return;
//     }
//     double minLat = widget.members.first.latitude;
//     double maxLat = widget.members.first.latitude;
//     double minLng = widget.members.first.longitude;
//     double maxLng = widget.members.first.longitude;
//     for (final m in widget.members) {
//       minLat = math.min(minLat, m.latitude);
//       maxLat = math.max(maxLat, m.latitude);
//       minLng = math.min(minLng, m.longitude);
//       maxLng = math.max(maxLng, m.longitude);
//     }
//     await _mapController!.animateCamera(
//       CameraUpdate.newLatLngBounds(
//         LatLngBounds(
//           southwest: LatLng(minLat, minLng),
//           northeast: LatLng(maxLat, maxLng),
//         ),
//         60,
//       ),
//     );
//   }
//
//   Set<Marker> _buildMarkers() {
//     return widget.members.map((m) {
//       final isSelected = m.id == _selectedMemberId;
//       return Marker(
//         markerId: MarkerId(m.id),
//         position: m.position,
//         rotation: m.headingDegrees ?? 0,
//         anchor: const Offset(0.5, 0.5),
//         zIndex: isSelected ? 2 : 1,
//         icon: BitmapDescriptor.defaultMarkerWithHue(_hueForColor(m.color)),
//         onTap: () => _focusMember(m, zoom: 16),
//         infoWindow: InfoWindow(title: m.name, snippet: _statusLabel(m)),
//       );
//     }).toSet();
//   }
//
//   double _hueForColor(Color c) {
//     final hsl = HSLColor.fromColor(c);
//     return hsl.hue;
//   }
//
//   String _statusLabel(MemberLocation m) {
//     final speed = widget.speedUnitKmh
//         ? '${m.speedKmh.toStringAsFixed(0)} km/h'
//         : '${(m.speedKmh * 0.621371).toStringAsFixed(0)} mph';
//     switch (m.effectiveStatus) {
//       case MovementStatus.driving:
//         return 'Driving • $speed';
//       case MovementStatus.walking:
//         return 'Walking • $speed';
//       case MovementStatus.stopped:
//         return 'Stopped';
//       case MovementStatus.unknown:
//         return speed;
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     return SafeArea(
//       child: Scaffold(
//         body: Stack(
//           children: [
//             GoogleMap(
//               initialCameraPosition: CameraPosition(
//                 target: widget.members.isNotEmpty
//                     ? widget.members.first.position
//                     : const LatLng(9.9252, 78.1198), // fallback: Madurai
//                 zoom: 12,
//               ),
//               markers: _buildMarkers(),
//               myLocationButtonEnabled: false,
//               zoomControlsEnabled: false,
//               onMapCreated: (c) {
//                 _mapController = c;
//                 WidgetsBinding.instance.addPostFrameCallback((_) {
//                   _fitAllMembers();
//                 });
//               },
//             ),
//
//             //     Top member chip strip.
//             SafeArea(
//               child: SizedBox(
//                 height: 84,
//                 child: ListView.separated(
//                   padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
//                   scrollDirection: Axis.horizontal,
//                   itemCount: widget.members.length,
//                   separatorBuilder: (_, __) => const SizedBox(width: 10),
//                   itemBuilder: (context, i) {
//                     final m = widget.members[i];
//                     final isSelected = m.id == _selectedMemberId;
//                     return GestureDetector(
//                       onTap: () => _focusMember(m),
//                       child: Column(
//                         mainAxisSize: MainAxisSize.min,
//                         children: [
//                           Expanded(
//                             child: Container(
//                               padding: const EdgeInsets.all(2),
//                               decoration: BoxDecoration(
//                                 shape: BoxShape.circle,
//                                 border: Border.all(
//                                   color: isSelected
//                                       ? m.color
//                                       : Colors.transparent,
//                                   width: 2.5,
//                                 ),
//                               ),
//                               child: CircleAvatar(
//                                 radius: 24,
//                                 backgroundColor: m.color.withValues(
//                                   alpha: 0.15,
//                                 ),
//                                 backgroundImage: m.avatarUrl != null
//                                     ? NetworkImage(m.avatarUrl!)
//                                     : null,
//                                 child: m.avatarUrl == null
//                                     ? Text(
//                                         m.name.isNotEmpty
//                                             ? m.name[0].toUpperCase()
//                                             : '?',
//                                         style: TextStyle(
//                                           color: m.color,
//                                           fontWeight: FontWeight.bold,
//                                         ),
//                                       )
//                                     : null,
//                               ),
//                             ),
//                           ),
//                           const SizedBox(height: 4),
//                           SizedBox(
//                             width: 70,
//                             child: Text(
//                               m.name,
//                               maxLines: 1,
//                               textAlign: TextAlign.center,
//                               style: theme.textTheme.labelSmall?.copyWith(
//                                 color: Platform.isIOS
//                                     ? Colors.white
//                                     : Colors.black,
//                               ),
//                               overflow: TextOverflow.ellipsis,
//                             ),
//                           ),
//                         ],
//                       ),
//                     );
//                   },
//                 ),
//               ),
//             ),
//             DraggableScrollableSheet(
//               controller: _sheetController,
//               initialChildSize: 0.32,
//               minChildSize: 0.14,
//               maxChildSize: 0.62,
//               builder: (context, scrollController) {
//                 final m = _selectedMember;
//                 return Material(
//                   color: Colors.white,
//                   borderRadius: const BorderRadius.vertical(
//                     top: Radius.circular(20),
//                   ),
//                   // decoration: BoxDecoration(
//                   //   color: theme.colorScheme.surface,
//                   //   borderRadius: const BorderRadius.vertical(
//                   //     top: Radius.circular(20),
//                   //   ),
//                   //   boxShadow: const [
//                   //     BoxShadow(color: Colors.black26, blurRadius: 12),
//                   //   ],
//                   // ),
//                   child: ListView(
//                     controller: scrollController,
//                     padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
//                     children: [
//                       Center(
//                         child: Container(
//                           width: 40,
//                           height: 4,
//                           margin: const EdgeInsets.only(bottom: 12),
//                           decoration: BoxDecoration(
//                             color: theme.dividerColor,
//                             borderRadius: BorderRadius.circular(2),
//                           ),
//                         ),
//                       ),
//                       if (m == null)
//                         const Padding(
//                           padding: EdgeInsets.symmetric(vertical: 24),
//                           child: Center(child: Text('No member selected')),
//                         )
//                       else
//                         _MemberDetailCard(
//                           member: m,
//                           speedUnitKmh: widget.speedUnitKmh,
//                         ),
//                       if (widget.members.length > 1) ...[
//                         const SizedBox(height: 20),
//                         Text('All members', style: theme.textTheme.titleSmall),
//                         const SizedBox(height: 8),
//                         ...widget.members.map(
//                           (mem) => _MemberListTile(
//                             member: mem,
//                             selected: mem.id == _selectedMemberId,
//                             speedUnitKmh: widget.speedUnitKmh,
//                             onTap: () => _focusMember(mem),
//                           ),
//                         ),
//                       ],
//                     ],
//                   ),
//                 );
//               },
//             ),
//             // Recenter / fit-all FAB.
//             Positioned(
//               right: 16,
//               bottom: 0,
//               child: SafeArea(
//                 minimum: const EdgeInsets.only(bottom: 260),
//                 child: Row(
//                   mainAxisAlignment: MainAxisAlignment.spaceBetween,
//                   children: [
//                     GestureDetector(
//                       onTap: () async {
//                         Navigator.push(
//                           context,
//                           MaterialPageRoute(
//                             builder: (context) => WeeklyDrivingReportScreen(
//                               userId:
//                                   Supabase.instance.client.auth.currentUser!.id,
//                               repository: DrivingReportRepository(
//                                 Supabase.instance.client,
//                               ),
//                             ),
//                           ),
//                         );
//                         final prefs = await SharedPreferences.getInstance();
//                         final familyId = prefs.getString('last_family_id');
//                         // final checkedIn = await Navigator.push<bool>(
//                         //   context,
//                         //   MaterialPageRoute(
//                         //     builder: (context) => CheckInScreen(
//                         //       familyId: familyId ?? "",
//                         //       placesRepository: PlacesRepository(
//                         //         Supabase.instance.client,
//                         //       ),
//                         //       checkInService: CheckInService(
//                         //         Supabase.instance.client,
//                         //       ),
//                         //       placesSearch: GooglePlacesSearch(
//                         //         'AIzaSyBBPcrPNHpRnsozTqQV_Q8knWBnqLIFMzY',
//                         //       ),
//                         //       currentLat:
//                         //           0 /* your current lat, e.g. from your last GPS fix */,
//                         //       currentLng: 0 /* your current lng */,
//                         //     ),
//                         //   ),
//                         // );
//                         // if (checkedIn == true) {
//                         //   // optionally refresh something, show a snackbar, etc.
//                         // }
//                       },
//                       child: Container(
//                         padding: EdgeInsets.symmetric(
//                           horizontal: 20,
//                           vertical: 10,
//                         ),
//                         decoration: BoxDecoration(
//                           borderRadius: BorderRadius.circular(20),
//                           color: Colors.white,
//                           boxShadow: [
//                             BoxShadow(
//                               color: Colors.grey.shade300,
//                               blurRadius: 0.8,
//                               spreadRadius: 0.8,
//                               offset: Offset(0, 0.4),
//                             ),
//                           ],
//                         ),
//                         child: Row(
//                           children: [
//                             Icon(
//                               Icons.location_on_outlined,
//                               color: ShieldColors.activeTeal,
//                               size: 18,
//                             ),
//                             Text(
//                               "Check in",
//                               style: TextStyle(color: ShieldColors.activeTeal),
//                             ),
//                           ],
//                         ),
//                       ),
//                     ),
//                     FloatingActionButton.small(
//                       heroTag: 'life360-fit-all',
//                       onPressed: _fitAllMembers,
//                       child: const Icon(Icons.center_focus_strong),
//                     ),
//                   ],
//                 ),
//               ),
//             ),
//           ],
//         ),
//
//         // Bottom detail sheet.
//         // bottomSheet: DraggableScrollableSheet(
//         //   controller: _sheetController,
//         //   initialChildSize: 0.32,
//         //   minChildSize: 0.14,
//         //   maxChildSize: 0.62,
//         //   builder: (context, scrollController) {
//         //     final m = _selectedMember;
//         //     return Container(
//         //       decoration: BoxDecoration(
//         //         color: theme.colorScheme.surface,
//         //         borderRadius: const BorderRadius.vertical(
//         //           top: Radius.circular(20),
//         //         ),
//         //         boxShadow: const [
//         //           BoxShadow(color: Colors.black26, blurRadius: 12),
//         //         ],
//         //       ),
//         //       child: ListView(
//         //         controller: scrollController,
//         //         padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
//         //         children: [
//         //           Center(
//         //             child: Container(
//         //               width: 40,
//         //               height: 4,
//         //               margin: const EdgeInsets.only(bottom: 12),
//         //               decoration: BoxDecoration(
//         //                 color: theme.dividerColor,
//         //                 borderRadius: BorderRadius.circular(2),
//         //               ),
//         //             ),
//         //           ),
//         //           if (m == null)
//         //             const Padding(
//         //               padding: EdgeInsets.symmetric(vertical: 24),
//         //               child: Center(child: Text('No member selected')),
//         //             )
//         //           else
//         //             _MemberDetailCard(
//         //               member: m,
//         //               speedUnitKmh: widget.speedUnitKmh,
//         //             ),
//         //           if (widget.members.length > 1) ...[
//         //             const SizedBox(height: 20),
//         //             Text('All members', style: theme.textTheme.titleSmall),
//         //             const SizedBox(height: 8),
//         //             ...widget.members.map(
//         //               (mem) => _MemberListTile(
//         //                 member: mem,
//         //                 selected: mem.id == _selectedMemberId,
//         //                 speedUnitKmh: widget.speedUnitKmh,
//         //                 onTap: () => _focusMember(mem),
//         //               ),
//         //             ),
//         //           ],
//         //         ],
//         //       ),
//         //     );
//         //   },
//         // ),
//       ),
//     );
//   }
// }
//
// // ---------------------------------------------------------------------------
// // DETAIL CARD (speed, address, battery, last updated)
// // ---------------------------------------------------------------------------
//
// class _MemberDetailCard extends StatelessWidget {
//   const _MemberDetailCard({required this.member, required this.speedUnitKmh});
//
//   final MemberLocation member;
//   final bool speedUnitKmh;
//
//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final speedText = speedUnitKmh
//         ? '${member.speedKmh.toStringAsFixed(0)} km/h'
//         : '${(member.speedKmh * 0.621371).toStringAsFixed(0)} mph';
//
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Row(
//           children: [
//             CircleAvatar(
//               radius: 26,
//               backgroundColor: member.color.withValues(alpha: 0.15),
//               backgroundImage: member.avatarUrl != null
//                   ? NetworkImage(member.avatarUrl!)
//                   : null,
//               child: member.avatarUrl == null
//                   ? Text(
//                       member.name.isNotEmpty
//                           ? member.name[0].toUpperCase()
//                           : '?',
//                       style: TextStyle(
//                         color: member.color,
//                         fontWeight: FontWeight.bold,
//                         fontSize: 18,
//                       ),
//                     )
//                   : null,
//             ),
//             const SizedBox(width: 12),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Text(member.name, style: theme.textTheme.titleMedium),
//                   Text(
//                     'Updated ${_relativeTime(member.lastUpdated)}',
//                     style: theme.textTheme.bodySmall?.copyWith(
//                       color: theme.hintColor,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             _StatusPill(status: member.effectiveStatus),
//           ],
//         ),
//         const SizedBox(height: 16),
//         Row(
//           children: [
//             Expanded(
//               child: _StatTile(
//                 icon: Icons.speed,
//                 label: 'Speed',
//                 value: speedText,
//               ),
//             ),
//             if (member.batteryPercent != null)
//               Expanded(
//                 child: _StatTile(
//                   icon: member.batteryPercent! < 20
//                       ? Icons.battery_alert
//                       : Icons.battery_std,
//                   label: 'Battery',
//                   value: '${member.batteryPercent!.toStringAsFixed(0)}%',
//                   valueColor: member.batteryPercent! < 20
//                       ? Colors.redAccent
//                       : null,
//                 ),
//               ),
//           ],
//         ),
//         const SizedBox(height: 12),
//         if (member.address != null) ...[
//           Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               Icon(Icons.location_on, size: 18, color: theme.hintColor),
//               const SizedBox(width: 6),
//               Expanded(
//                 child: Text(member.address!, style: theme.textTheme.bodyMedium),
//               ),
//             ],
//           ),
//           const SizedBox(height: 4),
//         ],
//         Row(
//           children: [
//             Icon(Icons.my_location, size: 16, color: theme.hintColor),
//             const SizedBox(width: 6),
//             Text(
//               '${member.latitude.toStringAsFixed(5)}, '
//               '${member.longitude.toStringAsFixed(5)}',
//               style: theme.textTheme.bodySmall?.copyWith(
//                 color: theme.hintColor,
//               ),
//             ),
//           ],
//         ),
//       ],
//     );
//   }
//
//   static String _relativeTime(DateTime dt) {
//     final diff = DateTime.now().difference(dt);
//     if (diff.inSeconds < 60) return 'just now';
//     if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
//     if (diff.inHours < 24) return '${diff.inHours}h ago';
//     return DateFormat('MMM d, h:mm a').format(dt);
//   }
// }
//
// class _StatTile extends StatelessWidget {
//   const _StatTile({
//     required this.icon,
//     required this.label,
//     required this.value,
//     this.valueColor,
//   });
//
//   final IconData icon;
//   final String label;
//   final String value;
//   final Color? valueColor;
//
//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     return Row(
//       children: [
//         Icon(icon, size: 22, color: theme.hintColor),
//         const SizedBox(width: 8),
//         Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Text(
//               label,
//               style: theme.textTheme.bodySmall?.copyWith(
//                 color: theme.hintColor,
//               ),
//             ),
//             Text(
//               value,
//               style: theme.textTheme.titleSmall?.copyWith(color: valueColor),
//             ),
//           ],
//         ),
//       ],
//     );
//   }
// }
//
// class _StatusPill extends StatelessWidget {
//   const _StatusPill({required this.status});
//
//   final MovementStatus status;
//
//   @override
//   Widget build(BuildContext context) {
//     late final Color color;
//     late final IconData icon;
//     late final String label;
//     switch (status) {
//       case MovementStatus.driving:
//         color = Colors.orange;
//         icon = Icons.directions_car;
//         label = 'Driving';
//         break;
//       case MovementStatus.walking:
//         color = Colors.blue;
//         icon = Icons.directions_walk;
//         label = 'Walking';
//         break;
//       case MovementStatus.stopped:
//         color = Colors.green;
//         icon = Icons.pause_circle;
//         label = 'Stopped';
//         break;
//       case MovementStatus.unknown:
//         color = Colors.grey;
//         icon = Icons.help_outline;
//         label = '—';
//         break;
//     }
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
//       decoration: BoxDecoration(
//         color: color.withValues(alpha: 0.12),
//         borderRadius: BorderRadius.circular(20),
//       ),
//       child: Row(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           Icon(icon, size: 14, color: color),
//           const SizedBox(width: 4),
//           Text(
//             label,
//             style: TextStyle(
//               color: color,
//               fontSize: 12,
//               fontWeight: FontWeight.w600,
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// class _MemberListTile extends StatelessWidget {
//   const _MemberListTile({
//     required this.member,
//     required this.selected,
//     required this.speedUnitKmh,
//     required this.onTap,
//   });
//
//   final MemberLocation member;
//   final bool selected;
//   final bool speedUnitKmh;
//   final VoidCallback onTap;
//
//   @override
//   Widget build(BuildContext context) {
//     final speedText = speedUnitKmh
//         ? '${member.speedKmh.toStringAsFixed(0)} km/h'
//         : '${(member.speedKmh * 0.621371).toStringAsFixed(0)} mph';
//     return ListTile(
//       onTap: onTap,
//       selected: selected,
//       contentPadding: EdgeInsets.zero,
//       leading: CircleAvatar(
//         backgroundColor: member.color.withValues(alpha: 0.15),
//         backgroundImage: member.avatarUrl != null
//             ? NetworkImage(member.avatarUrl!)
//             : null,
//         child: member.avatarUrl == null
//             ? Text(
//                 member.name.isNotEmpty ? member.name[0].toUpperCase() : '?',
//                 style: TextStyle(color: member.color),
//               )
//             : null,
//       ),
//       title: Text(member.name),
//       subtitle: Text(member.address ?? speedText),
//       trailing: _StatusPill(status: member.effectiveStatus),
//     );
//   }
// }
// // life360_map_screen_v2.dart
// //
// // Map screen styled to match the real Life360 app layout:
// //   - Member markers + saved place markers (home/school/college/gym) on the map
// //   - Swipeable card carousel at the bottom (PageView), one card per member —
// //     swiping the carousel moves the map camera; tapping a map marker moves
// //     the carousel. This mirrors Life360's actual bottom-card behavior,
// //     replacing a generic DraggableScrollableSheet.
// //   - Quick action row (call / message) per member card.
// //
// // Requires: life360_map_screen.dart (MemberLocation, MovementStatus)
// //           life360_places.dart (SavedPlace, PlacesRepository)
//
// class Life360MapScreenV2 extends StatefulWidget {
//   const Life360MapScreenV2({
//     super.key,
//     required this.members,
//     required this.familyId,
//     required this.placesRepository,
//     this.speedUnitKmh = true,
//     this.onCallMember,
//     this.onMessageMember,
//   });
//
//   final List<MemberLocation> members;
//   final String familyId;
//   final PlacesRepository placesRepository;
//   final bool speedUnitKmh;
//
//   /// Optional hooks for the quick-action buttons on each card.
//   final void Function(MemberLocation member)? onCallMember;
//   final void Function(MemberLocation member)? onMessageMember;
//
//   @override
//   State<Life360MapScreenV2> createState() => _Life360MapScreenV2State();
// }
//
// class _Life360MapScreenV2State extends State<Life360MapScreenV2> {
//   GoogleMapController? _mapController;
//   late final PageController _cardController;
//   int _selectedIndex = 0;
//   List<SavedPlace> _places = [];
//   bool _suppressPageCallback = false;
//
//   @override
//   void initState() {
//     super.initState();
//     _cardController = PageController(viewportFraction: 0.88);
//     _loadPlaces();
//   }
//
//   Future<void> _loadPlaces() async {
//     final places = await widget.placesRepository.fetchPlaces(widget.familyId);
//     if (mounted) setState(() => _places = places);
//   }
//
//   @override
//   void didUpdateWidget(covariant Life360MapScreenV2 oldWidget) {
//     super.didUpdateWidget(oldWidget);
//     if (_selectedIndex >= widget.members.length && widget.members.isNotEmpty) {
//       _selectedIndex = 0;
//     }
//   }
//
//   @override
//   void dispose() {
//     _cardController.dispose();
//     super.dispose();
//   }
//
//   MemberLocation? get _selectedMember =>
//       widget.members.isEmpty ? null : widget.members[_selectedIndex];
//
//   Future<void> _selectMember(int index, {bool moveCard = true}) async {
//     if (index < 0 || index >= widget.members.length) return;
//     setState(() => _selectedIndex = index);
//     final member = widget.members[index];
//     await _mapController?.animateCamera(
//       CameraUpdate.newLatLngZoom(member.position, 16),
//     );
//     if (moveCard && _cardController.hasClients) {
//       _suppressPageCallback = true;
//       await _cardController.animateToPage(
//         index,
//         duration: const Duration(milliseconds: 250),
//         curve: Curves.easeOut,
//       );
//       _suppressPageCallback = false;
//     }
//   }
//
//   Future<void> _fitAllMembers() async {
//     if (widget.members.isEmpty || _mapController == null) return;
//     if (widget.members.length == 1) {
//       await _selectMember(0);
//       return;
//     }
//     double minLat = widget.members.first.latitude;
//     double maxLat = widget.members.first.latitude;
//     double minLng = widget.members.first.longitude;
//     double maxLng = widget.members.first.longitude;
//     for (final m in widget.members) {
//       minLat = math.min(minLat, m.latitude);
//       maxLat = math.max(maxLat, m.latitude);
//       minLng = math.min(minLng, m.longitude);
//       maxLng = math.max(maxLng, m.longitude);
//     }
//     await _mapController!.animateCamera(
//       CameraUpdate.newLatLngBounds(
//         LatLngBounds(
//           southwest: LatLng(minLat, minLng),
//           northeast: LatLng(maxLat, maxLng),
//         ),
//         60,
//       ),
//     );
//   }
//
//   Set<Marker> _buildMemberMarkers() {
//     return widget.members.asMap().entries.map((entry) {
//       final i = entry.key;
//       final m = entry.value;
//       return Marker(
//         markerId: MarkerId('member_${m.id}'),
//         position: m.position,
//         rotation: m.headingDegrees ?? 0,
//         anchor: const Offset(0.5, 0.5),
//         zIndex: i == _selectedIndex ? 2 : 1,
//         icon: BitmapDescriptor.defaultMarkerWithHue(
//           HSLColor.fromColor(m.color).hue,
//         ),
//         onTap: () => _selectMember(i),
//       );
//     }).toSet();
//   }
//
//   Set<Marker> _buildPlaceMarkers() {
//     return _places.map((p) {
//       return Marker(
//         markerId: MarkerId('place_${p.id}'),
//         position: p.position,
//         icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
//         alpha: 0.85,
//         infoWindow: InfoWindow(title: p.label),
//       );
//     }).toSet();
//   }
//
//   Set<Circle> _buildPlaceCircles() {
//     return _places.map((p) {
//       return Circle(
//         circleId: CircleId('place_radius_${p.id}'),
//         center: p.position,
//         radius: p.radiusM,
//         fillColor: Colors.deepPurple.withValues(alpha: 0.08),
//         strokeColor: Colors.deepPurple.withValues(alpha: 0.4),
//         strokeWidth: 1,
//       );
//     }).toSet();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       body: Stack(
//         children: [
//           GoogleMap(
//             initialCameraPosition: CameraPosition(
//               target: widget.members.isNotEmpty
//                   ? widget.members.first.position
//                   : const LatLng(9.9252, 78.1198),
//               zoom: 12,
//             ),
//             markers: {..._buildMemberMarkers(), ..._buildPlaceMarkers()},
//             circles: _buildPlaceCircles(),
//             myLocationButtonEnabled: false,
//             zoomControlsEnabled: false,
//             padding: const EdgeInsets.only(bottom: 200),
//             // keep controls clear of cards
//             onMapCreated: (c) {
//               _mapController = c;
//               WidgetsBinding.instance.addPostFrameCallback((_) {
//                 _fitAllMembers();
//               });
//             },
//           ),
//
//           // Top search / title bar (Life360-style header).
//           SafeArea(
//             child: Padding(
//               padding: const EdgeInsets.all(12),
//               child: Material(
//                 elevation: 3,
//                 borderRadius: BorderRadius.circular(24),
//                 child: Padding(
//                   padding: const EdgeInsets.symmetric(
//                     horizontal: 16,
//                     vertical: 12,
//                   ),
//                   child: Row(
//                     children: [
//                       const Icon(Icons.people_alt, size: 20),
//                       const SizedBox(width: 8),
//                       Text(
//                         'Family',
//                         style: Theme.of(context).textTheme.titleMedium,
//                       ),
//                       const Spacer(),
//                       IconButton(
//                         icon: const Icon(Icons.center_focus_strong),
//                         onPressed: _fitAllMembers,
//                       ),
//                     ],
//                   ),
//                 ),
//               ),
//             ),
//           ),
//
//           // Bottom swipeable member card carousel.
//           Positioned(
//             left: 0,
//             right: 0,
//             bottom: 0,
//             child: SafeArea(
//               top: false,
//               child: SizedBox(
//                 height: 168,
//                 child: widget.members.isEmpty
//                     ? const Center(child: Text('No members yet'))
//                     : PageView.builder(
//                         controller: _cardController,
//                         itemCount: widget.members.length,
//                         onPageChanged: (i) {
//                           if (_suppressPageCallback) return;
//                           _selectMember(i, moveCard: false);
//                         },
//                         itemBuilder: (context, i) {
//                           return _MemberCard(
//                             member: widget.members[i],
//                             speedUnitKmh: widget.speedUnitKmh,
//                             onCall: widget.onCallMember,
//                             onMessage: widget.onMessageMember,
//                           );
//                         },
//                       ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }
// }
//
// // ---------------------------------------------------------------------------
// // MEMBER CARD (matches Life360's bottom carousel card)
// // ---------------------------------------------------------------------------
//
// class _MemberCard extends StatelessWidget {
//   const _MemberCard({
//     required this.member,
//     required this.speedUnitKmh,
//     this.onCall,
//     this.onMessage,
//   });
//
//   final MemberLocation member;
//   final bool speedUnitKmh;
//   final void Function(MemberLocation member)? onCall;
//   final void Function(MemberLocation member)? onMessage;
//
//   @override
//   Widget build(BuildContext context) {
//     final theme = Theme.of(context);
//     final speedText = speedUnitKmh
//         ? '${member.speedKmh.toStringAsFixed(0)} km/h'
//         : '${(member.speedKmh * 0.621371).toStringAsFixed(0)} mph';
//
//     String statusLine;
//     switch (member.effectiveStatus) {
//       case MovementStatus.driving:
//         statusLine = 'Driving • $speedText';
//         break;
//       case MovementStatus.walking:
//         statusLine = 'Walking • $speedText';
//         break;
//       case MovementStatus.stopped:
//         statusLine = 'At a stop';
//         break;
//       case MovementStatus.unknown:
//         statusLine = speedText;
//         break;
//     }
//
//     return Padding(
//       padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
//       child: Material(
//         elevation: 6,
//         borderRadius: BorderRadius.circular(18),
//         color: theme.colorScheme.surface,
//         child: Padding(
//           padding: const EdgeInsets.all(14),
//           child: Row(
//             crossAxisAlignment: CrossAxisAlignment.start,
//             children: [
//               CircleAvatar(
//                 radius: 26,
//                 backgroundColor: member.color.withValues(alpha: 0.15),
//                 backgroundImage: member.avatarUrl != null
//                     ? NetworkImage(member.avatarUrl!)
//                     : null,
//                 child: member.avatarUrl == null
//                     ? Text(
//                         member.name.isNotEmpty
//                             ? member.name[0].toUpperCase()
//                             : '?',
//                         style: TextStyle(
//                           color: member.color,
//                           fontWeight: FontWeight.bold,
//                           fontSize: 18,
//                         ),
//                       )
//                     : null,
//               ),
//               const SizedBox(width: 12),
//               Expanded(
//                 child: Column(
//                   crossAxisAlignment: CrossAxisAlignment.start,
//                   children: [
//                     Text(member.name, style: theme.textTheme.titleMedium),
//                     const SizedBox(height: 2),
//                     Text(
//                       statusLine,
//                       style: theme.textTheme.bodySmall?.copyWith(
//                         color: theme.hintColor,
//                       ),
//                     ),
//                     if (member.address != null)
//                       Padding(
//                         padding: const EdgeInsets.only(top: 2),
//                         child: Text(
//                           member.address!,
//                           style: theme.textTheme.bodySmall,
//                           maxLines: 1,
//                           overflow: TextOverflow.ellipsis,
//                         ),
//                       ),
//                     Padding(
//                       padding: const EdgeInsets.only(top: 2),
//                       child: Text(
//                         _relativeTime(member.lastUpdated),
//                         style: theme.textTheme.bodySmall?.copyWith(
//                           color: theme.hintColor,
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               Column(
//                 children: [
//                   IconButton(
//                     icon: const Icon(Icons.call_outlined),
//                     onPressed: onCall != null ? () => onCall!(member) : null,
//                   ),
//                   IconButton(
//                     icon: const Icon(Icons.message_outlined),
//                     onPressed: onMessage != null
//                         ? () => onMessage!(member)
//                         : null,
//                   ),
//                 ],
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
//
//   static String _relativeTime(DateTime dt) {
//     final diff = DateTime.now().difference(dt);
//     if (diff.inSeconds < 60) return 'Updated just now';
//     if (diff.inMinutes < 60) return 'Updated ${diff.inMinutes}m ago';
//     if (diff.inHours < 24) return 'Updated ${diff.inHours}h ago';
//     return 'Updated ${DateFormat('MMM d, h:mm a').format(dt)}';
//   }
// }
// life360_map_screen.dart
//
// A Life360-style "family/group map" screen for Flutter.
//
// Shows:
//  - Google Map with a marker per member (colored avatar-style pin)
//  - Draggable bottom sheet with member details: speed, address,
//    last updated, battery %, driving/stopped status
//  - Horizontal member chip list at the top to quickly jump to a member
//  - Recenter / "show all members" FAB
//
// Dependencies (add to pubspec.yaml):
//   google_maps_flutter: ^2.9.0
//   geocoding: ^3.0.0         // for reverse-geocoding lat/lng -> address (optional)
//   intl: ^0.19.0             // for "last updated" time formatting
//
// Wire `MemberLocation` up to your own realtime source (Supabase Realtime,
// Firebase, socket, polling API, etc.) — just push updated MemberLocation
// objects into `onMembersChanged` / update `_members` and call setState,
// or convert `_members` to a Stream/ValueNotifier if you prefer.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/features/driving_detection/weekly_stats_driving.dart';

import '../../core/design/shield_theme.dart';
import '../../services/check_in_service.dart';
import '../../services/life360_places.dart';

// ---------------------------------------------------------------------------
// MODEL
// ---------------------------------------------------------------------------

enum MovementStatus { stopped, walking, driving, unknown }

class MemberLocation {
  final String id;
  final String name;
  final String? avatarUrl;
  final Color color;
  final double latitude;
  final double longitude;
  final double speedKmh; // current speed in km/h
  final double? headingDegrees; // 0-360, for rotating the marker
  final double? batteryPercent; // 0-100
  final DateTime lastUpdated;
  final String? address; // pre-resolved address, if you have one
  final MovementStatus status;
  final bool motionPermissionEnabled;
  final DateTime? permissionChangedAt;

  const MemberLocation({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.speedKmh,
    required this.lastUpdated,
    this.avatarUrl,
    this.color = Colors.blue,
    this.headingDegrees,
    this.batteryPercent,
    this.address,
    this.status = MovementStatus.unknown,
    this.motionPermissionEnabled = true,
    this.permissionChangedAt,
  });

  LatLng get position => LatLng(latitude, longitude);

  MovementStatus get effectiveStatus {
    if (status != MovementStatus.unknown) return status;
    if (speedKmh < 1) return MovementStatus.stopped;
    if (speedKmh < 8) return MovementStatus.walking;
    return MovementStatus.driving;
  }
}

// ---------------------------------------------------------------------------
// SCREEN
// ---------------------------------------------------------------------------

class Life360MapScreen extends StatefulWidget {
  const Life360MapScreen({
    super.key,
    required this.members,
    this.onRefresh,
    this.speedUnitKmh = true,
    this.showAllMembers = true,
  });

  /// Current members to plot on the map. Pass an updated list (e.g. from a
  /// realtime stream) and this widget will animate/update markers.
  final List<MemberLocation> members;

  /// Called when the user pulls to refresh / taps the refresh action.
  final Future<void> Function()? onRefresh;

  /// true = show speed in km/h, false = show mph.
  final bool speedUnitKmh;
  final bool showAllMembers;

  @override
  State<Life360MapScreen> createState() => _Life360MapScreenState();
}

class _Life360MapScreenState extends State<Life360MapScreen> {
  GoogleMapController? _mapController;
  String? _selectedMemberId;
  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  bool isLoad = false;
  final ValueNotifier<double> _sheetExtent = ValueNotifier<double>(0.32);

  @override
  void didUpdateWidget(covariant Life360MapScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep selection valid if a member disappears from the list.
    if (_selectedMemberId != null &&
        widget.members.every((m) => m.id != _selectedMemberId)) {
      _selectedMemberId = widget.members.isNotEmpty
          ? widget.members.first.id
          : null;
    } else if (_selectedMemberId == null && widget.members.isNotEmpty) {
      _selectedMemberId = widget.members.first.id;
    }
  }

  @override
  void initState() {
    super.initState();
    if (widget.members.isNotEmpty) {
      _selectedMemberId = widget.members.first.id;
    }
    _loadMemberIcons();

    _sheetController.addListener(() {
      if (_sheetController.isAttached) {
        _sheetExtent.value = _sheetController.size;
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
    _sheetExtent.dispose();
  }

  MemberLocation? get _selectedMember {
    if (_selectedMemberId == null) return null;
    try {
      return widget.members.firstWhere((m) => m.id == _selectedMemberId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _focusMember(MemberLocation member, {double zoom = 16}) async {
    setState(() => _selectedMemberId = member.id);
    await _mapController?.animateCamera(
      CameraUpdate.newLatLngZoom(member.position, zoom),
    );
    // _sheetController.animateTo(
    //   0.32,
    //   duration: const Duration(milliseconds: 250),
    //   curve: Curves.easeOut,
    // );
    if (_sheetController.isAttached) {
      _sheetController.animateTo(
        0.32,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  }

  Future<void> _fitAllMembers() async {
    if (widget.members.isEmpty || _mapController == null) return;
    if (widget.members.length == 1) {
      await _focusMember(widget.members.first);
      return;
    }
    double minLat = widget.members.first.latitude;
    double maxLat = widget.members.first.latitude;
    double minLng = widget.members.first.longitude;
    double maxLng = widget.members.first.longitude;
    for (final m in widget.members) {
      minLat = math.min(minLat, m.latitude);
      maxLat = math.max(maxLat, m.latitude);
      minLng = math.min(minLng, m.longitude);
      maxLng = math.max(maxLng, m.longitude);
    }
    await _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        60,
      ),
    );
  }

  // Set<Marker> _buildMarkers() {
  //   return widget.members.map((m) {
  //     final isSelected = m.id == _selectedMemberId;
  //     return Marker(
  //       markerId: MarkerId(m.id),
  //       position: m.position,
  //       rotation: m.headingDegrees ?? 0,
  //       anchor: const Offset(0.5, 0.5),
  //       zIndex: isSelected ? 2 : 1,
  //       icon: BitmapDescriptor.defaultMarkerWithHue(_hueForColor(m.color)),
  //       onTap: () => _focusMember(m, zoom: 16),
  //       infoWindow: InfoWindow(title: m.name, snippet: _statusLabel(m)),
  //     );
  //   }).toSet();
  // }
  final Set<String> _avatarIds = {};
  final Map<String, String> _avatarUrls = {};

  Future<void> _loadAvatarIcons() async {
    for (final m in widget.members) {
      final url = m.avatarUrl;
      if (url == null || url.isEmpty) continue;
      if (_avatarUrls[m.id] == url) continue; // already loaded

      try {
        _memberIcons[m.id] = await _avatarMarker(url);
        _avatarIds.add(m.id);
        _avatarUrls[m.id] = url;
      } catch (_) {
        // download failed: keep the old icon
      }
    }
    if (mounted) setState(() {});
  }

  Future<BitmapDescriptor> _avatarMarker(
    String url, {
    int size = 110,
    double border = 6,
    Color borderColor = Colors.white,
  }) async {
    final response = await http.get(Uri.parse(url));
    final codec = await ui.instantiateImageCodec(
      response.bodyBytes,
      targetWidth: size,
      targetHeight: size,
    );
    final image = (await codec.getNextFrame()).image;

    final total = size + border * 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final center = Offset(total / 2, total / 2);

    // Border circle
    canvas.drawCircle(center, total / 2, Paint()..color = borderColor);

    // Clip to circle and draw the photo
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: size / 2)),
    );
    canvas.drawImage(image, Offset(border, border), Paint());

    final picture = recorder.endRecording();
    final img = await picture.toImage(total.toInt(), total.toInt());
    final bytes = (await img.toByteData(
      format: ui.ImageByteFormat.png,
    ))!.buffer.asUint8List();

    // Older google_maps_flutter: BitmapDescriptor.fromBytes(bytes)
    return BitmapDescriptor.bytes(bytes, width: 48, height: 48);
  }

  Set<Marker> _buildMarkers() {
    return widget.members.where((m) => _memberIcons.containsKey(m.id)).map((m) {
      final isSelected = m.id == _selectedMemberId;

      return Marker(
        markerId: MarkerId(m.id),
        position: m.position,
        rotation: _avatarIds.contains(m.id) ? 0 : (m.headingDegrees ?? 0),
        anchor: const Offset(0.5, 0.5),
        zIndex: isSelected ? 2 : 1,
        icon: _memberIcons[m.id]!,
        onTap: () => _focusMember(m, zoom: 16),
        infoWindow: InfoWindow(title: m.name, snippet: _statusLabel(m)),
      );
    }).toSet();
  }

  Map<String, BitmapDescriptor> _memberIcons = {};

  Future<void> _loadMemberIcons() async {
    final icons = <String, BitmapDescriptor>{};

    for (final member in widget.members) {
      icons[member.id] = await _createAvatarMarker(member.name, member.color);
    }

    if (!mounted) return;

    setState(() {
      _memberIcons = icons;
    });
    await _loadAvatarIcons();
  }

  //
  Future<BitmapDescriptor> _createAvatarMarker(
    String name,
    Color backgroundColor,
  ) async {
    final firstName = name.trim().split(' ').first;

    const double size = 120;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Avatar background
    final paint = Paint()..color = backgroundColor;

    canvas.drawCircle(const Offset(size / 2, 45), 40, paint);

    // White border
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5;

    canvas.drawCircle(const Offset(size / 2, 45), 40, borderPaint);

    // Avatar initial
    final initialPainter = TextPainter(
      text: TextSpan(
        text: firstName.isNotEmpty ? firstName[0].toUpperCase() : '?',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 30,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: ui.TextDirection.ltr, // IMPORTANT
    );

    initialPainter.layout();

    initialPainter.paint(
      canvas,
      Offset((size - initialPainter.width) / 2, 45 - initialPainter.height / 2),
    );

    // First name
    final namePainter = TextPainter(
      text: TextSpan(
        text: firstName,
        style: const TextStyle(
          color: Colors.black,
          fontSize: 16,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: ui.TextDirection.ltr, // IMPORTANT
      maxLines: 1,
      ellipsis: '...',
    );

    namePainter.layout(maxWidth: size);

    namePainter.paint(canvas, Offset((size - namePainter.width) / 2, 88));

    final picture = recorder.endRecording();

    final image = await picture.toImage(size.toInt(), size.toInt());

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return BitmapDescriptor.fromBytes(byteData!.buffer.asUint8List());
  }

  double _hueForColor(Color c) {
    final hsl = HSLColor.fromColor(c);
    return hsl.hue;
  }

  String _statusLabel(MemberLocation m) {
    final speed = widget.speedUnitKmh
        ? '${m.speedKmh.toStringAsFixed(0)} km/h'
        : '${(m.speedKmh * 0.621371).toStringAsFixed(0)} mph';
    switch (m.effectiveStatus) {
      case MovementStatus.driving:
        return 'Driving • $speed';
      case MovementStatus.walking:
        return 'Walking • $speed';
      case MovementStatus.stopped:
        return 'Stopped';
      case MovementStatus.unknown:
        return speed;
    }
  }

  Future<Position?> _getCurrentPosition() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enable Location Services.')),
        );
      }
      return null;
    }

    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission is required.')),
        );
      }
      return null;
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Location permission is permanently denied. Please enable it in Settings.',
            ),
          ),
        );
      }
      return null;
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
  }

  Future<void> _onAddPlaceTap() async {
    final prefs = await SharedPreferences.getInstance();
    final familyId = prefs.getString('last_family_id');
    if (familyId == null) return;

    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddPlaceScreen(
          familyId: familyId,
          showAllMembers: widget.showAllMembers,
          repository: PlacesRepository(Supabase.instance.client),
        ),
      ),
    );
  }

  _buildCheckInButton() {
    return GestureDetector(
      onTap: () async {
        setState(() {
          isLoad = true;
        });
        final position = await _getCurrentPosition();

        if (position == null) {
          setState(() {
            isLoad = false;
          });
          return;
        }
        setState(() {
          isLoad = false;
        });
        final prefs = await SharedPreferences.getInstance();
        final familyId = prefs.getString('last_family_id');
        final checkedIn = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => CheckInScreen(
              familyId: familyId ?? "",
              showAllMembers: widget.showAllMembers,
              placesRepository: PlacesRepository(Supabase.instance.client),
              checkInService: CheckInService(Supabase.instance.client),
              placesSearch: GooglePlacesSearch(
                'AIzaSyDaiR-2trfsS9oVK7ed0MnxhD9YRnOaQCk',
              ),
              currentLat: position
                  .latitude /* your current lat, e.g. from your last GPS fix */,
              currentLng: position.longitude /* your current lng */,
            ),
          ),
        );
        if (checkedIn == true) {
          await showGeneralDialog(
            context: context,
            barrierDismissible: false,
            barrierLabel: 'Check-in completed',
            barrierColor: Colors.black54,
            transitionDuration: const Duration(milliseconds: 400),
            pageBuilder: (context, animation, secondaryAnimation) {
              return const SizedBox();
            },
            transitionBuilder: (context, animation, secondaryAnimation, child) {
              final curvedAnimation = CurvedAnimation(
                parent: animation,
                curve: Curves.elasticOut,
              );

              return ScaleTransition(
                scale: curvedAnimation,
                child: FadeTransition(
                  opacity: animation,
                  child: Center(
                    child: Material(
                      color: Colors.transparent,
                      child: Container(
                        width: 280,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 28,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.12),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check_rounded,
                                color: Colors.green,
                                size: 48,
                              ),
                            ),

                            const SizedBox(height: 18),

                            const Text(
                              'Check-in Done!',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 8),

                            const Text(
                              'Your location has been checked in successfully.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),

                            const SizedBox(height: 22),

                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () {
                                  Navigator.of(context).pop();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Text(
                                  'Done',
                                  style: TextStyle(fontWeight: FontWeight.w600),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.grey.shade300,
              blurRadius: 4,
              spreadRadius: 0.8,
              offset: Offset(0, 0.8),
            ),
          ],
        ),
        child: isLoad
            ? Center(
                child: SizedBox(
                  height: 25,
                  width: 25,

                  child: CircularProgressIndicator(),
                ),
              )
            : Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    color: ShieldColors.activeTeal,
                    size: 18,
                  ),
                  Text(
                    "Check in",
                    style: TextStyle(color: ShieldColors.activeTeal),
                  ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: widget.members.isNotEmpty
                  ? widget.members.first.position
                  : const LatLng(9.9252, 78.1198), // fallback: Madurai
              zoom: 12,
            ),
            markers: _buildMarkers(),
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            onMapCreated: (c) {
              _mapController = c;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                _fitAllMembers();
              });
            },
          ),

          // Top member chip strip.
          SafeArea(
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 12, top: 0),
                  child: Material(
                    color: Colors.white,
                    shape: const CircleBorder(),
                    elevation: 3,
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).maybePop(),
                      child: const SizedBox(
                        width: 35,
                        height: 35,
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          size: 15,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: SizedBox(
                    height: 84,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.members.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, i) {
                        final m = widget.members[i];
                        final isSelected = m.id == _selectedMemberId;
                        print(m.avatarUrl);
                        print("avatarUrl");
                        return GestureDetector(
                          onTap: () => _focusMember(m),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Expanded(
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? m.color
                                          : Colors.transparent,
                                      width: 2.5,
                                    ),
                                  ),
                                  child: CircleAvatar(
                                    radius: 24,
                                    backgroundColor: m.color.withValues(
                                      alpha: 0.15,
                                    ),
                                    backgroundImage:
                                        m.avatarUrl != null && m.avatarUrl != ""
                                        ? NetworkImage(m.avatarUrl!)
                                        : null,
                                    child:
                                        m.avatarUrl == null || m.avatarUrl == ""
                                        ? Text(
                                            m.name.isNotEmpty
                                                ? m.name[0].toUpperCase()
                                                : '?',
                                            style: TextStyle(
                                              color: m.color,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          )
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                m.name,
                                //style: theme.textTheme.labelSmall,
                                style: TextStyle(
                                  color: Platform.isIOS
                                      ? Colors.white
                                      : Colors.black,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          DraggableScrollableSheet(
            controller: _sheetController,
            initialChildSize: 0.32,
            minChildSize: 0.14,
            maxChildSize: 0.80,
            snap: true,
            snapSizes: const [0.32],
            snapAnimationDuration: const Duration(milliseconds: 280),
            builder: (context, scrollController) {
              final m = _selectedMember;
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.white, Color(0xFFF1F5F9)],
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 20,
                      offset: const Offset(0, -4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  child: ListView(
                    controller: scrollController,
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 5,
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      if (m == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(child: Text('No member selected')),
                        )
                      else
                        _MemberDetailCard(
                          member: m,
                          speedUnitKmh: widget.speedUnitKmh,
                        ),
                      if (widget.members.length > 1) ...[
                        const SizedBox(height: 20),
                        Text('All members', style: theme.textTheme.titleSmall),
                        const SizedBox(height: 8),
                        ...widget.members.map(
                          (mem) => _MemberListTile(
                            member: mem,
                            selected: mem.id == _selectedMemberId,
                            speedUnitKmh: widget.speedUnitKmh,
                            onTap: () => _focusMember(mem),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),

          // Recenter / fit-all FAB.
          // Positioned(
          //   right: 16,
          //   bottom: 0,
          //   child: SafeArea(
          //     minimum: const EdgeInsets.only(bottom: 260),
          //     child: FloatingActionButton.small(
          //       heroTag: 'life360-fit-all',
          //       onPressed: _fitAllMembers,
          //       child: const Icon(Icons.center_focus_strong),
          //     ),
          //   ),
          // ),
          // Positioned(
          //   right: 70,
          //   bottom: 0,
          //   child: SafeArea(
          //     minimum: const EdgeInsets.only(bottom: 260),
          //     child: FloatingActionButton.small(
          //       heroTag: 'add-location',
          //       onPressed: () async {
          //         final prefs = await SharedPreferences.getInstance();
          //
          //         final familyId = prefs.getString('last_family_id');
          //         if (familyId == null) {
          //           return;
          //         }
          //         final added = await Navigator.push<bool>(
          //           context,
          //           MaterialPageRoute(
          //             builder: (_) => AddPlaceScreen(
          //               familyId: familyId ?? "",
          //               repository: PlacesRepository(Supabase.instance.client),
          //             ),
          //           ),
          //         );
          //       },
          //       child: const Icon(Icons.add),
          //     ),
          //   ),
          // ),
          // Positioned(
          //   left: 16,
          //   bottom: 0,
          //   child: SafeArea(
          //     minimum: const EdgeInsets.only(bottom: 260),
          //     child: GestureDetector(
          //       onTap: () async {
          //         setState(() {
          //           isLoad = true;
          //         });
          //         final position = await _getCurrentPosition();
          //
          //         if (position == null) {
          //           setState(() {
          //             isLoad = false;
          //           });
          //           return;
          //         }
          //         setState(() {
          //           isLoad = false;
          //         });
          //         final prefs = await SharedPreferences.getInstance();
          //         final familyId = prefs.getString('last_family_id');
          //         final checkedIn = await Navigator.push<bool>(
          //           context,
          //           MaterialPageRoute(
          //             builder: (context) => CheckInScreen(
          //               familyId: familyId ?? "",
          //               placesRepository: PlacesRepository(
          //                 Supabase.instance.client,
          //               ),
          //               checkInService: CheckInService(
          //                 Supabase.instance.client,
          //               ),
          //               placesSearch: GooglePlacesSearch(
          //                 'AIzaSyDaiR-2trfsS9oVK7ed0MnxhD9YRnOaQCk',
          //               ),
          //               currentLat: position
          //                   .latitude /* your current lat, e.g. from your last GPS fix */,
          //               currentLng: position.longitude /* your current lng */,
          //             ),
          //           ),
          //         );
          //         if (checkedIn == true) {
          //           await showGeneralDialog(
          //             context: context,
          //             barrierDismissible: false,
          //             barrierLabel: 'Check-in completed',
          //             barrierColor: Colors.black54,
          //             transitionDuration: const Duration(milliseconds: 400),
          //             pageBuilder: (context, animation, secondaryAnimation) {
          //               return const SizedBox();
          //             },
          //             transitionBuilder:
          //                 (context, animation, secondaryAnimation, child) {
          //                   final curvedAnimation = CurvedAnimation(
          //                     parent: animation,
          //                     curve: Curves.elasticOut,
          //                   );
          //
          //                   return ScaleTransition(
          //                     scale: curvedAnimation,
          //                     child: FadeTransition(
          //                       opacity: animation,
          //                       child: Center(
          //                         child: Material(
          //                           color: Colors.transparent,
          //                           child: Container(
          //                             width: 280,
          //                             padding: const EdgeInsets.symmetric(
          //                               horizontal: 24,
          //                               vertical: 28,
          //                             ),
          //                             decoration: BoxDecoration(
          //                               color: Colors.white,
          //                               borderRadius: BorderRadius.circular(24),
          //                             ),
          //                             child: Column(
          //                               mainAxisSize: MainAxisSize.min,
          //                               children: [
          //                                 Container(
          //                                   width: 72,
          //                                   height: 72,
          //                                   decoration: BoxDecoration(
          //                                     color: Colors.green.withValues(
          //                                       alpha: 0.12,
          //                                     ),
          //                                     shape: BoxShape.circle,
          //                                   ),
          //                                   child: const Icon(
          //                                     Icons.check_rounded,
          //                                     color: Colors.green,
          //                                     size: 48,
          //                                   ),
          //                                 ),
          //
          //                                 const SizedBox(height: 18),
          //
          //                                 const Text(
          //                                   'Check-in Done!',
          //                                   style: TextStyle(
          //                                     fontSize: 22,
          //                                     fontWeight: FontWeight.bold,
          //                                   ),
          //                                 ),
          //
          //                                 const SizedBox(height: 8),
          //
          //                                 const Text(
          //                                   'Your location has been checked in successfully.',
          //                                   textAlign: TextAlign.center,
          //                                   style: TextStyle(
          //                                     fontSize: 14,
          //                                     color: Colors.grey,
          //                                   ),
          //                                 ),
          //
          //                                 const SizedBox(height: 22),
          //
          //                                 SizedBox(
          //                                   width: double.infinity,
          //                                   child: ElevatedButton(
          //                                     onPressed: () {
          //                                       Navigator.of(context).pop();
          //                                     },
          //                                     style: ElevatedButton.styleFrom(
          //                                       backgroundColor: Colors.green,
          //                                       foregroundColor: Colors.white,
          //                                       padding:
          //                                           const EdgeInsets.symmetric(
          //                                             vertical: 13,
          //                                           ),
          //                                       shape: RoundedRectangleBorder(
          //                                         borderRadius:
          //                                             BorderRadius.circular(12),
          //                                       ),
          //                                     ),
          //                                     child: const Text(
          //                                       'Done',
          //                                       style: TextStyle(
          //                                         fontWeight: FontWeight.w600,
          //                                       ),
          //                                     ),
          //                                   ),
          //                                 ),
          //                               ],
          //                             ),
          //                           ),
          //                         ),
          //                       ),
          //                     ),
          //                   );
          //                 },
          //           );
          //         }
          //       },
          //       child: Container(
          //         padding: EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          //         decoration: BoxDecoration(
          //           borderRadius: BorderRadius.circular(20),
          //           color: Colors.white,
          //           boxShadow: [
          //             BoxShadow(
          //               color: Colors.grey.shade300,
          //               blurRadius: 0.8,
          //               spreadRadius: 0.8,
          //               offset: Offset(0, 0.4),
          //             ),
          //           ],
          //         ),
          //         child: isLoad
          //             ? Center(
          //                 child: SizedBox(
          //                   height: 25,
          //                   width: 25,
          //
          //                   child: CircularProgressIndicator(),
          //                 ),
          //               )
          //             : Row(
          //                 children: [
          //                   Icon(
          //                     Icons.location_on_outlined,
          //                     color: ShieldColors.activeTeal,
          //                     size: 18,
          //                   ),
          //                   Text(
          //                     "Check in",
          //                     style: TextStyle(color: ShieldColors.activeTeal),
          //                   ),
          //                 ],
          //               ),
          //       ),
          //     ),
          //   ),
          // ),
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return ValueListenableBuilder<double>(
                  valueListenable: _sheetExtent,
                  builder: (context, extent, _) {
                    final visible = extent < 0.5;
                    final bottom = extent * constraints.maxHeight + 12;

                    return Stack(
                      children: [
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: bottom,
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) =>
                                FadeTransition(
                                  opacity: animation,
                                  child: SlideTransition(
                                    position: Tween<Offset>(
                                      begin: const Offset(0, 0.6),
                                      end: Offset.zero,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                ),
                            child: visible
                                ? Row(
                                    key: const ValueKey('actions-visible'),
                                    children: [
                                      _buildCheckInButton(),
                                      const Spacer(),
                                      FloatingActionButton.small(
                                        backgroundColor: Colors.white,
                                        heroTag: 'add-location',
                                        onPressed: _onAddPlaceTap,
                                        child: const Icon(
                                          Icons.add,
                                          color: ShieldColors.activeTeal,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      FloatingActionButton.small(
                                        heroTag: 'life360-fit-all',
                                        onPressed: _fitAllMembers,
                                        child: const Icon(
                                          Icons.center_focus_strong,
                                        ),
                                      ),
                                    ],
                                  )
                                : const SizedBox.shrink(
                                    key: ValueKey('actions-hidden'),
                                  ),
                          ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),

      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 0,
        // 'Location' tab, since this IS the location/map screen
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          switch (index) {
            case 0:
              break; // already here
            case 1:
              // final members = widget.members
              //     .where((m) => m.role.toLowerCase() != 'leader')
              //     .toList();

              if (widget.members.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'No family members available for driving reports',
                    ),
                  ),
                );
                return;
              }
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => WeeklyDrivingReportScreen(
                    members: widget.members.map((m) {
                      return (userId: m.id, name: m.name, color: m.color);
                    }).toList(),
                    repository: DrivingReportRepository(
                      Supabase.instance.client,
                    ),
                  ),
                ),
              );
              break;
            case 2:
              // Safety screen — not built yet
              break;
            case 3:
              // Membership screen — not built yet
              break;
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.location_on),
            label: 'Location',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.directions_car),
            label: 'Driving',
          ),
          // BottomNavigationBarItem(icon: Icon(Icons.shield), label: 'Safety'),
          // BottomNavigationBarItem(icon: Icon(Icons.star), label: 'Membership'),
        ],
      ),
      // Bottom detail sheet.
      // bottomSheet: DraggableScrollableSheet(
      //   controller: _sheetController,
      //   initialChildSize: 0.32,
      //   minChildSize: 0.14,
      //   maxChildSize: 0.62,
      //   builder: (context, scrollController) {
      //     final m = _selectedMember;
      //     return Container(
      //       decoration: BoxDecoration(
      //         color: theme.colorScheme.surface,
      //         borderRadius: const BorderRadius.vertical(
      //           top: Radius.circular(20),
      //         ),
      //         boxShadow: const [
      //           BoxShadow(color: Colors.black26, blurRadius: 12),
      //         ],
      //       ),
      //       child: ListView(
      //         controller: scrollController,
      //         padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      //         children: [
      //           Center(
      //             child: Container(
      //               width: 40,
      //               height: 4,
      //               margin: const EdgeInsets.only(bottom: 12),
      //               decoration: BoxDecoration(
      //                 color: theme.dividerColor,
      //                 borderRadius: BorderRadius.circular(2),
      //               ),
      //             ),
      //           ),
      //           if (m == null)
      //             const Padding(
      //               padding: EdgeInsets.symmetric(vertical: 24),
      //               child: Center(child: Text('No member selected')),
      //             )
      //           else
      //             _MemberDetailCard(
      //               member: m,
      //               speedUnitKmh: widget.speedUnitKmh,
      //             ),
      //           if (widget.members.length > 1) ...[
      //             const SizedBox(height: 20),
      //             Text('All members', style: theme.textTheme.titleSmall),
      //             const SizedBox(height: 8),
      //             ...widget.members.map(
      //               (mem) => _MemberListTile(
      //                 member: mem,
      //                 selected: mem.id == _selectedMemberId,
      //                 speedUnitKmh: widget.speedUnitKmh,
      //                 onTap: () => _focusMember(mem),
      //               ),
      //             ),
      //           ],
      //         ],
      //       ),
      //     );
      //   },
      // ),
    );
  }
}

// ---------------------------------------------------------------------------
// DETAIL CARD (speed, address, battery, last updated)
// ---------------------------------------------------------------------------

class _MemberDetailCard extends StatelessWidget {
  const _MemberDetailCard({required this.member, required this.speedUnitKmh});

  final MemberLocation member;
  final bool speedUnitKmh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final speedText = speedUnitKmh
        ? '${member.speedKmh.toStringAsFixed(0)} km/h'
        : '${(member.speedKmh * 0.621371).toStringAsFixed(0)} mph';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),

      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 5,
            spreadRadius: 0.5,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: member.color.withValues(alpha: 0.15),
                backgroundImage:
                    member.avatarUrl != null && member.avatarUrl != ""
                    ? NetworkImage(member.avatarUrl!)
                    : null,
                child: member.avatarUrl == "" || member.avatarUrl == null
                    ? Text(
                        member.name.isNotEmpty
                            ? member.name[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          color: member.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(member.name, style: theme.textTheme.titleMedium),
                    Text(
                      'Updated ${_relativeTime(member.lastUpdated)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusPill(status: member.effectiveStatus),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.speed,
                  label: 'Speed',
                  value: speedText,
                ),
              ),
              if (member.batteryPercent != null)
                Expanded(
                  child: _StatTile(
                    icon: member.batteryPercent! < 20
                        ? Icons.battery_alert
                        : Icons.battery_std,
                    label: 'Battery',
                    value: '${member.batteryPercent!.toStringAsFixed(0)}%',
                    valueColor: member.batteryPercent! < 20
                        ? Colors.redAccent
                        : null,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (member.address != null) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Last trip ended at", style: theme.textTheme.bodySmall),
                SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.location_on, size: 18, color: theme.hintColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        member.address!,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
          ],
          // Row(
          //   children: [
          //     Icon(Icons.my_location, size: 16, color: theme.hintColor),
          //     const SizedBox(width: 6),
          //     Text(
          //       '${member.latitude.toStringAsFixed(5)}, '
          //           '${member.longitude.toStringAsFixed(5)}',
          //       style: theme.textTheme.bodySmall?.copyWith(
          //         color: theme.hintColor,
          //       ),
          //     ),
          //   ],
          // ),
        ],
      ),
    );
  }

  //
  static String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return DateFormat('MMM d, h:mm a').format(dt);
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    this.valueColor,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 22, color: theme.hintColor),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                color: valueColor,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final MovementStatus status;

  @override
  Widget build(BuildContext context) {
    late final Color color;
    late final IconData icon;
    late final String label;
    switch (status) {
      case MovementStatus.driving:
        color = Colors.orange;
        icon = Icons.directions_car;
        label = 'Driving';
        break;
      case MovementStatus.walking:
        color = Colors.blue;
        icon = Icons.directions_walk;
        label = 'Walking';
        break;
      case MovementStatus.stopped:
        color = Colors.red;
        icon = Icons.stop_circle_outlined;
        label = 'Stopped';
        break;
      case MovementStatus.unknown:
        color = Colors.grey;
        icon = Icons.help_outline;
        label = '—';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberListTile extends StatelessWidget {
  const _MemberListTile({
    required this.member,
    required this.selected,
    required this.speedUnitKmh,
    required this.onTap,
  });

  final MemberLocation member;
  final bool selected;
  final bool speedUnitKmh;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final speedText = speedUnitKmh
        ? '${member.speedKmh.toStringAsFixed(0)} km/h'
        : '${(member.speedKmh * 0.621371).toStringAsFixed(0)} mph';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.20),
            blurRadius: 3,
            spreadRadius: 1,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.white,
          child: ListTile(
            onTap: onTap,
            selected: selected,
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: member.color.withValues(alpha: 0.15),
              backgroundImage:
                  member.avatarUrl != null && member.avatarUrl != ""
                  ? NetworkImage(member.avatarUrl!)
                  : null,
              child: member.avatarUrl == "" || member.avatarUrl == null
                  ? Text(
                      member.name.isNotEmpty
                          ? member.name[0].toUpperCase()
                          : '?',
                      style: TextStyle(color: member.color),
                    )
                  : null,
            ),
            title: Text(member.name),
            subtitle: Text(member.address ?? speedText),
            trailing: _StatusPill(status: member.effectiveStatus),
          ),
        ),
      ),
    );
  }
}
