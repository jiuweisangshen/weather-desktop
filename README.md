# 天气 · Weather Desktop

多源聚合的 Windows 天气桌面程序。程序同时拉取多个公开天气接口，加权汇总给出更稳的当前温度与预报，界面用 PySide6 + QML 做成苹果式的「液态玻璃」风格：写实天空实景背景、玻璃卡片、鼠标跟随高光、平滑过渡，并支持**简体中文 / 繁體中文 / English** 三语实时切换。

> 本项目由 **豆包（Doubao）、DeepSeek、腾讯混元、通义千问** 共同完成：豆包负责整体架构、后端、QML 界面与整合交付；DeepSeek 负责代码审查、地理编码与 AQI 补丁、稳定性修复；腾讯混元参与交互流程与产品化建议；通义千问负责液态玻璃视觉规范与界面文案。

## 功能

- **多源加权**：Open-Meteo、中国天气网、GFS、ECMWF、wttr.in、和风天气（可选）并行取数，缺失源自动归一化，偏离均值过大的源自动剔除
- **当前 + 逐小时 + 15 天**：温度、体感、湿度、气压、能见度、风向风力、阵风、紫外线、降水、日出日落
- **空气质量**：大陆城市优先中国天气网官方国标 AQI，缺失时按 HJ 633-2012 由模型浓度换算并标注口径
- **气象预警**：中国天气网全国预警列表为主源，中央气象台兜底；蓝/黄/橙/红四级按稳定 code 着色
- **月相**：按经纬度计算月相、照射比例、月龄、月出月落
- **液态玻璃界面**：实景天空背景随时段与天气切换，玻璃卡片可拖动互换位置，深/浅双主题
- **三语界面**：设置面板内一键切换 简体中文 / 繁體中文 / English，切换后界面即时重建生效
- **单实例**：重复启动只会唤起已有窗口，不会开出第二个

## 三语实现

不依赖 Qt Linguist 的 `.ts/.qm` 编译链，而是「简体原文即键」的自建词典：

```
src/weather_app/i18n.py          # 语言常量、词典加载、tr()、localize()
src/weather_app/i18n/strings.json  # zh-TW 与 en 两份译文（约 300 条）
```

- QML 侧所有文案写成 `tr("简体原文")`，由 Python 词典翻译；
- 后端数据（天气描述、AQI/UV 等级、风向、预警级别与类型、数据源名、状态提示）在交给界面前用 `localize()` 递归翻译，`code/id/icon/unit` 等标识字段原样保留；
- 语言切换由 Python 销毁并重建 QML 引擎完成，避免逐条重翻译与旧绑定残留；
- 数据源返回的模板化长句带 `_note_tpl` 参数，缓存里存模板而不是成品句子，切语言不会出现旧语言残留。

## 数据源

| 数据源 | 用途 | 状态 |
|---|---|---|
| Open-Meteo（best_match） | 主预报：当前 / 逐小时 / 15 天 | 启用 |
| 中国天气网 | 国内官方实测（实况、国标 AQI）、全国预警列表 | 启用（大陆城市） |
| Open-Meteo GFS / ECMWF | 当前温度交叉校验（模式源，权重已降） | 启用 |
| Open-Meteo Air Quality | 空气污染参考（模型浓度，官方缺失时使用） | 启用 |
| wttr.in | 交叉校验（WorldWeatherOnline 派生） | 启用 |
| 和风天气 QWeather | 可选，填 Key 后启用 | 默认关闭 |
| ip-api.com | IP 自动定位 | 自动定位时使用 |

聚合规则：默认权重 open-meteo 0.28 / 中国天气网 0.24 / wttr.in 0.22 / 和风 0.12 / GFS 0.07 / ECMWF 0.07；参与源多于 2 个且某源偏离加权均值超过 2.5°C 时剔除最远源后重算。

## 运行环境

- Windows 10/11 x64
- Python 3.14（开发环境），PySide6 6.12
- 依赖见 `requirements.txt`

## 开发运行

```powershell
python -m venv .venv
.venv\Scripts\pip install -r requirements.txt
.venv\Scripts\python.exe src\weather_app\main.py
```

离屏截图自检（不需要桌面 GPU 窗口）：

```powershell
$env:QT_QPA_PLATFORM = "offscreen"
.venv\Scripts\python.exe src\weather_app\main.py --screenshot out.png --city 北京
```

## 打包

```powershell
.venv\Scripts\python.exe -m PyInstaller 天气.spec --distpath dist --workpath build\pyi --noconfirm
```

安装包（Inno Setup 6/7）：

```powershell
ISCC.exe installer\天气_install.iss
```

## 目录结构

```
src/weather_app/
├── main.py            入口（QML 加载、单实例、截图验证模式）
├── app.py             Qt 桥（请求 / 信号 / 设置读写 / 多语言切换）
├── fetch.py           取数编排（并行 + 硬截止时间 + 缓存）
├── aggregate.py       多源加权聚合、提示语、预警合并
├── geo.py             地理编码（别名表 + 区县 + 经纬度）
├── aqi_cn.py          中国 AQI（HJ 633-2012）
├── wmo.py             WMO 天气代码、风向、UV 等级
├── i18n.py            多语言运行时
├── i18n/strings.json  繁體中文 / English 词典
├── config.py / cache.py
├── sources/           open_meteo / chinacom / wttrin / qweather / alarm_nmc
└── ui/                main.qml + GlassCard / WeatherIcon / MetricTile / HourlyTile /
                       DailyRow / MoonPhaseCard / SkyPreview / RainDrops / TipBubble
assets/
├── icons/svg/         矢量图标源（可再编辑）
├── icons/png/         渲染后的图标
├── appicon/           程序图标（多尺寸 ico）
└── ui/                极光渐变背景
```

## 免责声明

本程序仅聚合第三方公开天气数据，展示的「综合温度」为多源加权参考值，不构成任何专业气象结论；数据版权归各数据源所有。
