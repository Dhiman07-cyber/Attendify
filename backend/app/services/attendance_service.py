from datetime import date, datetime, time, timezone, timedelta
from typing import List, Optional, Tuple, Dict, Any
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, and_, or_
from fastapi import HTTPException, status

from app.models.session import ClassSession
from app.models.subject import Subject
from app.models.semester import Semester
from app.models.attendance import AttendanceRecord
from app.models.timetable import TimetableEntry
from app.models.holiday import Holiday
from app.models.profile import AcademicProfile
from app.schemas.session import ClassSessionOut, ExtraClassCreate
from app.schemas.attendance import (
    AttendanceBulkMarkRequest, AttendanceCorrectionRequest,
    AttendanceSaveResult
)
from app.schemas.today import TodayOverviewOut
from app.calculations.attendance_engine import calculate_overall_metrics
from app.services.academic_service import get_active_semester

def compute_time_status(
    start_str: Optional[str],
    end_str: Optional[str],
    reference_time: Optional[time] = None,
    target_date: Optional[date] = None,
    reference_date: Optional[date] = None
) -> Optional[str]:
    if not start_str or not end_str:
        return None
    try:
        sh, sm = map(int, start_str.split(":")[:2])
        eh, em = map(int, end_str.split(":")[:2])
        start_t = time(sh, sm)
        end_t = time(eh, em)
    except Exception:
        return None

    ref_d = reference_date or date.today()
    if target_date is not None:
        if target_date > ref_d:
            return "Upcoming"
        elif target_date < ref_d:
            return "Done"

    ref = reference_time or datetime.now().time()
    if ref >= end_t:
        return "Done"
    elif start_t <= ref < end_t:
        return "Now"
    else:
        return "Upcoming"


def validate_attendance_edit_window(target_date: date) -> None:
    today = date.today()
    if target_date > today:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Cannot mark attendance for future dates."
        )
    if target_date < today - timedelta(days=2):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Attendance editing window has expired for this date (only today and the previous 2 days are editable)."
        )

