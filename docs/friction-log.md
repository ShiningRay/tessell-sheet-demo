# 开发摩擦记录

记录 `tessell-sheet-demo` 开发过程中真实撞到的问题、临时绕过方式与 framework 建议。
每条都对应一个已提交的 GitHub issue（链接在 README）。

环境：macOS arm64、Crystal 1.21.1、Retina scale=2。

**状态（2026-11-14 更新）**：Tessell 已发布 v0.2.0，下列 5 条全部在上游修复或补齐。
demo 已把临时绕过全部替换为正式 API，`shard.yml` 固定到 `tag: v0.2.0`。
每节末尾的「v0.2.0 落地」写明实际采用的接口与移除的 workaround。

| # | 主题 | 上游版本 | Issue |
|---|---|---|---|
| 1 | `Kit::Context` 把设备像素文本度量写回逻辑布局 | v0.2.0 已修 | [#14](https://github.com/ShiningRay/tessell/issues/14) |
| 2 | `Painter` 无 z-order 与文本 clip 契约 | v0.2.0 已修 | [#15](https://github.com/ShiningRay/tessell/issues/15) |
| 3 | `Root` 无条件消费 Tab | v0.2.0 已修 | [#16](https://github.com/ShiningRay/tessell/issues/16) |
| 4 | 无二维滚动 / 冻结表头 | v0.2.0 补 `ScrollModel` | [#17](https://github.com/ShiningRay/tessell/issues/17) |
| 5 | Crystal 语言/API 坑 | v0.2.0 已进文档 | [#18](https://github.com/ShiningRay/tessell/issues/18) |

## 1. DPI 度量单位（#14）

**当时的症状**：Retina 下所有文本宽度翻倍，右对齐数字超出单元格，`Text#truncate` 提前截断。
`Context#measure_text` 用设备字号测量，却把结果直接当逻辑单位用。

**当时的绕过**：宿主包一层 `LogicalTextMetrics`，把 `measure` 与 `line_height` 都除以 scale。

**v0.2.0 落地**：`Context#measure_text` / `line_height` / `text_metrics` 统一返回逻辑单位，
`max_width` 同步乘 scale 保证换行一致。demo 删除了整个 `LogicalTextMetrics` 类，
`CoreTextMetrics` 直接注入 `Root`。

## 2. Painter 层序（#15）

**当时的症状**：编辑单元格时原值文本盖住编辑器背景；滚动时半可见行文本越过 clip 画到行号列。

**当时的绕过**：编辑态跳过原值文本；只给完全可见的单元格/表头发文本。

**v0.2.0 落地**：契约写明「调用顺序即绘制顺序，clip 同时约束形状与文本」。
`draw_text` 增加 `from_batch` / `clip`，`draw_draw_list` 增加区间参数。
demo 宿主改为按 `CmdKind::Text` 标记切段提交（形状段 → 文本段 → 形状段），
删除两处可见性过滤，半可见单元格与表头标签恢复正常发命令，由后端 scissor 裁切。

## 3. Tab 归属（#16）

**当时的症状**：`Root#handle` 先处理 Tab 焦点环，`deliver` 收不到 Tab；
表格无法在单元格间用 Tab 移动，组件吃掉 Tab 后键盘也没有出口。

**当时的绕过**：`SheetApp#handle_app_event` 在 `Root` 之前拦截 Tab，另加 Escape 推焦点。

**v0.2.0 落地**：`Component#wants_tab?` 声明后 `Root` 先投递 Tab/Shift+Tab；
`Ctrl/Meta+Tab` 恒定留给焦点环。demo 给 `SheetGrid` 加 `wants_tab? = true`，
删除应用层 Tab 拦截，保留 Escape 作为符合电子表格习惯的额外出口。
spec 增加两条：Root 投递 Tab 后焦点仍留在网格；`Ctrl+Tab` 能切出。

## 4. 二维滚动（#17）

**当时的症状**：700 行 Grid 自己实现 `col_x`/`col_at_x`/`row_at_y`、滚动条 thumb、
可见区间与 clamp；`ScrollView` 单子组件模型无法承载冻结表头。

**v0.2.0 落地**：新增 `Kit::ScrollModel`（单轴数学：clamp、thumb、`visible_range`、
`offset_at`/`index_at`）。demo 的 x/y 各持一个实例：

- 行区间与行坐标直接用 `model_y.visible_range` / `offset_at` / `index_at`；
- 滚动条 thumb 用 `model.thumb(track_len)`，拖动用 `max_offset` 比例换算；
- clamp 交给 `offset=` 写入即 clamp，删掉手写 `clamp_scroll`。

列宽不等，x 轴只复用 offset/clamp，可见列仍单独扫描——这是 `ScrollModel`
按等高条目设计的边界，cookbook 也已写明二维用法。

## 5. Crystal 坑（#18）

- `initialize` 中用 `self` 初始化 ivar 被判定未初始化 → `uninitialized` workaround 仍在（语言层限制）；
- `extend` 不能做参数名 → `extending`；
- `Int32#to_char` 不存在 → `unsafe_chr`；
- `<=>` 返回 `Int32?` → 补 `|| 0`；
- `Rasterizer.new` 只收 `FtMeasurer` → 保留原始 `FtMeasurer` 给光栅化，缓存装饰器只给布局。

v0.2.0 把这些写进 `docs/usage.md` 的「写示例常撞的 Crystal 编译错误」，
并明确了 Rasterizer/FtMeasurer 分工；demo 代码注释同步指向该文档。

## 顺带采用的 v0.2.0 能力

- **`App::Runner`（#3）**：宿主帧循环改为 `runner.frames_limit` + `runner.advance`，
  删除手写 `frames` 计数退出。
- **PNG 直出（#9）**：`--screenshot=x.png` 直接写 PNG。注意 `tools/lib/png.cr`
  不在 shard 的 require 路径内（只发布 `src/`），demo 自带 `src/sheet_demo/png.cr`。
- **`DebugInfo` / F1 overlay（#11）**：宿主每帧塞 `DebugInfo.collect`，F1 查看
  帧耗时、quads、atlas、hover/focus。
- **`FontMetrics`（#6）**：删除 `-fs * 0.1` 经验基线，统一用 `TextBaseline.centered`
  → `ctx.text_metrics(size)`。
- **语义 grid token（#8）**：网格线改用 `ctx.render_theme.grid`。
- **`SoftwareBackend`（#10）**：新增 `spec/render_spec.cr`，在纯 CPU 后端断言
  选区填充、暗色 surface、活动单元格边框与画布底色。

## 仍然存在的缺口（v0.2.0 之后新记录）

- **`tools/` 不进 shard 路径**：`TessellPNG` 与 `TessellGolden` 只对仓库内的
  `examples/` 可用，外部消费者无法 `require "tessell/tools/lib/png"`。
  建议发布为 `src/tessell/tools/png.cr` 或独立 shard。
- **`Kit::Key` 未跟随 `Input::KeyCode` 扩展**：核心补了 `KeyT` / `Digit0-9` / `F1-F4`，
  但 `Kit::Key` 仍是旧的 19 个值，`Root#map_key` 也不会映射新键。
  表格的数字快速输入、F1 debug 之外的快捷键仍需宿主直接读原始 keysym。
- **`Root` 不转发按键时间戳/重复标志**：`Input::Event` 有了 `timestamp_ms` / `repeat`，
  `Root#to_kit` 没有传给 Kit 事件，Router 的双击判定能用，但组件拿不到。
- **多字体仍需应用自己拼装**：`FontStack` 给出 `pick`，但 atlas/renderer 每脸一份，
  宿主需自行循环创建；`Kit::Context` 只接受单个 `TextMetrics`。
