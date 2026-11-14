# Changelog

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
