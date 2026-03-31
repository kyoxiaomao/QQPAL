from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any
from uuid import uuid4

from state.enums import TaskStatus


def utc_now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass
class TaskRecord:
    user_input: str
    task_id: str = field(default_factory=lambda: f"task_{uuid4().hex[:12]}")
    status: str = TaskStatus.IDLE.value
    result: str = ""
    error: str = ""
    timestamps: dict[str, str] = field(default_factory=lambda: {"created_at": utc_now_iso()})

    def to_dict(self) -> dict[str, Any]:
        return {
            "task_id": self.task_id,
            "user_input": self.user_input,
            "status": self.status,
            "result": self.result,
            "error": self.error,
            "timestamps": dict(self.timestamps),
        }
