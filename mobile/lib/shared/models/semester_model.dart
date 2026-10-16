class SemesterModel {
  final String id;
  final String userId;
  final int semesterNumber;
  final String label;
  final String startDate;
  final String endDate;
  final String status;
  final bool isActive;
  final int totalWeeks;
  final int currentWeek;
  final int weeksRemaining;
  final double progressPercentage;
  final List<int> workingDays;
  final int classStartHour;
  final int classEndHour;

  SemesterModel({
    required this.id,
    required this.userId,
    required this.semesterNumber,
    required this.label,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.isActive,
    required this.totalWeeks,
    required this.currentWeek,
    required this.weeksRemaining,
    required this.progressPercentage,
    this.workingDays = const [0, 1, 2, 3, 4, 5],
    this.classStartHour = 9,
    this.classEndHour = 16,
  });

  factory SemesterModel.fromJson(Map<String, dynamic> json) {
    return SemesterModel(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? '',
      semesterNumber: json['semester_number'] ?? 5,
      label: json['label'] ?? '5th Semester',
      startDate: json['start_date'] ?? '2026-08-01',
      endDate: json['end_date'] ?? '2026-12-20',
      status: json['status'] ?? 'ACTIVE',
      isActive: json['is_active'] ?? false,
      totalWeeks: json['total_weeks'] ?? 16,
      currentWeek: json['current_week'] ?? 12,
      weeksRemaining: json['weeks_remaining'] ?? 4,
      progressPercentage: (json['progress_percentage'] as num?)?.toDouble() ?? 75.0,
      workingDays: (json['working_days'] as List?)?.map((e) => (e as num).toInt()).toList() ?? const [0, 1, 2, 3, 4, 5],
      classStartHour: (json['class_start_hour'] as num?)?.toInt() ?? 9,
      classEndHour: (json['class_end_hour'] as num?)?.toInt() ?? 16,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'semester_number': semesterNumber,
    'label': label,
    'start_date': startDate,
    'end_date': endDate,
    'status': status,
    'is_active': isActive,
    'total_weeks': totalWeeks,
    'current_week': currentWeek,
    'weeks_remaining': weeksRemaining,
    'progress_percentage': progressPercentage,
    'working_days': workingDays,
    'class_start_hour': classStartHour,
    'class_end_hour': classEndHour,
  };
}
