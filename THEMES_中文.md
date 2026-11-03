# 主题

在 **设置 → 外观 → 主题** 打开主题库。内置 Aurora、Dusk、Forest、Paper，
以及参考 Prism 原版的 Bright、Dark 和四款猫主题（Kitteh、Rory、Rory Flat、Teawie）。
点击卡片查看选择，再点 **使用主题** 应用。Paper 和 Prism Bright 使用浅色，其余内置主题使用深色。

## 制作与分享

1. 在设置中调整外观模式、强调色、背景或壁纸，以及 Liquid Glass 参数。
2. 打开主题库，选择 **创建主题…**，填写名称和作者，再保存当前外观。
3. 选中保存的主题，点击 **导出…**，将 `.vitra-theme.json` 文件发给别人。
4. 接收方在主题库点击 **导入…**，选择文件，再点击 **使用主题**。

壁纸会转换成 PNG 并直接包含在主题中，不需要附带原始文件或保持相同的电脑路径。
壁纸源文件和转换后的 PNG 各不超过 4 MB，图片不超过 1600 万像素；主题文件不超过 8 MB。
主题库最多保存 64 款玩家主题。玩家主题可删除，官方主题始终保留。

主题只包含配色、背景和玻璃参数。账号、实例、游戏设置、窗口布局和无障碍偏好不会随主题分享。
修改已应用主题的外观后，设置会显示为“自定义”；可以另存为一款新主题。
当前分享方式是主题文件，可通过聊天、论坛或其他文件渠道分发。

## 文件格式

主题采用版本化的 JSON 数据。下面是可直接导入的最小示例：

```json
{
  "format": "vitra-theme",
  "version": 1,
  "name": "My violet theme",
  "author": "Player",
  "appearance": {
    "mode": "Dark",
    "accent": "#C1A3FF",
    "background": {
      "kind": "gradient",
      "angle": 45,
      "stops": [
        {"color": "#221C35", "position": 0},
        {"color": "#70425A", "position": 1}
      ]
    },
    "glass": {"frost": 0.42, "materialVariant": 0}
  }
}
```

`mode` 支持 `Dark`、`Light`、`System`；渐变支持 2 到 8 个按位置排列的色标。
`glass` 使用 Glass Lab 的参数名称，未提供的外观参数恢复为启动器默认值。
图片背景使用 `kind: "image"`、内嵌 PNG/JPEG 的 `image` 数据 URL，以及
`placement`（`Fill`、`Fit`、`Stretch`、`Center`、`Tile`）。导出的壁纸统一为 PNG。
可选的 `appearance.cat` 为 `kitteh`、`rory`、`rory-flat` 或 `teawie`，用于选择内置猫素材；
省略该字段即不显示猫。需要在支持猫主题的版本中导入，猫素材会按 Prism 原有日期规则切换节日版本。
导入会校验参数、图片和版本，拒绝外部图片路径。主题文件不包含可执行的 QML、JavaScript 或插件。

玩家主题保存在启动器数据目录的 `themes` 子目录中。导入的主题使用新的本地标识，
文件内的名称、作者或自称“官方”的字段不会改变其玩家主题身份。

猫图使用项目自带的 Prism Launcher 素材：Kitteh 来自 MultiMC，Rory 由 Ashtaka 绘制，
Teawie 由 SympathyTea 绘制并以 CC BY-SA 4.0 授权。原素材与许可说明保留在
`core/launcher/resources/backgrounds`。
