function p = pfc_gui_fus_params(handles)
%PFC_GUI_FUS_PARAMS 读「2. 超声 / 反馈 / PCD」参数并做基本校验。
p.freq_mhz = num_from(handles, 'frequency', 1.5);
p.volt_mVpp = num_from(handles, 'voltage', 1);
p.prf_hz = num_from(handles, 'PRF', 2);
p.n_cycle = max(1, round(num_from(handles, 'BurstCount', 400)));
p.n_cycle = min(p.n_cycle, 5000);
p.duration_s = num_from(handles, 'duration', 20);
p.npts = max(4096, round(num_from(handles, 'sampleNum', 40000)));
p.npts = min(p.npts, 50000);
p.target_db = num_from(handles, 'ControllerTarget', 2);
p.max_mVpp = num_from(handles, 'MaxV', 120);
p.mb_load_s = num_from(handles, 'MBLoadTime', 15);
p.fs_target = 40e6;
p.studyID = 'run';
if isfield(handles, 'studyID') && isgraphics(handles.studyID)
    p.studyID = char(get(handles.studyID, 'String'));
end

if ~(isfinite(p.freq_mhz) && p.freq_mhz > 0)
    error('pfc:params', '请填写有效的 FUS 频率 (MHz)。');
end
if ~(isfinite(p.volt_mVpp) && p.volt_mVpp > 0)
    error('pfc:params', '请填写有效的 FUS 电压 (mVpp)。');
end
% DG2052 高阻常见 1 mVpp–10 Vpp；20 mV 与 500 mV 都合法，不要额外截断。
if p.volt_mVpp > 10000
    error('pfc:params', '电压 %.4g mVpp 超过 10 Vpp，请确认单位是 mVpp。', p.volt_mVpp);
end
if ~(isfinite(p.prf_hz) && p.prf_hz > 0)
    error('pfc:params', '请填写有效的 PRF (Hz)。');
end
if ~(isfinite(p.duration_s) && p.duration_s > 0)
    error('pfc:params', '请填写有效的治疗时长 (s)。');
end
if ~(isfinite(p.max_mVpp) && p.max_mVpp > 0)
    p.max_mVpp = 120;
end
if ~(isfinite(p.mb_load_s) && p.mb_load_s >= 0)
    p.mb_load_s = 0;
end

% 50k 点、约 31–40 MSa/s 只能盖住约 1.2–1.6 ms，周期数不能按 5000 硬打满。
max_cyc = max(80, floor((p.npts / p.fs_target) * p.freq_mhz * 1e6 / 1.25));
p.n_cycle = min(p.n_cycle, max_cyc);
p.period_s = 1 / p.prf_hz;
p.n_expect = max(1, round(p.duration_s * p.prf_hz));
end

function v = num_from(handles, tag, def)
v = def;
if isfield(handles, tag) && isgraphics(handles.(tag))
    x = str2double(get(handles.(tag), 'String'));
    if isfinite(x)
        v = x;
    end
end
end
