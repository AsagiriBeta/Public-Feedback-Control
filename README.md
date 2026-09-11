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
| `PFC_Installer_v<版本>.exe` | 分发用安装程序（约 3 MB）；**文件名带版本号**，下载目录里一眼能区分 |

程序内部的程序名固定为 `pfc_app`（不带版本号）—— 若把版本号写进程序名，每版在 Windows 眼里
都是另一个产品，覆盖安装会失效、「应用和功能」里还会堆一串旧条目。

## 分发到目标机

**只分发 `PFC_Installer_v<版本>.exe` 即可。** 目标机双击它，安装向导会自动从 MathWorks 下载并
安装 MATLAB Runtime，装完桌面/开始菜单就有图标，之后点击即用 —— 部署的人不用自己去找 Runtime。

前提是**目标机安装时能上外网**（安装器会拉 ~5 GB 的 Runtime）。交付方式由脚本自动选：

| 编译机上 | `RuntimeDelivery` | 目标机安装时 |
|----------|-------------------|--------------|
| 没有 Runtime 安装包（默认） | `web` | 联网自动下载并安装 Runtime |
| 先跑过 `compiler.runtime.download` | `installer` | 断网也能装（安装包体积大得多） |

`pfc_app.exe` **不能单独分发**：MATLAB Compiler 生成的 exe 不含解释器，必须在本机找到
版本匹配的 MATLAB Runtime（它靠注册表定位，`RegQueryValueExW`），因此不存在"拷贝即运行"
的免安装形态 —— 绿色版这条路走不通。

目标机上还需要（安装器不负责这些）：

1. **MATLAB Runtime R2026a** —— 已由安装程序处理；
2. **NI-VISA**（或仪器厂商 VISA）+ 仪器 USB 驱动 —— `visadev` 依赖它，且不在 Runtime 内。

打包后换仪器不用重新编译：运行程序 → 界面 **仪器设置** → 填 VISA 地址。

### 升级与卸载

- **走界面里的「检查更新」最省事**：程序会自己下载、关闭、再启动安装程序，不需要你手工处理。
- **手动装的话，必须先退出程序。** MATLAB 生成的安装程序**既不检测也不提示**目标程序是否在
  运行 —— 遇到被占用的 `pfc_app.exe` 会**静默跳过替换**，装完看着像装成功了，其实还是旧版。
  确认装没装上的办法：看 Windows「应用和功能」里的版本号，或程序窗口标题上的版本号。
- **卸载**：Windows「设置 → 应用」里的 `pfc_app`，或直接运行
  `%ProgramFiles%\pfc_app\uninstall\bin\win64\Uninstall_Application.exe`。
  卸载不会动 `%LOCALAPPDATA%\PFC` 下的采集数据与界面参数。

## 软件更新

「文件」面板右上角有 **检查更新** 按钮；当前版本号显示在窗口标题上。

### 怎么工作

1. 取更新源（**写死在程序里**，见下；运维可用本地配置文件覆盖）；
2. 拉取该地址的**更新清单**（JSON），与 `pfc_version()` 比较版本；
3. 没有新版就直接告诉你「已是最新版本」，到此结束；
4. 有新版才弹窗问一句，确认后：下载安装包到临时目录 → **自动关闭本程序** → 启动安装程序
   （留 5 秒等程序退出。安装程序替换不掉正在使用的 `pfc_app.exe`，所以必须先退）。

### 更新源

**默认源已经写死在程序里**（`pfc_update.m` 的 `default_source()`），指向本仓库：

```
https://raw.githubusercontent.com/AsagiriBeta/Public-Feedback-Control/main/update.json
```

所以目标机**装上就能直接点「检查更新」，不用先配一遍**。

| 内容 | 放哪 |
|------|------|
| `update.json` | 仓库根目录（就几行文本，跟着源码走） |
| `PFC_Installer_v<版本>.exe` | **GitHub Release 附件**（不提交进仓库，否则每发一版都给 git 历史永久增加约 3 MB） |

**界面上没有任何更新源设置** —— 用户点「检查更新」只会得到「有更新」或「已是最新」两种结果。
`pfc_update.ini` 是留给运维的兜底（内网服务器、局域网共享、隔离网回不了源），装上后不生成、
不提示，需要时才手工放一个：

```
source=https://example.com/pfc/update.json     # 任意 HTTPS，Gitee / 内网服务器同理
source=\\server\share\pfc\update.json          # 局域网共享，目标机不必上网
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
路会指向不存在的旧文件名。`version` 与 `url` 都由 `pfc_installer_asset.m` 按当前版本算出，
你只维护 `notes`：

```json
{
  "version": "0.2.0",
  "url": "https://github.com/AsagiriBeta/Public-Feedback-Control/releases/download/v0.2.0/PFC_Installer_v0.2.0.exe",
  "notes": "新增仪器自动扫描；修复 XXX"
}
```

### 发版流程

**只需改 `pfc_version.m` 里的版本号，然后跑一条命令：**

```matlab
pfc_version                            % 看一眼当前版本
pfc_release                            % 打包 → 建 v<版本> Release 并上传安装包 → 推送清单
pfc_release('notes', '这一版改了什么')   % 顺手写更新说明
```

`pfc_release` 会自动：校验版本号（tag 已存在就拒绝，防重复发版）→ 打包 → 建 `v<版本>`
的 Release 并上传安装包 → 提交并推送 `update.json`。清单里的 `version` 直接取自
`pfc_version()`，所以不会出现「包是新的、清单还是旧的」。

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
| v0.1.0 之前（无更新按钮） | 拷 `PFC_Installer_v<版本>.exe` 过去，**先退出程序**再双击；装完就有更新功能了 |
| v0.1.0 / v0.1.1 | 点 **检查更新** → 确认 → 自动下载并启动安装器；这两版**不会自动关程序**，要自己先关 |
| v0.1.2 及以后 | 点 **检查更新** → 确认 → 自动下载 → **自动关闭程序** → 启动安装器 |

几点注意：

- **装之前程序必须是关的**（v0.1.2 起由程序自动关闭）。安装程序替换不掉运行中的 `pfc_app.exe`，
  而且它**不报错也不提示**，装完看着像成功、其实还是旧版 —— 用「应用和功能」或窗口标题上的
  版本号确认一下最稳。
- **不用先卸载旧版**：安装程序装到同一目录并覆盖程序文件。
- **参数与数据不会丢**：界面参数、仪器地址在 `%LOCALAPPDATA%\PFC` 下，不在安装目录里，
  采集数据也在你指定的目录，升级都不受影响 —— 装完不用重调参数。
- 升级后建议先点 **仪器设置 → 扫描仪器** 确认仪器还认得出来，再跑采集。

## 许可

©2022 Washington University。非商业、非临床、不可用于人体。RIGOL 仪器层为本实验室扩展。
