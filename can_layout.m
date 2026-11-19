function can_layout(sigs, payload)
%CAN_LAYOUT  打印 8x8 位图，直观显示每个信号占了哪些位
%
%   can_layout(sigs)            % 只看协议布局
%   can_layout(sigs, payload)   % 同时打印每字节十六进制
%
%   行 = Byte0..Byte7，列 = bit7..bit0（左边是高位，和协议文档一致）
%   格子里是该信号在 sigs 中的序号，'.' 表示未使用。

nByte = 8;
grid  = repmat('.', nByte, 8);

for k = 1:numel(sigs)
    bits = signal_bits(sigs(k));
    for b = bits
        byteIdx = floor(b / 8);        % 0..7
        bitIdx  = mod(b, 8);           % 0..7（0 = LSB）
        grid(byteIdx + 1, 8 - bitIdx) = label(k);
    end
end

fprintf('\n         bit7 bit6 bit5 bit4 bit3 bit2 bit1 bit0\n');
for i = 1:nByte
    if nargin > 1
        hex = sprintf('%02X', payload(i));
        fprintf('  Byte%d  %s   | %s |\n', i-1, ...
            sprintf('%s ', grid(i,:)), hex);
    else
        fprintf('  Byte%d  %s\n', i-1, sprintf('%s ', grid(i,:)));
    end
end

fprintf('\n  图例：\n');
for k = 1:numel(sigs)
    s = sigs(k);
    fprintf('    %s = %-12s %2d bit  %-8s startBit=%-2d\n', ...
        label(k), s.name, s.length, s.order, s.startBit);
end
fprintf('\n');
end

% ----------------------------------------------------------------------
function c = label(k)
if k <= 9
    c = sprintf('%d', k);      % 1..9
else
    c = char('A' + k - 10);    % 10.. = A,B,C...
end
end

% ----------------------------------------------------------------------
function bits = signal_bits(sig)
% 返回该信号占用的全局"LSB 位号"列表（0 = Byte0.bit0）
len = sig.length;
bits = zeros(1, len);

if strcmpi(sig.order, 'Intel')
    bits = sig.startBit + (0:len-1);
else
    byteIdx = floor(sig.startBit / 8);
    bitIdx  = mod(sig.startBit, 8);     % 从 MSB 侧开始
    for i = 1:len
        bits(i) = byteIdx * 8 + bitIdx;
        if bitIdx == 0
            byteIdx = byteIdx + 1;
            bitIdx  = 7;
        else
            bitIdx  = bitIdx - 1;
        end
    end
end
end
