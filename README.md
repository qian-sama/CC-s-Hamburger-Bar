# CC's Hamburger Bar

2D 像素风汉堡店经营游戏，使用 **Godot 4.6** + **GDScript** 独立开发。采用**主场景枢纽 + 多子场景**分区玩法：煎肉、组装、收银各自独立场景，通过交互区切换；全局状态由 Autoload 单例跨场景保持。

## 环境要求

- [Godot Engine 4.6](https://godotengine.org/)（项目 `config/features` 含 `4.6`）
- 操作系统：Windows / macOS / Linux

## 如何运行

1. 克隆仓库并用 Godot 4.6 打开项目目录
2. 主场景：`res://sceen/主场景.tscn`（已在 `project.godot` 中配置为启动场景）
3. 点击编辑器 **运行（F5）**

## 游戏玩法

### 一局流程

| 阶段 | 操作 |
|------|------|
| 开始前 | 按 **E** 开始新一局（清空收入与运行时数据） |
| 营业中 | 在主场景走动，进入各分区完成煎肉 → 组装 → 收银 |
| 结束 | 按 **X** 结束本局，查看本局累计收入 |

### 主场景（枢纽）

- **WASD** 移动角色
- 走进标有交互的区域，按 **E** 进入：煎肉区 / 组装区 / 收银区
- 从子场景返回时，角色会落回进入分区前在主场景的位置
- 按 **U** 打开/关闭全局**订单看板**（显示待做小票）

### 煎肉区

- 站在**冷藏区**按 **P**：在铁板第一个空槽放一块生肉（最多 8 槽，2 行 × 4 列）
- 肉饼在铁板上自动煎制，约每 **20 秒** 升一阶段：三分熟 → 七分熟 → 全熟 → 焦
- 站在**铁板取肉区**按 **I** / **O**：按玩家 X 坐标取**上排 / 下排**最近一列中**最靠上**的一块肉，送入**熟肉 FIFO 队列**（上限 8）
- 离开煎肉区后铁板仍在「离线」计时，返回时按离开时长补算熟度

### 组装区

- **O**：放底包 / 顶包（须先底后顶）
- **I**：从底部轮播选择食材并叠层（生菜、番茄、芝士等）；**肉饼**从熟肉队列**队首**取出（须 ≥ 三分熟）
- **P**：汉堡封顶且成品盘未满时，提交到**成品盘**（上限 6）
- **L**：重做当前案板（已消耗熟肉不返还）
- **E**：返回主场景

### 收银区

- 顾客随机刷客，沿路径：**进店 → 柜台点单 → 取餐排队 → 离开**
- 玩家进入**点单区**后，顾客身旁气泡逐层写出订单，并登记**订单小票**
- 在**取餐区**按 **P**：向取餐队**队首**顾客交付成品盘上的汉堡
- **评分**：对比订单层结构与交付汉堡（含肉饼熟度），基础价约 **$5–$10**，错漏扣款；完美匹配全额

---

## 游戏框架

### 架构总览

```
┌─────────────────────────────────────────────────────────┐
│  Autoload 层                                             │
│  GameState │ OrderBoard │ MoneyHUD │ GameFlow           │
└──────────────────────────┬──────────────────────────────┘
                           │ Signal / 直接调用
     ┌─────────────────────┼─────────────────────┐
     ▼                     ▼                     ▼
  主场景.tscn          grill_sceen.tscn      assemble.tscn
  (枢纽 + 玩家)         (煎肉)              (组装)
                           │
                      收银区.tscn
                      (顾客仅在本场景实例化)
```

### Autoload 职责

| 单例 | 脚本/场景 | 作用 |
|------|-----------|------|
| `GameState` | `sceen/game_state.gd` | 会话阶段、金钱、熟肉/成品 FIFO、案板、铁板快照、顾客与订单队列 |
| `OrderBoard` | `sceen/order_board_overlay.tscn` | 全局待做订单 UI |
| `MoneyHUD` | `sceen/money_hud.tscn` | 收入显示 |
| `GameFlow` | `sceen/game_flow_overlay.tscn` | 开局 / 结算全屏层 |

### 设计要点

- **单一数据源**：玩法数据集中在 `GameState`，分区场景负责表现与输入，避免多场景各存一份状态
- **事件驱动**：`cooked_patties_changed`、`order_tickets_changed`、`money_changed` 等 Signal 驱动 HUD 与子系统刷新
- **FIFO 队列**：熟肉、成品、进店队、取餐队、订单小票均为先入先出，交餐与组装对齐队首
- **场景切换持久化**：切换前由 `InteractZone` 触发保存；回到分区时从 `GameState` 恢复

### 目录结构（核心）

```
sceen/
├── game_state.gd          # 全局状态
├── interact_zone.gd       # 通用 E 键换场景
├── players.gd             # 玩家移动与交互
├── grill_work.gd          # 煎肉区逻辑
├── assemble_work.gd       # 组装区逻辑
├── cashier_work.gd        # 收银区逻辑
├── burger_stack.gd        # 案板叠层
├── patty.gd / grill_plate.gd
├── order_scoring.gd / order_generator.gd
├── 主场景.tscn
├── grill_sceen.tscn
├── assemble.tscn
└── 收银区.tscn
```

---

## 核心场景实现

### 1. 主场景 + 场景切换（`interact_zone.gd`）

- 各入口/出口挂 `Area2D` + `InteractZone`，`target_scene` 指向目标 `.tscn`
- 玩家 `CharacterBody2D` 进入区域后显示 **Press E**，在 `_unhandled_input` 中调用 `zone.interact(player)`
- 切换前：若在煎肉/组装场景，先调用 `save_grill_state_to_game()` / `save_assembly_state_to_game()`
- 进入分区时 `GameState.save_hub_return(position)`；回主场景时 `players.gd` 在 `_ready` 恢复坐标

```gdscript
# interact_zone.gd（流程摘要）
game_state.save_hub_return(player.global_position)
get_tree().change_scene_to_file(target_scene)
```

### 2. GameState 全局状态（`game_state.gd`）

**跨场景字段示例：**

| 数据 | 说明 |
|------|------|
| `cooked_patty_doneness_list` | 熟肉 FIFO，`take_next_cooked_patty()` 队首取出 |
| `finished_burgers` | 成品汉堡层数组的队列 |
| `assembly_plate_layers` | 组装案板半成品 |
| `grill_patty_snapshots` | 铁板每槽快照（槽位、煎制时间、熟度等） |
| `_customers` + `CustomerPhase` | 顾客状态机字典 |
| `_order_tickets` | 点单后的待做小票 FIFO |

**离线煎制：**

```text
离开煎肉区 → save_grill_patty_snapshots() + mark_grill_left()
回到煎肉区 → consume_grill_absent_seconds() → restore_grill_snapshots(..., absent_seconds)
```

`Patty` 在恢复时对 `cook_time` 加上离线秒数，继续推进熟度。

### 3. 煎肉区（`grill_sceen.tscn` + `grill_work.gd`）

- `GrillPlate`：8 个 `GrillSlot`，`find_first_empty_slot()` 放置，`take_topmost_in_column(row)` 按列取肉
- `Patty`：`State.ON_GRILL` 时每帧累加 `cook_time`，阶段边界 20s × n，发出 `became_ready` / `became_burnt`
- 取肉成功 → `GameState.push_cooked_patty(doneness)` → `CookedPattyHolder` 监听 Signal 刷新槽位显示
- 区域检测：`ColdStorage` / `GrillPickupZone` 的 `body_entered` 控制能否响应 P / I / O

### 4. 组装区（`assemble.tscn` + `assemble_work.gd`）

- `BurgerStack`：层数据 `{ type, doneness }`，规则为**底包 → 馅料（≤12）→ 顶包**
- 肉饼层调用 `GameState.take_next_cooked_patty()`，熟度低于三分熟则拒绝
- `IngredientCarousel` 轮播蔬菜；`try_add_ingredient` 失败时显示 CantDo 提示
- 离开场景：`assemble_work.save_assembly_state_to_game()` → `assembly_plate_layers`
- 进入场景：`restore_from_layers()` 重建案板精灵

### 5. 收银区（`收银区.tscn` + `cashier_work.gd`）

**顾客状态机（`GameState.CustomerPhase`）：**

```text
PENDING → WALKING_IN → AT_COUNTER → WALKING_PICKUP → WAITING_PICKUP → LEAVING
```

- `GameState` 负责刷客计时、`walk_in` / `pickup` 队列、柜台 `claim_counter`
- `cashier_work` 仅在本场景 spawn 顾客节点，监听 `customer_spawned` / `pickup_queue_changed`
- 点单：玩家进入 `OrderZone` → `CustomerOrderBubble` 逐层 reveal → `enqueue_pickup` + `register_order_ticket`
- 交餐：取餐区按 P → `deliver_to_front_pickup_customer()` → `OrderScoring.calculate_payment` → 更新 `player_money`

### 6. 评分模块（`order_scoring.gd`）

- 将订单与交付汉堡各层统计为 `(type, doneness)` 计数
- 肉饼要求熟度一致；蔬菜等只比 `type`
- 输出 `amount`、`perfect_match`、`error_count` 供 `MoneyHUD` 展示

---

## 操作一览

| 按键 | 主场景/通用 | 煎肉区 | 组装区 | 收银区 |
|------|-------------|--------|--------|--------|
| WASD | 移动 | — | — | — |
| E | 进入分区 / 开始一局 | — | 回主场景 | — |
| X | 结束一局 | — | — | — |
| U | 订单看板 | — | — | — |
| P | — | 冷藏上架 | 成品入库 | 取餐交付 |
| I | — | 取上排肉 | 加料 | — |
| O | — | 取下排肉 | 底/顶包 | — |
| L | — | — | 重做 | — |

---

## 素材与授权

- 像素素材位于 `游戏素材/`
- 代码仅供学习与交流展示；如需开源请自行补充 LICENSE

## 作者

陈实 — 天津大学

GitHub: [qian-sama/CC-s-Hamburger-Bar](https://github.com/qian-sama/CC-s-Hamburger-Bar)
