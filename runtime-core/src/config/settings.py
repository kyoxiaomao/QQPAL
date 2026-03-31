from dataclasses import dataclass
import os


@dataclass(frozen=True)
class RuntimeSettings:
    host: str = "127.0.0.1"
    port: int = 8765
    planning_delay_seconds: float = 0.8
    running_delay_seconds: float = 1.2
    success_delay_seconds: float = 0.6


def load_settings() -> RuntimeSettings:
    return RuntimeSettings(
        host=os.getenv("QQPAL_RUNTIME_HOST", "127.0.0.1"),
        port=int(os.getenv("QQPAL_RUNTIME_PORT", "8765")),
        planning_delay_seconds=float(os.getenv("QQPAL_RUNTIME_PLANNING_DELAY", "0.8")),
        running_delay_seconds=float(os.getenv("QQPAL_RUNTIME_RUNNING_DELAY", "1.2")),
        success_delay_seconds=float(os.getenv("QQPAL_RUNTIME_SUCCESS_DELAY", "0.6")),
    )
