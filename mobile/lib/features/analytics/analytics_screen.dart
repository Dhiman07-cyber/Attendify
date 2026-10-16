import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/local_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../shared/widgets/landscape_header.dart';
import '../../shared/widgets/shimmer_skeleton.dart';
import '../../shared/widgets/liquid_glass_card.dart';
import '../../shared/widgets/attendance_progress_ring.dart';
import '../../shared/models/subject_model.dart';
import '../../shared/models/analytics_model.dart';
import '../setup/academic_setup_screen.dart';
import 'providers/analytics_provider.dart';

class AnalyticsScreen extends ConsumerStatefulWidget {
  final VoidCallback onOpenDrawer;
  final VoidCallback? onNavigateToProfile;
  final VoidCallback? onOpenSetup;

  const AnalyticsScreen({
    super.key,
    required this.onOpenDrawer,
    this.onNavigateToProfile,
    this.onOpenSetup,
  });

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _activeTabIndex = 0; // 0=Overview, 1=Subject-wise, 2=Requirements, 3=Trends

  Widget _buildAnalyticsBody(AnalyticsOverviewModel data) {
    return SingleChildScrollView(
      clipBehavior: Clip.hardEdge,
      padding: const EdgeInsets.only(bottom: 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Header with landscape artwork and actions
          LandscapeHeaderWidget(
            greeting: 'Analytics',
            userName: 'Attendance Insights',
            semesterInfo: data.semesterLabel,
            showActions: false,
            topOffset: 76,
          ),

          const SizedBox(height: 18),

          // 2. Interactive Filter Tabs: Overview | Subject-wise | Requirements | Trends
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFFF1EBE6),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Expanded(child: _buildInteractiveTab('Overview', 0)),
                  Expanded(child: _buildInteractiveTab('Subject-wise', 1)),
                  Expanded(child: _buildInteractiveTab('Requirements', 2)),
                  Expanded(child: _buildInteractiveTab('Trends', 3)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 14),

          // 3. Tab Content View
          if (data.subjects.isEmpty) ...[
            _buildEmptyTimetableCard(context),
          ] else if (_activeTabIndex == 0) ...[
            _buildOverviewTab(data),
          ] else if (_activeTabIndex == 1) ...[
            _buildSubjectWiseTab(data),
          ] else if (_activeTabIndex == 2) ...[
            _buildRequirementsTab(data),
          ] else if (_activeTabIndex == 3) ...[
            _buildTrendsTab(data),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyTimetableCard(BuildContext context) {
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
              'Configure your weekly routine and curriculum in Academic Setup to view attendance analytics.',
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
                if (widget.onOpenSetup != null) {
                  widget.onOpenSetup!();
                } else {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AcademicSetupScreen(
                        onComplete: () => ref.refresh(analyticsProvider),
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

  @override
  Widget build(BuildContext context) {
    final analyticsAsync = ref.watch(analyticsProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: analyticsAsync.when(
        loading: () {
          final cached = LocalStorage().getCachedAnalyticsSync();
          if (cached != null) {
            try {
              final model = AnalyticsOverviewModel.fromJson(cached);
              if (model.subjects.isNotEmpty) {
                return _buildAnalyticsBody(model);
              }
            } catch (_) {}
          }
          return _buildAnalyticsSkeleton(context);
        },
        error: (err, _) => Center(child: Text(err.toString())),
        data: (data) {
          if (data.subjects.isEmpty &&
              (analyticsAsync.isLoading || analyticsAsync.isRefreshing)) {
            return _buildAnalyticsSkeleton(context);
          }
          return _buildAnalyticsBody(data);
        },
      ),
    );
  }

  Widget _buildInteractiveTab(String label, int index) {
    final isActive = _activeTabIndex == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _activeTabIndex = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutCubic,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? AppColors.terracotta : AppColors.inkMuted,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildAnalyticsSkeleton(BuildContext context) {
    return SingleChildScrollView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header skeleton
          const LandscapeHeaderWidget(
            greeting: 'Analytics',
            userName: 'Attendance Insights',
            semesterInfo: 'Active Semester • Overview',
            showActions: false,
            topOffset: 76,
            isLoading: true,
          ),

          const SizedBox(height: 18),

          // Tab Bar Skeleton
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ShimmerLoading(
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFF1EBE6),
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Content Skeleton
          ShimmerLoading(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  // Top metric cards side-by-side
                  const IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          flex: 3,
                          child: LiquidGlassCard(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              children: [
                                SkeletonBox.circle(size: 80),
                                SizedBox(height: 12),
                                SkeletonBox.text(width: 90, height: 12),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: LiquidGlassCard(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox.circle(size: 32),
                                SizedBox(height: 12),
                                SkeletonBox.text(width: 80, height: 14),
                                SizedBox(height: 8),
                                SkeletonBox.text(
                                    width: double.infinity, height: 10),
                                SizedBox(height: 4),
                                SkeletonBox.text(width: 70, height: 10),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Subject-wise card skeleton
                  LiquidGlassCard(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SkeletonBox.text(width: 160, height: 14),
                        const SizedBox(height: 16),
                        ...List.generate(
                          3,
                          (i) => const Padding(
                            padding: EdgeInsets.only(bottom: 14),
                            child: Row(
                              children: [
                                SkeletonBox(
                                    width: 32,
                                    height: 32,
                                    borderRadius:
                                        BorderRadius.all(Radius.circular(8))),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      SkeletonBox.text(
                                          width: 120, height: 12),
                                      SizedBox(height: 6),
                                      SkeletonBox.text(
                                          width: double.infinity, height: 4),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 12),
                                SkeletonBox.text(width: 36, height: 12),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Side by side requirement cards
                  const IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: LiquidGlassCard(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox.circle(size: 20),
                                SizedBox(height: 8),
                                SkeletonBox.text(width: 100, height: 12),
                                SizedBox(height: 12),
                                SkeletonBox.text(width: 40, height: 26),
                                SizedBox(height: 8),
                                SkeletonBox.text(
                                    width: double.infinity, height: 10),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: LiquidGlassCard(
                            padding: EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                SkeletonBox.circle(size: 20),
                                SizedBox(height: 8),
                                SkeletonBox.text(width: 100, height: 12),
                                SizedBox(height: 12),
                                SkeletonBox.text(width: 40, height: 26),
                                SizedBox(height: 8),
                                SkeletonBox.text(
                                    width: double.infinity, height: 10),
                              ],
                            ),
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
    );
  }

  // ==========================================
  // TAB 0: OVERVIEW
  // ==========================================
  Widget _buildOverviewTab(AnalyticsOverviewModel data) {
    final firstCritical = data.subjects
        .where((s) => (s.classesNeededForMin ?? 0) > 0)
        .firstOrNull;
    final safeSubjects =
        data.subjects.where((s) => s.maxSafeAbsences > 0).toList();
    final firstSafe = safeSubjects.isNotEmpty ? safeSubjects[0] : null;
    final secondSafe = safeSubjects.length > 1 ? safeSubjects[1] : null;

    final bool hasNoData = data.totalConducted == 0 || !data.hasData;
    final bool isOnTrack =
        (data.overallPercentage ?? 0.0) >= data.personalTarget;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Top Row: Overall Ring & "You are on track" Card (EQUAL HEIGHT VIA IntrinsicHeight)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Overall Ring
                Expanded(
                  flex: 6,
                  child: LiquidGlassCard(
                    padding: const EdgeInsets.all(12),
                    child: AttendanceProgressRing(
                      percentage: data.overallPercentage,
                      attended: data.totalAttended,
                      conducted: data.totalConducted,
                      targetPercentage: data.personalTarget,
                      minimumPercentage: data.minimumRequirement,
                      trendChange: data.monthOverMonthChange,
                      size: 100,
                    ),
                  ),
                ),

                const SizedBox(width: 10),

                // Dynamic Status Card (stretched to match height)
                Expanded(
                  flex: 5,
                  child: LiquidGlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: hasNoData
                                    ? AppColors.sandLight
                                    : isOnTrack
                                        ? AppColors.sageLight
                                        : AppColors.coralLight,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                hasNoData
                                    ? Icons.info_outline_rounded
                                    : isOnTrack
                                        ? Icons.track_changes_rounded
                                        : Icons.warning_amber_rounded,
                                size: 18,
                                color: hasNoData
                                    ? AppColors.inkMuted
                                    : isOnTrack
                                        ? AppColors.sage
                                        : AppColors.coral,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              hasNoData
                                  ? 'No records yet'
                                  : isOnTrack
                                      ? 'You are on track'
                                      : 'Below target',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.5,
                                  color: hasNoData
                                      ? AppColors.ink
                                      : isOnTrack
                                          ? AppColors.sageDark
                                          : AppColors.coral),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              hasNoData
                                  ? 'Mark classes to start tracking attendance.'
                                  : isOnTrack
                                      ? 'Attend regularly to stay above 75% in all subjects.'
                                      : 'Attend upcoming classes to recover to target.',
                              style: AppTypography.bodySmall
                                  .copyWith(fontSize: 10.5, height: 1.25),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                        if (!hasNoData)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 5),
                            decoration: BoxDecoration(
                              color: (isOnTrack
                                      ? AppColors.sageLight
                                      : AppColors.coralLight)
                                  .withValues(alpha: 0.6),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isOnTrack
                                      ? Icons.check_circle_rounded
                                      : Icons.warning_rounded,
                                  size: 13,
                                  color: isOnTrack
                                      ? AppColors.sageDark
                                      : AppColors.coral,
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      isOnTrack
                                          ? 'All subjects safe'
                                          : 'Attention needed',
                                      style: TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w700,
                                          color: isOnTrack
                                              ? AppColors.sageDark
                                              : AppColors.coral),
                                    ),
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

        // Subject-wise Attendance Card List with "View Details" click to Tab 1
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LiquidGlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Text(
                        'Subject-wise Attendance',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => setState(() => _activeTabIndex = 1),
                      child: const Text(
                        'View Details',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: AppColors.terracotta),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: data.subjects.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final sub = data.subjects[index];
                    return _buildSubjectProgressRow(sub);
                  },
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Grid Row: Attendance Requirements & You can miss (EQUAL HEIGHT VIA IntrinsicHeight)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Attendance Requirements (Click opens Tab 2)
                Expanded(
                  child: LiquidGlassCard(
                    padding: const EdgeInsets.all(16),
                    onTap: () => setState(() => _activeTabIndex = 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Icon(Icons.bar_chart_rounded,
                                    size: 18, color: AppColors.coral),
                                Icon(Icons.chevron_right_rounded,
                                    size: 16, color: AppColors.inkMuted),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text('Attendance Requirements',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 12)),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  hasNoData ? '--' : '${data.totalRecoveryClassesNeeded}',
                                  style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: hasNoData ? AppColors.inkMuted : AppColors.coral),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                      hasNoData
                                          ? 'Awaiting class attendance records.'
                                          : 'Total classes needed to reach 75% in all subjects.',
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.inkMuted)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFAF6F3),
                              borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            children: [
                              Icon(
                                hasNoData
                                    ? Icons.schedule_rounded
                                    : (firstCritical != null
                                        ? Icons.warning_amber_rounded
                                        : Icons.check_circle_rounded),
                                size: 14,
                                color: hasNoData
                                    ? AppColors.inkMuted
                                    : (firstCritical != null
                                        ? AppColors.coral
                                        : AppColors.sage),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  hasNoData
                                      ? 'Awaiting classes'
                                      : (firstCritical != null
                                          ? '${firstCritical.name}: ${firstCritical.classesNeededForMin ?? 1} classes'
                                          : 'All subjects safe'),
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600),
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

                const SizedBox(width: 12),

                // You Can Miss (Click opens Tab 2)
                Expanded(
                  child: LiquidGlassCard(
                    padding: const EdgeInsets.all(16),
                    onTap: () => setState(() => _activeTabIndex = 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Icon(Icons.calendar_today_rounded,
                                    size: 18, color: AppColors.sage),
                                Icon(Icons.chevron_right_rounded,
                                    size: 16, color: AppColors.inkMuted),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text('You can miss',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 12)),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  hasNoData ? '--' : (firstSafe != null ? '${firstSafe.maxSafeAbsences}' : '0'),
                                  style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.w800,
                                      color: hasNoData ? AppColors.inkMuted : AppColors.sage),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                      hasNoData
                                          ? 'Safe absence margins will appear once classes are recorded.'
                                          : (firstSafe != null
                                              ? 'classes in ${firstSafe.name} and still stay above 75%.'
                                              : 'safe absences remaining for your targets.'),
                                      style: const TextStyle(
                                          fontSize: 10,
                                          color: AppColors.inkMuted)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                              color: const Color(0xFFFAF6F3),
                              borderRadius: BorderRadius.circular(8)),
                          child: Row(
                            children: [
                              Icon(
                                hasNoData
                                    ? Icons.schedule_rounded
                                    : (firstSafe != null
                                        ? _getSubjectIconData(firstSafe.icon)
                                        : Icons.shield_outlined),
                                size: 14,
                                color: hasNoData ? AppColors.inkMuted : AppColors.sage,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  hasNoData
                                      ? 'Awaiting classes'
                                      : (secondSafe != null
                                          ? '${secondSafe.name}: ${secondSafe.maxSafeAbsences} classes'
                                          : firstSafe != null
                                              ? 'Margin: ${firstSafe.maxSafeAbsences} classes'
                                              : '0 safe absences'),
                                  style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600),
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

        // Overall Attendance Trend (Click opens Tab 3)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: LiquidGlassCard(
            padding: const EdgeInsets.all(18),
            onTap: () => setState(() => _activeTabIndex = 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_graph_rounded,
                        size: 18, color: AppColors.sage),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Overall Attendance Trend',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 14),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Trend Painter with Target line
                if (hasNoData || data.trends.isEmpty)
                  Container(
                    height: 100,
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFAF7F4),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: const Text(
                      'Trend will appear as attendance records accumulate.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppColors.inkMuted,
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 100,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _AnalyticsTrendPainter(
                        trends: data.trends,
                        targetPercentage: data.personalTarget,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

      ],
    );
  }

  // ==========================================
  // TAB 1: SUBJECT-WISE
  // ==========================================
  Widget _buildSubjectWiseTab(dynamic data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'All Subjects (${data.subjects.length})',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.sageLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Target: ${data.personalTarget.toStringAsFixed(0)}%',
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.sageDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: data.subjects.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final sub = data.subjects[index];
              return _buildDetailedSubjectCard(sub, data.personalTarget);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDetailedSubjectCard(SubjectModel sub, double targetPct) {
    final bool hasNoData = sub.conducted == 0;
    final pct = sub.percentage ?? 0.0;
    final isSafe = !hasNoData && pct >= targetPct;
    final isCritical = !hasNoData && pct < 75.0;

    Color badgeColor = hasNoData
        ? AppColors.inkMuted
        : (isSafe
            ? AppColors.sage
            : (isCritical ? AppColors.coral : AppColors.amber));
    Color badgeBg = hasNoData
        ? const Color(0xFFEFECE9)
        : (isSafe
            ? AppColors.sageLight
            : (isCritical ? AppColors.coralLight : AppColors.amberLight));

    return LiquidGlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.getSubjectColor(sub.color).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getSubjectIconData(sub.icon),
                  size: 20,
                  color: AppColors.getSubjectColor(sub.color),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sub.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    if (sub.code != null && sub.code!.isNotEmpty)
                      Text(
                        sub.code!,
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.inkMuted),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  hasNoData ? '--' : '${pct.toStringAsFixed(1)}%',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: badgeColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: hasNoData ? 0.0 : (pct / 100.0).clamp(0.0, 1.0),
              backgroundColor: hasNoData ? const Color(0xFFEFECE9) : badgeColor.withValues(alpha: 0.18),
              valueColor: AlwaysStoppedAnimation<Color>(badgeColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Attended: ${sub.attended} of ${sub.conducted} classes',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall
                      .copyWith(fontSize: 11, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: hasNoData
                    ? const Text(
                        'Awaiting attendance records',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.end,
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkMuted),
                      )
                    : (sub.classesNeededForMin != null && sub.classesNeededForMin! > 0)
                        ? Text(
                            'Need ${sub.classesNeededForMin} to reach 75%',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: AppColors.coral),
                          )
                        : (sub.maxSafeAbsences > 0)
                            ? Text(
                                'Safe to miss ${sub.maxSafeAbsences} classes',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.sageDark),
                              )
                            : const Text(
                                'Already at target',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.sageDark),
                              ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 2: REQUIREMENTS & PLANNING
  // ==========================================
  Widget _buildRequirementsTab(dynamic data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Target Policy Overview Card
          LiquidGlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.rule_folder_rounded,
                        size: 20, color: AppColors.terracotta),
                    SizedBox(width: 8),
                    Text(
                      'Attendance Policy & Forecasting',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBF7F4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('Minimum Required',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 11, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text(
                              '${data.minimumRequirement.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.terracotta),
                            ),
                            const SizedBox(height: 2),
                            const Text('Mandatory threshold',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 10, color: AppColors.inkMuted)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFBF7F4),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.divider),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Text('Personal Target',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 11, color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 6),
                            Text(
                              '${data.personalTarget.toStringAsFixed(0)}%',
                              style: const TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.sage),
                            ),
                            const SizedBox(height: 2),
                            const Text('Default target goal',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 10, color: AppColors.inkMuted)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          const Text(
            'Subject-wise Forecasting',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink),
          ),
          const SizedBox(height: 8),

          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: data.subjects.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final sub = data.subjects[index];
              final hasNoData = sub.conducted == 0;
              final pct = sub.percentage ?? 0.0;
              final isUnder = !hasNoData && pct < 75.0;

              return LiquidGlassCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: hasNoData
                            ? const Color(0xFFEFECE9)
                            : (isUnder ? AppColors.coralLight : AppColors.sageLight),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        hasNoData
                            ? Icons.schedule_rounded
                            : (isUnder ? Icons.warning_amber_rounded : Icons.check_rounded),
                        size: 18,
                        color: hasNoData
                            ? AppColors.inkMuted
                            : (isUnder ? AppColors.coral : AppColors.sageDark),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            sub.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                          Text(
                            hasNoData
                                ? 'No attendance records (0 conducted)'
                                : 'Current: ${pct.toStringAsFixed(1)}% (${sub.attended}/${sub.conducted})',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (hasNoData) ...[
                          const Text(
                            'Awaiting data',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: AppColors.inkMuted),
                          ),
                          const Text(
                            'no advice yet',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.inkMuted),
                          ),
                        ] else if (isUnder) ...[
                          Text(
                            'Need ${sub.classesNeededForMin ?? 1}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AppColors.coral),
                          ),
                          const Text(
                            'to reach 75%',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.inkMuted),
                          ),
                        ] else ...[
                          Text(
                            'Miss ≤ ${sub.maxSafeAbsences}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: AppColors.sageDark),
                          ),
                          const Text(
                            'safe absences',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.inkMuted),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ==========================================
  // TAB 3: TRENDS & PROJECTIONS
  // ==========================================
  Widget _buildTrendsTab(AnalyticsOverviewModel data) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month-over-month Trend Chart Card
          LiquidGlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Attendance Trajectory',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    if (data.totalConducted > 0 &&
                        data.monthOverMonthChange != 0.0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: data.monthOverMonthChange >= 0
                              ? AppColors.sageLight
                              : AppColors.coralLight,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              data.monthOverMonthChange >= 0
                                  ? Icons.arrow_upward_rounded
                                  : Icons.arrow_downward_rounded,
                              size: 11,
                              color: data.monthOverMonthChange >= 0
                                  ? AppColors.sageDark
                                  : AppColors.coral,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              '${data.monthOverMonthChange >= 0 ? '+' : ''}${data.monthOverMonthChange.toStringAsFixed(1)}% MoM',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: data.monthOverMonthChange >= 0
                                      ? AppColors.sageDark
                                      : AppColors.coral),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Continuous trajectory plotted against the ${data.personalTarget.toStringAsFixed(0)}% baseline',
                  style:
                      const TextStyle(fontSize: 11, color: AppColors.inkMuted),
                ),
                const SizedBox(height: 18),
                if (!data.hasData || data.totalConducted == 0 || data.trends.isEmpty)
                  Container(
                    height: 140,
                    width: double.infinity,
                    alignment: Alignment.center,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF9F7F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.show_chart_rounded, size: 28, color: AppColors.inkMuted),
                        SizedBox(height: 8),
                        Text(
                          'Trend will appear as attendance records accumulate.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.inkMuted),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    height: 140,
                    width: double.infinity,
                    child: CustomPaint(
                      painter: _AnalyticsTrendPainter(
                        trends: data.trends,
                        targetPercentage: data.personalTarget,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Weekly Breakdown Analysis
          LiquidGlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Day-of-Week Attendance Pattern',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 12),
                if (!data.hasData || data.totalConducted == 0)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    alignment: Alignment.center,
                    child: const Column(
                      children: [
                        Icon(Icons.calendar_today_outlined,
                            size: 26, color: AppColors.inkMuted),
                        SizedBox(height: 8),
                        Text(
                          'No day-of-week pattern yet',
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.inkMuted),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Pattern will appear once attendance is recorded across weekdays.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11, color: AppColors.inkLight),
                        ),
                      ],
                    ),
                  )
                else ...[
                  _buildDayRow(
                      'Monday',
                      (data.overallPercentage ?? 75.0) / 100.0,
                      '${(data.overallPercentage ?? 75.0).toStringAsFixed(0)}%'),
                  const SizedBox(height: 8),
                  _buildDayRow(
                      'Tuesday',
                      (data.overallPercentage ?? 75.0) / 100.0,
                      '${(data.overallPercentage ?? 75.0).toStringAsFixed(0)}%'),
                  const SizedBox(height: 8),
                  _buildDayRow(
                      'Wednesday',
                      (data.overallPercentage ?? 75.0) / 100.0,
                      '${(data.overallPercentage ?? 75.0).toStringAsFixed(0)}%'),
                  const SizedBox(height: 8),
                  _buildDayRow(
                      'Thursday',
                      (data.overallPercentage ?? 75.0) / 100.0,
                      '${(data.overallPercentage ?? 75.0).toStringAsFixed(0)}%'),
                  const SizedBox(height: 8),
                  _buildDayRow(
                      'Friday',
                      (data.overallPercentage ?? 75.0) / 100.0,
                      '${(data.overallPercentage ?? 75.0).toStringAsFixed(0)}%'),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // End-of-Semester Forecast Card
          LiquidGlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFBECE9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.insights_rounded,
                      color: AppColors.terracotta, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Projected Final Attendance',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        data.hasData && data.overallPercentage != null
                            ? 'If you maintain your current attendance pattern (${data.overallPercentage!.toStringAsFixed(1)}%), your projected semester final is ~${data.overallPercentage!.toStringAsFixed(1)}%.'
                            : 'No attendance data yet. Mark your classes to project your semester final trajectory.',
                        style: const TextStyle(
                            fontSize: 11, color: AppColors.inkMuted),
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
  }

  Widget _buildDayRow(String day, double ratio, String text) {
    return Row(
      children: [
        SizedBox(
          width: 80,
          child: Text(
            day,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: const Color(0xFFEFE9E4),
              valueColor: AlwaysStoppedAnimation<Color>(
                ratio >= 0.75 ? AppColors.sage : AppColors.coral,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        SizedBox(
          width: 34,
          child: Text(
            text,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: ratio >= 0.75 ? AppColors.sageDark : AppColors.coral,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubjectProgressRow(SubjectModel sub) {
    final icon = _getSubjectIconData(sub.icon);
    final hasNoData = sub.conducted == 0;
    final pct = sub.percentage ?? 0.0;
    Color barColor = AppColors.sage;
    if (hasNoData) {
      barColor = AppColors.inkMuted;
    } else if (sub.status == 'CRITICAL' || pct < 75.0) {
      barColor = AppColors.coral;
    } else if (sub.status == 'CAUTION') {
      barColor = AppColors.amber;
    }

    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.getSubjectColor(sub.color)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon,
                  size: 16, color: AppColors.getSubjectColor(sub.color)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          sub.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        children: [
                          Text(
                            hasNoData
                                ? '--'
                                : (sub.percentage != null
                                    ? '${pct.toStringAsFixed(1)}%'
                                    : '0.0%'),
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: hasNoData ? AppColors.inkMuted : AppColors.ink),
                          ),
                          if (!hasNoData &&
                              sub.classesNeededForMin != null &&
                              sub.classesNeededForMin! > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: sub.status == 'CRITICAL'
                                    ? AppColors.coralLight
                                    : AppColors.amberLight,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                'Need ${sub.classesNeededForMin} more',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: sub.status == 'CRITICAL'
                                      ? AppColors.coral
                                      : AppColors.amber,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: hasNoData ? 0.0 : (pct / 100.0).clamp(0.0, 1.0),
                            backgroundColor: hasNoData ? const Color(0xFFEFECE9) : barColor.withValues(alpha: 0.18),
                            valueColor: AlwaysStoppedAnimation<Color>(barColor),
                            minHeight: 4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${sub.attended} / ${sub.conducted}',
                        style: AppTypography.bodySmall.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  IconData _getSubjectIconData(String? icon) {
    if (icon == 'code') return Icons.code_rounded;
    if (icon == 'settings') return Icons.settings_rounded;
    if (icon == 'functions') return Icons.functions_rounded;
    if (icon == 'database') return Icons.storage_rounded;
    if (icon == 'wifi') return Icons.wifi_rounded;
    if (icon == 'chat') return Icons.chat_bubble_outline_rounded;
    return Icons.book_rounded;
  }
}

class _AnalyticsTrendPainter extends CustomPainter {
  final List<TrendPointModel> trends;
  final double targetPercentage;

  _AnalyticsTrendPainter({
    this.trends = const [],
    this.targetPercentage = 75.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final validPoints = trends
        .where((t) => t.percentage != null && !t.percentage!.isNaN)
        .map((t) => (t.percentage! / 100.0).clamp(0.0, 1.0))
        .toList();

    final safeTarget = targetPercentage.isNaN ? 75.0 : targetPercentage;
    final targetThreshold = (safeTarget / 100.0).clamp(0.0, 1.0);
    final targetY = size.height * (1.0 - targetThreshold);

    final dotted = Paint()
      ..color = AppColors.sage
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    double startX = 0;
    while (startX < size.width) {
      canvas.drawLine(
          Offset(startX, targetY), Offset(startX + 6, targetY), dotted);
      startX += 10;
    }

    // Text: Target (75%)
    final tp = TextPainter(
      text: TextSpan(
          text: 'Target (${safeTarget.toStringAsFixed(0)}%)',
          style: const TextStyle(color: AppColors.inkMuted, fontSize: 10)),
      textDirection: TextDirection.ltr,
    )..layout();
    if (size.width >= 70) {
      tp.paint(canvas, Offset(size.width - 70, targetY - 14));
    }

    if (validPoints.length < 2) {
      final noDataTp = TextPainter(
        text: const TextSpan(
          text: 'Trend will appear as attendance records accumulate',
          style: TextStyle(
            color: AppColors.inkLight,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      noDataTp.paint(
        canvas,
        Offset(
          (size.width - noDataTp.width) / 2,
          (size.height - noDataTp.height) / 2 + 10,
        ),
      );
      return;
    }

    final paintLine = Paint()
      ..color = AppColors.coral
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;

    final paintFill = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          AppColors.coral.withValues(alpha: 0.28),
          AppColors.coral.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));

    final path = Path();
    final fillPath = Path();
    final stepX = size.width / (validPoints.length - 1);

    for (int i = 0; i < validPoints.length; i++) {
      final x = i * stepX;
      final y = size.height * (1.0 - validPoints[i]);

      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        final prevX = (i - 1) * stepX;
        final prevY = size.height * (1.0 - validPoints[i - 1]);
        path.cubicTo(
            prevX + (x - prevX) / 2, prevY, prevX + (x - prevX) / 2, y, x, y);
        fillPath.cubicTo(
            prevX + (x - prevX) / 2, prevY, prevX + (x - prevX) / 2, y, x, y);
      }

      if (!x.isNaN && !y.isNaN) {
        canvas.drawCircle(Offset(x, y), 4, Paint()..color = Colors.white);
        canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = AppColors.coral);
      }
    }

    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, paintFill);
    canvas.drawPath(path, paintLine);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
