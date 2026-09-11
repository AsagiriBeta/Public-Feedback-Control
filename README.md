# Public-Feedback-Control

PCD（被动空化检测）采集与闭环超声反馈控制。算法来自 Washington University Chen 实验室（Chien 等, *CMMM* 2022, [9867230](https://doi.org/10.1155/2022/9867230)）。本实验室 PCD 中心约 **3 MHz**，稳态空化 SC 用 **2f（3.0 MHz）**，不用原文因 4.7 MHz PCD 而选的 3f（4.5 MHz）。

本仓库以 **MATLAB + Instrument Control Toolbox（`visadev`）+ NI-VISA** 运行，硬件为实验室 **RIGOL DHO814** 与 **RIGOL DG2052**。

## 硬件

| 角色 | 型号 | 接口 |
|------|------|------|
| 示波器 | **RIGOL DHO814**（DHO800 系列） | USB-VISA / USBTMC |
| 信号源 | **RIGOL DG2052**（DG2000 系列） | USB-VISA |

VISA 地址的默认值在 `rigol/rigol_instr_config.m`。实际使用时**不用手抄地址**：界面点
**仪器设置 → 扫描仪器**，程序会枚举本机 VISA 资源、逐个发 `*IDN?` 读出型号，自动把 DHO814 /
DG2052 填好；识别不出来时也能手动输入。命令行等价写法：

```matlab
devs = rigol_scan_instruments();            % 看看都挂着什么仪器
cfg  = rigol_instr_config('autodetect');    % 自动填好识别到的示波器/信号源
rigol_instr_config('save', cfg);            % 落盘
```

官方手册请从产品页下载；本机副本可放在 `manuals/`（不入库）。

### 接线（本实验室）

| 示波器 | 信号 |
|--------|------|
| **CH1** | 波形发生器回读（触发；FFT 应见 **1.5 MHz**） |
| **CH2** | PCD 接收 |

DHO814 **没有 EXT 口**，因此用 CH1 边沿触发每一发。无换能器/50 Ω 负载时不要打开射频输出。

## 运行

需要：**MATLAB R2020b+**（本机为 R2026a）、**Instrument Control Toolbox**、已安装的 **NI-VISA**。

```matlab
cd('<项目目录>')     % 例如 D:\Projects\Public-Feedback-Control
start_gui           % GUIDE 主界面（等价于 pfc_app）
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
| `pfc_instr_dialog.m` | 仪器设置对话框（扫描 + 选择 + 手动输入） |
| `pfc_version.m` / `pfc_update.m` | 版本号（唯一出处）／更新检查与安装 |
| `pfc_build_exe.m` | Windows 打包脚本 |
| `pfc_visa.m` / `pfc_gui_busy.m` / `pfc_ensure_save_dir.m` 等 | 连接、运行锁、存盘等公共件 |
| `rigol/rigol_scan_instruments.m` / `rigol_visa_table.m` | 仪器自动扫描 / `visadevlist` 返回值解析 |
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
| 版本号 | `pfc_version.m`（发版只改这里） |
| 更新源 | `pfc_update.m` + 本地 `pfc_update.ini`（没有该文件＝关闭更新检查） |

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
| `pfc_update.ini` | 更新源地址 | 关闭更新检查 |
| `data/` | 默认采集输出目录 | 下次自动重建 |

仪器地址在界面点 **仪器设置** 即可修改（换仪器/换电脑无需改代码）；点进去先按 **扫描仪器**
能自动识别接着的 DHO814 / DG2052。

## 打包成 Windows 独立程序（可选）

需要一台装了 **MATLAB + MATLAB Compiler + MATLAB Compiler SDK + Instrument Control Toolbox** 的 Windows
机器 —— **Compiler 不支持交叉编译，macOS 上无法产出 Windows exe**。后两者不能省：`rigol/` 的
`visadev` 通信要随 exe 打进 Runtime 侧依赖（缺 ICT 编译时直接报错），安装包由 Compiler SDK 生成。

```matlab
pfc_build_exe                  % 编译 exe，并打包安装程序
pfc_build_exe('noinstaller')   % 只编译 exe
```

脚本会先把项目根与 `rigol/` 加进路径再编译 —— mcc 的依赖分析只认「编译时在路径上」的文件，
漏掉 `rigol/` 会编译通过、exe 一跑才报 `Undefined function 'rigol_xxx'`。

产物在 `build/` 下：

| 文件 | 说明 |
|------|------|
| `pfc_app.exe` | 独立程序本体（约 1.5 MB，已内含 `rigol/` 驱动与 `.fig` 界面） |
| `PFC_Installer.exe` | 分发用安装程序（约 3 MB）；Runtime 交付方式见下 |

## 分发到目标机

**只分发 `PFC_Installer.exe` 即可。** 目标机双击它，安装向导会自动从 MathWorks 下载并安装
MATLAB Runtime，装完桌面/开始菜单就有图标，之后点击即用 —— 部署的人不用自己去找 Runtime。

前提是**目标机安装时能上外网**（安装器会拉 ~5 GB 的 Runtime）。交付方式由脚本自动选：

| 编译机上 | `RuntimeDelivery` | 目标机安装时 |
|----------|-------------------|--------------|
| 没有 Runtime 安装包（默认） | `web` | 联网自动下载并安装 Runtime |
| 先跑过 `compiler.runtime.download` | `installer` | 断网也能装（安装包体积大得多） |

`pfc_app.exe` **不能单独分发**：MATLAB Compiler 生成的 exe 不含解释器，必须在本机找到
版本匹配的 MATLAB Runtime（它靠注册表定位，`RegQueryValueExW`），因此不存在"拷贝即运行"
的免安装形态 —— 绿色版这条路走不通。

目标机上还需要（安装器不负责这些）：

1. **MATLAB Runtime R2026a** —— 已由 `PFC_Installer.exe` 处理；
2. **NI-VISA**（或仪器厂商 VISA）+ 仪器 USB 驱动 —— `visadev` 依赖它，且不在 Runtime 内。

打包后换仪器不用重新编译：运行程序 → 界面 **仪器设置** → 填 VISA 地址。

## 软件更新

「文件」面板右上角有 **检查更新** 按钮；当前版本号显示在窗口标题上。

### 怎么工作

1. 读 `<工作根>/pfc_update.ini` 里的 `source`（更新源）；
2. 拉取该地址的**更新清单**（JSON），与 `pfc_version()` 比较版本；
3. 有新版就弹窗问一句，确认后把安装包下载到临时目录并**启动安装程序**；
4. 安装程序要替换程序文件，所以会先提示你关掉本程序。

首次点「检查更新」若提示未配置更新源，跟着弹窗填地址即可。

### 更新源

两种写法都支持，目标机不必上外网：

```
source=https://your-server/pfc/update.json      # 内网 HTTP 服务
source=\\nas\share\pfc\update.json              # 局域网共享
```

### 更新清单格式

```json
{
  "version": "0.2.0",
  "url": "PFC_Installer.exe",
  "notes": "新增仪器自动扫描；修复 XXX"
}
```

`url` 写相对路径时按清单所在目录解析，所以把整个发布目录（`update.json` + `PFC_Installer.exe`）
一起丢到服务器或共享盘即可，换机器不用改。

### 发版流程

1. 改 `pfc_version.m` 里的版本号（唯一出处）；
2. `pfc_build_exe` 出新的 `PFC_Installer.exe`；
3. 把新的 `update.json`（`version` 改成新号）与 `PFC_Installer.exe` 覆盖到更新源目录。

程序只做「下载 + 启动安装程序」，不会静默覆盖文件；装不装由用户在弹窗里确认。

### 已经部署的旧版怎么升级

**关键前提：更新功能是 v0.1.0 才有的。** 更早的版本界面上既没有「检查更新」按钮、也不显示
版本号，所以它**无法自我更新**，那些机器必须人工装一次新安装包：

| 目标机当前版本 | 升级方式 |
|----------------|----------|
| v0.1.0 之前（无更新按钮） | 从共享盘/更新源拷 `PFC_Installer.exe` 过去，双击装一次；装完就有更新功能了 |
| v0.1.0 及以后 | 界面点 **检查更新** → 确认 → 自动下载并启动安装器 → 关掉程序等它装完 |

几点注意：

- **升级时程序必须关闭**，否则安装器替换不了正在运行的 exe。点「检查更新」时程序会提示先关掉。
- **不用先卸载旧版**：安装程序装到同一目录并覆盖程序文件；若它提示"已安装"，按提示覆盖/修复即可。
- **参数与数据不会丢**：界面参数、仪器地址、更新源都在 `%LOCALAPPDATA%\PFC` 下，不在安装目录里，
  采集数据也在你指定的目录，升级都不受影响 —— 装完不用重调参数。
- 升级后建议先点 **仪器设置 → 扫描仪器** 确认仪器还认得出来，再跑采集。

## 许可

©2022 Washington University。非商业、非临床、不可用于人体。RIGOL 仪器层为本实验室扩展。
