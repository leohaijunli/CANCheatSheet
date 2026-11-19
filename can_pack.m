function payload = can_pack(payload, sig, physValue)
%CAN_PACK  把物理值打包进 CAN 的 8 字节 payload
%
%   payload = can_pack([], sig, 398.6)          % 新建全零帧并写入第一个信号
%   payload = can_pack(payload, sig2, -125.7)   % 继续叠加到同一帧
%
%   原理（关键，只需记这一条）：
%     先把 8 个字节当成一个 uint64 的"位容器"，然后在容器里按位移放数据。
%       Intel    : 直接 typecast   -> payload(1) 是容器最低字节
%       Motorola : swapbytes 之后 -> Byte0 是容器最高字节（大端视角）
%   这样任何跨字节、任意位宽都只需要一次移位，不用写 if-else 拼字节。
%
%   注意：Intel 分支依赖主机为小端（x86/x64 的 Windows/macOS/Linux 都是）。

if isempty(payload)
    payload = zeros(1, 8, 'uint8');
end
assert(isa(payload,'uint8') && numel(payload) == 8, ...
    'payload 必须是 1x8 的 uint8');

[~, ~, endian] = computer();
assert(endian == 'L', '本实现假定主机为小端（x86/x64）');

% ---- 1. 物理值 -> 原始整数 raw ----------------------------------------
raw = round((physValue - sig.offset) / sig.scale);

% ---- 2. 范围检查 + 负值转补码 ----------------------------------------
if sig.signed
    lo = -2^(sig.length-1);
    hi =  2^(sig.length-1) - 1;
    if raw < lo || raw > hi
        error('can_pack:range', ...
            '%s 超出范围: %g（允许 %g ~ %g），物理值 %g', ...
            sig.name, raw, lo, hi, physValue);
    end
    if raw < 0
        raw = raw + 2^sig.length;      % 负数 -> 二进制补码
    end
else
    if raw < 0 || raw > 2^sig.length - 1
        error('can_pack:range', ...
            '%s 超出范围: %g（允许 0 ~ %g），物理值 %g', ...
            sig.name, raw, 2^sig.length - 1, physValue);
    end
end

raw  = uint64(raw);

% ---- 快速路径：整字节信号（8 bit 且字节对齐）--------------------------
% 此时根本不需要移位/掩码，直接给对应字节赋值即可。
% 但 Intel 的整字节与 Motorola 的整字节【字节位置相同】（8 bit 无跨字节），
% 所以两种端序都适用。
if sig.length == 8 && mod(sig.startBit, 8) == 0
    payload(sig.startBit/8 + 1) = uint8(bitand(raw, uint64(255)));
    return;
end

mask = bitshift(uint64(1), sig.length) - 1;   % 位宽掩码
val  = bitand(raw, mask);                     % 只保留 length 位

% ---- 3. 在 64 位容器里算出移位量 --------------------------------------
if strcmpi(sig.order, 'Intel')
    word = typecast(payload, 'uint64');       % 小端：payload(1) = 最低字节
    sh   = sig.startBit;                      % DBC 的 startBit 就是 LSB 位号
else
    word = swapbytes(typecast(payload, 'uint64'));   % 转成大端视角
    % DBC 的 startBit 是 MSB 位置 -> 换成"从最高位算起"的序号
    beMsb = floor(sig.startBit / 8) * 8 + (7 - mod(sig.startBit, 8));
    sh    = 64 - (beMsb + sig.length);        % 右移多少位能让 LSB 落到 bit0
end

% ---- 4. 先清空这段位，再写入（不会破坏同字节的其它信号）---------------
field = bitshift(mask, sh);
word  = bitor(bitand(word, bitcmp(field)), bitshift(val, sh));

% ---- 5. 容器 -> 字节数组 ----------------------------------------------
if strcmpi(sig.order, 'Intel')
    payload = typecast(word, 'uint8');
else
    payload = typecast(swapbytes(word), 'uint8');
end
end