async def get_today_sessions(
    db: AsyncSession,
    user_id: str,
    target_date: Optional[date] = None,
    *,
    active_sem: Optional[Semester] = None,
    precomputed_overall_pct: Optional[float] = None,
    has_precomputed_overall: bool = False,
) -> TodayOverviewOut:
    if not target_date:
        target_date = date.today()

    if active_sem is None:
        active_sem = await get_active_semester(db, user_id)

    # 1. Check if registered holiday covers this date
    hol_stmt = select(Holiday).where(
        Holiday.user_id == user_id,
        Holiday.start_date <= target_date,
        Holiday.end_date >= target_date
    )
    hol_res = await db.execute(hol_stmt)
    holiday = hol_res.scalar_one_or_none()

    # 2. Look up recurring timetable entries for target weekday
    day_of_week = target_date.weekday()
    tt_stmt = (
        select(TimetableEntry, Subject)
        .join(Subject, TimetableEntry.subject_id == Subject.id)
        .where(
            TimetableEntry.semester_id == active_sem.id,
            TimetableEntry.day_of_week == day_of_week,
            Subject.is_active == True
        )
        .order_by(TimetableEntry.start_time.asc())
    )
    tt_res = await db.execute(tt_stmt)
    timetable_rows = tt_res.all()

    # 3. Look up concrete sessions already existing in DB for target_date
    concrete_stmt = (
        select(ClassSession, Subject, AttendanceRecord)
        .join(Subject, ClassSession.subject_id == Subject.id)
        .outerjoin(AttendanceRecord, and_(
            AttendanceRecord.class_session_id == ClassSession.id,
            AttendanceRecord.user_id == user_id
        ))
        .where(
            ClassSession.semester_id == active_sem.id,
            ClassSession.date == target_date
        )
    )
    concrete_res = await db.execute(concrete_stmt)
    concrete_rows = concrete_res.all()

    # Map concrete sessions by (subject_id, start_time) and by id
    concrete_by_slot: Dict[Tuple[str, Optional[str]], Tuple[ClassSession, Subject, Optional[AttendanceRecord]]] = {}
    concrete_ids_used = set()

    for cs, subj, att in concrete_rows:
        concrete_by_slot[(cs.subject_id, cs.start_time)] = (cs, subj, att)

    sessions_out: List[ClassSessionOut] = []
    marked_count = 0
    pending_count = 0
    not_held_count = 0
    ref_time = datetime.now().time()

    # Build synthesized slots for each recurring timetable entry
    for tt, subj in timetable_rows:
        slot_key = (subj.id, tt.start_time)
        if slot_key in concrete_by_slot:
            cs, s, att = concrete_by_slot[slot_key]
            concrete_ids_used.add(cs.id)
            att_status = att.status if att else None
            att_id = att.id if att else None

            if att_status == "NOT_HELD" or cs.session_status in ["NOT_HELD", "HOLIDAY", "CANCELLED"]:
                not_held_count += 1
            elif att_status in ["ATTENDED", "ABSENT"]:
                marked_count += 1
            else:
                pending_count += 1

            time_st = compute_time_status(cs.start_time, cs.end_time, ref_time, target_date=target_date)
            sessions_out.append(ClassSessionOut(
                id=cs.id,
                timetable_entry_id=tt.id,
                semester_id=cs.semester_id,
                subject_id=cs.subject_id,
                subject_name=s.name,
                subject_code=s.code,
                subject_color=s.color,
                subject_icon=s.icon,
                date=cs.date,
                start_time=cs.start_time,
                end_time=cs.end_time,
                faculty_name=cs.faculty_name or s.faculty_name,
                room=cs.room,
                session_status=cs.session_status,
                is_extra=cs.is_extra,
                time_status=time_st,
                attendance_status=att_status,
                attendance_id=att_id,
                class_type=cs.class_type or (tt.class_type if tt else None) or "THEORY"
            ))
        else:
            # Virtual session slot (Pure Read - NO DB writes)
            sess_status = "HOLIDAY" if holiday else "SCHEDULED"
            if sess_status == "HOLIDAY":
                not_held_count += 1
            else:
                pending_count += 1

            time_st = compute_time_status(tt.start_time, tt.end_time, ref_time, target_date=target_date)
            virtual_id = f"virtual:{tt.id}:{target_date.isoformat()}"
            sessions_out.append(ClassSessionOut(
                id=virtual_id,
                timetable_entry_id=tt.id,
                semester_id=active_sem.id,
                subject_id=subj.id,
                subject_name=subj.name,
                subject_code=subj.code,
                subject_color=subj.color,
                subject_icon=subj.icon,
                date=target_date,
                start_time=tt.start_time,
                end_time=tt.end_time,
                faculty_name=tt.faculty_name or subj.faculty_name,
                room=tt.room,
                session_status=sess_status,
                is_extra=False,
                time_status=time_st,
                attendance_status=None,
                attendance_id=None,
                class_type=tt.class_type or "THEORY"
            ))

    # Add any extra classes or concrete sessions not matched to timetable entries
    for cs, subj, att in concrete_rows:
        if cs.id not in concrete_ids_used:
            att_status = att.status if att else None
            att_id = att.id if att else None

            if att_status == "NOT_HELD" or cs.session_status in ["NOT_HELD", "HOLIDAY", "CANCELLED"]:
                not_held_count += 1
            elif att_status in ["ATTENDED", "ABSENT"]:
                marked_count += 1
            else:
                pending_count += 1

            time_st = compute_time_status(cs.start_time, cs.end_time, ref_time, target_date=target_date)
            sessions_out.append(ClassSessionOut(
                id=cs.id,
                timetable_entry_id=None,
                semester_id=cs.semester_id,
                subject_id=cs.subject_id,
                subject_name=subj.name,
                subject_code=subj.code,
                subject_color=subj.color,
                subject_icon=subj.icon,
                date=cs.date,
                start_time=cs.start_time,
                end_time=cs.end_time,
                faculty_name=cs.faculty_name or subj.faculty_name,
                room=cs.room,
                session_status=cs.session_status,
                is_extra=cs.is_extra,
                time_status=time_st,
                attendance_status=att_status,
                attendance_id=att_id,
                class_type=cs.class_type or "UNSPECIFIED"
            ))

    # Sort timed first, then untimed
    sessions_out.sort(key=lambda s: (0 if s.start_time else 1, s.start_time or "99:99"))

    if has_precomputed_overall:
        overall_pct = precomputed_overall_pct
    else:
        from app.services.analytics_service import get_semester_overall_metrics
        overall_res = await get_semester_overall_metrics(db, user_id, active_sem.id)
        overall_pct = overall_res.get("overall_percentage")

    date_str = target_date.strftime("%A, %d %B %Y")

    return TodayOverviewOut(
        selected_date=target_date,
        selected_date_str=date_str,
        semester_label=active_sem.label,
        total_classes=len(sessions_out),
        marked_classes=marked_count,
        pending_classes=pending_count,
        not_held_classes=not_held_count,
        sessions=sessions_out,
        current_overall_percentage=overall_pct,
        projected_overall_percentage=overall_pct,
        projected_delta=0.0
    )

