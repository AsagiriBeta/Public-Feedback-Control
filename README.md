# Public-Feedback-Control（RIGOL 示波器 / 信号源改版）

本仓库脚本用于 PCD（被动空化检测）信号采集与闭环反馈超声实验，算法与界面源自 Washington University Chen 实验室开源实现，对应论文：

Chien 等, *Blood-Brain Barrier Opening by Individualized Closed-Loop Feedback Control of Focused Ultrasound*, [Hindawi CMMM 2022, 9867230](https://doi.org/10.1155/2022/9867230)（本地 PDF 可参考 `2022_9867230.pdf`）。

## 相对原版的硬件与软件变更

| 项目 | 原版（文献配套） | 本实验室配置 |
|------|------------------|--------------|
| 采集 | PicoScope PS5000A + Pico MATLAB SDK | **RIGOL DHO814**（DHO800 系列，USB-VISA / USBTMC） |
| 激励 | 依赖外部 `fgen_*_UTSW` 驱动（未随仓库提供） | **RIGOL DG2052**（DG2000 系列，USB-VISA） |
| 通信 | Pico SDK | **MATLAB Instrument Control Toolbox**，`visadev` 访问 VISA 资源字符串 |

示波器 SCPI 依据 **RIGOL《DHO800/DHO900 Programming Guide》**（与 DHO814 同一命令体系）：波形读取流程为 `:STOP` → `:WAVeform:MODE RAW` → `:WAVeform:DATA?` 等（手册 3.28 节）。  
信号源命令依据 **DG2000 编程手册**中的 `:SOURce<n>:`、`:BURSt:`、`:OUTPut<n>:` 子系统；猝发参数在 `BURSt:STATe ON` 之前写完（与手册建议一致），周期使用 `BURSt:INTernal:PERiod`。

官方资料入口（下载编程指南与用户手册）：

- [RIGOL DHO800 产品页 / 手册下载](https://www.rigol.com/zh_CN/products/oscilloscope/DHO800.html)
- [RIGOL DG2000 / DG2052 产品页](https://www.rigol.com/zh_CN/products/function-arbitrary-waveform-generator/DG2000.html)

## 环境要求

1. **MATLAB**（建议 R2020b 及以上，需支持 `visadev`）。
2. **Instrument Control Toolbox**。
3. 计算机已安装 **VISA** 运行时（常见为 **NI-VISA** 或厂商配套 USBTMC 驱动），USB 连接后可在资源列表中看到 `USB0::...::INSTR` 类地址。
4. 将本仓库置于 MATLAB 路径中；`MatlabScript_FeedbackControl` 启动时会 `addpath(fullfile(pwd,'rigol'))`。

## 仪器配置（必做）

编辑 **`rigol/rigol_instr_config.m`**：

- `scope_visa`、`awg_visa`：在 MATLAB 中执行 `visadevlist`，将 DHO814 与 DG2052 对应的 **完整 VISA 资源字符串**粘贴到配置中（勿沿用占位符 `YOUR_*_SERIAL`）。
- `scope_channel`：接 PCD 信号的通道（1–4）。
- `awg_channel`：用于激励的通道（1 或 2）。

可选参数：

- `harmonic_bandwidth_hz`：由基频自动划分 FFT 谐波带时的带宽（默认 200 kHz）。
- `use_legacy_fft_bins`：若为 `true`，则使用原仓库中针对 Picoscope 固定采样配置的硬编码索引（仅在与旧数据严格对比时使用；若 NFFT 与采样率不一致可能导致越界）。

## DG2052 连接自检

填好 `rigol_instr_config.m` 中的 `awg_visa` 后，可在 MATLAB 中运行：

```matlab
run('rigol/test_dg2052_connection.m')
```

脚本会查询 `*IDN?`、写入 1 kHz / 20 mVpp 连续正弦并回读频率与幅度，再调用与主界面相同的 `rigol_dg2052_apply_burst` 做一次猝发配置。默认**不打开**前面板射频输出；若需验证实际输出，将脚本内 `enable_output_pulse` 改为 `true`（务必确认下游功放/换能器与负载安全）。

## 使用顺序建议

1. 连接 USB，确认 `visadevlist` 中两台仪器均出现。
2. （建议）运行 `rigol/test_dg2052_connection.m` 确认 DG2052 程控正常。
3. 在 GUI 中点击 **IniFgen**（或等价回调），初始化全局 `fgen` 与 DG2052 猝发参数。
4. 按原流程进行 **PCDcontrol** / **Sonication**；采集由 DHO814 单次触发 + RAW 波形读取完成。

## 触发与垂直刻度

默认在 `rigol_dho814_setup.m` 中为 **CHn DC 耦合**、边沿触发、触发电平约 **10 mV**（`TRIGger:EDGE:LEVel`）。若 PCD 信号幅度不同，请在示波器面板或该文件中调整 **垂直档位 `CHANnel<n>:SCALe`** 与 **触发电平**，否则可能无法稳定单次触发。

## FFT 频带说明

原版在固定 `realFs` 与 `depth` 下使用固定索引 `SC_range` / `IC_range`。改版后默认按 GUI 中的 **基频（MHz）** 估算 **3× 基频** 与 **基频/2** 附近的频带求和，以适配 `ACQuire:SRATe?` 得到的实际采样率。若需与历史 Picoscope 数据完全一致，在配置中开启 `use_legacy_fft_bins` 并保证 `NFFT` 与旧实验一致。

## 代码贡献与版权

代码由 Chih-Yen Chien 等开发，并经 Chen Ultrasound Lab 成员扩展；本分支增加 RIGOL 仪器层与说明文档。

## Copyright Notice: ©2022 Washington University

Washington University hereby grants to you a non-transferable, non-exclusive, royalty-free, non-commercial, non-clinical, not-for-use with human subjects, research license to use and copy the computer code that may be downloaded within this site (the “Software”). You agree to include this license and the above copyright notice in all copies of the Software. The Software may not be distributed, shared, or transferred to any third party. This license does not grant any rights or licenses to any other patents, copyrights, or other forms of intellectual property owned or controlled by Washington University.

YOU AGREE THAT THE SOFTWARE PROVIDED HEREUNDER IS EXPERIMENTAL AND IS PROVIDED “AS IS”, WITHOUT ANY WARRANTY OF ANY KIND, EXPRESSED OR IMPLIED, INCLUDING WITHOUT LIMITATION WARRANTIES OF MERCHANTABILITY OR FITNESS FOR ANY PARTICULAR PURPOSE, OR NON-INFRINGEMENT OF ANY THIRD-PARTY PATENT, COPYRIGHT, OR ANY OTHER THIRD-PARTY RIGHT. IN NO EVENT SHALL THE CREATORS OF THE SOFTWARE OR WASHINGTON UNIVERSITY BE LIABLE FOR ANY DIRECT, INDIRECT, SPECIAL, OR CONSEQUENTIAL DAMAGES ARISING OUT OF OR IN ANY WAY CONNECTED WITH THE SOFTWARE, THE USE OF THE SOFTWARE, OR THIS AGREEMENT, WHETHER IN BREACH OF CONTRACT, TORT OR OTHERWISE, EVEN IF SUCH PARTY IS ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.
