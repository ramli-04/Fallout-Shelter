from typing import Literal
from pydantic import BaseModel, ConfigDict, Field

class Decision(BaseModel):
    model_config = ConfigDict(extra="forbid", strict=True)
    action: Literal["MOVE_TO_SHELTER", "WAIT", "OBSERVE", "COMMUNICATE"]
    target: str = Field(max_length=64)
    message: str = Field(max_length=160)
    reason: str = Field(max_length=240)
    confidence: float = Field(ge=0, le=1)
