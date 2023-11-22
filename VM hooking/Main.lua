key = 11;

local handle_exec = function(inst, real_vip)
    return (inst[1] == 2 and inst[3] == 35) and 26 or real_vip;
end;

local StrToNumber = tonumber;
local Byte = string.byte;
local Char = string.char;
local Sub = string.sub;
local Subg = string.gsub;
local Rep = string.rep;
local Concat = table.concat;
local Insert = table.insert;
local LDExp = math.ldexp;
local GetFEnv = getfenv or function()
	return _ENV;
end;
local Setmetatable = setmetatable;
local PCall = pcall;
local Select = select;
local Unpack = unpack or table.unpack;
local ToNumber = tonumber;
local function VMCall(ByteString, vmenv, ...)
	local DIP = 1;
	local repeatNext;
	ByteString = Subg(Sub(ByteString, 5), "..", function(byte)
		if (Byte(byte, 2) == 79) then
			repeatNext = StrToNumber(Sub(byte, 1, 1));
			return "";
		else
			local a = Char(StrToNumber(byte, 16));
			if repeatNext then
				local b = Rep(a, repeatNext);
				repeatNext = nil;
				return b;
			else
				return a;
			end
		end
	end);
	local function gBit(Bit, Start, End)
		if End then
			local Res = (Bit / (2 ^ (Start - 1))) % (2 ^ (((End - 1) - (Start - 1)) + 1));
			return Res - (Res % 1);
		else
			local Plc = 2 ^ (Start - 1);
			return (((Bit % (Plc + Plc)) >= Plc) and 1) or 0;
		end
	end
	local function gBits8()
		local a = Byte(ByteString, DIP, DIP);
		DIP = DIP + 1;
		return a;
	end
	local function gBits16()
		local a, b = Byte(ByteString, DIP, DIP + 2);
		DIP = DIP + 2;
		return (b * 256) + a;
	end
	local function gBits32()
		local a, b, c, d = Byte(ByteString, DIP, DIP + 3);
		DIP = DIP + 4;
		return (d * 16777216) + (c * 65536) + (b * 256) + a;
	end
	local function gFloat()
		local Left = gBits32();
		local Right = gBits32();
		local IsNormal = 1;
		local Mantissa = (gBit(Right, 1, 20) * (2 ^ 32)) + Left;
		local Exponent = gBit(Right, 21, 31);
		local Sign = ((gBit(Right, 32) == 1) and -1) or 1;
		if (Exponent == 0) then
			if (Mantissa == 0) then
				return Sign * 0;
			else
				Exponent = 1;
				IsNormal = 0;
			end
		elseif (Exponent == 2047) then
			return ((Mantissa == 0) and (Sign * (1 / 0))) or (Sign * NaN);
		end
		return LDExp(Sign, Exponent - 1023) * (IsNormal + (Mantissa / (2 ^ 52)));
	end
	local function gString(Len)
		local Str;
		if not Len then
			Len = gBits32();
			if (Len == 0) then
				return "";
			end
		end
		Str = Sub(ByteString, DIP, (DIP + Len) - 1);
		DIP = DIP + Len;
		local FStr = {};
		for Idx = 1, #Str do
			FStr[Idx] = Char(Byte(Sub(Str, Idx, Idx)));
		end
		return Concat(FStr);
	end
	local gInt = gBits32;
	local function _R(...)
		return {...}, Select("#", ...);
	end
	local function Deserialize()
		local Instrs = {};
		local Functions = {};
		local Lines = {};
		local Chunk = {Instrs,Functions,nil,Lines};
		local ConstCount = gBits32();
		local Consts = {};
		for Idx = 1, ConstCount do
			local Type = gBits8();
			local Cons;
			if (Type == 1) then
				Cons = gBits8() ~= 0;
			elseif (Type == 2) then
				Cons = gFloat();
			elseif (Type == 3) then
				Cons = gString();
			end
			Consts[Idx] = Cons;
		end
		Chunk[3] = gBits8();
		for Idx = 1, gBits32() do
			local Descriptor = gBits8();
			if (gBit(Descriptor, 1, 1) == 0) then
				local Type = gBit(Descriptor, 2, 3);
				local Mask = gBit(Descriptor, 4, 6);
				local Inst = {gBits16(),gBits16(),nil,nil};
				if (Type == 0) then
					Inst[3] = gBits16();
					Inst[4] = gBits16();
				elseif (Type == 1) then
					Inst[3] = gBits32();
				elseif (Type == 2) then
					Inst[3] = gBits32() - (2 ^ 16);
				elseif (Type == 3) then
					Inst[3] = gBits32() - (2 ^ 16);
					Inst[4] = gBits16();
				end
				if (gBit(Mask, 1, 1) == 1) then
					Inst[2] = Consts[Inst[2]];
				end
				if (gBit(Mask, 2, 2) == 1) then
					Inst[3] = Consts[Inst[3]];
				end
				if (gBit(Mask, 3, 3) == 1) then
					Inst[4] = Consts[Inst[4]];
				end
				Instrs[Idx] = Inst;
			end
		end
		for Idx = 1, gBits32() do
			Functions[Idx - 1] = Deserialize();
		end
		return Chunk;
	end
	local function Wrap(Chunk, Upvalues, Env)
		local Instr = Chunk[1];
		local Proto = Chunk[2];
		local Params = Chunk[3];
		return function(...)
			local Instr = Instr;
			local Proto = Proto;
			local Params = Params;
			local _R = _R;
			local VIP = 1;
			local Top = -1;
			local Vararg = {};
			local Args = {...};
			local PCount = Select("#", ...) - 1;
			local Lupvals = {};
			local Stk = {};
			for Idx = 0, PCount do
				if (Idx >= Params) then
					Vararg[Idx - Params] = Args[Idx + 1];
				else
					Stk[Idx] = Args[Idx + 1];
				end
			end
			local Varargsz = (PCount - Params) + 1;
			local Inst;
			local Enum;
			while true do
				Inst = Instr[VIP];
				Enum = Inst[1];
				if (Enum <= 6) then
					if (Enum <= 2) then
						if (Enum <= 0) then
							Stk[Inst[2]] = Inst[3] ~= 0;
						elseif (Enum == 1) then
							VIP = Inst[3];
						else
							Stk[Inst[2]] = Inst[3];
						end
					elseif (Enum <= 4) then
						if (Enum > 3) then
							do
								return;
							end
						else
							local A = Inst[2];
							Stk[A](Stk[A + 1]);
						end
					elseif (Enum > 5) then
						if (Stk[Inst[2]] ~= Inst[4]) then <-- 1
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					else
						local A = Inst[2];
						do
							return Stk[A](Unpack(Stk, A + 1, Inst[3]));
						end
					end
				elseif (Enum <= 9) then
					if (Enum <= 7) then
						if (Stk[Inst[2]] ~= Inst[4]) then  <-- 2
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					elseif (Enum == 8) then
						Stk[Inst[2]] = Inst[3] ~= 0;
						VIP = VIP + 1;
					elseif ((Inst[3] == "_ENV") or (Inst[3] == "getfenv")) then
						Stk[Inst[2]] = Env;
					else
						Stk[Inst[2]] = Env[Inst[3]];
					end
				elseif (Enum <= 11) then
					if (Enum == 10) then
						if (Inst[2] ~= Inst[4]) then  <-- 3 
							VIP = VIP + 1;
						else
							VIP = Inst[3];
						end
					else
						Stk[Inst[2]] = Stk[Inst[3]] % Inst[4];
					end
				elseif (Enum > 12) then
					local A = Inst[2];
					do
						return Unpack(Stk, A, Top);
					end
				elseif not Stk[Inst[2]] then

					VIP = VIP + 1;
				else
					VIP = Inst[3];
				end
			   VIP = VIP + 1;
			   VIP = handle_exec(Inst, VIP);
			end
		end;
	end
	return Wrap(Deserialize(), {}, vmenv)(...);
end
VMCall("LOL!0C3O00026O00F03F03053O007072696E7403273O006661696C656420746F20676574207061737420455120682O6F6B20636865636B205B305830315D03233O006661696C656420746F206765742070617374204A4D5020636865636B205B305830325D026O0008402O033O006B657900024O00C0F2F040025O00E4944003273O006661696C656420746F20676574207061737420455120682O6F6B20636865636B205B305830335D030B3O0077686974656C6973746564030F3O006E6F742077686974656C697374656400273O002E0A00010003000100010004013O000300012O00089O003O00013O00060C3O000A000100010004013O000A0001001209000100023O001202000200034O0005000100024O000D00018O000100013O00060C00010011000100010004013O00110001001209000200023O001202000300044O0005000200034O000D00025O001202000200053O001209000300063O00260700030023000100070004013O00230001001209000300063O00200B00030003000800260600030023000100090004013O002300010026070002001F000100050004013O001F0001001209000300023O0012020004000A4O0005000300044O000D00035O001209000300023O0012020004000B4O00030003000200010004013O00260001001209000300023O0012020004000C4O00030003000200012O00043O00017O00", GetFEnv(), ...);