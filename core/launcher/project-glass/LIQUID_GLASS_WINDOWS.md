# Windows 液态玻璃

## 当前窗口与侧栏修正

- 窗口、卡片封面和实例缩略图使用 `ContinuousClip.qml`：三次超椭圆的连续曲线，
  shader 按物理像素导数计算边缘覆盖率，曲线外的 alpha 严格归零，不再阈值化贴图遮罩。
- 红绿灯采用提供的 macOS 27 Sketch 中 `Titlebars/Light/Window Controls/Standard/Active`
  的几何尺寸：直径 14 pt，间隔 9 pt，中心距 23 pt，三个按钮共享水平中线。
- Windows 侧栏整体继续使用取样的液态玻璃。`SidebarGlow.qml` 在其右缘额外叠加少量
  内容颜色，保留对应的纵向位置，颜色向左平滑归零；高精度中间纹理和轻微抖动减轻色带。
  “Glow reach from right edge” 控制范围（默认 48%，限制 20–65%），采样宽度、
  柔和度、饱和度和强度分别调整；参数仍随 GlassTuning JSON 保存。
- 紧凑顶部导航使用 `GlassNavigation.qml` 的单个选中胶囊，接入 Glass Lab 的
  按下放大、拖动拉伸和松手吸附回弹；松手才切页，减少动态效果时只禁用形变与回弹。
- 下载分类使用同一液态玻璃 shader 的平滑融合距离函数；按住按钮时，按钮放大并与相邻
  按钮融合，松开后复原。“Button fusion”和“Fusion distance”也可从调试器 JSON 导入。
- 下载列表在窗口范围内延伸，工具栏位于可采样列表的独立浮层。搜索控件使用单层展开
  胶囊，排序与缩放工具位于下面的独立工具条。

构建后可用 Qt 的 `qmltestrunner -input launcher/project-glass/tests/ui`（在 core 目录）
运行像素覆盖、右缘光晕及真实鼠标拖动测试。测试使用 build-win11 中已编译的 shader；
`QSG_RHI_BACKEND=d3d11`，分别以 `QT_SCALE_FACTOR=1`、`1.25`、`2` 验证不同 DPI。
后文记录了此前实现；与上述不同的窗口遮罩和侧栏光晕方式以本节为准。

macOS 上由 AppKit `NSGlassEffectView` 绘制的元素，在 Windows 上改用
`liquid glass test` 调试器里的同一套渲染器：`LiquidGlass.qml` + `shaders/liquidglass.frag`。
调试器直接读取这两个文件，因此在调试器里改 shader 或调参，看到的就是启动器的效果。
macOS 路径不变；其他平台仍使用原有的 QML 回退外观。

## 覆盖范围

`GlassSurface` 是与 `Rectangle` 兼容的表面组件（`color` / `border` / `radius` / `gradient`）。
Windows 上会隐藏原填充，改为绘制 LiquidGlass；文字和交互仍在原控件上。

| macOS 原生玻璃 | Windows |
| --- | --- |
| 顶部导航栏、选中胶囊 | `topBar`，选中页签 |
| 侧边栏及选中行、选择器、头像 | 侧栏背景，`SidebarControl`（规则与 AppKit 相同：选中行或 panel/account/avatar/field） |
| 播放条、Launch 按钮、实例选择 | `bottomDock`、Launch（强调色）、`instancePicker` 及选中行 |
| 搜索按钮/面板、账号按钮、Groups、Done resizing | 对应 `GlassPane` |
| 账号菜单与账号弹窗、选择器弹出菜单 | `accountGlassControl` 控件，弹窗背景 |
| 下载/版本行、Download 按钮、分类、编辑器面板 | `editorGlassControl` 控件，`EditorGlassPane` |
| Quick Download 卡片 | 未安装卡片（已安装卡片被封面完全覆盖，不加玻璃） |

不使用玻璃的部分与 AppKit 保持一致：`content` / `scrollEdge*` 角色（macOS 上是 NSVisualEffectView），
原生开关（Offline），以及位于另一个窗口中的 `Popup.Window`。Windows 上账号相关的对话框
改为窗口内弹出层，以便取样。右键菜单仍使用 Qt 默认样式。

## 开关与滑块

`GlassSwitch` / `GlassSlider` 照搬调试器的玻璃开关和滑块，替换启动器内全部 `Switch` / `Slider`
（含账号菜单的 Offline 开关；macOS 原生路径仍由 AppKit 的 NSSwitch 绘制）。

- 开关：64×28 灰/绿胶囊轨道，白色胶囊滑块 40×24；按下放大到 56×39 并过渡为凸透镜玻璃，
  松开后 OutBack 回弹。点击、拖动、Space/Enter 由 Qt `Switch` 处理。
- 滑块：6 pt 轨道，强调色填充，白色横向胶囊 40×30，按下 50×36 并变为玻璃；`thumbScale`
  用于搜索栏的缩放滑块。手柄占位尺寸固定，取值映射与 Qt `Slider` 一致。
- 按下时的玻璃只取样"壁纸 + 该控件轨道"的小合成纹理，手柄自身不进入纹理；松开后停止取样。
- 减少动态效果时不放大、不回弹；关闭液态玻璃或材质时，手柄保持白色胶囊。

## 窗口外观

Windows 11 的 DWM 只提供 8 px / 4 px / 直角三种窗口圆角，无法设置其他数值。为与 macOS 27
一致（圆角 24 pt、左上角红绿灯），主窗口在 Windows 上以 `FramelessWindowHint` 创建（Qt
因此用逐像素 alpha 合成），`Frontend.cpp` 的 `WindowsChrome` 随后：

