import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/storage/local_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/widgets/liquid_glass_card.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/shimmer_skeleton.dart';
import '../auth/providers/auth_provider.dart';
import '../../shared/providers/semesters_provider.dart';
import '../../core/theme/time_format_provider.dart';
import 'providers/setup_provider.dart';

class AcademicSetupScreen extends ConsumerStatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback? onCancel;
  final int? initialSemesterNumber;
  final bool? isReturningUser;

  const AcademicSetupScreen({
    super.key,
    required this.onComplete,
    this.onCancel,
    this.initialSemesterNumber,
    this.isReturningUser,
  });

  @override
  ConsumerState<AcademicSetupScreen> createState() =>
      _AcademicSetupScreenState();
}

class _AcademicSetupScreenState extends ConsumerState<AcademicSetupScreen>
    with WidgetsBindingObserver {
  final LocalStorage _storage = LocalStorage();
  final PageController _pageController = PageController(keepPage: false);
  int _currentStep = 0;
  bool get _isReturningUser =>
      widget.isReturningUser ??
      (ref.read(setupProvider).status?.setupComplete == true);
  bool _isCommitted = false;
  String _cachedUserId = 'default';
  Timer? _draftDebounceTimer;

  // Step 1: Academic Profile
  final _fullNameCtrl = TextEditingController();
  final _universityCtrl = TextEditingController();
  final _courseCtrl = TextEditingController();
  final _studentIdCtrl = TextEditingController();
  int _durationYears = 4;
  int _sessionStart = 2024;
  int _sessionEnd = 2028;

  // Step 2: Semester Context
  int _semesterNumber = 1;
  final _semesterLabelCtrl = TextEditingController(text: '1st Semester');
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now().add(const Duration(days: 180));
  double _minAttendance = 75.0;
  double _personalTarget = 75.0;
  Set<int> _availableSemesterNumbers = {};
  final Map<int, Map<String, dynamic>> _semesterCache = {};
  bool _isLoadingSemesterData = false;

  // Step 3: Subjects Drafts
  final List<Map<String, dynamic>> _subjects = [];

  // Subject form inputs
  final _newSubNameCtrl = TextEditingController();
  final _newSubCodeCtrl = TextEditingController();
  final _newSubFacultyCtrl = TextEditingController();

  // Step 4: Routine / Timetable Drafts
  final List<Map<String, dynamic>> _timetableEntries = [];
  String? _selectedRoutineSubject;
  int _routineDayOfWeek = 0; // 0=Mon
  final _routineStartCtrl = TextEditingController(text: '09:00');
  final _routineEndCtrl = TextEditingController(text: '10:00');
  final _routineRoomCtrl = TextEditingController();
  String?
      _quickAssignTool; // null = no tool selected, 'Break Time' = break, 'subject_name' = subject
  int _classStartHour = 9; // 09:00 AM (default)
  int _classEndHour = 16; // 04:00 PM (default)
  String _startDay = 'Monday'; // Default Monday
  String _endDay = 'Saturday'; // Default Saturday
  final ScrollController _timetableScrollCtrl = ScrollController();

  static const List<String> _allDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  String get _weeklyScheduleType =>
      (_startDay == 'Monday' && _endDay == 'Saturday')
          ? 'mon_sat'
          : (_startDay == 'Monday' && _endDay == 'Friday')
              ? 'mon_fri'
              : 'custom';

  List<int> get _scheduleHours => List.generate(
        (_classEndHour - _classStartHour).clamp(1, 14),
        (i) => _classStartHour + i,
      );

  List<String> get _scheduleDays {
    final sIdx = _allDays.indexOf(_startDay);
    final eIdx = _allDays.indexOf(_endDay);
    if (sIdx != -1 && eIdx != -1 && sIdx <= eIdx) {
      return _allDays.sublist(sIdx, eIdx + 1);
    }
    return const [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday'
    ];
  }

  String _formatHourString(int hour) {
    final h = hour.toString().padLeft(2, '0');
    return '$h:00';
  }

  String _formatHourDisplay(int hour) {
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayH = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayH $period';
  }

  Future<DateTime?> _showThemedDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
  }) {
    return showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate,
      lastDate: lastDate,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.terracotta,
              onPrimary: Colors.white,
              surface: AppColors.surface,
              onSurface: AppColors.ink,
              secondary: AppColors.rose,
              error: AppColors.coral,
            ),
          ),
          child: child!,
        );
      },
    );
  }

  Color _getSubjectColor(String name) {
    if (name.toLowerCase() == 'break time' || name.toLowerCase() == 'break') {
      return AppColors.amber;
    }
    for (final s in _subjects) {
      if (s['name'] == name) {
        return _parseColor(s['color'] as String?);
      }
    }
    return AppColors.terracotta;
  }

  String? _getSubjectCode(String name) {
    if (name.toLowerCase() == 'break time' || name.toLowerCase() == 'break') {
      return 'BREAK';
    }
    for (final s in _subjects) {
      if (s['name'] == name) {
        final code = s['code'] as String?;
        if (code != null && code.trim().isNotEmpty) {
          return code.trim();
        }
      }
    }
    return null;
  }

  Color _parseColor(String? hexString) {
    if (hexString == null || hexString.isEmpty) return AppColors.terracotta;
    try {
      final clean = hexString.replaceAll('#', '');
      if (clean.length == 6) {
        return Color(int.parse('FF$clean', radix: 16));
      }
    } catch (_) {}
    return AppColors.terracotta;
  }

  int? _parseHour(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    final parts = timeStr.split(':');
    return int.tryParse(parts[0]);
  }

  Map<String, dynamic>? _findEntryStartingAt(int dayOfWeek, int hour) {
    final hStr = hour.toString().padLeft(2, '0');
    for (final t in _timetableEntries) {
      if (t['day_of_week'] == dayOfWeek) {
        final st = t['start_time'] as String? ?? '';
        if (st.startsWith(hStr)) {
          return t;
        }
      }
    }
    return null;
  }

  Map<String, dynamic>? _findEntrySpanning(int dayOfWeek, int hour) {
    for (final t in _timetableEntries) {
      if (t['day_of_week'] == dayOfWeek) {
        final startH = _parseHour(t['start_time'] as String?);
        final endH = _parseHour(t['end_time'] as String?);
        if (startH != null && endH != null) {
          if (startH < hour && endH > hour) {
            return t;
          }
        }
      }
    }
    return null;
  }

  // Step 5: Holidays Drafts (empty by default; populated from DB or user input)
  final List<Map<String, dynamic>> _holidays = [];
  final _holidayTitleCtrl = TextEditingController();
  DateTime _holidayStartDate = DateTime.now().add(const Duration(days: 14));
  DateTime _holidayEndDate = DateTime.now().add(const Duration(days: 15));
  final String _holidayCategory = 'University Holiday';

  // Step 3: Color Palette
  String _selectedSubColor = '#C96E5B';
  static const List<String> _subjectColorPalette = [
    '#C96E5B', // Terracotta
    '#72A68A', // Sage
    '#D9A35B', // Amber
    '#4A8B9F', // Ocean
    '#8F7BAE', // Lavender
    '#2A9D8F', // Emerald Teal (refined from former duplicate coral)
    '#9C4A6F', // Mulberry Rose (distinct 7th accent)
  ];

  // Step 6: Starting Attendance Drafts
  final Map<String, int> _startingAttended = {};
  final Map<String, int> _startingConducted = {};
  final Map<String, TextEditingController> _attendedControllers = {};
  final Map<String, TextEditingController> _conductedControllers = {};

  TextEditingController _getAttendedController(
      String subjectName, int currentVal) {
    var ctrl = _attendedControllers[subjectName];
    if (ctrl == null) {
      ctrl = TextEditingController(text: currentVal.toString());
      _attendedControllers[subjectName] = ctrl;
    } else {
      final parsed = int.tryParse(ctrl.text);
      if (parsed != currentVal && !FocusScope.of(context).hasFocus) {
        ctrl.text = currentVal.toString();
      }
    }
    return ctrl;
  }

  TextEditingController _getConductedController(
      String subjectName, int currentVal) {
    var ctrl = _conductedControllers[subjectName];
    if (ctrl == null) {
      ctrl = TextEditingController(text: currentVal.toString());
      _conductedControllers[subjectName] = ctrl;
    } else {
      final parsed = int.tryParse(ctrl.text);
      if (parsed != currentVal && !FocusScope.of(context).hasFocus) {
        ctrl.text = currentVal.toString();
      }
    }
    return ctrl;
  }

  bool _isSubmitting = false;
  String? _errorMessage;
  int _restoringDraftCount = 0;
  bool get _isRestoringDraft => _restoringDraftCount > 0;

  Timer? _debounceSaveTimer;

  void _onFieldChanged() {
    if (_isRestoringDraft) return;
    _debounceSaveTimer?.cancel();
    _debounceSaveTimer = Timer(const Duration(milliseconds: 600), () {
      debugPrint('_debounceSaveTimer fired');
      if (mounted && !_isCommitted) {
        _saveDraft();
      }
    });
  }

  void _onSubNameChanged() {
    if (mounted) setState(() {});
  }

  void _attachListeners() {
    _fullNameCtrl.addListener(_onFieldChanged);
    _universityCtrl.addListener(_onFieldChanged);
    _courseCtrl.addListener(_onFieldChanged);
    _studentIdCtrl.addListener(_onFieldChanged);
    _semesterLabelCtrl.addListener(_onFieldChanged);
    _newSubNameCtrl.addListener(_onFieldChanged);
    _newSubNameCtrl.addListener(_onSubNameChanged);
    _newSubCodeCtrl.addListener(_onFieldChanged);
    _newSubFacultyCtrl.addListener(_onFieldChanged);
    _routineStartCtrl.addListener(_onFieldChanged);
    _routineEndCtrl.addListener(_onFieldChanged);
    _routineRoomCtrl.addListener(_onFieldChanged);
    _holidayTitleCtrl.addListener(_onFieldChanged);
  }

  void _removeListeners() {
    _fullNameCtrl.removeListener(_onFieldChanged);
    _universityCtrl.removeListener(_onFieldChanged);
    _courseCtrl.removeListener(_onFieldChanged);
    _studentIdCtrl.removeListener(_onFieldChanged);
    _semesterLabelCtrl.removeListener(_onFieldChanged);
    _newSubNameCtrl.removeListener(_onFieldChanged);
    _newSubNameCtrl.removeListener(_onSubNameChanged);
    _newSubCodeCtrl.removeListener(_onFieldChanged);
    _newSubFacultyCtrl.removeListener(_onFieldChanged);
    _routineStartCtrl.removeListener(_onFieldChanged);
    _routineEndCtrl.removeListener(_onFieldChanged);
    _routineRoomCtrl.removeListener(_onFieldChanged);
    _holidayTitleCtrl.removeListener(_onFieldChanged);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.initialSemesterNumber != null) {
      _semesterNumber = widget.initialSemesterNumber!;
      _semesterLabelCtrl.text = _formatSemesterLabel(_semesterNumber);
    } else {
      final activeSemNum =
          ref.read(semestersProvider).activeSemester?.semesterNumber;
      if (activeSemNum != null) {
        _semesterNumber = activeSemNum;
        _semesterLabelCtrl.text = _formatSemesterLabel(activeSemNum);
      }
    }
    _attachListeners();
    // Prefill full name from Auth, fetch database baseline, and restore user's local draft
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _restoringDraftCount++;
      try {
        try {
          final user = ref.read(authProvider).user;
          if (user != null && user.id.isNotEmpty) {
            _cachedUserId = user.id;
          }
        } catch (_) {}

        // 1. Fetch server baseline state first
        final auth = ref.read(authProvider);
        if (auth.isAuthenticated && auth.user != null) {
          await _fetchDatabaseSetupData(
              targetSemester: widget.initialSemesterNumber);
        }

        // 2. Load uncommitted draft from local storage AFTER database fetch
        // so that in-progress subjects, timetable, and steps take precedence over DB defaults!
        await _loadDraft();

        if (mounted) {
          try {
            final user = ref.read(authProvider).user;
            if (user != null && _fullNameCtrl.text.isEmpty) {
              setState(() {
                _fullNameCtrl.text = user.fullName;
              });
            }
          } catch (_) {}
        }
        if (_subjects.isNotEmpty &&
            _selectedRoutineSubject == null &&
            mounted) {
          setState(() {
            _selectedRoutineSubject = _subjects[0]['name'] as String;
          });
        }
        _syncPageToCurrentStep();
      } finally {
        _restoringDraftCount--;
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _saveDraft(immediate: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _removeListeners();
    _debounceSaveTimer?.cancel();
    _draftDebounceTimer?.cancel();
    if (!_isCommitted) {
      _executeSaveDraft(allowUnmounted: true);
    }
    _pageController.dispose();
    _fullNameCtrl.dispose();
    _universityCtrl.dispose();
    _courseCtrl.dispose();
    _studentIdCtrl.dispose();
    _semesterLabelCtrl.dispose();
    _newSubNameCtrl.dispose();
    _newSubCodeCtrl.dispose();
    _newSubFacultyCtrl.dispose();
    _routineStartCtrl.dispose();
    _routineEndCtrl.dispose();
    _routineRoomCtrl.dispose();
    _holidayTitleCtrl.dispose();
    _timetableScrollCtrl.dispose();
    for (final c in _attendedControllers.values) {
      c.dispose();
    }
    for (final c in _conductedControllers.values) {
      c.dispose();
    }
    _debounceSaveTimer?.cancel();
    _draftDebounceTimer?.cancel();
    super.dispose();
  }

  String _getUserId() {
    if (mounted) {
      try {
        final user = ref.read(authProvider).user;
        if (user != null && user.id.isNotEmpty) {
          _cachedUserId = user.id;
          return user.id;
        }
      } catch (_) {}
    }
    return _cachedUserId;
  }

  Map<String, dynamic> _serializeDraft() {
    return {
      'current_step': _currentStep,
      // Step 1
      'full_name': _fullNameCtrl.text,
      'university_name': _universityCtrl.text,
      'course_name': _courseCtrl.text,
      'student_id_number': _studentIdCtrl.text,
      'duration_years': _durationYears,
      'session_start': _sessionStart,
      'session_end': _sessionEnd,
      // Step 2
      'semester_number': _semesterNumber,
      'semester_label': _semesterLabelCtrl.text,
      'start_date': _startDate.toIso8601String(),
      'end_date': _endDate.toIso8601String(),
      'min_attendance': _minAttendance,
      'personal_target': _personalTarget,
      'class_start_hour': _classStartHour,
      'class_end_hour': _classEndHour,
      'start_day': _startDay,
      'end_day': _endDay,
      'weekly_schedule_type': _weeklyScheduleType,
      // Step 3
      'subjects': _subjects
          .map((s) => {
                'name': s['name'],
                'code': s['code'],
                'faculty': s['faculty'],
                'color': s['color'] ?? '#C96E5B',
              })
          .toList(),
      'new_sub_name': _newSubNameCtrl.text,
      'new_sub_code': _newSubCodeCtrl.text,
      'new_sub_faculty': _newSubFacultyCtrl.text,
      // Step 4
      'timetable_entries': _timetableEntries
          .map((t) => {
                'subject_name': t['subject_name'],
                'day_of_week': t['day_of_week'],
                'start_time': t['start_time'],
                'end_time': t['end_time'],
                'room': t['room'],
                'class_type': t['class_type'] ?? 'Theory',
                'faculty_name': t['faculty_name'],
              })
          .toList(),
      'routine_day_of_week': _routineDayOfWeek,
      'routine_start': _routineStartCtrl.text,
      'routine_end': _routineEndCtrl.text,
      'routine_room': _routineRoomCtrl.text,
      'selected_routine_subject': _selectedRoutineSubject,
      // Step 5
      'holidays': _holidays
          .map((h) => {
                'title': h['title'],
                'start_date': h['start_date'] is DateTime
                    ? (h['start_date'] as DateTime).toIso8601String()
                    : (h['start_date']?.toString() ??
                        DateTime.now().toIso8601String()),
                'end_date': h['end_date'] is DateTime
                    ? (h['end_date'] as DateTime).toIso8601String()
                    : (h['end_date']?.toString() ??
                        DateTime.now().toIso8601String()),
                'category': h['category'],
                'notes': h['notes'],
              })
          .toList(),
      'holiday_title': _holidayTitleCtrl.text,
      'holiday_start_date': _holidayStartDate.toIso8601String(),
      'holiday_end_date': _holidayEndDate.toIso8601String(),
      // Step 6
      'starting_attended': _startingAttended,
      'starting_conducted': _startingConducted,
    };
  }

  void _restoreDraft(Map<String, dynamic> draft) {
    _restoringDraftCount++;
    try {
      if (!_isReturningUser && _availableSemesterNumbers.isEmpty) {
        final step = draft['current_step'];
        final maxStep = _isReturningUser ? 5 : 6;
        if (step is int && step >= 0 && step <= maxStep) {
          _currentStep = step;
        }
      }

      // Step 1
      if (draft['full_name'] is String &&
          (draft['full_name'] as String).isNotEmpty) {
        _fullNameCtrl.text = draft['full_name'] as String;
      }
      if (draft['university_name'] is String &&
          (draft['university_name'] as String).isNotEmpty) {
        _universityCtrl.text = draft['university_name'] as String;
      }
      if (draft['course_name'] is String &&
          (draft['course_name'] as String).isNotEmpty) {
        _courseCtrl.text = draft['course_name'] as String;
      }
      if (draft['student_id_number'] is String &&
          (draft['student_id_number'] as String).isNotEmpty) {
        _studentIdCtrl.text = draft['student_id_number'] as String;
      }
      if (draft['duration_years'] is int) {
        _durationYears = draft['duration_years'] as int;
      }
      if (draft['session_start'] is int) {
        _sessionStart = draft['session_start'] as int;
      }
      if (draft['session_end'] is int) {
        _sessionEnd = draft['session_end'] as int;
      }

      // Step 2
      if (draft['semester_number'] is int) {
        _semesterNumber = draft['semester_number'] as int;
      }
      if (draft['semester_label'] is String &&
          (draft['semester_label'] as String).isNotEmpty) {
        _semesterLabelCtrl.text = draft['semester_label'] as String;
      }
      if (draft['start_date'] is String) {
        try {
          _startDate = DateTime.parse(draft['start_date'] as String);
        } catch (_) {}
      }
      if (draft['end_date'] is String) {
        try {
          _endDate = DateTime.parse(draft['end_date'] as String);
        } catch (_) {}
      }
      if (draft['min_attendance'] != null) {
        _minAttendance = (draft['min_attendance'] as num).toDouble();
      }
      if (draft['personal_target'] != null) {
        _personalTarget = (draft['personal_target'] as num).toDouble();
      }
      if (draft['class_start_hour'] is int) {
        _classStartHour = draft['class_start_hour'] as int;
      }
      if (draft['class_end_hour'] is int) {
        _classEndHour = draft['class_end_hour'] as int;
      }
      if (draft['start_day'] is String &&
          _allDays.contains(draft['start_day'])) {
        _startDay = draft['start_day'] as String;
      }
      if (draft['end_day'] is String && _allDays.contains(draft['end_day'])) {
        _endDay = draft['end_day'] as String;
      } else if (draft['weekly_schedule_type'] is String) {
        if (draft['weekly_schedule_type'] == 'mon_fri') {
          _startDay = 'Monday';
          _endDay = 'Friday';
        } else {
          _startDay = 'Monday';
          _endDay = 'Saturday';
        }
      }

      // Step 3: Only restore subjects if draft contains non-empty subjects
      if (draft['subjects'] is List && (draft['subjects'] as List).isNotEmpty) {
        _subjects.clear();
        for (final item in draft['subjects'] as List) {
          if (item is Map) {
            _subjects.add({
              'name': item['name'] ?? '',
              'code': item['code'],
              'faculty': item['faculty'],
              'color': item['color'] ?? '#C96E5B',
            });
          }
        }
      }
      if (draft['new_sub_name'] is String) {
        _newSubNameCtrl.text = draft['new_sub_name'] as String;
      }
      if (draft['new_sub_code'] is String) {
        _newSubCodeCtrl.text = draft['new_sub_code'] as String;
      }
      if (draft['new_sub_faculty'] is String) {
        _newSubFacultyCtrl.text = draft['new_sub_faculty'] as String;
      }

      // Step 4: Only restore timetable if draft contains non-empty entries
      if (draft['timetable_entries'] is List &&
          (draft['timetable_entries'] as List).isNotEmpty) {
        _timetableEntries.clear();
        for (final item in draft['timetable_entries'] as List) {
          if (item is Map) {
            final rawType =
                (item['class_type'] as String?)?.toUpperCase() ?? 'THEORY';
            final mappedType = (rawType == 'LAB' ||
                    rawType.contains('LAB') ||
                    rawType.contains('PRACTICAL'))
                ? 'Lab'
                : (rawType == 'UNSPECIFIED' || rawType.contains('OTHER'))
                    ? 'Others'
                    : 'Theory';
            _timetableEntries.add({
              'subject_name': item['subject_name'] ?? '',
              'day_of_week': (item['day_of_week'] as num?)?.toInt() ?? 0,
              'start_time': item['start_time'] ?? '09:00',
              'end_time': item['end_time'] ?? '10:00',
              'room': item['room'] ?? '',
              'class_type': mappedType,
              'faculty_name': item['faculty_name'],
            });
          }
        }
      }
      if (draft['routine_day_of_week'] is int) {
        _routineDayOfWeek = draft['routine_day_of_week'] as int;
      }
      if (draft['routine_start'] is String) {
        _routineStartCtrl.text = draft['routine_start'] as String;
      }
      if (draft['routine_end'] is String) {
        _routineEndCtrl.text = draft['routine_end'] as String;
      }
      if (draft['routine_room'] is String) {
        _routineRoomCtrl.text = draft['routine_room'] as String;
      }
      if (draft['selected_routine_subject'] is String) {
        _selectedRoutineSubject = draft['selected_routine_subject'] as String;
      }

      // Step 5: Restore holidays from draft, but never let stale default suggestions overwrite real DB holidays
      if (draft['holidays'] is List && (draft['holidays'] as List).isNotEmpty) {
        final rawList = (draft['holidays'] as List).whereType<Map>().toList();
        final hasRealHolidays = _holidays.isNotEmpty;
        final isOnlyDefaults = rawList.isNotEmpty &&
            rawList.every(
              (h) =>
                  h['title'] == 'Diwali Break' ||
                  h['title'] == 'Mid-Term Break',
            );

        // If DB already provided holidays or this is a returning/existing semester, ignore hardcoded defaults from draft
        if (!(hasRealHolidays && isOnlyDefaults) &&
            !((_isReturningUser || _availableSemesterNumbers.isNotEmpty) &&
                isOnlyDefaults)) {
          final filteredList = (_isReturningUser ||
                  _availableSemesterNumbers.isNotEmpty ||
                  hasRealHolidays)
              ? rawList
                  .where((h) =>
                      h['title'] != 'Diwali Break' &&
                      h['title'] != 'Mid-Term Break')
                  .toList()
              : rawList;

          if (filteredList.isNotEmpty) {
            _holidays.clear();
            for (final item in filteredList) {
              DateTime? sDate;
              DateTime? eDate;
              if (item['start_date'] is String) {
                try {
                  sDate = DateTime.parse(item['start_date'] as String);
                } catch (_) {}
              }
              if (item['end_date'] is String) {
                try {
                  eDate = DateTime.parse(item['end_date'] as String);
                } catch (_) {}
              }
              if (sDate != null && eDate != null) {
                _holidays.add({
                  'title': item['title'] ?? 'Holiday',
                  'start_date': sDate,
                  'end_date': eDate,
                  'category': (item['category'] == 'Break')
                      ? 'Semester Break'
                      : (item['category'] ?? 'University Holiday'),
                  'notes': item['notes'],
                });
              }
            }
          }
        }
      }
      if (draft['holiday_title'] is String) {
        _holidayTitleCtrl.text = draft['holiday_title'] as String;
      }
      if (draft['holiday_start_date'] is String) {
        try {
          _holidayStartDate =
              DateTime.parse(draft['holiday_start_date'] as String);
        } catch (_) {}
      }
      if (draft['holiday_end_date'] is String) {
        try {
          _holidayEndDate = DateTime.parse(draft['holiday_end_date'] as String);
        } catch (_) {}
      }

      // Step 6: Starting attendance
      if (draft['starting_attended'] is Map &&
          (draft['starting_attended'] as Map).isNotEmpty) {
        _startingAttended.clear();
        (draft['starting_attended'] as Map).forEach((k, v) {
          if (k is String && v is num) {
            _startingAttended[k] = v.toInt();
          }
        });
      }
      if (draft['starting_conducted'] is Map &&
          (draft['starting_conducted'] as Map).isNotEmpty) {
        _startingConducted.clear();
        (draft['starting_conducted'] as Map).forEach((k, v) {
          if (k is String && v is num) {
            _startingConducted[k] = v.toInt();
          }
        });
      }

      // Ensure selected routine subject is valid
      if (_selectedRoutineSubject == null ||
          !_subjects.any((s) => s['name'] == _selectedRoutineSubject)) {
        _selectedRoutineSubject =
            _subjects.isNotEmpty ? _subjects.first['name'] as String : null;
      }
    } finally {
      _restoringDraftCount--;
    }
  }

  void _syncPageToCurrentStep() {
    void doJump() {
      if (mounted &&
          _pageController.hasClients &&
          _pageController.page?.round() != _currentStep) {
        _pageController.jumpToPage(_currentStep);
      }
    }

    if (_pageController.hasClients) {
      doJump();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => doJump());
  }

  void _saveDraft({bool immediate = false}) {
    if (_isCommitted || _isRestoringDraft || _isLoadingSemesterData) return;
    if (immediate) {
      _draftDebounceTimer?.cancel();
      _executeSaveDraft();
      return;
    }
    _draftDebounceTimer?.cancel();
    _draftDebounceTimer = Timer(const Duration(milliseconds: 250), () {
      debugPrint('_draftDebounceTimer fired');
      _executeSaveDraft();
    });
  }

  Future<void> _executeSaveDraft({bool allowUnmounted = false}) async {
    if (_isCommitted ||
        _isRestoringDraft ||
        _isLoadingSemesterData ||
        (!mounted && !allowUnmounted)) {
      return;
    }
    if (_subjects.isEmpty &&
        _timetableEntries.isEmpty &&
        _availableSemesterNumbers.isNotEmpty) {
      return;
    }
    try {
      final userId = _getUserId();
      final draft = _serializeDraft();
      await _storage.saveAcademicSetupDraft(userId, draft);
    } catch (e) {
      debugPrint('Error saving academic setup draft: $e');
    }
  }

  Future<void> _loadDraft() async {
    try {
      final userId = _getUserId();
      final draft = await _storage.getAcademicSetupDraft(userId);
      if (draft != null && mounted) {
        final draftSem = draft['semester_number'];
        if (draftSem is int && draftSem != _semesterNumber) {
          return;
        }
        setState(() {
          _restoreDraft(draft);
        });
        _syncPageToCurrentStep();
      }
    } catch (e) {
      debugPrint('Error loading academic setup draft: $e');
    }
  }

  Future<void> _clearDraft() async {
    _draftDebounceTimer?.cancel();
    try {
      final userId = _getUserId();
      await _storage.clearAcademicSetupDraft(userId);
    } catch (e) {
      debugPrint('Error clearing academic setup draft: $e');
    }
  }

  String _formatSemesterLabel(int num) {
    if (num == 1) return '1st Semester';
    if (num == 2) return '2nd Semester';
    if (num == 3) return '3rd Semester';
    return '${num}th Semester';
  }

  Future<void> _fetchDatabaseSetupData({int? targetSemester}) async {
    if (!mounted) return;
    setState(() => _isLoadingSemesterData = true);
    try {
      final data = await ref
          .read(setupProvider.notifier)
          .fetchSetupData(semesterNumber: targetSemester);
      if (data != null && mounted) {
        final nums = (data['available_semester_numbers'] as List?)
                ?.map((e) => (e as num).toInt())
                .toList() ??
            [];
        _availableSemesterNumbers = nums.toSet();

        final semInfo = data['semester'] as Map<String, dynamic>?;
        final activeSem =
            ref.read(semestersProvider).activeSemester?.semesterNumber;
        final semNum = (semInfo?['semester_number'] as num?)?.toInt() ??
            (targetSemester ?? activeSem ?? _semesterNumber);
        _semesterCache[semNum] = data;

        _applySetupData(data);

        // If visiting first-time after partial setup or semesters exist
        if (!_isReturningUser) {
          final status = ref.read(setupProvider).status;
          final isRevisiting = status?.setupComplete == true || nums.isNotEmpty;
          if (isRevisiting &&
              widget.initialSemesterNumber == null &&
              _currentStep == 0) {
            _currentStep = 1;
          }
        }
      }
    } catch (e) {
      debugPrint('Error fetching academic setup data: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingSemesterData = false);
        _syncPageToCurrentStep();
      }
    }
  }

  void _applySetupData(Map<String, dynamic> data) {
    _restoringDraftCount++;
    try {
      if (data['university_name'] is String &&
          (data['university_name'] as String).isNotEmpty) {
        _universityCtrl.text = data['university_name'] as String;
      }
      if (data['course_name'] is String &&
          (data['course_name'] as String).isNotEmpty) {
        _courseCtrl.text = data['course_name'] as String;
      }
      if (data['full_name'] is String &&
          (data['full_name'] as String).isNotEmpty) {
        _fullNameCtrl.text = data['full_name'] as String;
      }
      if (data['student_id_number'] is String &&
          (data['student_id_number'] as String).isNotEmpty) {
        _studentIdCtrl.text = data['student_id_number'] as String;
      }
      if (data['academic_duration_years'] is int) {
        _durationYears = data['academic_duration_years'] as int;
      }
      if (data['academic_session_start'] is int) {
        _sessionStart = data['academic_session_start'] as int;
      }
      if (data['academic_session_end'] is int) {
        _sessionEnd = data['academic_session_end'] as int;
      }
      if (data['minimum_attendance'] != null) {
        _minAttendance = (data['minimum_attendance'] as num).toDouble();
      }
      if (data['personal_target'] != null) {
        _personalTarget = (data['personal_target'] as num).toDouble();
      }

      final semInfo = data['semester'] as Map<String, dynamic>?;
      if (semInfo != null) {
        _semesterNumber =
            (semInfo['semester_number'] as num?)?.toInt() ?? _semesterNumber;
        if (semInfo['semester_label'] is String) {
          _semesterLabelCtrl.text = semInfo['semester_label'] as String;
        }
        if (semInfo['start_date'] is String) {
          try {
            _startDate = DateTime.parse(semInfo['start_date'] as String);
          } catch (_) {}
        }
        if (semInfo['end_date'] is String) {
          try {
            _endDate = DateTime.parse(semInfo['end_date'] as String);
          } catch (_) {}
        }
        if (semInfo['start_day'] is String &&
            _allDays.contains(semInfo['start_day'])) {
          _startDay = semInfo['start_day'] as String;
        }
        if (semInfo['end_day'] is String &&
            _allDays.contains(semInfo['end_day'])) {
          _endDay = semInfo['end_day'] as String;
        } else if (semInfo['working_days'] is List &&
            (semInfo['working_days'] as List).isNotEmpty) {
          final wList = (semInfo['working_days'] as List)
              .map((e) => (e as num).toInt())
              .toList();
          final minD = wList.reduce((a, b) => a < b ? a : b);
          final maxD = wList.reduce((a, b) => a > b ? a : b);
          if (minD >= 0 && minD < _allDays.length) _startDay = _allDays[minD];
          if (maxD >= 0 && maxD < _allDays.length) _endDay = _allDays[maxD];
        }
        if (semInfo['class_start_hour'] is int) {
          _classStartHour = semInfo['class_start_hour'] as int;
        }
        if (semInfo['class_end_hour'] is int) {
          _classEndHour = semInfo['class_end_hour'] as int;
        }
      }

      if (data['subjects'] is List) {
        _subjects.clear();
        for (final s in data['subjects'] as List) {
          if (s is Map) {
            _subjects.add({
              'name': s['name'] ?? '',
              'code': s['code'],
              'faculty': s['faculty_name'] ?? s['faculty'],
              'color': s['color'] ?? '#C96E5B',
            });
          }
        }
      }

      if (data['timetable_entries'] is List) {
        _timetableEntries.clear();
        for (final t in data['timetable_entries'] as List) {
          if (t is Map) {
            final rawType =
                (t['class_type'] as String?)?.toUpperCase() ?? 'THEORY';
            final mappedType = (rawType == 'LAB' ||
                    rawType.contains('LAB') ||
                    rawType.contains('PRACTICAL'))
                ? 'Lab'
                : (rawType == 'UNSPECIFIED' || rawType.contains('OTHER'))
                    ? 'Others'
                    : 'Theory';
            _timetableEntries.add({
              'subject_name': t['subject_name'] ?? '',
              'day_of_week': (t['day_of_week'] as num?)?.toInt() ?? 0,
              'start_time': t['start_time'] ?? '09:00',
              'end_time': t['end_time'] ?? '10:00',
              'room': t['room'] ?? '',
              'faculty_name': t['faculty_name'],
              'class_type': mappedType,
            });
          }
        }
      }

      if (data['holidays'] is List) {
        _holidays.clear();
        for (final h in data['holidays'] as List) {
          if (h is Map) {
            DateTime? sDate;
            DateTime? eDate;
            if (h['start_date'] is String) {
              try {
                sDate = DateTime.parse(h['start_date'] as String);
              } catch (_) {}
            }
            if (h['end_date'] is String) {
              try {
                eDate = DateTime.parse(h['end_date'] as String);
              } catch (_) {}
            }
            if (sDate != null && eDate != null) {
              _holidays.add({
                'title': h['title'] ?? 'Holiday',
                'start_date': sDate,
                'end_date': eDate,
                'category': (h['category'] == 'Break')
                    ? 'Semester Break'
                    : (h['category'] ?? 'University Holiday'),
                'notes': h['notes'],
              });
            }
          }
        }
        // If returning user or user has semesters in DB, ensure default suggestions never appear
        if (_isReturningUser || _availableSemesterNumbers.isNotEmpty) {
          _holidays.removeWhere((h) =>
              h['title'] == 'Diwali Break' || h['title'] == 'Mid-Term Break');
        }
      }

      _startingAttended.clear();
      _startingConducted.clear();
      if (data['starting_attendance'] is List) {
        for (final sa in data['starting_attendance'] as List) {
          if (sa is Map && sa['subject_name'] is String) {
            final sName = sa['subject_name'] as String;
            _startingAttended[sName] =
                (sa['attended_count'] as num?)?.toInt() ?? 0;
            _startingConducted[sName] =
                (sa['conducted_count'] as num?)?.toInt() ?? 0;
          }
        }
      }

      if (_subjects.isNotEmpty) {
        _selectedRoutineSubject = _subjects.first['name'] as String;
      }
    } finally {
      _restoringDraftCount--;
    }
  }

  Future<void> _changeSemesterNumber(int newSem) async {
    if (newSem < 1 || newSem > (_durationYears * 2)) return;
    if (newSem == _semesterNumber) return;

    setState(() => _isLoadingSemesterData = true);
    try {
      if (_semesterCache.containsKey(newSem)) {
        final cached = _semesterCache[newSem]!;
        setState(() {
          _applySetupData(cached);
          _semesterNumber = newSem;
          _semesterLabelCtrl.text = _formatSemesterLabel(newSem);
        });
      } else {
        final data = await ref
            .read(setupProvider.notifier)
            .fetchSetupData(semesterNumber: newSem);
        if (data != null && mounted) {
          final isExisting =
              (data['semester'] as Map<String, dynamic>?)?['is_existing'] ==
                  true;
          if (isExisting) {
            _semesterCache[newSem] = data;
            setState(() {
              _applySetupData(data);
              _semesterNumber = newSem;
              _semesterLabelCtrl.text = _formatSemesterLabel(newSem);
            });
          } else {
            // New semester term: preserve global fields, reset semester-scoped data
            setState(() {
              _semesterNumber = newSem;
              _semesterLabelCtrl.text = _formatSemesterLabel(newSem);
              _startDate = DateTime.now().subtract(const Duration(days: 60));
              _endDate = DateTime.now().add(const Duration(days: 60));
              _subjects.clear();
              _timetableEntries.clear();
              _holidays.clear();
              _startingAttended.clear();
              _startingConducted.clear();
              _selectedRoutineSubject = null;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error changing semester: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingSemesterData = false);
        _saveDraft();
      }
    }
  }

  String? _getValidRoutineSubject() {
    if (_subjects.isEmpty) return null;
    final availableNames = _subjects.map((s) => s['name'] as String).toSet();
    if (_selectedRoutineSubject != null &&
        availableNames.contains(_selectedRoutineSubject)) {
      return _selectedRoutineSubject;
    }
    return _subjects.first['name'] as String;
  }

  void _addSubject() {
    final name = _newSubNameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a subject name first.'),
          backgroundColor: AppColors.coral,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final isDuplicate = _subjects.any(
      (s) => (s['name'] as String).toLowerCase() == name.toLowerCase(),
    );
    if (isDuplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Subject "$name" is already added.'),
          backgroundColor: AppColors.amber,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() {
      _subjects.add({
        'name': name,
        'code': _newSubCodeCtrl.text.trim().isEmpty
            ? null
            : _newSubCodeCtrl.text.trim(),
        'faculty': _newSubFacultyCtrl.text.trim().isEmpty
            ? null
            : _newSubFacultyCtrl.text.trim(),
        'color': _selectedSubColor,
      });
      _selectedRoutineSubject ??= name;
      _newSubNameCtrl.clear();
      _newSubCodeCtrl.clear();
      _newSubFacultyCtrl.clear();
    });

    FocusScope.of(context).unfocus();
    _saveDraft(immediate: true);
    HapticFeedback.lightImpact();
  }

  void _deleteSubject(int idx) {
    if (idx < 0 || idx >= _subjects.length) return;
    setState(() {
      final removed = _subjects.removeAt(idx);
      final removedName = removed['name'] as String;

      // 1. Remove timetable entries referencing the deleted subject
      _timetableEntries.removeWhere((t) => t['subject_name'] == removedName);

      // 2. Remove starting attendance counters
      _startingAttended.remove(removedName);
      _startingConducted.remove(removedName);

      // 3. Reset _selectedRoutineSubject safely
      if (_selectedRoutineSubject == removedName ||
          !_subjects.any((s) => s['name'] == _selectedRoutineSubject)) {
        _selectedRoutineSubject =
            _subjects.isNotEmpty ? _subjects.first['name'] as String : null;
      }
    });
    _saveDraft(immediate: true);
  }

  void _goToStep(int targetStep) {
    final maxStep = _isReturningUser ? 5 : 6;
    if (targetStep < 0 || targetStep > maxStep) return;
    setState(() => _currentStep = targetStep);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        targetStep,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
    _saveDraft(immediate: true);
  }

  void _nextStep() {
    final maxStep = _isReturningUser ? 5 : 6;
    if (_currentStep < maxStep) {
      _goToStep(_currentStep + 1);
    } else {
      _commitSetup();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _goToStep(_currentStep - 1);
    } else if (widget.onCancel != null) {
      widget.onCancel!();
    }
  }

  Future<void> _commitSetup() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final uni = _universityCtrl.text.trim();
    final course = _courseCtrl.text.trim();
    final semLabel = _semesterLabelCtrl.text.trim();

    final payload = {
      'university_name': uni.isEmpty ? 'Not specified' : uni,
      'course_name': course.isEmpty ? 'Not specified' : course,
      'full_name':
          _fullNameCtrl.text.trim().isEmpty ? null : _fullNameCtrl.text.trim(),
      'student_id_number': _studentIdCtrl.text.trim().isEmpty
          ? null
          : _studentIdCtrl.text.trim(),
      'academic_duration_years': _durationYears,
      'academic_session_start': _sessionStart,
      'academic_session_end': _sessionEnd,
      'semester_number': _semesterNumber,
      'semester_label':
          semLabel.isEmpty ? _formatSemesterLabel(_semesterNumber) : semLabel,
      'start_date': DateFormat('yyyy-MM-dd').format(_startDate),
      'end_date': DateFormat('yyyy-MM-dd').format(_endDate),
      'start_day': _startDay,
      'end_day': _endDay,
      'working_days': _scheduleDays
          .map((d) => _allDays.indexOf(d))
          .where((i) => i != -1)
          .toList(),
      'class_start_hour': _classStartHour,
      'class_end_hour': _classEndHour,
      'minimum_attendance': _minAttendance,
      'personal_target': _personalTarget,
      'low_attendance_alert': 70.0,
      'subjects': _subjects
          .map((s) => {
                'name': (s['name'] as String).trim(),
                'code': (s['code'] as String?)?.trim().isEmpty == true
                    ? null
                    : (s['code'] as String?)?.trim(),
                'faculty_name':
                    (s['faculty'] as String?)?.trim().isEmpty == true
                        ? null
                        : (s['faculty'] as String?)?.trim(),
                'color': s['color'] ?? '#C96E5B',
              })
          .toList(),
      'timetable_entries': _timetableEntries
          .where((t) =>
              t['subject_name'] == 'Break Time' ||
              t['subject_name'] == 'Break' ||
              _subjects.any((s) => s['name'] == t['subject_name']))
          .map((t) => {
                'subject_name': t['subject_name'],
                'day_of_week': t['day_of_week'] is int
                    ? t['day_of_week']
                    : int.tryParse(t['day_of_week'].toString()) ?? 0,
                'start_time': t['start_time'],
                'end_time': t['end_time'],
                'room': t['room'],
                'class_type': t['class_type'] ?? 'Theory',
                'faculty_name': t['faculty_name'],
              })
          .toList(),
      'holidays': _holidays
          .map((h) => {
                'title': (h['title'] as String).trim(),
                'start_date': DateFormat('yyyy-MM-dd')
                    .format(h['start_date'] as DateTime),
                'end_date':
                    DateFormat('yyyy-MM-dd').format(h['end_date'] as DateTime),
                'category': (h['category'] == 'Break')
                    ? 'Semester Break'
                    : (h['category'] ?? 'University Holiday'),
                'notes': h['notes'],
              })
          .toList(),
      'starting_attendance': _subjects
          .map((s) {
            final name = (s['name'] as String).trim();
            return {
              'subject_name': name,
              'attended_count': _startingAttended[name] ?? 0,
              'conducted_count': _startingConducted[name] ?? 0,
            };
          })
          .where((sa) => (sa['conducted_count'] as int) > 0)
          .toList(),
    };

    final success = await ref.read(setupProvider.notifier).commitSetup(payload);

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (success) {
        _isCommitted = true;
        await _clearDraft();
        // All provider invalidations are handled by setup_provider.commitSetup().
        // Do not duplicate here — it causes a 5x dashboard request storm.
        widget.onComplete();
      } else {
        setState(() {
          _errorMessage =
              ref.read(setupProvider).errorMessage ?? 'Failed to save setup.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _currentStep == 0 && widget.onCancel != null,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_currentStep > 0) {
          _goToStep(_currentStep - 1);
        } else if (widget.onCancel != null) {
          widget.onCancel!();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () {
            if (!mounted) return;
            final primaryFocus = FocusManager.instance.primaryFocus;
            if (primaryFocus != null && primaryFocus.hasFocus) {
              primaryFocus.unfocus();
              _saveDraft();
            }
          },
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Prevent RenderFlex overflow during transient micro-constraint frames (e.g. initial web canvas layout)
                if (constraints.maxHeight < 160) {
                  return const SizedBox.shrink();
                }
                return Column(
                  children: [
                    // Top Navigation & Step Indicator
                    _buildTopIndicator(),

                    if (_errorMessage != null)
                      Container(
                        margin: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.coralLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.coral.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline_rounded,
                                color: AppColors.coral, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _errorMessage!,
                                style: const TextStyle(
                                    color: AppColors.coral,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Page View with steps (6 steps for returning students, 7 for first onboarding)
                    Expanded(
                      child: PageView(
                        controller: _pageController,
                        physics: const NeverScrollableScrollPhysics(),
                        onPageChanged: (page) {
                          if (_currentStep != page) {
                            setState(() => _currentStep = page);
                          }
                        },
                        children: [
                          if (!_isReturningUser) _buildStep1Profile(),
                          _buildStep2Semester(),
                          _buildStep3Subjects(),
                          _buildStep4Routine(),
                          _buildStep5Holidays(),
                          _buildStep6Attendance(),
                          _buildStep7Review(),
                        ],
                      ),
                    ),

                    // Bottom Navigation Controls
                    _buildBottomControls(),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopIndicator() {
    final totalSteps = _isReturningUser ? 6 : 7;
    final stepTitles = _isReturningUser
        ? [
            'Semester Term',
            'Subjects',
            'Timetable',
            'Holidays',
            'Initial Attendance',
            'Review & Save',
          ]
        : [
            'Academic Profile',
            'Semester Term',
            'Subjects',
            'Timetable',
            'Holidays',
            'Initial Attendance',
            'Review & Save',
          ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: const BoxDecoration(
        color: AppColors.background,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (_currentStep > 0 || widget.onCancel != null) ...[
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    icon:
                        const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    onPressed: _prevStep,
                    padding: EdgeInsets.zero,
                    tooltip:
                        _currentStep == 0 ? 'Close Setup' : 'Previous Step',
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Text(
                'Step ${_currentStep + 1}/$totalSteps',
                style: const TextStyle(
                  color: AppColors.terracotta,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
              const Text('•', style: TextStyle(color: AppColors.inkMuted)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  stepTitles[_currentStep.clamp(0, stepTitles.length - 1)],
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                key: const Key('academic_setup_cancel_button'),
                onPressed: () {
                  if (widget.onCancel != null) {
                    widget.onCancel!();
                  } else if (Navigator.canPop(context)) {
                    Navigator.pop(context);
                  }
                },
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(44, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    color: AppColors.inkMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Progress indicator
          Row(
            children: List.generate(totalSteps, (idx) {
              final isReached = idx <= _currentStep;
              return Expanded(
                child: Padding(
                  padding:
                      EdgeInsets.only(right: idx < (totalSteps - 1) ? 5 : 0),
                  child: InkWell(
                    key: Key('step_segment_$idx'),
                    onTap: () => _goToStep(idx),
                    borderRadius: BorderRadius.circular(3),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: isReached
                            ? AppColors.terracotta
                            : AppColors.divider,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildStepHeader({
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppColors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final maxStep = _isReturningUser ? 5 : 6;
    final isSubjectsStep =
        _isReturningUser ? _currentStep == 1 : _currentStep == 2;
    final keyboardVisible = MediaQuery.of(context).viewInsets.bottom > 0;

    // When on Step 3 (Subjects) and mobile keyboard is visible,
    // swap the primary action above the keyboard to "Add Subject"
    // so tapping the floating action button adds the subject as expected.
    if (isSubjectsStep && keyboardVisible) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          border: Border(top: BorderSide(color: AppColors.divider)),
          boxShadow: [
            BoxShadow(
              color: AppColors.shadowWarm,
              blurRadius: 8,
              offset: Offset(0, -2),
            ),
          ],
        ),
        child: AppButton(
          key: const Key('bottom_add_subject_button'),
          label: 'Add Subject',
          icon: Icons.add_circle_outline_rounded,
          showArrow: false,
          onPressed: _addSubject,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: AppButton(
        label: _currentStep == maxStep
            ? (_isSubmitting ? 'Saving Setup...' : 'Confirm Configuration')
            : 'Continue to Step ${_currentStep + 2}',
        isLoading: _isSubmitting,
        onPressed: _isSubmitting ? null : _nextStep,
      ),
    );
  }

  // STEP 1: GLOBAL PROFILE
  Widget _buildStep1Profile() {
    return SingleChildScrollView(
      physics: const ClampingScrollPhysics(),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeader(
            title: 'Academic Profile',
            subtitle:
                'Configure your institutional details. These settings apply globally across all your semesters.',
          ),
          AppTextField(
            label: 'Full Name',
            controller: _fullNameCtrl,
            hint: 'Your full name',
            prefixIcon: const Icon(Icons.person_outline_rounded,
                size: 20, color: AppColors.inkMuted),
            onEditingComplete: () {
              FocusScope.of(context).unfocus();
              _saveDraft();
            },
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'University / College Name',
            controller: _universityCtrl,
            hint: 'e.g. Apex Technical University',
            prefixIcon: const Icon(Icons.account_balance_outlined,
                size: 20, color: AppColors.inkMuted),
            onEditingComplete: () {
              FocusScope.of(context).unfocus();
              _saveDraft();
            },
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Course / Degree Program',
            controller: _courseCtrl,
            hint: 'e.g. B.Tech Computer Science & Engineering',
            prefixIcon: const Icon(Icons.school_outlined,
                size: 20, color: AppColors.inkMuted),
            onEditingComplete: () {
              FocusScope.of(context).unfocus();
              _saveDraft();
            },
          ),
          const SizedBox(height: 14),
          AppTextField(
            label: 'Student ID / Roll Number (Optional)',
            controller: _studentIdCtrl,
            hint: 'e.g. ADTU/2024/001',
            prefixIcon: const Icon(Icons.badge_outlined,
                size: 20, color: AppColors.inkMuted),
            onEditingComplete: () {
              FocusScope.of(context).unfocus();
              _saveDraft();
            },
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Degree Duration',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: _durationYears,
                          isExpanded: true,
                          items: [1, 2, 3, 4, 5, 6].map((y) {
                            return DropdownMenuItem(
                                value: y, child: Text('$y Years'));
                          }).toList(),
                          onChanged: (val) {
                            setState(() => _durationYears = val ?? 4);
                            _saveDraft();
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Session Span',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: '$_sessionStart-$_sessionEnd',
                          isExpanded: true,
                          items: [
                            '2022-2026',
                            '2023-2027',
                            '2024-2028',
                            '2025-2029',
                            '2026-2030'
                          ].map((span) {
                            return DropdownMenuItem(
                                value: span, child: Text(span));
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              final parts = val.split('-');
                              setState(() {
                                _sessionStart = int.parse(parts[0]);
                                _sessionEnd = int.parse(parts[1]);
                              });
                              _saveDraft();
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // STEP 2: SEMESTER
  Widget _buildStep2Semester() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeader(
            title: 'Semester & Attendance Rules',
            subtitle: 'Define your current academic term and attendance goals.',
          ),

          // Big Squared Card for Semester Stepper
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.divider, width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadowWarm,
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                const Text(
                  'Semester',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.inkMuted,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Minus Stepper Button [-]
                    Material(
                      color: _semesterNumber > 1
                          ? const Color(0xFFF7F1EC)
                          : AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: (_semesterNumber > 1 && !_isLoadingSemesterData)
                            ? () => _changeSemesterNumber(_semesterNumber - 1)
                            : null,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.remove_rounded,
                            size: 24,
                            color: _semesterNumber > 1
                                ? AppColors.terracotta
                                : AppColors.inkMuted.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ),

                    // Big Center Semester Title & Status
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            _formatSemesterLabel(_semesterNumber),
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                              letterSpacing: -0.4,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: _availableSemesterNumbers
                                      .contains(_semesterNumber)
                                  ? AppColors.sage.withValues(alpha: 0.15)
                                  : AppColors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              _availableSemesterNumbers
                                      .contains(_semesterNumber)
                                  ? 'Saved in Records'
                                  : 'New Semester Term',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: _availableSemesterNumbers
                                        .contains(_semesterNumber)
                                    ? AppColors.sage
                                    : AppColors.amber,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Plus Stepper Button [+]
                    Material(
                      color: _semesterNumber < (_durationYears * 2)
                          ? const Color(0xFFF7F1EC)
                          : AppColors.surfaceAlt,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        onTap: (_semesterNumber < (_durationYears * 2) &&
                                !_isLoadingSemesterData)
                            ? () => _changeSemesterNumber(_semesterNumber + 1)
                            : null,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          width: 48,
                          height: 48,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.add_rounded,
                            size: 24,
                            color: _semesterNumber < (_durationYears * 2)
                                ? AppColors.terracotta
                                : AppColors.inkMuted.withValues(alpha: 0.3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_isLoadingSemesterData) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(
                    color: AppColors.terracotta,
                    backgroundColor: Color(0xFFF7F1EC),
                    minHeight: 2.5,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),

          // College / Semester Term Dates (Start & End)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadowWarm,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.terracotta.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.calendar_today_rounded,
                          color: AppColors.terracotta, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Expected Semester Timings',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.ink),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Specify college start and end dates to calculate semester progress and forecasts accurately.',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    // Start Date Field
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _startDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                            builder: (context, child) => Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: AppColors.terracotta,
                                  onPrimary: Colors.white,
                                  surface: AppColors.surface,
                                ),
                              ),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setState(() {
                              _startDate = picked;
                              if (_endDate.isBefore(_startDate)) {
                                _endDate =
                                    _startDate.add(const Duration(days: 120));
                              }
                            });
                            _saveDraft();
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('College / Term Start',
                                  style: TextStyle(
                                      fontSize: 11, color: AppColors.inkMuted)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.event_available_rounded,
                                      size: 16, color: AppColors.terracotta),
                                  const SizedBox(width: 6),
                                  Text(
                                    DateFormat('dd MMM yyyy')
                                        .format(_startDate),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: AppColors.ink),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // End Date Field
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _endDate,
                            firstDate: _startDate,
                            lastDate: DateTime(2030),
                            builder: (context, child) => Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: const ColorScheme.light(
                                  primary: AppColors.terracotta,
                                  onPrimary: Colors.white,
                                  surface: AppColors.surface,
                                ),
                              ),
                              child: child!,
                            ),
                          );
                          if (picked != null) {
                            setState(() => _endDate = picked);
                            _saveDraft();
                          }
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceAlt,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.divider),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('College / Term End',
                                  style: TextStyle(
                                      fontSize: 11, color: AppColors.inkMuted)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.event_busy_rounded,
                                      size: 16, color: AppColors.amberDark),
                                  const SizedBox(width: 6),
                                  Text(
                                    DateFormat('dd MMM yyyy').format(_endDate),
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13,
                                        color: AppColors.ink),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // College Schedule & Working Days Framework (Compulsory)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.terracotta.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.schedule_rounded,
                          color: AppColors.terracotta, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Timings',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.ink),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Configures your timetable grid slots and active academic days.',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Section 1: Class Timings (Start & End)
                const Text('Class Timings',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // Field 1: Start Time (Default 9 AM)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Start Time',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.inkMuted)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: _classStartHour,
                                isExpanded: true,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.ink),
                                items: const [
                                  DropdownMenuItem(
                                      value: 7,
                                      child: Text('7 AM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 8,
                                      child: Text('8 AM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 9,
                                      child: Text('9 AM (Default)',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 10,
                                      child: Text('10 AM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 11,
                                      child: Text('11 AM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 12,
                                      child: Text('12 PM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 13,
                                      child: Text('1 PM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 14,
                                      child: Text('2 PM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _classStartHour = val;
                                      if (_classEndHour <= _classStartHour) {
                                        _classEndHour =
                                            (_classStartHour + 1).clamp(8, 22);
                                      }
                                    });
                                    _saveDraft();
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Field 2: End Time (Default 4 PM)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('End Time',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.inkMuted)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<int>(
                                value: _classEndHour,
                                isExpanded: true,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.ink),
                                items: const [
                                  DropdownMenuItem(
                                      value: 12,
                                      child: Text('12 PM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 13,
                                      child: Text('1 PM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 14,
                                      child: Text('2 PM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 15,
                                      child: Text('3 PM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 16,
                                      child: Text('4 PM (Default)',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 17,
                                      child: Text('5 PM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 18,
                                      child: Text('6 PM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 19,
                                      child: Text('7 PM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 20,
                                      child: Text('8 PM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                  DropdownMenuItem(
                                      value: 21,
                                      child: Text('9 PM',
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.ink))),
                                ],
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _classEndHour = val;
                                      if (_classStartHour >= _classEndHour) {
                                        _classStartHour =
                                            (_classEndHour - 1).clamp(6, 20);
                                      }
                                    });
                                    _saveDraft();
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Section 2: Working Days (Start & End)
                const Text('Working Days',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    // Field 1: Day Wise Start (Default Monday)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Day Wise Start',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.inkMuted)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _startDay,
                                isExpanded: true,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.ink),
                                items: _allDays.map((d) {
                                  return DropdownMenuItem(
                                    value: d,
                                    child: Text(
                                      d == 'Monday' ? '$d (Default)' : d,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.ink),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _startDay = val;
                                      final sIdx = _allDays.indexOf(_startDay);
                                      final eIdx = _allDays.indexOf(_endDay);
                                      if (sIdx > eIdx) {
                                        _endDay = _startDay;
                                      }
                                    });
                                    _saveDraft();
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Field 2: Day End (Default Saturday)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Day End',
                              style: TextStyle(
                                  fontSize: 11, color: AppColors.inkMuted)),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<String>(
                                value: _endDay,
                                isExpanded: true,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.ink),
                                items: _allDays.map((d) {
                                  return DropdownMenuItem(
                                    value: d,
                                    child: Text(
                                      d == 'Saturday' ? '$d (Default)' : d,
                                      style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.ink),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) {
                                    setState(() {
                                      _endDay = val;
                                      final sIdx = _allDays.indexOf(_startDay);
                                      final eIdx = _allDays.indexOf(_endDay);
                                      if (eIdx < sIdx) {
                                        _startDay = _endDay;
                                      }
                                    });
                                    _saveDraft();
                                  }
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Attendance Targets & Goals
          LiquidGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.terracotta.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.verified_user_outlined,
                          color: AppColors.terracotta, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Attendance Targets & Goals',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.ink),
                          ),
                          Text(
                            'Institutional minimum & your personal attendance goal',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Bar 1: Mandatory Minimum (Terracotta)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Mandatory Minimum',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.terracottaLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.terracotta.withValues(alpha: 0.2)),
                      ),
                      child: Text(
                        '${_minAttendance.toStringAsFixed(1)}% Required',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: AppColors.terracottaDark),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                    'University threshold required to be eligible for exams.',
                    style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: AppColors.terracotta,
                    inactiveTrackColor: AppColors.sand,
                    thumbColor: AppColors.terracotta,
                    overlayColor: AppColors.terracotta.withValues(alpha: 0.12),
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8, elevation: 1.5),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 16),
                  ),
                  child: Slider(
                    value: _minAttendance,
                    min: 60.0,
                    max: 90.0,
                    divisions: 30,
                    onChanged: (v) => setState(() => _minAttendance = v),
                    onChangeEnd: (_) => _saveDraft(),
                  ),
                ),
                const SizedBox(height: 10),

                // Bar 2: Personal Target (Warm Amber, replacing green)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Personal Target',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.ink)),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.amberLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: AppColors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        '${_personalTarget.toStringAsFixed(1)}% Goal',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: Color(0xFF9E681A)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                    'Your aspirational target to maintain a safe attendance margin.',
                    style: TextStyle(fontSize: 11, color: AppColors.inkMuted)),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 6,
                    activeTrackColor: AppColors.amber,
                    inactiveTrackColor: AppColors.sand,
                    thumbColor: AppColors.amber,
                    overlayColor: AppColors.amber.withValues(alpha: 0.12),
                    thumbShape: const RoundSliderThumbShape(
                        enabledThumbRadius: 8, elevation: 1.5),
                    overlayShape:
                        const RoundSliderOverlayShape(overlayRadius: 16),
                  ),
                  child: Slider(
                    value: _personalTarget,
                    min: 60.0,
                    max: 95.0,
                    divisions: 35,
                    onChanged: (v) => setState(() => _personalTarget = v),
                    onChangeEnd: (_) => _saveDraft(),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    const Text('Quick presets:',
                        style:
                            TextStyle(fontSize: 11, color: AppColors.inkMuted)),
                    ...[75.0, 80.0, 85.0, 90.0].map((preset) {
                      final isSelected = (_personalTarget - preset).abs() < 0.5;
                      return InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          setState(() => _personalTarget = preset);
                          _saveDraft();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.amberLight
                                : AppColors.surface,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.amber
                                  : AppColors.divider,
                              width: 1,
                            ),
                          ),
                          child: Text(
                            preset == 75.0
                                ? '75% (Default)'
                                : '${preset.toInt()}%',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? const Color(0xFF9E681A)
                                  : AppColors.inkSecondary,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // STEP 3: SUBJECTS
  Widget _buildStep3Subjects() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeader(
            title: 'Enroll Subjects',
            subtitle:
                'Add all subjects for this semester in one place. You can edit or remove subjects anytime.',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.terracotta.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_subjects.length} Enrolled',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppColors.terracotta),
              ),
            ),
          ),

          // Add Subject Inline Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadowWarm,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.terracotta.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.menu_book_rounded,
                          color: AppColors.terracotta, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add New Subject',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.ink),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Configure subject identity, code and faculty',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                AppTextField(
                  label: 'Subject Name (Required)',
                  controller: _newSubNameCtrl,
                  hint: 'e.g. Computer Networks',
                  prefixIcon: const Icon(Icons.bookmark_border_rounded,
                      size: 20, color: AppColors.inkMuted),
                  onTapOutside: (_) {
                    FocusScope.of(context).unfocus();
                    _saveDraft();
                  },
                  onEditingComplete: _addSubject,
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        label: 'Code (Optional)',
                        controller: _newSubCodeCtrl,
                        hint: 'e.g. CS-504',
                        prefixIcon: const Icon(Icons.tag_rounded,
                            size: 18, color: AppColors.inkMuted),
                        onTapOutside: (_) {
                          FocusScope.of(context).unfocus();
                          _saveDraft();
                        },
                        onEditingComplete: _addSubject,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppTextField(
                        label: 'Faculty (Optional)',
                        controller: _newSubFacultyCtrl,
                        hint: 'e.g. Prof. Ahmed',
                        prefixIcon: const Icon(Icons.person_outline_rounded,
                            size: 18, color: AppColors.inkMuted),
                        onTapOutside: (_) {
                          FocusScope.of(context).unfocus();
                          _saveDraft();
                        },
                        onEditingComplete: _addSubject,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Subject Accent Color Palette
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Text('Color Accent',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.ink)),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '• Tap to select identity tint',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.inkMuted),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: _subjectColorPalette.map((colorHex) {
                          final isSelected = _selectedSubColor == colorHex;
                          final colorVal = _parseColor(colorHex);
                          return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: InkWell(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _selectedSubColor = colorHex);
                              },
                              borderRadius: BorderRadius.circular(18),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: colorVal,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.ink
                                        : Colors.white,
                                    width: isSelected ? 2.5 : 1.5,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: colorVal.withValues(
                                          alpha: isSelected ? 0.45 : 0.22),
                                      blurRadius: isSelected ? 6 : 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: isSelected
                                    ? const Icon(Icons.check_rounded,
                                        size: 18, color: Colors.white)
                                    : null,
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // High-impact Add Subject button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [
                          Color(0xFFE26B55),
                          Color(0xFFCE5944),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.terracotta.withValues(alpha: 0.32),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _addSubject,
                        borderRadius: BorderRadius.circular(12),
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add_circle_outline_rounded,
                                  color: Colors.white, size: 19),
                              SizedBox(width: 8),
                              Text(
                                'Add Subject',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          // Enrolled Subjects Section Header
          if (_isLoadingSemesterData && _subjects.isEmpty)
            const Padding(
              padding: EdgeInsets.only(bottom: 12, top: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.terracotta,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'Loading Enrolled Subjects...',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: AppColors.inkSecondary,
                    ),
                  ),
                ],
              ),
            )
          else if (_subjects.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12, top: 4),
              child: Row(
                children: [
                  const Text(
                    'Enrolled Subjects',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.terracotta.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_subjects.length}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.terracotta,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // List of added subjects / Loading Skeleton / Empty State
          if (_isLoadingSemesterData && _subjects.isEmpty)
            ShimmerLoading(
              child: Column(
                children: List.generate(
                  3,
                  (index) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: const Row(
                      children: [
                        SkeletonBox(
                          width: 36,
                          height: 36,
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SkeletonBox.text(width: 140, height: 13),
                              SizedBox(height: 6),
                              SkeletonBox.text(width: 80, height: 10),
                            ],
                          ),
                        ),
                        SkeletonBox(
                          width: 30,
                          height: 30,
                          borderRadius: BorderRadius.all(Radius.circular(8)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else if (_subjects.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.auto_stories_outlined,
                        size: 40,
                        color: AppColors.inkMuted.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    const Text(
                      'No subjects enrolled yet',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.ink),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Add at least one subject above to proceed with timetable and attendance tracking.',
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ..._subjects.asMap().entries.map((entry) {
              final idx = entry.key;
              final sub = entry.value;
              final subColor = _parseColor(sub['color'] as String?);
              final code = sub['code'] as String?;
              final faculty = sub['faculty'] as String?;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: subColor.withValues(alpha: 0.25),
                    width: 1.2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: subColor.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                    const BoxShadow(
                      color: AppColors.shadowWarm,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 10,
                      bottom: 10,
                      width: 4.5,
                      child: Container(
                        decoration: BoxDecoration(
                          color: subColor,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(4),
                            bottomRight: Radius.circular(4),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  subColor.withValues(alpha: 0.20),
                                  subColor.withValues(alpha: 0.08),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: subColor.withValues(alpha: 0.28),
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Icon(Icons.menu_book_rounded,
                                  color: subColor, size: 20),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  sub['name'] as String,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 15,
                                    color: AppColors.ink,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 5),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 4,
                                  children: [
                                    if (code != null && code.trim().isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color:
                                              subColor.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: subColor.withValues(
                                                  alpha: 0.24)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.tag_rounded,
                                                size: 10.5, color: subColor),
                                            const SizedBox(width: 3),
                                            Text(
                                              code.trim().toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w700,
                                                color: subColor,
                                                letterSpacing: 0.3,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if (faculty != null &&
                                        faculty.trim().isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 7, vertical: 2.5),
                                        decoration: BoxDecoration(
                                          color: AppColors.surfaceAlt,
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          border: Border.all(
                                              color: AppColors.divider),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                                Icons.person_outline_rounded,
                                                size: 11,
                                                color: AppColors.inkMuted),
                                            const SizedBox(width: 3),
                                            Text(
                                              faculty.trim(),
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                fontWeight: FontWeight.w600,
                                                color: AppColors.inkSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    if ((code == null || code.trim().isEmpty) &&
                                        (faculty == null ||
                                            faculty.trim().isEmpty))
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.sandLight
                                              .withValues(alpha: 0.6),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          'Subject #${idx + 1}',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: AppColors.inkMuted,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _deleteSubject(idx);
                              },
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppColors.coralLight
                                      .withValues(alpha: 0.7),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color:
                                        AppColors.coral.withValues(alpha: 0.25),
                                    width: 1,
                                  ),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.delete_outline_rounded,
                                    color: AppColors.coral,
                                    size: 19,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildQuickToolChip({
    required String label,
    IconData? icon,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('quick_tool_$label'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.18)
                : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : AppColors.divider,
              width: isSelected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 14, color: isSelected ? color : AppColors.inkMuted),
                const SizedBox(width: 5),
              ] else ...[
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: isSelected ? color : AppColors.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic>? _findConflictingEntry({
    required int dayOfWeek,
    required int startHour,
    required int endHour,
    Map<String, dynamic>? ignoreEntry,
  }) {
    for (final entry in _timetableEntries) {
      if (identical(entry, ignoreEntry)) continue;
      if (entry['day_of_week'] != dayOfWeek) continue;

      final eStart = _parseHour(entry['start_time'] as String?);
      final eEnd = _parseHour(entry['end_time'] as String?);
      if (eStart == null || eEnd == null) continue;

      // Intervals [startHour, endHour) and [eStart, eEnd) overlap if startHour < eEnd && endHour > eStart
      if (startHour < eEnd && endHour > eStart) {
        return entry;
      }
    }
    return null;
  }

  void _handleSlotTap(int dayIdx, int hour,
      {Map<String, dynamic>? existingEntry}) {
    if (_quickAssignTool != null) {
      final isBreak = _quickAssignTool == 'Break Time';
      final startTimeStr = _formatHourString(hour);
      final endTimeStr = _formatHourString(hour + 1);

      // Check what is currently at this slot
      final entryStarting = _findEntryStartingAt(dayIdx, hour);
      final entrySpanning = _findEntrySpanning(dayIdx, hour);
      final activeMatch = existingEntry ?? entryStarting ?? entrySpanning;
      final currentSubject = activeMatch?['subject_name'] as String?;

      // 1. TOGGLE TO BLANK: If same subject is already in this slot, tapping again removes it and makes it blank!
      if (currentSubject != null && currentSubject == _quickAssignTool) {
        setState(() {
          if (existingEntry != null) {
            _timetableEntries.remove(existingEntry);
          }
          if (entryStarting != null) {
            _timetableEntries.remove(entryStarting);
          }
          if (entrySpanning != null) {
            _timetableEntries.remove(entrySpanning);
          }
          _timetableEntries.removeWhere(
            (t) {
              if (t['day_of_week'] != dayIdx) return false;
              final sH = _parseHour(t['start_time'] as String?);
              final eH = _parseHour(t['end_time'] as String?);
              return sH != null && eH != null && hour >= sH && hour < eH;
            },
          );
        });
        _saveDraft(immediate: true);
        HapticFeedback.lightImpact();
        AppToast.showTopRight(
          context,
          'Removed "$currentSubject" from ${_scheduleDays[dayIdx.clamp(0, _scheduleDays.length - 1)]} ${_formatHourDisplay(hour)} slot.',
          icon: Icons.delete_sweep_rounded,
          accentColor: AppColors.inkMuted,
        );
        return;
      }

      // 2. CONFLICT CHECK: Cannot overwrite an ongoing multi-hour class spanning into this slot
      if (entrySpanning != null && !identical(entrySpanning, existingEntry)) {
        final spanName = entrySpanning['subject_name'] as String? ?? 'Class';
        final spanStart = entrySpanning['start_time'] as String? ?? '';
        final spanEnd = entrySpanning['end_time'] as String? ?? '';
        AppToast.showConflict(
          context,
          'Slot ${_formatHourDisplay(hour)} is part of a multi-hour class ($spanName $spanStart–$spanEnd). Edit or resize that class first.',
        );
        HapticFeedback.heavyImpact();
        return;
      }

      // 3. Normal quick-assign replacement for this 1-hour slot
      setState(() {
        if (existingEntry != null) {
          _timetableEntries.remove(existingEntry);
        }
        if (entryStarting != null) {
          _timetableEntries.remove(entryStarting);
        }
        _timetableEntries.removeWhere(
          (t) =>
              t['day_of_week'] == dayIdx && _parseHour(t['start_time']) == hour,
        );
        _timetableEntries.add({
          'subject_name': _quickAssignTool!,
          'day_of_week': dayIdx,
          'start_time': startTimeStr,
          'end_time': endTimeStr,
          'class_type': isBreak ? 'Break' : 'Theory',
          'room': isBreak ? '' : 'Room 101',
        });
      });
      _saveDraft(immediate: true);
      HapticFeedback.lightImpact();
      return;
    }

    // No quick assign tool active: open slot editor modal directly
    _openSlotEditor(
        dayOfWeek: dayIdx, startHour: hour, existingEntry: existingEntry);
  }

  // STEP 4: ROUTINE / TIMETABLE
  Widget _buildStep4Routine() {
    final activeDays = _scheduleDays;
    final hours = _scheduleHours;
    const double dayColWidth = 60.0;
    const double hourColWidth = 144.0;
    const double slotHeight = 94.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeader(
            title: 'Weekly Schedule',
            subtitle:
                'Tap any slot to schedule, or pick a Quick-Assign chip below to fast-fill slots.',
          ),

          // Quick-Assign Toolbar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadowWarm,
                    blurRadius: 4,
                    offset: Offset(0, 1)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.touch_app_rounded,
                              size: 16, color: AppColors.terracotta),
                          SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Quick-Assign Tool',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: AppColors.ink),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Clear Selection Button (disabled when null, active when selected)
                    TextButton.icon(
                      key: const Key('clear_selection_button'),
                      onPressed: _quickAssignTool != null
                          ? () {
                              HapticFeedback.lightImpact();
                              setState(() => _quickAssignTool = null);
                            }
                          : null,
                      icon: Icon(
                        Icons.close_rounded,
                        size: 13,
                        color: _quickAssignTool != null
                            ? AppColors.terracotta
                            : AppColors.inkLight.withValues(alpha: 0.5),
                      ),
                      label: Text(
                        'Clear Selection',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _quickAssignTool != null
                              ? AppColors.terracotta
                              : AppColors.inkLight.withValues(alpha: 0.5),
                        ),
                      ),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        backgroundColor: _quickAssignTool != null
                            ? AppColors.terracotta.withValues(alpha: 0.08)
                            : Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                          side: BorderSide(
                            color: _quickAssignTool != null
                                ? AppColors.terracotta.withValues(alpha: 0.4)
                                : AppColors.divider,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    children: [
                      // Tool 1: Break Time
                      _buildQuickToolChip(
                        label: 'Break Time',
                        icon: Icons.coffee_rounded,
                        color: AppColors.amber,
                        isSelected: _quickAssignTool == 'Break Time',
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _quickAssignTool = _quickAssignTool == 'Break Time'
                                ? null
                                : 'Break Time';
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      // Tool 2..N: Enrolled Subjects only
                      ..._subjects.map((sub) {
                        final name = sub['name'] as String;
                        final code = sub['code'] as String?;
                        final col = _parseColor(sub['color'] as String?);
                        final label =
                            (code != null && code.isNotEmpty) ? code : name;
                        final isSel = _quickAssignTool == name;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _buildQuickToolChip(
                            label: label,
                            color: col,
                            isSelected: isSel,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() {
                                _quickAssignTool = isSel ? null : name;
                              });
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Timetable Grid with Fixed Leftmost Day Column and Horizontally Scrollable Hour Slots
          if (_isLoadingSemesterData && _timetableEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: ShimmerLoading(
                child: Container(
                  height: 240,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: const Column(
                    children: [
                      SkeletonBox(
                          width: double.infinity,
                          height: 32,
                          borderRadius: BorderRadius.all(Radius.circular(8))),
                      SizedBox(height: 12),
                      Expanded(
                        child: Row(
                          children: [
                            SkeletonBox(
                                width: 50,
                                height: double.infinity,
                                borderRadius:
                                    BorderRadius.all(Radius.circular(8))),
                            SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                children: [
                                  Expanded(
                                      child: SkeletonBox(
                                          width: double.infinity,
                                          height: double.infinity,
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(8)))),
                                  SizedBox(height: 8),
                                  Expanded(
                                      child: SkeletonBox(
                                          width: double.infinity,
                                          height: double.infinity,
                                          borderRadius: BorderRadius.all(
                                              Radius.circular(8)))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.divider),
                boxShadow: const [
                  BoxShadow(
                    color: AppColors.shadowWarm,
                    blurRadius: 10,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. PINNED / FIXED LEFT DAY COLUMN
                  Container(
                    width: dayColWidth,
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      border: Border(
                        right: BorderSide(color: AppColors.divider, width: 1.0),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Color.fromRGBO(0, 0, 0, 0.03),
                          blurRadius: 3,
                          offset: Offset(1, 0),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Leftmost Day Column Header
                        Container(
                          width: dayColWidth,
                          height: 42,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: AppColors.surface,
                            border: Border(
                              bottom: BorderSide(color: AppColors.divider),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_today_rounded,
                                  size: 11, color: AppColors.terracotta),
                              SizedBox(width: 3),
                              Text(
                                'Day',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.ink),
                              ),
                            ],
                          ),
                        ),

                        // Leftmost Day Label Cells for Each Active Day
                        ...activeDays.map((dayName) {
                          final dayIdx = _allDays.indexOf(dayName);
                          final daySlotsCount = _timetableEntries
                              .where((t) => t['day_of_week'] == dayIdx)
                              .length;

                          return Container(
                            width: dayColWidth,
                            height: slotHeight,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 2, vertical: 6),
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              color: AppColors.surface,
                              border: Border(
                                bottom: BorderSide(color: AppColors.divider),
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  dayName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 10.5,
                                    color: AppColors.ink,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                if (daySlotsCount > 0)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: AppColors.sage
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '$daySlotsCount ${daySlotsCount == 1 ? 'class' : 'classes'}',
                                      style: const TextStyle(
                                        fontSize: 8.0,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.sage,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  )
                                else
                                  const Text(
                                    'No classes',
                                    style: TextStyle(
                                      fontSize: 8.0,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.inkMuted,
                                    ),
                                    maxLines: 1,
                                  ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),

                  // 2. HORIZONTALLY SCROLLABLE HOUR SLOTS
                  Expanded(
                    child: ScrollConfiguration(
                      behavior: ScrollConfiguration.of(context).copyWith(
                        dragDevices: {
                          PointerDeviceKind.touch,
                          PointerDeviceKind.mouse,
                          PointerDeviceKind.trackpad,
                          PointerDeviceKind.stylus,
                        },
                      ),
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        controller: _timetableScrollCtrl,
                        physics: const BouncingScrollPhysics(),
                        child: Container(
                          color: AppColors.surface,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Time Column Headers Across the Top
                              Container(
                                color: AppColors.surface,
                                child: Row(
                                  children: hours.map((hour) {
                                    final nextHour = hour + 1;
                                    return Container(
                                      width: hourColWidth,
                                      height: 42,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6),
                                      alignment: Alignment.center,
                                      decoration: const BoxDecoration(
                                        color: AppColors.surface,
                                        border: Border(
                                          right: BorderSide(
                                              color: AppColors.divider),
                                          bottom: BorderSide(
                                              color: AppColors.divider),
                                        ),
                                      ),
                                      child: Text(
                                        '${_formatHourDisplay(hour)} – ${_formatHourDisplay(nextHour)}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                          color: AppColors.ink,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),

                              // Hour Slots for Each Day (Unified Block Spanning)
                              ...activeDays.map((dayName) {
                                final dayIdx = _allDays.indexOf(dayName);
                                return Row(
                                  children: _buildDayHourCells(
                                      dayIdx, hours, hourColWidth, slotHeight),
                                );
                              }),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // Generates row hour cells, dynamically collapsing multi-hour classes into a single unified spanning block
  List<Widget> _buildDayHourCells(
      int dayIdx, List<int> hours, double hourColWidth, double slotHeight) {
    final cells = <Widget>[];
    int i = 0;
    while (i < hours.length) {
      final hour = hours[i];
      final startingEntry = _findEntryStartingAt(dayIdx, hour);

      if (startingEntry != null) {
        final startH =
            _parseHour(startingEntry['start_time'] as String?) ?? hour;
        final endH =
            _parseHour(startingEntry['end_time'] as String?) ?? (startH + 1);
        final remainingHours = hours.length - i;
        final span = (endH - startH).clamp(1, remainingHours).toInt();
        final blockWidth = hourColWidth * span;

        cells.add(
          Container(
            width: blockWidth,
            height: slotHeight,
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(
                right: BorderSide(color: AppColors.divider),
                bottom: BorderSide(color: AppColors.divider),
              ),
            ),
            child: _buildScheduledSlotCard(
              startingEntry,
              dayIdx,
              hour,
              span: span,
            ),
          ),
        );
        i += span;
      } else {
        final spanningEntry = _findEntrySpanning(dayIdx, hour);
        if (spanningEntry != null) {
          final endH =
              _parseHour(spanningEntry['end_time'] as String?) ?? (hour + 1);
          final remainingHours = hours.length - i;
          final span = (endH - hour).clamp(1, remainingHours).toInt();
          final blockWidth = hourColWidth * span;

          cells.add(
            Container(
              width: blockWidth,
              height: slotHeight,
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  right: BorderSide(color: AppColors.divider),
                  bottom: BorderSide(color: AppColors.divider),
                ),
              ),
              child: _buildScheduledSlotCard(
                spanningEntry,
                dayIdx,
                hour,
                span: span,
              ),
            ),
          );
          i += span;
        } else {
          cells.add(
            Container(
              width: hourColWidth,
              height: slotHeight,
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  right: BorderSide(color: AppColors.divider),
                  bottom: BorderSide(color: AppColors.divider),
                ),
              ),
              child: _buildEmptySlotBox(dayIdx, hour),
            ),
          );
          i += 1;
        }
      }
    }
    return cells;
  }

  // Unified Scheduled Slot Card (supporting 1-hr and multi-hour merged blocks as a single unified card)
  Widget _buildScheduledSlotCard(
    Map<String, dynamic> entry,
    int dayIdx,
    int hour, {
    int span = 1,
  }) {
    final subjectName = entry['subject_name'] as String? ?? 'Subject';
    final classType = entry['class_type'] as String? ?? 'Theory';
    final room = entry['room'] as String? ?? '';
    final startTime = entry['start_time'] as String? ?? '';
    final endTime = entry['end_time'] as String? ?? '';

    final isBreak = subjectName.toLowerCase() == 'break time' ||
        subjectName.toLowerCase() == 'break' ||
        classType.toLowerCase() == 'break';
    final isLab = !isBreak &&
        (classType.toLowerCase().contains('lab') ||
            classType.toLowerCase().contains('practical'));
    final isOther = !isBreak &&
        !isLab &&
        (classType.toLowerCase().contains('other') ||
            classType.toLowerCase().contains('unspecified'));

    final subjectColor =
        isBreak ? AppColors.amber : _getSubjectColor(subjectName);
    final subjectCode = isBreak ? 'BREAK' : _getSubjectCode(subjectName);

    // Primary display: First priority CODES if set by user, else subject name
    final hasCode =
        subjectCode != null && subjectCode.isNotEmpty && subjectCode != 'BREAK';
    final primaryTitle =
        isBreak ? 'Break Time' : (hasCode ? subjectCode : subjectName);
    final secondaryTitle = isBreak ? null : (hasCode ? subjectName : null);

    final startH = _parseHour(startTime) ?? hour;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('slot_card_${dayIdx}_$startH'),
        onTap: () => _handleSlotTap(dayIdx, startH, existingEntry: entry),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isBreak
                  ? AppColors.amber.withValues(alpha: 0.4)
                  : subjectColor.withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: AppColors.shadowWarm,
                blurRadius: 3,
                offset: Offset(0, 1),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // 1. Left accent strip showing subject color
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 3.5,
                child: Container(
                  color: isBreak ? AppColors.amber : subjectColor,
                ),
              ),

              // 2. Card Content (IgnorePointer so touches pass through to outer InkWell, leaving right edge clear for edit button)
              IgnorePointer(
                child: Padding(
                  padding: const EdgeInsets.only(
                      left: 10, right: 28, top: 6, bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Top row: Badges
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: isBreak
                                  ? AppColors.amber
                                  : (isLab
                                      ? AppColors.sage
                                      : (isOther
                                          ? AppColors.ocean
                                          : subjectColor)),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              isBreak
                                  ? 'BREAK'
                                  : (isLab
                                      ? 'LAB'
                                      : (isOther ? 'OTHER' : 'THEORY')),
                              style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white),
                            ),
                          ),
                          if (span > 1 && !isBreak) ...[
                            const SizedBox(width: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: (isLab ? AppColors.sage : subjectColor)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${span}h',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w800,
                                  color: isLab ? AppColors.sage : subjectColor,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),

                      // Middle: Primary Code/Subject + Secondary Name
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              primaryTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: span > 1 ? 12 : 11,
                                color: AppColors.ink,
                              ),
                            ),
                            if (secondaryTitle != null)
                              Text(
                                secondaryTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: span > 1 ? 10 : 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                          ],
                        ),
                      ),

                      // Bottom: Timing & Room
                      Text(
                        room.isNotEmpty
                            ? '$room • $startTime – $endTime'
                            : '$startTime – $endTime',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // 3. Dedicated Edit Button positioned on top right (receives taps cleanly)
              Positioned(
                top: 4,
                right: 4,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    key: Key('edit_slot_${dayIdx}_$startH'),
                    onTap: () => _openSlotEditor(
                        dayOfWeek: dayIdx,
                        startHour: startH,
                        existingEntry: entry),
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.edit_outlined,
                          size: 14,
                          color: isBreak ? AppColors.amber : subjectColor),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Empty Slot Box with "+" icon
  Widget _buildEmptySlotBox(int dayIdx, int hour) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: Key('empty_slot_${dayIdx}_$hour'),
        onTap: () => _handleSlotTap(dayIdx, hour),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.divider,
              width: 1.0,
            ),
          ),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.divider),
                    boxShadow: const [
                      BoxShadow(
                        color: AppColors.shadowWarm,
                        blurRadius: 2,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(Icons.add_rounded,
                      size: 16, color: AppColors.terracotta),
                ),
                const SizedBox(height: 4),
                Text(
                  _quickAssignTool != null ? 'Quick Add' : 'Add Class',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Modal Sheet Slot Editor with Option 1: Subject, Option 2: Class Type, Option 3: Side-by-Side Timing
  void _openSlotEditor({
    required int dayOfWeek,
    required int startHour,
    Map<String, dynamic>? existingEntry,
  }) {
    if (_subjects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enroll at least one subject in Step 3 first.'),
          backgroundColor: AppColors.coral,
        ),
      );
      return;
    }

    final dayName = _scheduleDays[dayOfWeek.clamp(0, _scheduleDays.length - 1)];
    String selectedSubject = existingEntry != null
        ? (existingEntry['subject_name'] as String? ??
            _getValidRoutineSubject() ??
            '')
        : (_getValidRoutineSubject() ?? '');

    final rawCt = existingEntry?['class_type'] as String? ?? 'Theory';
    String classType =
        (rawCt == 'LAB' || rawCt.contains('Lab') || rawCt.contains('Practical'))
            ? 'Lab'
            : (rawCt == 'Others' ||
                    rawCt == 'UNSPECIFIED' ||
                    rawCt.contains('Other'))
                ? 'Others'
                : 'Theory';
    int currentStartHour =
        _parseHour(existingEntry?['start_time'] as String?) ?? startHour;
    int currentEndHour = _parseHour(existingEntry?['end_time'] as String?) ??
        ((classType == 'Lab' || classType == 'Practical/Lab')
            ? (currentStartHour + 2).clamp(currentStartHour + 1, 23)
            : (currentStartHour + 1).clamp(currentStartHour + 1, 23));

    final roomCtrl =
        TextEditingController(text: existingEntry?['room'] as String? ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final startDisplay = _formatHourDisplay(currentStartHour);
            final endDisplay = _formatHourDisplay(currentEndHour);

            return Container(
              padding: EdgeInsets.only(
                top: 20,
                left: 20,
                right: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              decoration: const BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header Handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Title & Day badge
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                existingEntry != null
                                    ? 'Edit Schedule Slot'
                                    : 'Schedule Class',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$dayName • $startDisplay – $endDisplay',
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.inkMuted),
                              ),
                            ],
                          ),
                        ),
                        if (existingEntry != null)
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                color: AppColors.coral),
                            tooltip: 'Delete Slot',
                            onPressed: () {
                              setState(() {
                                _timetableEntries.remove(existingEntry);
                              });
                              _saveDraft(immediate: true);
                              Navigator.pop(ctx);
                            },
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: AppColors.inkMuted),
                            tooltip: 'Close',
                            onPressed: () => Navigator.pop(ctx),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // OPTION 1: SELECT SUBJECT
                    const Text(
                      '1. Select Subject',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: (selectedSubject == 'Break Time' ||
                                  _subjects
                                      .any((s) => s['name'] == selectedSubject))
                              ? selectedSubject
                              : (_subjects.isNotEmpty
                                  ? _subjects.first['name'] as String
                                  : 'Break Time'),
                          isExpanded: true,
                          items: [
                            // 1. FIRST OPTION: BREAK "Break Time"
                            DropdownMenuItem<String>(
                              value: 'Break Time',
                              child: Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      color: AppColors.amber,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  const Expanded(
                                    child: Text(
                                      'Break Time',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13,
                                          color: AppColors.ink),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.amber
                                          .withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'BREAK',
                                      style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.amber),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // 2. ENROLLED SUBJECTS
                            ..._subjects.map((s) {
                              final name = s['name'] as String;
                              final code = s['code'] as String?;
                              final color = _parseColor(s['color'] as String?);
                              return DropdownMenuItem<String>(
                                value: name,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                          color: color, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: AppColors.ink),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (code != null && code.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.15),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          code,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: color,
                                              fontWeight: FontWeight.w700),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            }),
                          ],
                          onChanged: (val) {
                            if (val != null) {
                              setModalState(() {
                                selectedSubject = val;
                                if (val == 'Break Time') {
                                  classType = 'Break';
                                  currentEndHour = (currentStartHour + 1)
                                      .clamp(currentStartHour + 1, 23);
                                } else if (classType == 'Break') {
                                  classType = 'Theory';
                                }
                              });
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // OPTION 2: SELECT CLASS TYPE (Theory vs Practical/Lab)
                    const Text(
                      '2. Select Class Type',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink),
                    ),
                    const SizedBox(height: 8),
                    if (selectedSubject == 'Break Time')
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: AppColors.amber.withValues(alpha: 0.4)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.coffee_rounded,
                                size: 18, color: AppColors.amber),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Break / Recess interval (scheduled routine pause)',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Row(
                        children: [
                          // Theory Option
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setModalState(() {
                                  classType = 'Theory';
                                  currentEndHour = (currentStartHour + 1)
                                      .clamp(currentStartHour + 1, 23);
                                });
                                HapticFeedback.selectionClick();
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 10),
                                decoration: BoxDecoration(
                                  color: classType == 'Theory'
                                      ? AppColors.terracotta
                                          .withValues(alpha: 0.12)
                                      : AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: classType == 'Theory'
                                        ? AppColors.terracotta
                                        : AppColors.divider,
                                    width: classType == 'Theory' ? 2.0 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.menu_book_rounded,
                                          size: 16,
                                          color: classType == 'Theory'
                                              ? AppColors.terracotta
                                              : AppColors.inkMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            'Theory',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                              color: classType == 'Theory'
                                                  ? AppColors.terracotta
                                                  : AppColors.ink,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      '1 Hour',
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: AppColors.inkMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),

                          // Practical / Lab Option
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                final targetEndHour = currentStartHour + 2;
                                if (targetEndHour > _classEndHour) {
                                  AppToast.showConflict(
                                    context,
                                    'Cannot schedule 2-hour class at ${_formatHourDisplay(currentStartHour)}: working hours end at ${_formatHourDisplay(_classEndHour)}.',
                                  );
                                  HapticFeedback.heavyImpact();
                                  return;
                                }

                                final conflict = _findConflictingEntry(
                                  dayOfWeek: dayOfWeek,
                                  startHour: currentStartHour,
                                  endHour: targetEndHour,
                                  ignoreEntry: existingEntry,
                                );
                                if (conflict != null) {
                                  final cName =
                                      conflict['subject_name'] ?? 'Class';
                                  final cStart = conflict['start_time'] ?? '';
                                  final cEnd = conflict['end_time'] ?? '';
                                  AppToast.showConflict(
                                    context,
                                    'Conflict: Cannot schedule 2-hour class. "$cName" is already booked from $cStart to $cEnd.',
                                  );
                                  HapticFeedback.heavyImpact();
                                  return;
                                }

                                setModalState(() {
                                  classType = 'Lab';
                                  currentEndHour = targetEndHour;
                                });
                                HapticFeedback.selectionClick();
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 10),
                                decoration: BoxDecoration(
                                  color: (classType == 'Lab' ||
                                          classType == 'Practical/Lab')
                                      ? AppColors.sage.withValues(alpha: 0.12)
                                      : AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: (classType == 'Lab' ||
                                            classType == 'Practical/Lab')
                                        ? AppColors.sage
                                        : AppColors.divider,
                                    width: (classType == 'Lab' ||
                                            classType == 'Practical/Lab')
                                        ? 2.0
                                        : 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.biotech_rounded,
                                          size: 16,
                                          color: (classType == 'Lab' ||
                                                  classType == 'Practical/Lab')
                                              ? AppColors.sage
                                              : AppColors.inkMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            'Lab',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                              color: (classType == 'Lab' ||
                                                      classType ==
                                                          'Practical/Lab')
                                                  ? AppColors.sage
                                                  : AppColors.ink,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      '2 Hours',
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: AppColors.inkMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // Others Option
                          Expanded(
                            child: InkWell(
                              onTap: () {
                                setModalState(() {
                                  classType = 'Others';
                                  currentEndHour = (currentStartHour + 1)
                                      .clamp(currentStartHour + 1, 23);
                                });
                                HapticFeedback.selectionClick();
                              },
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 10),
                                decoration: BoxDecoration(
                                  color: (classType == 'Others' ||
                                          classType == 'UNSPECIFIED')
                                      ? AppColors.ocean.withValues(alpha: 0.12)
                                      : AppColors.surface,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: (classType == 'Others' ||
                                            classType == 'UNSPECIFIED')
                                        ? AppColors.ocean
                                        : AppColors.divider,
                                    width: (classType == 'Others' ||
                                            classType == 'UNSPECIFIED')
                                        ? 2.0
                                        : 1.0,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.category_rounded,
                                          size: 16,
                                          color: (classType == 'Others' ||
                                                  classType == 'UNSPECIFIED')
                                              ? AppColors.ocean
                                              : AppColors.inkMuted,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            'Others',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                              color: (classType == 'Others' ||
                                                      classType ==
                                                          'UNSPECIFIED')
                                                  ? AppColors.ocean
                                                  : AppColors.ink,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      '1 Hour',
                                      style: TextStyle(
                                          fontSize: 10.5,
                                          color: AppColors.inkMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    const SizedBox(height: 20),

                    // OPTION 3: SIDE-BY-SIDE TIMINGS (DYNAMIC DROPDOWNS)
                    const Text(
                      '3. Class Timings',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Start Time Dropdown
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.schedule_rounded,
                                        size: 14, color: AppColors.inkMuted),
                                    SizedBox(width: 4),
                                    Text('Start Time',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.inkMuted,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: currentStartHour,
                                    isExpanded: true,
                                    items: () {
                                      final startOpts = List.generate(
                                        (_classEndHour - _classStartHour)
                                            .clamp(1, 14),
                                        (i) => _classStartHour + i,
                                      );
                                      if (!startOpts
                                          .contains(currentStartHour)) {
                                        startOpts.add(currentStartHour);
                                        startOpts.sort();
                                      }
                                      return startOpts.map((h) {
                                        return DropdownMenuItem<int>(
                                          value: h,
                                          child: Text(
                                            _formatHourDisplay(h),
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.ink),
                                          ),
                                        );
                                      }).toList();
                                    }(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        final newEnd =
                                            (classType == 'Practical/Lab')
                                                ? (val + 2).clamp(val + 1, 23)
                                                : (val + 1).clamp(val + 1, 23);

                                        if (newEnd > _classEndHour) {
                                          AppToast.showConflict(
                                            context,
                                            'Classes end at ${_formatHourDisplay(_classEndHour)}. Cannot start class at ${_formatHourDisplay(val)} with duration of ${newEnd - val}h.',
                                          );
                                          HapticFeedback.heavyImpact();
                                          return;
                                        }

                                        final conflict = _findConflictingEntry(
                                          dayOfWeek: dayOfWeek,
                                          startHour: val,
                                          endHour: newEnd,
                                          ignoreEntry: existingEntry,
                                        );
                                        if (conflict != null) {
                                          final cName =
                                              conflict['subject_name'] ??
                                                  'Class';
                                          final cStart =
                                              conflict['start_time'] ?? '';
                                          final cEnd =
                                              conflict['end_time'] ?? '';
                                          AppToast.showConflict(
                                            context,
                                            'Time conflict: "$cName" is already scheduled from $cStart to $cEnd.',
                                          );
                                          HapticFeedback.heavyImpact();
                                          return;
                                        }

                                        setModalState(() {
                                          currentStartHour = val;
                                          currentEndHour = newEnd;
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Icon(Icons.arrow_forward_rounded,
                            color: AppColors.inkMuted, size: 16),
                        const SizedBox(width: 10),

                        // End Time Dropdown
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.timer_outlined,
                                        size: 14, color: AppColors.inkMuted),
                                    SizedBox(width: 4),
                                    Text('End Time',
                                        style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.inkMuted,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ),
                                DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: currentEndHour,
                                    isExpanded: true,
                                    items: () {
                                      final endOpts = List.generate(
                                        (23 - currentStartHour).clamp(1, 6),
                                        (i) => currentStartHour + 1 + i,
                                      );
                                      if (!endOpts.contains(currentEndHour)) {
                                        endOpts.add(currentEndHour);
                                        endOpts.sort();
                                      }
                                      return endOpts.map((h) {
                                        return DropdownMenuItem<int>(
                                          value: h,
                                          child: Text(
                                            _formatHourDisplay(h),
                                            style: const TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.ink),
                                          ),
                                        );
                                      }).toList();
                                    }(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        if (val <= currentStartHour) {
                                          AppToast.showConflict(context,
                                              'End time must be after start time.');
                                          HapticFeedback.heavyImpact();
                                          return;
                                        }
                                        if (val > _classEndHour) {
                                          AppToast.showConflict(
                                            context,
                                            'Classes end at ${_formatHourDisplay(_classEndHour)}. Cannot set end time to ${_formatHourDisplay(val)}.',
                                          );
                                          HapticFeedback.heavyImpact();
                                          return;
                                        }

                                        final conflict = _findConflictingEntry(
                                          dayOfWeek: dayOfWeek,
                                          startHour: currentStartHour,
                                          endHour: val,
                                          ignoreEntry: existingEntry,
                                        );
                                        if (conflict != null) {
                                          final cName =
                                              conflict['subject_name'] ??
                                                  'Class';
                                          final cStart =
                                              conflict['start_time'] ?? '';
                                          final cEnd =
                                              conflict['end_time'] ?? '';
                                          AppToast.showConflict(
                                            context,
                                            'Time conflict: "$cName" is already scheduled from $cStart to $cEnd.',
                                          );
                                          HapticFeedback.heavyImpact();
                                          return;
                                        }

                                        setModalState(() {
                                          currentEndHour = val;
                                          if (currentEndHour -
                                                  currentStartHour >=
                                              2) {
                                            classType = 'Practical/Lab';
                                          } else {
                                            classType = 'Theory';
                                          }
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // Optional Room / Hall
                    AppTextField(
                      label: 'Room / Lab / Hall (Optional)',
                      controller: roomCtrl,
                      hint: 'e.g. Room 101, CS Lab 2',
                      prefixIcon: const Icon(Icons.meeting_room_outlined,
                          size: 20, color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 20),

                    // Action Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              side: const BorderSide(color: AppColors.divider),
                            ),
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel',
                                style: TextStyle(
                                    color: AppColors.inkMuted,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.terracotta,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                            icon: Icon(
                                existingEntry != null
                                    ? Icons.check_rounded
                                    : Icons.add_rounded,
                                size: 18),
                            label: Text(
                              existingEntry != null
                                  ? 'Update Slot'
                                  : 'Add Slot',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700),
                            ),
                            onPressed: () {
                              if (currentStartHour >= currentEndHour) {
                                AppToast.showConflict(context,
                                    'End time must be after start time.');
                                HapticFeedback.heavyImpact();
                                return;
                              }

                              if (currentEndHour > _classEndHour) {
                                AppToast.showConflict(
                                  context,
                                  'Class cannot extend past closing hour (${_formatHourDisplay(_classEndHour)}).',
                                );
                                HapticFeedback.heavyImpact();
                                return;
                              }

                              final conflict = _findConflictingEntry(
                                dayOfWeek: dayOfWeek,
                                startHour: currentStartHour,
                                endHour: currentEndHour,
                                ignoreEntry: existingEntry,
                              );
                              if (conflict != null) {
                                final cName =
                                    conflict['subject_name'] ?? 'Class';
                                final cStart = conflict['start_time'] ?? '';
                                final cEnd = conflict['end_time'] ?? '';
                                AppToast.showConflict(
                                  context,
                                  'Schedule conflict: "$cName" is already scheduled from $cStart to $cEnd.',
                                );
                                HapticFeedback.heavyImpact();
                                return;
                              }

                              final startTimeStr =
                                  _formatHourString(currentStartHour);
                              final endTimeStr =
                                  _formatHourString(currentEndHour);
                              final roomVal = roomCtrl.text.trim();

                              final effectiveClassType =
                                  (selectedSubject == 'Break Time')
                                      ? 'Break'
                                      : classType;

                              setState(() {
                                if (existingEntry != null) {
                                  existingEntry['subject_name'] =
                                      selectedSubject;
                                  existingEntry['class_type'] =
                                      effectiveClassType;
                                  existingEntry['start_time'] = startTimeStr;
                                  existingEntry['end_time'] = endTimeStr;
                                  existingEntry['room'] = roomVal;
                                } else {
                                  _timetableEntries.add({
                                    'subject_name': selectedSubject,
                                    'day_of_week': dayOfWeek,
                                    'start_time': startTimeStr,
                                    'end_time': endTimeStr,
                                    'class_type': effectiveClassType,
                                    'room': roomVal,
                                  });
                                }
                                _selectedRoutineSubject = selectedSubject;
                              });
                              _saveDraft(immediate: true);
                              HapticFeedback.lightImpact();
                              Navigator.pop(ctx);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // STEP 5: CALENDAR
  Widget _buildStep5Holidays() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeader(
            title: 'Academic Holidays',
            subtitle:
                'Holidays and academic breaks are excluded from attendance denominator so your record stays 100% accurate.',
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_holidays.length} Events',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    color: AppColors.amber),
              ),
            ),
          ),

          // Add Event Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: const [
                BoxShadow(
                  color: AppColors.shadowWarm,
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.amber.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.event_outlined,
                          color: AppColors.amber, size: 18),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Event',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.ink),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Schedule holidays, festivals, study breaks or closures',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.inkMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                AppTextField(
                  label: 'Event Title',
                  controller: _holidayTitleCtrl,
                  hint: 'e.g. Diwali Break, Foundation Day',
                  prefixIcon: const Icon(Icons.celebration_outlined,
                      size: 20, color: AppColors.inkMuted),
                  onTapOutside: (_) {
                    FocusScope.of(context).unfocus();
                    _saveDraft();
                  },
                  onEditingComplete: () {
                    FocusScope.of(context).unfocus();
                    _saveDraft();
                  },
                ),
                const SizedBox(height: 12),

                // Side-by-Side Date Range Capsule Card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Duration',
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink)),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: AppColors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '${_holidayEndDate.difference(_holidayStartDate).inDays + 1} Day${_holidayEndDate.difference(_holidayStartDate).inDays == 0 ? '' : 's'}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.amber),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          // Start Date
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () async {
                                final picked = await _showThemedDatePicker(
                                  context: context,
                                  initialDate: _holidayStartDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setState(() {
                                    _holidayStartDate = picked;
                                    if (_holidayEndDate
                                        .isBefore(_holidayStartDate)) {
                                      _holidayEndDate = _holidayStartDate;
                                    }
                                  });
                                  _saveDraft();
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.divider),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.calendar_today_rounded,
                                            size: 11,
                                            color: AppColors.terracotta),
                                        SizedBox(width: 4),
                                        Text('Starts On',
                                            style: TextStyle(
                                                fontSize: 10.5,
                                                color: AppColors.inkMuted,
                                                fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('dd MMM yyyy')
                                          .format(_holidayStartDate),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.ink),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward_rounded,
                                size: 16, color: AppColors.inkMuted),
                          ),
                          // End Date
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () async {
                                final picked = await _showThemedDatePicker(
                                  context: context,
                                  initialDate: _holidayEndDate,
                                  firstDate: _holidayStartDate,
                                  lastDate: DateTime(2030),
                                );
                                if (picked != null) {
                                  setState(() => _holidayEndDate = picked);
                                  _saveDraft();
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: AppColors.surface,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: AppColors.divider),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.event_available_rounded,
                                            size: 11,
                                            color: AppColors.terracotta),
                                        SizedBox(width: 4),
                                        Text('Ends On',
                                            style: TextStyle(
                                                fontSize: 10.5,
                                                color: AppColors.inkMuted,
                                                fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      DateFormat('dd MMM yyyy')
                                          .format(_holidayEndDate),
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.ink),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.terracotta,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 11),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Event',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    onPressed: () {
                      final title = _holidayTitleCtrl.text.trim();
                      if (title.isNotEmpty) {
                        setState(() {
                          _holidays.removeWhere((h) =>
                              h['title'] == 'Diwali Break' ||
                              h['title'] == 'Mid-Term Break');
                          _holidays.add({
                            'title': title,
                            'start_date': _holidayStartDate,
                            'end_date': _holidayEndDate,
                            'category': _holidayCategory,
                            'notes': null,
                          });
                          _holidayTitleCtrl.clear();
                        });
                        _saveDraft();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (_holidays.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.event_busy_outlined,
                        size: 40,
                        color: AppColors.inkMuted.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    const Text(
                      'No events scheduled yet',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.ink),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Add academic breaks or institutional holidays above.',
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._holidays.asMap().entries.map((entry) {
              final idx = entry.key;
              final h = entry.value;
              final sDate = h['start_date'] as DateTime;
              final eDate = h['end_date'] as DateTime;
              final sStr = DateFormat('dd MMM').format(sDate);
              final eStr = DateFormat('dd MMM yyyy').format(eDate);
              final durationDays = eDate.difference(sDate).inDays + 1;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadowWarm,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 4.5,
                      child: Container(color: AppColors.amber),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.amber.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.celebration_rounded,
                                color: AppColors.amber, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  h['title'] as String,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                      color: AppColors.ink),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '$sStr – $eStr',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.inkMuted,
                                          fontWeight: FontWeight.w500),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 1.5),
                                      decoration: BoxDecoration(
                                        color: AppColors.surfaceAlt,
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                            color: AppColors.divider),
                                      ),
                                      child: Text(
                                        '$durationDays Day${durationDays == 1 ? '' : 's'}',
                                        style: const TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.ink),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded,
                                color: AppColors.coral, size: 20),
                            onPressed: () {
                              setState(() => _holidays.removeAt(idx));
                              _saveDraft();
                            },
                            tooltip: 'Delete Event',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // STEP 6: PAST ATTENDANCE RECORDS
  Widget _buildStep6Attendance() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeader(
            title: 'Past Attendance Records',
            subtitle:
                'Starting AttendiFy mid-semester? Enter your verified attended and conducted totals. If you are starting fresh, leave all as 0.',
          ),
          if (_subjects.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Icon(Icons.fact_check_outlined,
                        size: 40,
                        color: AppColors.inkMuted.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    const Text(
                      'No subjects enrolled',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: AppColors.ink),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Please enroll subjects in Step 3 first.',
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                    ),
                  ],
                ),
              ),
            )
          else
            ..._subjects.map((sub) {
              final name = sub['name'] as String;
              final subColor = _parseColor(sub['color'] as String?);
              final code = sub['code'] as String?;
              final att = _startingAttended[name] ?? 0;
              final cond = _startingConducted[name] ?? 0;
              final hasData = cond > 0;
              final pct = hasData ? (att / cond * 100) : 0.0;
              final isAboveTarget = pct >= _personalTarget;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadowWarm,
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 4.5,
                      child: Container(color: subColor),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Subject Name & Code + Attendance Percentage Pill
                          Row(
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14.5,
                                            color: AppColors.ink),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (code != null &&
                                        code.trim().isNotEmpty) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1.5),
                                        decoration: BoxDecoration(
                                          color:
                                              subColor.withValues(alpha: 0.12),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          code.trim(),
                                          style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w700,
                                              color: subColor),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: hasData
                                      ? (isAboveTarget
                                          ? AppColors.sage
                                              .withValues(alpha: 0.15)
                                          : AppColors.coral
                                              .withValues(alpha: 0.15))
                                      : AppColors.surfaceAlt,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: hasData
                                        ? (isAboveTarget
                                            ? AppColors.sage
                                                .withValues(alpha: 0.3)
                                            : AppColors.coral
                                                .withValues(alpha: 0.3))
                                        : AppColors.divider,
                                  ),
                                ),
                                child: Text(
                                  hasData
                                      ? '${pct.toStringAsFixed(1)}%'
                                      : 'No records yet',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: hasData
                                        ? (isAboveTarget
                                            ? AppColors.sage
                                            : AppColors.coral)
                                        : AppColors.inkMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Line 1: Classes Attended (Separate Line)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle_outline_rounded,
                                    size: 16, color: AppColors.sage),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Classes Attended',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink),
                                  ),
                                ),
                                // Stepper decrement button
                                InkWell(
                                  onTap: att > 0
                                      ? () {
                                          final nAtt = att - 1;
                                          setState(() {
                                            _startingAttended[name] = nAtt;
                                            _attendedControllers[name]?.text =
                                                nAtt.toString();
                                          });
                                          _saveDraft();
                                        }
                                      : null,
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(6),
                                      border:
                                          Border.all(color: AppColors.divider),
                                    ),
                                    child: Icon(Icons.remove_rounded,
                                        size: 16,
                                        color: att > 0
                                            ? AppColors.ink
                                            : AppColors.inkMuted),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Direct Numeric Editable Input Field
                                SizedBox(
                                  width: 54,
                                  height: 34,
                                  child: TextFormField(
                                    controller:
                                        _getAttendedController(name, att),
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                        color: AppColors.ink),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 7),
                                      filled: true,
                                      fillColor: AppColors.surface,
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          borderSide: const BorderSide(
                                              color: AppColors.divider)),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          borderSide: const BorderSide(
                                              color: AppColors.divider)),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          borderSide: const BorderSide(
                                              color: AppColors.terracotta,
                                              width: 1.5)),
                                    ),
                                    onChanged: (val) {
                                      final parsed =
                                          int.tryParse(val.trim()) ?? 0;
                                      setState(() {
                                        _startingAttended[name] =
                                            parsed.clamp(0, 9999);
                                        final curCond =
                                            _startingConducted[name] ?? 0;
                                        if (curCond <
                                            _startingAttended[name]!) {
                                          _startingConducted[name] =
                                              _startingAttended[name]!;
                                          _conductedControllers[name]?.text =
                                              _startingAttended[name]!
                                                  .toString();
                                        }
                                      });
                                      _saveDraft();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Stepper increment button
                                InkWell(
                                  onTap: () {
                                    final nAtt = att + 1;
                                    setState(() {
                                      _startingAttended[name] = nAtt;
                                      _attendedControllers[name]?.text =
                                          nAtt.toString();
                                      final curCond =
                                          _startingConducted[name] ?? 0;
                                      if (curCond < nAtt) {
                                        _startingConducted[name] = nAtt;
                                        _conductedControllers[name]?.text =
                                            nAtt.toString();
                                      }
                                    });
                                    _saveDraft();
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(6),
                                      border:
                                          Border.all(color: AppColors.divider),
                                    ),
                                    child: const Icon(Icons.add_rounded,
                                        size: 16, color: AppColors.sage),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Line 2: Classes Conducted (Separate Line)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.event_note_rounded,
                                    size: 16, color: AppColors.terracotta),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Classes Conducted',
                                    style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.ink),
                                  ),
                                ),
                                // Stepper decrement button
                                InkWell(
                                  onTap: cond > att
                                      ? () {
                                          final nCond = cond - 1;
                                          setState(() {
                                            _startingConducted[name] = nCond;
                                            _conductedControllers[name]?.text =
                                                nCond.toString();
                                          });
                                          _saveDraft();
                                        }
                                      : null,
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(6),
                                      border:
                                          Border.all(color: AppColors.divider),
                                    ),
                                    child: Icon(Icons.remove_rounded,
                                        size: 16,
                                        color: cond > att
                                            ? AppColors.ink
                                            : AppColors.inkMuted),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Direct Numeric Editable Input Field
                                SizedBox(
                                  width: 54,
                                  height: 34,
                                  child: TextFormField(
                                    controller:
                                        _getConductedController(name, cond),
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,
                                        color: AppColors.ink),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              vertical: 7),
                                      filled: true,
                                      fillColor: AppColors.surface,
                                      border: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          borderSide: const BorderSide(
                                              color: AppColors.divider)),
                                      enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          borderSide: const BorderSide(
                                              color: AppColors.divider)),
                                      focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          borderSide: const BorderSide(
                                              color: AppColors.terracotta,
                                              width: 1.5)),
                                    ),
                                    onChanged: (val) {
                                      final parsed =
                                          int.tryParse(val.trim()) ?? 0;
                                      setState(() {
                                        _startingConducted[name] =
                                            parsed.clamp(0, 9999);
                                        final curAtt =
                                            _startingAttended[name] ?? 0;
                                        if (_startingConducted[name]! <
                                            curAtt) {
                                          _startingConducted[name] = curAtt;
                                          _conductedControllers[name]?.text =
                                              curAtt.toString();
                                        }
                                      });
                                      _saveDraft();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 6),
                                // Stepper increment button
                                InkWell(
                                  onTap: () {
                                    final nCond = cond + 1;
                                    setState(() {
                                      _startingConducted[name] = nCond;
                                      _conductedControllers[name]?.text =
                                          nCond.toString();
                                    });
                                    _saveDraft();
                                  },
                                  borderRadius: BorderRadius.circular(6),
                                  child: Container(
                                    width: 32,
                                    height: 32,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(6),
                                      border:
                                          Border.all(color: AppColors.divider),
                                    ),
                                    child: const Icon(Icons.add_rounded,
                                        size: 16, color: AppColors.terracotta),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // STEP 7: REVIEW & SAVE
  Widget _buildStep7Review() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStepHeader(
            title: 'Review Academic Configuration',
            subtitle:
                'Confirm all details before activating your semester. Tap edit on any section to adjust settings.',
          ),

          // 1. Top Metrics Quick Grid (4 Cards - Strictly Equal Height & Unified)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                      boxShadow: const [
                        BoxShadow(
                            color: AppColors.shadowWarm,
                            blurRadius: 4,
                            offset: Offset(0, 1)),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${_subjects.length}',
                            style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: AppColors.terracotta)),
                        const SizedBox(height: 3),
                        const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Subjects',
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.inkMuted,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                      boxShadow: const [
                        BoxShadow(
                            color: AppColors.shadowWarm,
                            blurRadius: 4,
                            offset: Offset(0, 1)),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${_timetableEntries.length}',
                            style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ocean)),
                        const SizedBox(height: 3),
                        const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Weekly Slots',
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.inkMuted,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                      boxShadow: const [
                        BoxShadow(
                            color: AppColors.shadowWarm,
                            blurRadius: 4,
                            offset: Offset(0, 1)),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${_holidays.length}',
                            style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: AppColors.amber)),
                        const SizedBox(height: 3),
                        const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Events',
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.inkMuted,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.divider),
                      boxShadow: const [
                        BoxShadow(
                            color: AppColors.shadowWarm,
                            blurRadius: 4,
                            offset: Offset(0, 1)),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('${_personalTarget.toStringAsFixed(0)}%',
                            style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                                color: AppColors.sage)),
                        const SizedBox(height: 3),
                        const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Target Goal',
                              maxLines: 1,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppColors.inkMuted,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. Academic Profile Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadowWarm,
                    blurRadius: 4,
                    offset: Offset(0, 1)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.person_pin_rounded,
                            color: AppColors.terracotta, size: 18),
                        SizedBox(width: 8),
                        Text('Academic Profile',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.ink)),
                      ],
                    ),
                    if (!_isReturningUser)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            size: 18, color: AppColors.terracotta),
                        onPressed: () => _goToStep(0),
                        tooltip: 'Edit Profile',
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.sageLight,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Profile Active',
                            style: TextStyle(
                                color: AppColors.sageDark,
                                fontSize: 11,
                                fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
                const Divider(color: AppColors.divider, height: 16),
                _buildReviewDetailRow(
                    'Student Name',
                    _fullNameCtrl.text.isEmpty
                        ? 'Not specified'
                        : _fullNameCtrl.text),
                const SizedBox(height: 6),
                _buildReviewDetailRow(
                    'Institution',
                    _universityCtrl.text.isEmpty
                        ? 'Not specified'
                        : _universityCtrl.text),
                const SizedBox(height: 6),
                _buildReviewDetailRow(
                    'Program',
                    _courseCtrl.text.isEmpty
                        ? 'Not specified'
                        : _courseCtrl.text),
                if (_studentIdCtrl.text.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _buildReviewDetailRow(
                      'Student ID / Roll', _studentIdCtrl.text),
                ],
                const SizedBox(height: 6),
                _buildReviewDetailRow('Duration & Session',
                    '$_durationYears Years ($_sessionStart–$_sessionEnd)'),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 3. Semester & Attendance Rules Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadowWarm,
                    blurRadius: 4,
                    offset: Offset(0, 1)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified_user_outlined,
                            color: AppColors.terracotta, size: 18),
                        SizedBox(width: 8),
                        Text('Semester & Rules',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.ink)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          size: 18, color: AppColors.terracotta),
                      onPressed: () => _goToStep(_isReturningUser ? 0 : 1),
                      tooltip: 'Edit Semester',
                    ),
                  ],
                ),
                const Divider(color: AppColors.divider, height: 16),
                _buildReviewDetailRow('Active Term', _semesterLabelCtrl.text),
                const SizedBox(height: 6),
                _buildReviewDetailRow(
                  'Working Schedule',
                  '$_startDay to $_endDay\n${_formatHourDisplay(_classStartHour)} – ${_formatHourDisplay(_classEndHour)}',
                ),
                const SizedBox(height: 6),
                _buildReviewDetailRow(
                  'Attendance Targets',
                  'Minimum: ${_minAttendance.toStringAsFixed(0)}%\nPersonal Goal: ${_personalTarget.toStringAsFixed(0)}%',
                  valueColor: AppColors.terracotta,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 4. Enrolled Subjects List Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadowWarm,
                    blurRadius: 4,
                    offset: Offset(0, 1)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.menu_book_rounded,
                            color: AppColors.terracotta, size: 18),
                        const SizedBox(width: 8),
                        Text('Enrolled Subjects (${_subjects.length})',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.ink)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          size: 18, color: AppColors.terracotta),
                      onPressed: () => _goToStep(_isReturningUser ? 1 : 2),
                      tooltip: 'Edit Subjects',
                    ),
                  ],
                ),
                const Divider(color: AppColors.divider, height: 16),
                if (_subjects.isEmpty)
                  const Text('No subjects enrolled yet.',
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted))
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _subjects.map((s) {
                      final sColor = _parseColor(s['color'] as String?);
                      final code = s['code'] as String?;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceAlt,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: sColor, shape: BoxShape.circle)),
                            const SizedBox(width: 6),
                            Text(s['name'] as String,
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.ink)),
                            if (code != null && code.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Text('($code)',
                                  style: const TextStyle(
                                      fontSize: 10.5,
                                      color: AppColors.inkMuted)),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 5. Weekly Timetable Breakdown Card (Requested by User)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadowWarm,
                    blurRadius: 4,
                    offset: Offset(0, 1)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_view_week_rounded,
                            color: AppColors.ocean, size: 18),
                        const SizedBox(width: 8),
                        Text(
                            'Weekly Timetable (${_timetableEntries.length} Slots)',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.ink)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          size: 18, color: AppColors.terracotta),
                      onPressed: () => _goToStep(_isReturningUser ? 2 : 3),
                      tooltip: 'Edit Timetable',
                    ),
                  ],
                ),
                const Divider(color: AppColors.divider, height: 16),
                if (_timetableEntries.isEmpty)
                  const Text('No classes scheduled in timetable.',
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted))
                else
                  ..._scheduleDays.map((dayName) {
                    final dayIdx = _allDays.indexOf(dayName);
                    final dayEntries = _timetableEntries
                        .where((t) => t['day_of_week'] == dayIdx)
                        .toList()
                      ..sort((a, b) => (a['start_time'] as String? ?? '')
                          .compareTo(b['start_time'] as String? ?? ''));

                    if (dayEntries.isEmpty) return const SizedBox.shrink();

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color:
                                      AppColors.ocean.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  dayName,
                                  style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.ocean),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${dayEntries.length} class${dayEntries.length == 1 ? '' : 'es'}',
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.inkMuted),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ...dayEntries.map((e) {
                            final subName =
                                e['subject_name'] as String? ?? 'Class';
                            final sCol = _getSubjectColor(subName);
                            final st = e['start_time'] as String? ?? '';
                            final et = e['end_time'] as String? ?? '';
                            final rm = e['room'] as String?;
                            final cType =
                                e['class_type'] as String? ?? 'Theory';

                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceAlt,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.divider),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                      width: 3.5,
                                      height: 24,
                                      decoration: BoxDecoration(
                                          color: sCol,
                                          borderRadius:
                                              BorderRadius.circular(2))),
                                  const SizedBox(width: 8),
                                  Text(
                                    formatSlotRange(st, et,
                                        is24h: ref.watch(timeFormatProvider) ==
                                            '24h'),
                                    style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.ink),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      subName,
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.ink),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (rm != null && rm.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      rm,
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.inkMuted),
                                    ),
                                  ],
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: cType == 'Break'
                                          ? AppColors.amber
                                              .withValues(alpha: 0.15)
                                          : AppColors.surface,
                                      borderRadius: BorderRadius.circular(4),
                                      border:
                                          Border.all(color: AppColors.divider),
                                    ),
                                    child: Text(
                                      cType,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w700,
                                        color: cType == 'Break'
                                            ? AppColors.amber
                                            : AppColors.inkMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 6. Academic Calendar Events Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.divider),
              boxShadow: const [
                BoxShadow(
                    color: AppColors.shadowWarm,
                    blurRadius: 4,
                    offset: Offset(0, 1)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.event_note_rounded,
                            color: AppColors.amber, size: 18),
                        const SizedBox(width: 8),
                        Text('Academic Holidays (${_holidays.length} Events)',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                                color: AppColors.ink)),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined,
                          size: 18, color: AppColors.terracotta),
                      onPressed: () => _goToStep(_isReturningUser ? 3 : 4),
                      tooltip: 'Edit Holidays',
                    ),
                  ],
                ),
                const Divider(color: AppColors.divider, height: 16),
                if (_holidays.isEmpty)
                  const Text('No events or holidays scheduled.',
                      style: TextStyle(fontSize: 12, color: AppColors.inkMuted))
                else
                  ..._holidays.map((h) {
                    final sDate = h['start_date'] as DateTime;
                    final eDate = h['end_date'] as DateTime;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          const Icon(Icons.celebration_rounded,
                              color: AppColors.amber, size: 14),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              h['title'] as String,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.ink),
                            ),
                          ),
                          Text(
                            '${DateFormat('dd MMM').format(sDate)} – ${DateFormat('dd MMM').format(eDate)}',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.inkMuted),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewDetailRow(String label, String value,
      {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 130,
          child: Text(label,
              style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.inkMuted,
                  fontWeight: FontWeight.w500)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}
