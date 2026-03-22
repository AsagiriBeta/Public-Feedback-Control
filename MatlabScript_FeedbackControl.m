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
gui_Singleton = 1;
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
addpath(pwd)
addpath(fullfile(pwd, 'rigol'));

% --- Outputs from this function are returned to the command line.
function varargout = MatlabScript_FeedbackControl_OutputFcn(hObject, eventdata, handles)
% varargout  cell array for returning output args (see VARARGOUT);
% hObject    handle to figure
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Get default command line output from handles structure
varargout{1} = handles.output;


function motor_speed_Callback(hObject, eventdata, handles)
% hObject    handle to motor_speed (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
handles.experimental_motor_speed = round(str2double(get(handles.motor_speed,'String')));
guidata(hObject, handles);
check_if_ready(hObject, handles);


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
check_if_ready(hObject, handles);

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

% ret = CsMl_FreeSystem(handle);
% clear all; close all; clc
% delete(instrfindall)
motor_initialize_Homing
fprintf('Motor is homed\n');

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
function manual_motor_move(hObject, handles, motor_dim, is_neg)
motor_movable = true;

% Check if valid motor step size
motor_movement_size = str2double(get(handles.motor_step_size,'String'));
if isnan(motor_movement_size) == true
    motor_movable = false;
end
% Check if valid movement speed
motor_movement_speed = round(str2double(get(handles.motor_speed,'String')));
if isnan(motor_movement_speed) == true
    motor_movable = false;
end
% Check if valid displacement
motor_movement_displacement = str2double(get(handles.displacement,'String'));
if isnan(motor_movement_displacement) == true
    motor_movable = false;
elseif is_neg
    motor_movement_displacement = -motor_movement_displacement;
end

% Move the motor
if motor_movable
    if abs(motor_movement_displacement) > 0          % CP
        motor_move(motor_dim, motor_movement_displacement);
    end
end


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
folder_name = uigetdir;
set(handles.directory,'String',folder_name);
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



function frequency_Callback(hObject, eventdata, handles)
% hObject    handle to frequency (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of frequency as text
%        str2double(get(hObject,'String')) returns contents of frequency as a double


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



function voltage_Callback(hObject, eventdata, handles)
% hObject    handle to voltage (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of voltage as text
%        str2double(get(hObject,'String')) returns contents of voltage as a double


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
function PCDcontrol_Callback(hObject, eventdata, handles)
% hObject    handle to PCDcontrol (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)
global fgen


%% Load GUI parameter for function generator
SonicationDuration = 20;                               % Total time for sonication [s]
Fs      = 40e6;                                        % Sampling Frequency [Hz]
freq    = str2num(get(handles.frequency,'String'));    % frequency [MHz]
cycle   = str2num(get(handles.BurstCount,'String'));   % burst count
PRF     = str2num(get(handles.PRF,'String'));          % burst period [s]
PL      = 1/freq*cycle/1e6;                            % Pulse length [s]
volt    = str2num(get(handles.voltage,'String'));      % voltage [mVppk]
offset  = 0;
depth = str2num(get(handles.sampleNum,'String'));      % Sampling frequency * pulse length
Vstep = 1;                                             % Step size for voltage ramp
%% Directory for saving data
directory= get(handles.directory,'String');
if ~endsWith(directory, filesep)
    directory = [directory filesep];
end
filename = ['PCDcontrol_',get(handles.studyID,'String')];


%% RIGOL DHO814：USB-VISA 采集（替代 PicoScope PS5000A）
cfg = rigol_instr_config();
scope = rigol_dho814_open();
info = rigol_dho814_setup(scope, Fs, depth, cfg.scope_channel);
timeIntervalNanoSeconds = info.timeIntervalNanoSeconds;

%% data acquisition and FFT setup
realFs = info.realFs;
NFFT =2^nextpow2(depth);
F = realFs.*(0:(NFFT/2))/NFFT;
freq_hz = freq * 1e6;
if cfg.use_legacy_fft_bins
    SC_range = cfg.legacy_SC_range;
    IC_range = cfg.legacy_IC_range;
else
    [SC_range, IC_range] = rigol_fft_harmonic_bands(freq_hz, realFs, NFFT, cfg.harmonic_bandwidth_hz);
end

cd(directory)


%% Get and set Figure handle
cla(handles.realtimeSCplot)
cla(handles.realtimeICplot)
cla(handles.realtimeVplot)

pulse = 1;
axes(handles.FFT_plot);
FFTax = gca;
axes(handles.Signal_plot);
Signalax = gca;
axes(handles.realtimeSCplot);
SCplotax = gca;
axes(handles.realtimeICplot);
ICplotax = gca;
axes(handles.realtimeVplot);
Vplotax = gca;



%% Initialize Fgen and Start data acquisition
fgen_excute_UTSW(freq,volt,0,cycle,1/PRF);
rigol_dg2052_output_set(fgen, true);
SonicationTimeLeft  = SonicationDuration;
SonicationStart = tic;


while  SonicationTimeLeft > 0
    
    [chA, timeIntervalNanoSeconds, ~] = rigol_dho814_acquire_block(scope, depth, cfg.scope_channel);
    datamat(pulse,:) = chA; 
    
    % Plot realtime signal and FFT result
    set(handles.PulseNum,'String',['Before MB injection; pulse #',num2str(pulse)]);
    PCD_data = chA;
    tt = (0:(length(PCD_data)-1)).*double(timeIntervalNanoSeconds).*1e-9.*1e6;
    plot(Signalax,tt,PCD_data)
    set(Signalax, 'FontSize', 9,'FontWeight','bold');
    title(Signalax, 'Time Signal');
    xlabel(Signalax, 'Time (micro second)')
    ylabel(Signalax, 'Amplitude')      
    
    X = abs(fft(PCD_data,NFFT));
    Y = X(1:(NFFT/2)+1);
    semilogy(FFTax,F/1e6,Y);
    set(FFTax, 'XLim', [0 10]);
    set(FFTax, 'FontSize', 9,'FontWeight','bold');
    title(FFTax, 'FFT');
    xlabel(FFTax, 'Frequency (MHz)')
    
    %% Saving acquisition
    Vbaselinerealtime(pulse) = volt;  
    RampSC_baseline(pulse) = sum(Y(SC_range));
    RampIC_baseline(pulse) = sum(Y(IC_range));
    rigol_dg2052_set_vpp_mV(fgen, volt);
    
    %% Plot realtime SC, IC, V
    hold(SCplotax,'on')
    plot(SCplotax,pulse,RampSC_baseline(pulse),'b.')
    set(SCplotax, 'FontSize', 9,'FontWeight','bold');
    set(SCplotax, 'XLim', [0 SonicationDuration*2+5]);
    title(SCplotax, 'SC');
    xlabel(SCplotax, 'Pulse #')
    
    hold(ICplotax,'on')
    plot(ICplotax,pulse,RampIC_baseline(pulse),'b.')
    set(ICplotax, 'FontSize', 9,'FontWeight','bold');
    set(ICplotax, 'XLim', [0 SonicationDuration*2+5]);
    title(ICplotax, 'IC');
    xlabel(ICplotax, 'Pulse #')
    
    hold(Vplotax,'on')
    plot(Vplotax,pulse,Vbaselinerealtime(pulse),'bo')
    set(Vplotax, 'FontSize', 9,'FontWeight','bold');
    set(Vplotax, 'YLim', [0 50]);
    set(Vplotax, 'XLim', [0 SonicationDuration*2+5]);
    title(Vplotax, 'Voltage');
    xlabel(Vplotax, 'Pulse #')
    drawnow
    
    
    volt = volt+Vstep;
    pulse = pulse + 1;
    %% Time remaining
    SonicationTimeLeft  = (SonicationDuration - toc(SonicationStart))
    if SonicationTimeLeft<=0
        rigol_dg2052_output_set(fgen, false);
    end
end

guidata(hObject, handles);

clear scope
% Set times for saving file name
date_format = 'yyyy-mm-dd';
date_string = datestr(now, date_format);
time_format = 'HHMMSS';
time_string = datestr(now, time_format);
filename = sprintf([filename, '_', date_string,'_',time_string]);
save([directory,'NoMB_', filename '.mat']);
clear datamat tempSC_baseline tempIC_baseline RampSC_baseline RampIC_baseline stdSC_baseline stdIC_baseline;




% --- Executes on button press in Sonication.
function Sonication_Callback(hObject, eventdata, handles)
% hObject    handle to Sonication (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

%% Sonication Parameters Definition
global fgen
BaselineDuration = 5;                                                % 10pulses
BaselineVolt = 18;                                                   % unit: mVpp, equivilent to 0.2MPa (free-field)
SonicationDuration = str2num(get(handles.duration,'String'));        % total time for sonication [s]
Fs      = 40e6;                                                      % Sampling Frequency
freq    = str2num(get(handles.frequency,'String'));                  % frequency [MHz]
cycle   = str2num(get(handles.BurstCount,'String'));                 % burst count
PRF     = str2num(get(handles.PRF,'String'));                        % burst period [s]
PL      = 1/freq*cycle/1e6;                                          % Pulse length [s]
volt    = str2num(get(handles.voltage,'String'));                    % voltage [Vppk]
offset  = 0;
depth = str2num(get(handles.sampleNum,'String'));                    % Data acquisition length [points]
Vstep = 1;                                                           % Step size for voltage ramp
RampSC=0;

TGT = str2num(get(handles.ControllerTarget,'String'));               % Target cavitation level
VrampFlag = true;
maxInputV = str2num(get(handles.MaxV,'String'));                     % Max Input voltage for safety

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%% RIGOL DHO814（USB-VISA）
cfg = rigol_instr_config();
scope = rigol_dho814_open();
info = rigol_dho814_setup(scope, Fs, depth, cfg.scope_channel);
timeIntervalNanoSeconds = info.timeIntervalNanoSeconds;

%% data acquisition and FFT setup
realFs = info.realFs;
NFFT =2^nextpow2(depth);
F = realFs*(0:(NFFT/2))/NFFT;
freq_hz = freq * 1e6;
if cfg.use_legacy_fft_bins
    SC_range = cfg.legacy_SC_range;
    IC_range = cfg.legacy_IC_range;
else
    [SC_range, IC_range] = rigol_fft_harmonic_bands(freq_hz, realFs, NFFT, cfg.harmonic_bandwidth_hz);
end
filename=get(handles.directory,'string');
if ~endsWith(filename, filesep)
    filename = [filename filesep];
end
studyIDName = get(handles.studyID,'String');


%% Get and Set Figure handles
cla(handles.realtimeSCplot)
cla(handles.realtimeICplot)
cla(handles.realtimeVplot)

pulse = 1;
axes(handles.FFT_plot);
FFTax = gca;
axes(handles.Signal_plot);
Signalax = gca;
axes(handles.realtimeSCplot);
SCplotax = gca;
axes(handles.realtimeICplot);
ICplotax = gca;
axes(handles.realtimeVplot);
Vplotax = gca;

%% Clear variables
clear tempSC_baseline tempIC_baseline Vbaselinerealtime


%% Start baseline cavitation signal acquisition for defining target level (i.e. desired dB level above baseline cavitation signal)
fgen_excute_UTSW(freq,BaselineVolt,0,cycle,1/PRF);
SonicationStart = tic;
MBLoadTime = str2num(get(handles.MBLoadTime,'String'));
SonicationDuration = BaselineDuration+MBLoadTime;
SonicationTimeLeft  = SonicationDuration;
FUSonFlag = true;
firstFUSon=1;
while  SonicationTimeLeft > 0
    if (toc(SonicationStart)>=MBLoadTime)&&(FUSonFlag)
        rigol_dg2052_output_set(fgen, true);
        FUSonFlag=false;
        firstFUSon = pulse;
    end
    [chA, timeIntervalNanoSeconds, ~] = rigol_dho814_acquire_block(scope, depth, cfg.scope_channel);
    datamat(pulse,:) = chA;
    
    set(handles.PulseNum,'String',['Baseline acquisition: pulse #',num2str(pulse)]);
    PCD_data = chA;
    tt = (0:(length(PCD_data)-1)).*double(timeIntervalNanoSeconds).*1e-9.*1e6;
    plot(Signalax,tt,PCD_data)
    set(Signalax, 'FontSize', 9,'FontWeight','bold');
    title(Signalax, 'Time Signal');
    xlabel(Signalax, 'Time (micro second)')
    ylabel(Signalax, 'Amplitude')   
    
    X = abs(fft(PCD_data,NFFT));
    Y = X(1:(NFFT/2)+1);
    semilogy(FFTax,F/1e6,Y);
    set(FFTax, 'XLim', [0 10]);
    set(FFTax, 'FontSize', 9,'FontWeight','bold');
    title(FFTax, 'FFT');
    xlabel(FFTax, 'Frequency (MHz)')
    
    % Baseline acquisition
    tempSC_baseline(pulse) = sum(Y(SC_range));
    tempIC_baseline(pulse) = sum(Y(IC_range));
    Vrealtime(pulse) = BaselineVolt;  
    % Plot realtime SC, IC, V
    hold(SCplotax,'on')
    plot(SCplotax,pulse,tempSC_baseline(pulse),'b.')
    set(SCplotax, 'FontSize', 9,'FontWeight','bold');
    set(SCplotax, 'XLim', [0 60]);
    title(SCplotax, 'SC');
    xlabel(SCplotax, 'Pulse #')

    hold(ICplotax,'on')
    plot(ICplotax,pulse,tempIC_baseline(pulse),'b.')
    set(ICplotax, 'FontSize', 9,'FontWeight','bold');
    set(ICplotax, 'XLim', [0 60]);
    title(ICplotax, 'IC');
    xlabel(ICplotax, 'Pulse #')

    hold(Vplotax,'on')
    plot(Vplotax,pulse,Vrealtime(pulse),'bo')
    set(Vplotax, 'FontSize', 9,'FontWeight','bold');
    set(Vplotax, 'YLim', [0 50]);
    set(Vplotax, 'XLim', [0 60]);
    title(Vplotax, 'Voltage');
    xlabel(Vplotax, 'Pulse #')
    drawnow
    
    pulse = pulse + 1;
    % Time remaining
    SonicationTimeLeft  = (SonicationDuration - toc(SonicationStart))
    if SonicationTimeLeft<=0
        rigol_dg2052_output_set(fgen, false);
    end
end
stdSC_baseline = std(tempSC_baseline(firstFUSon:end));
stdIC_baseline = std(tempIC_baseline(firstFUSon:end));
RampSC_baseline = mean(tempSC_baseline(firstFUSon:end));
RampIC_baseline = mean(tempIC_baseline(firstFUSon:end));
SCdesired = 10^(log10(RampSC_baseline*(10^(TGT/10))));


%% Start treatment acquisition
fgen_excute_UTSW(freq,volt,0,cycle,1/PRF);
rigol_dg2052_output_set(fgen, true);
SonicationStart = tic;
SonicationDuration = str2num(get(handles.duration,'String'));        % total time for sonication [s]
SonicationTimeLeft  = SonicationDuration;
sumRampSC = 0;
while  (SonicationTimeLeft > 0)

    [chA, timeIntervalNanoSeconds, ~] = rigol_dho814_acquire_block(scope, depth, cfg.scope_channel);
    datamat(pulse,:) = chA;
    
    set(handles.PulseNum,'String',['During MB injection; pulse #',num2str(pulse)]);
    PCD_data = chA;
    tt = (0:(length(PCD_data)-1)).*double(timeIntervalNanoSeconds).*1e-9.*1e6;
    plot(Signalax,tt,PCD_data)
    set(Signalax, 'FontSize', 9,'FontWeight','bold');
    title(Signalax, 'Time Signal');
    xlabel(Signalax, 'Time (micro second)')
    
    
    X = abs(fft(PCD_data,NFFT));
    Y = X(1:(NFFT/2)+1); 
    semilogy(FFTax,F/1e6,Y); 
    set(FFTax, 'XLim', [0 10]);
    set(FFTax, 'FontSize', 9,'FontWeight','bold');
    title(FFTax, 'FFT');
    xlabel(FFTax, 'Frequency (MHz)')

    
    %% Feedback control processing: Using VrampFlag to determine the phase of feedback control algorithm
    % VrampFlag = true --> pressure ramping-up phase
    % VrampFlag = false --> pressure maintaining phase
    % RampSC/RampIC --> record realtime SC level and IC level
    
    Vrealtime(pulse) = volt;
    RampSC(pulse) = sum(Y(SC_range));
    RampIC(pulse) = sum(Y(IC_range));
    

    sumRampSC = sum(RampSC(firstFUSon:end));
    if VrampFlag      
        if ((RampSC(pulse)>= SCdesired)&&(firstFUSon~=pulse))
            FeedbackEvent = pulse;
            VrampFlag = false;
            Tolcoeff = 0.4;
            tolerance_posrange = 10^(log10(RampSC_baseline*(10^((TGT+Tolcoeff)/10))));
            tolerance_negrange = 10^(log10(RampSC_baseline*(10^((TGT-Tolcoeff)/10))));

        else
            volt = volt+Vstep;
            if volt>maxInputV, volt = maxInputV; end
        end

    else
        step = 1;
        if (RampSC(pulse)>tolerance_posrange)
            volt = volt-step;
        elseif (RampSC(pulse)<tolerance_negrange)
            volt = volt+step;
            if volt>maxInputV, volt = maxInputV; end
        end
    end
    rigol_dg2052_set_vpp_mV(fgen, volt);
    
    %% Plot realtime SC, IC, V
    hold(SCplotax,'on')
    plot(SCplotax,pulse,RampSC(pulse),'b.')
    set(SCplotax, 'FontSize', 9,'FontWeight','bold');
    set(SCplotax, 'XLim', [0 SonicationDuration*2+5]);
    title(SCplotax, 'SC');
    xlabel(SCplotax, 'Pulse #')
    
    hold(ICplotax,'on')
    plot(ICplotax,pulse,RampIC(pulse),'b.')
    set(ICplotax, 'FontSize', 9,'FontWeight','bold');
    set(ICplotax, 'XLim', [0 SonicationDuration*2+5]);
    title(ICplotax, 'IC');
    xlabel(ICplotax, 'Pulse #')
    
    hold(Vplotax,'on')
    plot(Vplotax,pulse,Vrealtime(pulse),'bo')
    set(Vplotax, 'FontSize', 9,'FontWeight','bold');
    set(Vplotax, 'YLim', [0 maxInputV]);
    set(Vplotax, 'XLim', [0 SonicationDuration*2+5]);
    title(Vplotax, 'Voltage');
    xlabel(Vplotax, 'Pulse #')
    drawnow
    
    %% Time remaining
    SonicationTimeLeft  = (SonicationDuration - toc(SonicationStart))%(SonicationDuration - toc)/60;
    TimeRecord(pulse) = SonicationTimeLeft;
    if (SonicationTimeLeft<=0)
        rigol_dg2052_output_set(fgen, false);
    end
    pulse = pulse + 1;
end

clear scope
save([filename studyIDName '.mat']);
clear datamat Vrealtime RampSC RampIC TimeRecord



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
global fgen
try
    if ~isempty(fgen)
        rigol_dg2052_output_set(fgen, false);
    end
catch
end



function edit40_Callback(hObject, eventdata, handles)
% hObject    handle to edit40 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

% Hints: get(hObject,'String') returns contents of edit40 as text
%        str2double(get(hObject,'String')) returns contents of edit40 as a double


% --- Executes during object creation, after setting all properties.
function edit40_CreateFcn(hObject, eventdata, handles)
% hObject    handle to edit40 (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    empty - handles not created until after all CreateFcns called

% Hint: edit controls usually have a white background on Windows.
%       See ISPC and COMPUTER.
if ispc && isequal(get(hObject,'BackgroundColor'), get(0,'defaultUicontrolBackgroundColor'))
    set(hObject,'BackgroundColor','white');
end


% --- Executes on button press in IniFgen.
function IniFgen_Callback(hObject, eventdata, handles)
% hObject    handle to IniFgen (see GCBO)
% eventdata  reserved - to be defined in a future version of MATLAB
% handles    structure with handles and user data (see GUIDATA)

global fgen

%% function generator initialization

% fgen_inital_Verasonics
freq    = str2num(get(handles.frequency,'String'));      %frequency [MHz]
cycle   = str2num(get(handles.BurstCount,'String'));        %burst count
PRF     = str2num(get(handles.PRF,'String'));        %burst period [s]
volt    = str2num(get(handles.voltage,'String'));    %voltage [mVppk]
fgen_initialize_UTSW(freq,volt,0,cycle,1/PRF);
