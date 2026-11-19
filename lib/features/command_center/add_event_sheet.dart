import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:intl/intl.dart';

import '../../core/data/calendar_provider.dart';
import '../../main.dart';

class AddEventSheet extends ConsumerStatefulWidget {
  final CalendarEvent? event;

  const AddEventSheet({super.key, this.event});

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

  // Inline validation state
  bool _memberError = false;
  bool _dateError = false;
  bool _timeError = false;

  @override
  void initState() {
    super.initState();
    if (widget.event != null) {
      final event = widget.event!;

      _titleController.text = event.title;
      _locationController.text = event.location ?? '';
      _notesController.text = event.notes ?? '';

      _selectedDate = event.eventDatetime.toLocal();
      _selectedTime = TimeOfDay.fromDateTime(event.eventDatetime.toLocal());

      _eventType = event.eventType ?? 'Personal';
    }

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
            if (widget.event != null) {
              final participants = widget.event!.participants;

              if (participants != null && participants.isNotEmpty) {
                final participantId = participants.first.toString();

                final exists = _familyMembers.any(
                  (member) => member['user_id'].toString() == participantId,
                );

                _selectedUserId = exists ? participantId : null;
              }
            } else {
              final me = _familyMembers
                  .where((m) => m['user_id'] == profile.userId)
                  .toList();
              if (me.isNotEmpty) {
                _selectedUserId = me.first['user_id'];
              } else {
                _selectedUserId = _familyMembers.first['user_id'];
              }
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Failed to fetch family members: $e');
      if (mounted) setState(() => _isLoadingMembers = false);
    }
  }

  /// Validates a given step. Sets the relevant error flags and returns
  /// whether the step is allowed to proceed.
  bool _validateStep(int step) {
    switch (step) {
      case 0:
        final valid = _selectedUserId != null;
        setState(() => _memberError = !valid);
        return valid;

      // case 2:
      //   final formValid = _formKey.currentState?.validate() ?? true;
      //   final dateValid = _selectedDate != null;
      //   final timeValid = _selectedTime != null;
      //   setState(() {
      //     _dateError = !dateValid;
      //     _timeError = !timeValid;
      //   });
      //   return formValid && dateValid && timeValid;
      case 2:
        final formValid = _formKey.currentState?.validate() ?? true;
        final dateValid = _selectedDate != null;
        final timeValid = _selectedTime != null;
        final tooSoon = _isTooSoon();
        setState(() {
          _dateError = !dateValid;
          _timeError = !timeValid;
          _tooSoonError = tooSoon;
        });
        return formValid && dateValid && timeValid && !tooSoon;
      default:
        return true;
    }
  }

  bool _tooSoonError = false;

  DateTime get _minimumAppointmentTime =>
      DateTime.now().add(const Duration(hours: 1));

