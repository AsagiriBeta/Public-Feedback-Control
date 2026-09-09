function outdir = pfc_ensure_save_dir(handles)
%PFC_ENSURE_SAVE_DIR 返回有效保存目录（不存在则创建）。
outdir = strtrim(char(get(handles.directory, 'String')));
if isempty(outdir)
    root = fileparts(mfilename('fullpath'));
    outdir = fullfile(root, 'data');
    set(handles.directory, 'String', outdir);
end
if ~isfolder(outdir)
    mkdir(outdir);
end
end
