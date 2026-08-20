import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:well_check_v3/core/design/shield_theme.dart';
import 'package:well_check_v3/core/data/user_profile_provider.dart';
import 'package:well_check_v3/core/data/medication_provider.dart';
import 'package:well_check_v3/core/notifications/medication_notification_service.dart';
import 'package:intl/intl.dart';

class AddMedicationSheet extends ConsumerStatefulWidget {
  final Medication? existingMedication; // ADD THIS

  const AddMedicationSheet({super.key, this.existingMedication});

  @override
  ConsumerState<AddMedicationSheet> createState() => _AddMedicationSheetState();
}

class _AddMedicationSheetState extends ConsumerState<AddMedicationSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _dosageController = TextEditingController();
  final _instructionsController = TextEditingController();
  final _doctorController = TextEditingController();

  bool _isLoading = false;
  bool _isLoadingMembers = true;
  String? _selectedUserId;
  String? _selectedUserName;
  List<Map<String, dynamic>> _familyMembers = [];

  // Schedule fields
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _isOngoing = true;
  String _recurrence = 'daily';
  List<TimeOfDay> _scheduleTimes = [const TimeOfDay(hour: 8, minute: 0)];
  List<int> _selectedDays = []; // 0=Sun..6=Sat

  static const _recurrenceOptions = [
    ('daily', 'Daily'),
    ('every_other_day', 'Every Other Day'),
    ('weekly', 'Weekly'),
    ('monthly', 'Monthly'),
    ('as_needed', 'As Needed'),
  ];

  static const _dayLabels = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

  @override
  void initState() {
    super.initState();
    _fetchFamilyMembers();
    final med = widget.existingMedication;
    if (med != null) {
      _nameController.text = med.medicationName;
      _selectedUserId = med.assignedTo;
      _selectedUserName = med.assignedName;
      _dosageController.text = med.dosage;
      _instructionsController.text = med.instructions ?? '';
      _doctorController.text = med.doctor ?? '';
      _recurrence = med.recurrence;
      _startDate = med.startDate!;
      _endDate = med.endDate;
      _isOngoing = med.endDate == null;
      _selectedDays = List<int>.from(med.daysOfWeek ?? []);
      _scheduleTimes = med.scheduleTimes.map((s) {
        final parts = s.split(':');
        return TimeOfDay(
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
        );
      }).toList();
    }
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
            _selectedUserId = me.isNotEmpty
                ? me.first['user_id']
                : _familyMembers.first['user_id'];
            _selectedUserName = me.isNotEmpty
                ? me.first['profiles']['full_name']
                : _familyMembers.first['profiles']['full_name'];
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching members: $e');
      if (mounted) setState(() => _isLoadingMembers = false);
    }
    final med = widget.existingMedication;
    if (med != null) {
      _selectedUserId = med.assignedTo;
      _selectedUserName = med.assignedName;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _dosageController.dispose();
    _instructionsController.dispose();
    _doctorController.dispose();
    super.dispose();
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(
          2, '0')}';

  String _formatTimeDisplay(TimeOfDay t) {
    final period = t.hour >= 12 ? 'PM' : 'AM';
    final hour = t.hour == 0 ? 12 : (t.hour > 12 ? t.hour - 12 : t.hour);
    return '$hour:${t.minute.toString().padLeft(2, '0')} $period';
  }

  Future<void> _pickStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (ctx, child) =>
          Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: Theme
                  .of(
                ctx,
              )
                  .colorScheme
                  .copyWith(primary: ShieldColors.activeTeal),
            ),
            child: child!,
          ),
    );
    if (picked != null && mounted) setState(() => _startDate = picked);
  }

  Future<void> _pickEndDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate ?? _startDate.add(const Duration(days: 30)),
      firstDate: _startDate,
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
      builder: (ctx, child) =>
          Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: Theme
                  .of(
                ctx,
              )
                  .colorScheme
                  .copyWith(primary: ShieldColors.activeTeal),
            ),
            child: child!,
          ),
    );
    if (picked != null && mounted) setState(() => _endDate = picked);
  }

  Future<void> _addTimeSlot() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 12, minute: 0),
      builder: (ctx, child) =>
          Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: Theme
                  .of(
                ctx,
              )
                  .colorScheme
                  .copyWith(primary: ShieldColors.activeTeal),
            ),
            child: child!,
          ),
    );
    if (picked != null && mounted) {
      setState(() {
        _scheduleTimes.add(picked);
        _scheduleTimes.sort(
              (a, b) =>
              (a.hour * 60 + a.minute).compareTo(b.hour * 60 + b.minute),
        );
      });
    }
  }

  DateTime _calculateFirstScheduleDate(DateTime startDate,
      TimeOfDay time,
      String recurrence,
      List<int> selectedDays,) {
    var date = DateTime(
      startDate.year,
      startDate.month,
      startDate.day,
      time.hour,
      time.minute,
    );

    switch (recurrence) {
      case 'weekly':
        if (selectedDays.isNotEmpty) {
          final currentDay = date.weekday % 7; // Sunday=0

          int? nextDay;

          for (final d in selectedDays) {
            if (d >= currentDay) {
              nextDay = d;
              break;
            }
          }

          nextDay ??= selectedDays.first + 7;

          final diff = nextDay - currentDay;

          date = date.add(Duration(days: diff));
        }
        break;

      case 'every_other_day':
        break;

      case 'daily':
        break;

      case 'monthly':
        break;
    }

    return date;
  }

  Future<void> _saveMedication() async {
    if (!_formKey.currentState!.validate() || _selectedUserId == null) {
      if (_selectedUserId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a family member.')),
        );
      }
      return;
    }

    if (_scheduleTimes.isEmpty && _recurrence != 'as_needed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one schedule time.')),
      );
      return;
    }
    if (_scheduleTimes.isEmpty && _recurrence != 'as_needed') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one schedule time.')),
      );
      return;
    }

