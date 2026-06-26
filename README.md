# TDF_Visual

`TDF_Visual` 是一个基于 [Processing](https://processing.org/) 的三维力传感器可视化项目，用来将磁场读数 `Bx / By / Bz` 实时解耦为三轴受力 `Fx / Fy / Fz`，并通过一整套仪表盘式面板（三维力矢量、压力垫、切向罗盘、波形、矩阵等）展示传感器状态。支持 **H2 / H4 / H6** 三种传感器模型。

## 演示效果

> 注：界面经过多轮重构，下面的截图展示整体思路，实际 UI（字体、面板布局、控件）与最新版本会有差异。

### Z 轴压力演示

主要展示 `Fz` 压力垫、Z 向受力反馈与整体三维受力状态。

![TDF_Visual Z-axis demo](docs/demo.png)

### 切向力演示

主要展示 `XY` 切向力罗盘与切向受力方向变化，适合观察横向拖拽 / 侧向受力。

![TDF_Visual tangential demo](docs/demo-tangential.png)

## 核心原理

程序启动后先进行基线校准（采集 `100` 帧静止数据求平均），随后用解耦矩阵把磁场变化量转换为三轴受力：

```text
ΔV = [Bx - baselineX, By - baselineY, Bz - baselineZ]
F  = D * ΔV
D  = S^-1
```

- `S`：灵敏度矩阵，单位 `uT/N`（行 = Bx/By/Bz，列 = Fx/Fy/Fz）
- `D`：解耦矩阵，单位 `N/uT`，由 `S` 求逆得到
- **`Fz` 按"只测压"处理**：解耦后 Z 向负值会被钳为 0；`Fx / Fy` 保留正负

## 界面面板

| 面板 | 内容与交互 |
|------|------------|
| **Sensor State**（顶部状态栏） | 基线、磁场增量、解耦力三列读数；传感器徽章、`LIVE/HOLD`、`BAD` 坏帧计数、**FPS 实时帧率**（绿/黄/红分级）、`Calibration` 按钮 |
| **S / D Matrix**（矩阵面板） | `H2 / H4 / H6` 选项卡、`S/D` 切换、3×3 矩阵数值；始终可见 |
| **3D Force Vector**（三维力矢量） | 立体笼 + 彩色坐标轴 + 原点球 + 地面网格；三根分量箭头 + 发光合力箭头 + 分量投影虚线；面板上**拖拽可自由旋转** |
| **Force Components**（柱状图） | `Fx / Fy / Fz / |F|` 四根柱，按各自轴的全局量程归一 |
| **Z-Axis Pressure**（压力垫） | 点阵随 `Fz` 由绿变红、按高斯隆起；默认正俯视，**拖拽自由旋转**，`Reset` 复位视角 |
| **XY Tangential Force**（切向罗盘） | 阻尼平滑的指针表示 XY 切向力（真实方向 + 大小），按合成 XY 量程归一 |
| **Magnetic Delta Waveform**（波形） | `dBx / dBy / dBz` 滚动波形；**默认显示 200 个点**，底部滑块可调显示点数（50~600），`Reset` 复位为 200 |
| **Axis Ranges**（全局量程） | `X / Y / Z` 三个量程滑块 + `XY Lock`（默认开，X=Y 同步）+ `Reset`（恢复默认 5 / 5 / 20） |

> 3D 力矢量的轴向映射：屏幕**下方 = +Z**、**左下 = +X**、**右下 = +Y**。

## 全局量程（Axis Ranges）

`X / Y / Z` 三个滑块设定各轴的"满量程"（N），**对所有面板全局生效**：

- 柱状图：`Fx / Fy / Fz` 各按对应轴量程归一，`|F|` 按合成量程
- 3D 矢量：各轴按自身量程缩放（小力用平方根映射放大，更可见；文字读数始终是真实 N 值）
- 压力垫：`Fz` 饱和阈值 = Z 量程
- 切向罗盘：满量程 = `√(Xmax² + Ymax²)`，箭头保持真实物理方向
- **`XY Lock`**（默认开）：锁定 X、Y 量程相等并同步变化

## 交互操作

### 快捷键

| 按键 | 功能 |
| --- | --- |
| `T` | 切换 `S / D` 矩阵显示 |
| `1 / 2 / 3` | 选择 `H2 / H4 / H6` 传感器 |
| `C` | 重新执行基线校准 |

### 鼠标

- 顶部 `Calibration` 按钮：重新基线校准
- 矩阵面板：点选 `H2/H4/H6` 选项卡、`S/D` 切换
- 3D 力矢量：拖拽旋转视角
- 压力垫：拖拽旋转、`Reset` 复位视角
- 全局量程：拖动 `X/Y/Z` 滑块、`XY Lock` 开关、`Reset` 复位
- 波形：拖动点数滑块、`Reset` 复位点数

## 运行环境

- Processing `4.x`
- Windows 串口环境（波特率 `115200`，自动匹配含 `COM` 的端口）
- Python `3.x` + `openpyxl`（**可选**，仅在需要从 Excel 重新生成 CSV 时使用）
- 字体 `Orbitron`、`Space Mono`（已随项目放在 `data/`，无需额外安装）

> **性能提示**：3D 面板较吃显卡。若是带独显的笔记本（混合显卡），请确保 Processing 的 `java.exe` 走**独立显卡**（Windows 设置 → 系统 → 显示 → 显卡，或 NVIDIA 控制面板），否则默认走核显会明显掉帧。`ForceView.pde` / `PressureGrid.pde` 顶部的 `FV_SS` / `PG_SS`（超采样倍数）可在"清晰度"与"帧率"间权衡。

## 快速开始

1. 安装 Processing `4.x`。
2. 如需从 `Processed_Data.xlsx` 重新生成 `sensitivity_data.csv`，先安装 Python 依赖：

   ```bash
   pip install openpyxl
   ```

3. 用 Processing IDE 打开项目目录并运行 `TDF_Visual.pde`（所有 `.pde` 标签会一起编译）。
4. 连接串口设备，保持传感器静止，等待基线采样（100 帧）完成后进入实时显示。

命令行方式：

```bash
processing-java --sketch=/path/to/TDF_Visual --run
```

## 数据输入格式

支持以下 CSV（`;` 会被自动转成 `,`）：

```text
Bx,By,Bz
SensorID,Bx,By,Bz
Bx,By,Bz,Fx,Fy,Fz
```

说明：

- `Bx / By / Bz` 单位为 `uT`
- 4 列时首列 `SensorID` 被忽略；6 列时后 3 列力数据当前不参与计算
- 以 `#` 开头、或含 `:` / `=` 的行视为调试/表头并跳过；非有限值会被丢弃并计入 `BAD` 计数

固件参考：`Single_Sensor/Single_Sensor.ino`（MLX90393，输出 `x,y,z`，`115200`，`DEBUG_MODE` 保持为 `0`）。

## 字体

界面字体在 `Theme.pde` 中以 64px 烘焙（保证缩放/高分屏下清晰）：

- **标签 / 标题**：`Orbitron`（`data/Orbitron.ttf`）
- **数值读数**：`Space Mono`（`data/SpaceMono-Regular.ttf`）

若字体文件缺失会自动回退到系统字体（Segoe UI / Cascadia Mono）。

## 灵敏度数据流程

启动时 `Decoupling.pde` 会：先尝试运行 `convert_data.py`（读 `Processed_Data.xlsx` → 写 `sensitivity_data.csv`，需 Python + openpyxl），再读取 `sensitivity_data.csv` 构建 `S`，并求逆得到 `D`。若没有 Python，则直接用已有的 CSV。要改标定值：改 `Processed_Data.xlsx`（需 Python）**或**直接改 `sensitivity_data.csv`。

## 项目结构

| 文件 | 作用 |
| --- | --- |
| `TDF_Visual.pde` | 主入口：`setup/draw`、输入处理、顶部状态栏、FPS、设计空间缩放 |
| `SensorReceiver.pde` | 串口接收与 CSV 解析（坏帧统计） |
| `Baseline.pde` | 基线采样（100 帧）与校准进度 |
| `Decoupling.pde` | 灵敏度矩阵加载、求逆、力解耦（`Fz` 钳为非负） |
| `ForceView.pde` | 三维力矢量仪表 + 柱状图（离屏 P3D） |
| `PressureGrid.pde` | `Fz` 压力点阵（离屏 P3D，可旋转） |
| `TangentialCompass.pde` | `XY` 切向力罗盘（阻尼指针） |
| `SensorPlot.pde` | `dBx / dBy / dBz` 实时波形 + 点数控制 |
| `RangePanel.pde` | 全局 `X/Y/Z` 量程滑块 + XY 锁 + 复位 |
| `MatrixHUD.pde` | `S / D` 矩阵叠加面板 |
| `Theme.pde` | 配色、字体、面板/徽章绘制工具 |
| `convert_data.py` | 从 Excel 提取灵敏度矩阵生成 CSV |
| `Processed_Data.xlsx` | 原始灵敏度数据 |
| `sensitivity_data.csv` | 运行时读取的灵敏度矩阵 |
| `data/*.ttf` | Orbitron / Space Mono 字体 |

## 数据流

```text
xlsx --convert_data.py--> sensitivity_data.csv ─┐ (启动一次)
                                                ▼
Serial CSV → SensorReceiver → Baseline(100) → Decoupling(F=D·ΔV) → 各面板
                                                                     ↕
                                       Axis Ranges（全局量程）/ 鼠标交互
```
