import uuid
from datetime import date
from typing import List, Optional
from sqlalchemy import String, Integer, Boolean, Date, ForeignKey, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy import TypeDecorator
from sqlalchemy.orm import Mapped, mapped_column, relationship
from app.db.session import Base
import json

class JSONType(TypeDecorator):
    """Platform-independent JSON type.
    
    Uses JSONB for PostgreSQL, TEXT for SQLite.
    Handles serialization/deserialization automatically.
    """
    impl = Text
    cache_ok = True

    def load_dialect_impl(self, dialect):
        if dialect.name == 'postgresql':
            return dialect.type_descriptor(JSONB())
        else:
            return dialect.type_descriptor(Text())

    def process_bind_param(self, value, dialect):
        if value is None:
            return value
        if dialect.name == 'postgresql':
            # PostgreSQL JSONB handles lists/dicts natively
            return value
        else:
            # SQLite needs JSON string
            if isinstance(value, str):
                return value
            return json.dumps(value)

    def process_result_value(self, value, dialect):
        if value is None:
            return value
        if dialect.name == 'postgresql':
            # PostgreSQL returns native Python objects from JSONB
            return value
        else:
            # SQLite returns string, need to parse
            if isinstance(value, str):
                try:
                    return json.loads(value)
                except (json.JSONDecodeError, TypeError):
                    return value
            return value

class Semester(Base):
    __tablename__ = "semesters"
    
    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: uuid.uuid4().hex)
    user_id: Mapped[str] = mapped_column(String(36), ForeignKey("users.id", ondelete="CASCADE"), nullable=False, index=True)
    semester_number: Mapped[int] = mapped_column(Integer, nullable=False)
    label: Mapped[str] = mapped_column(String(100), nullable=False) # e.g. "5th Semester"
    start_date: Mapped[date] = mapped_column(Date, nullable=False)
    end_date: Mapped[date] = mapped_column(Date, nullable=False)
    status: Mapped[str] = mapped_column(String(20), default="ACTIVE") # ACTIVE, COMPLETED, UPCOMING
    is_active: Mapped[bool] = mapped_column(Boolean, default=True) # currently selected semester
    total_weeks: Mapped[int] = mapped_column(Integer, default=16)
    _working_days_raw: Mapped[Optional[List[int]]] = mapped_column(
        "working_days", 
        JSONType, 
        nullable=True,
        default=None
    )  # Stores [0,1,2,3,4,5] where 0=Mon, 6=Sun
    class_start_hour: Mapped[int] = mapped_column(Integer, default=9, nullable=True)
    class_end_hour: Mapped[int] = mapped_column(Integer, default=16, nullable=True)
    
    # Relationships
    user = relationship("User", back_populates="semesters")
    subjects = relationship("Subject", back_populates="semester", cascade="all, delete-orphan")
    timetable_entries = relationship("TimetableEntry", back_populates="semester", cascade="all, delete-orphan")
    class_sessions = relationship("ClassSession", back_populates="semester", cascade="all, delete-orphan")
    holidays = relationship("Holiday", back_populates="semester", cascade="all, delete-orphan")
    
    @property
    def working_days(self) -> List[int]:
        """Get working days as list of integers (0=Monday, 6=Sunday)."""
        if self._working_days_raw is not None:
            if isinstance(self._working_days_raw, list):
                return self._working_days_raw
            # Fallback for any string values in database
            if isinstance(self._working_days_raw, str):
                try:
                    return json.loads(self._working_days_raw)
                except (json.JSONDecodeError, TypeError):
                    pass
        return [0, 1, 2, 3, 4, 5]  # Default Mon-Sat
    
    @working_days.setter
    def working_days(self, value: List[int]):
        """Set working days from list of integers."""
        self._working_days_raw = value if value is not None else [0, 1, 2, 3, 4, 5]
