function varargout = MatlabScript_FeedbackControl(varargin)
% MATLABSCRIPT_FEEDBACKCONTROL MATLAB code for MatlabScript_FeedbackControl.fig
%      MATLABSCRIPT_FEEDBACKCONTROL, by itself, creates a new MATLABSCRIPT_FEEDBACKCONTROL or raises the existing
%      singleton*.
%
%      H = MATLABSCRIPT_FEEDBACKCONTROL returns the handle to a new MATLABSCRIPT_FEEDBACKCONTROL or the handle to
%      the existing singleton*.
%
%      MATLABSCRIPT_FEEDBACKCONTROL('CALLBACK',hObject,eventData,handles,...) calls the local
%      function named CALLBACK in MATLABSCRIPT_FEEDBACKCONTROL.M with the given input arguments.
%
%      MATLABSCRIPT_FEEDBACKCONTROL('Property','Value',...) creates a new MATLABSCRIPT_FEEDBACKCONTROL or raises the
%      existing singleton*.  Starting from the left, property value pairs are
%      applied to the GUI before MatlabScript_FeedbackControl_OpeningFcn gets called.  An
%      unrecognized property name or invalid value makes property application
%      stop.  All inputs are passed to MatlabScript_FeedbackControl_OpeningFcn via varargin.
%
%      *See GUI Options on GUIDE's Tools menu.  Choose "GUI allows only one
%      instance to run (singleton)".
%
% See also: GUIDE, GUIDATA, GUIHANDLES

% Edit the above text to modify the response to help MatlabScript_FeedbackControl

% Last Modified by GUIDE v2.5 02-Feb-2022 09:22:08

% Begin initialization code - DO NOT EDIT
gui_Singleton = 0;
gui_State = struct('gui_Name',       mfilename, ...
    'gui_Singleton',  gui_Singleton, ...
    'gui_OpeningFcn', @MatlabScript_FeedbackControl_OpeningFcn, ...
    'gui_OutputFcn',  @MatlabScript_FeedbackControl_OutputFcn, ...
    'gui_LayoutFcn',  [] , ...
    'gui_Callback',   []);
if nargin && ischar(varargin{1})
    gui_State.gui_Callback = str2func(varargin{1});
end

if nargout
    [varargout{1:nargout}] = gui_mainfcn(gui_State, varargin{:});
else
    gui_mainfcn(gui_State, varargin{:});
end
% End initialization code - DO NOT EDIT

% --- Executes just before MatlabScript_FeedbackControl is made visible.
function MatlabScript_FeedbackControl_OpeningFcn(hObject, eventdata, handles, varargin)
% This function has no output args, see OutputFcn.
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
% varargin   command line arguments to MatlabScript_FeedbackControl (see VARARGIN)

% Choose default command line output for MatlabScript_FeedbackControl
handles.output = hObject;

% Update handles structure
guidata(hObject, handles);
if ~isdeployed
    root = fileparts(mfilename('fullpath'));
    addpath(root);
    addpath(fullfile(root, 'rigol'));
end
try
    pfc_apply_gui_layout(hObject);
catch err
    warning('PFC:Layout', '界面布局未应用：%s', err.message);
end
defdir = fullfile(pfc_root(), 'data');
curdir = strtrim(char(get(handles.directory, 'String')));
if isempty(curdir) || ~isfolder(curdir)
    if ~isfolder(defdir)
        mkdir(defdir);
    end
    set(handles.directory, 'String', defdir);
end
fr = str2double(get(handles.frequency, 'String'));
if ~(isfinite(fr) && fr > 0)
    set(handles.frequency, 'String', '1.5');
end
bc = str2double(get(handles.BurstCount, 'String'));
if ~(isfinite(bc) && bc >= 1 && bc <= 2000)
    set(handles.BurstCount, 'String', '400');
end
sn = str2double(get(handles.sampleNum, 'String'));
if ~(isfinite(sn) && sn >= 4096 && sn <= 50000)
    set(handles.sampleNum, 'String', '40000');
