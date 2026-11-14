# 开发摩擦记录

记录 `tessell-sheet-demo` 开发过程中真实撞到的问题、临时绕过方式与 framework 建议。
每条都对应一个已提交的 GitHub issue（链接在 README）。

环境：macOS arm64、Crystal 1.21.1、Tessell main（SD2D/OpenGL 宿主，Retina scale=2）。

| # | 主题 | 影响 | Issue |
|---|---|---|---|
| 1 | `Kit::Context` 把设备像素文本度量写回逻辑布局 | DPR≠1 时所有文本宽度翻倍，按钮/单元格右对齐全部错位 | [#14](https://github.com/ShiningRay/tessell/issues/14) |
| 2 | `Painter` 无 z-order 与文本 clip 契约 | GL 文本总在所有形状之后绘制，编辑框背景被覆盖；滚动文本溢出表头 | [#15](https://github.com/ShiningRay/tessell/issues/15) |
| 3 | `Root` 无条件消费 Tab | 表格无法用 Tab 在单元格间移动，且没有键盘出口 | [#16](https://github.com/ShiningRay/tessell/issues/16) |
| 4 | 无二维滚动 / 冻结表头 | 700 行 Grid 自己实现坐标、滚动条与可见区间 | [#17](https://github.com/ShiningRay/tessell/issues/17) |
| 5 | Crystal 语言/API 坑 | 首跑编译失败 5 处，各花 5–20 分钟 | [#18](https://github.com/ShiningRay/tessell/issues/18) |

## 1. DPI 度量单位（#14）

`Context#measure_text` 把逻辑字号换成设备字号再交给 `TextMetrics`，但返回值直接进入布局。
Retina 下文本宽度翻倍、`Text#truncate` 提前截断。

临时方案：宿主包一层 `LogicalTextMetrics`，把 `measure` 和 `line_height` 都除以 scale。
每个 Tessell 应用都要写一次。建议框架提供适配器并统一单位契约。

## 2. Painter 层序（#15）

截图里能直接看到的两个 bug：

1. 编辑单元格时，原值文本盖住了编辑器背景与边框；
2. 滚动时半可见行的文本越过 `clip` 画到行号列和滚动条上。

原因是 `draw_draw_list` 丢弃 `CmdKind::Text`，宿主随后统一提交文本顶点；`push_clip` 只作用于形状。
临时方案：编辑态跳过原值文本；只给完全可见的单元格发文本。
代价：滚动边缘会缺半行字。这不是可接受的最终行为，issue 里给了逐条建议。

## 3. Tab 归属（#16）

`Root#handle` 先处理 Tab 焦点环，`deliver` 收不到 Tab。
临时方案：`SheetApp#handle_app_event` 在 `Root` 之前拦截 Tab，并额外用 Escape 把焦点推回工具栏，否则键盘出不去。
根因与 #13 第 4 点「focus scope」相同。

## 4. 二维滚动（#17）

`ScrollView` 是单子组件模型，冻结表头需要两套 viewport。
Grid 自己实现了 `col_x`/`col_at_x`/`row_at_y`、滚动条拖拽、可见区间与 clamp。
建议抽 `ScrollModel`，比直接做 DataGrid 更通用。

## 5. Crystal 坑（#18）

- `initialize` 中用 `self` 初始化 ivar 被判定未初始化 → `uninitialized` workaround；
- `extend` 不能做参数名；
- `Int32#to_char` 不存在，要用 `unsafe_chr`；
- `<=>` 返回 `Int32?`，赋给 `Int32` 要补 `|| 0`；
- `Rasterizer.new` 只收 `FtMeasurer`，缓存装饰器只能给布局用。

## 其他观察（未单独开 issue）

- `Rasterizer` 与布局 `Measurer` 必须共享同一份 FreeType 尺寸状态时，缓存装饰器会掩盖 hinting 差异；demo 保留原始 `FtMeasurer` 给光栅化。
- 没有公共的 PNG 输出，截图仍是 PPM + `ffmpeg` 转换（对应已有 #9）。
- atlas 同步仍要按 `used_pixels`/`evicted_total` 判断（对应已有 #1），demo 在宿主里重复了股票 demo 的 workaround。
- 没有 `Application`/`Runner`，宿主 700 行里大部分是 SDL/GL 样板（对应已有 #3）。
- 输入模型仍缺 `S/O/N/Y` 等键码（对应已有 #4）；demo 在 SDL 层读了原始 keysym 才实现 Cmd+S。
