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
start_gui          % GUIDE 主界面
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
| `MatlabScript_FeedbackControl.m` / `.fig` | GUIDE 主界面 |
| `start_gui.m` | 启动入口 |
| `rigol/` | DHO814 / DG2052 驱动与自检、单次收发 |
| `data/` | 采集默认保存目录（不入库） |

幅度单位为 **mVpp**。本实验室无位移台，电机区已从界面隐藏。

## 许可

©2022 Washington University。非商业、非临床、不可用于人体。RIGOL 仪器层为本实验室扩展。