  bool _isTooSoon() {
    if (_selectedDate == null || _selectedTime == null) return false;
    final selected = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );
    return selected.isBefore(_minimumAppointmentTime);
  }

  Future<void> _saveEvent() async {
    if (!_validateStep(2)) {
      setState(() => _currentStep = 2);
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
      final now = DateTime.now();
      final minimumAppointmentTime = now.add(const Duration(hours: 1));

      if (finalDateTime.isBefore(minimumAppointmentTime)) {
        //setState(() => _isLoading = false);
        setState(() {
          _isLoading = false;
          _tooSoonError = true;
          _currentStep = 2;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Appointment must be at least 1 hour from now.'),
            ),
          );
        }

        return;
      }
      final title = _titleController.text.trim().isNotEmpty
          ? _titleController.text.trim()
          : _eventType;

      // await Supabase.instance.client.from('calendar_events').insert({
      //   'family_id': profile.familyId,
      //   'created_by': profile.userId,
      //   'title': title,
      //   'event_datetime': finalDateTime.toUtc().toIso8601String(),
      //   'location': _locationController.text.trim().isEmpty
      //       ? null
      //       : _locationController.text.trim(),
      //   'participants': _selectedUserId != null ? [_selectedUserId] : [],
      //   'notes': _notesController.text.trim().isEmpty
      //       ? null
      //       : _notesController.text.trim(),
      // });
      final eventData = {
        'title': title,
        'event_type': _eventType,
        'event_datetime': finalDateTime.toUtc().toIso8601String(),
        'location': _locationController.text.trim().isEmpty
            ? null
            : _locationController.text.trim(),
        'participants': _selectedUserId != null ? [_selectedUserId] : [],
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      };

      if (widget.event == null) {
        // CREATE
        await Supabase.instance.client.from('calendar_events').insert({
          'family_id': profile.familyId,
          'created_by': profile.userId,
          ...eventData,
        });
      } else {
        // EDIT
        await Supabase.instance.client
            .from('calendar_events')
            .update(eventData)
            .eq('id', widget.event!.id);
      }
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
      await logWellEvent(Supabase.instance.client, {
        'family_id': profile.familyId,
        'user_id': profile.userId,
        'event_type': 'calendar',
        'user_name': profile.fullName,
        'title': 'New Event Scheduled',
        'battery_level': level,
        'description':
            '$title scheduled for ${DateFormat.jm().format(finalDateTime)} on ${DateFormat.yMd().format(finalDateTime)}',
      });

      if (mounted) {
        context.pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.event == null
                  ? 'Appointment Scheduled!'
                  : 'Appointment Updated!',
            ),
            backgroundColor: ShieldColors.safeZoneGreen,
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to save event: $e');
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
    FocusManager.instance.primaryFocus?.unfocus();
    final minDate = DateUtils.dateOnly(_minimumAppointmentTime);
    var initial = _selectedDate ?? minDate;
    if (initial.isBefore(minDate)) initial = minDate;

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: minDate,
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _dateError = false;
        _tooSoonError = _isTooSoon();
      });
    }
    // final picked = await showDatePicker(
    //   context: context,
    //   initialDate: _selectedDate ?? DateTime.now(),
    //   firstDate: DateTime.now(),
    //   lastDate: DateTime.now().add(const Duration(days: 365)),
    // );
    // if (picked != null && mounted) {
    //   setState(() {
    //     _selectedDate = picked;
    //     _dateError = false;
    //   });
    // }
  }

  Future<void> _pickTime() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final picked = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedTime = picked;
        _timeError = false;
        _tooSoonError = _isTooSoon();
      });
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.event == null
              ? 'New Event / Appointment'
              : 'Edit Event / Appointment',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            decoration: const BoxDecoration(
              color: ShieldColors.backgroundWhite,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            // padding: EdgeInsets.fromLTRB(
            //   12,
            //   12,
            //   12,
            //   MediaQuery.of(context).viewInsets.bottom + 32,
            // ),
            // constraints: BoxConstraints(
            //   maxHeight: MediaQuery.of(context).size.height * 0.9,
            // ),
            child: Column(
              // mainAxisSize: MainAxisSize.min,
              children: [
                // Container(
                //   width: 40,
                //   height: 4,
                //   margin: const EdgeInsets.only(bottom: 24),
                //   decoration: BoxDecoration(
                //     color: Colors.grey.shade300,
                //     borderRadius: BorderRadius.circular(2),
                //   ),
                // ),
                const SizedBox(height: 16),
                Stepper(
                  type: StepperType.vertical,
                  physics: const ClampingScrollPhysics(),
                  currentStep: _currentStep,
                  controlsBuilder: (context, details) {
                    return Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Row(
                        children: [
                          ElevatedButton(
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
                                        ? (widget.event == null
                                              ? 'Schedule Event'
                                              : 'Update Event')
                                        : 'Continue',
                                  ),
                          ),
                          if (_currentStep > 0) ...[
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: _isLoading
                                  ? null
                                  : details.onStepCancel,
                              child: const Text('Back'),
                            ),
                          ],
                        ],
                      ),
                    );
                  },
                  onStepContinue: () {
                    if (!_validateStep(_currentStep)) return;
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
                    // ---------------------------------------------------------
                    // Step 0 — Select Member
                    // ---------------------------------------------------------
                    Step(
                      title: const Text('Select Member'),
                      isActive: _currentStep >= 0,
                      content: _isLoadingMembers
                          ? const CircularProgressIndicator()
                          : DropdownButtonFormField<String>(
                              isExpanded: true,
                              value: _selectedUserId,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: ShieldDesign.roundedTwelve,
                                ),
                                prefixIcon: const Icon(Icons.person),
                                errorText: _memberError
                                    ? 'Please select a member'
                                    : null,
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
                                  child: Text(
                                    '$name ($role)',
                                    overflow: TextOverflow.ellipsis,

                                    maxLines: 1,
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                setState(() {
                                  _selectedUserId = val;
                                  _memberError = false;
                                });
                              },
                            ),
                    ),

                    // ---------------------------------------------------------
                    // Step 1 — Event Type
                    // ---------------------------------------------------------
                    Step(
                      title: const Text('Event Type'),
                      isActive: _currentStep >= 1,
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
                    ),

                    // ---------------------------------------------------------
                    // Step 2 — Details
                    // ---------------------------------------------------------
                    Step(
                      title: const Text('Details'),
                      isActive: _currentStep >= 2,
                      content: Form(
                        key: _formKey,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(height: 10),
                            TextFormField(
                              controller: _titleController,
                              decoration: InputDecoration(
                                labelText: 'Custom Title (Optional)',
                                border: OutlineInputBorder(
                                  borderRadius: ShieldDesign.roundedTwelve,
                                ),
                              ),
                              validator: (value) {
                                if (value != null && value.trim().length > 60) {
                                  return 'Title must be under 60 characters';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            TextFormField(
                              controller: _locationController,
                              decoration: InputDecoration(
                                labelText: 'Location / Clinic',
                                border: OutlineInputBorder(
                                  borderRadius: ShieldDesign.roundedTwelve,
                                ),
                                prefixIcon: const Icon(Icons.place),
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Location field is required';
                                }
                                if (value != null &&
                                    value.trim().length > 100) {
                                  return 'Location must be under 100 characters';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 18),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: InkWell(
                                    borderRadius: ShieldDesign.roundedTwelve,
                                    onTap: _pickDate,
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'Date',
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              ShieldDesign.roundedTwelve,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.calendar_today,
                                        ),
                                        errorText: _dateError
                                            ? 'Date is required'
                                            : null,
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
                                    borderRadius: ShieldDesign.roundedTwelve,
                                    onTap: _pickTime,
                                    child: InputDecorator(
                                      decoration: InputDecoration(
                                        labelText: 'Time',
                                        border: OutlineInputBorder(
                                          borderRadius:
                                              ShieldDesign.roundedTwelve,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.access_time,
                                        ),
                                        errorText: _timeError
                                            ? 'Time is required'
                                            : null,
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
                            if (_tooSoonError)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: 8,
                                  left: 12,
                                ),
                                child: Text(
                                  'Appointment must be at least 1 hour from now.',
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 18),
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
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Notes field is required';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    // ---------------------------------------------------------
                    // Step 3 — Confirm
                    // ---------------------------------------------------------
                    Step(
                      title: const Text('Confirm'),
                      isActive: _currentStep >= 3,
                      content: Text(
                        'Will schedule $_eventType for '
                        '${_selectedDate != null ? DateFormat.yMd().format(_selectedDate!) : '...'} '
                        'at ${_selectedTime != null ? _selectedTime!.format(context) : '...'}. '
                        'Tap Schedule to save to Family Calendar and alert participants.',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