// --- New: validate start date isn't in the past ---
    final today = DateTime.now();
    final todayDateOnly = DateTime(today.year, today.month, today.day);
    final startDateOnly = DateTime(
        _startDate.year, _startDate.month, _startDate.day);

    if (startDateOnly.isBefore(todayDateOnly)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start date cannot be in the past.')),
      );
      return;
    }

// If start date is today, make sure at least one schedule time is still upcoming
    if (startDateOnly.isAtSameMomentAs(todayDateOnly) &&
        _scheduleTimes.isNotEmpty &&
        _recurrence != 'as_needed') {
      final hasUpcomingTime = _scheduleTimes.any((t) {
        final scheduled = DateTime(
          today.year,
          today.month,
          today.day,
          t.hour,
          t.minute,
        );
        return scheduled.isAfter(today);
      });

      if (!hasUpcomingTime) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'All selected times for today have already passed. Please pick a later time or start date.',
            ),
          ),
        );
        return;
      }
    }
    setState(() => _isLoading = true);

    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      if (profile == null) throw Exception('No profile found');
      debugPrint("_selectedUserId");
      debugPrint(_selectedUserId);
      final timeStrings = _scheduleTimes.map(_formatTime).toList();
      DateTime? utcDateTime;

      if (_recurrence != 'as_needed' && _scheduleTimes.isNotEmpty) {
        final firstTime = _scheduleTimes.first;

        final nextDate = _calculateFirstScheduleDate(
          _startDate,
          firstTime,
          _recurrence,
          _selectedDays,
        );

        // utcDateTime = DateTime.utc(
        //   nextDate.year,
        //   nextDate.month,
        //   nextDate.day,
        //   nextDate.hour,
        //   nextDate.minute,
        // );

        utcDateTime = nextDate.toUtc();
      }
      // Build frequency string for backward compatibility
      final freqLabel = _recurrenceOptions
          .firstWhere(
            (r) => r.$1 == _recurrence,
        orElse: () => ('daily', 'Daily'),
      )
          .$2;
      final freqStr = _scheduleTimes.isNotEmpty
          ? '${_scheduleTimes.length}x $freqLabel'
          : freqLabel;
      final isEditing = widget.existingMedication != null;

      if (isEditing) {
        await Supabase.instance.client
            .from('medications')
            .update({
          'family_id': profile.familyId,
          'assigned_to': _selectedUserId,
          'assigned_name': _selectedUserName,

          'medication_name': _nameController.text.trim(),
          'dosage': _dosageController.text.trim(),
          'frequency': freqStr,
          'instructions': _instructionsController.text
              .trim()
              .isEmpty
              ? null
              : _instructionsController.text.trim(),
          'doctor': _doctorController.text
              .trim()
              .isEmpty
              ? null
              : _doctorController.text.trim(),
          'schedule_times': timeStrings,
          'start_date': DateFormat('yyyy-MM-dd').format(_startDate),
          'end_date': _isOngoing
              ? null
              : (_endDate != null
              ? DateFormat('yyyy-MM-dd').format(_endDate!)
              : null),
          'recurrence': _recurrence,
          'days_of_week': _selectedDays,
          'is_active': true,
          'scheduled_at': utcDateTime?.toIso8601String(),
          'reminder_sent': false,
        })
            .eq('id', widget.existingMedication!.id);
        // final response = await Supabase.instance.client.functions.invoke(
        //   'medication-reminder-cron',
        //   body: {"medication_id": widget.existingMedication!.id},
        // );
        //
        // debugPrint("[Medication] response:");
        // debugPrint(response.data.toString());
      } else {
        final medication = await Supabase.instance.client
            .from('medications')
            .insert({
          'family_id': profile.familyId,
          'assigned_to': _selectedUserId,
          'assigned_name': _selectedUserName,
          'medication_name': _nameController.text.trim(),
          'dosage': _dosageController.text.trim(),
          'frequency': freqStr,
          'instructions': _instructionsController.text
              .trim()
              .isEmpty
              ? null
              : _instructionsController.text.trim(),
          'doctor': _doctorController.text
              .trim()
              .isEmpty
              ? null
              : _doctorController.text.trim(),
          'schedule_times': timeStrings,
          'start_date': DateFormat('yyyy-MM-dd').format(_startDate),
          'end_date': _isOngoing
              ? null
              : (_endDate != null
              ? DateFormat('yyyy-MM-dd').format(_endDate!)
              : null),
          'recurrence': _recurrence,
          'days_of_week': _selectedDays,
          'is_active': true,
          'scheduled_at': utcDateTime?.toIso8601String(),
          'reminder_sent': false,
        })
            .select()
            .single();
        // final response = await Supabase.instance.client.functions.invoke(
        //   'medication-reminder-cron',
        //   body: {"medication_id": medication['id']},
        // );
        //
        // debugPrint("[Medication] response:");
        // debugPrint(response.data.toString());
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isEditing ? "Updated successfully" : 'Medication saved.',
          ),
          backgroundColor: ShieldColors.activeTeal,
        ),
      );
      debugPrint(
        '[Medication] Saved with schedule: $timeStrings, recurrence: $_recurrence',
      );

      // 1. If assigned to self, schedule local notifications natively
      if (_selectedUserId == profile.userId) {
        try {
          final allMeds = await Supabase.instance.client
              .from('medications')
              .select()
              .eq('family_id', profile.familyId)
              .eq('is_active', true);
          final medList = allMeds.map((e) => Medication.fromJson(e)).toList();
          await MedicationNotificationService.scheduleForMedications(medList);
          debugPrint(
            '[Medication] Notifications scheduled locally for ${medList
                .length} active medications',
          );
        } catch (e) {
          debugPrint('[Medication] Local Notification scheduling failed: $e');
        }
      } else {
        // 2. If assigned to someone else, trigger a cloud push notification so they know
        try {
          await Supabase.instance.client.functions.invoke(
            'push-router',
            body: {
              'target_user_id': _selectedUserId,
              'title': 'New Medication Scheduled',
              'body':
              '${profile.fullName ??
                  'Someone'} assigned you $freqStr of ${_nameController.text
                  .trim()}',
              'action': 'new_assignment',
            },
          );
          debugPrint(
            '[Medication] Sent assignment push notification via Edge Function',
          );
          final res = await Supabase.instance.client
              .from('profiles')
              .select('fcm_token')
              .eq('id', _selectedUserId!)
              .single();

          if (res['fcm_token'] == null) {
            debugPrint("User has no FCM token");
            return;
          }
          // await Supabase.instance.client.functions.invoke(
          //   'push-router',
          //   body: {
          //     "target_user_id": _selectedUserId.toString(),
          //     "title": "New Medication Scheduled",
          //     "body": "...",
          //     //"action": "new_assignment",
          //   },
          // );
          debugPrint(
            '[Medication] Sent assignment push notification via Edge Function',
          );
        } catch (e) {
          debugPrint('[Medication] Failed to send push-router invocation: $e');
        }
      }

      if (mounted) context.pop();
    } catch (e) {
      debugPrint('[Medication] ERROR saving: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving medication: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
          ),
        );
      }
      return;
    }

    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,

        title: Text(
          'Add Medication',
          style: Theme
              .of(context)
              .textTheme
              .titleLarge
              ?.copyWith(
            fontWeight: FontWeight.bold,
            color: ShieldColors.textBody,
          ),
        ),
      ),
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: ShieldColors.backgroundWhite,
            // borderRadius: BorderRadius.only(
            //   topLeft: Radius.circular(24),
            //   topRight: Radius.circular(24),
            // ),
          ),

          padding: EdgeInsets.fromLTRB(
            24,
            12,
            24,
            0,
            // MediaQuery.of(context).viewInsets.bottom + 32,
          ),
          child: Form(
            key: _formKey,
            child: ListView(
              physics: ScrollPhysics(),
              shrinkWrap: true,
              children: [
                // Drag handle

                // ── ASSIGN TO ──
                _sectionLabel('Assign To'),
                if (_isLoadingMembers)
                  const Center(child: CircularProgressIndicator())
                else
                  if (_familyMembers.isNotEmpty)
                    DropdownButtonFormField<String>(
                      value: _selectedUserId,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: ShieldDesign.roundedTwelve,
                        ),
                        prefixIcon: const Icon(Icons.person),
                      ),

                      items: _familyMembers.map((m) {
                        final name = m['profiles']?['full_name'] ?? 'Unknown';

                        final role = m['role'];

                        return DropdownMenuItem<String>(
                          value: m['user_id'] as String,
                          child: Text('$name ($role)'),
                        );
                      }).toList(),

                      onChanged: (val) {
                        final member = _familyMembers.firstWhere(
                              (m) => m['user_id'] == val,
                        );

                        setState(() {
                          _selectedUserId = val;

                          _selectedUserName = member['profiles']?['full_name'];
                        });
                      },

                      validator: (val) => val == null ? 'Required' : null,
                    ),

                const SizedBox(height: 16),

                // ── MEDICATION INFO ──
                _sectionLabel('Medication Details'),
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Medication Name',
                    border: OutlineInputBorder(
                      borderRadius: ShieldDesign.roundedTwelve,
                    ),
                    prefixIcon: const Icon(Icons.medical_services),
                  ),
                  validator: (val) =>
                  val == null || val.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dosageController,
                  decoration: InputDecoration(
                    labelText: 'Dosage (e.g. 50mg)',
                    border: OutlineInputBorder(
                      borderRadius: ShieldDesign.roundedTwelve,
                    ),
                    prefixIcon: const Icon(Icons.science),
                  ),
                  validator: (val) =>
                  val == null || val.isEmpty ? 'Required' : null,
                ),

                const SizedBox(height: 20),

                // ── SCHEDULE ──
                _sectionLabel('Schedule'),

                // Recurrence picker
                DropdownButtonFormField<String>(
                  value: _recurrence,
                  decoration: InputDecoration(
                    labelText: 'Recurrence',
                    border: OutlineInputBorder(
                      borderRadius: ShieldDesign.roundedTwelve,
                    ),
                    prefixIcon: const Icon(Icons.repeat),
                  ),
                  items: _recurrenceOptions.map((r) {
                    return DropdownMenuItem(value: r.$1, child: Text(r.$2));
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _recurrence = val);
                  },
                ),

                // Days of week (shown for weekly)
                if (_recurrence == 'weekly') ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 6,
                    children: List.generate(7, (i) {
                      final selected = _selectedDays.contains(i);
                      return FilterChip(
                        label: Text(_dayLabels[i]),
                        selected: selected,
                        selectedColor: ShieldColors.activeTeal.withValues(
                          alpha: 0.2,
                        ),
                        checkmarkColor: ShieldColors.activeTeal,
                        onSelected: (val) {
                          setState(() {
                            if (val) {
                              _selectedDays.add(i);
                            } else {
                              _selectedDays.remove(i);
                            }
                            _selectedDays.sort();
                          });
                        },
                      );
                    }),
                  ),
                ],

                const SizedBox(height: 12),

                // Schedule times
                if (_recurrence != 'as_needed') ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Dose Times',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _addTimeSlot,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Time'),
                        style: TextButton.styleFrom(
                          foregroundColor: ShieldColors.activeTeal,
                        ),
                      ),
                    ],
                  ),
                  if (_scheduleTimes.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: ShieldColors.surfaceLight,
                        borderRadius: ShieldDesign.roundedTwelve,
                      ),
                      child: const Text(
                        'Tap "Add Time" to set when doses should be taken.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _scheduleTimes
                          .asMap()
                          .entries
                          .map((entry) {
                        final i = entry.key;
                        final t = entry.value;
                        return Chip(
                          avatar: const Icon(
                            Icons.schedule,
                            size: 16,
                            color: ShieldColors.activeTeal,
                          ),
                          label: Text(
                            _formatTimeDisplay(t),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          backgroundColor: ShieldColors.softMint,
                          deleteIcon: const Icon(Icons.close, size: 16),
                          onDeleted: () {
                            setState(() => _scheduleTimes.removeAt(i));
                            ref.refresh(familyMedicationsProvider);
                          },
                        );
                      }).toList(),
                    ),
                ],

                const SizedBox(height: 16),

                // Date range
                Row(
                  children: [
                    Expanded(
                      child: _dateButton(
                        label: 'Start Date',
                        date: _startDate,
                        onTap: _pickStartDate,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _isOngoing
                          ? _ongoingToggle()
                          : _dateButton(
                        label: 'End Date',
                        date: _endDate,
                        onTap: _pickEndDate,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _isOngoing = !_isOngoing;
                          if (_isOngoing) _endDate = null;
                        });
                      },
                      child: Text(
                        _isOngoing ? 'Set End Date' : 'Make Ongoing',
                        style: const TextStyle(
                          color: ShieldColors.activeTeal,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // ── OPTIONAL DETAILS ──
                _sectionLabel('Optional Details'),
                TextFormField(
                  controller: _instructionsController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: 'Instructions (for AI Voice)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: ShieldDesign.roundedTwelve,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _doctorController,
                  decoration: InputDecoration(
                    labelText: 'Prescribing Doctor',
                    border: OutlineInputBorder(
                      borderRadius: ShieldDesign.roundedTwelve,
                    ),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),

                const SizedBox(height: 28),

                // ── SAVE BUTTON ──
                SizedBox(
                  height: 56,
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _saveMedication,
                    icon: _isLoading
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                        : const Icon(Icons.check_circle),
                    label: const Text(
                      'Save Medication',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ShieldColors.activeTeal,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: ShieldDesign.roundedTwelve,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: ShieldColors.activeTeal,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _dateButton({
    required String label,
    DateTime? date,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: ShieldDesign.roundedTwelve,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: ShieldDesign.roundedTwelve,
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today,
              size: 18,
              color: ShieldColors.activeTeal,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  Text(
                    date != null
                        ? DateFormat('MMM d, yyyy').format(date)
                        : 'Select',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ongoingToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(
          color: ShieldColors.activeTeal.withValues(alpha: 0.3),
        ),
        borderRadius: ShieldDesign.roundedTwelve,
        color: ShieldColors.softMint,
      ),
      child: const Row(
        children: [
          Icon(Icons.all_inclusive, size: 18, color: ShieldColors.activeTeal),
          SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'End Date',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                ),
                Text(
                  'Ongoing',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: ShieldColors.activeTeal,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
