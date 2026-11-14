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

全部已提为 issue（#19–#32，其中 #28 是上游同期自提）。每条都附了实测输出与最小复现。

| Issue | 缺口 |
|---|---|
| [#19](https://github.com/ShiningRay/tessell/issues/19) | 三套行高口径并存：`ctx.line_height`（1.25×）与 `font_metrics`/`measure`（FT metrics）不一致；`Text`/`Button`/`Input` 仍用 `fs*0.1` / `top+fs` 猜基线 |
| [#20](https://github.com/ShiningRay/tessell/issues/20) | `Kit::Event` 丢失输入语义：Router 有双击判定与 `timestamp_ms`/`repeat`，`Root#to_kit` 不透传 |
| [#21](https://github.com/ShiningRay/tessell/issues/21) | `DrawList` 的 Text 命令丢弃文本内容：宿主实现 #15 交错提交必须自建平行 batch 数组 |
| [#22](https://github.com/ShiningRay/tessell/issues/22) | `sync_atlas_dirty` 只在 `GLBackend` 上：`Backend` 抽象缺增量 atlas 同步 |
| [#23](https://github.com/ShiningRay/tessell/issues/23) | `Kit::Theme` ↔ `Render::Theme` 往返丢信息：`surface` 被 `bg` 覆盖 |
| [#24](https://github.com/ShiningRay/tessell/issues/24) | `Context` 文本测量缓存无上限无观测，`clear_text_cache` 无调用契约 |
| [#25](https://github.com/ShiningRay/tessell/issues/25) | `PaintListPainter` 与 `DrawListPainter` 的 clip 语义不一致（文本裁切断言误报通过） |
| [#26](https://github.com/ShiningRay/tessell/issues/26) | `Event::Kind::Focus` 存在但永不投递：`sync_focus` 只调 `on_focus_changed` |
| [#27](https://github.com/ShiningRay/tessell/issues/27) | `Kit::Key` 未跟随 `Input::KeyCode` 扩展：`Digit0-9`/`F1-F4`/`KeyT` 全落到 `Unknown` |
| [#28](https://github.com/ShiningRay/tessell/issues/28) | `Backend` 缺外部纹理通道：`DrawList` 无纹理四边形命令（上游同期自提，位图类控件无地基） |
| [#29](https://github.com/ShiningRay/tessell/issues/29) | 字体栈到不了组件层：`Painter#text` 无 `font_id`，`Kit::Text`/`Button` 无法声明粗体 |
| [#30](https://github.com/ShiningRay/tessell/issues/30) | `Root`/`Context` 的 `scale` 只读：DPI 变化只能重建 Root，焦点与编辑状态丢失 |
| [#31](https://github.com/ShiningRay/tessell/issues/31) | A11y 缺二维网格语义：`Role` 无 `Grid`/`GridCell`，`Meta` 无 row/col |
| [#32](https://github.com/ShiningRay/tessell/issues/32) | 编辑态缺 Tab 语义：`TextEditing` 允许 tab 但无制表位，`Input` 不处理 Tab |

### 对上一轮的更正

上一版 friction-log 写的「`tools/lib/png.cr` 不在 shard require 路径」是**误判**。
`require "tessell/tools/lib/png"` 在 shard 消费者里可以正常工作（shard 会把整个仓库
放进 `lib/tessell/`，Crystal 的 require 解析能到 `tools/`）。demo 已删掉自带的
`src/sheet_demo/png.cr`，改回上游 `TessellPNG.write`，`--screenshot=x.png` 行为不变。

demo 侧对这些缺口的处理：

- **#19**：`TextBaseline.centered` 用 `ctx.text_metrics` 计算基线（组件内已修正），
  但 `Kit::Text`/`Button`/`Input` 仍是框架内置的近似公式。
- **#20**：`SheetGrid` 自己维护 `@last_click_ms` 判断双击。
- **#21**：宿主维护 `@text_marks` 与 `@draw.list` 两份平行数组。
- **#22**：`GLPainter#flush` 绑定 `GL::GLBackend` 具体类型。
- **#23**：网格线读 `ctx.render_theme.grid`，其余色读 `ctx.theme.palette`，两者并存。
- **#24**：不在 demo 内清理（单表 200×26，文本集合有界）。
- **#25**：`spec/render_spec.cr` 改用 `DrawListPainter + SoftwareBackend`，不用 `PaintListPainter` 断言 clip。
- **#26**：依赖 `on_focus_changed`，不使用 `handle(Focus)`。
- **#27**：Cmd+S/O/N/Y 仍在 SDL 层读原始 keysym 后回调。
