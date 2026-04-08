import json
from dataclasses import dataclass, field
from datetime import datetime, timezone
from threading import Lock
from time import monotonic, sleep
from typing import Callable
from urllib import error, request
from uuid import uuid4

from websocket import WebSocket
from websocket import WebSocketConnectionClosedException
from websocket import create_connection

from config.settings import RuntimeSettings
from trace_logger import append_trace


@dataclass
class BridgeRequestState:
    request_id: str
    session_key: str
    run_id: str = ""
    status: str = "thinking"
    stream_text: str = ""
    final_text: str = ""
    error_text: str = ""
    started_at: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    first_packet_at: datetime | None = None
    first_delta_at: datetime | None = None
    completed_at: datetime | None = None
    is_ended: bool = False


class BridgeClient:
    def __init__(self, settings: RuntimeSettings) -> None:
        self._settings = settings
        self._lock = Lock()
        self._socket: WebSocket | None = None
        self._registered = False
        self._last_error = ""
        self._bridge_online = False
        self._status_ok = False
        self._openclaw_online = False
        self._last_response: dict | None = None
        self._last_heartbeat_at = ""
        self._gateway_url = ""
        self._transport_mode = ""
        self._health_error = ""
        self._status_error = ""

    def _write_trace(self, kind: str, data: dict) -> None:
        append_trace(self._settings.quick_chat_trace_path, kind, data)

    def ensure_connection(self) -> None:
        self._write_trace("runtime.bridge.connect", {
            "source": "runtime-core",
            "stage": "ensure_connection_start",
            "deviceId": self._settings.bridge_device_id,
            "bridgeHost": self._settings.bridge_host,
            "bridgePort": self._settings.bridge_port,
            "bridgeWsPath": self._settings.bridge_ws_path,
        })
        self.refresh_status()
        with self._lock:
            if self._socket is not None and self._registered:
                self._write_trace("runtime.bridge.connect", {
                    "source": "runtime-core",
                    "stage": "ensure_connection_reuse",
                    "deviceId": self._settings.bridge_device_id,
                })
                return
        self._connect()

    def refresh_status(self) -> None:
        health_url = f"http://{self._settings.bridge_host}:{self._settings.bridge_port}/health"
        status_url = f"http://{self._settings.bridge_host}:{self._settings.bridge_port}/status"
        try:
            with request.urlopen(health_url, timeout=5) as response:
                health_payload = json.loads(response.read().decode("utf-8"))
            if health_payload.get("status") != "ok":
                raise RuntimeError("bridge health check failed")
            with self._lock:
                self._bridge_online = True
                self._health_error = ""
                self._gateway_url = str(health_payload.get("gatewayUrl", self._gateway_url))
        except (OSError, error.URLError, TimeoutError, RuntimeError, json.JSONDecodeError) as exc:
            with self._lock:
                self._bridge_online = False
                self._status_ok = False
                self._openclaw_online = False
                self._registered = False
                self._health_error = str(exc)
                self._status_error = ""
                self._last_error = self._health_error
            return
        try:
            with request.urlopen(status_url, timeout=5) as response:
                payload = json.loads(response.read().decode("utf-8"))
            with self._lock:
                self._status_ok = payload.get("status") == "ok"
                self._openclaw_online = bool(payload.get("gatewayReady", False))
                self._gateway_url = str(payload.get("gatewayUrl", ""))
                self._transport_mode = str(payload.get("transportMode", ""))
                self._status_error = "" if self._status_ok else "bridge status not ok"
                self._last_error = str(payload.get("lastError", "")) if self._status_ok else self._status_error
        except (OSError, error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            with self._lock:
                self._status_ok = False
                self._openclaw_online = False
                self._registered = False
                self._status_error = str(exc)
                self._last_error = self._status_error

    def send_heartbeat(self) -> None:
        self.ensure_connection()
        with self._lock:
            if self._socket is None or not self._registered:
                return
            self._socket.send(json.dumps({
                "type": "heartbeat",
                "deviceId": self._settings.bridge_device_id,
                "status": "online",
            }, ensure_ascii=False))
            ack = self._receive_json_locked()
            if ack.get("success"):
                self._last_heartbeat_at = ack.get("message", "")

    def submit_message(self, text: str) -> dict:
        final_response: dict[str, object] = {
            "requestId": "",
            "sessionKey": "",
            "runId": "",
            "text": "",
            "error": "",
            "finished": False,
        }

        def on_event(event: dict) -> None:
            final_response["requestId"] = event.get("requestId", "")
            final_response["sessionKey"] = event.get("sessionKey", "")
            final_response["runId"] = event.get("runId", "")
            final_response["text"] = event.get("text", "")
            final_response["error"] = event.get("error", "")
            final_response["finished"] = bool(event.get("finished", False))

        self.stream_message(text, on_event=on_event)
        return dict(final_response)

    def stream_message(
        self,
        text: str,
        on_event: Callable[[dict], None] | None = None,
        request_id: str | None = None,
        session_key: str | None = None,
    ) -> dict:
        self.ensure_connection()
        state = BridgeRequestState(
            request_id=request_id or f"req_{uuid4().hex[:12]}",
            session_key=session_key or f"session_{self._settings.bridge_device_id}",
        )
        with self._lock:
            if self._socket is None or not self._registered:
                raise RuntimeError(self._last_error or "bridge not ready")
            self._socket.settimeout(self._settings.bridge_receive_timeout_seconds)
            self._socket.send(json.dumps({
                "type": "message",
                "deviceId": self._settings.bridge_device_id,
                "text": text,
                "requestId": state.request_id,
                "sessionKey": state.session_key,
            }, ensure_ascii=False))
            self._write_trace("runtime.bridge.submit", {
                "source": "runtime-core",
                "requestId": state.request_id,
                "sessionKey": state.session_key,
                "deviceId": self._settings.bridge_device_id,
                "text": text,
            })
            while not state.is_ended:
                payload = self._receive_json_locked()
                event = self._update_request_state_from_payload(state, payload)
                if event is None:
                    continue
                self._last_response = self._event_to_latest_response(event)
                if on_event is not None:
                    on_event(event)
        return self._build_stream_result(state)

    def get_status(self) -> dict:
        with self._lock:
            return {
                "bridgeOnline": self._bridge_online,
                "bridgeStatusOk": self._status_ok,
                "bridgeRegistered": self._registered,
                "openclawOnline": self._openclaw_online,
                "lastError": self._last_error,
                "healthError": self._health_error,
                "statusError": self._status_error,
                "lastHeartbeatAt": self._last_heartbeat_at,
                "gatewayUrl": self._gateway_url,
                "transportMode": self._transport_mode,
                "latestResponse": None if self._last_response is None else dict(self._last_response),
            }

    def close(self) -> None:
        with self._lock:
            if self._socket is not None:
                self._socket.close()
            self._socket = None
            self._registered = False

    def _connect(self) -> None:
        health_url = f"http://{self._settings.bridge_host}:{self._settings.bridge_port}/health"
        ws_url = f"ws://{self._settings.bridge_host}:{self._settings.bridge_port}{self._settings.bridge_ws_path}"
        socket: WebSocket | None = None
        try:
            health_started = monotonic()
            self._write_trace("runtime.bridge.connect", {
                "source": "runtime-core",
                "stage": "health_start",
                "url": health_url,
            })
            with request.urlopen(health_url, timeout=5) as response:
                payload = json.loads(response.read().decode("utf-8"))
                if payload.get("status") != "ok":
                    raise RuntimeError("bridge health check failed")
            self._write_trace("runtime.bridge.connect", {
                "source": "runtime-core",
                "stage": "health_ok",
                "url": health_url,
                "elapsedMs": int((monotonic() - health_started) * 1000),
            })

            ws_started = monotonic()
            self._write_trace("runtime.bridge.connect", {
                "source": "runtime-core",
                "stage": "ws_connect_start",
                "url": ws_url,
            })
            socket = create_connection(ws_url, timeout=5)
            socket.settimeout(self._settings.bridge_receive_timeout_seconds)
            self._write_trace("runtime.bridge.connect", {
                "source": "runtime-core",
                "stage": "ws_connect_ok",
                "url": ws_url,
                "elapsedMs": int((monotonic() - ws_started) * 1000),
            })

            register_started = monotonic()
            self._write_trace("runtime.bridge.connect", {
                "source": "runtime-core",
                "stage": "register_start",
                "deviceId": self._settings.bridge_device_id,
            })
            socket.send(json.dumps({
                "type": "register",
                "deviceId": self._settings.bridge_device_id,
                "capabilities": ["text"],
                "metadata": {
                    "platform": "runtime",
                    "source": "runtime-core",
                },
            }, ensure_ascii=False))
            ack = self._receive_json(socket)
            if not ack.get("success"):
                raise RuntimeError(ack.get("message", "bridge register failed"))
            self._write_trace("runtime.bridge.connect", {
                "source": "runtime-core",
                "stage": "register_ack_ok",
                "deviceId": self._settings.bridge_device_id,
                "elapsedMs": int((monotonic() - register_started) * 1000),
                "message": str(ack.get("message", "")),
            })
            with self._lock:
                self._socket = socket
                self._registered = True
                self._bridge_online = True
                self._last_error = ""
                self._last_heartbeat_at = ""
            self._write_trace("runtime.bridge.connect", {
                "source": "runtime-core",
                "stage": "connect_ready",
                "deviceId": self._settings.bridge_device_id,
                "url": ws_url,
            })
        except (OSError, error.URLError, TimeoutError, RuntimeError, json.JSONDecodeError, WebSocketConnectionClosedException) as exc:
            error_text = str(exc)
            stage = "connect_failed"
            lowered = error_text.lower()
            if "health" in lowered:
                stage = "health_error"
            elif "register" in lowered or "registered" in lowered:
                stage = "register_ack_error"
            elif "timed out" in lowered or "timeout" in lowered:
                if socket is None:
                    stage = "health_error"
                else:
                    stage = "register_ack_error"
            elif socket is None:
                stage = "ws_connect_error"
            self._write_trace("runtime.bridge.connect", {
                "source": "runtime-core",
                "stage": stage,
                "deviceId": self._settings.bridge_device_id,
                "url": ws_url,
                "error": error_text,
            })
            with self._lock:
                if socket is not None:
                    socket.close()
                if self._socket is not None:
                    self._socket.close()
                self._socket = None
                self._registered = False
                self._status_ok = False
                self._bridge_online = False
                self._openclaw_online = False
                self._last_error = error_text
            raise

    def _receive_json(self, socket: WebSocket) -> dict:
        raw = socket.recv()
        payload = json.loads(raw)
        self._bridge_online = True
        return payload

    def _receive_json_locked(self) -> dict:
        assert self._socket is not None
        try:
            return self._receive_json(self._socket)
        except (json.JSONDecodeError, WebSocketConnectionClosedException, OSError) as exc:
            self._registered = False
            self._bridge_online = False
            self._last_error = str(exc)
            raise RuntimeError(self._last_error) from exc

    def _json_get(self, payload: dict | None, names: list[str], default: object = "") -> object:
        if payload is None:
            return default
        for name in names:
            if name in payload:
                return payload[name]
        return default

    def _get_bridge_event_type(self, payload: dict) -> str:
        type_value = str(self._json_get(payload, ["type"], "")).strip()
        event_value = str(self._json_get(payload, ["event"], "")).strip()
        if type_value == "event" and event_value:
            return event_value
        if type_value:
            return type_value
        return event_value

    def _get_bridge_event_payload(self, payload: dict) -> dict | None:
        event_payload = self._json_get(payload, ["payload", "data"], None)
        return event_payload if isinstance(event_payload, dict) else None

    def _get_bridge_event_text(self, payload: dict) -> str:
        event_payload = self._get_bridge_event_payload(payload)
        value = self._json_get(event_payload, ["delta", "text", "content", "message"], None)
        if value is None:
            value = self._json_get(payload, ["delta", "text", "content", "message"], "")
        return str(value)

    def _get_bridge_event_error(self, payload: dict) -> str:
        event_payload = self._get_bridge_event_payload(payload)
        value = self._json_get(event_payload, ["error", "message", "text"], None)
        if value is None:
            value = self._json_get(payload, ["error", "message", "text"], "")
        return str(value)

    def _elapsed_ms(self, started_at: datetime | None, ended_at: datetime | None) -> int | None:
        if started_at is None or ended_at is None:
            return None
        return int((ended_at - started_at).total_seconds() * 1000)

    def _build_runtime_event(
        self,
        state: BridgeRequestState,
        event_type: str,
        payload: dict,
        text: str = "",
        error_text: str = "",
        finished: bool = False,
    ) -> dict:
        return {
            "event": event_type,
            "requestId": state.request_id,
            "sessionKey": state.session_key,
            "runId": state.run_id,
            "text": text,
            "error": error_text,
            "finished": finished,
            "firstPacketMs": self._elapsed_ms(state.started_at, state.first_packet_at),
            "firstDeltaMs": self._elapsed_ms(state.started_at, state.first_delta_at),
            "totalMs": self._elapsed_ms(state.started_at, state.completed_at),
            "payload": payload,
        }

    def _update_request_state_from_payload(self, state: BridgeRequestState, payload: dict) -> dict | None:
        event_type = self._get_bridge_event_type(payload)
        incoming_request_id = str(self._json_get(payload, ["requestId", "request_id"], "")).strip()
        if incoming_request_id and incoming_request_id != state.request_id:
            return None
        now = datetime.now(timezone.utc)
        run_id = str(self._json_get(payload, ["runId", "run_id"], "")).strip()
        if run_id:
            state.run_id = run_id
        session_key = str(self._json_get(payload, ["sessionKey", "session_key"], "")).strip()
        if session_key:
            state.session_key = session_key
        if event_type == "assistant.delta":
            text = self._get_bridge_event_text(payload).strip()
            if not text:
                return None
            if state.first_packet_at is None:
                state.first_packet_at = now
            if state.first_delta_at is None:
                state.first_delta_at = now
            state.status = "running"
            state.stream_text = text
            event = self._build_runtime_event(state, event_type, payload, text=text, finished=False)
            self._write_trace("runtime.bridge.event", {
                "source": "runtime-core",
                "requestId": state.request_id,
                "sessionKey": state.session_key,
                "runId": state.run_id,
                "event": event_type,
                "text": text,
                "error": "",
                "firstPacketMs": event.get("firstPacketMs"),
                "firstDeltaMs": event.get("firstDeltaMs"),
            })
            return event
        if event_type == "assistant.final":
            text = self._get_bridge_event_text(payload).strip() or state.stream_text
            if state.first_packet_at is None:
                state.first_packet_at = now
            state.stream_text = text
            state.final_text = text
            state.status = "completed"
            state.completed_at = now
            state.is_ended = True
            event = self._build_runtime_event(state, event_type, payload, text=text, finished=True)
            self._write_trace("runtime.bridge.event", {
                "source": "runtime-core",
                "requestId": state.request_id,
                "sessionKey": state.session_key,
                "runId": state.run_id,
                "event": event_type,
                "text": text,
                "error": "",
                "firstPacketMs": event.get("firstPacketMs"),
                "firstDeltaMs": event.get("firstDeltaMs"),
                "totalMs": event.get("totalMs"),
            })
            return event
        if event_type == "assistant.error":
            error_text = self._get_bridge_event_error(payload).strip() or "assistant.error"
            if state.first_packet_at is None:
                state.first_packet_at = now
            state.error_text = error_text
            state.status = "error"
            state.completed_at = now
            state.is_ended = True
            event = self._build_runtime_event(state, event_type, payload, error_text=error_text, finished=True)
            self._write_trace("runtime.bridge.event", {
                "source": "runtime-core",
                "requestId": state.request_id,
                "sessionKey": state.session_key,
                "runId": state.run_id,
                "event": event_type,
                "text": "",
                "error": error_text,
                "firstPacketMs": event.get("firstPacketMs"),
                "totalMs": event.get("totalMs"),
            })
            return event
        if event_type == "response":
            text = self._get_bridge_event_text(payload).strip()
            error_text = self._get_bridge_event_error(payload).strip()
            if state.first_packet_at is None:
                state.first_packet_at = now
            if error_text:
                state.error_text = error_text
                state.status = "error"
                state.completed_at = now
                state.is_ended = True
                event = self._build_runtime_event(state, event_type, payload, error_text=error_text, finished=True)
                self._write_trace("runtime.bridge.event", {
                    "source": "runtime-core",
                    "requestId": state.request_id,
                    "sessionKey": state.session_key,
                    "runId": state.run_id,
                    "event": event_type,
                    "text": "",
                    "error": error_text,
                    "firstPacketMs": event.get("firstPacketMs"),
                    "totalMs": event.get("totalMs"),
                })
                return event
            state.stream_text = text
            state.final_text = text
            state.status = "completed"
            state.completed_at = now
            state.is_ended = True
            event = self._build_runtime_event(state, event_type, payload, text=text, finished=True)
            self._write_trace("runtime.bridge.event", {
                "source": "runtime-core",
                "requestId": state.request_id,
                "sessionKey": state.session_key,
                "runId": state.run_id,
                "event": event_type,
                "text": text,
                "error": "",
                "firstPacketMs": event.get("firstPacketMs"),
                "totalMs": event.get("totalMs"),
            })
            return event
        return None

    def _event_to_latest_response(self, event: dict) -> dict:
        return {
            "requestId": str(event.get("requestId", "")),
            "sessionKey": str(event.get("sessionKey", "")),
            "runId": str(event.get("runId", "")),
            "text": str(event.get("text", "")),
            "error": str(event.get("error", "")),
            "finished": bool(event.get("finished", False)),
            "firstPacketMs": event.get("firstPacketMs"),
            "firstDeltaMs": event.get("firstDeltaMs"),
            "totalMs": event.get("totalMs"),
        }

    def _build_stream_result(self, state: BridgeRequestState) -> dict:
        return {
            "requestId": state.request_id,
            "sessionKey": state.session_key,
            "runId": state.run_id,
            "text": state.final_text or state.stream_text,
            "error": state.error_text,
            "finished": state.is_ended,
            "firstPacketMs": self._elapsed_ms(state.started_at, state.first_packet_at),
            "firstDeltaMs": self._elapsed_ms(state.started_at, state.first_delta_at),
            "totalMs": self._elapsed_ms(state.started_at, state.completed_at),
        }


def keep_bridge_alive(client: BridgeClient, settings: RuntimeSettings) -> None:
    while True:
        try:
            client.ensure_connection()
            client.send_heartbeat()
        except Exception:
            pass
        sleep(settings.bridge_health_poll_seconds)
