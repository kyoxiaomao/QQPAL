from datetime import datetime
from queue import Queue
from threading import Lock, Thread

from bridge.client import BridgeClient
from config.settings import RuntimeSettings
from state.enums import TaskStatus
from task.models import TaskRecord
from task.models import utc_now_iso
from trace_logger import append_trace


class TaskManager:
    def __init__(self, settings: RuntimeSettings) -> None:
        self._settings = settings
        self._bridge = BridgeClient(settings)
        self._tasks: dict[str, TaskRecord] = {}
        self._task_subscribers: dict[str, list[Queue]] = {}
        self._lock = Lock()
        self._bridge_worker = Thread(target=self._run_bridge_keepalive, daemon=True)
        self._bridge_worker.start()

    def _write_trace(self, kind: str, data: dict) -> None:
        append_trace(self._settings.quick_chat_trace_path, kind, data)

    def _trace_task_status_locked(self, task: TaskRecord, previous_status: str, reason: str) -> None:
        self._write_trace("runtime.task.status", {
            "source": "runtime-core",
            "taskId": task.task_id,
            "requestId": task.request_id,
            "sessionId": task.session_id,
            "sessionKey": task.session_key,
            "runId": task.run_id,
            "fromStatus": previous_status,
            "toStatus": task.status,
            "statusText": task.status_text,
            "finished": task.finished,
            "reason": reason,
            "error": task.error,
            "text": task.final_text or task.stream_text or task.result,
            "firstPacketAt": task.first_packet_at,
            "firstDeltaAt": task.first_delta_at,
        })

    def submit_chat_message(
        self,
        user_input: str,
        source: str = "quick_chat",
        session_id: str = "quick_chat_default",
        device_id: str = "",
        client_message_id: str = "",
    ) -> dict:
        task = TaskRecord(
            user_input=user_input,
            source=source,
            session_id=session_id,
            device_id=device_id,
            client_message_id=client_message_id,
        )
        task.status_text = "已接收请求，正在转发到 bridge"
        task.timestamps["updated_at"] = utc_now_iso()
        task.timestamps["status_text"] = task.status_text
        with self._lock:
            self._tasks[task.task_id] = task
            self._task_subscribers[task.task_id] = []
            self._write_trace("runtime.task.submit", {
                "source": "runtime-core",
                "taskId": task.task_id,
                "requestId": task.request_id,
                "sessionId": task.session_id,
                "deviceId": task.device_id,
                "clientMessageId": task.client_message_id,
                "text": task.user_input,
            })
        worker = Thread(target=self._run_task, args=(task.task_id,), daemon=True)
        worker.start()
        return {
            "status": "accepted",
            "requestId": task.request_id,
            "taskId": task.task_id,
            "message": {
                "clientMessageId": task.client_message_id,
                "text": task.user_input,
            },
            "runtimeState": {
                "busy": True,
                "status": TaskStatus.PLANNING.value,
                "statusText": task.status_text,
            },
        }

    def submit_task(self, user_input: str, should_fail: bool = False) -> dict:
        return self.submit_chat_message(user_input=user_input)

    def get_task(self, task_id: str) -> dict | None:
        with self._lock:
            task = self._tasks.get(task_id)
            return None if task is None else task.to_dict()

    def cancel_task(self, task_id: str) -> dict | None:
        with self._lock:
            task = self._tasks.get(task_id)
            if task is None:
                return None
            task.cancel_requested = True
            if not task.finished:
                previous_status = task.status
                task.status = TaskStatus.FAILED.value
                task.error = "任务已停止"
                task.status_text = "任务已停止"
                task.finished = True
                task.final_text = task.final_text or task.stream_text
                task.result = task.result or task.final_text
                task.timestamps["updated_at"] = utc_now_iso()
                task.timestamps["status_text"] = task.status_text
                task.timestamps["finished_at"] = utc_now_iso()
                self._trace_task_status_locked(task, previous_status, "cancel_requested")
                error_event = self._build_stream_event_locked(task, "assistant.error")
                done_event = self._build_stream_event_locked(task, "done")
            else:
                error_event = None
                done_event = None
            snapshot = task.to_dict()
        if error_event is not None:
            self._publish_task_event(task_id, error_event)
            self._publish_task_event(task_id, done_event)
        return snapshot

    def snapshot_tasks(self) -> list[dict]:
        with self._lock:
            return [task.to_dict() for task in self._tasks.values()]

    def subscribe_task_events(self, task_id: str) -> tuple[Queue | None, dict | None]:
        with self._lock:
            task = self._tasks.get(task_id)
            if task is None:
                return None, None
            snapshot = self._build_stream_snapshot_locked(task)
            if task.finished:
                return None, snapshot
            subscriber: Queue = Queue()
            self._task_subscribers.setdefault(task_id, []).append(subscriber)
            return subscriber, snapshot

    def unsubscribe_task_events(self, task_id: str, subscriber: Queue | None) -> None:
        if subscriber is None:
            return
        with self._lock:
            subscribers = self._task_subscribers.get(task_id, [])
            self._task_subscribers[task_id] = [item for item in subscribers if item is not subscriber]

    def build_status_payload(self) -> dict:
        bridge_status = self._bridge.get_status()
        tasks = self.snapshot_tasks()
        active_task = None
        latest_task = None
        for task in tasks:
            task_timestamps = task.get("timestamps", {})
            latest_timestamps = {} if latest_task is None else latest_task.get("timestamps", {})
            if latest_task is None or task_timestamps.get("updated_at", "") > latest_timestamps.get("updated_at", ""):
                latest_task = task
            if task.get("status", "") in {"talking", "planning", "running", "waiting_user"}:
                active_timestamps = {} if active_task is None else active_task.get("timestamps", {})
                if active_task is None or task_timestamps.get("updated_at", "") > active_timestamps.get("updated_at", ""):
                    active_task = task
        busy = active_task is not None
        bridge_online = bool(bridge_status.get("bridgeOnline", False))
        bridge_status_ok = bool(bridge_status.get("bridgeStatusOk", False))
        bridge_registered = bool(bridge_status.get("bridgeRegistered", False))
        openclaw_online = bool(bridge_status.get("openclawOnline", False))
        ai_state = self._derive_runtime_state(latest_task, bridge_status)
        ai_status_text = self._derive_runtime_status_text(ai_state)
        latest_response = {
            "requestId": latest_task.get("request_id", "") if latest_task else "",
            "taskId": latest_task.get("task_id", "") if latest_task else "",
            "role": "assistant",
            "text": latest_task.get("final_text", "") or latest_task.get("stream_text", "") or latest_task.get("result", "") if latest_task else "",
            "error": latest_task.get("error", "") if latest_task else "",
            "finished": bool(latest_task.get("finished", False)) if latest_task else False,
            "receivedAt": latest_task.get("timestamps", {}).get("updated_at", "") if latest_task else "",
            "runId": latest_task.get("run_id", "") if latest_task else "",
            "sessionKey": latest_task.get("session_key", "") if latest_task else "",
            "firstPacketAt": latest_task.get("first_packet_at", "") if latest_task else "",
            "firstDeltaAt": latest_task.get("first_delta_at", "") if latest_task else "",
        }
        return {
            "status": "ok",
            "service": "runtime-core",
            "aiState": ai_state,
            "aiStatusText": ai_status_text,
            "serviceHealth": {
                "runtimeOnline": True,
                "bridgeOnline": bridge_online,
                "bridgeStatusOk": bridge_status_ok,
                "bridgeRegistered": bridge_registered,
                "openclawOnline": openclaw_online,
                "lastHeartbeatAt": str(bridge_status.get("lastHeartbeatAt", "")),
                "lastError": str(bridge_status.get("lastError", "")),
                "healthError": str(bridge_status.get("healthError", "")),
                "statusError": str(bridge_status.get("statusError", "")),
                "gatewayUrl": str(bridge_status.get("gatewayUrl", "")),
                "transportMode": str(bridge_status.get("transportMode", "")),
            },
            "busy": busy,
            "activeTask": active_task,
            "latestTask": latest_task,
            "latestResponse": latest_response,
        }

    def _derive_runtime_state(self, task: dict | None, bridge_status: dict) -> str:
        if not bool(bridge_status.get("bridgeOnline", False)):
            return "service_offline"
        if not bool(bridge_status.get("bridgeStatusOk", False)):
            return "service_error"
        if not bool(bridge_status.get("bridgeRegistered", False)) or not bool(bridge_status.get("openclawOnline", False)):
            return "recovering"
        if task is None:
            return "online"
        task_status = str(task.get("status", ""))
        if task_status == TaskStatus.RUNNING.value:
            return "running"
        if task_status in {TaskStatus.TALKING.value, TaskStatus.PLANNING.value}:
            return "thinking"
        return "online"

    def _derive_runtime_status_text(self, ai_state: str) -> str:
        if ai_state == "service_offline":
            return "服务离线"
        if ai_state == "service_error":
            return "服务异常"
        if ai_state == "recovering":
            return "连接恢复中"
        if ai_state == "thinking":
            return "等待首包"
        if ai_state == "running":
            return "AI回复中"
        return "AI空闲"

    def _run_task(self, task_id: str) -> None:
        with self._lock:
            task = self._tasks[task_id]
            previous_status = task.status
            task.status = TaskStatus.TALKING.value
            task.status_text = "正在连接 bridge"
            task.timestamps["started_at"] = utc_now_iso()
            task.timestamps["updated_at"] = utc_now_iso()
            task.timestamps["status_text"] = task.status_text
            self._trace_task_status_locked(task, previous_status, "task_started")
            initial_event = self._build_stream_event_locked(task, "status")
        self._publish_task_event(task_id, initial_event)
        try:
            self._bridge.ensure_connection()
            with self._lock:
                task = self._tasks.get(task_id)
                if task is None or task.cancel_requested:
                    return
                previous_status = task.status
                task.status = TaskStatus.PLANNING.value
                task.status_text = "bridge 已连接，正在等待回复"
                task.timestamps["updated_at"] = utc_now_iso()
                task.timestamps["status_text"] = task.status_text
                self._trace_task_status_locked(task, previous_status, "bridge_connected")
                planning_event = self._build_stream_event_locked(task, "status")
            self._publish_task_event(task_id, planning_event)

            def on_event(event: dict) -> None:
                publish_event = None
                publish_done = None
                with self._lock:
                    current = self._tasks.get(task_id)
                    if current is None or current.cancel_requested:
                        return
                    now = utc_now_iso()
                    current.run_id = str(event.get("runId", "") or current.run_id)
                    current.session_key = str(event.get("sessionKey", "") or current.session_key)
                    event_name = str(event.get("event", ""))
                    if event_name == "assistant.delta":
                        if not current.first_packet_at:
                            current.first_packet_at = now
                        if not current.first_delta_at:
                            current.first_delta_at = now
                        previous_status = current.status
                        current.status = TaskStatus.RUNNING.value
                        current.status_text = "AI回复中"
                        current.stream_text = str(event.get("text", ""))
                        current.timestamps["updated_at"] = now
                        current.timestamps["status_text"] = current.status_text
                        self._trace_task_status_locked(current, previous_status, "assistant.delta")
                        publish_event = self._build_stream_event_locked(current, "assistant.delta")
                    elif event_name == "assistant.final":
                        if not current.first_packet_at:
                            current.first_packet_at = now
                        previous_status = current.status
                        current.status = TaskStatus.SUCCESS.value
                        current.status_text = "AI空闲"
                        current.stream_text = str(event.get("text", ""))
                        current.final_text = current.stream_text
                        current.result = current.final_text
                        current.finished = True
                        current.timestamps["updated_at"] = now
                        current.timestamps["status_text"] = current.status_text
                        current.timestamps["finished_at"] = now
                        self._trace_task_status_locked(current, previous_status, "assistant.final")
                        publish_event = self._build_stream_event_locked(current, "assistant.final")
                        publish_done = self._build_stream_event_locked(current, "done")
                    elif event_name == "assistant.error":
                        if not current.first_packet_at:
                            current.first_packet_at = now
                        previous_status = current.status
                        current.status = TaskStatus.FAILED.value
                        current.status_text = "AI空闲"
                        current.error = str(event.get("error", "bridge error"))
                        current.finished = True
                        current.timestamps["updated_at"] = now
                        current.timestamps["status_text"] = current.status_text
                        current.timestamps["finished_at"] = now
                        self._trace_task_status_locked(current, previous_status, "assistant.error")
                        publish_event = self._build_stream_event_locked(current, "assistant.error")
                        publish_done = self._build_stream_event_locked(current, "done")
                if publish_event is not None:
                    self._publish_task_event(task_id, publish_event)
                if publish_done is not None:
                    self._publish_task_event(task_id, publish_done)

            response = self._bridge.stream_message(
                task.user_input,
                on_event=on_event,
                request_id=task.request_id,
            )
            with self._lock:
                current = self._tasks.get(task_id)
                if current is None or current.cancel_requested or current.finished:
                    return
                error_text = str(response.get("error", "")).strip()
                response_text = str(response.get("text", "")).strip()
                if error_text:
                    previous_status = current.status
                    current.status = TaskStatus.FAILED.value
                    current.error = error_text
                    current.status_text = "AI空闲"
                    current.finished = True
                    current.timestamps["updated_at"] = utc_now_iso()
                    current.timestamps["status_text"] = current.status_text
                    current.timestamps["finished_at"] = utc_now_iso()
                    self._trace_task_status_locked(current, previous_status, "stream_result_error")
                    publish_event = self._build_stream_event_locked(current, "assistant.error")
                else:
                    previous_status = current.status
                    current.status = TaskStatus.SUCCESS.value
                    current.stream_text = response_text or current.stream_text
                    current.final_text = current.stream_text
                    current.result = current.final_text
                    current.status_text = "AI空闲"
                    current.finished = True
                    current.timestamps["updated_at"] = utc_now_iso()
                    current.timestamps["status_text"] = current.status_text
                    current.timestamps["finished_at"] = utc_now_iso()
                    self._trace_task_status_locked(current, previous_status, "stream_result_final")
                    publish_event = self._build_stream_event_locked(current, "assistant.final")
                publish_done = self._build_stream_event_locked(current, "done")
            self._publish_task_event(task_id, publish_event)
            self._publish_task_event(task_id, publish_done)
        except Exception as exc:
            with self._lock:
                task = self._tasks.get(task_id)
                if task is None or task.finished:
                    return
                previous_status = task.status
                task.status = TaskStatus.FAILED.value
                task.error = str(exc)
                task.status_text = str(exc)
                task.finished = True
                task.timestamps["updated_at"] = utc_now_iso()
                task.timestamps["status_text"] = task.status_text
                task.timestamps["finished_at"] = utc_now_iso()
                self._trace_task_status_locked(task, previous_status, "task_exception")
                publish_event = self._build_stream_event_locked(task, "assistant.error")
                publish_done = self._build_stream_event_locked(task, "done")
            self._publish_task_event(task_id, publish_event)
            self._publish_task_event(task_id, publish_done)

    def _run_bridge_keepalive(self) -> None:
        from bridge.client import keep_bridge_alive

        keep_bridge_alive(self._bridge, self._settings)

    def _publish_task_event(self, task_id: str, event: dict) -> None:
        with self._lock:
            subscribers = list(self._task_subscribers.get(task_id, []))
        for subscriber in subscribers:
            subscriber.put(event)

    def _build_stream_snapshot_locked(self, task: TaskRecord) -> dict:
        if task.finished:
            if task.error:
                return self._build_stream_event_locked(task, "assistant.error")
            return self._build_stream_event_locked(task, "assistant.final")
        if task.stream_text:
            return self._build_stream_event_locked(task, "assistant.delta")
        return self._build_stream_event_locked(task, "status")

    def _build_stream_event_locked(self, task: TaskRecord, event_name: str) -> dict:
        return {
            "event": event_name,
            "taskId": task.task_id,
            "requestId": task.request_id,
            "sessionId": task.session_id,
            "sessionKey": task.session_key,
            "runId": task.run_id,
            "status": task.status,
            "statusText": task.status_text,
            "text": task.final_text or task.stream_text or task.result,
            "error": task.error,
            "finished": task.finished,
            "interrupted": task.cancel_requested,
            "firstPacketAt": task.first_packet_at,
            "firstDeltaAt": task.first_delta_at,
            "firstPacketMs": self._duration_ms(task.timestamps.get("started_at", ""), task.first_packet_at),
            "firstDeltaMs": self._duration_ms(task.timestamps.get("started_at", ""), task.first_delta_at),
            "totalMs": self._duration_ms(task.timestamps.get("started_at", ""), task.timestamps.get("finished_at", "")),
        }

    def _duration_ms(self, started_at: str, ended_at: str) -> int | None:
        if not started_at or not ended_at:
            return None
        try:
            started = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
            ended = datetime.fromisoformat(ended_at.replace("Z", "+00:00"))
        except ValueError:
            return None
        return int((ended - started).total_seconds() * 1000)
