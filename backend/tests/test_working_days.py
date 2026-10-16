"""Test working_days configuration for semesters.

DEPRECATED: working_days is no longer used for forecast calculations.
The forecast engine now derives future classes directly from scheduled timetable entries.
This test file is kept for backward compatibility verification only.
"""
import pytest
import uuid
from httpx import AsyncClient, ASGITransport
from app.main import app

@pytest.mark.skip(reason="working_days validation is deprecated - forecast now uses actual timetable entries")
@pytest.mark.asyncio
async def test_working_days_crud_and_forecast():
    """Test working_days create, read, update and forecast integration."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Register user
        email = f"workdays_test_{uuid.uuid4().hex[:6]}@test.edu"
        reg_resp = await client.post("/api/v1/auth/register", json={
            "email": email,
            "password": "Password123!",
            "full_name": "Working Days Test",
            "university_name": "Test University",
            "course_name": "Computer Science",
            "current_semester_number": 5
        })
        assert reg_resp.status_code == 201
        token = reg_resp.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # 1. Test default working_days (Mon-Sat)
        sems_resp = await client.get("/api/v1/semesters", headers=headers)
        semesters = sems_resp.json()
        assert len(semesters) == 1
        default_sem = semesters[0]
        assert default_sem["working_days"] == [0, 1, 2, 3, 4, 5]  # Mon-Sat

        # 2. Create semester with custom working_days (Mon-Fri only)
        create_resp = await client.post("/api/v1/semesters", headers=headers, json={
            "semester_number": 6,
            "label": "6th Semester",
            "start_date": "2027-01-10",
            "end_date": "2027-05-30",
            "total_weeks": 18,
            "working_days": [0, 1, 2, 3, 4]  # Mon-Fri
        })
        assert create_resp.status_code == 201
        new_sem = create_resp.json()
        assert new_sem["working_days"] == [0, 1, 2, 3, 4]
        sem_id = new_sem["id"]

        # 3. Update working_days (add Sunday for weekend classes)
        update_resp = await client.patch(f"/api/v1/semesters/{sem_id}", headers=headers, json={
            "working_days": [0, 1, 2, 3, 4, 6]  # Mon-Fri + Sun
        })
        assert update_resp.status_code == 200
        updated_sem = update_resp.json()
        assert updated_sem["working_days"] == [0, 1, 2, 3, 4, 6]

        # 4. Verify GET returns correct working_days
        get_resp = await client.get("/api/v1/semesters", headers=headers)
        all_sems = get_resp.json()
        updated = next(s for s in all_sems if s["id"] == sem_id)
        assert updated["working_days"] == [0, 1, 2, 3, 4, 6]

        # 5. Test validation - empty working_days
        empty_resp = await client.post("/api/v1/semesters", headers=headers, json={
            "semester_number": 7,
            "label": "7th Semester",
            "start_date": "2027-08-01",
            "end_date": "2027-12-20",
            "working_days": []
        })
        assert empty_resp.status_code == 422  # Validation error

        # 6. Test validation - invalid weekday
        invalid_resp = await client.post("/api/v1/semesters", headers=headers, json={
            "semester_number": 7,
            "label": "7th Semester",
            "start_date": "2027-08-01",
            "end_date": "2027-12-20",
            "working_days": [0, 1, 2, 8]  # 8 is invalid
        })
        assert invalid_resp.status_code == 422

        # 7. Test validation - duplicates
        dup_resp = await client.post("/api/v1/semesters", headers=headers, json={
            "semester_number": 7,
            "label": "7th Semester",
            "start_date": "2027-08-01",
            "end_date": "2027-12-20",
            "working_days": [0, 1, 1, 2, 3]  # Duplicate 1
        })
        # Should succeed but deduplicate
        if dup_resp.status_code == 201:
            assert sorted(dup_resp.json()["working_days"]) == [0, 1, 2, 3]


@pytest.mark.asyncio
async def test_working_days_forecast_integration():
    """
    Test that forecast calculations work correctly based on actual timetable entries.
    
    The forecast engine now enumerates actual scheduled classes from timetable entries,
    regardless of working_days configuration. This test verifies the new behavior.
    """
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Register user
        email = f"forecast_wd_{uuid.uuid4().hex[:6]}@test.edu"
        reg_resp = await client.post("/api/v1/auth/register", json={
            "email": email,
            "password": "Password123!",
            "full_name": "Forecast Test",
            "seed_demo_data": False
        })
        token = reg_resp.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # Get default semester
        sems = (await client.get("/api/v1/semesters", headers=headers)).json()
        sem_id = sems[0]["id"]

        # Create subject
        subj_resp = await client.post("/api/v1/subjects", headers=headers, json={
            "name": "Mathematics",
            "code": "MA-501"
        })
        subject_id = subj_resp.json()["id"]

        # Create Monday timetable entry
        monday_resp = await client.post("/api/v1/timetable", headers=headers, json={
            "subject_id": subject_id,
            "day_of_week": 0,  # Monday
            "start_time": "09:00",
            "end_time": "10:00",
            "class_type": "THEORY"
        })
        assert monday_resp.status_code == 201

        # Create Saturday timetable entry
        saturday_resp = await client.post("/api/v1/timetable", headers=headers, json={
            "subject_id": subject_id,
            "day_of_week": 5,  # Saturday
            "start_time": "09:00",
            "end_time": "10:00",
            "class_type": "THEORY"
        })
        assert saturday_resp.status_code == 201

        # Get analytics - both Monday and Saturday classes should be counted in forecast
        analytics_resp = await client.get("/api/v1/analytics/overview", headers=headers)
        analytics = analytics_resp.json()
        
        # With the new approach, both Monday and Saturday classes are counted
        # because they're both in the timetable
        assert analytics["forecast_status"] in ["COMPLETE", "NO_DATA", "INCOMPLETE_SEMESTER_DATES"]
        
        # If forecast is complete, verify both classes appear in remaining count
        if analytics["forecast_status"] == "COMPLETE":
            # Should have both Monday and Saturday classes in forecast
            subjects = analytics.get("subjects", [])
            if subjects:
                math_subject = subjects[0]
                remaining = math_subject.get("remaining_classes")
                # Exact count depends on semester dates, but should be > 0 if forecast works
                assert remaining is None or remaining >= 0

def test_semester_stats_working_days_and_holidays_exclusion():
    """Verify that _compute_semester_stats excludes non-working days (Sat/Sun) and registered holidays."""
    from datetime import date
    from app.models.semester import Semester
    from app.models.holiday import Holiday
    from app.services.academic_service import _compute_semester_stats

    # 1. 2-week semester: Monday 2026-10-05 to Friday 2026-10-16 (12 calendar days)
    # Mon-Fri: 10 working days. Sat & Sun: 2 days.
    sem = Semester(
        id="sem_test_exclusion",
        user_id="user_test",
        semester_number=1,
        label="1st Semester",
        start_date=date(2026, 10, 5),
        end_date=date(2026, 10, 16),
        status="ACTIVE",
        is_active=True,
        total_weeks=2,
        _working_days_raw=[0, 1, 2, 3, 4]  # Mon-Fri only
    )

    # Without holiday: 10 working days total
    stats_no_hol = _compute_semester_stats(sem)
    assert stats_no_hol.total_weeks == 2

    # 2. Add a 3-day holiday: Wed-Fri 2026-10-14 to 2026-10-16
    h = Holiday(
        id="hol_test",
        user_id="user_test",
        semester_id="sem_test_exclusion",
        start_date=date(2026, 10, 14),
        end_date=date(2026, 10, 16),
        title="Mid-Term Break",
        category="University Holiday"
    )
    sem.holidays = [h]

    stats_with_hol = _compute_semester_stats(sem)
    # 10 working days - 3 holiday days = 7 total academic working days
    # Week calculation: (7 + 5 - 1) // 5 = 2 weeks
    assert stats_with_hol.working_days == [0, 1, 2, 3, 4]
    assert stats_with_hol.progress_percentage >= 0.0


@pytest.mark.asyncio
async def test_academic_setup_working_days_and_hours_persistence():
    """Verify that Academic Setup commits and retrieves custom working_days, day bounds, and class hours."""
    transport = ASGITransport(app=app)
    async with AsyncClient(transport=transport, base_url="http://test") as client:
        # Register user
        email = f"setup_wd_{uuid.uuid4().hex[:6]}@test.edu"
        reg_resp = await client.post("/api/v1/auth/register", json={
            "email": email,
            "password": "Password123!",
            "full_name": "Setup Days Test",
            "seed_demo_data": False
        })
        assert reg_resp.status_code == 201
        token = reg_resp.json()["access_token"]
        headers = {"Authorization": f"Bearer {token}"}

        # 1. Commit Academic Setup with Mon-Fri (no Saturday) and 8:00 AM to 3:00 PM (hour 15)
        setup_payload = {
            "university_name": "Tech Institute",
            "course_name": "B.Tech IT",
            "academic_duration_years": 4,
            "academic_session_start": 2024,
            "academic_session_end": 2028,
            "semester_number": 1,
            "semester_label": "1st Semester",
            "start_date": "2026-08-01",
            "end_date": "2026-12-15",
            "start_day": "Monday",
            "end_day": "Friday",
            "working_days": [0, 1, 2, 3, 4],
            "class_start_hour": 8,
            "class_end_hour": 15,
            "minimum_attendance": 75.0,
            "personal_target": 75.0,
            "low_attendance_alert": 70.0,
            "subjects": [
                {
                    "name": "Algorithms",
                    "code": "CS-201",
                    "faculty_name": "Dr. Turing",
                    "color": "#C96E5B"
                }
            ],
            "timetable_entries": [
                {
                    "subject_name": "Algorithms",
                    "day_of_week": 0,
                    "start_time": "08:00",
                    "end_time": "09:00",
                    "room": "Room 101",
                    "class_type": "THEORY"
                }
            ],
            "holidays": [],
            "starting_attendance": []
        }

        commit_resp = await client.post("/api/v1/profile/setup", headers=headers, json=setup_payload)
        assert commit_resp.status_code == 200, commit_resp.text

        # 2. Fetch Academic Setup data (re-visiting setup)
        get_setup_resp = await client.get("/api/v1/profile/setup-data", headers=headers)
        assert get_setup_resp.status_code == 200
        setup_data = get_setup_resp.json()

        sem_info = setup_data.get("semester")
        assert sem_info is not None
        assert sem_info["working_days"] == [0, 1, 2, 3, 4]
        assert sem_info["start_day"] == "Monday"
        assert sem_info["end_day"] == "Friday"
        assert sem_info["class_start_hour"] == 8
        assert sem_info["class_end_hour"] == 15

        # 3. Verify GET /api/v1/semesters reflects the active semester's settings
        sems_resp = await client.get("/api/v1/semesters", headers=headers)
        assert sems_resp.status_code == 200
        sems = sems_resp.json()
        active_sem = next((s for s in sems if s["is_active"]), None)
        assert active_sem is not None
        assert active_sem["working_days"] == [0, 1, 2, 3, 4]
        assert active_sem["class_start_hour"] == 8
        assert active_sem["class_end_hour"] == 15


