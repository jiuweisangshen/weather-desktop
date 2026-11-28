# 天气 · 多源天气分析（Windows EXE）

一款本地 Windows 天气桌面软件：同时拉取多个天气数据源，加权汇总后给出“较为准确”的温度与天气信息，以苹果式“液态玻璃”圆角界面呈现。

- **程序**：`dist\天气\天气.exe`（文件夹版，双击即用，无需安装）
- **开发**：Python 3.14.8（venv：`F:\weather\.venv`）+ PySide6 6.12 + QML

---

## 一、功能一览

| 模块 | 内容 |
|---|---|
| 基础信息 | 所查地区（名称/省级/国家 + 坐标）、当前温度、体感温度、高低温 |
| 当日详情 | 当日最高/最低温度、天气状况（多云/雨/雪…）、空气污染程度（中国 AQI） |
| 15 天预报 | 每日天气状况、温度区间条、降水概率、日出/日落 |
| 逐小时详情 | 每 48 小时：天气状况、体感温度、紫外线指数、风力/阵风/风向、日出日落、降水量（mm）、能见度、湿度、气压 |
| 数据来源 | 界面底部常驻数据源名称与官方链接（点击直达），并标注“已启用/未启用” |

界面支持：搜索任意城市（中文/英文/经纬度）、**窗口自由缩放与最大化**（拖拽四边/四角，或双击标题栏、点击右上角最大化按钮；最小宽度 1160px）、**深浅色双主题切换**（右上角太阳/月亮按钮，一键切换并自动记忆，重启后保持）、**天气实景动态背景**（深色主题下背景随当前天气实时切换：晴/多云/阴/雨/雪/雾/雷/夜空 8 种写实天空，平滑淡入）、悬停顶部按钮显示功能说明气泡、无卡顿滚动与自然过渡动画、右下角窗口控制（最小化/最大化/关闭）。

---

## 二、数据源与聚合算法

### 数据源（全部免费，除和风外无需注册）

| 数据源 | 用途 | 链接 | 状态 |
|---|---|---|---|
| Open-Meteo（best_match） | 主预报：当前/逐小时/15 天 | https://open-meteo.com/ | 已启用 |
| 中国天气网 | 国内官方实测：国标 AQI、实况温度/湿度/气压/能见度/风 | http://www.weather.com.cn/ | 已启用（大陆城市） |
| Open-Meteo 单模型 GFS | 当前温度交叉校验（模式源，权重已降） | https://open-meteo.com/ | 已启用 |
| Open-Meteo 单模型 ECMWF IFS | 当前温度交叉校验（模式源，权重已降） | https://open-meteo.com/ | 已启用 |
| Open-Meteo 空气质量 API | 空气污染参考（模型浓度，仅官方缺失时使用） | https://open-meteo.com/en/docs/air-quality-api | 已启用 |
| wttr.in | 交叉校验（WorldWeatherOnline 派生数据） | https://wttr.in/ | 已启用 |
| 和风天气 QWeather | 可选：在 `config.json` 填入免费 Key 后启用 | https://dev.qweather.com/ | 默认关闭 |
| 墨迹天气 | 参考站点（无公开 API，仅展示参考） | https://www.moji.com/ | 仅参考 |
| ip-api.com | IP 自动定位 | https://ip-api.com/ | 自动定位时使用 |

### 温度聚合算法

“当前温度”不是单一来源，而是多源加权平均。**实测结论**：地面实测源（中国天气网 / wttr.in / 和风）彼此差异小、更可靠；模式源（GFS / ECMWF）更分散，权重已降低。默认权重：

```
open-meteo 0.30 · chinacom(中国天气网) 0.20 · wttr.in 0.20 · gfs 0.10 · ecmwf 0.10 · qweather 0.10
```

- 某源请求失败时自动剔除并对剩余源重新归一化（界面底部显示实际参与源与占比）。
- **离群剔除**：参与源多于 2 个且某源偏离加权均值超过 2.5°C 时，自动剔除最远源后重算，避免模式源拖偏。
- 各源温差较大（>1.5°C）时界面提示“多源温差 X.X°C，已按加权平均”。
- 逐日最高/最低温度同样多源加权（ECMWF / wttr.in / 和风参与）。

### 空气污染口径说明（裁决结论）

- **大陆城市**：优先显示**中国天气网官方国标 AQI**（国家环境监测实时数据），界面标注“国标（中国天气网官方实时监测）”。
- **国外城市/官方缺失**：回退为按中国 HJ 633-2012 标准由 Open-Meteo 模型浓度（PM2.5/PM10 小时值）换算，界面标注“换算值·小时值参考”。
- 实测表明 Open-Meteo 模型浓度可能明显高于官方监测（如北京模型 PM2.5≈296 vs 官方 AQI 120），因此官方数据优先；PM2.5/PM10 浓度仍展示 Open-Meteo 模型值（标注 μg/m³，仅供参考）。

