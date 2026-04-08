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
    source: str = "quick_chat"
    session_id: str = "quick_chat_default"
    device_id: str = ""
    client_message_id: str = ""
    task_id: str = field(default_factory=lambda: f"task_{uuid4().hex[:12]}")
    request_id: str = field(default_factory=lambda: f"req_{uuid4().hex[:12]}")
    status: str = TaskStatus.IDLE.value
    result: str = ""
    error: str = ""
    stream_text: str = ""
    final_text: str = ""
    run_id: str = ""
    session_key: str = ""
    first_packet_at: str = ""
    first_delta_at: str = ""
    finished: bool = False
    timestamps: dict[str, str] = field(default_factory=lambda: {"created_at": utc_now_iso()})
    cancel_requested: bool = False
    status_text: str = ""

    def to_dict(self) -> dict[str, Any]:
        return {
            "task_id": self.task_id,
            "request_id": self.request_id,
            "source": self.source,
            "session_id": self.session_id,
            "device_id": self.device_id,
            "client_message_id": self.client_message_id,
            "user_input": self.user_input,
            "status": self.status,
            "status_text": self.status_text,
            "result": self.result,
            "error": self.error,
            "stream_text": self.stream_text,
            "final_text": self.final_text,
            "run_id": self.run_id,
            "session_key": self.session_key,
            "first_packet_at": self.first_packet_at,
            "first_delta_at": self.first_delta_at,
            "finished": self.finished,
            "timestamps": dict(self.timestamps),
        }
