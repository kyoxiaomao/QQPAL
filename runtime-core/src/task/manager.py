from threading import Lock, Thread

from config.settings import RuntimeSettings
from state.machine import DemoTaskStateMachine
from task.models import TaskRecord


class TaskManager:
    def __init__(self, settings: RuntimeSettings) -> None:
        self._settings = settings
        self._machine = DemoTaskStateMachine(settings)
        self._tasks: dict[str, TaskRecord] = {}
        self._lock = Lock()

    def submit_task(self, user_input: str, should_fail: bool = False) -> dict:
        task = TaskRecord(user_input=user_input)
        with self._lock:
            self._tasks[task.task_id] = task

        worker = Thread(target=self._run_task, args=(task.task_id, should_fail), daemon=True)
        worker.start()
        return task.to_dict()

    def get_task(self, task_id: str) -> dict | None:
        with self._lock:
            task = self._tasks.get(task_id)
            return None if task is None else task.to_dict()

    def _run_task(self, task_id: str, should_fail: bool) -> None:
        with self._lock:
            task = self._tasks[task_id]
        self._machine.run(task, should_fail=should_fail)
