# TDF_Visual

`TDF_Visual` 是一个基于 [Processing](https://processing.org/) 的三维力传感器可视化项目：磁传感器（MLX90393）读取 PDMS 内嵌磁铁结构的磁场 `Bx / By / Bz`，程序将其实时解耦为三轴受力 `Fx / Fy / Fz`，并通过一整套仪表盘式面板（三维力矢量、压力垫、切向罗盘、波形、矩阵等）展示传感器状态。支持 **H2 / H4 / H6** 三种传感器模型，支持 **USB 串口**、**蓝牙 BLE（ESP32-C3）** 两种真实数据源，以及无需硬件的 **Preview Demo** 模拟数据源，并内置 **CSV 数据录制** 功能。

界面右侧另有一列为摩擦电方向预留：**4 路摩擦电（TENG）信号面板** 与 **材质识别结果卡片**。这两块目前**只在 Preview Demo 中有数据**——真实摩擦电信号的传输格式和材质分类器都还没有接入。

本仓库同时包含配套的**标定数据管线**（`TDF_DataProcess/` 子目录：原始标定数据 + Python 分析脚本），可视化与数据处理统一在一个仓库、双分支（`main` 稳定 / `dev` 开发）管理。

## 演示效果

> 以下截图均来自当前版本的 **Preview Demo**（模拟数据，界面顶部有 `DEMO` 标记），不是真实传感器读数。

### 启动界面

选择 Serial / Bluetooth LE 两种真实数据源，或点 **Preview Demo**（快捷键 `D`）在没有传感器的情况下预览整套界面。

![TDF_Visual startup chooser](docs/demo-startup.png)

### 按压（Z 轴）

`Fz` 约 12 N 时的状态：压力垫中心隆起变色、柱状图与三维矢量指向 +Z；右侧摩擦电面板记录按下时的脉冲，材质卡片正在识别（`SENSING`，Nylon 90%）。

![TDF_Visual Z-axis demo](docs/demo.png)

### 切向滑动（XY）

轻压下切向力绕圈：切向罗盘指针偏离中心、`Fx / Fy` 柱有正负；摩擦电上、下两排电极出现相反极性的信号，电极分布图上叠加了实时 XY 力箭头。

![TDF_Visual tangential demo](docs/demo-tangential.png)

## 核心原理

程序启动后先选择数据源，再进行基线校准（采集 `100` 帧静止数据求平均），随后用解耦矩阵把磁场变化量转换为三轴受力：

```text
ΔV = [Bx - baselineX, By - baselineY, Bz - baselineZ]
F  = D * ΔV
D  = S^-1
```

- `S`：灵敏度矩阵，单位 `uT/N`（行 = Bx/By/Bz，列 = Fx/Fy/Fz），由 `TDF_DataProcess` 管线从标定数据拟合得到
- `D`：解耦矩阵，单位 `N/uT`，由 `S` 求逆得到
- **`Fz` 按"只测压"处理**：解耦后 Z 向负值会被钳为 0；`Fx / Fy` 保留正负

## 数据源（串口 / BLE / Demo）

启动后首先显示**数据源选择界面**（两张卡片 + 一个 Preview Demo 按钮，也可按 `S` / `B` / `D` 快捷键）：

> **没有传感器也能预览**：点 **Preview Demo**（或按 `D`），程序用模拟数据驱动整套界面，循环演示按压 / 切向滑动 / 组合受力。界面会显示 `DEMO` 标记，此模式下不能录制 CSV。

| 数据源 | 链路 | 说明 |
|--------|------|------|
| **Serial (USB)** | `Single_Sensor.ino` → USB 串口（115200） | 有线方案，自动匹配含 `COM` 的端口 |
| **Bluetooth LE** | `BLE_Arduino.ino`（ESP32-C3）→ BLE NUS → `ble_bridge.py` → 标准输入流 | 无线方案，设备名 `TDF_Sensor`，100 Hz 采样；桥接脚本自动扫描、断线自动重连 |
| **Preview Demo** | `DemoSource.pde`（程序内生成） | 无需硬件。12 s 循环演示按压 / 切向滑动 / 组合受力，并同步生成 4 路摩擦电信号和材质识别结果；顶部显示 `DEMO` 标记，`REC` 不可用 |

三种数据源最终都走**同一套帧处理逻辑**（基线 → 解耦 → 各面板），串口与 BLE 输出相同的 `x,y,z` 文本帧。运行中可随时点顶部 `SOURCE` 按钮或按 `ESC` 返回选择界面**热切换**数据源（不必重启程序）。

## 界面面板

| 面板 | 内容与交互 |
|------|------------|
| **Sensor State**（顶部状态栏） | 基线、磁场增量、解耦力三列读数；传感器徽章、`LIVE/HOLD`（按数据流时效判定，断流 0.4s 才变 HOLD）、`BAD` 坏帧计数；右侧纵向控件列：**REC**（CSV 录制）、**SOURCE**（热切换数据源）、**FPS**（绿/黄/红分级）、**Calibration** |
| **S / D Matrix**（矩阵面板） | `H2 / H4 / H6` 选项卡、`S/D` 切换、3×3 矩阵数值；始终可见 |
| **3D Force Vector**（三维力矢量） | 立体笼 + 彩色坐标轴 + 原点球 + 地面网格；三根分量箭头 + 发光合力箭头 + 分量投影虚线；面板上**拖拽可自由旋转** |
| **Force Components**（柱状图） | `Fx / Fy / Fz / |F|` 四根柱，按各自轴的全局量程归一 |
| **Z-Axis Pressure**（压力垫） | 点阵随 `Fz` 由绿变红、按高斯隆起；默认正俯视，**拖拽自由旋转**，`Reset` 复位视角 |
| **XY Tangential Force**（切向罗盘） | 阻尼平滑的指针表示 XY 切向力（真实方向 + 大小），按合成 XY 量程归一 |
| **Magnetic Delta Waveform**（波形） | `dBx / dBy / dBz` 滚动波形；**默认显示 200 个点**，底部滑块可调显示点数（50~600），`Reset` 复位为 200 |
| **Material recognition**（右上材质识别） | 当前状态（WAITING / SENSING / RESULT）、识别出的材质与置信度、前 3 名概率条、最近 5 次结果。候选材质：Nylon / Skin / Paper / PET / Silicone / PTFE。**目前只有 Demo 模式有结果**（Demo 中是模拟判别，不是训练好的模型），真实分类器尚未接入，此时显示 `No classifier connected` |
| **Triboelectric (TENG)**（右侧摩擦电列） | 4 路摩擦电通道 `T1~T4`：活动指示灯、实时值与衰减峰值、滚动波形；事件计数 + `Reset`；底部 2×2 电极分布图（亮度 = 近期峰值，叠加 XY 力箭头与 Fz 圆点）。**目前只有 Demo 模式有数据**，真实串口/BLE 的摩擦电数据格式尚未接入，此时显示 `No TENG input` |
| **Axis Ranges**（全局量程） | `X / Y / Z` 三个量程滑块 + `XY Lock`（默认开）+ **`DENT` 滑块**（压力垫凹陷敏感度 0.2~5×，纯视觉效果，不影响任何计算数值）+ `Reset` |

> 3D 力矢量的轴向映射：屏幕**下方 = +Z**、**左下 = +X**、**右下 = +Y**。

## CSV 数据录制

- 顶部 **REC** 按钮开始录制（按钮变红、显示已录秒数），再按停止并**弹窗命名**文件；
- 数据写入 `csv_export/` 文件夹（自动创建），**按满采样率逐帧记录**（不受 60 FPS 画面刷新限制）；
- 列：`epoch_ms, t_ms, Bx/By/Bz(uT), dBx/dBy/dBz, Fx/Fy/Fz(N)`；
- 弹窗取消、切换数据源、程序退出均不丢数据（自动以时间戳名落盘）；上次异常退出的半成品会在下次录制时自动抢救为 `recovered_*.csv`。

## 交互操作

### 快捷键

| 按键 | 场景 | 功能 |
| --- | --- | --- |
| `S` / `B` / `D` | 选择界面 | 选择串口 / 蓝牙 / 模拟演示 |
| `ESC` | 运行中 | 返回数据源选择界面（不退出程序） |
| `T` | 运行中 | 切换 `S / D` 矩阵显示 |
| `1 / 2 / 3` | 运行中 | 选择 `H2 / H4 / H6` 传感器 |
| `C` | 运行中 | 重新执行基线校准 |

### 鼠标

- 顶部控件列：`REC` 录制、`SOURCE` 热切换数据源、`Calibration` 重新校准
- 矩阵面板：点选 `H2/H4/H6` 选项卡、`S/D` 切换
- 3D 力矢量 / 压力垫：拖拽旋转视角（压力垫有 `Reset`）
- 全局量程：拖动 `X/Y/Z/DENT` 滑块、`XY Lock` 开关、`Reset` 复位
- 波形：拖动点数滑块、`Reset` 复位点数
- 摩擦电面板：`Reset` 清零各通道峰值与事件计数（不清波形）

## 运行环境

- Processing `4.x`
- **串口模式**：Windows 串口环境（波特率 `115200`）
- **BLE 模式**：Python `3.x` + `bleak`（`pip install bleak`），以及烧录了 `BLE_Arduino.ino` 的 ESP32-C3
- Python `3.x` + `openpyxl`（**可选**，仅在需要从 Excel 重新生成 CSV 时使用）
- 字体 `Orbitron`、`Space Mono`（已随项目放在 `data/`，无需额外安装）

> **性能提示**：3D 面板较吃显卡。若是带独显的笔记本（混合显卡），请确保 Processing 的 `java.exe` 走**独立显卡**，否则默认走核显会明显掉帧。`ForceView.pde` / `PressureGrid.pde` 顶部的 `FV_SS` / `PG_SS`（超采样倍数）可在"清晰度"与"帧率"间权衡。

## 快速开始

1. 安装 Processing `4.x`。
2. 按需安装 Python 依赖：

   ```bash
   pip install bleak openpyxl
   ```

3. 用 Processing IDE 打开项目目录并运行 `TDF_Visual.pde`（所有 `.pde` 标签会一起编译，`TDF_DataProcess/` 子目录会被 Processing 忽略）。
4. 在启动界面选择数据源：
   - **串口**：连接 USB 设备（`Single_Sensor.ino`）；
   - **BLE**：给 ESP32-C3 上电（`BLE_Arduino.ino`），程序自动扫描 `TDF_Sensor` 并连接；
   - **没有传感器**：点 **Preview Demo** 或按 `D`。
5. 保持传感器静止，等待基线采样（100 帧）完成后进入实时显示（Demo 模式会自动完成）。

命令行方式（Processing 4.x 自带的 `processing` 命令行入口）：

```bash
processing cli --sketch=/path/to/TDF_Visual --run
```

## 数据输入格式

串口与 BLE 两条链路均输出以下 CSV 文本帧（`;` 会被自动转成 `,`）：

```text
Bx,By,Bz
SensorID,Bx,By,Bz
Bx,By,Bz,Fx,Fy,Fz
```

说明：

- `Bx / By / Bz` 单位为 `uT`
- 4 列时首列 `SensorID` 被忽略；6 列时后 3 列力数据当前不参与计算
- 以 `#` 开头、或含 `:` / `=` 的行视为调试/表头并跳过；非有限值会被丢弃并计入 `BAD` 计数
- BLE 固件在传感器读取失败时会发送哨兵值 `-1,-1,-1`，传感器缺失时发送 `0,0,0`

固件参考：`Single_Sensor/Single_Sensor.ino`（串口）与 `BLE_Arduino/BLE_Arduino.ino`（BLE，`DEBUG_MODE` 均保持为 `0`）。

> **摩擦电与材质识别尚未进入传输格式。** 以后接入时只需调用两组已有接口：
> - 摩擦电：`pushTengFrame(t1, t2, t3, t4)`（单位 V，每帧一次）；固件建议每帧发送**峰值保持**值（该帧时间内绝对值最大的采样），因为摩擦电脉冲只有毫秒级，100 Hz 直接采样会漏掉大部分峰值；
> - 材质识别：`materialBeginContact()` → `materialUpdate(概率数组)` → `materialCommit()`，候选材质在 `MaterialPanel.pde` 的 `MATERIAL_NAMES` 中修改。

## 灵敏度数据流程

**上游（`TDF_DataProcess/`，标定数据变化时手动运行）**：`python process_sensitivity.py` 读取 `Raw_Data/` 下 158 个原始标定 CSV（X/Y 轴 0–3N 各 7 级、Z 轴 0–20N 41 级），计算逐级均值、最小二乘拟合灵敏度（**带 R² / 残差质量报告与非线性警告**），生成拟合图并写入 `TDF_DataProcess/Processed_Data.xlsx`（保存前自动 `.bak` 备份）。

**下游（程序启动时）**：`Decoupling.pde` 先尝试运行 `convert_data.py`（读仓库根目录的 `Processed_Data.xlsx` → 写 `sensitivity_data.csv`），再读取 CSV 构建 `S` 并求逆得到 `D`。若没有 Python，则直接用已有的 CSV。

> 注意：`Processed_Data.xlsx` 目前存在两份（仓库根目录一份供程序读取、`TDF_DataProcess/` 一份由管线生成），标定值更新后需手动同步。

## 项目结构

| 文件 | 作用 |
| --- | --- |
| `TDF_Visual.pde` | 主入口：`setup/draw`、输入处理、顶部状态栏与控件列、设计空间缩放 |
| `Connection.pde` | 数据源状态机：启动选择界面、BLE 桥接进程管理、热切换 |
| `DemoSource.pde` | 模拟数据源：无硬件时生成合成磁场帧，循环演示整套界面 |
| `SensorReceiver.pde` | 帧解析（串口/BLE/演示共用）、坏帧统计、LIVE/HOLD 时效判定 |
| `CsvExport.pde` | CSV 录制：REC/STOP、满采样率写盘、异步命名弹窗、崩溃抢救 |
| `Baseline.pde` | 基线采样（100 帧）与校准进度 |
| `Decoupling.pde` | 灵敏度矩阵加载、求逆、力解耦（`Fz` 钳为非负） |
| `ForceView.pde` | 三维力矢量仪表 + 柱状图（离屏 P3D） |
| `PressureGrid.pde` | `Fz` 压力点阵（离屏 P3D，可旋转，凹陷受 `DENT` 调节） |
| `TangentialCompass.pde` | `XY` 切向力罗盘（阻尼指针） |
| `SensorPlot.pde` | `dBx / dBy / dBz` 实时波形 + 点数控制 |
| `RangePanel.pde` | 全局 `X/Y/Z` 量程滑块 + XY 锁 + `DENT` 滑块 + 复位 |
| `MaterialPanel.pde` | 材质识别结果卡片（状态、材质 + 置信度、概率条、历史），对外提供 `materialBeginContact / materialUpdate / materialCommit` 接口 |
| `TengPanel.pde` | 右侧 4 路摩擦电（TENG）面板：波形、峰值、事件计数、2×2 电极分布图（白点 = Fz，白线 = XY 切向力） |
| `MatrixHUD.pde` | `S / D` 矩阵叠加面板 |
| `Theme.pde` | 配色、字体、面板/徽章绘制工具 |
| `ble_bridge.py` | BLE → stdout 桥接（bleak，自动扫描/重连） |
| `convert_data.py` | 从 Excel 提取灵敏度矩阵生成 CSV |
| `Processed_Data.xlsx` / `sensitivity_data.csv` | 灵敏度数据（xlsx 为源、csv 为运行时读取） |
| `Single_Sensor/` | 串口固件（Arduino + MLX90393） |
| `BLE_Arduino/` | BLE 固件（ESP32-C3 + MLX90393，NUS，100 Hz） |
| `TDF_DataProcess/` | 标定数据管线：`Raw_Data/` 原始数据、`process_sensitivity.py` 分析脚本、拟合图、`AI_Calibration_Plan.pdf`（机器学习标定实验方案） |
| `data/*.ttf` | Orbitron / Space Mono 字体 |

## 数据流

```text
TDF_DataProcess: Raw_Data CSV --process_sensitivity.py--> Processed_Data.xlsx
                                        (手动同步到根目录副本)
根目录: Processed_Data.xlsx --convert_data.py--> sensitivity_data.csv ─┐ (启动一次)
                                                                      ▼
串口: Single_Sensor.ino ──USB──► serialEvent ─┐
BLE:  BLE_Arduino.ino ──NUS──► ble_bridge.py ─┤
Demo: DemoSource（B = B0 + S·F(t) + 噪声）────┤
                                              ▼
                SensorReceiver → Baseline(100) → Decoupling(F=D·ΔV) → 左侧力学面板
                          └─→ CsvExport（REC 录制，Demo 下禁用）→ csv_export/*.csv

Demo: 由 F(t) 推导摩擦电信号 ──pushTengFrame──► TengPanel（右侧 4 路摩擦电）
      模拟判别（非训练模型）──material*()──► MaterialPanel（右上材质识别）
      （真实摩擦电数据与分类器尚未接入）
```
