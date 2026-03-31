# runtime-core

QQPAL 的本地运行时中枢最小实现。

当前版本包含：

- 目录骨架
- Python 最小服务
- 3 个本地 API
- 1 个任务状态机 demo

目录结构：

```text
runtime-core/
  config/
    runtime.example.json
  src/
    api/
      server.py
    cloud/
      .gitkeep
    config/
      settings.py
    engine/
      .gitkeep
    host/
      .gitkeep
    installer/
      .gitkeep
    monitor/
      .gitkeep
    state/
      enums.py
      machine.py
    task/
      manager.py
      models.py
    main.py
  tests/
    smoke_demo.py
```

API：

- `GET /health`
- `POST /tasks`
- `GET /tasks/{task_id}`

请求示例：

```json
{
  "input": {
    "text": "打开网页并提交表单"
  }
}
```

启动：

```bash
py -3 runtime-core/src/main.py
```

验证：

```bash
py -3 runtime-core/tests/smoke_demo.py
```
