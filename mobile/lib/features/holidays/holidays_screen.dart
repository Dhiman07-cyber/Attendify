import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/widgets/landscape_header.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/app_text_field.dart';
import '../../shared/models/holiday_model.dart';
import '../../shared/providers/semesters_provider.dart';
import 'providers/holidays_provider.dart';
import '../../shared/widgets/app_toast.dart';


import '../../shared/widgets/liquid_glass_card.dart';
import '../../shared/widgets/shimmer_skeleton.dart';
import '../setup/academic_setup_screen.dart';

class HolidaysScreen extends ConsumerWidget {
  final VoidCallback onOpenDrawer;
  final VoidCallback? onNavigateToCalendar;
  final VoidCallback? onNavigateToProfile;
  final VoidCallback? onOpenSetup;

  const HolidaysScreen({
    super.key,
    required this.onOpenDrawer,
    this.onNavigateToCalendar,
    this.onNavigateToProfile,
    this.onOpenSetup,
  });

  void _showAddHolidaySheet(BuildContext context, WidgetRef ref) {
    final titleCtrl = TextEditingController();
    final todayStr = DateTime.now().toIso8601String().split('T').first;
    final startCtrl = TextEditingController(text: todayStr);
    final endCtrl = TextEditingController(text: todayStr);
    String selectedCategory = 'Festival';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Container(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            top: 24,
            left: 20,
            right: 20,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
                topLeft: Radius.circular(28), topRight: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Add Holiday',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                  IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(ctx)),
                ],
              ),
              const SizedBox(height: 16),
              AppTextField(
                  label: 'Holiday Title',
                  hint: 'e.g. Diwali Vacation',
                  controller: titleCtrl),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: AppTextField(
                        label: 'Start Date',
                        hint: 'YYYY-MM-DD',
                        controller: startCtrl),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppTextField(
                        label: 'End Date',
                        hint: 'YYYY-MM-DD',
                        controller: endCtrl),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Category',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.inkSecondary)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  'University Holiday',
                  'Festival',
                  'Academic',
                  'Semester Break',
                  'Exam Break',
                  'Other'
                ].map((cat) {
                  final isSel = selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSel,
                    onSelected: (val) {
                      if (val) setSheetState(() => selectedCategory = cat);
                    },
                    selectedColor: AppColors.terracottaLight,
                    labelStyle: TextStyle(
                      color:
                          isSel ? AppColors.terracotta : AppColors.inkSecondary,
                      fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 12,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              AppButton(
                label: 'Save Holiday',
                showArrow: false,
                onPressed: () {
                  if (titleCtrl.text.trim().isNotEmpty) {
                    ref.read(holidaysProvider.notifier).addHoliday(
                          title: titleCtrl.text.trim(),
                          startDate: startCtrl.text.trim(),
                          endDate: endCtrl.text.trim(),
                          category: selectedCategory,
                        );
                  }
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(holidaysProvider);
    final semState = ref.watch(semestersProvider);

    final isInitialLoading =
        (!state.hasLoaded || state.isLoading) && state.holidays.isEmpty;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            LandscapeHeaderWidget(
              greeting: 'Holidays',
              userName: 'Holiday Calendar',
              semesterInfo:
                  '${semState.activeSemester?.label ?? 'Active Semester'} • Holidays',
              showActions: false,
              topOffset: 76,
              isLoading: isInitialLoading,
            ),

            const SizedBox(height: 6),

            if (isInitialLoading) ...[
              _buildHolidaysSkeleton(context),
            ] else if (state.holidays.isEmpty) ...[
              _buildEmptyTimetableCard(context, ref),
            ] else ...[
              // Action Cards: Add Holidays & Upload Holidays (EQUAL HEIGHT VIA IntrinsicHeight)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: InkWell(
                          onTap: () => _showAddHolidaySheet(context, ref),
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.terracottaLight,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color:
                                      AppColors.terracotta.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    color: AppColors.terracotta,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.add,
                                      color: Colors.white, size: 18),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Add Holidays',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: AppColors.terracotta),
                                      ),
                                      Text(
                                        'Manual Entry',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.inkMuted),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            AppToast.showComingSoon(context, feature: 'Upload Holidays');
                          },
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEFF5FA),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: const Color(0xFFD4E3EF)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: const BoxDecoration(
                                    color: AppColors.ocean,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.file_upload_outlined,
                                      color: Colors.white, size: 18),
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Upload Holidays',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: AppColors.ocean),
                                      ),
                                      Text(
                                        'Image / PDF (OCR)',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.inkMuted),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 14),

            // Filter Pills: All | Upcoming | Past & Date sort
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Row(
                        children: [
                          _buildFilterPill(
                              'All',
                              state.filterType == 'all',
                              () => ref
                                  .read(holidaysProvider.notifier)
                                  .setFilter('all')),
                          const SizedBox(width: 8),
                          _buildFilterPill(
                              'Upcoming',
                              state.filterType == 'upcoming',
                              () => ref
                                  .read(holidaysProvider.notifier)
                                  .setFilter('upcoming')),
                          const SizedBox(width: 8),
                          _buildFilterPill(
                              'Past',
                              state.filterType == 'past',
                              () => ref
                                  .read(holidaysProvider.notifier)
                                  .setFilter('past')),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Row(
                    children: [
                      Icon(Icons.swap_vert_rounded,
                          size: 16, color: AppColors.inkMuted),
                      SizedBox(width: 4),
                      Text('Date',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.inkMuted)),
                      Icon(Icons.keyboard_arrow_down_rounded,
                          size: 16, color: AppColors.inkMuted),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Upcoming Holidays Section
            if (state.filterType != 'past') ...[
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.event_available_outlined,
                              size: 18, color: AppColors.terracotta),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Upcoming Holidays',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: state.upcomingHolidays.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final h = state.upcomingHolidays[index];
                    return _buildHolidayTile(h);
                  },
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Past Holidays Section
            if (state.filterType != 'upcoming') ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.history_rounded,
                              size: 18, color: AppColors.inkMuted),
                          SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              'Past Holidays',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 15),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'View All',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.terracotta,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: state.pastHolidays.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final h = state.pastHolidays[index];
                    return _buildHolidayTile(h);
                  },
                ),
              ),
            ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHolidaysSkeleton(BuildContext context) {
    return ShimmerLoading(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 2 Action Cards Skeleton
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.divider),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      height: 58,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.divider),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Filter Tabs Skeleton
            Container(
              height: 36,
              width: 220,
              decoration: BoxDecoration(
                color: const Color(0xFFF1EBE6),
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            const SizedBox(height: 16),

            // Section Header Skeleton
            const SkeletonBox.text(width: 140, height: 16),
            const SizedBox(height: 12),

            // Holiday List Skeletons
            ...List.generate(
              4,
              (i) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Row(
                    children: [
                      SkeletonBox(
                        width: 44,
                        height: 44,
                        borderRadius: BorderRadius.all(Radius.circular(12)),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonBox.text(width: 140, height: 14),
                            SizedBox(height: 6),
                            SkeletonBox(
                              width: 60,
                              height: 18,
                              borderRadius: BorderRadius.all(Radius.circular(6)),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 8),
                      SkeletonBox.text(width: 40, height: 12),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyTimetableCard(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
              child: const Icon(
                Icons.calendar_view_week_rounded,
                color: AppColors.terracotta,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Your timetable isn't set up yet.",
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: AppColors.ink,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Add your holidays and term schedule in Academic Setup to begin tracking off-days.',
              style: TextStyle(fontSize: 12, color: AppColors.inkMuted),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.terracotta,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text(
                'Set Up Timetable',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: () {
                if (onOpenSetup != null) {
                  onOpenSetup!();
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AcademicSetupScreen(
                        onComplete: () => ref.read(holidaysProvider.notifier).loadHolidays(),
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

  Widget _buildFilterPill(String label, bool isActive, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isActive ? AppColors.terracottaLight : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive
                ? AppColors.terracotta.withValues(alpha: 0.5)
                : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? AppColors.terracotta : AppColors.inkMuted,
          ),
        ),
      ),
    );
  }

  Widget _buildHolidayTile(HolidayModel h) {
    // Parse month and day e.g. "2026-10-17" => "OCT", "17"
    String monthStr = 'OCT';
    String dayStr = '17';
    String weekdayStr = 'Fri';
    try {
      final parts = h.startDate.split('-');
      if (parts.length == 3) {
        dayStr = parts[2];
        final m = int.parse(parts[1]);
        const months = [
          '',
          'JAN',
          'FEB',
          'MAR',
          'APR',
          'MAY',
          'JUN',
          'JUL',
          'AUG',
          'SEP',
          'OCT',
          'NOV',
          'DEC'
        ];
        monthStr = months[m];
      }
    } catch (_) {}

    Color tagColor = AppColors.lavender;
    Color tagBg = AppColors.lavenderLight;
    if (h.category == 'Festival') {
      tagColor = AppColors.coral;
      tagBg = AppColors.coralLight;
    } else if (h.category == 'National') {
      tagColor = AppColors.sage;
      tagBg = AppColors.sageLight;
    } else if (h.category == 'Other') {
      tagColor = AppColors.amber;
      tagBg = AppColors.amberLight;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          // Date box
          Container(
            width: 48,
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: h.isUpcoming
                  ? const Color(0xFFFDEAE8)
                  : const Color(0xFFF2F4F2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  monthStr,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: h.isUpcoming
                        ? AppColors.terracotta
                        : AppColors.sageDark,
                  ),
                ),
                Text(
                  dayStr,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: h.isUpcoming ? AppColors.terracotta : AppColors.ink,
                  ),
                ),
                Text(
                  weekdayStr,
                  style:
                      const TextStyle(fontSize: 9, color: AppColors.inkMuted),
                ),
              ],
            ),
          ),

          const SizedBox(width: 14),

          // Title & Category tag
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  h.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.ink),
                ),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: tagBg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    h.category,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: tagColor),
                  ),
                ),
              ],
            ),
          ),

          // Duration badge & chevron
          Text(
            '${h.durationDays} ${h.durationDays > 1 ? 'days' : 'day'}',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppColors.inkMuted),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded,
              size: 18, color: AppColors.inkMuted),
        ],
      ),
    );
  }
}
