import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:attendhub/core/theme/app_theme.dart';
import 'package:attendhub/features/today/today_screen.dart';
import 'package:attendhub/features/today/providers/today_provider.dart';

import 'package:attendhub/shared/models/semester_model.dart';
import 'package:attendhub/shared/providers/semesters_provider.dart';

class FakeTodayNotifier extends TodayNotifier {
  final TodayState fakeState;

  FakeTodayNotifier(this.fakeState) : super() {
    state = fakeState;
  }

  @override
  Future<void> loadToday({int? offset}) async {
    // No-op for tests
  }
}

class FakeSemestersNotifier extends StateNotifier<SemestersState> implements SemestersNotifier {
  FakeSemestersNotifier(super.state);

  @override
  void clear() {}

  @override
  Future<void> loadSemesters() async {}

  @override
  Future<bool> switchSemester(String semesterId) async => true;
}

void main() {
  final sampleTimetable = [
    {
      'id': 'tt-1',
      'subject_name': 'Software Engineering',
      'subject_color': '#C96E5B',
      'day_of_week': 0, // Monday
      'start_time': '09:00',
      'end_time': '10:00',
      'room': 'LH-101',
      'class_type': 'Theory',
      'faculty_name': 'Prof. A. Sharma',
      'is_attended': true,
      'is_absent': false,
      'is_not_held': false,
      'is_unmarked': false,
    },
    {
      'id': 'tt-2',
      'subject_name': 'Database Systems',
      'subject_color': '#72A68A',
      'day_of_week': 1, // Tuesday
      'start_time': '10:00',
      'end_time': '11:00',
      'room': 'LH-102',
      'class_type': 'Theory',
      'faculty_name': 'Dr. M. Roy',
      'is_attended': false,
      'is_absent': true,
      'is_not_held': false,
      'is_unmarked': false,
    },
    {
      'id': 'tt-3',
      'subject_name': 'Computer Networks',
      'subject_color': '#4A80B0',
      'day_of_week': 2, // Wednesday
      'start_time': '11:00',
      'end_time': '12:00',
      'room': 'LH-201',
      'class_type': 'Theory',
      'faculty_name': 'Dr. S. Das',
      'is_attended': false,
      'is_absent': false,
      'is_not_held': false,
      'is_unmarked': true,
    },
  ];

  final dummyTodayState = TodayState(
    isLoading: false,
    dateStr: 'Tuesday, 13 Oct 2026',
    semesterLabel: '5th Semester',
    sessions: [],
    timetableEntries: sampleTimetable,
    weekStartDateStr: '2026-10-12',
    weekEndDateStr: '2026-10-18',
  );

  Widget createTestWidget({TodayState? state, SemestersState? semestersState}) {
    return ProviderScope(
      overrides: [
        todayProvider.overrideWith((ref) => FakeTodayNotifier(state ?? dummyTodayState)),
        if (semestersState != null)
          semestersProvider.overrideWith((ref) => FakeSemestersNotifier(semestersState)),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: TodayScreen(
          onOpenDrawer: () {},
        ),
      ),
    );
  }

  group('Routine Weekly Grid Widget Tests', () {
    testWidgets('TodayScreen renders Weekly Routine Grid only with NO Today toggle segment', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // Header greeting & context
      expect(find.text('Weekly Routine'), findsOneWidget);
      expect(find.text('5th Semester • Classes'), findsOneWidget);

      // Verify NO segmented toggle for Today tab
      expect(find.textContaining('Today ('), findsNothing);
      expect(find.text('Scheduled for today'), findsNothing);
      expect(find.text("Save Today's Attendance"), findsNothing);

      // Verify Weekly Schedule Grid components
      expect(find.text('Weekly Schedule Grid'), findsOneWidget);
      expect(find.text('DAY'), findsOneWidget);
      expect(find.text('MON'), findsOneWidget);
      expect(find.text('TUE'), findsOneWidget);
      expect(find.text('WED'), findsOneWidget);

      // Verify subjects appear in grid
      expect(find.text('Software Engineering'), findsWidgets);
      expect(find.text('Database Systems'), findsWidgets);
      expect(find.text('Computer Networks'), findsWidgets);
    });

    testWidgets('Ticks represent ONLY actual persisted ATTENDED records (no false ticks)', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      // In sampleTimetable:
      // tt-1 (Software Engineering) has is_attended: true -> MUST show checkmark
      // tt-2 (Database Systems) has is_absent: true -> MUST NOT show checkmark
      // tt-3 (Computer Networks) has is_unmarked: true -> MUST NOT show checkmark
      // Therefore, exactly ONE checkmark icon is rendered across the entire grid!
      final checkmarkIcons = find.byIcon(Icons.check_circle_rounded);
      expect(checkmarkIcons, findsOneWidget);
    });

    testWidgets('Tapping a slot opens details sheet with quick attendance update actions', (tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final slotFinder = find.text('Software Engineering').first;
      await tester.tap(slotFinder);
      await tester.pumpAndSettle();

      // Interactive update prompt and options
      expect(find.textContaining('Update Attendance'), findsOneWidget);
      expect(find.text('Edit Routine in Academic Setup'), findsOneWidget);
      expect(find.text('Attended'), findsWidgets);
      expect(find.text('Absent'), findsWidgets);
      expect(find.text('Not Held'), findsWidgets);

      // Close bottom sheet
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining('Update Attendance'), findsNothing);
    });

    testWidgets('Empty timetable state displays clean setup message', (tester) async {
      final emptyState = TodayState(
        isLoading: false,
        dateStr: 'Today',
        semesterLabel: '5th Semester',
        sessions: [],
        timetableEntries: [],
      );

      await tester.pumpWidget(createTestWidget(state: emptyState));
      await tester.pumpAndSettle();

      expect(find.text("Your timetable isn't set up yet."), findsOneWidget);
      expect(find.text('Set Up Timetable'), findsOneWidget);
    });

    testWidgets('RoutineScreen renders without overflow at 320px (iPhone SE)', (tester) async {
      tester.view.physicalSize = const Size(320, 680);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      final err = tester.takeException();
      if (err is FlutterError) {
        for (final d in err.diagnostics) {
          debugPrint('DIAG VAL: ${d.value}');
        }
      }
      expect(err, isNull);
    });

    testWidgets('RoutineScreen renders without overflow at 430px (iPhone Pro Max)', (tester) async {
      tester.view.physicalSize = const Size(430, 932);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(createTestWidget());
      expect(tester.takeException(), isNull);
    });

    testWidgets('RoutineScreen completely omits "No more classes scheduled for today" card when no class is live or next', (tester) async {
      final emptyState = TodayState(
        isLoading: false,
        dateStr: 'Tuesday, 13 Oct 2026',
        semesterLabel: '5th Semester',
        sessions: [],
        timetableEntries: [],
        weekStartDateStr: '2026-10-12',
        weekEndDateStr: '2026-10-18',
      );
      await tester.pumpWidget(createTestWidget(state: emptyState));
      await tester.pumpAndSettle();

      expect(find.textContaining('No more classes scheduled for today'), findsNothing);
    });

    testWidgets('TodayScreen respects activeSemester Mon-Fri working_days: Saturday and Sunday are NOT rendered in grid', (tester) async {
      final monFriSemester = SemesterModel(
        id: 'sem-mon-fri',
        userId: 'user-1',
        semesterNumber: 1,
        label: '1st Semester',
        startDate: '2026-08-01',
        endDate: '2026-12-15',
        status: 'ACTIVE',
        isActive: true,
        totalWeeks: 16,
        currentWeek: 8,
        weeksRemaining: 8,
        progressPercentage: 50.0,
        workingDays: [0, 1, 2, 3, 4], // Mon to Fri
        classStartHour: 9,
        classEndHour: 16,
      );

      await tester.pumpWidget(createTestWidget(
        semestersState: SemestersState(semesters: [monFriSemester]),
      ));
      await tester.pumpAndSettle();

      expect(find.text('MON'), findsOneWidget);
      expect(find.text('TUE'), findsOneWidget);
      expect(find.text('WED'), findsOneWidget);
      expect(find.text('THU'), findsOneWidget);
      expect(find.text('FRI'), findsOneWidget);
      expect(find.text('SAT'), findsNothing);
      expect(find.text('SUN'), findsNothing);
    });

    testWidgets('TodayScreen displays Saturday when activeSemester working_days includes Saturday ([0, 1, 2, 3, 4, 5])', (tester) async {
      final monSatSemester = SemesterModel(
        id: 'sem-mon-sat',
        userId: 'user-1',
        semesterNumber: 1,
        label: '1st Semester',
        startDate: '2026-08-01',
        endDate: '2026-12-15',
        status: 'ACTIVE',
        isActive: true,
        totalWeeks: 16,
        currentWeek: 8,
        weeksRemaining: 8,
        progressPercentage: 50.0,
        workingDays: [0, 1, 2, 3, 4, 5], // Mon to Sat
        classStartHour: 9,
        classEndHour: 16,
      );

      await tester.pumpWidget(createTestWidget(
        semestersState: SemestersState(semesters: [monSatSemester]),
      ));
      await tester.pumpAndSettle();

      expect(find.text('MON'), findsOneWidget);
      expect(find.text('SAT'), findsOneWidget);
      expect(find.text('SUN'), findsNothing);
    });

    testWidgets('TodayScreen respects activeSemester classStartHour and classEndHour', (tester) async {
      final customHoursSemester = SemesterModel(
        id: 'sem-hours',
        userId: 'user-1',
        semesterNumber: 1,
        label: '1st Semester',
        startDate: '2026-08-01',
        endDate: '2026-12-15',
        status: 'ACTIVE',
        isActive: true,
        totalWeeks: 16,
        currentWeek: 8,
        weeksRemaining: 8,
        progressPercentage: 50.0,
        workingDays: [0, 1, 2, 3, 4],
        classStartHour: 8,
        classEndHour: 14,
      );

      await tester.pumpWidget(createTestWidget(
        semestersState: SemestersState(semesters: [customHoursSemester]),
      ));
      await tester.pumpAndSettle();

      // Hours 8 AM through 1 PM
      expect(find.text('8 AM'), findsOneWidget);
      expect(find.text('1 PM'), findsOneWidget);
    });
  });
}
