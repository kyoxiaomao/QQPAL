from time import sleep

from config.settings import RuntimeSettings
from state.enums import TaskStatus
from task.models import TaskRecord, utc_now_iso


class DemoTaskStateMachine:
    def __init__(self, settings: RuntimeSettings) -> None:
        self._settings = settings

    def run(self, task: TaskRecord, should_fail: bool = False) -> None:
        self._transition(task, TaskStatus.TALKING, "正在确认需求")
        sleep(self._settings.planning_delay_seconds / 2.0)
        self._transition(task, TaskStatus.PLANNING, "正在生成执行方案")
        sleep(self._settings.planning_delay_seconds)
        self._transition(task, TaskStatus.RUNNING, "正在执行任务")
        sleep(self._settings.running_delay_seconds)

        if should_fail:
            task.error = "示例任务执行失败"
            self._transition(task, TaskStatus.FAILED, "任务执行失败")
        else:
            task.result = f"已完成示例任务：{task.user_input}"
            self._transition(task, TaskStatus.SUCCESS, "任务执行完成")

        task.timestamps["finished_at"] = utc_now_iso()
        sleep(self._settings.success_delay_seconds)

    def _transition(self, task: TaskRecord, status: TaskStatus, status_text: str) -> None:
        task.status = status.value
        task.timestamps["updated_at"] = utc_now_iso()
        task.timestamps["status_text"] = status_text