async def bulk_save_attendance(
    db: AsyncSession,
    user_id: str,
    payload: AttendanceBulkMarkRequest
) -> AttendanceSaveResult:
    items = payload.items or payload.records or []
    if not items:
        return AttendanceSaveResult(
            updated_count=0,
            message="No attendance items provided.",
            overall_percentage=None,
            projected_change=0.0
        )

    active_sem = await get_active_semester(db, user_id)
    now = datetime.now(timezone.utc)
    updated_count = 0

    # Determine default target date from payload or today
    bulk_date = payload.date or date.today()

    for item in items:
        item_date = item.date or bulk_date
        validate_attendance_edit_window(item_date)

        target_session_id = item.session_id

        # If virtual session or timetable entry reference, materialize concrete ClassSession
        if (target_session_id and target_session_id.startswith("virtual:")) or item.timetable_entry_id:
            tt_id = item.timetable_entry_id
            if not tt_id and target_session_id and target_session_id.startswith("virtual:"):
                parts = target_session_id.split(":")
                if len(parts) >= 2:
                    tt_id = parts[1]

            if not tt_id:
                continue

            # Look up timetable entry and verify ownership
            tt_stmt = (
                select(TimetableEntry, Subject)
                .join(Subject, TimetableEntry.subject_id == Subject.id)
                .join(Semester, TimetableEntry.semester_id == Semester.id)
                .where(
                    TimetableEntry.id == tt_id,
                    Semester.user_id == user_id,
                    Semester.id == active_sem.id
                )
            )
            tt_res = await db.execute(tt_stmt)
            tt_row = tt_res.first()
            if not tt_row:
                continue
            tt_obj, subj_obj = tt_row

            # Check if concrete session already materialized
            existing_sess_stmt = select(ClassSession).where(
                ClassSession.semester_id == active_sem.id,
                ClassSession.subject_id == subj_obj.id,
                ClassSession.date == item_date,
                or_(
                    ClassSession.timetable_entry_id == tt_id,
                    ClassSession.start_time == tt_obj.start_time
                )
            )
            existing_sess_res = await db.execute(existing_sess_stmt)
            existing_sess = existing_sess_res.scalar_one_or_none()

            if existing_sess:
                target_session_id = existing_sess.id
            else:
                new_sess = ClassSession(
                    semester_id=active_sem.id,
                    subject_id=subj_obj.id,
                    date=item_date,
                    timetable_entry_id=tt_obj.id,
                    start_time=tt_obj.start_time,
                    end_time=tt_obj.end_time,
                    faculty_name=tt_obj.faculty_name or subj_obj.faculty_name,
                    room=tt_obj.room,
                    session_status="SCHEDULED",
                    is_extra=False,
                    class_type=tt_obj.class_type  # Snapshot class_type from timetable entry
                )
                db.add(new_sess)
                await db.flush()
                target_session_id = new_sess.id
        else:
            # Concrete session ID provided
            if not target_session_id:
                continue
            sess_stmt = (
                select(ClassSession)
                .join(Semester, ClassSession.semester_id == Semester.id)
                .where(
                    ClassSession.id == target_session_id,
                    Semester.user_id == user_id,
                    Semester.id == active_sem.id
                )
            )
            sess_res = await db.execute(sess_stmt)
            sess = sess_res.scalar_one_or_none()
            if not sess:
                continue
            validate_attendance_edit_window(sess.date)

        # Upsert AttendanceRecord
        rec_stmt = select(AttendanceRecord).where(
            AttendanceRecord.class_session_id == target_session_id,
            AttendanceRecord.user_id == user_id
        )
        rec_res = await db.execute(rec_stmt)
        rec = rec_res.scalar_one_or_none()

        if rec:
            if rec.status != item.status:
                rec.status = item.status
                rec.updated_at = now
                updated_count += 1
        else:
            rec = AttendanceRecord(
                class_session_id=target_session_id,
                user_id=user_id,
                status=item.status,
                marked_at=now,
                updated_at=now,
                source="daily_bulk"
            )
            db.add(rec)
            updated_count += 1

    await db.commit()

    from app.services.analytics_service import get_semester_overall_metrics
    overall_res = await get_semester_overall_metrics(db, user_id, active_sem.id)

    return AttendanceSaveResult(
        updated_count=updated_count,
        message=f"Successfully saved {updated_count} attendance records.",
        overall_percentage=overall_res.get("overall_percentage"),
        projected_change=0.0
    )

