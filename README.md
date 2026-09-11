# Public-Feedback-Control

PCD（被动空化检测）采集与闭环超声反馈控制。算法来自 Washington University Chen 实验室（Chien 等, *CMMM* 2022, [9867230](https://doi.org/10.1155/2022/9867230)）。本实验室 PCD 中心约 **3 MHz**，稳态空化 SC 用 **2f（3.0 MHz）**，不用原文因 4.7 MHz PCD 而选的 3f（4.5 MHz）。

本仓库以 **MATLAB + Instrument Control Toolbox（`visadev`）+ NI-VISA** 运行，硬件为实验室 **RIGOL DHO814** 与 **RIGOL DG2052**。

## 硬件

| 角色 | 型号 | 接口 |
|------|------|------|
| 示波器 | **RIGOL DHO814**（DHO800 系列） | USB-VISA / USBTMC |
| 信号源 | **RIGOL DG2052**（DG2000 系列） | USB-VISA |

VISA 地址在 `rigol/rigol_instr_config.m`。换仪器后在 MATLAB 执行 `visadevlist`，把 `ResourceName` 填进去。

官方手册请从产品页下载；本机副本可放在 `manuals/`（不入库）。

### 接线（本实验室）

| 示波器 | 信号 |
|--------|------|
| **CH1** | 波形发生器回读（触发；FFT 应见 **1.5 MHz**） |
| **CH2** | PCD 接收 |

DHO814 **没有 EXT 口**，因此用 CH1 边沿触发每一发。无换能器/50 Ω 负载时不要打开射频输出。

## 运行

需要：**MATLAB R2020b+**（本机为 R2025b）、**Instrument Control Toolbox**、已安装的 **NI-VISA**。

```matlab
cd('/Users/asagiri/Projects/Public-Feedback-Control')
start_gui          % GUIDE 主界面（等价于 pfc_app）
```

界面上 **单次采集 FFT 并保存** 会从 DHO814 读回时域波形，在电脑上算 FFT 并写入 `data/`（或你选的保存目录）。**PCDcontrol** / **Sonication** 每一发同样刷新时域+FFT，结束后把全部脉冲存成 `.mat`。

DHO814 **示波器屏幕上有 Math FFT**（最多约 1 Mpts，见 [DHO800 数据手册](https://download.rigol.com/en/Manual/Digital%20Oscilloscope/DHO800/DHO800_DataSheet_EN.pdf) 与编程手册 `:MATH:FFT:*`）。闭环用的二次谐波 SC（2f）/ IC 宽带和存盘分析在 **电脑端 FFT** 完成，不依赖把示波器 MATH 波形读回来。

无换能器/50 Ω 负载时不要打开射频输出。

命令窗口也可：

```matlab
addpath('rigol')
test_dg2052_connection   % 信号源自检（默认不开输出）
oneshot_fft_plot         % 开环发一帧、收一帧，弹窗画频谱并保存
```

## 目录

| 路径 | 内容 |
|------|------|
| `pfc_app.m` / `start_gui.m` | 启动入口（打包用 `pfc_app`；`start_gui` 为开发快捷方式） |
| `MatlabScript_FeedbackControl.m` / `.fig` | GUIDE 主界面与回调 |
| `pfc_apply_gui_layout.m` / `pfc_ui_colors.m` | 界面布局 / 全局配色（唯一出处） |
| `pfc_run_experiment.m` / `pfc_debug_no_mb.m` / `pfc_debug_live.m` | 采集、开环、闭环与调试主流程 |
| `pfc_gui_params.m` / `pfc_root.m` / `pfc_gui_close.m` | 参数持久化、可写路径、关窗存盘 |
| `pfc_build_exe.m` | Windows 打包脚本 |
| `pfc_visa.m` / `pfc_gui_busy.m` / `pfc_ensure_save_dir.m` 等 | 连接、运行锁、存盘等公共件 |
| `rigol/` | DHO814 / DG2052 驱动与自检、单次收发 |
| `data/` | 采集默认保存目录（不入库） |

幅度单位为 **mVpp**。本实验室无位移台，电机区已从界面隐藏。

## 一套源码，两种运行方式

开发调试与打包分发共用同一份代码，差异只由 `isdeployed` 与 `pfc_root()` 处理。新增功能请只走下列入口，不要在别处再写一套：

| 关注点 | 唯一出处 |
|--------|----------|
| 启动入口 | `pfc_app.m` |
| 可写路径（存档 / 数据 / 配置） | `pfc_root()` |
| 配色 | `pfc_ui_colors.m` |
| 仪器地址 | `rigol_instr_config.m`（默认值 + 本地 `rigol_config.ini`） |
| 界面参数 | `pfc_gui_params.m` |

## 本机配置的存放位置

界面参数（频率/电压/PRF/周期数/时长/采样点/目标/上限/ID/目录等）、默认数据目录、仪器 VISA 地址都会自动持久化，**换台机器不用重调**。它们都写在"可写工作根"下：

| 运行方式 | 工作根 | 说明 |
|----------|--------|------|
| 源码运行 | 项目根目录 | 与以前一致 |
| 打包 exe 运行 | `%LOCALAPPDATA%\PFC`（Windows） | 可用环境变量 `PFC_HOME` 指定别处 |

| 文件 | 作用 | 删除后 |
|------|------|--------|
| `pfc_gui_params.mat` | 界面参数存档 | 回到界面默认值 |
| `rigol_config.ini` | 仪器 VISA 地址覆盖 | 回到代码内默认地址 |
| `data/` | 默认采集输出目录 | 下次自动重建 |

仪器地址在界面点 **仪器设置** 即可修改（换仪器/换电脑无需改代码）。

## 打包成 Windows 独立程序（可选）

需要一台装了 **MATLAB + MATLAB Compiler** 的 Windows 机器 —— **Compiler 不支持交叉编译，macOS 上无法产出 Windows exe**。

```matlab
pfc_build_exe                  % 编译 exe，并打包含 MATLAB Runtime 的安装程序
pfc_build_exe('noinstaller')   % 只编译 exe
```

产物在 `build/` 下。目标机运行前需安装：

1. **MATLAB Runtime**（版本与编译用的 MATLAB 一致；安装包可选内置）；
2. **NI-VISA**（或仪器厂商 VISA）+ 仪器 USB 驱动 —— `visadev` 依赖它，且不在 Runtime 内。

打包后换仪器不用重新编译：运行程序 → 界面 **仪器设置** → 填 VISA 地址。

## 许可

©2022 Washington University。非商业、非临床、不可用于人体。RIGOL 仪器层为本实验室扩展。
