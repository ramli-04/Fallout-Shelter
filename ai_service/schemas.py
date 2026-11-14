from typing import Literal
from pydantic import BaseModel, ConfigDict, Field

class Decision(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    action: Literal["MOVE_TO_SHELTER", "WAIT", "OBSERVE", "COMMUNICATE", "DANCE", "FLEE_RANDOMLY", "HELP_AGENT", "FOLLOW_AGENT", "CALL", "TEXT", "POST", "FIND_FAMILY", "DRIVE_TO_SHELTER", "CREATE_ROADBLOCK", "REMOVE_ROADBLOCK", "ISSUE_ALERT"]
    target: str = Field(max_length=64)
    message: str = Field(max_length=160)
    reason: str = Field(max_length=240)
    confidence: float = Field(ge=0, le=1)
