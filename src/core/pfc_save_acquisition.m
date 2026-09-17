function rundir = pfc_save_acquisition(outdir, stem, S, opts)
%PFC_SAVE_ACQUISITION 一次采集写成一个目录：raw.mat + params.txt + 分析图。
%
%   rundir = pfc_save_acquisition(outdir, stem, S)
%   rundir = pfc_save_acquisition(outdir, stem, S, opts)
%
% 目录名 {stem}_{yyyymmdd_HHMMSS}/，里面是：
%   raw.mat      与旧扁平 .mat 同一套字段（顶层旧名 + params）
%   params.txt   pfc_save_params 快照的可读文本
%   fft_ch1.png / fft_ch2.png / time_ch1_ch2.png / pulse_sc_ic.png
%
% 返回 rundir（状态栏、result.file 指向这个文件夹）。旧扁平 *_run_*.mat
% 仍可 load，本函数只改以后的保存，不写兼容副本。
%
% opts.rundir  已有本次目录则覆盖 raw.mat（实验中每 5 发备份，不换时间戳）
% opts.plots   true 时出图（默认 true；中途备份传 false，结束时再出一次）

if nargin < 4 || isempty(opts)
    opts = struct();
end
if ~isstruct(opts)
    opts = struct();
end
if ~isfolder(outdir)
    mkdir(outdir);
end
stem = regexprep(char(string(stem)), '[^A-Za-z0-9_-]+', '_');
stem = regexprep(stem, '^_+|_+$', '');
if isempty(stem)
    stem = 'run';
end

if isfield(opts, 'rundir') && strlength(string(opts.rundir)) > 0
    rundir = char(string(opts.rundir));
else
    stamp = datestr(now, 'yyyymmdd_HHMMSS'); %#ok<DATST>
    rundir = fullfile(outdir, sprintf('%s_%s', stem, stamp));
end
if ~isfolder(rundir)
    mkdir(rundir);
end

rawfile = fullfile(rundir, 'raw.mat');
save(rawfile, '-struct', 'S', '-v7.3');

if isfield(S, 'params') && isstruct(S.params)
    try
        write_params_txt(fullfile(rundir, 'params.txt'), S.params);
    catch
    end
end

do_plots = true;
if isfield(opts, 'plots') && ~isempty(opts.plots)
    do_plots = logical(opts.plots(1));
end
% 出图失败不影响 raw.mat：分析图是附赠，数据才是这次实验。
if do_plots
    try
        pfc_save_run_plots(rundir, S);
    catch err
        warning('PFC:savePlots', '分析图未写出（raw.mat 已保存）：%s', err.message);
    end
end
fprintf('已保存 %s\n', rundir);
end

function write_params_txt(fp, P)
%WRITE_PARAMS_TXT 把 pfc_save_params 快照写成 key = value，方便不打开 MATLAB 就看。
fid = fopen(fp, 'w');
if fid < 0
    return;
end
cleaner = onCleanup(@() fclose(fid)); %#ok<NASGU>
fprintf(fid, '%% PFC params snapshot  (pfc_save_params)\n');
keys = fieldnames(P);
for i = 1:numel(keys)
    k = keys{i};
    fprintf(fid, '%s = %s\n', k, fmt_val(P.(k)));
end
end

function s = fmt_val(v)
if isnumeric(v) || islogical(v)
    if isempty(v)
        s = '[]';
    elseif isscalar(v)
        if ~isfinite(double(v))
            s = char(string(v));
        elseif abs(double(v) - round(double(v))) < 1e-12 && abs(double(v)) < 1e12
            s = sprintf('%g', double(v));
        else
            s = sprintf('%.8g', double(v));
        end
    else
        s = mat2str(double(v), 8);
    end
elseif ischar(v) || isstring(v)
    s = char(string(v));
elseif isstruct(v)
    s = '<struct>';
else
    s = class(v);
end
end
