from enum import Enum


class TaskStatus(str, Enum):
    IDLE = "idle"
    TALKING = "talking"
    PLANNING = "planning"
    RUNNING = "running"
    WAITING_USER = "waiting_user"
    SUCCESS = "success"
    FAILED = "failed"
    PAUSED = "paused"
