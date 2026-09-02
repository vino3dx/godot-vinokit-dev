# Godot-Kit

> 面向 Godot Engine 的轻量级工具库与通用类集合。
> 为中大型 Godot 项目提供**资产管理、配置持久化、授权验证、UI 工具、硬件通信**等常用基础能力。

<p align="center">

![Godot](https://img.shields.io/badge/Godot-4.x-478CBF?logo=godot-engine\&logoColor=white)
![C#](https://img.shields.io/badge/C%23-.NET-512BD4?logo=dotnet\&logoColor=white)
![GDScript](https://img.shields.io/badge/GDScript-supported-478CBF?logo=godot-engine\&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Linux-lightgrey)
![License](https://img.shields.io/badge/License-MIT-green)
![Status](https://img.shields.io/badge/Status-Active-success)

</p>

---

## ✨ Features

Godot-Kit 不追求“大而全”，而是将项目开发过程中反复出现的底层功能封装成**独立、可复用的模块**。

### 📦 Asset Loading

统一处理项目内部与外部资源加载。

* **External Asset Loading**

  * 运行时加载外部 `.png`、`.jpg` 等图片
  * 自动转换为 `ImageTexture`
  * 支持不打包进 PCK 的外部资源

* **Media Loading**

  * 外部视频文件加载
  * 外部音频文件加载
  * 方便构建展厅、数字孪生、交互展示等项目

* **Path Mapping**

  * 统一管理外部资源路径
  * 区分开发环境与部署环境
  * 减少项目中硬编码路径

---

### ⚙️ Configuration

提供简单统一的配置文件管理。

* JSON / INI 配置读写
* 运行时配置加载
* 配置热重载
* 默认值与参数管理
* 敏感配置的基础加密支持

适用于：

```text
config.ini
settings.json
device.json
license.json
```

等项目配置。

---

### 🔐 License & Security

针对 **B 端展示、展厅、多媒体终端、外包项目**提供基础授权能力。

* **Date Lock**

  * 设置软件使用截止日期
  * 运行时自动验证授权状态

* **Device Binding**

  * 基于设备信息进行绑定
  * 防止授权文件直接复制到其他设备

* **Online Activation**

  * 可扩展在线激活机制
  * 支持与远程授权服务器结合

> Godot-Kit 的授权模块定位为基础设施，不试图替代专业 DRM 系统。

---

### 🛠️ UI Utilities

提供常见的运行时 UI 交互组件。

#### DraggableElement

让 Control / UI 元素支持运行时拖拽。

适用于：

* 展厅控制面板
* 自定义编辑器
* 节点操作界面
* 运行时 UI 布局

#### TransformBox

提供类似 DCC / 游戏编辑器的运行时变换控制。

支持：

* 移动
* 缩放
* 旋转
* Transform Gizmo
* 选中框

适合构建：

```text
运行时编辑器
数字展厅
交互设计工具
2D / 3D 编辑工具
```

---

### 🔌 Hardware Bridge

面向 Godot 与外部设备之间的通信。

#### UDP

用于：

* 局域网设备控制
* 多媒体服务器通信
* 投影设备
* 灯光控制
* 展厅中控
* 自定义硬件协议

#### Serial Port

用于：

* 串口设备
* Arduino
* MCU
* 工业控制器
* 外部传感器

统一封装通信逻辑，减少项目中重复编写底层通信代码。

---

## 🧩 Design Philosophy

Godot-Kit 遵循几个简单的设计原则：

### High Cohesion

每个模块负责明确的问题。

```text
AssetLoader
ConfigManager
LicenseManager
DraggableElement
TransformBox
UDPSender
SerialPort
```

模块之间尽可能减少依赖。

### Low Coupling

不强制项目采用特定架构。

你可以只使用其中一个模块：

```text
Godot Project
│
└── Godot-Kit
    ├── Asset
    ├── Config
    ├── License
    ├── UI
    └── Hardware
```

不需要为了使用 `AssetLoader` 而引入整个框架。

### Practical First

Godot-Kit 更关注实际项目中的重复工作，而不是为了抽象而抽象。

---

## 💻 Requirements

| Dependency   | Version   |
| ------------ | --------- |
| Godot Engine | 4.x       |
| GDScript     | Supported |
| C# / .NET    | Supported |
| Windows      | Supported |
| Linux        | Supported |

> 推荐使用 **Godot .NET 版本**，可以获得完整的 C# 支持。

---

## 📥 Installation

进入你的 Godot 项目：

```bash
cd your-project/addons
```

克隆仓库：

```bash
git clone https://github.com/your-username/godot-kit.git
```

安装完成后目录结构：

```text
your-project/
├── addons/
│   └── godot-kit/
│       ├── asset/
│       ├── config/
│       ├── license/
│       ├── ui/
│       ├── hardware/
│       └── plugin.cfg
├── scenes/
├── scripts/
└── project.godot
```

然后打开 Godot：

```text
Project
└── Project Settings
    └── Plugins
        └── Godot-Kit
            └── Enable
```

---

## 🚀 Quick Start

### External Texture

使用 `ExternalLoader` 加载项目外部图片：

```gdscript
var loader = ExternalLoader.new()

var texture = loader.load_texture(
    "C:/Exhibition/Assets/logo.png"
)

if texture:
    $Sprite2D.texture = texture
```

这样图片可以放在：

```text
C:/Exhibition/
└── Assets/
    ├── logo.png
    ├── background.jpg
    └── poster.png
```

而不需要将这些资源打包进 `.pck`。

---

## 📁 Recommended Project Structure

对于展厅、数字孪生、多媒体交互等项目，可以采用：

```text
Project/
│
├── addons/
│   └── godot-kit/
│
├── scenes/
│
├── scripts/
│
├── assets/
│
├── config/
│
└── project.godot
```

外部运行时资源：

```text
Application/
│
├── Application.exe
├── Application.pck
│
└── Assets/
    ├── Images/
    ├── Videos/
    ├── Audio/
    └── Config/
```

这样可以将**程序本体与经常变化的展示内容分离**，特别适合展厅项目和 B 端应用。

---

## 🗺️ Roadmap

* [x] External Asset Loader
* [x] JSON / INI Configuration
* [x] Runtime UI Utilities
* [x] UDP Communication
* [ ] Serial Port Module
* [ ] License Management
* [ ] Device Binding
* [ ] Online Activation
* [ ] More Runtime Editor Components
* [ ] Godot 4.x API Documentation
* [ ] Example Projects

---

## 🤝 Contributing

欢迎提交：

* Bug Report
* Feature Request
* Pull Request
* Documentation Improvement

如果你发现了问题，可以通过 GitHub Issues 提交反馈。

---

## 📄 License

Godot-Kit 使用 **MIT License**。

你可以自由地：

* 使用
* 修改
* 分发
* 用于商业项目

具体内容请参考仓库中的 `LICENSE` 文件。

---

## ⭐ Support

如果 Godot-Kit 对你的项目有所帮助，欢迎给项目点一个 ⭐ Star。

<p align="center">

**Godot-Kit — Build less boilerplate, focus on your project.**

</p>
