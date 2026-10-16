import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_endpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/models/semester_model.dart';
import '../../shared/models/user_model.dart';
import '../../shared/providers/semesters_provider.dart';
import '../../core/theme/time_format_provider.dart';
import '../auth/providers/auth_provider.dart';
import '../dashboard/providers/dashboard_provider.dart';
import 'providers/profile_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  final VoidCallback onBack;
  final VoidCallback? onOpenSetup;

  const ProfileScreen({
    super.key,
    required this.onBack,
    this.onOpenSetup,
  });

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  String? _editingFieldKey;
  late TextEditingController _editController;
  late FocusNode _editFocusNode;
  bool _isSaving = false;
  bool _isLoggingOut = false;

  @override
  void initState() {
    super.initState();
    _editController = TextEditingController();
    _editFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _editController.dispose();
    _editFocusNode.dispose();
    super.dispose();
  }

  String _formatShortDate(String dateStr) {
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('dd MMM yyyy').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  void _startEditing(String fieldKey, String currentValue) {
    HapticFeedback.selectionClick();
    setState(() {
      _editingFieldKey = fieldKey;
      _editController.text = currentValue;
      _editController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: currentValue.length,
      );
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editFocusNode.canRequestFocus) {
        _editFocusNode.requestFocus();
      }
    });
  }

  Future<void> _saveCurrentEdit(AcademicProfileModel profile, [SemesterModel? activeSem]) async {
    if (_editingFieldKey == null || _isSaving) return;
    final key = _editingFieldKey!;
    final text = _editController.text.trim();

    setState(() {
      _editingFieldKey = null;
      _isSaving = true;
    });

    try {
      final client = ApiClient();
      if (key == 'current_semester_label') {
        if (activeSem != null && activeSem.id.isNotEmpty) {
          await client.dio.patch(
            '${ApiEndpoints.semesters}/${activeSem.id}',
            data: {'label': text.isEmpty ? activeSem.label : text},
          );
          ref.invalidate(semestersProvider);
        }
        await client.dio.patch(
          ApiEndpoints.profile,
          data: {'current_semester_label': text},
        );
        ref.invalidate(profileProvider);
        ref.invalidate(dashboardProvider);
      } else {
        dynamic payloadValue = text;
        if (key == 'academic_duration_years') {
          payloadValue = int.tryParse(text) ?? profile.academicDurationYears;
        } else if (key == 'academic_session_start') {
          final parts = text.split(RegExp(r'[\s–-]+')).where((p) => p.isNotEmpty).toList();
          final startYear = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? profile.academicSessionStart ?? 2024;
          final endYear = parts.length > 1
              ? (int.tryParse(parts[1]) ?? (startYear + profile.academicDurationYears))
              : (startYear + profile.academicDurationYears);
          await client.dio.patch(
            ApiEndpoints.profile,
            data: {
              'academic_session_start': startYear,
              'academic_session_end': endYear,
            },
          );
          ref.invalidate(profileProvider);
          ref.invalidate(dashboardProvider);
          HapticFeedback.lightImpact();
          return;
        } else if (key == 'personal_target') {
          final clean = text.replaceAll('%', '').trim();
          payloadValue = double.tryParse(clean) ?? profile.personalTarget;
        } else if (key == 'low_attendance_alert') {
          final clean = text.replaceAll('%', '').trim();
          payloadValue = double.tryParse(clean) ?? profile.lowAttendanceAlert;
        }

        await client.dio.patch(
          ApiEndpoints.profile,
          data: {key: payloadValue},
        );
        ref.invalidate(profileProvider);
        ref.invalidate(dashboardProvider);
      }
      HapticFeedback.lightImpact();
    } catch (e) {
      debugPrint('Error saving profile field $key: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _pickSemesterTimeline(SemesterModel activeSem) async {
    DateTime startDt = DateTime.tryParse(activeSem.startDate) ?? DateTime.now();
    DateTime endDt = DateTime.tryParse(activeSem.endDate) ?? DateTime.now().add(const Duration(days: 120));
    if (endDt.isBefore(startDt)) {
      endDt = startDt.add(const Duration(days: 30));
    }

    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: startDt, end: endDt),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppColors.terracotta,
              onPrimary: Colors.white,
              surface: AppColors.surface,
              onSurface: AppColors.ink,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      final startStr = DateFormat('yyyy-MM-dd').format(picked.start);
      final endStr = DateFormat('yyyy-MM-dd').format(picked.end);
      try {
        final client = ApiClient();
        await client.dio.patch(
          '${ApiEndpoints.semesters}/${activeSem.id}',
          data: {
            'start_date': startStr,
            'end_date': endStr,
          },
        );
        ref.invalidate(semestersProvider);
        ref.invalidate(profileProvider);
        ref.invalidate(dashboardProvider);
        HapticFeedback.lightImpact();
      } catch (e) {
        debugPrint('Error updating semester timeline: $e');
      }
    }
  }

  void _showHelpSupport(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.help_outline_rounded,
                        color: AppColors.terracotta, size: 22),
                    SizedBox(width: 8),
                    Text(
                      'Help & Support',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Frequently Asked Questions',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(height: 8),
            _buildFaqItem(
              'How are Safe Absences calculated?',
              'AttendiFy uses the pure formula: max(0, floor((Attended - 0.75 * Conducted) / 0.75)). If current attendance is below 75%, safe absences are strictly 0.',
            ),
            _buildFaqItem(
              'What if a class is cancelled or not held?',
              'Sessions marked NOT_HELD, CANCELLED, or scheduled on holidays never count against your attendance total.',
            ),
            _buildFaqItem(
              'How do I update semester, subjects or routine?',
              'Use Academic Setup located above Attendance Settings to adjust term dates, courses, timetable slots, and target attendance.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFBF6F3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: const Row(
                children: [
                  Icon(Icons.mail_outline_rounded,
                      color: AppColors.inkMuted, size: 20),
                  SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Need more assistance?',
                            style: TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600)),
                        Text('Contact us at support@attendify.app',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.inkMuted)),
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

  Widget _buildFaqItem(String question, String answer) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                color: AppColors.ink),
          ),
          const SizedBox(height: 2),
          Text(
            answer,
            style: const TextStyle(
                fontSize: 11, color: AppColors.inkMuted, height: 1.3),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.terracottaLight,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.school_rounded,
                  color: AppColors.terracotta, size: 20),
            ),
            const SizedBox(width: 10),
            const Text('About AttendiFy',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AttendiFy v1.0.1',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            SizedBox(height: 4),
            Text(
              'Student-first attendance tracking and forecasting utility.',
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
            ),
            SizedBox(height: 12),
            Text(
              '• 75.0% Attendance Threshold Default\n• Independent Student Record\n• Semester & User Isolated\n• Warm Design System & Liquid Glass',
              style: TextStyle(fontSize: 12, height: 1.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close',
                style: TextStyle(
                    color: AppColors.terracotta, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(profileProvider);
    final semestersState = ref.watch(semestersProvider);
    final activeSem = semestersState.activeSemester;
    final timeFormat = ref.watch(timeFormatProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: AppColors.ink),
          onPressed: widget.onBack,
        ),
        title: const Text(
          'Profile',
          style: TextStyle(
            fontFamily: 'serif',
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: profileAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.terracotta)),
        error: (err, _) => Center(child: Text(err.toString())),
        data: (profile) => SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manage your academic details and preferences',
                style:
                    AppTypography.bodySmall.copyWith(color: AppColors.inkMuted),
              ),
              const SizedBox(height: 16),

              // 1. Compact User Card (Clean profile overview without edit icons)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.divider),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadowWarm,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0xFF4A2421),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        profile.fullName.isNotEmpty
                            ? profile.fullName[0].toUpperCase()
                            : 'S',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            profile.fullName.isNotEmpty ? profile.fullName : 'Student',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppColors.ink,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            profile.studentIdNumber != null && profile.studentIdNumber!.isNotEmpty
                                ? (profile.studentIdNumber!.toLowerCase().startsWith('id:')
                                    ? profile.studentIdNumber!
                                    : 'ID: ${profile.studentIdNumber!}')
                                : 'ID: Not Set',
                            style: AppTypography.bodySmall.copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color: AppColors.inkMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            profile.courseName.isNotEmpty ? profile.courseName : 'Not specified',
                            style: AppTypography.bodySmall.copyWith(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.terracotta,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 2. Academic Information Section (Inline Editable with pencil icons)
              _buildSectionHeader(Icons.school_rounded, 'Academic Information'),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
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
                  children: [
                    _buildRowItem(
                      icon: Icons.person_outline_rounded,
                      label: 'Full Name',
                      value: profile.fullName.isNotEmpty ? profile.fullName : 'Not Set',
                      fieldKey: 'full_name',
                      profile: profile,
                      activeSem: activeSem,
                    ),
                    const Divider(color: AppColors.divider, height: 1),
                    _buildRowItem(
                      icon: Icons.account_balance_outlined,
                      label: 'University',
                      value: profile.universityName.isNotEmpty ? profile.universityName : 'Not Set',
                      fieldKey: 'university_name',
                      profile: profile,
                      activeSem: activeSem,
                    ),
                    const Divider(color: AppColors.divider, height: 1),
                    _buildRowItem(
                      icon: Icons.menu_book_outlined,
                      label: 'Course',
                      value: profile.courseName.isNotEmpty ? profile.courseName : 'Not Set',
                      fieldKey: 'course_name',
                      profile: profile,
                      activeSem: activeSem,
                    ),
                    const Divider(color: AppColors.divider, height: 1),
                    _buildRowItem(
                      icon: Icons.badge_outlined,
                      label: 'Student ID',
                      value: (profile.studentIdNumber != null && profile.studentIdNumber!.isNotEmpty)
                          ? profile.studentIdNumber!
                          : 'Not Set',
                      fieldKey: 'student_id_number',
                      profile: profile,
                      activeSem: activeSem,
                    ),
                    const Divider(color: AppColors.divider, height: 1),
                    _buildRowItem(
                      icon: Icons.date_range_outlined,
                      label: 'Total Years',
                      value: '${profile.academicDurationYears} Years',
                      fieldKey: 'academic_duration_years',
                      profile: profile,
                      activeSem: activeSem,
                    ),
                    const Divider(color: AppColors.divider, height: 1),
                    _buildRowItem(
                      icon: Icons.layers_outlined,
                      label: 'Current Semester',
                      value: (profile.currentSemesterLabel != null && profile.currentSemesterLabel!.isNotEmpty)
                          ? profile.currentSemesterLabel!
                          : (activeSem?.label ?? 'Not Set'),
                      fieldKey: 'current_semester_label',
                      profile: profile,
                      activeSem: activeSem,
                    ),
                    if (activeSem != null) ...[
                      const Divider(color: AppColors.divider, height: 1),
                      _buildRowItem(
                        icon: Icons.date_range_outlined,
                        label: 'Semester Timeline',
                        value: _formatShortDate(activeSem.startDate),
                        secondaryValue: _formatShortDate(activeSem.endDate),
                        fieldKey: 'semester_timeline',
                        isDateRange: true,
                        onDateTap: () => _pickSemesterTimeline(activeSem),
                        profile: profile,
                        activeSem: activeSem,
                      ),
                    ],
                    const Divider(color: AppColors.divider, height: 1),
                    _buildRowItem(
                      icon: Icons.calendar_month_outlined,
                      label: 'Academic Session',
                      value:
                          '${profile.academicSessionStart ?? 2024} – ${profile.academicSessionEnd ?? 2028}',
                      fieldKey: 'academic_session_start',
                      profile: profile,
                      activeSem: activeSem,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 3. Prominent Academic Setup Wizard Card (Moved to just above Attendance Settings)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFFF7F5), Color(0xFFFBF2EE)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.terracotta.withValues(alpha: 0.35)),
                  boxShadow: const [
                    BoxShadow(
                      color: AppColors.shadowWarm,
                      blurRadius: 8,
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
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: AppColors.terracotta,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.tune_rounded, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Academic Setup',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                  color: AppColors.ink,
                                ),
                              ),
                              SizedBox(height: 2),
                              Text(
                                'Reconfigure semester, timings, subjects & routine',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.terracotta,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.school_rounded, size: 17),
                        label: const Text(
                          'Open Academic Setup',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        ),
                        onPressed: widget.onOpenSetup,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 4. System Configurations Section (Inline Editable with pencil icons & timing format)
              _buildSectionHeader(
                  Icons.tune_rounded, 'System Configurations'),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
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
                  children: [
                    _buildRowItem(
                      icon: Icons.timer_outlined,
                      label: 'Target Attendance',
                      value:
                          '${profile.personalTarget.toStringAsFixed(0)}%',
                      fieldKey: 'personal_target',
                      profile: profile,
                      activeSem: activeSem,
                    ),
                    const Divider(color: AppColors.divider, height: 1),
                    _buildRowItem(
                      icon: Icons.notifications_none_rounded,
                      label: 'Low Attendance Alert',
                      value:
                          '${profile.lowAttendanceAlert.toStringAsFixed(0)}%',
                      fieldKey: 'low_attendance_alert',
                      profile: profile,
                      activeSem: activeSem,
                    ),
                    const Divider(color: AppColors.divider, height: 1),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.schedule_rounded, size: 20, color: AppColors.inkMuted),
                              SizedBox(width: 12),
                              Text(
                                'Timing Format',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: AppColors.ink,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF3EFEA),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildTimeFormatOption(
                                  label: '12-hour',
                                  isSelected: timeFormat == '12h',
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    ref.read(timeFormatProvider.notifier).setFormat('12h');
                                  },
                                ),
                                _buildTimeFormatOption(
                                  label: '24-hour',
                                  isSelected: timeFormat == '24h',
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    ref.read(timeFormatProvider.notifier).setFormat('24h');
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // 5. App & Support Section
              _buildSectionHeader(Icons.help_outline_rounded, 'Support & About'),
              const SizedBox(height: 10),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
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
                  children: [
                    _buildRowItem(
                      icon: Icons.support_agent_rounded,
                      label: 'Help & Support',
                      value: 'FAQ & Contact',
                      fieldKey: 'help_support',
                      isEditable: false,
                      showChevron: true,
                      onTap: () => _showHelpSupport(context),
                    ),
                    const Divider(color: AppColors.divider, height: 1),
                    _buildRowItem(
                      icon: Icons.info_outline_rounded,
                      label: 'About AttendiFy',
                      value: 'v1.0.1',
                      fieldKey: 'about_app',
                      isEditable: false,
                      showChevron: true,
                      onTap: () => _showAboutDialog(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // 6. Logout Button
              InkWell(
                onTap: _isLoggingOut
                    ? null
                    : () async {
                        setState(() => _isLoggingOut = true);
                        try {
                          await ref.read(authProvider.notifier).logout();
                        } finally {
                          if (mounted) {
                            setState(() => _isLoggingOut = false);
                          }
                        }
                      },
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBECE9),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                        color: AppColors.coral.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isLoggingOut) ...[
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.coral),
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Text(
                          'Logging out...',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.coral,
                          ),
                        ),
                      ] else ...[
                        const Icon(Icons.logout_rounded,
                            color: AppColors.coral, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Logout',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.coral,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title,
      {Color color = AppColors.terracotta}) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.ink),
        ),
      ],
    );
  }

  Widget _buildRowItem({
    required IconData icon,
    required String label,
    required String value,
    String? secondaryValue,
    required String fieldKey,
    bool isEditable = true,
    bool isDateRange = false,
    VoidCallback? onDateTap,
    bool showChevron = false,
    VoidCallback? onTap,
    AcademicProfileModel? profile,
    SemesterModel? activeSem,
  }) {
    final isEditingThis = _editingFieldKey == fieldKey;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: AppColors.inkMuted),
          const SizedBox(width: 12),
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: isEditingThis
                ? SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _editController,
                      focusNode: _editFocusNode,
                      autofocus: true,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.ink,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        filled: true,
                        fillColor: AppColors.surfaceAlt,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.terracotta, width: 1.2),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.terracotta, width: 1.2),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.terracotta, width: 1.6),
                        ),
                      ),
                      onTapOutside: (_) {
                        if (profile != null) {
                          _saveCurrentEdit(profile, activeSem);
                        }
                      },
                      onSubmitted: (_) {
                        if (profile != null) {
                          _saveCurrentEdit(profile, activeSem);
                        }
                      },
                    ),
                  )
                : InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: onTap ??
                        (isEditable
                            ? () {
                                if (isDateRange && onDateTap != null) {
                                  onDateTap();
                                } else {
                                  _startEditing(fieldKey, value == 'Not Set' ? '' : value);
                                }
                              }
                            : null),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(
                            child: secondaryValue != null
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        value,
                                        textAlign: TextAlign.end,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.inkSecondary,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        secondaryValue,
                                        textAlign: TextAlign.end,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.inkSecondary,
                                        ),
                                      ),
                                    ],
                                  )
                                : Text(
                                    value,
                                    textAlign: TextAlign.end,
                                    style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.inkSecondary,
                                    ),
                                  ),
                          ),
                          if (isEditable) ...[
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color: AppColors.terracotta,
                            ),
                          ],
                          if (showChevron) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 12,
                              color: AppColors.inkMuted,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeFormatOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: Color(0x14000000),
                    blurRadius: 4,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.terracotta : AppColors.inkMuted,
          ),
        ),
      ),
    );
  }
}
