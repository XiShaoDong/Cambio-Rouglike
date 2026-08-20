# KONG UI 主题规范

> **本文档职责**：主题令牌（dark/light）规范，**给开发者**。对应实现 `scripts/ui/ui_theme.gd`。Agent 需改 UI 配色时参考。

状态：v1（dark/light 双主题已接入）  
关联：[light_theme.css](light_theme.css)（浅色配色来源）、`scripts/ui/ui_theme.gd`

## 架构原则（CSS 风格）

UI 代码**不得硬编码颜色**。所有颜色、样式通过 autoload 单例 `UITheme` 读取，结构与表现分离：

```
main.gd（HTML 角色：节点/布局）  →  UITheme.color("token")（CSS 角色：样式）
```

- 切主题：`UITheme.switch_theme("dark" | "light")`（运行时生效）
- 读颜色：`UITheme.color("bg_table")`
- 当前主题：`UITheme.current`
- 所有主题定义在 `scripts/ui/ui_theme.gd` 的 `TOKENS` 字典

## 令牌清单

### 背景层级

| 令牌 | dark | light | 用途 |
| --- | --- | --- | --- |
| `bg_table` | `10151f` | `EDE6D6` | 桌面背景 |
| `bg_surface` | `22303f` | `FFFDF8` | 卡牌背面 / 主面板 |
| `bg_surface_alt` | `2a3140` | `F7F1E4` | 次级面板 |
| `bg_elevated` | `1c2633` | `FFFFFF` | 弹窗 / 浮层 |

### 文字

| 令牌 | dark | light | 用途 |
| --- | --- | --- | --- |
| `text_primary` | `e9effa` | `3A362E` | 主文字 |
| `text_secondary` | `aebbd0` | `8B8577` | 次要说明 |
| `text_muted` | `8899aa` | `B5AF9E` | 禁用 / 占位 |
| `text_inverse` | `10151f` | `FFFDF8` | 彩色按钮上的文字 |
| `text_on_card` | `1a2230` | `3A362E` | 卡牌深色文字 |

### 边框 / 强调 / 语义

| 令牌 | dark | light | 用途 |
| --- | --- | --- | --- |
| `border` | `c9d1dc` | `E3DBC8` | 卡牌边框 |
| `border_strong` | `8b96a8` | `CFC5AC` | 强边框 |
| `accent` | `f6d77a` | `D9714F` | 强调色（铃铛/提示/高亮） |
| `accent_soft` | `f6d77a` 35% | `FBE3D8` | 强调浅底 |
| `accent_hover` | `e6c45e` | `C4623F` | 强调 hover |
| `highlight_glow` | `f6d77a` | `D9714F` | 卡牌高亮发光 |
| `success` | `87d9a1` | `7A9B6E` | 成功（Ready/贴中） |
| `danger` | `ff7b7b` | `C1604F` | 危险（铃铛/贴错） |
| `warning` | `f6d77a` | `D9A441` | 警告 |
| `info` | `aebbd0` | `8B8577` | 信息 |

### 玩家标识

| 令牌 | dark | light | 用途 |
| --- | --- | --- | --- |
| `player_self_bg` | `f6d77a` 35% | `D9714F` 30% | 当前玩家名字背景 |
| `player_other_bg` | `8899aa` 25% | `8B8577` 20% | 其他玩家名字背景 |
| `player_self_text` | `ffe9a8` | `3A362E` | 当前玩家名字文字 |
| `player_other_text` | `c9d4e0` | `6f6a5e` | 其他玩家名字文字 |

### 卡牌

| 令牌 | dark | light | 用途 |
| --- | --- | --- | --- |
| `card_face_bg` | `f5f6f8` | `FFFDF8` | 牌面背景 |
| `card_back_bg` | `22303f` | `D9714F` | 牌背背景 |
| `card_back_border` | `ffffff` | `C4623F` | 牌背边框（含弃牌堆虚线） |
| `card_border` | `c9d1dc` | `E3DBC8` | 牌面边框 |
| `card_rank_red` | `c0392b` | `B04A36` | 红牌点数/花色 |
| `card_rank_black` | `1a2230` | `3A362E` | 黑牌点数/花色 |
| `card_value` | `4a5568` | `8B8577` | 右下角分值 |
| `card_shadow` | 黑 35% | 暖棕 15% | 卡牌阴影 |

## 新增令牌规则

1. 新颜色必须先加令牌（dark + light 各一份），再在代码中使用。
2. 令牌命名与 `light_theme.css` 变量对齐（bg_*/text_*/card_*）。
3. 不允许在 `main.gd` 出现新的 `Color("...")` 字面量。

## 调试快捷键

| 键 | 功能 |
| --- | --- |
| `F12` | 切换布局调试：所有容器半透明彩色边框（不同层级不同色） |
| `T` | 切换 dark / light 主题 |
