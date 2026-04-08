import json
from queue import Empty
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from config.settings import RuntimeSettings
from task.manager import TaskManager


class RuntimeRequestHandler(BaseHTTPRequestHandler):
    manager: TaskManager
    settings: RuntimeSettings

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/chat/stream":
            query = parse_qs(parsed.query)
            task_id = str(query.get("taskId", [""])[0]).strip()
            if not task_id:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "taskId is required"})
                return
            self._handle_chat_stream(task_id)
            return

        if parsed.path == "/health":
            self._send_json(
                HTTPStatus.OK,
                {
                    "service": "runtime-core",
                    "status": "ok",
                    "host": self.settings.host,
                    "port": self.settings.port,
                    "demo_mode": True,
                },
            )
            return

        if parsed.path == "/status":
            self._send_json(HTTPStatus.OK, self.manager.build_status_payload())
            return

        if parsed.path.startswith("/tasks/"):
            task_id = parsed.path.removeprefix("/tasks/")
            task = self.manager.get_task(task_id)
            if task is None:
                self._send_json(HTTPStatus.NOT_FOUND, {"error": f"task not found: {task_id}"})
                return
            self._send_json(HTTPStatus.OK, task)
            return

        self._send_json(HTTPStatus.NOT_FOUND, {"error": "route not found"})

    def do_POST(self) -> None:
        parsed = urlparse(self.path)
        if parsed.path == "/chat/messages":
            payload = self._read_json()
            user_input = self._extract_user_input(payload)
            if not user_input:
                self._send_json(HTTPStatus.BAD_REQUEST, {"error": "text or input.text is required"})
                return
            response = self.manager.submit_chat_message(
                user_input=user_input,
                source=str(payload.get("source", "quick_chat")),
                session_id=str(payload.get("sessionId", "quick_chat_default")),
                device_id=str(payload.get("deviceId", "")),
                client_message_id=str(payload.get("clientMessageId", "")),
            )
            self._send_json(HTTPStatus.ACCEPTED, response)
            return

        if parsed.path.startswith("/tasks/") and parsed.path.endswith("/cancel"):
            task_id = parsed.path.removeprefix("/tasks/").removesuffix("/cancel").strip("/")
            task = self.manager.cancel_task(task_id)
            if task is None:
                self._send_json(HTTPStatus.NOT_FOUND, {"error": f"task not found: {task_id}"})
                return
            self._send_json(HTTPStatus.ACCEPTED, task)
            return

        if parsed.path != "/tasks":
            self._send_json(HTTPStatus.NOT_FOUND, {"error": "route not found"})
            return

        payload = self._read_json()
        user_input = self._extract_user_input(payload)
        if not user_input:
            self._send_json(HTTPStatus.BAD_REQUEST, {"error": "user_input or input.text is required"})
            return

        should_fail = bool(payload.get("should_fail", False))
        task = self.manager.submit_task(user_input=user_input, should_fail=should_fail)
        self._send_json(HTTPStatus.ACCEPTED, task)

    def log_message(self, format: str, *args) -> None:
        return

    def _read_json(self) -> dict:
        content_length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(content_length) if content_length > 0 else b"{}"
        if not raw:
            return {}
        return json.loads(raw.decode("utf-8"))

    def _extract_user_input(self, payload: dict) -> str:
        if isinstance(payload.get("text"), str):
            return payload["text"].strip()
        if isinstance(payload.get("user_input"), str):
            return payload["user_input"].strip()
        input_block = payload.get("input")
        if isinstance(input_block, dict) and isinstance(input_block.get("text"), str):
            return input_block["text"].strip()
        return ""

    def _send_json(self, status: HTTPStatus, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _handle_chat_stream(self, task_id: str) -> None:
        subscriber, snapshot = self.manager.subscribe_task_events(task_id)
        if snapshot is None:
            self._send_json(HTTPStatus.NOT_FOUND, {"error": f"task not found: {task_id}"})
            return
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", "text/event-stream; charset=utf-8")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self.end_headers()
        try:
            self._send_sse_event(str(snapshot.get("event", "status")), snapshot)
            if subscriber is None:
                self._send_sse_event("done", {
                    "taskId": snapshot.get("taskId", task_id),
                    "requestId": snapshot.get("requestId", ""),
                    "finished": True,
                })
                return
            while True:
                try:
                    event = subscriber.get(timeout=10.0)
                except Empty:
                    self.wfile.write(b": ping\n\n")
                    self.wfile.flush()
                    continue
                self._send_sse_event(str(event.get("event", "status")), event)
                if str(event.get("event", "")) == "done":
                    return
        except (BrokenPipeError, ConnectionResetError):
            return
        finally:
            self.manager.unsubscribe_task_events(task_id, subscriber)

    def _send_sse_event(self, event_name: str, payload: dict) -> None:
        body = json.dumps(payload, ensure_ascii=False)
        chunk = f"event: {event_name}\ndata: {body}\n\n".encode("utf-8")
        self.wfile.write(chunk)
        self.wfile.flush()

def create_server(settings: RuntimeSettings, manager: TaskManager) -> ThreadingHTTPServer:
    handler = type("BoundRuntimeRequestHandler", (RuntimeRequestHandler,), {})
    handler.manager = manager
    handler.settings = settings
    return ThreadingHTTPServer((settings.host, settings.port), handler)
