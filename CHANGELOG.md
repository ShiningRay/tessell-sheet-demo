# Changelog

## Unreleased — upstream 64eb5b1（v0.2.0 之后 25 个提交）

上游把本仓提的 #19–#32 大部分实现了，demo 跟着迁移。没有新 tag，因此
`shard.yml` 用 `commit: 64eb5b1` 固定（可复现优先于跟随 `main`）。

### 破坏性变更适配
- `Kit::Painter#text` 新增 `font_id`，`Kit::Painter` 新增 abstract `image`：
  `GLPainter` 两个都实现。`image` 显式 `raise`——`GLBackend` 还没有外部纹理
  通道（[#45](https://github.com/ShiningRay/tessell/issues/45)），静默跳过会让
  「图没显示」变成难查的空现象。
- `Painter#text` 的坐标**是逻辑单位**。旧代码在 `text()` 里乘了 scale，`flush`
  又乘一次，导致双重缩放。现在命令保持逻辑单位，设备换算统一在 `flush` 做一次。
- `draw_text(batch_count:)` 是**开区间上界**，不是增量。传 delta 会重复绘制
  已有批次（表现为文字重影、整体位移）。
- `draw_text(clip:)` 要传**设备像素**：`DrawListPainter#push_clip` 已经把
  clip 换算过，`flush` 里不要再 `scale_rect` 一次。

### 移除的 workaround
- **#21**：删掉 `GLPainter` 的 `@text_marks` 平行数组。`Render::DrawCmd`
  现在直接携带 `text` / `font_size` / `font_id`（`atlas_id`），`flush` 单遍
  遍历命令列表即可。
- **#20**：删掉 `SheetGrid` 的 `@last_click_ms` / `@last_click_row` /
  `@last_click_col`。双击改用 `Event#click_count`（Router 判定），并额外要求
  按下与释放落在同一格，避免拖选收尾误入编辑。
- **#22**：`GLPainter#flush` 参数从 `GL::GLBackend` 收窄回 `Render::Backend`
  （`sync_atlas_dirty` 已在抽象上）。
- **#30**：窗口 resize / 跨 DPI 不再重建 `Root` 与 `SheetApp#build_root`，
  改调 `Root#scale=`；焦点、编辑态、滚动位置全部保留（新增 spec 锁住）。

### 采用的 v0.2.0+ 能力
- **#19**：`TextBaseline.centered` 直接委托 `TextDrawing.middle_baseline`，
  与内置 `Button` 同口径，不再维护第二份公式。
- **#31**：`SheetGrid` 的 a11y 角色改为 `Role::Grid`，并实现
  `a11y_row` / `a11y_col` / `a11y_row_count` / `a11y_col_count` /
  `a11y_row_index_text` / `a11y_col_index_text` / `a11y_selected` /
  `a11y_active_cell` / `a11y_first_visible_index`。
- **#32**：`begin_edit` 显式声明 `TabBehavior::Reject`，不依赖「insert 恰好
  拒绝 \t」的隐式行为。
- **#29**：`GLPainter` 接受 `font_id` 并持有 `Hash(Int32, TextRenderer)`，
  单 face 时只有 id 0。demo 目前仍是单 face，但宿主侧链路已就位。

### 宿主正确性修复（非框架缺口）
- SDL 事件的 `timestamp` / `repeat` 从未透传给 `Input::Event`，导致 Router 的
  双击判定在真机上永不成立（[#47](https://github.com/ShiningRay/tessell/issues/47)）。
  `pump_events` 现在转发 `timestamp_ms`（指针、滚轮、键盘、文本输入）与
  `repeat`。

### 新记录的上游缺口
- [#45](https://github.com/ShiningRay/tessell/issues/45)：`GLBackend` 没有实现
  外部纹理通道，`CmdKind::Image` 在 `draw_draw_list` 里落到 `else` 被静默吞掉。
- [#46](https://github.com/ShiningRay/tessell/issues/46)：`GLBackend` 的
  `submitted_quads` 被逐次 `draw_text` 清零，交错提交时帧统计只反映最后一次
  调用（实测 `quads=10`，实际近 200 个字形四边形）。
- [#47](https://github.com/ShiningRay/tessell/issues/47)：宿主不透传
  `timestamp_ms` 时 `click_count` 恒为 1，且没有诊断信号。

### 验证
- `crystal spec`：70 examples / 0 failures（新增双击、拖拽收尾、a11y 网格语义、
  Tab 拒绝、scale 保持编辑态）。
- macOS arm64 SDL2/OpenGL Retina scale=2 真实窗口：6 张截图逐张核对，与
  v0.2.0 基线一致。

## 0.2.0 (2026-11-14)

跟进 Tessell v0.2.0（上游修复了本仓提出的全部 5 个 issue）。

### 变更
- 依赖从 `branch: main`（9c28295）升级到 `tag: v0.2.0`（f807b17）。
- **#14 删除 `LogicalTextMetrics`**：`Context` 已统一返回逻辑单位，宿主直接注入
  `CoreTextMetrics`。
- **#15 宿主按命令序提交文本**：`GLPainter` 记录每次 `text()` 的 batch 边界，
  `flush` 以 `CmdKind::Text` 为界切段调用 `draw_draw_list` / `draw_text`；
  删除「只发完全可见单元格/表头」的 workaround。
- **#16 网格声明 `wants_tab?`**：删除 `SheetApp` 的 Tab 拦截；保留 Escape 出口；
  spec 覆盖 Tab 投递与 `Ctrl+Tab` 切出。
- **#17 采用 `Kit::ScrollModel`**：行区间、行坐标、滚动条 thumb、拖动、clamp 全部
  委托给 `model_x` / `model_y`。
- atlas 同步改用 `GLBackend#sync_atlas_dirty`（revision 驱动）。
- 宿主帧循环改 `App::Runner`；`--screenshot=x.png` 直出 PNG；F1 帧调试 overlay。
- 垂直居中改用 `ctx.text_metrics` 的 ascent/descent，删除 `-fs * 0.1` 经验基线。
- 网格线改用 `ctx.render_theme.grid` 语义 token。
- 新增 `spec/render_spec.cr`：`SoftwareBackend` 纯 CPU 像素断言。

### 新增
- `--scenario=debug` 截图场景与 F1 overlay 截图。
- `tools/export_assets.sh` 一键重生成 README 截图。
- PNG 截图直接使用上游 `require "tessell/tools/lib/png"`（shard 路径可达，已实测）。

### 向上游反馈
v0.2.0 之后又实测出 13 条缺口（#19–#32，其中 #28 为上游同期自提）：行高三套口径、
Kit 事件不转发双击/时间戳、DrawList Text 命令无文本内容、`sync_atlas_dirty`
不在 `Backend` 抽象、Theme 往返丢 `surface`、文本缓存无界、两个 Painter 的 clip
语义不一致、`Focus` 事件永不投递、`Kit::Key` 未跟随核心扩展、字体栈到不了组件层、
`scale` 只读导致 DPI 变化要重建 Root、A11y 缺二维网格语义、编辑态缺 Tab 语义。

### 验证
- `crystal spec`：60 examples / 0 failures。
- macOS arm64 SDL2/OpenGL Retina scale=2 真实窗口：6 张截图（默认/选区/编辑/
  滚动/深色/debug）逐张核对。
