# QQPAL MVP 项目介绍

## 目录

1. MVP 目标
2. MVP 范围说明
3. MVP 核心链路
4. 项目目录结构说明
5. 各模块职责划分
6. 核心数据与协议边界
7. MVP 开发重点
8. MVP 验收标准
9. 后续扩展方向

---

## 一、MVP 目标

QQPAL 的 MVP 版本目标，不是一次性完成完整的全场景数字分身体系，而是先完成一条最小可演示主链路：

> **Godot 负责前端交互与展示 → 云主 Agent 负责与用户交流和任务决策 → Runtime 接收执行计划并进行本地编排 → OpenClaw 执行 → Runtime 汇总本地状态 → Godot 展示宠物状态与任务结果**

这一版重点验证三件事：

- **架构是否成立**：Godot、Runtime、云主 Agent、OpenClaw 能否顺利串起来
- **产品体验是否成立**：桌宠是否能真实承载任务输入、执行反馈与宠物状态联动
- **后续扩展是否成立**：目录结构和模块边界是否足够支撑后续加入手机端、智能硬件和更多 OpenClaw 版本

---

## 二、MVP 范围说明

当前 MVP 明确收敛为以下范围：

- 仅做 **PC 主链路**
- 仅做 **Godot 桌宠 / UI**
- 仅做 **本地 Runtime**
- 仅做 **云端主 Agent**
- 仅做 **1 个 OpenClaw / 龙虾引擎对接**
- 仅做 **1 个核心演示场景**

当前版本明确**不纳入 MVP 主范围**的内容包括：

- 手机端正式接入
- 智能语音硬件接入
- 多 OpenClaw 厂商兼容
- 云端执行主机体系
- 多用户高并发
- 社区素材系统
- 商业化后台与权限体系

换句话说，MVP 不是最终产品，而是 QQPAL 的第一版“可跑通、可演示、可继续迭代”的技术与产品底座。

---

## 三、MVP 核心链路

MVP 版本只围绕一条最小闭环展开：

```text
Godot桌宠
  -> 云主Agent
  -> Runtime
  -> OpenClaw

OpenClaw
  -> Runtime
  -> Godot桌宠
```

### 具体含义

- **Godot** 负责前台交互、宠物表现和结果展示
- **云主 Agent** 负责和用户交流、理解任务、决定是否需要执行
- **Runtime** 负责本地状态机、任务承接、排队调度、引擎监管与状态回传
- **OpenClaw** 负责真实执行桌面任务

### 链路补充说明

- 普通对话优先发生在 **Godot ↔ 云主 Agent**
- 只有涉及真实执行的任务，才会由云端下发到 **Runtime**
- Godot 与 Runtime 的本地通信主要用于读取本地执行状态、安装状态和执行进度

### 核心闭环结果

只要这条链路跑通，QQPAL 就完成了从“概念设计”到“产品雏形”的跨越。

---

## 四、项目目录结构说明

当前 MVP 建议采用如下目录结构：

```text
QQPAL/
├─ docs/
│  ├─ QQPAL项目介绍.MD
│  ├─ QQPAL开发时间表.MD
│  ├─ protocol.md
│  ├─ states.md
│  └─ scene.md
│
├─ godot-app/
│  ├─ project.godot
│  ├─ scenes/
│  │  ├─ main/
│  │  ├─ pets/
│  │  ├─ task_panel/
│  │  └─ install/
│  ├─ scripts-gd/
│  │  ├─ pet/
│  │  ├─ ui/
│  │  └─ pages/
│  ├─ scripts-cs/
│  │  ├─ bridge/
│  │  ├─ models/
│  │  └─ mapping/
│  ├─ assets/
│  │  ├─ pets/
│  │  ├─ icons/
│  │  └─ audio/
│  └─ themes/
│
├─ runtime-core/
│  ├─ src/
│  │  ├─ host/
│  │  ├─ api/
│  │  ├─ task/
│  │  ├─ state/
│  │  ├─ cloud/
│  │  ├─ engine/
│  │  ├─ monitor/
│  │  └─ installer/
│  ├─ config/
│  └─ tests/
│
├─ openclaw-adapter/
│  ├─ manifests/
│  ├─ client/
│  ├─ mapping/
│  └─ samples/
│
├─ cloud-agent/
│  ├─ api/
│  ├─ planner/
│  ├─ schemas/
│  ├─ storage/
│  └─ tests/
│
├─ shared/
│  ├─ schemas/
│  ├─ enums/
│  ├─ examples/
│  └─ README.md
│
└─ scripts/
   ├─ dev/
   ├─ build/
   └─ demo/
```

这个目录结构的核心思路是：

- **Godot 和 Runtime 平级**
- **OpenClaw 适配单独隔离**
- **共享协议单独集中**
- **文档优先，代码跟随**

这样既方便并行开发，也方便后期拆分与扩展。

---

## 五、各模块职责划分

## （一）docs

`docs/` 用来沉淀 MVP 阶段最重要的“先定义、后开发”内容。

### 主要职责

- 记录协议文档
- 记录状态枚举
- 记录演示场景
- 记录开发排期与项目介绍

### 价值

它是整个项目的“约束层”，避免 Godot、Runtime、云端三边各自开发后接口不一致。

---

## （二）godot-app

`godot-app/` 是桌宠与主应用 UI 的前台工程。

### 主要职责

- 提供桌宠界面与任务输入入口
- 展示宠物动画、任务状态、执行结果
- 承担安装引导页和主任务页面
- 通过桥接层与 Runtime 通信

### 内部结构说明

