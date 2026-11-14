# 开发摩擦记录

记录 `tessell-sheet-demo` 开发过程中真实撞到的问题、临时绕过方式与 framework 建议。
每条都对应一个已提交的 GitHub issue（链接在 README）。

环境：macOS arm64、Crystal 1.21.1、Retina scale=2。

**状态（2026-11-15 更新）**：Tessell v0.2.0 之后 25 个提交（`64eb5b1`）把
#19–#32 全部实现。demo 已迁移并删掉所有相关 workaround，`shard.yml` 用
`commit: 64eb5b1` 固定（尚无更新 tag）。每节末尾的「v0.2.0 落地」写明实际
采用的接口；「64eb5b1 落地」写明这一轮的替换。

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

## 64eb5b1 落地（v0.2.0 之后 25 个提交）

这一轮上游把 #19–#32 全做完了。迁移时撞到的破坏性变更与替换：

### 破坏性变更

| 变更 | 症状 | 处理 |
|---|---|---|
| `Kit::Painter#text` 新增 `font_id : Int32`，`Painter` 新增 abstract `image` | 直接编译失败（abstract method not implemented） | 两个都实现；`image` 显式 `raise`（见 #45） |
| `Painter#text` 的坐标改为**逻辑单位** | 我在 `text()` 里乘了一次 scale、`flush` 里又乘一次 → 文字放大 2 倍并整体偏移 | 命令保持逻辑单位，设备换算只在 `flush` 做 |
| `draw_text(batch_count:)` 是开区间上界 | 传增量（delta）→ 文字重影 | 传 `after`（`batch_count` 的绝对值） |
| `draw_text(clip:)` 要设备像素 | `DrawListPainter#push_clip` 已换算过，`flush` 再 `scale_rect` → 网格内容被裁到只剩开头几行 | 原样透传 `cmd.clip` |

第二条和第四条特别值得记：它们不会编译报错，只会让画面错得很像"框架 bug"。
我一度以为是上游布局回归，直到把 v0.2.0 的二进制跑出来逐张对比才定位到是自己的双重缩放。

### 删掉的 workaround

- **#21**：`GLPainter` 的 `@text_marks` / `@submitted_batches` 整组删除。`Render::DrawCmd`
  现在有 `text` / `font_size` / `font_id`（存进 `atlas_id`），`flush` 单遍遍历即可。
- **#20**：`SheetGrid` 的 `@last_click_ms` / `@last_click_row` / `@last_click_col`
  删除，改用 `Event#click_count`。额外保留一条约束：按下与释放必须在同一格，
  否则拖选收尾会被 Router 的 `click_count` 误判成双击。
- **#22**：`GLPainter#flush` 的参数类型从 `GL::GLBackend` 收窄回 `Render::Backend`。
- **#30**：窗口 resize / 跨 DPI 不再 `build_root` + `on_root_ready` 重建，
  改调 `Root#scale=`。`spec/grid_spec.cr` 有一条断言锁住「scale 变化后编辑态与
  焦点仍在」。

### 采用的接口

- **#19**：`TextBaseline.centered` 直接委托 `TextDrawing.middle_baseline`。
- **#31**：`SheetGrid` 的 `a11y_role` 改为 `Role::Grid`，并实现 `a11y_row` /
  `a11y_col` / `a11y_row_count` / `a11y_col_count` / `a11y_row_index_text` /
  `a11y_col_index_text` / `a11y_selected` / `a11y_active_cell` /
  `a11y_first_visible_index`。注意 `Root#refresh_a11y_meta` 读的是组件方法，
  不是 `emit` 里 `b.node` 的声明——两处必须一致，否则 a11y 树里仍是 `Group`。
- **#32**：`begin_edit` 显式设 `TextEditing#tabs = TabBehavior::Reject`。
- **#29**：`GLPainter` 接受 `font_id` 并持有 `Hash(Int32, TextRenderer)`。
  demo 仍是单 face（只有 `Arial Unicode`），所以实际只有 id 0；链路已就位。

## 仍然存在的缺口

这一轮迁移中新发现 3 条，全部已提 issue（附实测输出与最小复现）。

| Issue | 缺口 | demo 侧处理 |
|---|---|---|
| [#45](https://github.com/ShiningRay/tessell/issues/45) | `GLBackend` 完全没有外部纹理通道：`create_texture` 落到基类返回 0，`draw_draw_list` 的 `case` 里没有 `CmdKind::Image` 分支，命令走到 `else` 静默丢弃 | `GLPainter#image` 显式 `raise`，让"图没显示"立刻可见 |
| [#46](https://github.com/ShiningRay/tessell/issues/46) | `GLBackend#stats.submitted_quads` 被逐次 `draw_text` 清零（`draw_batches_all` / `draw_batches_with_dirty` 开头都 `= 0`），交错提交时帧统计只反映最后一次调用 | 无（只影响 F1 overlay 的读数）；实测帧末 `quads=10`，实际近 200 个字形四边形 |
| [#47](https://github.com/ShiningRay/tessell/issues/47) | 宿主不透传 `timestamp_ms` 时 `Router` 的双击判定恒为 false（`event.timestamp_ms > 0 && @last_up_ts > 0`），`click_count` 永远 1，且没有任何诊断 | `pump_events` 透传 SDL 的 `timestamp` 与 `repeat`（官方 `kit_sdl_host` 的指针事件已透传，但它的 `TEXTINPUT` 没有） |

### 顺带发现（未单开 issue）

- `examples/lib/kit_sdl_host.cr:489` 在改成 `App::Runner` 后仍打印 `frames=#{frames}`，
  `frames` 局部变量已不存在 → `examples/app_calculator.cr` 编译失败。
  替代应为 `runner.frame_count`。
- `examples/lib/kit_sdl_host.cr` 的 `GLPainter` 没有实现 `image`（`Painter` 新增
  的 abstract 方法），也没有把 `text()` 的命令载荷改成逻辑单位（它仍在 `text()`
  里 `* @scale` 再 `@draw.text(dx, dy, ..., px_size.to_f32)`）。#21 之后宿主应该
  让命令保持逻辑单位、在 `flush` 里换算一次——官方的单 face 示例宿主没跟上。
- `examples/lib/kit_sdl_host.cr` 的 `image` 缺失与 `frames` 变量同时修掉后
  （实测把 `frames` 换成 `runner.frame_count` 即可编译通过），`app_calculator`
  才能构建；两个问题叠加使示例集当前是坏的。

## 对上一轮的更正

上一版 friction-log 写的「`tools/lib/png.cr` 不在 shard require 路径」是**误判**。
`require "tessell/tools/lib/png"` 在 shard 消费者里可以正常工作（shard 会把整个仓库
放进 `lib/tessell/`，Crystal 的 require 解析能到 `tools/`）。demo 已删掉自带的
`src/sheet_demo/png.cr`，改回上游 `TessellPNG.write`，`--screenshot=x.png` 行为不变。

因为这次迁移把 #20/#21/#22/#24/#27/#31/#32 等全部落地，v0.2.0 版本里
「demo 侧对这些缺口的处理」那一整段绕过清单已经全部失效，本文件不再保留。