---

## 三、使用说明

1. 双击 `dist\天气\天气.exe` 运行（首次启动会在程序目录生成 `config.json` 模板）。
2. 顶部搜索框输入城市（如 `北京`、`London`、`纽约`、`39.9,116.4`），回车查询。
3. 未输入城市时：优先使用 `config.json` 的 `default_city`，否则 IP 自动定位，失败兜底北京。
4. 底部点击数据源名称可打开对应官方链接。

### config.json 可选配置（EXE 同目录）

```json
{
  "qweather_key": "",        // 和风天气免费 Key（https://dev.qweather.com 注册），填入后自动启用和风数据源
  "default_city": "",        // 留空 = 自动定位；填写如 "北京"
  "cache_minutes": 10,       // 本地缓存时长（分钟），与 10 分钟自动刷新对齐
  "weights": {               // 当前温度聚合权重（缺失源自动归一化）
    "open-meteo": 0.30,
    "chinacom": 0.20,
    "wttr.in": 0.20,
    "gfs": 0.10,
    "ecmwf": 0.10,
    "qweather": 0.10
  }
}
```

> 数据刷新策略：启动时先读取未过期缓存立即上屏（秒开），后台线程强制拉取最新数据覆盖；此后每 10 分钟自动刷新当前城市。首次运行无缓存时直接拉取最新数据。

---

## 四、目录结构（F:\weather）

```
F:\weather
├── dist\天气\天气.exe   ← 最终交付程序（onedir 文件夹版，启动快）
├── src\weather_app\
│   ├── main.py               程序入口（QML 加载 + 截图验证模式）
│   ├── app.py                Qt 桥（请求/信号/链接 + 缓存先行 + 10 分钟自动刷新）
│   ├── fetch.py              取数编排（8 路线程池并行）
│   ├── geo.py                地理编码（别名表 + 可信度排序 + 兜底）
│   ├── aggregate.py          多源加权聚合
│   ├── aqi_cn.py             中国 AQI（HJ 633-2012）计算
│   ├── config.py / cache.py / wmo.py
│   ├── sources\              open_meteo.py / wttrin.py / qweather.py / chinacom.py / base.py
│   └── ui\                   main.qml + GlassCard/WeatherIcon/MetricTile/HourlyTile/DailyRow/TipBubble/
│                              SkyPreview（动态实景天空）/ RainDrops（雨滴动画）.qml
├── assets\
│   ├── icons\svg\            39 个矢量图标源（可分层二次编辑）
│   ├── icons\png\            38 个 256px 渲染图标
│   ├── appicon\              app_icon.ico（16~256 多尺寸）/ app_icon_1024.png
│   └── ui\                   aurora_0/1.png 极光渐变背景
├── team\                     协作 Agent 产出（qwen 视觉规范 / deepseek 审查与补丁）
├── 工作汇报\                 定期进度汇报
├── 分工合作.txt / 分工说明.md  多 Agent 分工说明
├── config.json              用户配置（首次运行自动生成）
└── README.md
```

---

## 五、开发 / 重新构建

```powershell
# 环境：Python 3.14.8 venv 已包含 PySide6 6.12.0 / PyInstaller 6.22.3 / requests / Pillow

# 开发运行
F:\weather\.venv\Scripts\python.exe F:\weather\src\weather_app\main.py

# 离屏截图验证（配合 QT_QPA_PLATFORM=offscreen）
F:\weather\.venv\Scripts\python.exe F:\weather\build\dbg_qml.py

# 重新打包（onedir 文件夹版，启动快；如需单文件版改 --onefile）
Set-Location F:\weather
F:\weather\.venv\Scripts\python.exe -m PyInstaller --noconfirm --clean --onedir --windowed `
  --name 天气 --icon F:\weather\assets\appicon\app_icon.ico `
  --paths F:\weather\src `
  --add-data "F:\weather\src\weather_app\ui;weather_app\ui" `
  --add-data "F:\weather\assets;assets" `
  F:\weather\src\weather_app\main.py
```

> 说明：本软件仅聚合第三方公开天气数据；天气本质多变，展示的“综合温度”为多源加权参考值。所有数据版权归各数据源所有。

---

## 六、多 Agent 协作记录

- **豆包**（本会话）：代码唯一所有者/整合者；后端、QML 界面、图标、打包与交付。
- **千问**：液态玻璃视觉规范、界面文案设计、参考图（`team\qwen\`）。
- **DeepSeek**（Opencode 调用的 DeepSeek）：后端审查报告（5 个 P1 全部合入）、地理编码补丁、中国 AQI 补丁、QML 参考组件、打包清单（`team\deepseek\`）。
- 协作分工详见 `分工合作.txt` 与 `分工说明.md`；进度见 `工作汇报\`。
