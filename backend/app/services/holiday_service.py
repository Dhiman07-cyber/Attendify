from datetime import date
from typing import List, Optional
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select, or_
from fastapi import HTTPException, status

from app.models.holiday import Holiday
from app.schemas.holiday import HolidayCreate, HolidayUpdate, HolidayOut
from app.services.academic_service import get_active_semester

def _compute_relative_label(start_date: date, end_date: date, today: date) -> tuple[bool, str]:
    if end_date < today:
        return False, "Past"
    diff = (start_date - today).days
    if diff == 0:
        return True, "Today"
    elif diff == 1:
        return True, "Tomorrow"
    elif diff < 0:
        return True, "Ongoing"
    elif diff < 7:
        return True, f"In {diff} days"
    elif diff < 30:
        weeks = diff // 7
        return True, f"In {diff} days"
    else:
        return True, f"In {diff} days"

def _map_holiday_out(h: Holiday, today: date) -> HolidayOut:
    duration = (h.end_date - h.start_date).days + 1
    is_up, rel_label = _compute_relative_label(h.start_date, h.end_date, today)
    return HolidayOut(
        id=h.id,
        user_id=h.user_id,
        semester_id=h.semester_id,
        title=h.title,
        start_date=h.start_date,
        end_date=h.end_date,
        category=h.category,
        notes=h.notes,
        source=h.source,
        duration_days=duration,
        is_upcoming=is_up,
        relative_time_label=rel_label
    )

async def list_holidays(
    db: AsyncSession,
    user_id: str,
    semester_id: Optional[str] = None,
    filter_type: Optional[str] = None # "upcoming", "past", "all"
) -> List[HolidayOut]:
    today = date.today()
    query = select(Holiday).where(Holiday.user_id == user_id)
    if semester_id:
        query = query.where(or_(Holiday.semester_id == semester_id, Holiday.semester_id == None))

    query = query.order_by(Holiday.start_date.asc())
    res = await db.execute(query)
    holidays = res.scalars().all()

    mapped = [_map_holiday_out(h, today) for h in holidays]
    if filter_type == "upcoming":
        return [h for h in mapped if h.is_upcoming]
    elif filter_type == "past":
        return [h for h in mapped if not h.is_upcoming]
    return mapped

async def get_next_upcoming_holiday(db: AsyncSession, user_id: str) -> Optional[HolidayOut]:
    today = date.today()
    stmt = (
        select(Holiday)
        .where(Holiday.user_id == user_id, Holiday.end_date >= today)
        .order_by(Holiday.start_date.asc())
    )
    res = await db.execute(stmt)
    first_hol = res.scalars().first()
    if first_hol:
        return _map_holiday_out(first_hol, today)
    return None

async def create_holiday(db: AsyncSession, user_id: str, data: HolidayCreate) -> HolidayOut:
    today = date.today()
    if data.end_date < data.start_date:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="End date cannot be earlier than start date.")

    sem_id = data.semester_id
    if not sem_id:
        active_sem = await get_active_semester(db, user_id)
        if active_sem:
            sem_id = active_sem.id

    hol = Holiday(
        user_id=user_id,
        semester_id=sem_id,
        start_date=data.start_date,
        end_date=data.end_date,
        title=data.title.strip(),
        category=data.category or "University Holiday",
        notes=data.notes,
        source="manual"
    )
    db.add(hol)
    await db.commit()
    await db.refresh(hol)
    return _map_holiday_out(hol, today)

async def update_holiday(db: AsyncSession, user_id: str, holiday_id: str, data: HolidayUpdate) -> HolidayOut:
    today = date.today()
    stmt = select(Holiday).where(Holiday.id == holiday_id, Holiday.user_id == user_id)
    res = await db.execute(stmt)
    hol = res.scalar_one_or_none()
    if not hol:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Holiday not found.")

    for field, val in data.model_dump(exclude_unset=True).items():
        if hasattr(hol, field) and val is not None:
            setattr(hol, field, val)

    if hol.end_date < hol.start_date:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="End date cannot be earlier than start date.")

    await db.commit()
    await db.refresh(hol)
    return _map_holiday_out(hol, today)

async def delete_holiday(db: AsyncSession, user_id: str, holiday_id: str) -> dict:
    stmt = select(Holiday).where(Holiday.id == holiday_id, Holiday.user_id == user_id)
    res = await db.execute(stmt)
    hol = res.scalar_one_or_none()
    if not hol:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Holiday not found.")
    await db.delete(hol)
    await db.commit()
    return {"status": "deleted", "message": "Holiday removed."}