- 恢复 `WS_THICKFRAME | WS_CAPTION` 等样式，`WM_NCCALCSIZE` 让整个窗口都是客户区：原生阴影、
  拖边调整大小（`WM_NCHITTEST`，6 px）、贴靠和最大化保留；最大化时内缩边框，不超出屏幕。
- 关闭 DWM 圆角和 1 px 边框线（否则会沿方形边界描边），把框架扩展到整个客户区。
- QML：`contentItem` 以 24 pt 圆角遮罩（最大化/全屏时为 0），左上角绘制关闭/最小化/缩放按钮，
  窗口失活时变灰、悬停显示 × − +。顶部拖动条仍负责移动和双击最大化。

代价：最大化按钮悬停弹出的贴靠布局菜单不再出现（拖到屏幕边缘贴靠仍可用）。macOS 不受影响。

## 侧栏

- 侧栏（含底部账号区）的玻璃比播放条、顶部导航更模糊：雾化 = 调好的雾化 + `sidebarFrost`
  （默认 0.3）。只要侧栏可见，就会启用内容场景的模糊纹理。
- Apple Music 式光晕：取侧栏右边 240 pt 宽的内容，以 16×(高/16) 的极低分辨率采样，
  再做三倍半径模糊、提高饱和度并水平镜像，使最近的内容贴着侧栏边缘；从右向左淡出到 35%。
  强度由 `sidebarGlow` 控制（默认 0.7）。只保留大块颜色，看不出形状和文字。
- 两个参数在 Settings → Liquid Glass 中可调，并随参数 JSON 一起复制/粘贴；调试器会忽略这两个键。

## 设置页

QML 设置页改为 iPadOS / macOS 设置的分组样式：顶部标题卡片（图标、标题、说明），
下方为圆角分组，每行包括彩色图标方块、标题、右侧数值/控件/箭头，分隔线从标题处开始。
组件为 `SettingsSection`、`SettingsRow`、`SettingsBlock`、`SettingsCaption`。
内容列最宽 760 pt，居中。macOS 原生设置页不受影响。

## 图标与卡片

- `macWindowMetrics.symbolIcon(name, color)` 在 macOS 由 SF Symbols 提供；其他平台由
  `Frontend.cpp` 读取 `assets/symbols/<name>.svg` 并着色，返回同样的 PNG data URL。
  这些 SVG 是本项目自绘的同风格图标，不含 Apple 素材。`appkit.disclosure.*` 和
  `appkit.selector` 映射到 chevron 图标。QML 中用 `SymbolImage`，图片未就绪时显示原字符。
- 默认封面（加载器图标）的实例卡片：玻璃底叠加从封面提取的平均色（45%），图标为卡片
  短边的 55%，水平居中、距顶部 10 pt，与 AppKit 卡片一致。自定义封面仍铺满裁切。
- 卡片底部阴影从标题上方 4 pt 开始，最深 70%（原为上方 12 pt、最深 85%）。
- 下载和版本列表在 QML 路径下于列表顶部裁切，不再盖住搜索/分类栏；底部仍延伸到窗口
  底边，在播放条下方滚动。

## 取样结构

- **壁纸**（`backgroundLayer`）：画布卡片和页面内面板取样。
- **内容场景**（`contentScene` = 背景 + 画布 + 页面）：导航、侧栏、播放条、搜索和弹出层取样。

浮层不在 `contentScene` 内，所以不会采到自己。页面 z=12，浮层 z≥40，层级未改变。
每组纹理有清晰和半分辨率模糊两份；只有雾化大于 0 时才生成模糊纹理（当前调好的参数雾化为 0）。

## 参数与调试接口

`GlassTuning.qml` 保存全部参数，格式与调试器的 JSON（version 3）相同。
默认值取自调试器的 `build/lab-settings.ini`。

- 调试器 **复制参数** → 启动器 Settings → **Liquid Glass** → **Paste from Glass Lab**
- 启动器 **Copy parameters** → 调试器 **导入参数**
- **Reset to tuned defaults** 恢复默认；开关可整体关闭液态玻璃（回到原 QML 外观）
- Settings 里的 **Glass appearance** 滑块在 Windows 上控制雾化（Clear = 0）

材质对照模式、减少高亮、提高对比度、减少透明度、减少动态效果和 Frosted 均按调试器的规则生效。
`radius`（圆角）和 `dark` 不导入：圆角由各控件决定，深浅色跟随启动器主题。
参数单独保存在 `ProjectGlassLiquidGlass` 设置分类中。

## 构建

仓库根目录运行 `build_windows.cmd`（`--no-run` 只构建）。vcpkg 位于 `core\cmake\vcpkg`
（提交 `0e5030f`；不存在时改用 `VCPKG_ROOT`）。需要 Qt 6.12 msvc2022_64、VS 2022 和 JDK 17
（Prism 的 Java 辅助程序以 Java 7 为目标，JDK 21 的 javac 会拒绝）。
shader 由 `qt_add_shaders` 编译进 `qrc:/pgshaders/liquidglass.frag.qsb`。

构建后脚本把 `jars`、Qt 库和 QML 模块部署到 `core\build-win11\Release`，
之后可以直接双击 `prismlauncher.exe` 运行。依赖使用项目自带的静态 triplet，不需要额外 DLL。
