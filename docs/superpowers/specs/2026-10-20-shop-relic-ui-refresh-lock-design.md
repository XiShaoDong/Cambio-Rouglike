# 商店刷新 / 锁定 + 饰品栏 UI（Phase 1）设计

日期：2026-10-20
分支：`agent/feature-game-rule`
状态：已与用户确认 UI 范围；饰品规则效果留待 Phase 2。

## 1. 背景与目标

当前商店（`Phase.SHOP`）是房间共享货架，最多展示 3 件固定价遗物，遗物池只有 2 件
（`Joker 变换`、`防守护盾`）。用户希望：

1. 商店固定 **2 个饰品位**。
2. 商店提供 **刷新**：每次消耗 10 货币，随机替换未锁定的饰品。
3. 每个货位可 **锁定 / 解锁**：锁定后刷新不动它，并且锁定状态可跨刷新、跨商店保留。
4. 商店改为 **每人独立货架**：每名玩家有自己的 2 个货位、自己的刷新与锁；别人看不到也买不走。
5. 新增 12 件饰品（先用占位字符表示），hover 显示名称与完整说明。
6. 3D 桌面每名玩家手牌左侧显示 **3 个饰品篮**，可 hover 查看说明。

本 Phase **只实现 UI、数据模型、服务器刷新/锁定协议和占位展示**；12 件饰品的实际规则效果
（减分、加视野、加分）在 Phase 2 逐条确认后实现。

## 2. 已确认决策

| 主题 | 决策 |
| --- | --- |
| 商店布局 | 保留当前上方不可购买的 `CARDS` 假卡区；下方 `RELICS` 区固定 2 个货位 |
| 刷新价格 | 每次 10 货币 |
| 刷新范围 | 只重掷该玩家**未锁定**的货位；已锁定货位保持原饰品与原货位 |
| 锁归属 | 每人独立；锁只影响自己的货架 |
| 锁的持久化 | 跨刷新、跳过购买、商店结束、下一局商店都保留；解锁或买走该件才清除 |
| 购买限制 | 每人每商店限购 1 件；买完即视为完成；另一格若锁定则保留到下次商店 |
| 遗物持有 | 每人最多 3 件；不同玩家可拥有同一饰品；同一玩家不能重复持有 |
| 3D 饰品篮 | 每名玩家手牌左侧 3 个篮子；显示占位字符；hover 弹出名称+说明；点击不触发动作 |
| 假卡区 | 先保留，后续再实现真实卡牌商品 |

## 3. 数据模型

### 3.1 `run_state`（跨局保留）

```gdscript
{
    "health": 2,
    "relic_slots": 3,
    "relics": {relic_id: def},              # 已出现的遗物定义目录（展示用）
    "relic_inventories": {seat: [relic_id, ...]},  # 每人最多 3 件，按获得顺序
    "shop_locks": {seat: {slot: relic_id}}, # slot 为 0/1；跨商店保留
    "mutator_ids": [],
    "enable_relics": false,
    "match_limit": 5,
}
```

- `relic_owners`（旧的单持有者模型）移除；`_is_relic_owner(seat, id)` 改为查询
  `relic_inventories[seat]`。
- 同一 `relic_id` 可以被多名玩家持有；`run.relics` 只存定义，不表示唯一持有。
- `shop_locks` 由购买/解锁/无效锁清理维护；不做每局清空。

### 3.2 `shop` 状态（仅 `Phase.SHOP`）

```gdscript
{
    "seats": {
        seat: {
            "offers": [
                {"index": 0, "relic_id": "...", "name": "...", "price": 50, "locked": false},
                {"index": 1, "relic_id": "...", "name": "...", "price": 50, "locked": false},
            ],
            "done": false,
        },
    },
    "done": {seat: true},   # 已完成（购买或跳过）的座位
}
```

- 服务器为每名存活玩家生成独立 2 个 offer。
- 快照按 viewer 投影：只把 viewer 自己的 offers 放进 `shop.offers`，不下发其他玩家货架。
- `shop_result` 保留为公开购买广播；key 改为 `"<seat>_<slot>"`，避免不同玩家同 slot 冲突。

### 3.3 快照字段

对局快照新增/调整：

```text
shop?: {
    offers: [{index, id, name, price, locked}],  // 仅 viewer 自己的货架
    done: SeatId[],
    refresh_cost: Integer,
    can_refresh: Boolean,
}
players[]: {
    ...
    relics: [String, String, String],  // 固定 3 格；空槽为 ""
}
```

- `players[].relics` 为公开信息，供 2D 遗物栏与 3D 饰品篮使用。
- 服务器内部 offer 字段名用 `relic_id`；快照对客户端沿用 `id`（与现有 `shop.offers` 一致）。
- `protected_slot` 仍保留；护盾消耗后从 `relic_inventories` 移除，2D 栏可按
  `protected_slot` 显示临时护盾状态（沿用现有行为）。
- `run.relics` 可继续下发定义目录；`run.relic_inventories` 不强制公开（用
  `players[].relics` 即可）。

