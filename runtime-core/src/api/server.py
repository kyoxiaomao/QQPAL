import json
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

from config.settings import RuntimeSettings
from task.manager import TaskManager


class RuntimeRequestHandler(BaseHTTPRequestHandler):
    manager: TaskManager
    settings: RuntimeSettings

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
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


def create_server(settings: RuntimeSettings, manager: TaskManager) -> ThreadingHTTPServer:
    handler = type("BoundRuntimeRequestHandler", (RuntimeRequestHandler,), {})
    handler.manager = manager
    handler.settings = settings
    return ThreadingHTTPServer((settings.host, settings.port), handler)
