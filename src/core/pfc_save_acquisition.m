function filepath = pfc_save_acquisition(outdir, stem, S)
%PFC_SAVE_ACQUISITION 把时域、FFT 与参数写成 .mat。
if ~isfolder(outdir)
    mkdir(outdir);
end
stamp = datestr(now, 'yyyymmdd_HHMMSS');
filepath = fullfile(outdir, sprintf('%s_%s.mat', stem, stamp));
save(filepath, '-struct', 'S', '-v7.3');
fprintf('已保存 %s\n', filepath);
end