## 4. 服务器协议

### 4.1 新 RPC

| 请求 | 载荷 | 合法阶段 | 校验 |
| --- | --- | --- | --- |
| `shop_refresh` | `{action_id}` | `SHOP` | 存活、未完成、货币 ≥ 10、至少 1 个未锁货位、遗物栏未满 |
| `shop_lock` | `{slot, locked, action_id}` | `SHOP` | 存活、未完成、slot ∈ {0,1}、该货位存在且未售出 |

错误码：

- 货币不足 → `INVALID_AMOUNT`
- 无未锁货位 / 遗物栏已满 → 新错误码 `SHOP_REFRESH_UNAVAILABLE`（追加到枚举末尾，保持既有值不变）
- 非法货位 / 已完成 → `INVALID_SLOT` / `DUPLICATE_OR_EXPIRED_ACTION`

### 4.2 刷新流程

1. 校验并扣 10 货币。
2. 对每个未锁货位：从遗物池随机取一个**未被该玩家持有、未锁定、未出现在另一货位**的饰品。
3. 锁定货位保持不变；`shop_locks` 不变。
4. 广播快照。

### 4.3 锁定流程

1. 校验后写入/清除 `run_state.shop_locks[seat][slot]`。
2. 不扣钱，不改变 offer。
3. 广播快照。

### 4.4 购买 / 跳过

- 购买：从自己的 `offers[slot]` 校验价格、遗物栏未满、未重复持有；扣款、加入
  `relic_inventories`、清该槽锁、标记 `done`、写 `shop_result`。
- 跳过：标记 `done`，**不清锁**。
- 全员 `done` 后调用 `_deal_next_match()`。
- 把末不进商店的既有规则不变。

### 4.5 商店开启

`_start_shop()`：

1. 清理无效锁：饰品不存在，或该饰品已被该玩家持有。**遗物栏已满不清锁**（锁按用户要求保留；
   只是购买时因栏位满而禁用）。
2. 对每名存活玩家、每个 slot：
   - 有有效锁 → 使用锁定的饰品，`locked=true`。
   - 否则随机一个未持有、未在另一格、未锁定的饰品。
3. 生成 `shop.seats`，广播。

## 5. 饰品定义（14 件）

现有 2 件保留；新增 12 件。价格先统一 `RELIC_PRICE = 50`，Phase 2 可调整。
每件定义包含：`id / name / desc / price / glyph / color / category`。

| id | 名称 | 占位字符 | 说明（Phase 1 tooltip 文案） |
| --- | --- | --- | --- |
| `relic_joker_transform` | Joker 变换 | `J` | 抽到 Joker 时可变换为任意牌（未变换时 Joker +2 分） |
| `relic_guard_shield` | 防守护盾 | `◇` | 下一局随机保护一格，免疫贴牌与交换 |
| `relic_tax_hand` | 手牌税 | `-1` | 手牌大于 4 张时，每张牌 -1 分（负分牌不受影响，最低到 0） |
| `relic_four_suits` | 四花色压制 | `4` | 手牌包含四个花色时，每张牌 -2 分（负分牌不受影响，最低到 0） |
| `relic_odd_hand` | 奇数惩罚 | `-6` | 手牌数量为奇数时，总分 -6 |
| `relic_duplicate` | 重复折半 | `/1.5` | 手牌中有相同点数的牌时，总分 ÷1.5 |
| `relic_triple` | 三张相同 | `/2` | 手牌中有三张或以上相同点数的牌时，总分 ÷2，可与重复折半叠加 |
| `relic_peek_reduce` | 窥视削弱 | `7` | 使用 7/8 查看自己的牌时，可使被查看的牌 -1 分（可降到负分，本局有效） |
| `relic_peek_flex` | 视野互换 | `<>` | 7/8 可以当 9/10 用（看别人），9/10 可以当 7/8 用（看自己） |
| `relic_odd_peek` | 奇数视野 | `ODD` | 每回合限一次：从抽牌堆抽到无能力的奇数牌时，可选择当作 7/8 查看自己一张 |
| `relic_even_peek` | 偶数视野 | `EVEN` | 每回合限一次：从抽牌堆抽到无能力的偶数牌时，可选择当作 9/10 查看别人一张 |
| `relic_slap_bonus` | 贴牌加成 | `+3` | 每回合限一次：成功贴其他玩家的牌后，交给对方的牌 +3 分（本局有效） |
| `relic_jack_bonus` | J 交换加成 | `+2` | 每回合限一次：使用 J 交换时，交给对方的牌 +2 分（本局有效） |
| `relic_peek_bonus` | 窥视加成 | `+1` | 每回合限一次：使用 9/10 查看别人的牌时，可使被查看的牌 +1 分（本局有效） |

> Phase 2 仍需确认：负数下限、除法取整、每回合计数重置时机、J/Q 与 6 传递的交互等；
> 这些不影响 Phase 1 的 UI 占位与说明展示。

## 6. 2D 商店 UI

