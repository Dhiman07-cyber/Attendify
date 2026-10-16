from typing import List, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from fastapi import HTTPException, status

from datetime import date, timedelta
from app.models.timetable import TimetableEntry
from app.models.subject import Subject
from app.models.semester import Semester
from app.models.session import ClassSession
from app.models.attendance import AttendanceRecord
from app.models.holiday import Holiday
from app.schemas.timetable import (
    TimetableEntryCreate,
    TimetableEntryUpdate,
    TimetableEntryOut,
    WeeklyRoutineStatusOut,
    WeeklyDayStatusOut,
    WeeklySlotStatusOut,
)
from app.services.academic_service import get_active_semester

DAYS_MAP = {0: "Monday", 1: "Tuesday", 2: "Wednesday", 3: "Thursday", 4: "Friday", 5: "Saturday", 6: "Sunday"}

def _map_entry_out(e: TimetableEntry, s: Subject) -> TimetableEntryOut:
    return TimetableEntryOut(
        id=e.id,
        semester_id=e.semester_id,
        subject_id=e.subject_id,
        subject_name=s.name if s else None,
        subject_color=s.color if s else None,
        subject_icon=s.icon if s else None,
        day_of_week=e.day_of_week,
        day_name=DAYS_MAP.get(e.day_of_week) if e.day_of_week is not None else None,
        start_time=e.start_time,
        end_time=e.end_time,
        faculty_name=e.faculty_name or (s.faculty_name if s else None),
        room=e.room,
        effective_from=e.effective_from,
        effective_to=e.effective_to
    )

async def list_timetable(db: AsyncSession, user_id: str, semester_id: Optional[str] = None) -> List[TimetableEntryOut]:
    if not semester_id:
        sem = await get_active_semester(db, user_id)
        semester_id = sem.id

    stmt = (
        select(TimetableEntry, Subject)
        .join(Subject, TimetableEntry.subject_id == Subject.id)
        .where(TimetableEntry.semester_id == semester_id)
        .order_by(TimetableEntry.day_of_week.asc(), TimetableEntry.start_time.asc())
    )
    result = await db.execute(stmt)
    rows = result.all()
    return [_map_entry_out(e, s) for e, s in rows]

async def create_timetable_entry(db: AsyncSession, user_id: str, data: TimetableEntryCreate) -> TimetableEntryOut:
    subj_stmt = (
        select(Subject)
        .join(Semester, Subject.semester_id == Semester.id)
        .where(Subject.id == data.subject_id, Semester.user_id == user_id)
    )
    subj_res = await db.execute(subj_stmt)
    subj = subj_res.scalar_one_or_none()
    if not subj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Subject not found.")

    raw_type = (data.class_type or "").strip().upper()
    if "LAB" in raw_type or "PRACTICAL" in raw_type:
        ct = "LAB"
    elif "THEORY" in raw_type:
        ct = "THEORY"
    elif "OTHER" in raw_type or "UNSPECIFIED" in raw_type:
        ct = "UNSPECIFIED"
    elif data.class_type:
        ct = "UNSPECIFIED"
    else:
        ct = "LAB" if ("lab" in subj.name.lower() or "practical" in subj.name.lower()) else "THEORY"

    entry = TimetableEntry(
        semester_id=subj.semester_id,
        subject_id=data.subject_id,
        day_of_week=data.day_of_week,
        start_time=data.start_time,
        end_time=data.end_time,
        faculty_name=data.faculty_name or subj.faculty_name,
        room=data.room,
        effective_from=data.effective_from,
        effective_to=data.effective_to,
        class_type=ct
    )
    db.add(entry)
    await db.commit()
    await db.refresh(entry)
    return _map_entry_out(entry, subj)

async def update_timetable_entry(db: AsyncSession, user_id: str, entry_id: str, data: TimetableEntryUpdate) -> TimetableEntryOut:
    stmt = (
        select(TimetableEntry, Subject)
        .join(Subject, TimetableEntry.subject_id == Subject.id)
        .join(Semester, TimetableEntry.semester_id == Semester.id)
        .where(TimetableEntry.id == entry_id, Semester.user_id == user_id)
    )
    result = await db.execute(stmt)
    row = result.first()
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Timetable entry not found.")
    entry, subj = row

    for field, val in data.model_dump(exclude_unset=True).items():
        if hasattr(entry, field):
            setattr(entry, field, val)

    await db.commit()
    await db.refresh(entry)
    return _map_entry_out(entry, subj)

async def delete_timetable_entry(db: AsyncSession, user_id: str, entry_id: str) -> dict:
    stmt = (
        select(TimetableEntry)
        .join(Semester, TimetableEntry.semester_id == Semester.id)
        .where(TimetableEntry.id == entry_id, Semester.user_id == user_id)
    )
    result = await db.execute(stmt)
    entry = result.scalar_one_or_none()
    if not entry:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Timetable entry not found.")
    await db.delete(entry)
    await db.commit()
    return {"status": "deleted", "message": "Timetable entry removed."}

