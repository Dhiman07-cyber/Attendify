import uuid
from typing import List, Optional
from datetime import date
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select
from fastapi import HTTPException, status

from app.models.subject import Subject
from app.models.timetable import TimetableEntry
from app.models.holiday import Holiday
from app.models.semester import Semester
from app.schemas.import_schema import (
    RoutineDraftEntry, RoutineReviewRequest,
    HolidayDraftEntry, HolidayReviewRequest,
    ImportParseResponse
)
from app.services.academic_service import get_active_semester

# Importer Boundary / Strategy Interface
class DocumentParserInterface:
    async def parse_routine(self, filename: str, content: bytes) -> List[RoutineDraftEntry]:
        raise NotImplementedError

    async def parse_holidays(self, filename: str, content: bytes) -> List[HolidayDraftEntry]:
        raise NotImplementedError

import csv
import io
import re
from datetime import date, datetime

class RuleBasedDocumentParser(DocumentParserInterface):
    """
    Robust rule-based parser that parses CSV/structured text files into clean drafts
    for user review before committing to the database.
    """
    async def parse_routine(self, filename: str, content: bytes) -> List[RoutineDraftEntry]:
        results: List[RoutineDraftEntry] = []
        try:
            text = content.decode('utf-8', errors='ignore')
            reader = csv.reader(io.StringIO(text))
            for row in reader:
                if not row or len(row) < 2:
                    continue
                if any(h in row[0].lower() for h in ["subject", "name", "course", "title"]):
                    continue
                name = row[0].strip()
                if not name:
                    continue
                code = row[1].strip() if len(row) > 1 and row[1].strip() else None
                faculty = row[2].strip() if len(row) > 2 and row[2].strip() else None
                day_val = 0
                if len(row) > 3:
                    try:
                        day_val = int(row[3]) % 7
                    except ValueError:
                        day_val = 0
                start_t = row[4].strip() if len(row) > 4 and row[4].strip() else "09:00"
                end_t = row[5].strip() if len(row) > 5 and row[5].strip() else "10:00"
                room = row[6].strip() if len(row) > 6 and row[6].strip() else None
                results.append(RoutineDraftEntry(
                    subject_name=name,
                    subject_code=code,
                    faculty_name=faculty,
                    day_of_week=day_val,
                    start_time=start_t,
                    end_time=end_t,
                    room=room,
                    confidence=0.92
                ))
        except Exception:
            pass
        return results

    async def parse_holidays(self, filename: str, content: bytes) -> List[HolidayDraftEntry]:
        results: List[HolidayDraftEntry] = []
        try:
            text = content.decode('utf-8', errors='ignore')
            reader = csv.reader(io.StringIO(text))
            for row in reader:
                if not row or len(row) < 3:
                    continue
                if any(h in row[0].lower() for h in ["title", "holiday", "name", "event"]):
                    continue
                title = row[0].strip()
                if not title:
                    continue
                try:
                    s_date = datetime.strptime(row[1].strip(), "%Y-%m-%d").date()
                    e_date = datetime.strptime(row[2].strip(), "%Y-%m-%d").date()
                except Exception:
                    continue
                cat = row[3].strip() if len(row) > 3 and row[3].strip() else "University Holiday"
                notes = row[4].strip() if len(row) > 4 and row[4].strip() else None
                results.append(HolidayDraftEntry(
                    title=title,
                    start_date=s_date,
                    end_date=e_date,
                    category=cat,
                    notes=notes,
                    confidence=0.95
                ))
        except Exception:
            pass
        return results

parser_instance = RuleBasedDocumentParser()

async def parse_routine_file(filename: str, content: bytes) -> ImportParseResponse:
    drafts = await parser_instance.parse_routine(filename, content)
    warnings = (
        ["Please review timings and room numbers before confirming."]
        if drafts else
        ["No entries could be parsed. Expected format: Subject,Code,Faculty,Day(0-6),StartTime,EndTime,Room"]
    )
    return ImportParseResponse(
        file_id=uuid.uuid4().hex,
        file_name=filename,
        source_type="routine",
        parser_used="RuleBasedDocumentParser",
        draft_routine=drafts,
        warning_notes=warnings
    )

async def parse_holiday_file(filename: str, content: bytes) -> ImportParseResponse:
    drafts = await parser_instance.parse_holidays(filename, content)
    warnings = (
        ["Verify multi-day holiday start and end dates before confirming."]
        if drafts else
        ["No entries could be parsed. Expected format: Title,StartDate(YYYY-MM-DD),EndDate(YYYY-MM-DD),Category,Notes"]
    )
    return ImportParseResponse(
        file_id=uuid.uuid4().hex,
        file_name=filename,
        source_type="holiday",
        parser_used="RuleBasedDocumentParser",
        draft_holidays=drafts,
        warning_notes=warnings
    )

async def confirm_routine_draft(
    db: AsyncSession,
    user_id: str,
    payload: RoutineReviewRequest
) -> dict:
    # Verify semester ownership
    sem_stmt = select(Semester).where(Semester.id == payload.semester_id, Semester.user_id == user_id)
    sem_res = await db.execute(sem_stmt)
    if not sem_res.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Semester not found.")

    created_entries = 0
    # Process each reviewed entry
    for entry in payload.entries:
        # Check if subject exists in semester
        subj_stmt = select(Subject).where(
            Subject.semester_id == payload.semester_id,
            Subject.name == entry.subject_name.strip()
        )
        res = await db.execute(subj_stmt)
        subj = res.scalar_one_or_none()
        if not subj:
            subj = Subject(
                semester_id=payload.semester_id,
                name=entry.subject_name.strip(),
                code=entry.subject_code,
                faculty_name=entry.faculty_name,
                is_active=True
            )
            db.add(subj)
            await db.flush()

        sub_name_lower = entry.subject_name.lower()
        ct = "LAB" if ("lab" in sub_name_lower or "practical" in sub_name_lower) else "THEORY"
        tt = TimetableEntry(
            semester_id=payload.semester_id,
            subject_id=subj.id,
            day_of_week=entry.day_of_week,
            start_time=entry.start_time,
            end_time=entry.end_time,
            faculty_name=entry.faculty_name or subj.faculty_name,
            room=entry.room,
            class_type=ct
        )
        db.add(tt)
        created_entries += 1

    await db.commit()
    return {"status": "success", "imported_count": created_entries, "message": f"Successfully imported {created_entries} routine entries."}

async def confirm_holiday_draft(
    db: AsyncSession,
    user_id: str,
    payload: HolidayReviewRequest
) -> dict:
    # Verify semester ownership
    sem_stmt = select(Semester).where(Semester.id == payload.semester_id, Semester.user_id == user_id)
    sem_res = await db.execute(sem_stmt)
    if not sem_res.scalar_one_or_none():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Semester not found.")

    created_count = 0
    for h in payload.holidays:
        hol = Holiday(
            user_id=user_id,
            semester_id=payload.semester_id,
            title=h.title.strip(),
            start_date=h.start_date,
            end_date=h.end_date,
            category=h.category,
            notes=h.notes,
            source="imported"
        )
        db.add(hol)
        created_count += 1

    await db.commit()
    return {"status": "success", "imported_count": created_count, "message": f"Successfully imported {created_count} holidays."}
