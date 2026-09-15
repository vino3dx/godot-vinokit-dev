# VinoKit

Godot 4.x 通用底层工具集，各模块相互独立、按需使用。

## 目录结构

```
core/       配置 / 资产 / 数据加载、窗口控制（Autoload 单例，插件启用后自动注册）
network/    TCP 心跳、TCP-UDP 网关、UDP 收发（普通节点，手动挂载到场景）
ui/         动画按钮、批量 UI 动画、摄像头画面视图（普通节点）
tools/      ClassDB 反射调试工具（@tool 节点，编辑器内使用）
modules/    独立功能模块（目前含视频播放组件 video_player.tscn）
```

## Autoload 单例

启用插件后自动注册：`VinoConfig` / `VinoAssets` / `VinoData` / `VinoWindow`。
`VinoAssets`、`VinoData`、`VinoWindow` 会软依赖 `VinoConfig`：若场景中已加载配置文件，
会自动从对应小节读取参数；否则使用脚本 / Inspector 中的默认值。

## 与旧版（1.2.0）的主要差异

- 三处重复的“编辑器 res:// / 导出后 exe 同级目录”路径解析逻辑收敛为 `core/vino_path_resolver.gd`
- 分散的 `print()` 收敛为 `core/vino_logger.gd`，由 `VinoConfig.debug_print` 统一开关
- `VinoAssetLoader` 的三个 `load_*` 方法合并为一套通用缓存加载流程
- 修复 `UDPSender` / `UDPReceiver` 中调用不存在方法 `get_config()`、访问私有属性 `.config` 的问题
- `CameraFeedView` 不再硬依赖非内置的 `CameraServerExtension` 类，未集成该扩展的项目可直接使用
- 移除了残留在网络模块默认值与视频播放器场景中的项目专属 IP / 路径等信息
- `VideoOverlayPlayer` 补全了此前只声明未触发的 `opened` / `playback_started` 等信号

## 已知限制（未在本次重构中处理）

- `network/` 下的心跳协议（`ID:<id>:Md5`、`State:<id>:<state>` 等）是项目专属协议，
  接入不同后端时需自行调整 `vino_tcp_heartbeat_monitor.gd` 中的解析逻辑
- `modules/vino_video_player` 依赖 FFmpeg 插件提供的 `FFmpegVideoStream`，未安装时会打印错误并跳过播放
