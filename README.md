# Passive-Cavitation-Detection

PCD（被动空化检测）采集与闭环超声反馈控制。算法来自 Washington University Chen 实验室（Chien 等, *CMMM* 2022, [9867230](https://doi.org/10.1155/2022/9867230)）。本实验室 PCD 中心约 **3 MHz**，稳态空化 SC 用 **2f（3.0 MHz）**，不用原文因 4.7 MHz PCD 而选的 3f（4.5 MHz）。

本仓库以 **MATLAB + Instrument Control Toolbox（`visadev`）+ NI-VISA** 运行，硬件为实验室 **RIGOL DHO814** 与 **RIGOL DG2052**。

## 硬件

| 角色 | 型号 | 接口 |
|------|------|------|
| 示波器 | **RIGOL DHO814**（DHO800 系列） | USB-VISA / USBTMC |
| 信号源 | **RIGOL DG2052**（DG2000 系列） | USB-VISA |

VISA 地址**没有写死在代码里**。界面点 **仪器设置 → 扫描仪器**，程序会枚举本机 VISA 资源、逐个发 `*IDN?` 读出型号，空栏自动填 DHO814 / DG2052；已有地址不会被扫描冲掉。识别不出来时也能手动输入或点「设为」。命令行等价写法：

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

## 采集链（改之前先读这一节）

下面三条都是拿真实数据定位出来的，改动前请确认没有把问题放回去。改完跑一次：

```matlab
pcd_selftest_acquisition     % 不需要接仪器
```

### 1. 波形必须用 WORD 读，不要改回 BYTE

`rigol_dho814_read_channel.m` 用 `:WAVeform:FORMat WORD`。DHO814 是 12 位 ADC，
BYTE 只取低 8 位，等于白扔 24 dB 动态范围。实测某轮数据里 IC 频带（3.3 MHz 一带）
的信号只有 20–95 µV，而 BYTE 的量化噪声 RMS 就有约 72 µV —— 那时**测到的全是量化
本底**。

字节序**不能**靠发命令声明：DHO800 的 `:WAVeform:*` 一共 14 条命令，**没有**
`:WAVeform:BYTeorder`（手册 3.28 逐节核对过）。所以解码按约定来：小端 + 手写字节
拼装（不依赖宿主机字节序），并用 `YREFerence` 反推 WORD 到底是有符号补码还是偏移
二进制（手册 3.28.11 只说它随 FORMat 变、没写是哪种）——参考位置在 0 附近按补码解，
在 32768 附近按偏移二进制解。实现见 `rigol_decode_waveform.m`。

### 2. CH2 量程要留余量，削顶帧必须重采

量程照**上一帧**峰值定（`pcd_run_experiment` 的 `set_ranges`，系数 `K=1.4`：
满量程 ≈ 2.8× 峰值）。旧的 `/3.2` 余量只有 36%，信号一变大就顶穿量程。

为什么必须拦：**对称削顶只生奇次谐波**（3f/5f），偶次反而被压掉，于是 3f 假性飙升。
实测那一轮 92 帧里有 **26 帧（28%）** 峰值贴在竖直量程上限，其中 3f 电平最高的一帧
比中位帧高约 45 dB。不剔除的话，闭环会把 3f 的假性飙升当成「空化增强」去追目标值。

判定在 `rigol_dho814_clipped.m`：峰值贴到满量程 98% 即判削顶，满量程 =
`scope_vdiv`/2 × SCALe（波形以 0 V 居中）。**不要**改用波峰因数判：实测统一到
「猝发段」口径后，削顶帧 1.13–2.29、其余帧 1.51–5.19，两段区间重叠、分不开；
满量程是硬边界，才分得开。

> 事后怎么判断一帧有没有被削顶：算 `峰值 / SCALe`。贴住的帧这个比值会聚在
> 4.0–4.37（标称 ±4 格，实测硬上限 4.368），而且**在量程各不相同时比值一致**——
> 被钉在量程上限就是这个指纹；正常帧明显小于 4。

### 3. 水平偏移显式归零，并记录波形几何

`rigol_dho814_setup.m` 里 `:TIMebase:MAIN:OFFSet 0`。以前从不设置它、用的是仪器
残留状态：实测某轮 92 帧里 1 ms 的猝发只有 0.42 ms 落在采集窗内（猝发起点一致在
1.180 ms、零抖动）。后果是 SC/IC 被占空比稀释约 11 dB，而且**稀释系数取决于一个
不受控的参数** —— 换台机器、或有人动过面板，标定就变了。

手册里有两个容易望文生义的地方，别拿它们当依据：

- `:TIMebase:HREFerence:MODE LB` **不是**「把触发点放在屏幕左边」。手册 3.26.7 写的是
  「改变水平时基时，围绕屏幕左侧扩展或压缩波形」—— 它是**缩放锚点**，与触发点落在
  窗内哪个位置无关。
- `:WAVeform:XORigin?` 在 **RAW** 模式下返回的是**内存**波形的起始时间（手册 3.28.7）。
  内存记录与屏幕窗不重合时，第 1 个采样点就不在触发点上 —— 这本身就能造成一个固定
  偏移，而且归零 `MAIN:OFFSet` 治不了它。

所以每轮采集做三件事：① `MAIN:OFFSet` 归零（消除不受控状态）；② 读回
`XORigin/XREFerence/YORigin/YREFerence/YINCrement` 存进数据（`wf_*` 字段）；
③ 跑一次 `check_burst_window`，把猝发在窗内的位置打进日志、存成 `burst_align`。
对齐对不对，看日志那行与 `burst_align.in_window`，不要靠猜。

### 存进 .mat 的采集质量元数据

| 字段 | 含义 |
|------|------|
| `n_clip_retry` | 因削顶被丢弃并重采的帧数（未进 V/SC/闭环/图） |
| `n_prime_discard` | 只为标定量程而未入库的帧数（正常为 1） |
| `pcd_scale_vdiv` / `tx_scale_vdiv` | 结束时 CH1/CH2 的量程 (V/div)，解释竖直分辨率 |
| `timebase_offset_s` | 采集时实际生效的水平偏移 |
| `wf_xorigin_s` / `wf_xref` | RAW 模式下内存波形的起始时间 / 时间参考基准 |
| `wf_yorigin` / `wf_yref` / `wf_yinc` | 竖直原点 / 参考位置 / 单位电压；`wf_yref` 反映二进制约定 |
| `burst_align` | 猝发在窗内的位置：`burst_s` / `win_s` / `start_s` / `in_window` |
| `waveform_format` | `WORD`（16 位容器 / 12 位 ADC） |

> 量程：`K_DIV=1.0`（峰值占 1 格，半边满量程 ≈ **4×峰值**）。仍贴轨则丢弃重采（最多 3 次），曲线不留削顶点。
> 真机看 `n_clip_retry` 是否接近 0。


## 运行

需要：**MATLAB R2026a**、**Instrument Control Toolbox**、已安装的 **NI-VISA**。

```matlab
cd('<项目目录>')     % 例如 D:\Projects\Passive-Cavitation-Detection
pcd_app             % 启动界面（会自动把 src/ rigol/ 等加进路径）
```

界面上 **单次采集 FFT 并保存** 会从 DHO814 读回时域波形，在电脑上算 FFT。**无微泡 / 有微泡开环 / 闭环** 每一发同样刷新时域+FFT。结束后（以及 oneshot / 调试）都写成**一个目录**，raw 和分析图放在一起：

```
data/OpenMB_run_YYYYMMDD_HHMMSS/
  raw.mat           % 与旧扁平 .mat 同一套字段（顶层旧名 + params）
  params.txt        % pcd_save_params 快照
  fft_ch1.png       % CH1 谱，标 f0
  fft_ch2.png       % CH2 谱，标 f0/2f 与 2.85/4.18 EMI
  time_ch1_ch2.png  % 短时域片段
  pulse_sc_ic.png   % 电压 / SC / IC / 2f-vs-EMI（n>1 且有这些向量时）
```

界面状态栏给出的是这个**文件夹**路径。旧的扁平 `*_run_*.mat` 仍可 `load`，不改加载逻辑。出图只在存盘结束时做一次（中途每 5 发只覆盖 `raw.mat`）；画失败也不丢 raw。

DHO814 **示波器屏幕上有 Math FFT**（最多约 1 Mpts，见 [DHO800 数据手册](https://download.rigol.com/en/Manual/Digital%20Oscilloscope/DHO800/DHO800_DataSheet_EN.pdf) 与编程手册 `:MATH:FFT:*`）。闭环用的二次谐波 SC（2f）/ IC 宽带和存盘分析在 **电脑端 FFT** 完成，不依赖把示波器 MATH 波形读回来。

无换能器/50 Ω 负载时不要打开射频输出。

命令窗口也可：

```matlab
pcd_setup                % 把各子目录加进路径（新开一个 MATLAB 会话时跑一次）
test_dg2052_connection   % 信号源自检（默认不开输出）
oneshot_fft_plot         % 开环发一帧、收一帧，弹窗画频谱并保存
```

## 目录

```
Passive-Cavitation-Detection/
├── pcd_app.m             启动入口（打包入口）
├── pcd_setup.m           把各子目录加进 MATLAB 搜索路径（新会话跑一次）
├── pcd_root.m            可写工作根 / 路径锚点
├── pcd_version.m         版本号（发版只改这里）
├── update.json           发布清单（目标机「检查更新」读它）
├── src/
│   ├── ui/               界面层：uifigure 宿主、UI 适配层、配色、对话框
│   ├── core/             业务逻辑：参数校验、采集/闭环流程、信号处理、存盘
│   └── io/               仪器与配置：VISA、参数存档、检查更新
├── rigol/                RIGOL DHO814 / DG2052 驱动与自检、单次收发
├── web/                  新版界面前端：index.html + Alpine.js + uPlot（离线静态资源）
├── tools/                构建与发布脚本（不参与运行）：pcd_build_exe / pcd_release
├── tests/                不依赖硬件的自检：pcd_selftest_acquisition
├── data/                 采集默认保存目录（不入库）
└── manuals/              厂商手册副本（不入库）
```

各层里的关键文件：

| 路径 | 内容 |
|------|------|
| `src/ui/pcd_ui_app.m` | 新版界面宿主（`uifigure` + `uihtml`）与事件分发 |
| `src/ui/pcd_ui_html.m` | UI 适配层：算法层只认这层接口（约定与校验见 `pcd_ui_check.m`） |
| `src/ui/pcd_ui_check.m` | 校验算法层收到的适配层是否具备约定接口 |
| `src/ui/pcd_ui_push.m` / `pcd_web_root.m` | 推数据给前端 / 前端资源路径（源码·打包两种模式） |
| `src/ui/pcd_instr_dialog.m` | 仪器设置对话框（扫描 + 选择 + 手动输入） |
| `src/ui/pcd_update_flow.m` | 「检查更新」交互流程 |
| `src/core/pcd_fus_params.m` | FUS 参数校验与推导（唯一出处） |
| `src/core/pcd_run_experiment.m` / `pcd_oneshot.m` / `pcd_debug_run.m` | 闭环 / 单次 / 调试流程 |
| `src/core/pcd_debug_no_mb.m` / `pcd_debug_live.m` | 开环调试与运行中实时改参数 |
| `src/core/pcd_spectrum.m` / `pcd_band_energy.m` / `pcd_fft_peak_mhz.m` | 信号处理 |
| `src/core/pcd_save_acquisition.m` / `pcd_save_run_plots.m` | 一次实验一个目录（raw.mat + 分析图） |
| `src/core/pcd_save_params.m` | 存盘参数快照 |
| `src/core/pcd_fitrow.m` | 采样帧定长整形（空帧/不等长帧的兜底，两种采集路径共用） |
| `src/io/pcd_visa.m` | 仪器连接与运行锁 |
| `src/io/pcd_prefs.m` | 界面参数持久化 |
| `src/io/pcd_update.m` | 检查更新（默认源写死 + 本地 `pcd_update.ini` 覆盖） |
| `rigol/rigol_scan_instruments.m` / `rigol_visa_table.m` | 仪器自动扫描 / `visadevlist` 返回值解析 |
| `rigol/rigol_decode_waveform.m` / `rigol_dho814_clipped.m` | 波形解码（WORD/BYTE）／削顶判定 |
| `tests/pcd_selftest_acquisition.m` | 采集链自检（不需要仪器） |

幅度单位为 **mVpp**。本实验室无位移台，电机区已从界面隐藏。

## 一套源码，两种运行方式

开发调试与打包分发共用同一份代码，差异只由 `isdeployed` 与 `pcd_root()` 处理。新增功能请只走下列入口，不要在别处再写一套：

| 关注点 | 唯一出处 |
|--------|----------|
| 启动入口 | `pcd_app.m` |
| 可写路径（存档 / 数据 / 配置） | `pcd_root()` |
| 前端样式 / 配色 | `web/app.css`（页面）+ `src/ui/pcd_ui_colors.m`（MATLAB 原生窗口与对话框） |
| 仪器地址 | `rigol/rigol_instr_config.m`（默认值 + 本地 `rigol_config.ini`） |
| 界面参数 | `src/io/pcd_prefs.m` |
| FUS 参数校验 | `src/core/pcd_fus_params.m` |
| 版本号 | `pcd_version.m`（发版只改这里） |
| 更新源 | `src/io/pcd_update.m` + 本地 `pcd_update.ini`（没有该文件＝关闭更新检查） |

## 本机配置的存放位置

界面参数（频率/电压/PRF/周期数/时长/采样点/目标/上限/ID/目录等）、默认数据目录、仪器 VISA 地址都会自动持久化，**换台机器不用重调**。它们都写在"可写工作根"下：

| 运行方式 | 工作根 | 说明 |
|----------|--------|------|
| 源码运行 | 项目根目录 | 与以前一致 |
| 打包 exe 运行 | `%LOCALAPPDATA%\PCD`（Windows） | 可用环境变量 `PCD_HOME` 指定别处 |

| 文件 | 作用 | 删除后 |
|------|------|--------|
| `pcd_prefs.mat` | 界面参数存档 | 回到界面默认值 |
| `rigol_config.ini` | 仪器 VISA 地址与通道覆盖 | 回到空地址（须重新扫描） |
| `pcd_update.ini` | 更新源地址 | 关闭更新检查 |
| `data/` | 默认采集输出目录 | 下次自动重建 |

仪器地址在界面点 **仪器设置** 即可修改（换仪器/换电脑无需改代码）。点进去先 **扫描仪器**，
空栏会自动填识别到的 DHO814 / DG2052；已有地址不会被冲掉。可用 **试连接** 确认 *IDN?*。

## 界面

界面本体是 `web/` 下的静态网页（Alpine.js + uPlot），由 `uifigure` + `uihtml` 嵌进 MATLAB 窗口；
MATLAB 只负责仪器与算法，两者走 `uihtml` 的双向通道：

| 方向 | 通道 |
|------|------|
| MATLAB → 前端 | `pcd_ui_push`（写 `h.Data`） |
| 前端 → MATLAB | `sendEventToMATLAB` → `src/ui/pcd_ui_app.m` 里的 `pcd_ui_event` |

布局、分辨率/DPI 自适应、圆角一律交给 CSS，图表交给 uPlot；MATLAB 侧只有窗口底色和
「仪器设置」对话框需要自己配色，见 `src/ui/pcd_ui_colors.m`。

算法层不直接碰控件，只通过「UI 适配层」（`src/ui/pcd_ui_html.m`）操作界面：它把界面操作收敛成
`ui.params() / ui.raw() / ui.debugfv() / ui.outdir() / ui.waveform() / ui.trend() /
ui.clearTrend() / ui.status()` 八个函数句柄，接口约定与校验见 `src/ui/pcd_ui_check.m`。
因此 `pcd_run_experiment`、`pcd_oneshot`、`pcd_debug_run`、`pcd_debug_no_mb` 与界面完全无关 ——
将来要换一种界面实现，算法层一行都不用改。

前端可**脱离 MATLAB 单独在浏览器预览**（自动跑演示数据），调样式很快：

```bash
cd web && python3 -m http.server 8765   # 打开 http://127.0.0.1:8765
```

## 打包成 Windows 独立程序（可选）

需要一台装了 **MATLAB + MATLAB Compiler + MATLAB Compiler SDK + Instrument Control Toolbox** 的 Windows
机器 —— **Compiler 不支持交叉编译，macOS 上无法产出 Windows exe**。后两者不能省：`rigol/` 的
`visadev` 通信要随 exe 打进 Runtime 侧依赖（缺 ICT 编译时直接报错），安装包由 Compiler SDK 生成。

```matlab
pcd_build_exe                  % 编译 exe，并打包安装程序
pcd_build_exe('noinstaller')   % 只编译 exe
```

脚本会先把项目根下所有子目录（`src/`、`rigol/` 等）加进路径再编译 —— mcc 的依赖分析只认
「编译时在路径上」的文件，漏掉 `src/` 或 `rigol/` 会编译通过、exe 一跑才报 `Undefined function`。
`web/` 属于静态资源、不在依赖分析范围内，由脚本作为附加文件打进去；注意打包后它**不在**
`<ctfroot>\web`，而被解到 `<ctfroot>\pcd_app\web`，定位逻辑见 `src/ui/pcd_web_root.m`。

打包用 `compiler.build.standaloneWindowsApplication`，**不要**换回 `standaloneApplication`：
后者生成的是控制台子系统程序，双击会先弹一个黑色 cmd 窗口，界面还没出来；关掉它还连带把程序关掉。
前者参数完全一致，只是不启动 Windows 命令行。

产物在 `build/` 下：

| 文件 | 说明 |
|------|------|
| `pcd_app.exe` | 独立程序本体（约 1.5 MB，已内含 `src/`、`rigol/` 驱动与 `web/` 前端资源） |
| `PCD_Installer_v<版本>.exe` | 分发用安装程序（约 3 MB）；**文件名带版本号**，下载目录里一眼能区分 |

程序内部的程序名固定为 `pcd_app`（不带版本号）—— 若把版本号写进程序名，每版在 Windows 眼里
都是另一个产品，覆盖安装会失效、「应用和功能」里还会堆一串旧条目。

## 分发到目标机

**只分发 `PCD_Installer_v<版本>.exe` 即可。** 目标机双击它，安装向导会自动从 MathWorks 下载并
安装 MATLAB Runtime，装完桌面/开始菜单就有图标，之后点击即用 —— 部署的人不用自己去找 Runtime。

前提是**目标机安装时能上外网**（安装器会拉 ~5 GB 的 Runtime）。交付方式由脚本自动选：

| 编译机上 | `RuntimeDelivery` | 目标机安装时 |
|----------|-------------------|--------------|
| 没有 Runtime 安装包（默认） | `web` | 联网自动下载并安装 Runtime |
| 先跑过 `compiler.runtime.download` | `installer` | 断网也能装（安装包体积大得多） |

`pcd_app.exe` **不能单独分发**：MATLAB Compiler 生成的 exe 不含解释器，必须在本机找到
版本匹配的 MATLAB Runtime（它靠注册表定位，`RegQueryValueExW`），因此不存在"拷贝即运行"
的免安装形态 —— 绿色版这条路走不通。

目标机上还需要（安装器不负责这些）：

1. **MATLAB Runtime R2026a** —— 已由安装程序处理；
2. **NI-VISA**（或仪器厂商 VISA）+ 仪器 USB 驱动 —— `visadev` 依赖它，且不在 Runtime 内。

打包后换仪器不用重新编译：运行程序 → 界面 **仪器设置** → 填 VISA 地址。

### 升级与卸载

- **走界面里的「检查更新」最省事**：程序会自己下载、关闭、再启动安装程序，不需要你手工处理。
- **手动装的话，必须先退出程序。** MATLAB 生成的安装程序**既不检测也不提示**目标程序是否在
  运行 —— 遇到被占用的 `pcd_app.exe` 会**静默跳过替换**，装完看着像装成功了，其实还是旧版。
  确认装没装上的办法：看 Windows「应用和功能」里的版本号，或程序窗口标题上的版本号。
- **卸载**：Windows「设置 → 应用」里的 `pcd_app`，或直接运行
  `%ProgramFiles%\pcd_app\uninstall\bin\win64\Uninstall_Application.exe`。
  卸载不会动 `%LOCALAPPDATA%\PCD` 下的采集数据与界面参数。

## 软件更新

「文件」面板右上角有 **检查更新** 按钮；当前版本号显示在窗口标题上。

### 怎么工作

1. 取更新源（**写死在程序里**，见下；运维可用本地配置文件覆盖）；
2. 拉取该地址的**更新清单**（JSON），与 `pcd_version()` 比较版本；
3. 没有新版就直接告诉你「已是最新版本」，到此结束；
4. 有新版才弹窗问一句，确认后：下载安装包到临时目录 → **自动关闭本程序** → 启动安装程序
   （留 5 秒等程序退出。安装程序替换不掉正在使用的 `pcd_app.exe`，所以必须先退）。

### 更新源

**默认源已经写死在程序里**（`pcd_update.m` 的 `default_source()`），指向本仓库：

```
https://raw.githubusercontent.com/AsagiriBeta/Passive-Cavitation-Detection/main/update.json
```

所以目标机**装上就能直接点「检查更新」，不用先配一遍**。

| 内容 | 放哪 |
|------|------|
| `update.json` | 仓库根目录（就几行文本，跟着源码走） |
| `PCD_Installer_v<版本>.exe` | **GitHub Release 附件**（不提交进仓库，否则每发一版都给 git 历史永久增加约 3 MB） |

**界面上没有任何更新源设置** —— 用户点「检查更新」只会得到「有更新」或「已是最新」两种结果。
`pcd_update.ini` 是留给运维的兜底（内网服务器、局域网共享、隔离网回不了源），装上后不生成、
不提示，需要时才手工放一个：

```
source=https://example.com/pcd/update.json     # 任意 HTTPS，Gitee / 内网服务器同理
source=\\server\share\pcd\update.json          # 局域网共享，目标机不必上网
source=none                                    # 关闭更新检查
```

删掉该文件即回到默认源（注意是**回到默认**，不是关闭）。

> 更新源必须是**公开**仓库：私有仓库的 raw 链接需要 access token，程序不带鉴权，会返回 404
> （报错里会提示这一条）。

> **刚发完版后的一段时间内，点「检查更新」可能仍读到旧清单**：`raw.githubusercontent.com`
> 有多台 CDN 边缘节点、各自缓存且刷新时机不同，不同机器会命中不同节点。实测加查询参数会被
> CDN 忽略、`github.com/.../raw/...` 也绕不过，而 GitHub API 能立刻拿到新内容 —— 说明这是缓存
> 而非发版失败；实测有节点超过 15 分钟仍未刷新。
>
> **所以别用「检查更新」来验证发布，看仓库的 Release 页面更可靠。** 正常使用（两次发版间隔
> 较久）不受影响。

### 更新清单格式

`url` 指向**带版本号的那次 Release**（不是 `releases/latest`）：文件名带版本号后，`latest` 那条
路会指向不存在的旧文件名。`version` 与 `url` 都由 `pcd_installer_asset.m` 按当前版本算出，
你只维护 `notes`：

```json
{
  "version": "0.2.0",
  "url": "https://github.com/AsagiriBeta/Passive-Cavitation-Detection/releases/download/v0.2.0/PCD_Installer_v0.2.0.exe",
  "notes": "新增仪器自动扫描；修复 XXX"
}
```

### 发版流程

**只需改 `pcd_version.m` 里的版本号，然后跑一条命令：**

```matlab
pcd_version                            % 看一眼当前版本
pcd_release                            % 打包 → 建 v<版本> Release 并上传安装包 → 推送清单
pcd_release('notes', '这一版改了什么')   % 顺手写更新说明
```

`pcd_release` 会自动：校验版本号（tag 已存在就拒绝，防重复发版）→ 打包 → 建 `v<版本>`
的 Release 并上传安装包 → 提交并推送 `update.json`。清单里的 `version` 直接取自
`pcd_version()`，所以不会出现「包是新的、清单还是旧的」。

前置条件（各一次）：

1. 编译机装 **gh**（GitHub CLI）并登录：`gh auth login`；
2. 配好 git 身份，否则提交会报 `Author identity unknown`：
   `git config --global user.name "…"` 与 `git config --global user.email "…"`；
3. 网络到不了 GitHub 时给 git 配代理：`git config --global http.proxy http://127.0.0.1:7890`。

程序只做「下载 + 关闭自己 + 启动安装程序」，不会静默覆盖文件；装不装由用户在弹窗里确认。

### 已经部署的旧版怎么升级

**关键前提：更新功能是 v0.1.0 才有的。** 更早的版本界面上既没有「检查更新」按钮、也不显示
版本号，所以它**无法自我更新**，那些机器必须人工装一次新安装包：

| 目标机当前版本 | 升级方式 |
|----------------|----------|
| v0.1.0 之前（无更新按钮） | 拷 `PCD_Installer_v<版本>.exe` 过去，**先退出程序**再双击；装完就有更新功能了 |
| v0.1.0 / v0.1.1 | 点 **检查更新** → 确认 → 自动下载并启动安装器；这两版**不会自动关程序**，要自己先关 |
| v0.1.2 及以后 | 点 **检查更新** → 确认 → 自动下载 → **自动关闭程序** → 启动安装器 |

几点注意：

- **装之前程序必须是关的**（v0.1.2 起由程序自动关闭）。安装程序替换不掉运行中的 `pcd_app.exe`，
  而且它**不报错也不提示**，装完看着像成功、其实还是旧版 —— 用「应用和功能」或窗口标题上的
  版本号确认一下最稳。
- **不用先卸载旧版**：安装程序装到同一目录并覆盖程序文件。
- **参数与数据不会丢**：界面参数、仪器地址在 `%LOCALAPPDATA%\PCD` 下，不在安装目录里，
  采集数据也在你指定的目录，升级都不受影响 —— 装完不用重调参数。
- 升级后建议先点 **仪器设置 → 扫描仪器** 确认仪器还认得出来，再跑采集。

## 许可

©2022 Washington University。非商业、非临床、不可用于人体。RIGOL 仪器层为本实验室扩展。