end
pfc_visa('reset_busy');
handles = guihandles(hObject);
handles.output = hObject;
% 恢复上次保存的参数（存档不存在则保持当前默认值）
try
    pfc_gui_params('apply', handles);
catch err
    warning('PFC:Prefs', '参数恢复失败：%s', err.message);
end
guidata(hObject, handles);
% 关闭窗口时先把参数存盘
set(hObject, 'CloseRequestFcn', @(src, ~) pfc_gui_close(src));
set(hObject, 'Visible', 'on');
movegui(hObject, 'onscreen');

% --- Outputs from this function are returned to the command line.
function varargout = MatlabScript_FeedbackControl_OutputFcn(hObject, eventdata, handles)
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.output;
set(handles.output, 'Visible', 'on');
movegui(handles.output, 'onscreen');
drawnow;


function motor_speed_Callback(hObject, eventdata, handles)
% hObject    handle to motor_speed (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
handles.experimental_motor_speed = round(str2double(get(handles.motor_speed,'String')));
guidata(hObject, handles);


% --- Executes during object creation, after setting all properties.
function motor_speed_CreateFcn(hObject, eventdata, handles)
% hObject    handle to motor_speed (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

function motor_step_size_Callback(hObject, eventdata, handles)
% hObject    handle to motor_step_size (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
handles.experimental_motor_step_size = str2double(get(handles.motor_step_size,'String'));
guidata(hObject, handles);

% --- Executes during object creation, after setting all properties.
function motor_step_size_CreateFcn(hObject, eventdata, handles)
% hObject    handle to motor_step_size (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% --- Executes when motor_controls is resized.
function motor_controls_SizeChangedFcn(hObject, eventdata, handles)
% hObject    handle to motor_controls (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% --- Executes on button press in reconnect_motor_pushbutton.
function reconnect_motor_pushbutton_Callback(hObject, eventdata, handles)
% hObject    handle to reconnect_motor_pushbutton (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% 位移台已从界面移除（本实验室无电机）。
return

function displacement_Callback(hObject, eventdata, handles)
% hObject    handle to displacement (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of displacement as text
%        str2double(get(hObject,'String')) returns contents of displacement as a double


% --- Executes during object creation, after setting all properties.
function displacement_CreateFcn(hObject, eventdata, handles)
% hObject    handle to displacement (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end

% Manual movement of motor defined function
function manual_motor_move(hObject, handles, motor_dim, is_neg) %#ok<INUSD>
return


% --- Executes on button press in y_neg.
function y_neg_Callback(hObject, eventdata, handles)
% hObject    handle to y_neg (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

fprintf(['Y: -',get(handles.displacement,'String'),'mm \n'])
manual_motor_move(hObject, handles, 'Y', true);


% --- Executes on button press in y_pos.
function y_pos_Callback(hObject, eventdata, handles)
% hObject    handle to y_pos (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
fprintf(['Y: +',get(handles.displacement,'String'),'mm \n'])
manual_motor_move(hObject, handles, 'Y', false);


% --- Executes on button press in x_pos.
function x_pos_Callback(hObject, eventdata, handles)
% hObject    handle to x_pos (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
fprintf(['X: +',get(handles.displacement,'String'),'mm \n'])
manual_motor_move(hObject, handles, 'X', false);


% --- Executes on button press in x_neg.
function x_neg_Callback(hObject, eventdata, handles)
% hObject    handle to x_neg (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
fprintf(['X: -',get(handles.displacement,'String'),'mm \n'])
manual_motor_move(hObject, handles,'X', true);


% --- Executes on button press in z_neg.
function z_neg_Callback(hObject, eventdata, handles)
% hObject    handle to z_neg (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
fprintf(['Z: -',get(handles.displacement,'String'),'mm \n'])
manual_motor_move(hObject, handles,'Z', true);


% --- Executes on button press in z_pos.
function z_pos_Callback(hObject, eventdata, handles)
% hObject    handle to z_pos (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
fprintf(['Z: +',get(handles.displacement,'String'),'mm \n'])
manual_motor_move(hObject, handles,'Z', false);



% --- Executes on button press in Choose_file.
function Choose_file_Callback(hObject, eventdata, handles)
% hObject    handle to Choose_file (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
cur = strtrim(char(get(handles.directory,'String')));
if isempty(cur) || ~isfolder(cur)
    cur = pwd;
end
folder_name = uigetdir(cur, '选择保存目录 / Choose save folder');
% uigetdir 取消时返回 0；此时保持原目录，否则会被写成字符串 "0" 并新建 ./0 目录。
if ~ischar(folder_name) || isempty(folder_name)
    return;
end
set(handles.directory,'String',folder_name);
try, pfc_gui_params('save', handles); catch, end
%check_save_ready(hObject, handles);
guidata(hObject,handles);


function directory_Callback(hObject, eventdata, handles)
% hObject    handle to directory (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of directory as text
%        str2double(get(hObject,'String')) returns contents of directory as a double


% --- Executes during object creation, after setting all properties.
function directory_CreateFcn(hObject, eventdata, handles)
% hObject    handle to directory (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function studyID_Callback(hObject, eventdata, handles)
% hObject    handle to studyID (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of studyID as text
%        str2double(get(hObject,'String')) returns contents of studyID as a double


% --- Executes during object creation, after setting all properties.
function studyID_CreateFcn(hObject, eventdata, handles)
% hObject    handle to studyID (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function frequency_Callback(hObject, eventdata, handles) %#ok<INUSD>


% --- Executes during object creation, after setting all properties.
function frequency_CreateFcn(hObject, eventdata, handles)
% hObject    handle to frequency (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function voltage_Callback(hObject, eventdata, handles) %#ok<INUSD>


% --- Executes during object creation, after setting all properties.
function voltage_CreateFcn(hObject, eventdata, handles)
% hObject    handle to voltage (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function PRF_Callback(hObject, eventdata, handles)
% hObject    handle to PRF (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of PRF as text
%        str2double(get(hObject,'String')) returns contents of PRF as a double


% --- Executes during object creation, after setting all properties.
function PRF_CreateFcn(hObject, eventdata, handles)
% hObject    handle to PRF (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function BurstCount_Callback(hObject, eventdata, handles)
% hObject    handle to BurstCount (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of BurstCount as text
%        str2double(get(hObject,'String')) returns contents of BurstCount as a double


% --- Executes during object creation, after setting all properties.
function BurstCount_CreateFcn(hObject, eventdata, handles)
% hObject    handle to BurstCount (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function duration_Callback(hObject, eventdata, handles)
% hObject    handle to duration (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of duration as text
%        str2double(get(hObject,'String')) returns contents of duration as a double


% --- Executes during object creation, after setting all properties.
function duration_CreateFcn(hObject, eventdata, handles)
% hObject    handle to duration (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function sampleNum_Callback(hObject, eventdata, handles)
% hObject    handle to sampleNum (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of sampleNum as text
%        str2double(get(hObject,'String')) returns contents of sampleNum as a double


% --- Executes during object creation, after setting all properties.
function sampleNum_CreateFcn(hObject, eventdata, handles)
% hObject    handle to sampleNum (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function MBLoadTime_Callback(hObject, eventdata, handles)
% hObject    handle to MBLoadTime (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of MBLoadTime as text
%        str2double(get(hObject,'String')) returns contents of MBLoadTime as a double


% --- Executes during object creation, after setting all properties.
function MBLoadTime_CreateFcn(hObject, eventdata, handles)
% hObject    handle to MBLoadTime (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in PCDcontrol.
function PCDcontrol_Callback(hObject, eventdata, handles) %#ok<INUSL>
if ~pfc_gui_busy(handles, true)
    return;
end
cleanup = onCleanup(@() pfc_gui_busy(handles, false)); %#ok<NASGU>
try
    pfc_run_experiment('before', handles);
catch err
    errordlg(err.message, '无微泡 CH2');
end


function OpenMB_Callback(hObject, eventdata, handles) %#ok<INUSL>
if ~pfc_gui_busy(handles, true)
    return;
end
cleanup = onCleanup(@() pfc_gui_busy(handles, false)); %#ok<NASGU>
try
    pfc_run_experiment('open_mb', handles);
catch err
    errordlg(err.message, '有微泡开环');
end


% --- Executes on button press in Sonication.
function Sonication_Callback(hObject, eventdata, handles) %#ok<INUSL>
if ~pfc_gui_busy(handles, true)
    return;
end
cleanup = onCleanup(@() pfc_gui_busy(handles, false)); %#ok<NASGU>
try
    pfc_run_experiment('feedback', handles);
catch err
    errordlg(err.message, '闭环反馈');
end


function ControllerTarget_Callback(hObject, eventdata, handles)
% hObject    handle to ControllerTarget (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of ControllerTarget as text
%        str2double(get(hObject,'String')) returns contents of ControllerTarget as a double


% --- Executes during object creation, after setting all properties.
function ControllerTarget_CreateFcn(hObject, eventdata, handles)
% hObject    handle to ControllerTarget (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end



function MaxV_Callback(hObject, eventdata, handles)
% hObject    handle to MaxV (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of MaxV as text
%        str2double(get(hObject,'String')) returns contents of MaxV as a double


% --- Executes during object creation, after setting all properties.
function MaxV_CreateFcn(hObject, eventdata, handles)
% hObject    handle to MaxV (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end




% --- Executes on button press in stop.
function stop_Callback(hObject, eventdata, handles)
% hObject    handle to stop (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global pfc_abort
pfc_abort = true;
pfc_visa('rf_off');



% --- Executes on button press in IniFgen.
function IniFgen_Callback(hObject, eventdata, handles) %#ok<INUSL>
if pfc_visa('is_busy')
    warndlg('采集进行中，请先 STOP。', 'PFC');
    return;
end
try
    p = pfc_gui_fus_params(handles);
    fgen_initialize_UTSW(p.freq_mhz, p.volt_mVpp, 0, p.n_cycle, p.period_s);
    rigol_dg2052_output_set(pfc_visa('fgen'), false);
    set(handles.PulseNum, 'String', sprintf( ...
        '已配置猝发  %.3g MHz  %.4g mVpp  %d cyc  PRF %.3g Hz（输出关闭）', ...
        p.freq_mhz, p.volt_mVpp, p.n_cycle, p.prf_hz));
catch err
    errordlg(err.message, '初始化信号源');
end


% --- 仪器设置：编辑 VISA 地址（打包成 exe 后无需改代码即可换仪器） ---
function InstrSetup_Callback(hObject, eventdata, handles) %#ok<INUSL>
if pfc_visa('is_busy')
    warndlg('采集进行中，请先 STOP。', 'PFC');
    return;
end
cfg = rigol_instr_config();
d = inputdlg( ...
    {'示波器 VISA 地址（DHO814）', '信号源 VISA 地址（DG2052）'}, ...
    '仪器设置 / Instruments', [1 64; 1 64], ...
    {char(cfg.scope_visa), char(cfg.awg_visa)});
if isempty(d)
    return;
end
s1 = strtrim(d{1});
s2 = strtrim(d{2});
if isempty(s1) || isempty(s2)
    errordlg('VISA 地址不能为空。', 'PFC');
    return;
end
cfg.scope_visa = s1;
cfg.awg_visa = s2;
try
    rigol_instr_config('save', cfg);
    pfc_visa('close');   % 释放旧连接，下次采集按新地址重连
catch err
    errordlg(err.message, '仪器设置');
    return;
end
msgbox(sprintf('已保存到：\n%s\n\n下次采集将按新地址连接。', rigol_instr_config('file')), ...
    '仪器设置');


function OneshotFFT_Callback(hObject, eventdata, handles) %#ok<INUSL>
% 开环：发一帧。调试看 CH1 FFT；PCD 波形仍存 CH2。
global fgen
if ~pfc_gui_busy(handles, true)
    return;
end
cleanup = onCleanup(@() pfc_gui_busy(handles, false)); %#ok<NASGU>
outdir = pfc_ensure_save_dir(handles);
cfg = rigol_instr_config();
[freq, volt] = pfc_gui_acquire_fv(handles);
cycle = str2double(get(handles.BurstCount,'String'));
PRF = str2double(get(handles.PRF,'String'));
depth = str2double(get(handles.sampleNum,'String'));
Fs = 40e6;
if any(isnan([freq, cycle, PRF, volt, depth]))
    errordlg('请先填写采集框频率/电压，以及 PRF、Burst、Depth。', 'PFC');
    return;
end

set(handles.PulseNum, 'String', '采集中 Acquiring…');
drawnow;

scope = rigol_dho814_open();
info = rigol_dho814_setup(scope, Fs, depth, cfg.scope_channel, max(5e-4, 0.25*(volt/1000)));
fgen_excute_UTSW(freq, volt, 0, cycle, 1/PRF);
try
    rigol_dg2052_output_set(fgen, true);
    [chA, dt_ns, realFs, chTx] = rigol_dho814_acquire_block(scope, depth, cfg.scope_pcd_channel);
    rigol_dg2052_output_set(fgen, false);
catch err
    try
        rigol_dg2052_output_set(fgen, false);
    catch
    end
    rethrow(err);
end

pfc_update_signal_fft(handles, chTx, dt_ns, realFs, freq, 'CH1 回读 TX');
[F, Y, db, NFFT] = pfc_spectrum(chTx, realFs);

S = struct();
S.chA = chA;
S.chTx = chTx;
S.realFs = realFs;
S.timeIntervalNanoSeconds = dt_ns;
S.f_Hz = F;
S.fft_abs = Y;
S.fft_dB = db;
S.NFFT = NFFT;
S.freq_MHz = freq;
S.volt_mVpp = volt;
S.PRF_Hz = PRF;
S.BurstCount = cycle;
S.studyID = get(handles.studyID,'String');
fp = pfc_save_acquisition(outdir, ['oneshot_' S.studyID], S);
set(handles.PulseNum, 'String', ['已保存 Saved  ' fp]);


function DebugRun_Callback(hObject, eventdata, handles) %#ok<INUSL>
if ~pfc_gui_busy(handles, true)
    return;
end
cleanup = onCleanup(@() pfc_gui_busy(handles, false)); %#ok<NASGU>
outdir = pfc_ensure_save_dir(handles);
opts = struct();
opts.handles = handles;
opts.outdir = outdir;
[opts.freq_mhz, opts.volt_mVpp] = pfc_gui_acquire_fv(handles);
opts.prf_hz = str2double(get(handles.PRF,'String'));
opts.n_cycle = str2double(get(handles.BurstCount,'String'));
opts.npts = str2double(get(handles.sampleNum,'String'));
if ~isfinite(opts.freq_mhz) || opts.freq_mhz <= 0, opts.freq_mhz = 1.5; end
if ~isfinite(opts.volt_mVpp) || opts.volt_mVpp <= 0, opts.volt_mVpp = 20; end
if ~isfinite(opts.prf_hz) || opts.prf_hz <= 0, opts.prf_hz = 2; end
if ~isfinite(opts.n_cycle) || opts.n_cycle < 1, opts.n_cycle = 400; end
if ~isfinite(opts.npts) || opts.npts < 1024, opts.npts = 40000; end
opts.npts = min(opts.npts, 40000);
opts.n_cycle = min(opts.n_cycle, 800);
try
    pfc_debug_no_mb(opts);
catch err
    errordlg(err.message, '调试采集');
end


