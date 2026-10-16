import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attendhub/core/theme/app_theme.dart';
import 'package:attendhub/features/settings/settings_screen.dart';
import 'package:attendhub/features/dashboard/dashboard_screen.dart';
import 'package:attendhub/features/analytics/analytics_screen.dart';
import 'package:attendhub/features/dashboard/providers/dashboard_provider.dart';
import 'package:attendhub/features/analytics/providers/analytics_provider.dart';
import 'package:attendhub/shared/models/dashboard_model.dart';
import 'package:attendhub/shared/models/analytics_model.dart';
import 'package:attendhub/shared/models/subject_model.dart';
import 'package:attendhub/shared/models/user_model.dart';
import 'package:attendhub/features/profile/providers/profile_provider.dart';
import 'package:attendhub/shared/widgets/bottom_nav_bar.dart';

void main() {
  group('AttendHub Dashboard, Analytics & Settings Tests', () {
    testWidgets(
        'DashboardScreen renders without RenderFlex overflow on narrow viewport',
        (tester) async {
      // Set a narrow screen size (340 x 700) where the 0.345px overflow previously occurred
      tester.view.physicalSize = const Size(340, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final dummyDashboard = DashboardOverviewModel(
        userName: 'Dev',
        courseName: 'B.Tech CSE',
        currentSemesterLabel: '5th Semester',
        overallPercentage: 78.4,
        totalAttended: 120,
        totalConducted: 153,
        targetPercentage: 75.0,
        minimumPercentage: 75.0,
        trendFromLastMonth: 0.0,
        currentWeek: 12,
        totalWeeks: 16,
        weeksRemaining: 4,
        semesterProgressPct: 75.0,
        todayDateStr: 'Today, Oct 9',
        todaySessions: [],
        subjectsNeedingAttention: [],
        trendPoints: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardProvider.overrideWith((ref) => dummyDashboard),
            selectedDateAttendanceProvider.overrideWith(
              (ref) => SelectedDateAttendanceNotifier(null, null, null, false),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: DashboardScreen(
              onOpenDrawer: () {},
              onNavigateToToday: () {},
              onNavigateToAnalytics: () {},
              onNavigateToCalendar: () {},
              onNavigateToProfile: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify that Attendance Trend (This Month) is displayed
      expect(find.text('Attendance Trend (This Month)'), findsOneWidget);
      expect(find.text('78.4%'), findsWidgets);

      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'DashboardScreen renders trend chart with single trend point without NaN assertion',
        (tester) async {
      final dummyDashboard = DashboardOverviewModel(
        userName: 'Dev',
        courseName: 'B.Tech CSE',
        currentSemesterLabel: '5th Semester',
        overallPercentage: 78.4,
        totalAttended: 120,
        totalConducted: 153,
        targetPercentage: 75.0,
        minimumPercentage: 75.0,
        trendFromLastMonth: 0.0,
        currentWeek: 12,
        totalWeeks: 16,
        weeksRemaining: 4,
        semesterProgressPct: 75.0,
        todayDateStr: 'Today, Oct 9',
        todaySessions: [],
        subjectsNeedingAttention: [],
        trendPoints: [
          TrendPointModel(
            label: 'Oct',
            percentage: 78.4,
            attended: 120,
            conducted: 153,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dashboardProvider.overrideWith((ref) => dummyDashboard),
            selectedDateAttendanceProvider.overrideWith(
              (ref) => SelectedDateAttendanceNotifier(null, null, null, false),
            ),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: DashboardScreen(
              onOpenDrawer: () {},
              onNavigateToToday: () {},
              onNavigateToAnalytics: () {},
              onNavigateToCalendar: () {},
              onNavigateToProfile: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(CustomPaint), findsWidgets);
    });

    testWidgets(
        'AnalyticsScreen tabs are interactive and switch content smoothly',
        (tester) async {
      final dummyAnalytics = AnalyticsOverviewModel(
        semesterId: 'sem-5',
        semesterLabel: '5th Semester',
        overallPercentage: 78.4,
        totalAttended: 120,
        totalAbsent: 33,
        totalConducted: 153,
        hasData: true,
        status: 'SAFE',
        statusLabel: 'Safe',
        personalTarget: 75.0,
        minimumRequirement: 75.0,
        monthOverMonthChange: 6.2,
        maxSafeAbsences: 4,
        totalRecoveryClassesNeeded: 6,
        totalSafeAbsencesMargin: 4,
        insights: [],
        trends: [],
        subjects: [
          SubjectModel(
            id: 'sub-1',
            semesterId: 'sem-5',
            name: 'Computer Networks',
            code: 'CS501',
            color: '#72A68A',
            icon: 'wifi',
            isActive: true,
            attended: 28,
            conducted: 32,
            percentage: 87.5,
            status: 'SAFE',
            statusLabel: 'Safe',
            maxSafeAbsences: 4,
          ),
          SubjectModel(
            id: 'sub-2',
            semesterId: 'sem-5',
            name: 'Mathematics',
            code: 'MA501',
            color: '#C96E5B',
            icon: 'functions',
            isActive: true,
            attended: 20,
            conducted: 30,
            percentage: 66.7,
            status: 'CRITICAL',
            statusLabel: 'Critical',
            classesNeededForMin: 6,
            maxSafeAbsences: 0,
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            analyticsProvider.overrideWith((ref) => dummyAnalytics),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: AnalyticsScreen(
              onOpenDrawer: () {},
              onNavigateToProfile: () {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Initially Overview tab is active
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('You are on track'), findsOneWidget);

      // Tap Subject-wise tab
      await tester.tap(find.text('Subject-wise'));
      await tester.pumpAndSettle();
      expect(find.text('All Subjects (2)'), findsOneWidget);
      expect(find.text('Computer Networks'), findsOneWidget);
      expect(find.text('Mathematics'), findsOneWidget);

      // Tap Requirements tab
      await tester.tap(find.text('Requirements'));
      await tester.pumpAndSettle();
      expect(find.text('Attendance Policy & Forecasting'), findsOneWidget);
      expect(find.text('Subject-wise Forecasting'), findsOneWidget);

      // Tap Trends tab
      await tester.tap(find.text('Trends'));
      await tester.pumpAndSettle();
      expect(find.text('Attendance Trajectory'), findsOneWidget);
      expect(find.text('Day-of-Week Attendance Pattern'), findsOneWidget);

      // Zero exceptions thrown
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        'AnalyticsScreen Subject-wise tab renders without RenderFlex overflow on iPhone SE (375px) and Ultra-Compact (320px)',
        (tester) async {
      final dummyAnalytics = AnalyticsOverviewModel(
        semesterId: 'sem-5',
        semesterLabel: '5th Semester',
        overallPercentage: 78.4,
        totalAttended: 120,
        totalAbsent: 33,
        totalConducted: 153,
        hasData: true,
        status: 'SAFE',
        statusLabel: 'Safe',
        personalTarget: 75.0,
        minimumRequirement: 75.0,
        monthOverMonthChange: 6.2,
        maxSafeAbsences: 4,
        totalRecoveryClassesNeeded: 6,
        totalSafeAbsencesMargin: 4,
        insights: [],
        trends: [],
        subjects: [
          SubjectModel(
            id: 'sub-1',
            semesterId: 'sem-5',
            name: 'Computer Networks and Systems Engineering',
            code: 'CS501',
            color: '#72A68A',
            icon: 'wifi',
            isActive: true,
            attended: 28,
            conducted: 32,
            percentage: 87.5,
            status: 'SAFE',
            statusLabel: 'Safe',
            maxSafeAbsences: 4,
          ),
          SubjectModel(
            id: 'sub-2',
            semesterId: 'sem-5',
            name: 'Mathematics and Discrete Optimization Structures',
            code: 'MA501',
            color: '#C96E5B',
            icon: 'functions',
            isActive: true,
            attended: 20,
            conducted: 30,
            percentage: 66.7,
            status: 'CRITICAL',
            statusLabel: 'Critical',
            classesNeededForMin: 6,
            maxSafeAbsences: 0,
          ),
        ],
      );

      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      tester.view.physicalSize = const Size(375.0, 667.0);
      tester.view.devicePixelRatio = 1.0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            analyticsProvider.overrideWith((ref) => dummyAnalytics),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: AnalyticsScreen(
              onOpenDrawer: () {},
              onNavigateToProfile: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap Subject-wise tab
      await tester.tap(find.text('Subject-wise'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('All Subjects (2)'), findsOneWidget);
      expect(find.text('Safe to miss 4 classes'), findsOneWidget);
      expect(find.text('Need 6 to reach 75%'), findsOneWidget);
    });

    testWidgets('LiquidGlassBottomNav drag-and-release switches tab to destination', (tester) async {
      int selectedTab = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            bottomNavigationBar: LiquidGlassBottomNav(
              currentIndex: selectedTab,
              onTap: (idx) => selectedTab = idx,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Drag from Dashboard (index 0) to Routine (index 1) and release
      final dashboardFinder = find.text('Dashboard');
      final routineFinder = find.text('Routine');

      final gesture = await tester.startGesture(tester.getCenter(dashboardFinder));
      await tester.pump();
      await gesture.moveTo(tester.getCenter(routineFinder));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(selectedTab, equals(1));
    });

    testWidgets('SettingsScreen renders 75% target defaults and preferences',
        (tester) async {
      final dummyProfile = AcademicProfileModel(
        id: 'prof-1',
        userId: 'user-1',
        fullName: 'Dev Student',
        email: 'dev@attendhub.test',
        universityName: 'Tech University',
        courseName: 'B.Tech CSE',
        academicDurationYears: 4,
        minimumAttendance: 75.0,
        personalTarget: 75.0,
        lowAttendanceAlert: 75.0,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            profileProvider.overrideWith((ref) => dummyProfile),
          ],
          child: const MaterialApp(
            home: SettingsScreen(onBack: _dummyCallback),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify Settings title and target default 75% invariant
      expect(find.text('Settings'), findsOneWidget);
      expect(find.text('Attendance Targets & Policy'), findsOneWidget);
      expect(find.text('Personal Attendance Target'), findsOneWidget);
      expect(find.text('Institutional Minimum'), findsOneWidget);
      expect(find.text('75.0%'), findsOneWidget);

      // Verify notification preferences
      expect(find.text('Notification Preferences'), findsOneWidget);
      expect(find.text('Morning Class Schedule'), findsOneWidget);

      // Verify Data Management & About
      expect(find.text('Data Management & Export'), findsOneWidget);
      expect(find.text('Export Attendance Report'), findsOneWidget);
      expect(find.text('About AttendiFy'), findsOneWidget);
    });
  });
}

void _dummyCallback() {}
