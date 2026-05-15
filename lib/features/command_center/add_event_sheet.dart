import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:intl/intl.dart';

class AddEventSheet extends ConsumerStatefulWidget {
  const AddEventSheet({super.key});

  @override
  ConsumerState<AddEventSheet> createState() => _AddEventSheetState();
}

class _AddEventSheetState extends ConsumerState<AddEventSheet> {
  int _currentStep = 0;
  final _formKey = GlobalKey<FormState>();

  final _titleController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  bool _isLoading = false;
  bool _isLoadingMembers = true;
  String? _selectedUserId; // In MVP we assign to one primary participant
  List<Map<String, dynamic>> _familyMembers = [];
  String _eventType = 'Personal';

  @override
  void initState() {
    super.initState();
    _fetchFamilyMembers();
  }

  Future<void> _fetchFamilyMembers() async {
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) return;

      final res = await Supabase.instance.client
          .from('family_members')
          .select('user_id, role, profiles(full_name)')
          .eq('family_id', profile.familyId);

      if (mounted) {
        setState(() {
          _familyMembers = List<Map<String, dynamic>>.from(res);
          _isLoadingMembers = false;
          if (_familyMembers.isNotEmpty) {
            final me = _familyMembers
                .where((m) => m['user_id'] == profile.userId)
                .toList();
            if (me.isNotEmpty) {
              _selectedUserId = me.first['user_id'];
            } else {
              _selectedUserId = _familyMembers.first['user_id'];
            }
          }
        });
      }
    } catch (e) {
      print("eeeee");
      print(e.toString());
      if (mounted) setState(() => _isLoadingMembers = false);
    }
  }

  Future<void> _saveEvent() async {
    if (!_formKey.currentState!.validate() ||
        _selectedDate == null ||
        _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete all fields (Date & Time required)'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile');

      final finalDateTime = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
        _selectedTime!.hour,
        _selectedTime!.minute,
      );

      final title = _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : _eventType;
      print("profile.familyId");
      print(profile.familyId);
      await Supabase.instance.client.from('calendar_events').insert({
        'family_id': profile.familyId,
        'created_by': profile.userId,
        'title': title,
        'event_datetime': finalDateTime.toUtc().toIso8601String(),
        'location': _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        'participants': _selectedUserId != null ? [_selectedUserId] : [],
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      });
      int level =
      100; // Safe default for simulators and aggressive background iOS policies
      try {
        final battery = Battery();
        level = await battery.batteryLevel;
      } catch (e) {
        debugPrint(
          'Battery info not available over isolate, using default: $e',
        );
      }
      // Emit to family network
      await Supabase.instance.client.from('well_events').insert({
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'event_type': 'calendar',
        'title': 'New Event Scheduled',
        'battery_level': level,

        'description':
            '$title scheduled for ${DateFormat.jm().format(finalDateTime)} on ${DateFormat.yMd().format(finalDateTime)}',
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Appointment Scheduled!'),
            backgroundColor: ShieldColors.safeZoneGreen,
          ),
        );
      }
    } catch (e) {
      print("eeeeeeeee");
      print(e.toString());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null && mounted) {
      setState(() => _selectedTime = picked);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: ShieldColors.backgroundWhite,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.9,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(
            'New Event / Appointment',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Stepper(
              type: StepperType.vertical,
              physics: const ClampingScrollPhysics(),
              currentStep: _currentStep,
              controlsBuilder: (context, details) {
                return Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isLoading
                              ? null
                              : (_currentStep == 3
                                    ? _saveEvent
                                    : details.onStepContinue),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ShieldColors.activeTeal,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: ShieldDesign.roundedTwelve,
                            ),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  _currentStep == 3
                                      ? 'Schedule Event'
                                      : 'Continue',
                                ),
                        ),
                      ),
                      if (_currentStep > 0) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: _isLoading ? null : details.onStepCancel,
                          child: const Text('Back'),
                        ),
                      ],
                    ],
                  ),
                );
              },
              onStepContinue: () {
                if (_currentStep < 3) {
                  setState(() => _currentStep += 1);
                }
              },
              onStepCancel: () {
                if (_currentStep > 0) {
                  setState(() => _currentStep -= 1);
                }
              },
              steps: [
                Step(
                  title: const Text('Select Member'),
                  content: _isLoadingMembers
                      ? const CircularProgressIndicator()
                      : DropdownButtonFormField<String>(
                          value: _selectedUserId,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: ShieldDesign.roundedTwelve,
                            ),
                            prefixIcon: const Icon(Icons.person),
                          ),
                          items: _familyMembers.map((member) {
                            final profileData =
                                member['profiles'] as Map<String, dynamic>?;
                            final name =
                                profileData?['full_name'] ??
                                profileData?['email'] ??
                                'Member';
                            final role = member['role'];
                            return DropdownMenuItem<String>(
                              value: member['user_id'] as String,
                              child: Text('$name ($role)'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            setState(() => _selectedUserId = val);
                          },
                        ),
                  isActive: _currentStep >= 0,
                ),
                Step(
                  title: const Text('Event Type'),
                  content: DropdownButtonFormField<String>(
                    value: _eventType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: ShieldDesign.roundedTwelve,
                      ),
                      prefixIcon: const Icon(Icons.category),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Doctor Appointment',
                        child: Text('Doctor Appointment'),
                      ),
                      DropdownMenuItem(
                        value: 'School Event',
                        child: Text('School Event'),
                      ),
                      DropdownMenuItem(
                        value: 'Personal',
                        child: Text('Personal'),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() => _eventType = val ?? 'Personal');
                    },
                  ),
                  isActive: _currentStep >= 1,
                ),
                Step(
                  title: const Text('Details'),
                  content: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _titleController,
                          decoration: InputDecoration(
                            labelText: 'Custom Title (Optional)',
                            border: OutlineInputBorder(
                              borderRadius: ShieldDesign.roundedTwelve,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _locationController,
                          decoration: InputDecoration(
                            labelText: 'Location / Clinic',
                            border: OutlineInputBorder(
                              borderRadius: ShieldDesign.roundedTwelve,
                            ),
                            prefixIcon: const Icon(Icons.place),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: _pickDate,
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Date',
                                    border: OutlineInputBorder(
                                      borderRadius: ShieldDesign.roundedTwelve,
                                    ),
                                    prefixIcon: const Icon(
                                      Icons.calendar_today,
                                    ),
                                  ),
                                  child: Text(
                                    _selectedDate == null
                                        ? 'Select Date'
                                        : DateFormat.yMd().format(
                                            _selectedDate!,
                                          ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: InkWell(
                                onTap: _pickTime,
                                child: InputDecorator(
                                  decoration: InputDecoration(
                                    labelText: 'Time',
                                    border: OutlineInputBorder(
                                      borderRadius: ShieldDesign.roundedTwelve,
                                    ),
                                    prefixIcon: const Icon(Icons.access_time),
                                  ),
                                  child: Text(
                                    _selectedTime == null
                                        ? 'Select Time'
                                        : _selectedTime!.format(context),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        TextFormField(
                          controller: _notesController,
                          maxLines: 2,
                          decoration: InputDecoration(
                            labelText: 'Notes',
                            alignLabelWithHint: true,
                            border: OutlineInputBorder(
                              borderRadius: ShieldDesign.roundedTwelve,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  isActive: _currentStep >= 2,
                ),
                Step(
                  title: const Text('Confirm'),
                  content: Text(
                    'Will schedule $_eventType for ${_selectedDate != null ? DateFormat.yMd().format(_selectedDate!) : '...'} at ${_selectedTime != null ? _selectedTime!.format(context) : '...'}. Tap Schedule to save to Family Calendar and alert participants.',
                  ),
                  isActive: _currentStep >= 3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
