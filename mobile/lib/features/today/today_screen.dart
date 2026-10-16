import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/time_format_provider.dart';
import '../../shared/providers/semesters_provider.dart';
import '../../shared/widgets/app_toast.dart';
import '../../shared/widgets/landscape_header.dart';
import '../../shared/widgets/liquid_glass_card.dart';
import '../../shared/widgets/shimmer_skeleton.dart';
import '../analytics/providers/analytics_provider.dart';
import '../dashboard/providers/dashboard_provider.dart';
import '../setup/academic_setup_screen.dart';
import '../subjects/providers/subjects_provider.dart';
import 'providers/today_provider.dart';

class TodayScreen extends ConsumerStatefulWidget {
  final VoidCallback onOpenDrawer;
  final VoidCallback? onNavigateToProfile;
  final VoidCallback? onOpenSetup;

  const TodayScreen({
    super.key,
    required this.onOpenDrawer,
    this.onNavigateToProfile,
    this.onOpenSetup,
  });

  @override
  ConsumerState<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends ConsumerState<TodayScreen> {
  final ScrollController _timetableScrollCtrl = ScrollController();

  static const List<String> _allDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  @override
  void dispose() {
    _timetableScrollCtrl.dispose();
    super.dispose();
  }

  List<String> _getScheduleDays(TodayState state) {
    final activeSem = ref.watch(semestersProvider).activeSemester;
    if (activeSem != null && activeSem.workingDays.isNotEmpty) {
      final days = activeSem.workingDays
          .where((i) => i >= 0 && i < _allDays.length)
          .map((i) => _allDays[i])
          .toList();
      if (days.isNotEmpty) return days;
    }
    final sIdx = _allDays.indexOf(state.startDay);
    final eIdx = _allDays.indexOf(state.endDay);
    if (sIdx != -1 && eIdx != -1 && sIdx <= eIdx) {
      return _allDays.sublist(sIdx, eIdx + 1);
    }
    return const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday'];
  }

  List<int> _getScheduleHours(TodayState state) {
    final activeSem = ref.watch(semestersProvider).activeSemester;
    int startH = activeSem?.classStartHour ?? state.classStartHour;
    int endH = activeSem?.classEndHour ?? state.classEndHour;
    for (final e in state.timetableEntries) {
      final st = _parseHour(e['start_time'] as String?);
      final et = _parseHour(e['end_time'] as String?);
      if (st != null && st < startH) startH = st;
      if (et != null && et > endH) endH = et;
    }
    if (startH >= endH) {
      return const [9, 10, 11, 12, 13, 14, 15, 16];
    }
    return List.generate(
      (endH - startH).clamp(1, 16),
      (i) => startH + i,
    );
  }

  String _normalizeClassType(dynamic raw) {
    if (raw == null) return 'Theory';
    final s = raw.toString().trim().toUpperCase();
    if (s == 'LAB' || s.contains('LAB') || s.contains('PRACTICAL')) return 'Lab';
    if (s == 'OTHER' || s.contains('OTHER') || s == 'UNSPECIFIED') return 'Others';
    if (s == 'THEORY') return 'Theory';
    return 'Theory';
  }

  String _formatHourDisplay(int hour, {bool is24h = false}) {
    if (is24h) {
      return '${hour.toString().padLeft(2, '0')}:00';
    }
    final period = hour >= 12 ? 'PM' : 'AM';
    final displayH = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
    return '$displayH $period';
  }

  int? _parseHour(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return null;
    try {
      final parts = timeStr.split(':');
      return int.tryParse(parts[0]);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic>? _findEntryStartingAt(List<Map<String, dynamic>> entries, int dayIdx, int hour) {
    for (final e in entries) {
      final d = e['day_of_week'] is int ? e['day_of_week'] as int : 0;
      if (d == dayIdx) {
        final startH = _parseHour(e['start_time'] as String?);
        if (startH == hour) return e;
      }
    }
    return null;
  }

  Map<String, dynamic>? _findEntrySpanning(List<Map<String, dynamic>> entries, int dayIdx, int hour) {
    for (final e in entries) {
      final d = e['day_of_week'] is int ? e['day_of_week'] as int : 0;
      if (d == dayIdx) {
        final startH = _parseHour(e['start_time'] as String?);
        final endH = _parseHour(e['end_time'] as String?);
        if (startH != null && endH != null && hour > startH && hour < endH) {
          return e;
        }
      }
    }
    return null;
  }

  bool _hasEarlierUpcomingToday(List<Map<String, dynamic>> entries, int dayIdx, int currentHour, int targetStartHour) {
    for (final e in entries) {
      final d = e['day_of_week'] is int ? e['day_of_week'] as int : 0;
      if (d == dayIdx) {
        final startH = _parseHour(e['start_time'] as String?);
        if (startH != null && startH > currentHour && startH < targetStartHour) {
          return true;
        }
      }
    }
    return false;
  }

  void _showSlotDetailsSheet(
    BuildContext context,
    Map<String, dynamic> entry,
    String dayName, {
    required bool isLive,
    required bool isNext,
  }) {
    final subName = entry['subject_name'] as String? ?? 'Class';
    final startTime = entry['start_time'] as String? ?? '09:00';
    final endTime = entry['end_time'] as String? ?? '10:00';
    final room = entry['room'] as String? ?? 'Room 101';
    final faculty = entry['faculty_name'] as String? ?? 'Department Faculty';
    final classType = _normalizeClassType(entry['class_type']);
    final is24h = ref.read(timeFormatProvider) == '24h';
    final formattedSlotTime = formatSlotRange(startTime, endTime, is24h: is24h);
    final colorHex = entry['subject_color'] as String? ?? '#C96E5B';
    final isBreak = subName.toLowerCase().contains('break') || entry['subject_code'] == 'BREAK';
    final accentColor = isBreak ? AppColors.amber : AppColors.getSubjectColor(colorHex);
    final isAttended = entry['is_attended'] == true;
    final isAbsent = entry['is_absent'] == true;
    final isNotHeld = entry['is_not_held'] == true;

    final todayState = ref.read(todayProvider);
    DateTime slotDate;
    if (entry['date'] != null) {
      slotDate = DateTime.tryParse(entry['date'].toString()) ?? DateTime.now();
    } else {
      final now = DateTime.now();
      final monday = now.subtract(Duration(days: now.weekday - 1)).add(Duration(days: 7 * todayState.weekOffset));
      final dow = entry['day_of_week'] is int ? entry['day_of_week'] as int : _allDays.indexOf(dayName);
      slotDate = monday.add(Duration(days: dow.clamp(0, 6)));
    }
    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);
    final targetMidnight = DateTime(slotDate.year, slotDate.month, slotDate.day);
    final isFuture = targetMidnight.isAfter(todayMidnight);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(28),
            topRight: Radius.circular(28),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Drag Handle
            Center(
              child: Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row: Subject Name + Close Button
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(isBreak ? Icons.coffee_rounded : Icons.school_rounded, color: accentColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        subName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$dayName (${DateFormat('dd MMM').format(slotDate)}) • $formattedSlotTime',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: AppColors.inkMuted),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),

            const SizedBox(height: 18),

            // Class Detail Chips Row
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (isBreak)
                  _buildInfoBadge(Icons.coffee_rounded, 'Recess / Break', AppColors.amberDark, AppColors.amberLight)
                else ...[
                  _buildInfoBadge(
                    classType.toLowerCase() == 'lab'
                        ? Icons.science_outlined
                        : (classType.toLowerCase() == 'theory' ? Icons.menu_book_rounded : Icons.category_outlined),
                    classType,
                    classType.toLowerCase() == 'lab'
                        ? AppColors.ocean
                        : (classType.toLowerCase() == 'theory' ? AppColors.terracotta : AppColors.ink),
                    classType.toLowerCase() == 'lab'
                        ? AppColors.oceanLight
                        : (classType.toLowerCase() == 'theory' ? AppColors.terracottaLight : const Color(0xFFEFECE9)),
                  ),
                  _buildInfoBadge(Icons.meeting_room_outlined, room, AppColors.sageDark, AppColors.sageLight),
                  _buildInfoBadge(Icons.person_outline_rounded, faculty, AppColors.inkMuted, const Color(0xFFEFECE9)),
                ],
                if (isLive)
                  _buildInfoBadge(Icons.radio_button_checked, isBreak ? 'Break Ongoing' : 'Live Right Now', isBreak ? AppColors.amberDark : AppColors.coral, isBreak ? AppColors.amberLight : AppColors.coralLight)
                else if (isNext)
                  _buildInfoBadge(Icons.schedule_rounded, isBreak ? 'Next Up: Break' : 'Next Class Today', AppColors.amberDark, AppColors.amberLight),
                if (!isBreak) ...[
                  if (isAttended)
                    _buildInfoBadge(Icons.check_circle_rounded, 'Attended', AppColors.sageDark, AppColors.sageLight)
                  else if (isAbsent)
                    _buildInfoBadge(Icons.cancel_outlined, 'Absent', AppColors.coral, AppColors.coralLight)
                  else if (isNotHeld)
                    _buildInfoBadge(Icons.remove_circle_outline, 'Not Held', AppColors.inkMuted, const Color(0xFFEFECE9)),
                ],
              ],
            ),

            const SizedBox(height: 20),

            // Attendance Action Section or Future Notice or Break Notice
            if (isBreak)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF9EE),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.amber.withValues(alpha: 0.35)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.coffee_rounded, size: 20, color: AppColors.amberDark),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Break Period • No attendance tracking required.',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.amberDark,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (isFuture)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9F7F5),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.event_outlined, size: 20, color: AppColors.inkMuted),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'This class is scheduled in the future. Attendance can be recorded once class day arrives.',
                        style: TextStyle(fontSize: 12, color: AppColors.inkMuted, height: 1.4),
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.touch_app_outlined, size: 17, color: AppColors.terracotta),
                        const SizedBox(width: 8),
                        Text(
                          'Update Attendance (${DateFormat('dd MMM').format(slotDate)})',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.ink),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Tap a status below to record or update attendance for this class:',
                      style: TextStyle(fontSize: 11.5, color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildAttendanceActionBtn(
                            label: 'Attended',
                            icon: Icons.check_circle_outline_rounded,
                            isSelected: isAttended,
                            color: AppColors.sageDark,
                            activeBg: AppColors.sageLight,
                            onPressed: () => _markSlotAttendance(
                              context: context,
                              sheetCtx: ctx,
                              entry: entry,
                              slotDate: slotDate,
                              status: 'ATTENDED',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildAttendanceActionBtn(
                            label: 'Absent',
                            icon: Icons.cancel_outlined,
                            isSelected: isAbsent,
                            color: AppColors.coral,
                            activeBg: AppColors.coralLight,
                            onPressed: () => _markSlotAttendance(
                              context: context,
                              sheetCtx: ctx,
                              entry: entry,
                              slotDate: slotDate,
                              status: 'ABSENT',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildAttendanceActionBtn(
                            label: 'Not Held',
                            icon: Icons.remove_circle_outline_rounded,
                            isSelected: isNotHeld,
                            color: AppColors.inkMuted,
                            activeBg: const Color(0xFFEBE7E2),
                            onPressed: () => _markSlotAttendance(
                              context: context,
                              sheetCtx: ctx,
                              entry: entry,
                              slotDate: slotDate,
                              status: 'NOT_HELD',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 18),

            // Open Setup Wizard Action Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.terracotta,
                  side: const BorderSide(color: AppColors.terracotta),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Edit Routine in Academic Setup', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AcademicSetupScreen(
                        onComplete: () => ref.read(todayProvider.notifier).loadToday(),
                        onCancel: () => Navigator.pop(context),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _markSlotAttendance({
    required BuildContext context,
    required BuildContext sheetCtx,
    required Map<String, dynamic> entry,
    required DateTime slotDate,
    required String status,
  }) async {
    Navigator.pop(sheetCtx);
    try {
      final client = ApiClient();
      final dateStr = DateFormat('yyyy-MM-dd').format(slotDate);
      final item = <String, dynamic>{
        'status': status,
        if (entry['session_id'] != null && (entry['session_id'] as String).isNotEmpty)
          'session_id': entry['session_id'],
        if (entry['timetable_entry_id'] != null && (entry['timetable_entry_id'] as String).isNotEmpty)
          'timetable_entry_id': entry['timetable_entry_id'],
        if (entry['subject_id'] != null && (entry['subject_id'] as String).isNotEmpty)
          'subject_id': entry['subject_id'],
      };

      await client.dio.post(
        ApiEndpoints.bulkDayAttendance,
        data: {
          'date': dateStr,
          'records': [item],
          'items': [item],
        },
      );

      await ref.read(todayProvider.notifier).loadToday();
      ref.invalidate(dashboardProvider);
      ref.invalidate(selectedDateAttendanceProvider);
      ref.invalidate(subjectsProvider);
      ref.invalidate(analyticsProvider);

      if (context.mounted) {
        final label = status == 'ATTENDED' ? 'Attended' : (status == 'ABSENT' ? 'Absent' : 'Not Held');
        AppToast.success(context, 'Marked as $label for ${DateFormat('dd MMM').format(slotDate)}');
      }
    } catch (e) {
      if (context.mounted) {
        AppToast.error(context, 'Failed to update attendance');
      }
    }
  }

  Widget _buildAttendanceActionBtn({
    required String label,
    required IconData icon,
    required bool isSelected,
    required Color color,
    required Color activeBg,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? activeBg : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : AppColors.divider,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: isSelected ? color : AppColors.inkMuted),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                color: isSelected ? color : AppColors.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoBadge(IconData icon, String text, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(todayProvider);
    final showSkeleton = !state.hasLoaded ||
        (state.isLoading && state.timetableEntries.isEmpty) ||
        (state.isLoadingWeek && state.timetableEntries.isEmpty);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        clipBehavior: Clip.hardEdge,
        padding: const EdgeInsets.only(bottom: 120),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // App Bar / Shell Header
            LandscapeHeaderWidget(
              greeting: 'Weekly Routine',
              userName: 'Plan & Track Classes',
              semesterInfo: '${state.semesterLabel} • Classes',
              showActions: false,
              topOffset: 76,
              isLoading: showSkeleton,
            ),

            const SizedBox(height: 16),

            // Routine Screen Content or Shimmer Skeleton
            if (showSkeleton)
              _buildWeeklyRoutineSkeleton(context)
            else
              _buildWeeklyRoutineView(context, state),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyRoutineSkeleton(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Action Row Skeleton (Today indicator & view toggle)
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SkeletonBox(
                  width: 140,
                  height: 32,
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
                SkeletonBox(
                  width: 90,
                  height: 32,
                  borderRadius: BorderRadius.all(Radius.circular(16)),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Timetable Grid Card Skeleton
            LiquidGlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Timetable header bar
                  Row(
                    children: [
                      const SkeletonBox(
                        width: 48,
                        height: 26,
                        borderRadius: BorderRadius.all(Radius.circular(6)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: List.generate(
                            4,
                            (i) => const Expanded(
                              child: Padding(
                                padding: EdgeInsets.symmetric(horizontal: 3),
                                child: SkeletonBox(
                                  height: 26,
                                  borderRadius: BorderRadius.all(Radius.circular(6)),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 5 Day Rows Skeleton
                  ...List.generate(
                    5,
                    (dayIdx) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          const SkeletonBox(
                            width: 48,
                            height: 50,
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Row(
                              children: List.generate(
                                4,
                                (colIdx) => const Expanded(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 3),
                                    child: SkeletonBox(
                                      height: 50,
                                      borderRadius: BorderRadius.all(Radius.circular(8)),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                  // Legend bar placeholder
                  const SkeletonBox.text(width: 220, height: 12),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Guidance Note Card Skeleton
            const LiquidGlassCard(
              padding: EdgeInsets.all(14),
              child: Row(
                children: [
                  SkeletonBox.circle(size: 28),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SkeletonBox.text(width: 160, height: 12),
                        SizedBox(height: 6),
                        SkeletonBox.text(width: 240, height: 10),
                      ],
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

  // ==========================================
  // WEEKLY ROUTINE VIEW
  // ==========================================
  Widget _buildWeeklyRoutineView(BuildContext context, TodayState state) {
    final activeDays = _getScheduleDays(state);
    final hours = _getScheduleHours(state);
    final entries = state.timetableEntries;
    final now = DateTime.now();
    final currentDayIdx = now.weekday - 1; // 0=Mon, 6=Sun
    final currentHour = now.hour;
    final is24h = ref.watch(timeFormatProvider) == '24h';

    // Calculate semester date boundaries for week navigation
    final activeSem = ref.watch(semestersProvider).activeSemester;
    DateTime? semStart;
    DateTime? semEnd;
    if (activeSem != null) {
      semStart = DateTime.tryParse(activeSem.startDate);
      semEnd = DateTime.tryParse(activeSem.endDate);
    }
    final startLimit = semStart != null ? DateTime(semStart.year, semStart.month, semStart.day) : null;
    final endLimit = semEnd != null ? DateTime(semEnd.year, semEnd.month, semEnd.day) : null;

    final todayMidnight = DateTime(now.year, now.month, now.day);
    final currentMonday = todayMidnight
        .subtract(Duration(days: todayMidnight.weekday - 1))
        .add(Duration(days: 7 * state.weekOffset));

    final prevSunday = currentMonday.subtract(const Duration(days: 1));
    final nextMonday = currentMonday.add(const Duration(days: 7));

    final canGoPrev = startLimit == null || !prevSunday.isBefore(startLimit);
    final canGoNext = endLimit == null || !nextMonday.isAfter(endLimit);

    const double dayColWidth = 64.0;
    const double hourColWidth = 140.0;
    const double slotHeight = 96.0;

    // Check if empty
    if (state.isTimetableEmpty && state.hasLoaded && !state.isLoading && !state.isLoadingWeek) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: LiquidGlassCard(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.terracotta.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.calendar_view_week_rounded, color: AppColors.terracotta, size: 28),
              ),
              const SizedBox(height: 16),
              const Text(
                'Your timetable isn\'t set up yet.',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              const Text(
                'Add your recurring classes in Academic Setup to view your weekly routine grid.',
                style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.terracotta,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.tune_rounded, size: 18),
                label: const Text('Set Up Timetable', style: TextStyle(fontWeight: FontWeight.w700)),
                onPressed: () {
                  if (widget.onOpenSetup != null) {
                    widget.onOpenSetup!();
                  } else {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AcademicSetupScreen(
                          onComplete: () => ref.read(todayProvider.notifier).loadToday(),
                          onCancel: () => Navigator.of(context).pop(),
                        ),
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Week Navigator
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LiquidGlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    Icons.chevron_left_rounded,
                    color: canGoPrev ? AppColors.ink : AppColors.inkMuted.withValues(alpha: 0.3),
                  ),
                  onPressed: canGoPrev
                      ? () {
                          ref.read(todayProvider.notifier).setWeekOffset(state.weekOffset - 1);
                        }
                      : null,
                ),
                Expanded(
                  child: Column(
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          state.weekLabel,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: AppColors.ink),
                        ),
                      ),
                      if (state.dateRangeDisplay.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            state.dateRangeDisplay,
                            style: const TextStyle(fontSize: 11, color: AppColors.inkMuted, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.chevron_right_rounded,
                    color: canGoNext ? AppColors.ink : AppColors.inkMuted.withValues(alpha: 0.3),
                  ),
                  onPressed: canGoNext
                      ? () {
                          ref.read(todayProvider.notifier).setWeekOffset(state.weekOffset + 1);
                        }
                      : null,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 14),

        // Hero Spotlight Card (Time-Aware Live / Next Class)
        if (state.weekOffset == 0) ...[
          if (_buildHeroSpotlightCard(context, state, activeDays, currentDayIdx, currentHour) case final heroCard?) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: heroCard,
            ),
            const SizedBox(height: 14),
          ],
        ],

        // Section Title & Routine Subtitle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weekly Schedule Grid',
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: AppColors.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'Read-only schedule • Scroll horizontally to inspect slots',
                      style: TextStyle(fontSize: 11, color: AppColors.inkMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: state.isLoadingWeek ? AppColors.amberLight : AppColors.sageLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  state.isLoadingWeek ? 'Updating...' : '${entries.length} slots',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: state.isLoadingWeek ? AppColors.amberDark : AppColors.sageDark,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // FULL WEEKLY TIMETABLE GRID WITH PINNED DAY COLUMN (or scoped skeleton during week switch)
        if (state.isLoadingWeek)
          _buildSkeletonWeeklyGrid(activeDays, hours)
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
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
                  ),
                  child: Column(
                    children: [
                      // Top Left Header Cell (Corner Intersection)
                      Container(
                        height: 38,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF9F7F5),
                          border: Border(bottom: BorderSide(color: AppColors.divider)),
                        ),
                        child: const Text(
                          'DAY',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: AppColors.inkMuted,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),

                      // Day Rows Header Labels
                      ...List.generate(activeDays.length, (idx) {
                        final dName = activeDays[idx];
                        final dayIdx = _allDays.indexOf(dName);
                        final isToday = (state.weekOffset == 0) && (dayIdx == currentDayIdx);

                        return Container(
                          height: slotHeight,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isToday ? const Color(0xFFFFF2EE) : Colors.transparent,
                            border: const Border(bottom: BorderSide(color: AppColors.divider)),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                dName.substring(0, 3).toUpperCase(),
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  color: isToday ? AppColors.terracotta : AppColors.ink,
                                ),
                              ),
                              if (isToday) ...[
                                const SizedBox(height: 3),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.terracotta,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'TODAY',
                                    style: TextStyle(fontSize: 7.5, fontWeight: FontWeight.w900, color: Colors.white),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),

                // 2. SCROLLABLE HORIZONTAL TIMELINE GRID
                Expanded(
                  child: SingleChildScrollView(
                    controller: _timetableScrollCtrl,
                    scrollDirection: Axis.horizontal,
                    physics: const ClampingScrollPhysics(),
                    child: SizedBox(
                      width: hourColWidth * hours.length,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Time Headers Row
                          Container(
                            height: 38,
                            decoration: const BoxDecoration(
                              color: Color(0xFFFDFCFA),
                              border: Border(bottom: BorderSide(color: AppColors.divider)),
                            ),
                            child: Row(
                              children: hours.map((h) {
                                return Container(
                                  width: hourColWidth,
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.only(left: 10),
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      right: BorderSide(color: AppColors.divider),
                                    ),
                                  ),
                                  child: Text(
                                    _formatHourDisplay(h, is24h: is24h),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.inkMuted,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                          // Day Slots Rows
                          ...List.generate(activeDays.length, (idx) {
                            final dName = activeDays[idx];
                            final dayIdx = _allDays.indexOf(dName);
                            return _buildDaySlotsRow(
                              context: context,
                              entries: entries,
                              dayName: dName,
                              dayIdx: dayIdx,
                              hours: hours,
                              hourColWidth: hourColWidth,
                              slotHeight: slotHeight,
                              currentDayIdx: currentDayIdx,
                              currentHour: currentHour,
                              isCurrentWeek: state.weekOffset == 0,
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Color & Badge Legend
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _buildLegendChip(AppColors.sageDark, 'Attended (Saved)'),
              _buildLegendChip(AppColors.terracotta, 'Now Active'),
              _buildLegendChip(AppColors.amberDark, 'Next Upcoming'),
              _buildLegendChip(AppColors.inkMuted, 'Scheduled / Unticked'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDaySlotsRow({
    required BuildContext context,
    required List<Map<String, dynamic>> entries,
    required String dayName,
    required int dayIdx,
    required List<int> hours,
    required double hourColWidth,
    required double slotHeight,
    required int currentDayIdx,
    required int currentHour,
    required bool isCurrentWeek,
  }) {
    final List<Widget> cells = [];
    int i = 0;

    while (i < hours.length) {
      final hour = hours[i];
      final startingEntry = _findEntryStartingAt(entries, dayIdx, hour);

      if (startingEntry != null) {
        final startH = _parseHour(startingEntry['start_time'] as String?) ?? hour;
        final endH = _parseHour(startingEntry['end_time'] as String?) ?? (startH + 1);
        final remainingHours = hours.length - i;
        final span = (endH - startH).clamp(1, remainingHours);
        final blockWidth = hourColWidth * span;

        final isToday = isCurrentWeek && (dayIdx == currentDayIdx);
        final isLiveNow = isToday && currentHour >= startH && currentHour < endH;
        final isNextUpcoming = isToday && currentHour < startH && !_hasEarlierUpcomingToday(entries, dayIdx, currentHour, startH);
        final isAttended = startingEntry['is_attended'] == true;

        cells.add(
          Container(
            width: blockWidth,
            height: slotHeight,
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: isToday ? const Color(0xFFFFFBF8) : AppColors.surface,
              border: const Border(
                right: BorderSide(color: AppColors.divider),
                bottom: BorderSide(color: AppColors.divider),
              ),
            ),
            child: _buildScheduledSlotCard(
              context: context,
              entry: startingEntry,
              dayName: dayName,
              isAttended: isAttended,
              isLive: isLiveNow,
              isNext: isNextUpcoming,
              span: span,
            ),
          ),
        );
        i += span;
      } else {
        final spanningEntry = _findEntrySpanning(entries, dayIdx, hour);
        if (spanningEntry != null) {
          final endH = _parseHour(spanningEntry['end_time'] as String?) ?? (hour + 1);
          final remainingHours = hours.length - i;
          final span = (endH - hour).clamp(1, remainingHours);
          final blockWidth = hourColWidth * span;

          final isToday = isCurrentWeek && (dayIdx == currentDayIdx);
          final startH = _parseHour(spanningEntry['start_time'] as String?) ?? hour;
          final isLiveNow = isToday && currentHour >= startH && currentHour < endH;
          final isAttended = spanningEntry['is_attended'] == true;

          cells.add(
            Container(
              width: blockWidth,
              height: slotHeight,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: isToday ? const Color(0xFFFFFBF8) : AppColors.surface,
                border: const Border(
                  right: BorderSide(color: AppColors.divider),
                  bottom: BorderSide(color: AppColors.divider),
                ),
              ),
              child: _buildScheduledSlotCard(
                context: context,
                entry: spanningEntry,
                dayName: dayName,
                isAttended: isAttended,
                isLive: isLiveNow,
                isNext: false,
                span: span,
              ),
            ),
          );
          i += span;
        } else {
          // Empty Slot Cell
          final isToday = isCurrentWeek && (dayIdx == currentDayIdx);
          cells.add(
            Container(
              width: hourColWidth,
              height: slotHeight,
              decoration: BoxDecoration(
                color: isToday ? const Color(0xFFFFFDFB) : AppColors.surface,
                border: const Border(
                  right: BorderSide(color: Color(0xFFF0EBE6)),
                  bottom: BorderSide(color: AppColors.divider),
                ),
              ),
              child: Center(
                child: Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE5DDD5),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
          );
          i++;
        }
      }
    }

    return Row(children: cells);
  }

  Widget _buildScheduledSlotCard({
    required BuildContext context,
    required Map<String, dynamic> entry,
    required String dayName,
    required bool isAttended,
    required bool isLive,
    required bool isNext,
    required int span,
  }) {
    final subName = entry['subject_name'] as String? ?? 'Class';
    final startTime = entry['start_time'] as String? ?? '09:00';
    final endTime = entry['end_time'] as String? ?? '10:00';
    final room = entry['room'] as String? ?? 'Room 101';
    final classType = _normalizeClassType(entry['class_type']);
    final is24h = ref.watch(timeFormatProvider) == '24h';
    final formattedSlotTime = formatSlotRange(startTime, endTime, is24h: is24h);
    final colorHex = entry['subject_color'] as String? ?? '#C96E5B';
    final isBreak = subName.toLowerCase().contains('break') || entry['subject_code'] == 'BREAK';
    final accentColor = isBreak ? AppColors.amber : AppColors.getSubjectColor(colorHex);

    Color cardBg;
    Border? border;

    if (isBreak) {
      cardBg = const Color(0xFFFEF9EE);
      border = Border.all(
        color: isLive
            ? AppColors.amberDark
            : AppColors.amber.withValues(alpha: 0.45),
        width: isLive ? 1.5 : 1,
      );
    } else if (isLive) {
      cardBg = const Color(0xFFFBECE9);
      border = Border.all(color: AppColors.terracotta, width: 1.5);
    } else if (isNext) {
      cardBg = const Color(0xFFFEF7ED);
      border = Border.all(color: AppColors.amberDark, width: 1.2);
    } else {
      cardBg = accentColor.withValues(alpha: 0.08);
      border = Border.all(color: accentColor.withValues(alpha: 0.25), width: 1);
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showSlotDetailsSheet(
          context,
          entry,
          dayName,
          isLive: isLive,
          isNext: isNext,
        ),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(10),
            border: border,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Top Row: Type Tag + Status Indicator (Tick ONLY when genuinely ATTENDED)
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: isBreak
                          ? AppColors.amber.withValues(alpha: 0.2)
                          : accentColor.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!isBreak) ...[
                          Icon(
                            classType.toLowerCase() == 'lab'
                                ? Icons.science_outlined
                                : (classType.toLowerCase() == 'theory' ? Icons.menu_book_rounded : Icons.category_outlined),
                            size: 9,
                            color: isBreak ? AppColors.amberDark : accentColor,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Text(
                          isBreak ? 'BREAK' : classType.toUpperCase(),
                          style: TextStyle(
                            fontSize: 8.5,
                            fontWeight: FontWeight.w800,
                            color: isBreak ? AppColors.amberDark : accentColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (isLive) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: isBreak ? AppColors.amberDark : AppColors.terracotta,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'NOW',
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ),
                  ] else if (isNext) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: AppColors.amberDark,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'NEXT',
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ),
                  ] else if (isAttended && !isBreak) ...[
                    // Strictly actual persisted ATTENDED record shows a green checkmark
                    const Icon(Icons.check_circle_rounded, size: 13, color: AppColors.sageDark),
                  ],
                ],
              ),

              // Middle: Subject Name
              Row(
                children: [
                  if (isBreak) ...[
                    const Icon(Icons.coffee_rounded, size: 13, color: AppColors.amberDark),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: Text(
                      subName,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                        color: isBreak
                            ? AppColors.amberDark
                            : (isLive ? AppColors.terracottaDark : AppColors.ink),
                        height: 1.2,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),

              // Bottom: Time & Room
              Row(
                children: [
                  const Icon(Icons.access_time_rounded, size: 10, color: AppColors.inkMuted),
                  const SizedBox(width: 3),
                  Expanded(
                    child: Text(
                      isBreak
                          ? formattedSlotTime
                          : (room.isNotEmpty ? '$formattedSlotTime • $room' : formattedSlotTime),
                      style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildHeroSpotlightCard(
    BuildContext context,
    TodayState state,
    List<String> activeDays,
    int currentDayIdx,
    int currentHour,
  ) {
    final entries = state.timetableEntries;
    Map<String, dynamic>? liveClass;
    Map<String, dynamic>? nextClass;

    final todayEntries = entries.where((t) => (t['day_of_week'] is int ? t['day_of_week'] : 0) == currentDayIdx).toList()
      ..sort((a, b) => ((a['start_time'] as String?) ?? '').compareTo((b['start_time'] as String?) ?? ''));

    for (final e in todayEntries) {
      final startH = _parseHour(e['start_time'] as String?);
      final endH = _parseHour(e['end_time'] as String?);
      if (startH != null && endH != null) {
        if (currentHour >= startH && currentHour < endH) {
          liveClass = e;
          break;
        }
      }
    }

    if (liveClass == null) {
      for (final e in todayEntries) {
        final startH = _parseHour(e['start_time'] as String?);
        if (startH != null && startH > currentHour) {
          nextClass = e;
          break;
        }
      }
    }

    if (liveClass != null) {
      final isLiveBreak = (liveClass['subject_name'] as String? ?? '').toLowerCase().contains('break') || liveClass['subject_code'] == 'BREAK';
      return LiquidGlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (isLiveBreak ? AppColors.amber : AppColors.terracotta).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isLiveBreak ? Icons.coffee_rounded : Icons.radio_button_checked,
                color: isLiveBreak ? AppColors.amberDark : AppColors.terracotta,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isLiveBreak ? AppColors.amberDark : AppColors.terracotta,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isLiveBreak ? 'BREAK TIME NOW' : 'LIVE CLASS NOW',
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                      Text(
                        formatSlotRange(liveClass['start_time'] ?? '', liveClass['end_time'] ?? '', is24h: ref.watch(timeFormatProvider) == '24h'),
                        style: const TextStyle(fontSize: 10, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    liveClass['subject_name'] ?? 'Class',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.ink),
                  ),
                  Text(
                    isLiveBreak ? 'Break Period • No attendance required' : '${liveClass['room'] ?? 'Room'} • ${liveClass['faculty_name'] ?? 'Faculty'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (nextClass != null) {
      final isNextBreak = (nextClass['subject_name'] as String? ?? '').toLowerCase().contains('break') || nextClass['subject_code'] == 'BREAK';
      return LiquidGlassCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.amber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isNextBreak ? Icons.coffee_rounded : Icons.schedule_rounded,
                color: AppColors.amberDark,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.amberDark,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isNextBreak ? 'NEXT UP: BREAK' : 'NEXT CLASS TODAY',
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w900, color: Colors.white),
                        ),
                      ),
                      Text(
                        'Starts at ${formatTimeString(nextClass['start_time'] ?? '', is24h: ref.watch(timeFormatProvider) == '24h')}',
                        style: const TextStyle(fontSize: 10, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    nextClass['subject_name'] ?? 'Class',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: AppColors.ink),
                  ),
                  Text(
                    isNextBreak ? 'Break Period' : '${nextClass['room'] ?? 'Room'} • ${nextClass['faculty_name'] ?? 'Faculty'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: AppColors.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // No active or upcoming classes scheduled today: return null so no card is rendered
    return null;
  }

  Widget _buildLegendChip(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: AppColors.inkMuted, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _buildSkeletonWeeklyGrid(List<String> activeDays, List<int> hours) {
    const double dayColWidth = 64.0;
    const double hourColWidth = 140.0;
    const double slotHeight = 96.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
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
            // Fixed Left Day Column
            Container(
              width: dayColWidth,
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(
                  right: BorderSide(color: AppColors.divider, width: 1.0),
                ),
              ),
              child: Column(
                children: [
                  Container(
                    height: 38,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: Color(0xFFF9F7F5),
                      border: Border(bottom: BorderSide(color: AppColors.divider)),
                    ),
                    child: const Text(
                      'DAY',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: AppColors.inkMuted,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                  for (final day in activeDays)
                    Container(
                      height: slotHeight,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.divider)),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            day.substring(0, 3).toUpperCase(),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: 14,
                            height: 2,
                            decoration: BoxDecoration(
                              color: AppColors.inkMuted.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // Horizontally Scrollable Grid Area with Skeletons
            Expanded(
              child: SingleChildScrollView(
                controller: _timetableScrollCtrl,
                scrollDirection: Axis.horizontal,
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Hour Header Row
                    Row(
                      children: [
                        for (final h in hours)
                          Container(
                            width: hourColWidth,
                            height: 38,
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF9F7F5),
                              border: Border(
                                right: BorderSide(color: AppColors.divider),
                                bottom: BorderSide(color: AppColors.divider),
                              ),
                            ),
                            child: Text(
                              _formatHourDisplay(h),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ),
                      ],
                    ),
                    // Skeleton Slot Rows
                    for (int d = 0; d < activeDays.length; d++)
                      Row(
                        children: [
                          for (int h = 0; h < hours.length; h++)
                            Container(
                              width: hourColWidth,
                              height: slotHeight,
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                border: Border(
                                  right: BorderSide(color: AppColors.divider),
                                  bottom: BorderSide(color: AppColors.divider),
                                ),
                              ),
                              child: ((d + h) % 3 == 0)
                                  ? Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.surface,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: AppColors.divider.withValues(alpha: 0.6)),
                                      ),
                                      child: const Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          SkeletonBox.text(width: 70, height: 10),
                                          SkeletonBox.text(width: 90, height: 12),
                                          SkeletonBox.text(width: 50, height: 9),
                                        ],
                                      ),
                                    )
                                  : Center(
                                      child: Container(
                                        width: 4,
                                        height: 4,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFE5DDD5),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

