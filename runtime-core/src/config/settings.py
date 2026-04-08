from dataclasses import dataclass
import os


@dataclass(frozen=True)
class RuntimeSettings:
    host: str = "127.0.0.1"
    port: int = 8765
    bridge_host: str = "127.0.0.1"
    bridge_port: int = 18790
    bridge_ws_path: str = "/ws"
    bridge_device_id: str = "runtime-host"
    bridge_health_poll_seconds: float = 2.0
    bridge_reconnect_seconds: float = 2.0
    bridge_heartbeat_seconds: float = 20.0
    bridge_receive_timeout_seconds: float = 30.0
    quick_chat_trace_path: str = ""


def load_settings() -> RuntimeSettings:
    default_trace_path = os.path.abspath(
        os.path.join(os.path.dirname(__file__), "..", "..", "..", "userdata", "quick-chat.trace.jsonl")
    )
    return RuntimeSettings(
        host=os.getenv("QQPAL_RUNTIME_HOST", "127.0.0.1"),
        port=int(os.getenv("QQPAL_RUNTIME_PORT", "8765")),
        bridge_host=os.getenv("QQPAL_BRIDGE_HOST", "127.0.0.1"),
        bridge_port=int(os.getenv("QQPAL_BRIDGE_PORT", "18790")),
        bridge_ws_path=os.getenv("QQPAL_BRIDGE_WS_PATH", "/ws"),
        bridge_device_id=os.getenv("QQPAL_BRIDGE_DEVICE_ID", "godot"),
        bridge_health_poll_seconds=float(os.getenv("QQPAL_BRIDGE_HEALTH_POLL_SECONDS", "2.0")),
        bridge_reconnect_seconds=float(os.getenv("QQPAL_BRIDGE_RECONNECT_SECONDS", "2.0")),
        bridge_heartbeat_seconds=float(os.getenv("QQPAL_BRIDGE_HEARTBEAT_SECONDS", "20.0")),
        bridge_receive_timeout_seconds=float(os.getenv("QQPAL_BRIDGE_RECEIVE_TIMEOUT_SECONDS", "30.0")),
        quick_chat_trace_path=os.getenv("QQPAL_QUICK_CHAT_TRACE_PATH", default_trace_path),
    )
