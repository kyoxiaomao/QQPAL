from api.server import create_server
from config.settings import load_settings
from task.manager import TaskManager


def main() -> None:
    settings = load_settings()
    manager = TaskManager(settings)
    server = create_server(settings, manager)
    print(f"[runtime-core] listening on http://{settings.host}:{settings.port}")
    server.serve_forever()


if __name__ == "__main__":
    main()
