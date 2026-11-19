function phys = can_unpack(sig, payload)
%CAN_UNPACK  从 8 字节 payload 中解出信号的物理值
%
%   phys = can_unpack(sigs(k), payload)
%
%   与 can_pack 严格互逆。

assert(isa(payload,'uint8') && numel(payload) == 8, ...
    'payload 必须是 1x8 的 uint8');

% ---- 快速路径：整字节信号（8 bit 且字节对齐）--------------------------
if sig.length == 8 && mod(sig.startBit, 8) == 0
    b = payload(sig.startBit/8 + 1);
    if sig.signed
        raw = double(typecast(b, 'int8'));    % int8 自带符号扩展
    else
        raw = double(b);
    end
    phys = raw * sig.scale + sig.offset;
    return;
end

mask = bitshift(uint64(1), sig.length) - 1;

% ---- 1. 从容器里把这段位取出来 ----------------------------------------
if strcmpi(sig.order, 'Intel')
    word = typecast(payload, 'uint64');
    sh   = sig.startBit;
else
    word  = swapbytes(typecast(payload, 'uint64'));
    beMsb = floor(sig.startBit / 8) * 8 + (7 - mod(sig.startBit, 8));
    sh    = 64 - (beMsb + sig.length);
end

raw = bitand(bitshift(word, -sh), mask);

% ---- 2. uint64 -> double（<=53 位不丢精度）----------------------------
raw = double(raw);

% ---- 3. 符号扩展（补码 -> 负数）--------------------------------------
if sig.signed && raw >= 2^(sig.length - 1)
    raw = raw - 2^sig.length;
end

% ---- 4. 原始值 -> 物理值 ----------------------------------------------
phys = raw * sig.scale + sig.offset;
end
