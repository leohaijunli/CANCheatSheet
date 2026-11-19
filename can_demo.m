%CAN_DEMO  完整闭环示例：物理值 -> 打包 -> "发送" -> "接收" -> 解析回物理值
%          全部为 Intel（小端）信号。
%
%   >> can_demo
%
% 覆盖的难点：
%   1. 12 bit 跨字节（Byte0 -> Byte1 低半字节）
%   2. 12 bit 从字节中间开始（Byte1.bit4 -> Byte2）
%   3. 16 bit 小端字节顺序（低字节在 Byte5，高字节在 Byte6）
%   4. 有符号补码（PackCurrent、CellTempMax）
%   5. 同一字节里塞 1 + 3 + 4 bit 三个小信号（Byte7）
%   6. 极值 / 往返一致性自检

clear; clc; close all;

CAN_ID = hex2dec('18F');

%% ===================== 1. 协议定义 ====================================
sigs = can_protocol_def();

fprintf('=========== 协议 0x%03X  BMS_Status  DLC=8  (Intel) ===========\n', CAN_ID);
fprintf('%-13s %5s %4s %9s %2s %7s %7s %15s %s\n', ...
    'Signal', 'Start', 'Len', 'Order', 'S', 'Scale', 'Offset', 'Range', 'Unit');
for k = 1:numel(sigs)
    s = sigs(k);
    if s.signed, sgn = 'S'; else, sgn = 'U'; end
    fprintf('%-13s %5d %4d %9s %2s %7.3g %7.3g %15s %s\n', ...
        s.name, s.startBit, s.length, s.order, sgn, ...
        s.scale, s.offset, sprintf('[%g,%g]', s.min, s.max), s.unit);
end

%% ===================== 2. 位布局可视化 ================================
fprintf('\n--------- 位布局（Byte 行 x Bit 列）---------\n');
can_layout(sigs);

%% ===================== 3. 打包（物理值 -> 字节）=======================
phys.tx = [398.6, -125.7, 76.4, 34, 3.652, 1, 3, 5];   % 与 sigs 顺序一致

payload = [];
for k = 1:numel(sigs)
    payload = can_pack(payload, sigs(k), phys.tx(k));
end

fprintf('--------- 打包结果 ---------\n');
fprintf('  期望物理值: ');
for k = 1:numel(sigs)
    fprintf('%g%s ', phys.tx(k), sigs(k).unit);
end
fprintf('\n');
fprintf('  payload HEX: %s\n', sprintf('%02X ', payload));
fprintf('  payload DEC: %s\n', sprintf('%3d ', payload));

can_layout(sigs, payload);

%% ===================== 4. "发送"到 CAN 总线 ===========================
% 这里用一个结构体模拟总线；接真实硬件时代码几乎是同样的形状，
% 见文件末尾的 Vehicle Network Toolbox 用法。
txMsg.id   = CAN_ID;
txMsg.dlc  = 8;
txMsg.data = payload;

bus = struct('id', {}, 'dlc', {}, 'data', {});   % 模拟总线缓冲区
bus(end+1) = txMsg;                              % 相当于 transmit(ch, txMsg)

%% ===================== 5. 从总线"接收" ===============================
rxMsg = bus(1);           % 相当于 receive(ch, 1)

fprintf('\n--------- 接收到的帧 ---------\n');
fprintf('  ID=0x%03X  DLC=%d  Data=%s\n', ...
    rxMsg.id, rxMsg.dlc, sprintf('%02X ', rxMsg.data));

%% ===================== 6. 解析（字节 -> 物理值）=======================
% 接收端只拿到 8 个原始字节，按协议逐个解析
phys.rx = zeros(1, numel(sigs));
for k = 1:numel(sigs)
    phys.rx(k) = can_unpack(sigs(k), rxMsg.data);
end

