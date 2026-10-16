import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/local_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/time_format_provider.dart';
import '../../shared/widgets/landscape_header.dart';
import '../../shared/widgets/liquid_glass_card.dart';
import '../../shared/widgets/attendance_progress_ring.dart';
import '../../shared/widgets/semester_progress_dial.dart';
import '../../shared/widgets/status_badge.dart';
import '../../shared/widgets/app_button.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/shimmer_skeleton.dart';
import '../../shared/models/dashboard_model.dart';
import '../../shared/models/session_model.dart';
import 'providers/dashboard_provider.dart';

class DashboardScreen extends ConsumerWidget {
  final VoidCallback onOpenDrawer;
  final VoidCallback onNavigateToToday;
  final VoidCallback onNavigateToAnalytics;
  final VoidCallback onNavigateToCalendar;
  final VoidCallback? onNavigateToProfile;
  final VoidCallback? onOpenSetup;

  const DashboardScreen({
    super.key,
    required this.onOpenDrawer,
    required this.onNavigateToToday,
    required this.onNavigateToAnalytics,
    required this.onNavigateToCalendar,
    this.onNavigateToProfile,
    this.onOpenSetup,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboardAsync = ref.watch(dashboardProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: dashboardAsync.when(
        loading: () {
          final cached = LocalStorage().getCachedDashboardSync();
          if (cached != null) {
            try {
              final model = DashboardOverviewModel.fromJson(cached);
              return _buildDashboardContent(context, ref, model);
            } catch (_) {}
          }
          return _buildDashboardSkeleton(context);
        },
        error: (err, stack) {
          final errStr = err.toString();
          if (errStr.contains('not authenticated') || errStr.contains('User is not authenticated')) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              ref.invalidate(dashboardProvider);
            });
            return _buildDashboardSkeleton(context);
          }
          return ErrorRetryView(
            message: err.toString(),
            onRetry: () => ref.refresh(dashboardProvider),
          );
        },
        data: (data) => _buildDashboardContent(context, ref, data),
      ),
    );
  }

  Widget _buildDashboardSkeleton(BuildContext context) {
    return ShimmerLoading(
      child: SingleChildScrollView(
        clipBehavior: Clip.hardEdge,
        padding: const EdgeInsets.only(bottom: 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const LandscapeHeaderWidget(
              greeting: 'Good morning,',
              userName: '',
              semesterInfo: '',
              isLoading: true,
              showActions: false,
              topOffset: 76,
            ),
            const SizedBox(height: 20),

            // Top Metric Cards skeleton (Matches IntrinsicHeight layout)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 6,
                      child: LiquidGlassCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFFEFE9E4),
                                          shape: BoxShape.circle,
                                        ),
                                        child: const Icon(
                                          Icons.pie_chart_outline_rounded,
                                          size: 14,
                                          color: AppColors.inkSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      const Flexible(
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'Overall Attendance',
                                            maxLines: 1,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13,
                                              color: AppColors.ink,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.chevron_right_rounded,
                                    size: 18, color: AppColors.inkMuted),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const Row(
                              children: [
                                SkeletonBox.circle(size: 76),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SkeletonBox.text(width: 60, height: 12),
                                      SizedBox(height: 8),
                                      SkeletonBox.text(width: 50, height: 12),
                                      SizedBox(height: 8),
                                      SkeletonBox.text(width: 40, height: 10),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      flex: 5,
                      child: LiquidGlassCard(
                        padding: EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      'Semester Progress',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                  ),
                                ),
                                SizedBox(width: 4),
                                Icon(Icons.chevron_right_rounded,
                                    size: 16, color: AppColors.inkMuted),
                              ],
                            ),
                            SizedBox(height: 14),
                            Center(
                              child: SkeletonBox.circle(size: 76),
                            ),
                            SizedBox(height: 10),
                            Center(
                              child: SkeletonBox.text(width: 80, height: 10),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Today's classes skeleton
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: LiquidGlassCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.calendar_today_rounded,
                                size: 18, color: AppColors.terracotta),
                            SizedBox(width: 8),
                            Text(
                              "Today's Classes",
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: AppColors.ink,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const SkeletonBox.text(width: 90, height: 11),
                    const SizedBox(height: 16),
                    _buildSkeletonSessionRow(),
                    const SizedBox(height: 12),
                    _buildSkeletonSessionRow(),
                    const SizedBox(height: 16),
                    AppButton(
                      label: "Mark Today's Attendance",
                      icon: Icons.calendar_month_rounded,
                      onPressed: onNavigateToToday,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Upcoming events & Quick insight skeleton
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: LiquidGlassCard(
                        padding: EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Icon(Icons.campaign_outlined,
                                    size: 18, color: AppColors.terracotta),
                                Icon(Icons.chevron_right_rounded,
                                    size: 16, color: AppColors.inkMuted),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Upcoming Events',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            SizedBox(height: 8),
                            SkeletonBox(
                              height: 44,
                              borderRadius:
                                  BorderRadius.all(Radius.circular(10)),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: LiquidGlassCard(
                        padding: EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Icon(Icons.lightbulb_outline_rounded,
                                    size: 18, color: AppColors.amber),
                                Icon(Icons.chevron_right_rounded,
                                    size: 16, color: AppColors.inkMuted),
                              ],
                            ),
                            SizedBox(height: 8),
                            Text(
                              'Quick Insight',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                            SizedBox(height: 8),
                            SkeletonBox(
                              height: 44,
                              borderRadius:
                                  BorderRadius.all(Radius.circular(10)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Attendance Trend Skeleton
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: LiquidGlassCard(
                padding: EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_graph_rounded,
                                size: 18, color: AppColors.terracotta),
                            SizedBox(width: 6),
                            Text(
                              'Attendance Trend (This Month)',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 13),
                            ),
                          ],
                        ),
                        SkeletonBox.text(width: 48, height: 16),
                      ],
                    ),
                    SizedBox(height: 20),
                    SkeletonBox(
                      height: 80,
                      borderRadius: BorderRadius.all(Radius.circular(8)),
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

  Widget _buildSkeletonSessionRow() {
    return const Row(
      children: [
        SkeletonBox.circle(size: 16),
        SizedBox(width: 12),
        SkeletonBox(
            width: 36,
            height: 36,
            borderRadius: BorderRadius.all(Radius.circular(10))),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox.text(width: 120, height: 12),
              SizedBox(height: 4),
              SkeletonBox.text(width: 80, height: 10),
            ],
          ),
        ),
        SkeletonBox(
            width: 54,
            height: 20,
            borderRadius: BorderRadius.all(Radius.circular(12))),
      ],
    );
  }

  Widget _buildDashboardContent(
    BuildContext context,
    WidgetRef ref,
    DashboardOverviewModel data,
  ) {
    try {
      final enrollmentId = (data.enrollmentId != null && data.enrollmentId.toString().trim().isNotEmpty)
          ? data.enrollmentId.toString().trim()
          : null;

      return SingleChildScrollView(
        clipBehavior: Clip.hardEdge,
        padding: const EdgeInsets.only(bottom: 96),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Landscape Header with Sunrise Artwork
            LandscapeHeaderWidget(
              greeting: 'Good morning,',
              userName: data.userName,
            semesterInfo: enrollmentId != null ? 'Enrollment ID · $enrollmentId' : '',
            showActions: false,
            topOffset: 76,
          ),

          const SizedBox(height: 20),

          // 2. Top Metric Cards (Overall Attendance & Semester Progress)
          Builder(
            builder: (context) {
              final screenWidth = MediaQuery.sizeOf(context).width;
              final isVeryCompact = screenWidth < 380;
              return Padding(
                padding: EdgeInsets.symmetric(horizontal: isVeryCompact ? 12 : 16),
                child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Overall Attendance Card
                        Expanded(
                          flex: 6,
                          child: LiquidGlassCard(
                            padding: EdgeInsets.all(isVeryCompact ? 12 : 16),
                            onTap: onNavigateToAnalytics,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFFEFE9E4),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                          Icons.pie_chart_outline_rounded,
                                          size: 14,
                                          color: AppColors.inkSecondary),
                                    ),
                                    const SizedBox(width: 6),
                                    const Flexible(
                                      child: Text(
                                        'Overall Attendance',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 13,
                                            color: AppColors.ink),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  size: 18, color: AppColors.inkMuted),
                            ],
                          ),
                          const SizedBox(height: 14),
                          AttendanceProgressRing(
                            percentage: data.overallPercentage,
                            attended: data.totalAttended,
                            conducted: data.totalConducted,
                            targetPercentage: data.targetPercentage,
                            minimumPercentage: data.minimumPercentage,
                            trendChange: data.trendFromLastMonth,
                            size: 105,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Semester Progress Card
                  Expanded(
                    flex: 5,
                    child: LiquidGlassCard(
                      padding: const EdgeInsets.all(12),
                      onTap: onNavigateToCalendar,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Semester Progress',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12,
                                        color: AppColors.ink),
                                  ),
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.chevron_right_rounded,
                                  size: 16, color: AppColors.inkMuted),
                            ],
                          ),
                          const SizedBox(height: 14),
                          SemesterProgressDial(
                            currentWeek: data.currentWeek,
                            totalWeeks: data.totalWeeks,
                            weeksRemaining: data.weeksRemaining,
                            progressPercentage: data.semesterProgressPct,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),

          const SizedBox(height: 16),

          // 3. Authoritative Daily Attendance Marking Card (Isolated Consumer to prevent full-screen rebuilds)
          Consumer(
            builder: (context, ref, _) {
              final dayState = ref.watch(selectedDateAttendanceProvider);
              return _buildDayAttendanceCard(context, ref, data, dayState);
            },
          ),

          const SizedBox(height: 16),

          // 4. Subjects Needing Attention
          if (data.subjectsNeedingAttention.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFFBECE9),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.track_changes_rounded,
                            size: 16, color: AppColors.terracotta),
                      ),
                      const SizedBox(width: 8),
                      const Text(
                        'Subjects Needing Attention',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppColors.ink),
                      ),
                    ],
                  ),
                  GestureDetector(
                    onTap: onNavigateToAnalytics,
                    child: Text(
                      'View All',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.terracotta,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: data.subjectsNeedingAttention.map<Widget>((item) {
                  return Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _buildAttentionCard(item),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],          // 5. Grid Row: Upcoming Events & Quick Insight
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Upcoming Events
                  Expanded(
                    child: LiquidGlassCard(
                      padding: const EdgeInsets.all(14),
                      onTap: onNavigateToCalendar,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(Icons.campaign_outlined,
                                  size: 18, color: AppColors.terracotta),
                              Icon(Icons.chevron_right_rounded,
                                  size: 16, color: AppColors.inkMuted),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Upcoming Events',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          if (data.upcomingHoliday != null)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFDF5EF),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.event_outlined,
                                      color: AppColors.coral, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          data.upcomingHoliday!.relativeTimeLabel,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 11),
                                        ),
                                        Text(
                                          data.upcomingHoliday!.title,
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: AppColors.inkMuted),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFBF8F5),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                    color: AppColors.divider
                                        .withValues(alpha: 0.5)),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.event_available_outlined,
                                      color: AppColors.inkLight, size: 18),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'No upcoming events',
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.inkMuted),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 12),

                  // Quick Insight
                  Expanded(
                    child: LiquidGlassCard(
                      padding: const EdgeInsets.all(14),
                      onTap: onNavigateToAnalytics,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Icon(Icons.lightbulb_outline_rounded,
                                  size: 18, color: AppColors.amber),
                              Icon(Icons.chevron_right_rounded,
                                  size: 16, color: AppColors.inkMuted),
                            ],
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Quick Insight',
                            style: TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          if (data.quickInsight != null)
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.sageLight,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.bar_chart_rounded,
                                      color: AppColors.sage, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      data.quickInsight!.message,
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.inkSecondary,
                                          height: 1.3),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 12),
                              decoration: BoxDecoration(
                                color:
                                    AppColors.sageLight.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(Icons.lightbulb_outline_rounded,
                                      color: AppColors.amber, size: 18),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Insights will appear as classes are recorded.',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.inkMuted,
                                          height: 1.3),
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // 6. Attendance Trend (This Month)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LiquidGlassCard(
              padding: const EdgeInsets.all(18),
              onTap: onNavigateToAnalytics,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_graph_rounded,
                                size: 18, color: AppColors.terracotta),
                            SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Attendance Trend (This Month)',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(Icons.chevron_right_rounded,
                                size: 16, color: AppColors.inkMuted),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            data.overallPercentage != null
                                ? '${data.overallPercentage!.toStringAsFixed(1)}%'
                                : '0.0%',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          if (data.totalConducted > 0 &&
                              data.trendFromLastMonth != 0.0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: data.trendFromLastMonth >= 0
                                    ? AppColors.sageLight
                                    : AppColors.coralLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    data.trendFromLastMonth >= 0
                                        ? Icons.arrow_upward_rounded
                                        : Icons.arrow_downward_rounded,
                                    size: 11,
                                    color: data.trendFromLastMonth >= 0
                                        ? AppColors.sageDark
                                        : AppColors.coral,
                                  ),
                                  Text(
                                    '${data.trendFromLastMonth >= 0 ? '+' : ''}${data.trendFromLastMonth.toStringAsFixed(1)}%',
                                    style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w700,
                                        color: data.trendFromLastMonth >= 0
                                            ? AppColors.sageDark
                                            : AppColors.coral),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Trend Graph Visual
                  SizedBox(
                    height: 100,
                    width: double.infinity,
                    child: data.trendPoints.isNotEmpty
                        ? CustomPaint(
                            painter: _TrendChartPainter(
                              points: data.trendPoints
                                  .map<double>((tp) {
                                    final p = tp.percentage;
                                    if (p == null || p.isNaN) return 0.0;
                                    return (p / 100.0).clamp(0.0, 1.0);
                                  })
                                  .toList(),
                              targetThreshold: (data.targetPercentage.isNaN
                                      ? 75.0
                                      : data.targetPercentage / 100.0)
                                  .clamp(0.0, 1.0),
                            ),
                          )
                        : const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.show_chart_rounded,
                                    color: AppColors.inkLight, size: 26),
                                SizedBox(height: 6),
                                Text(
                                  'No attendance trend recorded for this month yet',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.inkMuted,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          ],
        ),
      );
    } catch (e, st) {
      debugPrint('[Dashboard Content Crash] $e\n$st');
      return ErrorRetryView(
        message: 'Dashboard layout error: $e',
        onRetry: () => ref.refresh(dashboardProvider),
      );
    }
  }

  String _formatDateHeader(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;

    const shortWeekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    final weekday = shortWeekdays[date.weekday - 1];
    final month = months[date.month - 1];
    final dayStr = date.day.toString().padLeft(2, '0');
    final formattedDate = '$weekday, $dayStr $month ${date.year}';

    if (diff == 0) {
      return 'Today · $formattedDate';
    } else if (diff == -1) {
      return 'Yesterday · $formattedDate';
    } else if (diff == -2) {
      return '2 days ago · $formattedDate';
    } else if (diff < -2) {
      return '${diff.abs()} days ago · $formattedDate';
    } else if (diff == 1) {
      return 'Tomorrow · $formattedDate';
    } else {
      return 'In $diff days · $formattedDate';
    }
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _getDayName(DateTime d) {
    const weekdays = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return weekdays[d.weekday - 1];
  }

  Widget _buildWindowBadge(String label, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildDayAttendanceCard(
    BuildContext context,
    WidgetRef ref,
    dynamic data,
    SelectedDateAttendanceState dayState,
  ) {
    final dateLabel = _formatDateHeader(dayState.selectedDate);
    final isToday = _isSameDay(dayState.selectedDate, DateTime.now());

    // Resolve sessions: prioritize dayState.sessions; fallback to data.todaySessions if today and dayState has no sessions yet
    final List<dynamic> displayedSessions = dayState.sessions.isNotEmpty
        ? dayState.sessions
        : (isToday && data.todaySessions.isNotEmpty ? data.todaySessions : []);

    int attendedCount = 0;
    int absentCount = 0;
    int notHeldCount = 0;
    int unrecordedCount = 0;

    for (final s in displayedSessions) {
      final slotKey = (s.timetableEntryId != null &&
              s.timetableEntryId.toString().isNotEmpty)
          ? s.timetableEntryId.toString()
          : s.id.toString();
      final mark = dayState.draftMarks[slotKey] ?? s.attendanceStatus;
      if (mark == 'ATTENDED') {
        attendedCount++;
      } else if (mark == 'NOT_HELD') {
        notHeldCount++;
      } else if (mark == 'ABSENT') {
        absentCount++;
      } else {
        unrecordedCount++;
      }
    }

    final hasUnsavedDraft = dayState.draftMarks.isNotEmpty;
    final allAlreadySaved = displayedSessions.isNotEmpty &&
        displayedSessions.every((s) => s.attendanceStatus != null && s.attendanceStatus.toString().isNotEmpty);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: LiquidGlassCard(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header Row with All Attended Button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 18, color: AppColors.terracotta),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Today's Classes",
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              color: AppColors.ink),
                        ),
                      ),
                    ],
                  ),
                ),
                // "All Attended" Button (Checks all sessions in draft without auto-saving)
                if (dayState.isEditable && displayedSessions.isNotEmpty)
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      ref.read(selectedDateAttendanceProvider.notifier).markAllAttended(displayedSessions);
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.sage.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.sage.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.done_all_rounded,
                            size: 15,
                            color: AppColors.sageDark,
                          ),
                          SizedBox(width: 5),
                          Text(
                            'All Attended',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: AppColors.sageDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      dateLabel,
                      style: AppTypography.bodySmall.copyWith(
                        fontSize: 11,
                        color: AppColors.inkMuted,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: dayState.isFuture
                          ? _buildWindowBadge('Upcoming • View Only',
                              AppColors.inkMuted, const Color(0xFFF0ECE9))
                          : dayState.isExpired
                              ? _buildWindowBadge('Marking Closed',
                                  AppColors.amberDark, AppColors.amberLight)
                              : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Card Content View
              if ((dayState.isLoading || !dayState.hasLoaded) && displayedSessions.isEmpty && !dayState.isHoliday) ...[
                _buildSkeletonSessionRow(),
                const SizedBox(height: 12),
                _buildSkeletonSessionRow(),
              ] else if (dayState.isHoliday) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7F5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.coral.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.event_available_rounded,
                          color: AppColors.coral, size: 28),
                      const SizedBox(height: 8),
                      Text(
                        dayState.holidayName ?? 'Academic Holiday',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: AppColors.ink),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Registered holiday. No classes scheduled.',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.inkMuted),
                      ),
                    ],
                  ),
                ),
              ] else if (displayedSessions.isEmpty) ...[
                if (dayState.selectedDate.weekday == 7) ...[
                  // Sunday empty state
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF7F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.event_available_outlined,
                            color: AppColors.amberDark, size: 28),
                        const SizedBox(height: 8),
                        const Text(
                          'No classes scheduled for Sunday.',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.ink),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Enjoy your weekend.',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.inkMuted),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_view_week_rounded, size: 16),
                          label: const Text('View Weekly Routine'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.terracotta,
                            side: const BorderSide(
                                color: AppColors.terracotta),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: onNavigateToToday,
                        ),
                      ],
                    ),
                  ),
                ] else if (!dayState.hasTimetableSetup) ...[
                  // Timetable not set up
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF7F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.calendar_month_outlined,
                            color: AppColors.terracotta, size: 28),
                        const SizedBox(height: 8),
                        const Text(
                          "Your timetable isn't set up yet.",
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.ink),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Configure your weekly routine in Academic Setup to track classes.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11, color: AppColors.inkMuted),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.tune_rounded, size: 16),
                          label: const Text('Set Up Timetable'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.terracotta,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: onOpenSetup ?? onNavigateToToday,
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  // General weekday without classes
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF7F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.event_busy_outlined,
                            color: AppColors.inkMuted, size: 28),
                        const SizedBox(height: 8),
                        Text(
                          'No classes scheduled for ${_getDayName(dayState.selectedDate)}.',
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: AppColors.ink),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'No routine entries configured for this day.',
                          style: TextStyle(
                              fontSize: 11, color: AppColors.inkMuted),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.calendar_view_week_rounded, size: 16),
                          label: const Text('View Weekly Routine'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.terracotta,
                            side: const BorderSide(
                                color: AppColors.terracotta),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                          onPressed: onNavigateToToday,
                        ),
                      ],
                    ),
                  ),
                ],
              ] else ...[
                if (dayState.isEditable && displayedSessions.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Icon(Icons.check_box_outlined,
                              size: 13, color: AppColors.sageDark),
                          SizedBox(width: 3),
                          Text('Attended',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.sageDark)),
                          SizedBox(width: 8),
                          Icon(Icons.check_box_outline_blank_rounded,
                              size: 13, color: AppColors.coral),
                          SizedBox(width: 3),
                          Text('Absent (Unchecked)',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.coral)),
                          SizedBox(width: 8),
                          Icon(Icons.event_busy_outlined,
                              size: 13, color: AppColors.inkSecondary),
                          SizedBox(width: 3),
                          Text('Not Held / Cancelled',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.inkSecondary)),
                        ],
                      ),
                    ),
                  ),
                ],

                // Sessions list
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: displayedSessions.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final s = displayedSessions[index];
                    return _buildInteractiveSessionRow(
                        context, ref, s, dayState);
                  },
                ),

                const SizedBox(height: 14),

                // Count summary
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9F7F5),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded,
                          size: 14, color: AppColors.inkMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          dayState.isFuture
                              ? '${displayedSessions.length} upcoming scheduled ${displayedSessions.length == 1 ? 'class' : 'classes'} • Marking opens on class day'
                              : (attendedCount == 0 && absentCount == 0 && notHeldCount == 0)
                                  ? '${displayedSessions.length} scheduled ${displayedSessions.length == 1 ? 'class' : 'classes'} • Attendance not yet recorded'
                                  : '$attendedCount attended · $absentCount absent · $notHeldCount not held${unrecordedCount > 0 ? ' · $unrecordedCount unrecorded' : ''}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.inkSecondary),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Action Button or Status Info
                if (dayState.isEditable)
                  (allAlreadySaved && !hasUnsavedDraft)
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.sageLight,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                                color: AppColors.sage.withValues(alpha: 0.3)),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  size: 16, color: AppColors.sageDark),
                              SizedBox(width: 8),
                              Text(
                                'Attendance recorded for this day',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.sageDark),
                              ),
                            ],
                          ),
                        )
                      : AppButton(
                          label:
                              "Save Attendance ($attendedCount/${displayedSessions.length})",
                          icon: Icons.check_circle_outline,
                          isLoading: dayState.isSaving,
                          onPressed: () => _showAttendanceConfirmationDialog(
                            context,
                            ref,
                            dayState,
                            displayedSessions,
                            attendedCount,
                            absentCount,
                            notHeldCount,
                          ),
                        )
                else if (dayState.isFuture)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F2EF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Upcoming Date • Marking opens on class day',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkMuted),
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F2EF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Marking Closed • Attendance is read-only after rolling 3-day window',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkMuted),
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
  }

  Widget _buildInteractiveSessionRow(
    BuildContext context,
    WidgetRef ref,
    dynamic session,
    SelectedDateAttendanceState dayState,
  ) {
    final dayNotifier = ref.read(selectedDateAttendanceProvider.notifier);
    final slotKey = (session.timetableEntryId != null &&
            session.timetableEntryId.toString().isNotEmpty)
        ? session.timetableEntryId.toString()
        : session.id.toString();

    final currentMark =
        dayState.draftMarks[slotKey] ?? session.attendanceStatus;
    final isAttended = currentMark == 'ATTENDED';
    final isNotHeld = currentMark == 'NOT_HELD';
    final isAbsent = currentMark == 'ABSENT';

    IconData icon = Icons.book_rounded;
    if (session.subjectIcon == 'code') icon = Icons.code_rounded;
    if (session.subjectIcon == 'settings') icon = Icons.settings_rounded;
    if (session.subjectIcon == 'functions') icon = Icons.functions_rounded;
    if (session.subjectIcon == 'database') icon = Icons.storage_rounded;

    return Row(
      children: [
        // Interactive timeline dot: tap cycles Attended -> Absent -> Not Held
        InkWell(
          onTap: () {
            if (dayState.isEditable && session is ClassSessionModel) {
              if (isAttended) {
                dayNotifier.toggleAttended(session);
              } else if (isAbsent) {
                dayNotifier.markNotHeld(session);
              } else {
                dayNotifier.toggleAttended(session);
              }
            }
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isAttended
                  ? AppColors.sage
                  : (isAbsent
                      ? AppColors.coral
                      : (isNotHeld
                          ? const Color(0xFFC5BCB5)
                          : (session.timeStatus == 'Now' && !dayState.isFuture
                              ? AppColors.terracotta
                              : Colors.white))),
              border: Border.all(
                color: isAttended || isAbsent || isNotHeld
                    ? Colors.transparent
                    : (session.timeStatus == 'Now' && !dayState.isFuture
                        ? AppColors.terracotta
                        : AppColors.divider),
                width: 2,
              ),
            ),
            child: isAttended
                ? const Icon(Icons.check, size: 11, color: Colors.white)
                : (isAbsent
                    ? const Icon(Icons.close, size: 10, color: Colors.white)
                    : (isNotHeld
                        ? const Icon(Icons.remove, size: 10, color: Colors.white)
                        : null)),
          ),
        ),
        const SizedBox(width: 12),

        // Subject icon box
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.getSubjectColor(session.subjectColor)
                .withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon,
              size: 18, color: AppColors.getSubjectColor(session.subjectColor)),
        ),
        const SizedBox(width: 12),

        // Subject Info
        Expanded(
          child: Builder(
            builder: (context) {
              final timeFormat = ref.watch(timeFormatProvider);
              final is24h = timeFormat == '24h';
              final formattedTiming = formatSlotRange(
                session.startTime?.toString(),
                session.endTime?.toString(),
                is24h: is24h,
              );
              final displayType = session is ClassSessionModel
                  ? session.displayClassType
                  : ((session.classType?.toString().toUpperCase() == 'LAB')
                      ? 'Lab'
                      : (session.classType?.toString().toUpperCase() == 'THEORY'
                          ? 'Theory'
                          : 'Others'));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          session.subjectName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: AppColors.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: displayType.toLowerCase() == 'lab'
                              ? AppColors.ocean.withValues(alpha: 0.12)
                              : (displayType.toLowerCase() == 'theory'
                                  ? AppColors.terracotta.withValues(alpha: 0.12)
                                  : const Color(0xFFF0ECE8)),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          displayType,
                          style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: displayType.toLowerCase() == 'lab'
                                ? AppColors.ocean
                                : (displayType.toLowerCase() == 'theory'
                                    ? AppColors.terracotta
                                    : AppColors.inkSecondary),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        formattedTiming,
                        style: AppTypography.bodySmall.copyWith(fontSize: 11),
                      ),
                      if (session.facultyName != null && session.facultyName.toString().isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '• ${session.facultyName}',
                            style: AppTypography.bodySmall.copyWith(fontSize: 11),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              );
            },
          ),
        ),

        const SizedBox(width: 6),

        // Marking Controls / Status Badges
        if (dayState.isEditable) ...[
          if (isNotHeld)
            InkWell(
              onTap: () {
                if (session is ClassSessionModel) {
                  dayNotifier.markNotHeld(session);
                }
              },
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF6EFEB),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.divider),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_busy_rounded,
                        size: 13, color: AppColors.coral),
                    SizedBox(width: 4),
                    Text(
                      'Not Held',
                      style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.coral),
                    ),
                    SizedBox(width: 3),
                    Icon(Icons.close_rounded,
                        size: 11, color: AppColors.coral),
                  ],
                ),
              ),
            )
          else ...[
            Transform.scale(
              scale: 1.15,
              child: Checkbox(
                value: isAttended,
                activeColor: AppColors.sageDark,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4)),
                onChanged: (val) {
                  if (session is ClassSessionModel) {
                    dayNotifier.toggleAttended(session);
                  }
                },
              ),
            ),
            const SizedBox(width: 2),
            Tooltip(
              message: 'Mark Not Held / Cancelled',
              child: InkWell(
                onTap: () {
                  if (session is ClassSessionModel) {
                    dayNotifier.markNotHeld(session);
                  }
                },
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3EFEA),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: const Icon(
                    Icons.event_busy_outlined,
                    size: 15,
                    color: AppColors.inkSecondary,
                  ),
                ),
              ),
            ),
          ],
        ] else ...[
          // Read-only status badge
          StatusBadge(
            label: isAttended
                ? 'Attended'
                : (isAbsent
                    ? 'Absent'
                    : (isNotHeld
                        ? 'Not Held'
                        : (dayState.isFuture ? 'Upcoming' : (session.timeStatus ?? 'Scheduled')))),
          ),
        ],
      ],
    );
  }

  void _showAttendanceConfirmationDialog(
    BuildContext context,
    WidgetRef ref,
    SelectedDateAttendanceState dayState,
    List<dynamic> displayedSessions,
    int attendedCount,
    int absentCount,
    int notHeldCount,
  ) {
    final formattedDate = _formatDateHeader(dayState.selectedDate);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline_rounded,
                color: AppColors.terracotta, size: 22),
            SizedBox(width: 8),
            Text(
              'Confirm Attendance',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              formattedDate,
              style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: AppColors.ink),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9F7F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.divider),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.check_circle_rounded,
                          size: 16, color: AppColors.sageDark),
                      const SizedBox(width: 8),
                      Text('$attendedCount attended',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: AppColors.sageDark)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.cancel_outlined,
                          size: 16, color: AppColors.coral),
                      const SizedBox(width: 8),
                      Text('$absentCount will be recorded absent',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.coral)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.remove_circle_outline,
                          size: 16, color: AppColors.inkMuted),
                      const SizedBox(width: 8),
                      Text('$notHeldCount not held',
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.inkMuted)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Unchecked eligible sessions are recorded as absent upon confirmation. You can correct attendance within the rolling 3-day window.',
              style: TextStyle(
                  fontSize: 11, color: AppColors.inkMuted, height: 1.3),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text('Review',
                style: TextStyle(color: AppColors.inkMuted)),
            onPressed: () => Navigator.pop(ctx),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.terracotta,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Confirm & Save'),
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await ref
                  .read(selectedDateAttendanceProvider.notifier)
                  .confirmAndSaveAttendance();
              if (context.mounted) {
                if (ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Attendance recorded successfully!'),
                      backgroundColor: AppColors.sageDark,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                } else {
                  final err = ref.read(selectedDateAttendanceProvider).errorMessage;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        err != null && err.isNotEmpty
                            ? err
                            : 'Failed to save attendance. Selections kept for retry.',
                      ),
                      backgroundColor: AppColors.coral,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAttentionCard(dynamic item) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  item.name,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${item.percentage?.toStringAsFixed(1) ?? '0.0'}%',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: item.status == 'CRITICAL'
                      ? AppColors.coral
                      : AppColors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (item.percentage == null || item.percentage!.isNaN
                  ? 0.0
                  : (item.percentage! / 100.0).clamp(0.0, 1.0)),
              backgroundColor: const Color(0xFFFBECE9),
              valueColor: AlwaysStoppedAnimation<Color>(
                item.status == 'CRITICAL' ? AppColors.coral : AppColors.amber,
              ),
              minHeight: 4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            item.neededClassesMessage,
            style: const TextStyle(fontSize: 10, color: AppColors.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _TrendChartPainter extends CustomPainter {
  final List<double> points;
  final double targetThreshold;

  _TrendChartPainter({required this.points, required this.targetThreshold});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty || size.width <= 0 || size.height <= 0) return;

    final safeTargetThreshold = targetThreshold.isNaN
        ? 0.75
        : targetThreshold.clamp(0.0, 1.0);

    final paintLine = Paint()
      ..color = AppColors.coral
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;

    final paintFill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.coral.withValues(alpha: 0.25),
          AppColors.coral.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final dottedTarget = Paint()
      ..color = AppColors.sage
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    // Draw Target Dotted Line
    final targetY = size.height * (1.0 - safeTargetThreshold);
    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
          Offset(startX, targetY), Offset(startX + 6, targetY), dottedTarget);
      startX += 10;
    }

    if (points.length == 1) {
      final pointVal = points[0].isNaN ? 0.0 : points[0].clamp(0.0, 1.0);
      final y = size.height * (1.0 - (pointVal * 0.9));
      final x = size.width / 2;

      // Draw horizontal line representing this level
      final singleLine = Paint()
        ..color = AppColors.coral.withValues(alpha: 0.5)
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), singleLine);

      // Fill area under line
      final fillPath = Path()
        ..moveTo(0, size.height)
        ..lineTo(0, y)
        ..lineTo(size.width, y)
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(fillPath, paintFill);

      // Draw point circle safely
      canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = Colors.white);
      canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = AppColors.coral);
      return;
    }

    // Path for curve
    final path = Path();
    final fillPath = Path();

    final stepX = size.width / (points.length - 1);

    for (int i = 0; i < points.length; i++) {
      final pointVal = points[i].isNaN ? 0.0 : points[i].clamp(0.0, 1.0);
      final x = i * stepX;
      final y = size.height * (1.0 - (pointVal * 0.9));

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        final prevPointVal =
            points[i - 1].isNaN ? 0.0 : points[i - 1].clamp(0.0, 1.0);
        final prevX = (i - 1) * stepX;
        final prevY = size.height * (1.0 - (prevPointVal * 0.9));
        final cX1 = prevX + (x - prevX) / 2;
        final cY1 = prevY;
        final cX2 = prevX + (x - prevX) / 2;
        final cY2 = y;
        path.cubicTo(cX1, cY1, cX2, cY2, x, y);
        fillPath.cubicTo(cX1, cY1, cX2, cY2, x, y);
      }

      // Draw point circle
      if (!x.isNaN && !y.isNaN) {
        canvas.drawCircle(Offset(x, y), 3.5, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = AppColors.coral);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, paintFill);
    canvas.drawPath(path, paintLine);
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.targetThreshold != targetThreshold;
}