async def list_weekly_status(
    db: AsyncSession,
    user_id: str,
    semester_id: Optional[str] = None,
    week_offset: int = 0
) -> WeeklyRoutineStatusOut:
    if not semester_id:
        sem = await get_active_semester(db, user_id)
        semester_id = sem.id
        semester_label = sem.label
    else:
        sem_res = await db.execute(select(Semester).where(Semester.id == semester_id, Semester.user_id == user_id))
        sem = sem_res.scalar_one_or_none()
        if not sem:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Semester not found.")
        semester_label = sem.label

    today_date = date.today()
    # Calculate Monday of current week
    monday_current = today_date - timedelta(days=today_date.weekday())
    start_date = monday_current + timedelta(weeks=week_offset)
    end_date = start_date + timedelta(days=6)

    # 1. Fetch all timetable entries for this semester with subjects
    tt_stmt = (
        select(TimetableEntry, Subject)
        .join(Subject, TimetableEntry.subject_id == Subject.id)
        .where(TimetableEntry.semester_id == semester_id)
        .order_by(TimetableEntry.day_of_week.asc(), TimetableEntry.start_time.asc())
    )
    tt_rows = (await db.execute(tt_stmt)).all()

    # 2. Fetch holidays overlapping this week
    hol_stmt = (
        select(Holiday)
        .where(
            Holiday.semester_id == semester_id,
            Holiday.start_date <= end_date,
            Holiday.end_date >= start_date,
        )
    )
    holidays = (await db.execute(hol_stmt)).scalars().all()

    # 3. Fetch concrete sessions & attendance for this week
    sess_stmt = (
        select(ClassSession, AttendanceRecord)
        .outerjoin(AttendanceRecord, AttendanceRecord.class_session_id == ClassSession.id)
        .where(
            ClassSession.semester_id == semester_id,
            ClassSession.date >= start_date,
            ClassSession.date <= end_date,
        )
    )
    sess_rows = (await db.execute(sess_stmt)).all()

    # Index sessions by (date, timetable_entry_id) and (date, subject_id, start_time)
    sessions_by_entry: dict[tuple[date, str], tuple[ClassSession, Optional[AttendanceRecord]]] = {}
    for cs, att in sess_rows:
        if cs.timetable_entry_id:
            sessions_by_entry[(cs.date, cs.timetable_entry_id)] = (cs, att)
        # fallback indexing
        sessions_by_entry[(cs.date, f"{cs.subject_id}_{cs.start_time}")] = (cs, att)

    days_out: list[WeeklyDayStatusOut] = []

    for day_idx in range(7):
        cur_date = start_date + timedelta(days=day_idx)
        is_today = (cur_date == today_date)
        is_past = (cur_date < today_date)
        is_future = (cur_date > today_date)

        # Check holiday
        matching_hol = next((h for h in holidays if h.start_date <= cur_date <= h.end_date), None)
        is_holiday = matching_hol is not None
        holiday_title = matching_hol.title if matching_hol else None

        slots_for_day: list[WeeklySlotStatusOut] = []
        # Filter timetable entries for this weekday
        day_entries = [(e, s) for e, s in tt_rows if e.day_of_week == day_idx]

        for e, s in day_entries:
            # Check effective dates
            if e.effective_from and cur_date < e.effective_from:
                continue
            if e.effective_to and cur_date > e.effective_to:
                continue

            # Look up concrete session & attendance
            sess_match = sessions_by_entry.get((cur_date, e.id))
            if not sess_match and e.start_time:
                sess_match = sessions_by_entry.get((cur_date, f"{e.subject_id}_{e.start_time}"))

            sess_obj, att_obj = sess_match if sess_match else (None, None)

            att_status = att_obj.status if att_obj else None
            is_attended = (att_status == "ATTENDED")
            is_absent = (att_status == "ABSENT")
            is_not_held = (att_status == "NOT_HELD")
            is_unmarked = (att_status is None)

            slots_for_day.append(
                WeeklySlotStatusOut(
                    timetable_entry_id=e.id,
                    subject_id=s.id,
                    subject_name=s.name,
                    subject_code=s.code,
                    subject_color=s.color or "#C96E5B",
                    subject_icon=s.icon or "book",
                    day_of_week=day_idx,
                    date=cur_date,
                    start_time=e.start_time,
                    end_time=e.end_time,
                    room=e.room,
                    faculty_name=e.faculty_name or s.faculty_name,
                    class_type=sess_obj.class_type if sess_obj else (e.class_type or "UNSPECIFIED"),
                    session_id=sess_obj.id if sess_obj else None,
                    attendance_status=att_status,
                    is_attended=is_attended,
                    is_absent=is_absent,
                    is_not_held=is_not_held,
                    is_unmarked=is_unmarked,
                )
            )

        days_out.append(
            WeeklyDayStatusOut(
                day_of_week=day_idx,
                day_name=DAYS_MAP.get(day_idx, ""),
                date=cur_date,
                is_holiday=is_holiday,
                holiday_title=holiday_title,
                is_today=is_today,
                is_past=is_past,
                is_future=is_future,
                slots=slots_for_day,
            )
        )

    def _format_week_label(offset: int) -> str:
        if offset == 0:
            return "This week"
        elif offset == -1:
            return "Last week"
        elif offset == 1:
            return "Next week"
        elif offset < -1:
            return f"{abs(offset)} weeks ago"
        else:
            return f"In {offset} weeks"

    date_range_label = f"{start_date.strftime('%d %b %Y')} – {end_date.strftime('%d %b %Y')}"

    return WeeklyRoutineStatusOut(
        week_offset=week_offset,
        start_date=start_date,
        end_date=end_date,
        week_label=_format_week_label(week_offset),
        date_range_label=date_range_label,
        semester_id=semester_id,
        semester_label=semester_label,
        days=days_out,
    )