- `scenes/`：Godot 场景资源
- `scripts-gd/`：GDScript 编写的动画、UI 和本地接口调用逻辑
- `scripts-cs/`：预留目录，当前阶段不作为主路线
- `assets/`：宠物、美术、音效资源
- `themes/`：界面主题与样式

### 技术原则

- **动画、UI 和 Godot 侧接口调用统一优先用 GDScript**
- **Godot ↔ Runtime 当前统一采用本地 HTTP API**

---

## （三）runtime-core

`runtime-core/` 是整个 MVP 的本地中枢，也是系统主骨架。

### 主要职责

- 接收来自云主 Agent 的任务计划
- 管理本地任务状态机
- 根据执行器状态做任务排队、阻塞控制和调度
- 管理与 OpenClaw 的连接和调用
- 输出状态给 Godot
- 提供本地 API
- 管理安装与监控流程

### 内部结构说明

- `host/`：运行入口与宿主逻辑
- `api/`：Godot 本地调用接口
- `task/`：任务队列与流转逻辑
- `state/`：状态枚举与状态机
- `cloud/`：与云主 Agent 通信
- `engine/`：执行器接入
- `monitor/`：状态采集、心跳与监管
- `installer/`：OpenClaw 安装管理

### 项目地位

Runtime 是 MVP 里最先应当落地的主模块，因为它连接：

- Godot
- 云主 Agent
- OpenClaw

它是整个系统的中轴。

---

## （四）openclaw-adapter

`openclaw-adapter/` 用于隔离 OpenClaw/龙虾引擎的具体适配逻辑。

### 主要职责

- 封装引擎调用方式
- 管理引擎描述信息与 manifest
- 定义 worker 映射关系
- 提供对接样例

### 这样拆分的好处

- 避免 Runtime 直接绑死某一种引擎实现
- 后续便于替换不同厂商版本
- 有利于后续扩展多个引擎版本并存

---

## （五）cloud-agent

`cloud-agent/` 是云端主 Agent 的最小服务实现。

### 主要职责

- 接收任务请求
- 生成 task_id
- 调用大模型进行最小任务拆解
- 输出结构化执行计划
- 为 Runtime 提供可消费的任务数据

### MVP 原则

当前阶段它不追求复杂多 Agent 协作，而只需要做到：

- 能收任务
- 能拆任务
- 能把结果稳定返回

---

## （六）shared

`shared/` 是多模块共享的协议与结构定义目录。

### 主要职责

- 放任务 schema
- 放状态枚举
- 放事件结构
- 放示例请求/响应

### 价值

它让 Godot、Runtime、云主 Agent 三边围绕同一份协议工作，减少返工和字段漂移。

---

## （七）scripts

`scripts/` 是辅助脚本目录，不承载核心业务逻辑。

### 主要职责

- 本地开发脚本
- 构建脚本
- 演示辅助脚本

---

## 六、核心数据与协议边界

MVP 阶段必须优先定死三类内容：

### 1. 任务协议

至少包含：

- `task_id`
- `scene_type`
- `input`
- `plan`
- `status`
- `result`
- `error`

### 2. 状态枚举

至少包含：

- `idle`
- `planning`
- `running`
- `waiting_user`
- `success`
- `failed`

### 3. 宠物映射状态

至少包含：

- 待机
- 思考
- 忙碌
- 提示
- 成功
- 失败

MVP 阶段最重要的一点，是先让 Runtime 输出统一状态，再由 Godot 负责表现映射，而不是让 Godot 自己推测业务状态。

---

## 七、MVP 开发重点

围绕这个目录结构，MVP 开发重点可以收敛成下面几项：

| 优先级 | 模块 | 重点内容 |
| --- | --- | --- |
| P0 | runtime-core | 任务状态机、本地 API、引擎监管 |
| P0 | cloud-agent | 收任务、拆任务、回结构化计划 |
| P0 | godot-app | 主界面、任务输入、状态展示、宠物切换 |
| P1 | openclaw-adapter | 1 个真实引擎调用跑通 |
| P1 | shared | 协议和状态统一 |
| P2 | docs | 文档沉淀和排期同步 |

最关键的顺序是：

> **先定协议，再立 Runtime，再接 Godot 和云主 Agent，最后接真实 OpenClaw。**

---

## 八、MVP 验收标准

只要满足下面这些条件，就可以认为 QQPAL MVP 已经成立：

### 1. Godot 端

- 能输入任务
- 能展示任务状态
- 能看到宠物状态变化
- 能看到结果或失败提示

### 2. Runtime 端

- 能接收计划
- 能驱动状态流转
- 能调用 1 个 OpenClaw
- 能把结果回传给 Godot

### 3. 云端主 Agent

- 能创建任务
- 能返回 task_id
- 能输出结构化计划

### 4. OpenClaw 对接

- 能执行 1 个真实场景
- 能返回至少一类真实状态

---

## 九、后续扩展方向

这个 MVP 目录结构后续可以自然扩展：

- `mobile-app/`：手机端远程控制入口
- `smart-device/`：智能语音硬件入口
- `cloud-executor/`：云端执行节点
- `community/`：素材与宠物社区

也就是说，这一版目录结构虽然服务于 MVP，但并不是一次性目录，而是未来正式版本的基础骨架。

---

## 一句话总结

> 这份目录结构对应的 QQPAL MVP，本质上是一套以 `godot-app` 为前台、以 `runtime-core` 为本地中枢、以 `cloud-agent` 为任务拆解中心、以 `openclaw-adapter` 为执行适配层、以 `shared` 为统一协议层的最小可演示数字分身工程骨架。
