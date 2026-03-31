# runtime-core 说明文档

## 一、定位

`runtime-core` 是 QQPAL 的本地运行时中枢。

它位于 `godot-app` 和后续真实执行能力之间，主要负责：

- 接收任务输入
- 维护任务状态机
- 输出统一状态给前端
- 作为后续对接 OpenClaw / 云主 Agent 的基础层

当前这版是 **最小可运行版本**，目标不是一次做全，而是先把本地 Runtime 的最小骨架搭起来，方便后续逐步替换 `MockTaskService`。

---

## 二、当前已实现内容

目前已经落地：

- `runtime-core/` 目录骨架
- Python 标准库实现的本地 HTTP 服务
- 3 个最小 API
- 1 个任务状态机 demo
- 1 个 smoke 测试脚本

当前实现特点：

- **无第三方依赖**
- **可直接本地运行**
- **适合作为 Godot 联调起点**

---

## 三、目录结构

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
  README.md
```

---

## 四、各文件作用

### 1. 启动入口

- `runtime-core/src/main.py`
  - 服务启动入口
  - 加载配置
  - 初始化 `TaskManager`
  - 创建 HTTP 服务并开始监听

### 2. 配置

- `runtime-core/src/config/settings.py`
  - 运行配置模型
  - 支持从环境变量读取 host、port、各阶段延迟

- `runtime-core/config/runtime.example.json`
  - 当前作为示例配置文件存在
  - 便于后续扩展成真实配置读取逻辑

### 3. API 层

- `runtime-core/src/api/server.py`
  - 定义 HTTP 路由
  - 处理请求与响应
  - 当前负责：
    - `GET /health`
    - `POST /tasks`
    - `GET /tasks/{task_id}`

### 4. 状态层

- `runtime-core/src/state/enums.py`
  - 定义任务状态枚举

- `runtime-core/src/state/machine.py`
  - 定义 demo 状态机
  - 当前流转为：

```text
talking -> planning -> running -> success / failed
```

### 5. 任务层

- `runtime-core/src/task/models.py`
  - 定义任务数据结构 `TaskRecord`
  - 管理 `task_id / user_input / status / result / error / timestamps`

- `runtime-core/src/task/manager.py`
  - 维护任务字典
  - 提交任务
  - 查询任务
  - 后台线程执行 demo 状态机

### 6. 测试层

- `runtime-core/tests/smoke_demo.py`
  - 启动临时服务
  - 调用 health
  - 创建任务
  - 轮询任务状态直到结束

---

## 五、当前 API 说明

### 1. 健康检查

**接口**

```text
GET /health
```

**用途**

- 检查 runtime-core 是否正常启动

**返回示例**

```json
{
  "service": "runtime-core",
  "status": "ok",
  "host": "127.0.0.1",
  "port": 8765,
  "demo_mode": true
}
```

---

### 2. 创建任务

**接口**

```text
POST /tasks
```

**请求示例**

```json
{
  "input": {
    "text": "打开网页并提交表单"
  }
}
```

也支持：

```json
{
  "user_input": "打开网页并提交表单"
}
```

**可选字段**

```json
{
  "should_fail": true
}
```

这个字段用于触发失败演示流程。

**返回示例**

```json
{
  "task_id": "task_xxxxx",
  "user_input": "打开网页并提交表单",
  "status": "talking",
  "result": "",
  "error": "",
  "timestamps": {
    "created_at": "2026-03-25T13:51:19.788586+00:00",
    "updated_at": "2026-03-25T13:51:19.788730+00:00",
    "status_text": "正在确认需求"
  }
}
```

---

### 3. 查询任务

**接口**

```text
GET /tasks/{task_id}
```

**用途**

- 获取当前任务状态
- 给 Godot 轮询或后续事件桥接使用

**返回字段**

- `task_id`
- `user_input`
- `status`
- `result`
- `error`
- `timestamps`

---

## 六、当前状态定义

当前已定义状态：

- `idle`
- `talking`
- `planning`
- `running`
- `waiting_user`
- `success`
- `failed`
- `paused`

其中这版 demo 实际会用到：

- `talking`
- `planning`
- `running`
- `success`
- `failed`

---

## 七、运行方式

在项目根目录执行：

```bash
py -3 runtime-core/src/main.py
```

启动后默认监听：

```text
http://127.0.0.1:8765
```

可通过环境变量覆盖：

- `QQPAL_RUNTIME_HOST`
- `QQPAL_RUNTIME_PORT`
- `QQPAL_RUNTIME_PLANNING_DELAY`
- `QQPAL_RUNTIME_RUNNING_DELAY`
- `QQPAL_RUNTIME_SUCCESS_DELAY`

---

## 八、验证方式

执行：

```bash
py -3 runtime-core/tests/smoke_demo.py
```

这个脚本会自动：

- 启动一个临时端口服务
- 调用 `/health`
- 调用 `/tasks`
- 轮询 `/tasks/{task_id}`
- 输出最终状态

---

## 九、这一版的价值

这一版的核心价值不是“功能完整”，而是：

- 把 Runtime 作为独立模块正式落地
- 让 Godot 后续有真实的本地服务可对接
- 把状态机、任务模型、接口边界先固定下来
- 为以后接入 OpenClaw 和云主 Agent 提供稳定入口

也就是说，它已经可以替代“纯文档阶段”，进入“可联调阶段”。

---

## 十、下一步建议

建议按下面顺序继续推进：

### 第一步：Godot 对接 runtime-core

让 `godot-app` 不再直接依赖 `MockTaskService`，而是：

- 提交输入到 `POST /tasks`
- 用 `GET /tasks/{task_id}` 获取状态

### 第二步：把状态同步打通

把 runtime-core 返回的：

- `planning`
- `running`
- `success`
- `failed`

映射到 Godot 当前桌宠状态和主窗口展示逻辑。

### 第三步：接入真实执行器

把 demo 状态机中的假执行过程，逐步替换成：

- OpenClaw 适配器
- 本地 worker
- 云主 Agent 下发计划

### 第四步：完善 Runtime 内部模块

继续补全：

- `engine/`
- `cloud/`
- `monitor/`
- `installer/`
- `host/`

---

## 十一、一句话总结

`runtime-core` 这一版已经是一个 **可启动、可提交任务、可查询状态、可跑状态机 demo 的最小本地 Runtime**，可以作为 QQPAL 后续联调与扩展的正式基础。