async def correct_attendance_record(
    db: AsyncSession,
    user_id: str,
    record_id: str,
    payload: AttendanceCorrectionRequest
) -> AttendanceSaveResult:
    stmt = (
        select(AttendanceRecord, ClassSession)
        .join(ClassSession, AttendanceRecord.class_session_id == ClassSession.id)
        .join(Semester, ClassSession.semester_id == Semester.id)
        .where(
            AttendanceRecord.id == record_id,
            AttendanceRecord.user_id == user_id,
            Semester.user_id == user_id
        )
    )
    result = await db.execute(stmt)
    row = result.first()
    if not row:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Attendance record not found.")

    rec, cs = row
    validate_attendance_edit_window(cs.date)

    original = rec.status
    now = datetime.now(timezone.utc)

    if original != payload.new_status:
        rec.status = payload.new_status
        rec.updated_at = now
        await db.commit()

    active_sem = await get_active_semester(db, user_id)
    from app.services.analytics_service import get_semester_overall_metrics
    overall_res = await get_semester_overall_metrics(db, user_id, active_sem.id)

    return AttendanceSaveResult(
        updated_count=1,
        message=f"Attendance corrected from {original} to {payload.new_status}.",
        overall_percentage=overall_res.get("overall_percentage"),
        projected_change=0.0
    )

async def add_extra_class_session(
    db: AsyncSession,
    user_id: str,
    data: ExtraClassCreate
) -> ClassSessionOut:
    subj_stmt = (
        select(Subject)
        .join(Semester, Subject.semester_id == Semester.id)
        .where(Subject.id == data.subject_id, Semester.user_id == user_id)
    )
    subj_res = await db.execute(subj_stmt)
    subj = subj_res.scalar_one_or_none()
    if not subj:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Subject not found.")

    target_date = data.date or date.today()

    sess = ClassSession(
        semester_id=subj.semester_id,
        subject_id=subj.id,
        date=target_date,
        start_time=data.start_time,
        end_time=data.end_time,
        faculty_name=data.faculty_name or subj.faculty_name,
        room=data.room,
        session_status="SCHEDULED",
        is_extra=True
    )
    db.add(sess)
    await db.commit()
    await db.refresh(sess)

    time_st = compute_time_status(sess.start_time, sess.end_time)

    return ClassSessionOut(
        id=sess.id,
        timetable_entry_id=None,
        semester_id=sess.semester_id,
        subject_id=sess.subject_id,
        subject_name=subj.name,
        subject_code=subj.code,
        subject_color=subj.color,
        subject_icon=subj.icon,
        date=sess.date,
        start_time=sess.start_time,
        end_time=sess.end_time,
        faculty_name=sess.faculty_name,
        room=sess.room,
        session_status=sess.session_status,
        is_extra=True,
        time_status=time_st,
        attendance_status=None,
        attendance_id=None
    )
