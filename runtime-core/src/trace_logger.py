from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from threading import Lock
from typing import Any


_TRACE_LOCK = Lock()


def append_trace(path: str, kind: str, data: dict[str, Any]) -> None:
    if not path:
        return
    payload = {
        "ts": datetime.now(timezone.utc).isoformat(),
        "kind": kind,
    }
    payload.update(data)
    line = json.dumps(payload, ensure_ascii=False)
    target = Path(path)
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        with _TRACE_LOCK:
            with target.open("a", encoding="utf-8", newline="\n") as handle:
                handle.write(line)
                handle.write("\n")
    except OSError:
        return