fprintf('\n--------- 解析结果 vs 原始物理值 ---------\n');
fprintf('%-13s %14s %14s %12s\n', 'Signal', 'TX(原始)', 'RX(解析)', '误差');
ok = true;
for k = 1:numel(sigs)
    err = abs(phys.rx(k) - phys.tx(k));
    tol = max(1e-9, abs(sigs(k).scale) * 1e-6);
    good = err <= tol;
    ok = ok && good;
    fprintf('%-13s %14.6g %14.6g %12.3g %s\n', ...
        sigs(k).name, phys.tx(k), phys.rx(k), err, ternary(good,'OK','FAIL'));
end
fprintf('\n  总判定: %s\n', ternary(ok, 'PASS', 'FAIL'));

%% ===================== 7. 极值与往返自检 =============================
fprintf('\n--------- 极值 / 往返自检（每个信号取边界值）---------\n');
allPass = true;
for k = 1:numel(sigs)
    s = sigs(k);
    if s.signed
        raws = [0, 1, -1, 2^(s.length-1)-1, -2^(s.length-1)];
    else
        raws = [0, 1, 2^s.length-2, 2^s.length-1];
    end
    for r = raws
        pv   = r * s.scale + s.offset;
        p    = can_pack([], s, pv);
        back = can_unpack(s, p);
        bad  = abs(back - pv) > max(1e-9, abs(s.scale)*1e-6);
        allPass = allPass && ~bad;
        if bad
            fprintf('  FAIL %-12s raw=%-8g phys=%-10.6g back=%-10.6g\n', ...
                s.name, r, pv, back);
        end
    end
end
fprintf('  极值自检: %s\n', ternary(allPass, 'PASS', 'FAIL'));

%% ===================== 8. "只改一个 bit" 演示 ========================
% 验证位操作不会串扰：只把 ChargeFlag 取反，其它字节必须完全不变
p2 = can_pack(payload, sigs(6), 0);      % ChargeFlag 1 -> 0
diffBytes = find(p2 ~= payload) - 1;
fprintf('\n--------- 单 bit 修改不串扰 ---------\n');
fprintf('  ChargeFlag 1->0 后变化的字节: %s\n', mat2str(diffBytes));
fprintf('  Byte7: %02X -> %02X （只应变化 bit0）\n', payload(8), p2(8));

%% ===================== 9. 手工对拍 ==================================
expectedHex = '92 7F B1 BF 22 44 0E 57';
fprintf('\n--------- 与手工推算的基准帧对拍 ---------\n');
fprintf('  expected: %s\n', expectedHex);
fprintf('  actual  : %s\n', sprintf('%02X ', payload));
if strcmp(strtrim(sprintf('%02X ', payload)), expectedHex)
    fprintf('  对拍: PASS\n');
else
    fprintf('  对拍: FAIL\n');
end

fprintf('\n完成。\n');

%% ===================== 附：接真实硬件 ================================
% 需要 Vehicle Network Toolbox。示例（Vector VN1610，通道 1）：
%
%   ch = canChannel('Vector', 'VN1610 1', 1);
%   configBusSpeed(ch, 500000);
%   start(ch);
%
%   msg      = canMessage(CAN_ID, false, 8);   % false = 标准帧
%   msg.Data = payload;                        % 1x8 uint8
%   transmit(ch, msg);
%
%   rx = receive(ch, 1, 1);                    % 等 1 帧，超时 1s
%   if ~isempty(rx)
%       v = can_unpack(sigs(1), rx.Data);
%   end
%
%   stop(ch); delete(ch);
%
% 若有 DBC，可让工具箱直接对拍：
%   db  = canDatabase('bms_status.dbc');
%   msg = canMessage(db, 'BMS_Status');
%   msg.Signals.PackVoltage = 398.6;
%   msg.Signals.PackCurrent = -125.7;
%   ... 之后 msg.Data 应与上面 payload 完全一致。

% ----------------------------------------------------------------------
function s = ternary(cond, a, b)
if cond, s = a; else, s = b; end
end
