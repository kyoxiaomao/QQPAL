import json
import sys
import threading
import time
from pathlib import Path
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
if str(SRC) not in sys.path:
    sys.path.insert(0, str(SRC))

from api.server import create_server
from config.settings import RuntimeSettings
from task.manager import TaskManager


def request_json(method: str, url: str, payload: dict | None = None) -> dict:
    body = None
    headers = {}
    if payload is not None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        headers["Content-Type"] = "application/json"
    request = Request(url, data=body, headers=headers, method=method)
    with urlopen(request, timeout=5) as response:
        return json.loads(response.read().decode("utf-8"))


def main() -> None:
    settings = RuntimeSettings(port=8766, planning_delay_seconds=0.2, running_delay_seconds=0.3, success_delay_seconds=0.1)
    manager = TaskManager(settings)
    server = create_server(settings, manager)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    base_url = f"http://{settings.host}:{settings.port}"
    health = request_json("GET", f"{base_url}/health")
    print("health:", health)

    created = request_json("POST", f"{base_url}/tasks", {"input": {"text": "打开网页并提交表单"}})
    print("created:", created)

    task_id = created["task_id"]
    current = created
    for _ in range(20):
        time.sleep(0.15)
        current = request_json("GET", f"{base_url}/tasks/{task_id}")
        if current["status"] in {"success", "failed"}:
            break
    print("final:", current)

    server.shutdown()
    server.server_close()


if __name__ == "__main__":
    main()
