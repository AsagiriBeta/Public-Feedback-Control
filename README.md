# Public-Feedback-Control

PCD（被动空化检测）采集与闭环超声反馈控制。算法来自 Washington University Chen 实验室开源实现（Chien 等, *CMMM* 2022, [9867230](https://doi.org/10.1155/2022/9867230)）。

本仓库以 **Python + PyVISA** 为主，可在 macOS / Windows / Linux 上运行；原 MATLAB 脚本仍保留作对照。

## 硬件

| 角色 | 型号 | 接口 |
|------|------|------|
| 示波器 | **RIGOL DHO814**（DHO800 系列，12 bit，100 MHz，单通道 25 Mpts） | USB-VISA / USBTMC |
| 信号源 | **RIGOL DG2052**（DG2000 系列，50 MHz，双通道） | USB-VISA |

示波器读波按手册 **3.28** 节：`:STOP` → `:WAVeform:MODE RAW` → `:WAVeform:FORMat WORD` → `:WAVeform:DATA?`，电压换算 `(raw − YORigin − YREFerence) × YINCrement`。  
信号源猝发命令顺序与实验室 **DG2000-Trigger** 控制器一致：`:APPL:SIN`、先关输出、猝发参数写完再 `:BURSt:STATe ON`；内部 PRF 的同时打开后面板 `:BURSt:TRIGger:TRIGOut POSitive`，供示波器硬件同步。

USB 资源示例（序列号因机而异，界面「扫描」后可从下拉框选择，也可填 `AUTO` 按 `*IDN?` 识别）：

- DHO814：`USB0::0x1AB1::0x0514::<SERIAL>::INSTR`
- DG2052：`USB0::0x1AB1::0x0641::<SERIAL>::INSTR`（手册示例有时为 `0x0642`）

官方手册与数据手册请从产品页下载（仓库不收录厂商 PDF）：[DHO800](https://www.rigol.com/zh_CN/products/oscilloscope/DHO800.html) · [DG2000](https://www.rigol.com/zh_CN/products/function-arbitrary-waveform-generator/DG2000.html)

### 推荐接线（硬件触发）

DHO814 **没有 EXT 口**。把 DG2052 该通道后面板 **[Sync/Ext Mod/Trig/FSK]** 接到示波器另一模拟通道（默认 CH2），界面「触发源」选 **AWG 同步**。这样每个超声猝发都有 TTL 边沿，比用微弱 PCD 信号边沿触发稳定得多（做法来自 DG2000-Trigger 的 CH1→CH2 外触发链路）。

驱动 50 Ω 功放时，AWG 负载选 **50**（默认）；高阻探头/开路选 **INFinity**。

## 在 Mac 上运行（源码）

1. 安装 **Python 3.10+**。
2. 安装 VISA（二选一）：
   - 推荐：[NI-VISA](https://www.ni.com/en/support/downloads/drivers/download.ni-visa.html)（macOS 安装后重启）
   - 或仅用纯 Python：`pip install pyvisa-py pyusb`，并安装 [libusb](https://libusb.info/)（`brew install libusb`）
3. 用 USB 连接 DHO814 与 DG2052。
4. 安装依赖并启动：

```bash
cd Public-Feedback-Control
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
python -m pfc --simulate          # 无仪器时看界面
python -m pfc                     # 接仪器
python -m pfc.cli list            # 列出 VISA 设备
python -m pfc.cli selftest        # 写猝发并回读（默认不开射频输出）
```

配置保存在 `~/.pfc/config.json`（可用 `pfc_config.example.json` 作模板）。界面里也可选 **仿真** 模式。

### 界面操作

1. **扫描** → **连接**（或选仿真后连接）。
2. **初始化信号源**：写入频率 / 周期数 / PRF / 幅度，输出保持关闭。
3. **PCD 基线**：约 20 s 升压采集，保存 `NoMB_PCDcontrol_*.npz/.mat`。
4. **闭环超声**：MB 等待 → 基线 → 升压到目标 SC → 在容差带内维持；**Escape / 停止** 立即关输出。
5. 数据目录与编号在左侧「实验」栏。

幅度单位为 **mVpp**。若仍用 PCD 通道边沿触发，请把垂直档位与触发电平调到实际探头幅度，否则单次触发可能超时。

未移植原 MATLAB 界面中的位移台（仓库内无电机驱动）。信号源 SCPI、后面板同步与「采集时 GUI 不抢写 VISA」对齐同实验室 **DG2000-Trigger** 控制器。

## 打包成可双击运行的程序

Mac 上日常开发请直接跑源码（`python -m pfc`），不必打成 `.app`。发布包由 GitHub Actions 构建：推送到 **main**（或在 Actions 里手动 Run）时自动升版本、打 tag、打包 **macOS arm64 / Windows x64** 的 onedir zip，并发布 GitHub Release。不打 Linux 包，以节省 Action 额度。

本地若要验证打包（必须在目标系统上）：

```bash
pip install ".[build]"
python packaging/build.py
# 或 ./scripts/build_pyinstaller.sh
```

| 平台 | 产物 |
|------|------|
| macOS | `dist/PFC/PFC`，整个 `PFC` 文件夹一起拷贝 |
| Windows | `dist/PFC/PFC.exe`，整个 `PFC` 文件夹一起拷贝 |

macOS 首次打开若提示未签名：右键打开，或在「隐私与安全性」中允许。运行时仍需本机已装 NI-VISA 或 libusb。CLI（`python -m pfc.cli`）只随源码提供。

## 开发测试

```bash
pip install pytest
pytest
```

## MATLAB 旧版

需要 Instrument Control Toolbox 与 `visadev`。编辑 `rigol/rigol_instr_config.m` 填入 VISA 地址后，运行 `MatlabScript_FeedbackControl`。细节见历史说明；新实验请用 Python 版。

## 许可

©2022 Washington University。非商业、非临床、不可用于人体；完整条款见仓库原版权声明。RIGOL 仪器层与 Python 改写为本实验室扩展。
