function tf = rigol_visa_same(a, b)
%RIGOL_VISA_SAME 两个 VISA 地址是否指向同一资源（忽略 ::0:: 写法差异）。
na = rigol_visa_norm(a);
nb = rigol_visa_norm(b);
tf = ~isempty(na) && strcmpi(na, nb);
end
