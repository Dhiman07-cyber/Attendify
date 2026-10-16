from typing import Optional, List
from datetime import date
from pydantic import BaseModel, Field, ConfigDict, field_validator
import json

class SemesterCreate(BaseModel):
    semester_number: int = Field(..., ge=1, le=20)
    label: str = Field(..., min_length=1, max_length=100)
    start_date: date
    end_date: date
    status: Optional[str] = "ACTIVE"
    total_weeks: Optional[int] = 16
    working_days: Optional[List[int]] = Field(default=None, description="DEPRECATED: Not used for forecasts. Weekday indices: 0=Monday, 6=Sunday")
    
    @field_validator('working_days')
    @classmethod
    def validate_working_days(cls, v):
        if v is None:
            return None
        if not v:
            return None  # Allow empty list, will default to None
        if not all(isinstance(day, int) and 0 <= day <= 6 for day in v):
            raise ValueError("working_days must contain integers 0-6 (Monday=0, Sunday=6)")
        if len(set(v)) != len(v):
            raise ValueError("working_days cannot contain duplicates")
        return sorted(set(v))

class SemesterUpdate(BaseModel):
    label: Optional[str] = None
    start_date: Optional[date] = None
    end_date: Optional[date] = None
    status: Optional[str] = None
    total_weeks: Optional[int] = None
    working_days: Optional[List[int]] = Field(default=None, description="DEPRECATED: Not used for forecasts")
    
    @field_validator('working_days')
    @classmethod
    def validate_working_days(cls, v):
        if v is None:
            return None
        if not v:
            return None  # Allow empty list
        if not all(isinstance(day, int) and 0 <= day <= 6 for day in v):
            raise ValueError("working_days must contain integers 0-6 (Monday=0, Sunday=6)")
        if len(set(v)) != len(v):
            raise ValueError("working_days cannot contain duplicates")
        return sorted(set(v))

class SemesterOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)
    id: str
    user_id: str
    semester_number: int
    label: str
    start_date: date
    end_date: date
    status: str
    is_active: bool
    total_weeks: int
    working_days: List[int] = Field(default=[0,1,2,3,4,5])
    class_start_hour: int = 9
    class_end_hour: int = 16
    current_week: int = 1
    weeks_remaining: int = 0
    progress_percentage: float = 0.0

class SemesterSwitchRequest(BaseModel):
    semester_id: str
