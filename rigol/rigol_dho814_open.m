function dev = rigol_dho814_open(visaAddr)
%RIGOL_DHO814_OPEN 复用已有 DHO814 visadev，不要对同一 USB 资源 new 第二次。
if nargin >= 1 && ~isempty(visaAddr)
    cfg = rigol_instr_config();
    if ~strcmp(visaAddr, cfg.scope_visa)
        warning('rigol:dho814:open', '忽略传入地址，使用 rigol_instr_config 中的单例连接。');
    end
end
dev = pcd_visa('scope');
end
