function rigol_dg2052_output_set(dev, on)
%RIGOL_DG2052_OUTPUT_SET 打开/关闭指定通道输出。
cfg = rigol_instr_config();
ch = cfg.awg_channel;
out = sprintf('OUTPut%d', ch);
if on
    writeline(dev, [':' out ':STATe ON']);
else
    writeline(dev, [':' out ':STATe OFF']);
end
end