保留现有 `ShopPanel` 场景骨架：

- `Title`：`SHOP`
- `CardsLabel` + `CardsRow`：保留假卡区
- `RelicsLabel` + `RelicsRow`：改为 2 个饰品位
- `Bottom`：`Currency` + `Spacer` + `Refresh` + `Leave`

每个饰品位：

- 占位图标：复用/扩展 `RelicIcon`，支持按定义显示字符。
- 名称、价格。
- `购买` 按钮：货币不足/已购买/已完成/遗物栏满/已持有 → 禁用并显示原因。
- `锁定` / `解锁` 按钮：已完成 → 禁用。
- 整个 slot 与名称/图标设置 `tooltip_text = 名称\n说明\n状态`。

底部 `Refresh`：

- 文本 `刷新 $10`。
- 禁用条件：已完成、货币 <10、两格都锁、遗物栏已满。
- `tooltip_text` 说明禁用原因。
- 点击调用 `GameState.request_shop_refresh(action_id)`。

`ShopPanel.setup()` 增加 `on_refresh`、`on_lock` 回调；`main.gd` 增加
`_on_shop_refresh()`、`_on_shop_lock(slot, locked)`。

## 7. 2D 遗物栏

`RelicBar` 改为读取 `players[].relics`（固定 3 格）：

- 每格显示占位字符 + 颜色；空槽显示空样式。
- tooltip 显示名称/说明/状态。
- 护盾：若 `protected_slot >= 0` 且该玩家当前没有护盾图标，可额外显示一个临时护盾状态
  （沿用现有“生效中”提示）。
- 计数改为 `持有数/3`。

## 8. 3D 饰品篮

### 8.1 节点与布局

- 每席 `Seats/SeatN` 下新增 `RelicBaskets`（由 `Table3dView` 动态创建）。
- 3 个篮子沿本地 Z 排开，放在本地 +X（该玩家视角的左手边），桌面高度：
  - `x = 1.15`
  - `z = -0.55 / 0.0 / +0.55`
  - `y = Table3dLayout.TABLE_HEIGHT + 0.03`
- 篮子视觉：小圆盘/浅碗 + 占位字符 `Label3D`（billboard，始终朝相机）。
- 空槽：低透明度圆环 + 无字符或 `·`。
- 拾取：`Area3D` + `BoxShape3D`，`PICK_MASK` 层，meta
  `{"kind": "relic", "seat": seat, "slot": i}`。
- 篮子不阻挡卡牌点击；点击 `relic` pick 不执行动作。

### 8.2 hover

- `Table3dView` 识别 `kind == "relic"`，记录悬停篮子并高亮圆环。
- 新增 `hovered_relic()` / `hovered_relic_screen_rect(cam)`。
- `main._update_relic_tooltip()` 用现有 `CardTooltip` 显示：
  `名称\n说明`；空槽显示 `空遗物位`。
- 与卡牌 tooltip 互斥：命中篮子时优先显示饰品说明。

## 9. 测试

更新/新增 headless 测试：

- `tests/verify_shop.gd`
  - 每人独立 2 个 offer。
  - 刷新扣 10；只重掷未锁货位；锁跨刷新保留。
  - 购买清锁、加入个人遗物栏、标记完成。
  - 全员完成后开下一局。
  - 货币不足 / 两格全锁 / 遗物栏满的拒绝。
- `tests/verify_relic_ui.gd`（新增）
  - 14 件定义、唯一 id、占位字符非空、说明非空。
  - `RelicBar` 固定 3 格、读取 `players[].relics`、tooltip 文本。
  - `ShopPanel` 2 个饰品位、刷新/锁定按钮状态与 hover 文本。
- `tests/verify_table3d_relics.gd`（新增）
  - 每席 3 个篮子节点、位置在本地 +X、空/非空状态。
  - 悬停 pick 返回 `kind=relic` 与正确 seat/slot。
  - tooltip 文本来自定义。
- 回归：`verify_relics` 改用 `relic_inventories`；`verify_board3d` 的 shop 状态适配新快照。

## 10. 非目标（Phase 1）

- 不实现 12 件饰品的实际减分/加分/视野效果。
- 不做真实卡牌商品。
- 不做 3D 篮子点击购买/解锁（锁定只在商店 2D UI 操作）。
- 不改贴牌、Kongbaya、系列赛、经济规则。

## 11. Phase 2 待确认清单

1. 奇数/偶数牌的具体范围：A/3/5/K 为奇数，2/4/6 为偶数；Joker 是否排除。
2. “每回合限一次”的回合边界：按 `turn_index` 还是按每名玩家自己的回合；跨局是否重置。
3. 7/8 减分与 9/10 加分的可选按钮交互与动画。
4. 贴牌 +3 / J +2 的数值写回方式与揭示一致性。
5. 四花色是否要求 4 种标准花色（Joker 红/黑不计）。
6. 多个减分饰品的最终公式与向下取整（已初步确认为：每张→求和→-6→除法→floor）。
