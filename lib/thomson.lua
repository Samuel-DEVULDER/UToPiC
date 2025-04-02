-- thomson.lua : lots of utility for handling
-- thomson screen.
--
-- Version: 02-jan-2017
--
-- Copyright 2016-2017 by Samuel Devulder
--
-- This program is free software; you can redistribute
-- it and/or modify it under the terms of the GNU
-- General Public License as published by the Free
-- Software Foundation; version 2 of the License.
-- See <http://www.gnu.org/licenses/>

if not thomson then

run("color.lua") -- optionnal

local unpack = unpack or table.unpack

local MODE_40   = 0
local MODE_80   = 1
local MODE_BM4  = 2
local MODE_BM16 = 3

thomson = {optiMAP=true, mode = MODE_40}

-- RAM banks
thomson.ramA = {} -- FOND  $E7C3 even (0)
thomson.ramB = {} -- FORME $E7C3 odd  (1)

function thomson.clear()
    for i=1,8000 do
        thomson.ramA[i] = 0
        thomson.ramB[i] = 0
    end
end

-- color levels
thomson.levels = {
    -- in pc-space (0-255):
    pc = {
        -- perl -e 'for($i=0; $i<16; ++$i) {print int(.5+255*($i/15)**(1/3)),"\n";}'
           0,103,130,149,164,177,188,198,207,215,223,230,237,243,249,255
        -- 0,100,127,142,163,179,191,203,215,223,231,239,243,247,251,255
        -- perl -e 'for($i=0; $i<16; ++$i) {print int(.5+255*($i/15)**(1/2.8)),"\n";}'
        -- 0, 97,124,144,159,172,184,194,204,212,221,228,235,242,249,255
    },
    -- in linear space (0-255):
    linear = {},
    -- maps pc-levels (0-255) to thomson levels (1-16)
    pc2to={},
    -- maps linear-levels (0-255) to thomson levels (1-16)
    linear2to={}
};

-- pc space to linear space
local function toLinear(val)
    -- use the version from Color library
    if not Color then
        val = val/255
        if val<=0.081 then
            val = val/4.5;
        else
            val = ((val+0.099)/1.099)^2.2;
        end
        val = val*255
        return val;
    else
        return Color:new(val,0,0):toLinear().r
    end
end

for i=1,16 do
    thomson.levels.linear[i] = toLinear(thomson.levels.pc[i])
end
for i=0,255 do
    local r,cm,dm;
    r,cm,dm = toLinear(i),0,1e30
    for c,v in ipairs(thomson.levels.linear) do
        local d = math.abs(v-r);
        if d<dm then cm,dm = c,d; end
    end
    thomson.levels.pc2to[i] = cm;
    r,cm,dm = i,0,1e30
    for c,v in ipairs(thomson.levels.linear) do
        local d = math.abs(v-r);
        if d<dm then cm,dm = c,d; end
    end
    thomson.levels.linear2to[i] = cm;
end

-- palette stuff
function thomson.palette(i, pal)
    -- returns palette #i if pal is missing (nil)
    -- if pal is a number, sets palette #i
    -- if pal is an array, sets the palette #i, #i+1, ...
    if type(pal)=='table' then
        for j,v in ipairs(pal) do
            thomson.palette(i+j-1,v)
        end
    elseif pal and i>=0 and i<thomson._palette.max then
        thomson._palette[i+1] = pal
    elseif not pal and i>=0 and i<thomson._palette.max then
        return thomson._palette[i+1]
    end
end;
thomson._palette = {offset = 0, max=16}
thomson.default_palette = {0,15,240,255,3840,3855,4080,4095,
                           1911,826,931,938,2611,2618,3815,123}

function thomson.isDefaultPalette()
    for i=0,15 do
        if thomson.default_palette[i+1]~=thomson.palette(i) then
            return false
        end
    end
    return true
end

-- border color
function thomson.border(c)
    if c then
        thomson._border = c;
    else
        return thomson._border
    end
end
thomson.border(0)

-- helper to appen tables to tables
function thomson._append(result, ...)
    for _,tab in ipairs({...}) do
        for _,v in ipairs(tab) do
            table.insert(result,v)
        end
    end
end

-- RLE compression of data into result
function thomson._compress(result,data)
    local partial,p,pmax={},1,#data
    local function addCarToPartial(car)
        partial[2] = partial[2]+1
        partial[2+partial[2]] = car
    end
    while p<=pmax do
        local num,car = 1,data[p]
        while num<255 and p<pmax and data[p+1]==car do
            num,p = num+1,p+1
        end
        local default=true
        if partial[1] then
            -- 01 aa 01 bb ==> 00 02 aa bb
            if default and num==1 and partial[1]==1 then
                partial = {0,2,partial[2],car}
                default = false
            end
            -- 00 n xx xx xx 01 bb ==> 00 n+1 xx xx xx bb
            if default and num==1 and partial[1]==0 and partial[2]<255 then
                addCarToPartial(car)
                default = false
            end
            -- 00 n xx xx xx 02 bb ==> 00 n+2 xx xx xx bb bb (pas utile mais sert quand combiné à la regle ci-dessus)
            if default and num==2 and partial[1]==0 and partial[2]<254 then
                addCarToPartial(car)
                addCarToPartial(car)
                default = false
            end
        end
        if default then
            thomson._append(result, partial)
            partial = {num,car}
        end
        p=p+1
    end
    thomson._append(result, partial)
    return result
end

-- convert color from MO5 to TO7 (MAP requires TO7 encoding)
local function mo5to7(val)
	-- MO5: DCBA 4321
	--      __
	-- TO7: 4DCB A321
	local t=((val%16)>=8) and 0 or 128
	val = math.floor(val/16)*8 + (val%8)
	val = (val>=64 and val-64 or val+64) + t
	return val
end

-- save a map file corresponging to the current file
-- if a map file already exist, a confirmation is
-- prompted to the user
local function save_current_file()
    local function exist(file)
        local f=io.open(file,'rb')
        if not f then return false else io.close(f); return true; end
    end
    local name,path = getfilename()
    local mapname = string.gsub(name,"%.%w*$","") .. ".map"
    local fullname = path .. '/' .. mapname
    local ok = not exist(fullname)
    if not ok then
        selectbox("Ovr " .. mapname .. "?", "Yes", function() ok = true; end, "No", function() ok = false; end)
    end
    if ok then thomson.savep(fullname) end
end

-- saves the thomson screen into a MAP file
function thomson.savep(name)
	thomson.last_info = os.clock() -- enable next info()
    if not name then return save_current_file() end

    wait(0) -- allow for key handling
    local data = thomson._get_map_data()
    local function savem(name, buf, addr)
        addr = addr or 0
        local out = io.open(name,"wb")
        if addr>=0 then
            out:write(string.char(0,
                                  math.floor(buf:len()/256), buf:len()%256,
                                  math.floor(addr/256), addr%256))
        end
        out:write(buf)
        if addr>=0 then
            out:write(string.char(255,0,0,0,0))
        end
        out:close()
    end
    local string_data = ''
    if not pcall(function() string_data = string.char(unpack(data)) end) then
        for i=1,#data do
            string_data = string_data .. string.char(data[i])
        end
    end
    savem(name, string_data)

    local function saveb_old(name, thomson)
        local data = {}

        local out = io.open(name,"wb")
        local lineno = 30000
        local function pr(txt)
            out:write(lineno .. " " .. txt .. "\r\n")
            lineno = lineno+10
        end
        if thomson.mode~=0 then pr("CONSOLE,,,,"..thomson.mode) end
        pr("LOCATE 0,0,0:COLOR 0,0")
        pr("SCREEN,,0:CLS:COLOR 7")
        pr("DEFINTA-Z")
        if not thomson.isDefaultPalette() then
            for i=0,15 do
                pr("PALETTE "..i..","..thomson.palette(i))
            end
        end
        pr("FOR J=0 TO 199:I=0:D=0")
        local loop = lineno
		if thomson.w==160 then
			pr('  READ C$:C=VAL("&H"+C$):L=C@16')
			pr("  LINE(I,J)-(I+L,J),15ANDC:I=I+L+1:IF I<>"..(thomson.w).." THEN "..loop)
		else
			pr('  READ C$:C=VAL("&H"+C$):L=C@16:D=NOT D')
			pr("  LINE(I,J)-(I+L,J),(15ANDC)XORD:I=I+L+1:IF I<>"..(thomson.w).." THEN "..loop)
		end
        pr("NEXT")
        local data=''
        for j=0,thomson.h-1 do
            local i=0
			local function p(i)
				local p=thomson.point(i,j)
				return p<0 and -1-p or p
			end
            while i<thomson.w do
                local x,c = i, p(i)
                repeat i = i+1 until i==thomson.w or c~=p(i)
                c = (i - 1 - x)*16 + c
                local l,t = data:len(),string.format(",%X", c)
                if data:len()+t:len()>=30*7 then
                    pr("DATA " .. data:sub(2))
                    data = t
                else
                    data = data..t
                end
            end
        end
		if thomson.w==160 then pr("DO:LOOP") end
        pr("DATA " .. data:sub(2))
        out:write("\r\nRUN")
        out:close()
    end

    local function saveb_old2(name, thomson)
        local data = {}

		local MID = '.-+=*<>!&@abcdefghijklmnopqrstuvwxyz?'
		local END = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ#'
		local BASE = MID:len()

        local out = io.open(name,"wb")
        local lineno = 30000
        local function pr(txt)
            out:write(lineno .. " " .. txt .. "\r\n")
            lineno = lineno+10
        end
        if thomson.w==160 then pr("CONSOLE,,,,3") end
        pr("LOCATE 0,0,0:COLOR 0,0")
        pr("SCREEN,,0:CLS:COLOR 7")
        pr("DEFINTA-Z")
        if not thomson.isDefaultPalette() then
            for i=0,15 do
                pr("PALETTE "..i..","..thomson.palette(i))
            end
        end
		pr('A$="' .. MID..'"')
		pr('B$="' .. END..'"')
		pr('C$="":A=1:C=0:L=0')
        pr("FOR J=0 TO 199:I=0:D=0")
        local loop = lineno
		pr('  IF A>L THEN READ C$:A=1:L=LEN(C$)')
		pr('  D$=MID$(C$,A,1):A=A+1')
		pr('  B=INSTR(A$,D$):IF B THEN C='..BASE..'*C+B-1:GOTO'..loop)
		pr('  C='..BASE..'*C+INSTR(B$,D$)-1:B=C@16+I')
		local COL = thomson.w==160 and "15ANDC" or "(15ANDC)XORD:D=NOT D"
		pr('  LINE(I,J)-(B,J),'..COL..':I=B+1:C=0')
		pr('  IF I<>'..(thomson.w)..'THEN'..loop)
		pr('NEXT')
		pr("DO:LOOP")
        local data=''
        for j=0,thomson.h-1 do
            local i=0
			local function p(i)
				local p=thomson.point(i,j)
				return p<0 and -1-p or p
			end
            while i<thomson.w do
                local x,c = i, p(i)
                repeat i = i+1 until i==thomson.w or c~=p(i)
                c = (i - 1 - x)*16 + c
				x,c = 1+(c%BASE),math.floor(c/BASE)
                local t = END:sub(x,x)
				while c>0 do
				   x,c = 1+(c%BASE),math.floor(c/BASE)
				   t = MID:sub(x,x)..t
				end
                if data:len()+t:len()>=30*7 then
                    pr("DATA " .. data)
                    data = t
                else
                    data = data..t
                end
            end
        end
        pr("DATA " .. data)
        out:write("\r\nRUN")
        out:close()
    end

    local function saveb_old3(name, thomson)
        local data = {}

		local MID = '.-+=*<>!&@abcdefghijklmnopqrstuvwxyz?'
		local END = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ#'
		local BASE = MID:len()

        local out = io.open(name,"wb")
        local lineno = 30000
        local function pr(txt)
            out:write(lineno .. " " .. txt .. "\r\n")
            lineno = lineno+10
        end
        if thomson.w==160 then pr("CONSOLE,,,,3") end
        pr("LOCATE 0,0,0:COLOR 0,0")
        pr("SCREEN,,0:CLS:COLOR 7")
        pr("DEFINTA-Z")
        if not thomson.isDefaultPalette() then
            for i=0,15 do
                pr("PALETTE "..i..","..thomson.palette(i))
            end
        end

        pr("FOR J=0 TO 199:I=0")
        local loop = lineno
		pr('  READ C$:C=VAL("&H"+C$)')
		pr('  IF C<32 THEN PSET(I,J),16-C:I=I+1:IF I<'..thomson.w..' THEN'..loop..'ELSE'..(lineno+40))
		pr('  O=I-(C@32):FOR K=0TO(31ANDC)+1')
		pr('  PSET(I+K,J),POINT(O+K,J):NEXT:I=I+(31ANDC)+2')
		pr('  IF I<'..thomson.w..' THEN '..loop)
		pr('NEXT')
		pr('GOTO'..lineno)
        local data=''
        for j=0,thomson.h-1 do
			local px={}; for i=0,thomson.w-1 do px[i] = 16-thomson.point(i,j) end
			local i=0
			while i<thomson.w do
			    local best,code = 1,px[i]
				for o=1,math.min(64,i) do
					local k=0
					while px[i+k]==px[i-o+k] and k<32 do k=k+1 end
					if k>best then best,code = k,o*32+k-2 end
				end
				i=i+best
				local t = string.format(',%X',code)
				if data:len()+t:len()>=30*7 then
                    pr("DATA " .. data:sub(2))
                    data = t
                else
                    data = data..t
                end
			end
        end
        pr("DATA " .. data:sub(2))
        out:write("\r\nRUN")
        out:close()
    end

    local function saveb_old4(name, thomson)
        local data = {}

		local MID = '.-+=*<>!&@abcdefghijklmnopqrstuvwxyz?'
		local END = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ#'
		local BASE = MID:len()

        local out = io.open(name,"wb")
        local lineno = 30000
        local function pr(txt)
            out:write(lineno .. " " .. txt .. "\r\n")
            lineno = lineno+10
        end
        if thomson.w==160 then pr("CONSOLE,,,,3") end
        pr("LOCATE 0,0,0:COLOR 0,0")
        pr("SCREEN,,0:CLS:COLOR 7")
        pr("DEFINTA-Z")
        if not thomson.isDefaultPalette() then
            for i=0,15 do
                pr("PALETTE "..i..","..thomson.palette(i))
            end
        end
		pr('A$="' .. MID..'"')
		pr('B$="' .. END..'"')
		-- local loop=lineno
        -- pr('READ C$:FOR A=1 TO LEN(C$)')
		-- pr('D$=MID$(C$,A,1):B=INSTR(A$,D$)')
		-- pr('IF B THEN C='..BASE..'*C+B-1:GOTO '..(lineno+30).. ' ELSE C='..BASE..'*C+INSTR(B$,D$)-1')
		-- pr('IF C<32 THEN PSET(I,J),C-16:I=I+1 ELSE O=C@32:FOR I=I TO(31ANDC)+I+1:PSET(I,J),POINT(I-O,J):NEXT')
		-- pr('C=0:IF I>='..thomson.w..' THEN I=0:J=J+1')
		-- pr('NEXT:IF J<'..thomson.h..' THEN '..loop)
		-- pr('GOTO '..lineno)



		-- 30250 I=0:J=0:READ C$
		-- 30260 C=T(ASC(C$)):IF LEN(C$)=1 THEN READ C$ ELSE C$=MID$(C$,2)
		-- 30270 IF 64ANDC THEN C=63ANDC ELSE IF C<32 THEN PSET(I,J),C-16:I=I+1:GOTO 30290 ELSE 30280
		-- 30275 B=T(ASC(C$)):IF LEN(C$)=1 THEN READ C$ ELSE C$=MID$(C$,2)
		-- 30276 C=C*37+(63ANDB):IF 64ANDB THEN 30275
		-- 30280 O=C@32:FOR I=I TO(31ANDC)+I+1:PSET(I,J),POINT(I-O,J):NEXT
		-- 30290 IF I<160 THEN 30260 ELSE I=0:J=J+1
		-- 30300 IF J<200 THEN 30260
		-- 30310 GOTO 30310

		pr('DIM T(127)')
		pr('FOR I=1 TO LEN(A$):T(ASC(MID$(A$,I,1)))=I-1:NEXT')
		pr('FOR I=1 TO LEN(B$):T(ASC(MID$(B$,I,1)))=-I:NEXT')
		pr('I=0:J=0:C=0')
		local loop=lineno
        pr('READ C$:FOR A=1 TO LEN(C$)')
		pr('B=T(ASC(MID$(C$,A,1))):IF B<0 THEN C='..BASE..'*C-B-1 ELSE '..(lineno+30))
		pr('IF C<32 THEN PSET(I,J),C-16:I=I+1 ELSE O=C@32:FOR I=I TO(31ANDC)+I+1:PSET(I,J),POINT(I-O,J):NEXT')
		pr('C=0:B=0:IF I='..thomson.w..' THEN I=0:J=J+1')
		pr('C='..BASE..'*C+B:NEXT:IF J<'..thomson.h..' THEN '..loop)
		pr('GOTO '..lineno)
        local data=''
        for j=0,thomson.h-1 do
			local px={}; for i=0,thomson.w-1 do px[i] = 16+thomson.point(i,j) end
			local i=0
			while i<thomson.w do
			    local best,code = 1,px[i]
				for o=1,i do
					local k=0
					while px[i+k]==px[i-o+k] and k<33 do k=k+1 end
					if k>best then best,code = k,o*32+k-2 end
				end
				i=i+best
				local x,c = 1+(code%BASE),math.floor(code/BASE)
                local t = END:sub(x,x)
				while c>0 do
				   x,c = 1+(c%BASE),math.floor(c/BASE)
				   t = MID:sub(x,x)..t
				end
				if data:len()+t:len()>=30*7 then
                    pr("DATA " .. data)
                    data = t
                else
                    data = data..t
                end
			end
        end
        pr("DATA " .. data)
        out:write("\r\nRUN")
        out:close()
    end

    local function saveb_old5(name, thomson)
        local data = {}

		local BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' ..
		               'abcdefghijklmnopqrstuvwxyz' ..
					   '0123456789' ..
					   '+/'
		local BASE = BASE64:len()

        local out = io.open(name,"wb")
        local lineno = 30000
        local function pr(txt)
            out:write(lineno .. " " .. txt .. "\r\n")
            lineno = lineno+10
        end
		local ROTATE = false
		pr("CLEAR 300")
        if thomson.w==160 then pr("CONSOLE,,,,3") end
        pr("LOCATE 0,0,0:COLOR 0,0")
        pr("SCREEN,,0:CLS:COLOR 7")
        pr("DEFINTA-Z")
        if not thomson.isDefaultPalette() then
		    pr('FOR I=0 TO 15:READ C:PALETTE I,C:NEXT')
			local t = ''
			for i=0,15 do t = t..','..thomson.palette(i) end
			pr('DATA ' .. t:sub(2))
        end

		-- thomson.h=2
		local w,h,p,IJ,IJC = thomson.w,thomson.h,thomson.point,'I,J','I-C,J'
		if ROTATE then w,h,p,IJ,IJC=h,w,function(x,y) return thomson.point(y,x) end,'J,I','J,I-C' end

		pr('C$="' .. BASE64 ..'"')
		pr('DIM T(122):FOR I=1 TO LEN(C$):T(ASC(MID$(C$,I,1)))=I-1:NEXT')
		pr('I=0:J=0')
		local loopback = 'IF A<L THEN '..(lineno+10)..' ELSE IF I<'..w..' THEN ' .. lineno .. ' ELSE I=0:J=J+1:IF J<'..h..' THEN '..lineno
		pr('READ C$:L=LEN(C$):A=0')
        pr('A=A+1:C=T(ASC(MID$(C$,A,1))):IF 32ANDC THEN PSET('..IJ..'),C-48:I=I+1:' .. loopback .. ' ELSE '..(lineno+30))
		-- pr('A=A+1:B=T(ASC(MID$(C$,A,1))):IF B<32 THEN C=C*32+B:GOTO '..lineno)
		pr('A=A+1:B=T(ASC(MID$(C$,A,1))):IF B<32 THEN C=C*32+B:A=A+1:B=T(ASC(MID$(C$,A,1)))')
		pr('FOR I=I TO I+B-31:PSET('..IJ..'),POINT('..IJC..'):NEXT:'..loopback)
		-- pr('A=A+1:B=T(ASC(MID$(C$,A,1))):IF B<32 THEN C=C*32+B:GOTO '..lineno)
		-- pr('IF C THEN FOR I=I TO I+B-31:PSET('..IJ..'),POINT('..IJC..'):NEXT ELSE PSET('..IJ..'),B-48:I=I+1')
		-- pr('C=0:'..loopback)
		pr('GOTO '..lineno)
		-- pr('IF INKEY$="" THEN '..lineno..' ELSE RUN ""')
        local data,maxlen='',256-12
        for j=0,h-1 do
			local px={}; for i=0,w-1 do px[i] = 16+p(i,j) end
			local i=0
			while i<w do
			    local best,code = 1,px[i]
				for o=1,i do
					local k=0
					while px[i+k]==px[i-o+k] and k<33 do k=k+1 end
					if k>best then best,code = k,o*32+k-2 end
				end
				i=i+best
				local x,c = 33+(code%32),math.floor(code/32)
                local t = BASE64:sub(x,x)
				while c>0 do
				   x,c = 1+(c%32),math.floor(c/32)
				   t = BASE64:sub(x,x)..t
				end
				if data:len()+t:len()>=maxlen then
                    pr("DATA " .. data)
                    data = t
                else
                    data = data..t
                end
			end
			if j~=h-1 and data:len()+2<maxlen then
				data=data..','
			else
                pr("DATA " .. data)
                data = ''
			end
        end
		-- if data~='' then pr("DATA " .. data) end
		out:write("\r\nRUN")
        out:close()
    end

    local function saveb_old6(name, thomson)
		local BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' ..
		               'abcdefghijklmnopqrstuvwxyz' ..
					   '0123456789' ..
					   '+/'

        local out = io.open(name,"wb")
        local lineno = 30000
        local function pr(txt)
            out:write(lineno .. " " .. txt .. "\r\n")
            lineno = lineno+10
        end
		local ROTATE = false
		
		pr("CLEAR300:DEFINTA-W")
        pr("LOCATE0,0,0:COLOR0,0:SCREEN,,0:CLS:COLOR7")
        if thomson.w==160 then pr("IFPEEK(&HFFF0)=2THEN?CHR$(27);CHR$(&H5E);:SCREEN,,0ELSECONSOLE,,,,3") end

		-- thomson.h=2
		local data,maxlen='',256-12
		local w,h,p,IJ,IJC = thomson.w,thomson.h,thomson.point,'I,J','I-C,J'
		if ROTATE then w,h,p,IJ,IJC=h,w,function(x,y) return thomson.point(y,x) end,'J,I','J,I-C' end
		
		if not ROTATE then
			local asm = {
				'9ED0                      ORG    $A000-(fin-debut)   ',
				'                                                     ',
				'9ED0                  debut                          ',
				'                                                     ',
				'9ED0                  multiple                       ',
				'9ED0  6AE4                DEC     ,S                 ',
				'                                                     ',
				'9ED2  4F                  CLRA                       ',
				'9ED3  3406                PSHS    D                  ',
				'                                                     ',
				'9ED5  E6C0                LDB     ,U+                ',
				'9ED7  E685                LDB     B,X                ',
				'9ED9  C520                BITB    #32                ',
				'9EDB  2611                BNE     done_mult          ',
				'                                                     ',
				'9EDD  8620                LDA     #32                ',
				'9EDF  E7E4                STB     ,S                 ',
				'9EE1  E661                LDB     1,S                ',
				'9EE3  3D                  MUL                        ',
				'9EE4  EAE4                ORB     ,S                 ',
				'9EE6  EDE4                STD     ,S                 ',
				'                                                     ',
				'9EE8  6A62                DEC     2,S                ',
				'9EEA  E6C0                LDB     ,U+                ',
				'9EEC  E685                LDB     B,X                ',
				'                                                     ',
				'9EEE                  done_mult                      ',
				'9EEE  C01E                SUBB    #30                ',
				'9EF0  1F98                TFR     B,A                ',
				'                                                     ',
				'9EF2                  mult_loop                      ',
				'9EF2  3432                PSHS    A,X,Y              ',
				'9EF4  ECA4                LDD     ,Y                 ',
				'9EF6  A365                SUBD    5,S                ',
				'9EF8  1F01                TFR     D,X                ',
				'9EFA  10AE22              LDY     2,Y                ',
				'9EFD  8D7C                BSR     POINT              ',
				'9EFF  3532                PULS    A,X,Y              ',
				'9F01  8D24                BSR     PLOT               ',
				'9F03  4A                  DECA                       ',
				'9F04  26EC                BNE     mult_loop          ',
				'9F06  3262                LEAS    2,S                ',
				'9F08  2010                BRA     loop2              ',
				'                                                     ',
				'9F0A                  decode                         ',
				'9F0A  E7E2                STB     ,-S                ',
				'9F0C  2710                BEQ     exit               ',
				'9F0E                  loop                           ',
				'9F0E  E6C0                LDB     ,U+                ',
				'9F10  E685                LDB     B,X                ',
				'9F12  C520                BITB    #32                ',
				'9F14  27BA                BEQ     multiple           ',
				'9F16                  single                         ',
				'9F16  C030                SUBB    #48                ',
				'9F18  8D0D                BSR     PLOT               ',
				'9F1A                  loop2                          ',
				'9F1A  6AE4                DEC     ,S                 ',
				'9F1C  26F0                BNE     loop               ',
				'                                                     ',
				'9F1E                  exit                           ',
				'9F1E  EEA4                LDU     ,Y                 ',
				'9F20  3516                PULS    D,X                ',
				'9F22  8602                LDA     #2                 ',
				'9F24  EF02                STU     2,X ; FACMO/LO     ',
				'9F26  39                  RTS                        ',
				'                                                     ',
				'9F27                  PLOT                           ',
				'9F27  E7A9FE88            STB     $2029-$21A1,Y      ',
				'9F2B  3430                PSHS    X,Y                ',
				'9F2D  AEA4                LDX     ,Y                 ',
				'9F2F  10AE22              LDY     2,Y                ',
				'9F32  8D42                BSR     PSET               ',
				'9F34  3530                PULS    X,Y                ',
				'9F36  6C21                INC     1,Y                ',
				'9F38  2602                BNE     PLOT1              ',
				'9F3A  6CA4                INC     ,Y                 ',
				'9F3C                  PLOT1                          ',
				'9F3C  39                  RTS                        ',
				'                                                     ',
				'9F3D                  entry                          ',
				'9F3D  3414                PSHS    B,X                ',
				'9F3F  1FB8                TFR     DP,A               ',
				'9F41  C6A1                LDB     #$A1               ',
				'9F43  1F02                TFR     D,Y                ',
				'9F45  E6E4                LDB     ,S                 ',
				'9F47  EE01                LDU     1,X                ',
				'9F49  308C34              LEAX    BASE64,PCR         ',
				'9F4C  A684                LDA     ,X                 ',
				'9F4E  27BA                BEQ     decode             ',
				'                                                     ',
				'9F50                  init                           ',
				'9F50  867F                LDA     #127               ',
				'9F52                  init1                          ',
				'9F52  6F86                CLR     A,X                ',
				'9F54  4A                  DECA                       ',
				'9F55  2AFB                BPL     init1              ',
				'9F57                  init2                          ',
				'9F57  5A                  DECB                       ',
				'9F58  2B06                BMI     init3              ',
				'9F5A  A6C5                LDA     B,U                ',
				'9F5C  E786                STB     A,X                ',
				'9F5E  20F7                BRA     init2              ',
				'9F60                  init3                          ',
				'9F60  3408                PSHS    DP                 ',
				'9F62  8640                LDA     #$40               ',
				'9F64  A4E4                ANDA    ,S                 ',
				'9F66  27B6                BEQ     exit               ',
									'* setup TO                       ',
				'9F68  8681                LDA     #$81 ; CMPA#       ',
				'9F6A  A716                STA     PSET-BASE64,X      ',
				'9F6C  A71B                STA     POINT-BASE64,X     ',
				'9F6E  CCFE97              LDD     #$6038-$61A1       ',
				'9F71  ED88A9              STD     PLOT+2-BASE64,X    ',
				'9F74  20A8                BRA     exit               ',
				'                                                     ',
				'9F76                  PSET                           ',
				'9F76  3F                  SWI                        ',
				'9F77  90                  FCB     $90                ',
				'9F78  7EE80F              JMP     $E80F              ',
				'                                                     ',
				'9F7B                  POINT                          ',
				'9F7B  3F                  SWI                        ',
				'9F7C  94                  FCB     $94                ',
				'9F7D  7EE821              JMP     $E821              ',
				'                                                     ',
				'9F80                  BASE64                         ',
				'9F80  FF                  FCB     -1                 ',
				'9F81                      RMB     127                ',
				'                                                     ',
				'A000                  fin                            ',
				'                                                     ',
				'A000                      END init                   '
			}                        
			local hex,start,stop,entry=''
			for _,l in ipairs(asm) do                        
				local a,h = l:match('(%x%x%x%x)  (%x+)%s+')
				if h then
					hex = hex..h
					start = start or a
					stop = a
				else
					local e = l:match('(%x%x%x%x)%s+entry ')
					if e then entry = e end
				end
			end
			local NOASM = lineno + 90
			pr("IFFRE(0)<32000THEN"..NOASM) 
			pr("CLEAR,&H9ECF:RESTORE"..lineno..':FORX=&H'..start..' TO&H'..stop..':READB$:POKEX,VAL("&H"+B$):NEXT:DEFUSR=&H'..entry)
			for i=1,hex:len(),2 do
				local t = ','..hex:sub(i,i+1)
				if data:len()+t:len()>=maxlen then
					pr("DATA " .. data:sub(2))
					data = t
				 else
					data = data..t
				 end
			end
			pr("DATA " .. data:sub(2))

			if not thomson.isDefaultPalette() then
				local t = ''
				for i=0,15 do t = t..','..thomson.palette(i) end
				pr('FORI=0TO15:READJ:PALETTEI,J:NEXT:DATA' .. t:sub(2))
			end			
			
			pr('READA$:I=USR(A$):I=0:J=0')
			pr('PSET(I,J),POINT(I,J):READA$:I=USR(A$):IFI<'..w..'THEN'..lineno..'ELSEI=0:J=J+1:IFJ<'..h..'THEN'..lineno)
			pr("GOTO"..(NOASM+60))
			lineno = NOASM
		end
	   		
		pr('RESTORE'..lineno..':READA$:DIMT(122):FORI=1TOLEN(A$):T(ASC(MID$(A$,I,1)))=I-1:NEXT:I=0:J=0')
		pr('DATA ' .. BASE64)

		local loopback = 'IFA<L THEN'..(lineno+10)..'ELSEIFI<'..w..'THEN'..lineno ..'ELSEI=0:J=J+1:IFJ<'..h..'THEN'..lineno
		pr('READA$:L=LEN(A$):A=0')
        pr('A=A+1:C=T(ASC(MID$(A$,A,1))):IFC>31THENPSET('..IJ..'),C-48:I=I+1:' .. loopback .. 'ELSE'..(lineno+30))
		pr('A=A+1:B=T(ASC(MID$(A$,A,1))):IFB<32THENC=C*32+B:A=A+1:B=T(ASC(MID$(A$,A,1)))')
		pr('FORI=I TOI+B-31:PSET('..IJ..'),POINT('..IJC..'):NEXT:'..loopback)

		-- pr('IF INKEY$="" THEN '..lineno..' ELSE RUN ""')
		pr('GOTO'..lineno)

		data=''
        for j=0,h-1 do
			local px={}; for i=0,w-1 do px[i] = 16+p(i,j) end
			local i=0
			while i<w do
			    local best,code = 1,px[i]
				for o=1,i do
					local k=0
					while px[i+k]==px[i-o+k] and k<33 do k=k+1 end
					if k>best then best,code = k,o*32+k-2 end
				end
				i=i+best
				local x,c = 33+(code%32),math.floor(code/32)
                local t = BASE64:sub(x,x)
				while c>0 do
				   x,c = 1+(c%32),math.floor(c/32)
				   t = BASE64:sub(x,x)..t
				end
				if data:len()+t:len()>=maxlen then
                    pr("DATA " .. data)
                    data = t
                else
                    data = data..t
                end
			end
			if j~=h-1 and data:len()+2<maxlen then
				data=data..','
			else
                pr("DATA " .. data)
                data = ''
			end
        end
		-- if data~='' then pr("DATA " .. data) end
		out:write("\r\nRUN")
        out:close()
    end

    local function saveb_old7(name, thomson)
		local BASE90 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ012345' .. -- 32
		               'abcdefghijklmnopqrstuvwxyz678' .. -- 29
					   '_`~.-+=*<>[](){}$%#?&@;!^\\|/9' -- 29 --> 90~
					   
        -- 0..31 -> token
		-- 32..60 -> 29 = repeat 2..31 depuis -1
		-- 61..89 -> 29 = repeat 2..31 depuis -(2+suivant = 92 max)

        local out = io.open(name,"wb")
        local lineno = 30000
        local function pr(txt)
            out:write(lineno .. " " .. txt .. "\r\n")
            lineno = lineno+10
        end
		local ROTATE = false
		
		pr("CLEAR300:DEFINTA-W")
        pr("LOCATE0,0,0:COLOR0,0:SCREEN,,0:CLS:COLOR7")
        if thomson.w==160 then pr("IFPEEK(&HFFF0)=2THEN?CHR$(27);CHR$(&H5E);:SCREEN,,0ELSECONSOLE,,,,3") end

		-- thomson.h=2
		local data,maxlen='',256-12
		local w,h,p,IJ,IJC = thomson.w,thomson.h,thomson.point,'I,J','I-C,J'
		if ROTATE then w,h,p,IJ,IJC=h,w,function(x,y) return thomson.point(y,x) end,'J,I','J,I-C' end
		
		if false and not ROTATE then
			local asm = {
				'9ED0                      ORG    $A000-(fin-debut)   ',
				'                                                     ',
				'9ED0                  debut                          ',
				'                                                     ',
				'9ED0                  multiple                       ',
				'9ED0  6AE4                DEC     ,S                 ',
				'                                                     ',
				'9ED2  4F                  CLRA                       ',
				'9ED3  3406                PSHS    D                  ',
				'                                                     ',
				'9ED5  E6C0                LDB     ,U+                ',
				'9ED7  E685                LDB     B,X                ',
				'9ED9  C520                BITB    #32                ',
				'9EDB  2611                BNE     done_mult          ',
				'                                                     ',
				'9EDD  8620                LDA     #32                ',
				'9EDF  E7E4                STB     ,S                 ',
				'9EE1  E661                LDB     1,S                ',
				'9EE3  3D                  MUL                        ',
				'9EE4  EAE4                ORB     ,S                 ',
				'9EE6  EDE4                STD     ,S                 ',
				'                                                     ',
				'9EE8  6A62                DEC     2,S                ',
				'9EEA  E6C0                LDB     ,U+                ',
				'9EEC  E685                LDB     B,X                ',
				'                                                     ',
				'9EEE                  done_mult                      ',
				'9EEE  C01E                SUBB    #30                ',
				'9EF0  1F98                TFR     B,A                ',
				'                                                     ',
				'9EF2                  mult_loop                      ',
				'9EF2  3432                PSHS    A,X,Y              ',
				'9EF4  ECA4                LDD     ,Y                 ',
				'9EF6  A365                SUBD    5,S                ',
				'9EF8  1F01                TFR     D,X                ',
				'9EFA  10AE22              LDY     2,Y                ',
				'9EFD  8D7C                BSR     POINT              ',
				'9EFF  3532                PULS    A,X,Y              ',
				'9F01  8D24                BSR     PLOT               ',
				'9F03  4A                  DECA                       ',
				'9F04  26EC                BNE     mult_loop          ',
				'9F06  3262                LEAS    2,S                ',
				'9F08  2010                BRA     loop2              ',
				'                                                     ',
				'9F0A                  decode                         ',
				'9F0A  E7E2                STB     ,-S                ',
				'9F0C  2710                BEQ     exit               ',
				'9F0E                  loop                           ',
				'9F0E  E6C0                LDB     ,U+                ',
				'9F10  E685                LDB     B,X                ',
				'9F12  C520                BITB    #32                ',
				'9F14  27BA                BEQ     multiple           ',
				'9F16                  single                         ',
				'9F16  C030                SUBB    #48                ',
				'9F18  8D0D                BSR     PLOT               ',
				'9F1A                  loop2                          ',
				'9F1A  6AE4                DEC     ,S                 ',
				'9F1C  26F0                BNE     loop               ',
				'                                                     ',
				'9F1E                  exit                           ',
				'9F1E  EEA4                LDU     ,Y                 ',
				'9F20  3516                PULS    D,X                ',
				'9F22  8602                LDA     #2                 ',
				'9F24  EF02                STU     2,X ; FACMO/LO     ',
				'9F26  39                  RTS                        ',
				'                                                     ',
				'9F27                  PLOT                           ',
				'9F27  E7A9FE88            STB     $2029-$21A1,Y      ',
				'9F2B  3430                PSHS    X,Y                ',
				'9F2D  AEA4                LDX     ,Y                 ',
				'9F2F  10AE22              LDY     2,Y                ',
				'9F32  8D42                BSR     PSET               ',
				'9F34  3530                PULS    X,Y                ',
				'9F36  6C21                INC     1,Y                ',
				'9F38  2602                BNE     PLOT1              ',
				'9F3A  6CA4                INC     ,Y                 ',
				'9F3C                  PLOT1                          ',
				'9F3C  39                  RTS                        ',
				'                                                     ',
				'9F3D                  entry                          ',
				'9F3D  3414                PSHS    B,X                ',
				'9F3F  1FB8                TFR     DP,A               ',
				'9F41  C6A1                LDB     #$A1               ',
				'9F43  1F02                TFR     D,Y                ',
				'9F45  E6E4                LDB     ,S                 ',
				'9F47  EE01                LDU     1,X                ',
				'9F49  308C34              LEAX    BASE64,PCR         ',
				'9F4C  A684                LDA     ,X                 ',
				'9F4E  27BA                BEQ     decode             ',
				'                                                     ',
				'9F50                  init                           ',
				'9F50  867F                LDA     #127               ',
				'9F52                  init1                          ',
				'9F52  6F86                CLR     A,X                ',
				'9F54  4A                  DECA                       ',
				'9F55  2AFB                BPL     init1              ',
				'9F57                  init2                          ',
				'9F57  5A                  DECB                       ',
				'9F58  2B06                BMI     init3              ',
				'9F5A  A6C5                LDA     B,U                ',
				'9F5C  E786                STB     A,X                ',
				'9F5E  20F7                BRA     init2              ',
				'9F60                  init3                          ',
				'9F60  3408                PSHS    DP                 ',
				'9F62  8640                LDA     #$40               ',
				'9F64  A4E4                ANDA    ,S                 ',
				'9F66  27B6                BEQ     exit               ',
									'* setup TO                       ',
				'9F68  8681                LDA     #$81 ; CMPA#       ',
				'9F6A  A716                STA     PSET-BASE64,X      ',
				'9F6C  A71B                STA     POINT-BASE64,X     ',
				'9F6E  CCFE97              LDD     #$6038-$61A1       ',
				'9F71  ED88A9              STD     PLOT+2-BASE64,X    ',
				'9F74  20A8                BRA     exit               ',
				'                                                     ',
				'9F76                  PSET                           ',
				'9F76  3F                  SWI                        ',
				'9F77  90                  FCB     $90                ',
				'9F78  7EE80F              JMP     $E80F              ',
				'                                                     ',
				'9F7B                  POINT                          ',
				'9F7B  3F                  SWI                        ',
				'9F7C  94                  FCB     $94                ',
				'9F7D  7EE821              JMP     $E821              ',
				'                                                     ',
				'9F80                  BASE64                         ',
				'9F80  FF                  FCB     -1                 ',
				'9F81                      RMB     127                ',
				'                                                     ',
				'A000                  fin                            ',
				'                                                     ',
				'A000                      END init                   '
			}                        
			local hex,start,stop,entry=''
			for _,l in ipairs(asm) do                        
				local a,h = l:match('(%x%x%x%x)  (%x+)%s+')
				if h then
					hex = hex..h
					start = start or a
					stop = a
				else
					local e = l:match('(%x%x%x%x)%s+entry ')
					if e then entry = e end
				end
			end
			local NOASM = lineno + 90
			pr("IFFRE(0)<32000THEN"..NOASM) 
			pr("CLEAR,&H9ECF:RESTORE"..lineno..':FORX=&H'..start..' TO&H'..stop..':READB$:POKEX,VAL("&H"+B$):NEXT:DEFUSR=&H'..entry)
			for i=1,hex:len(),2 do
				local t = ','..hex:sub(i,i+1)
				if data:len()+t:len()>=maxlen then
					pr("DATA " .. data:sub(2))
					data = t
				 else
					data = data..t
				 end
			end
			pr("DATA " .. data:sub(2))

			if not thomson.isDefaultPalette() then
				local t = ''
				for i=0,15 do t = t..','..thomson.palette(i) end
				pr('FORI=0TO15:READJ:PALETTEI,J:NEXT:DATA' .. t:sub(2))
			end			
			
			pr('READA$:I=USR(A$):I=0:J=0')
			pr('PSET(I,J),POINT(I,J):READA$:I=USR(A$):IFI<'..w..'THEN'..lineno..'ELSEI=0:J=J+1:IFJ<'..h..'THEN'..lineno)
			pr("GOTO"..(NOASM+60))
			lineno = NOASM
		end
	   		
		pr('RESTORE'..lineno..':READA$:DIMT(126):FORI=1TOLEN(A$):T(ASC(MID$(A$,I,1)))=I-1:NEXT:I=0:J=0')
		pr('DATA ' .. BASE90)

		local loopback = 'IFA<L THEN'..(lineno+10)..'ELSEIFI<'..w..'THEN'..lineno ..'ELSEI=0:J=J+1:IFJ<'..h..'THEN'..lineno
		pr('READA$:L=LEN(A$):A=0')
        pr('A=A+1:B=T(ASC(MID$(A$,A,1))):IFB<32THENPSET('..IJ..'),B-16:I=I+1:' .. loopback .. 'ELSE'..(lineno+30))
		pr('B=B-31:IFB>29THENB=B-28:A=A+1:C=T(ASC(MID$(A$,A,1)))+2ELSEC=1')
		pr('FORI=I TOI+B:PSET('..IJ..'),POINT('..IJC..'):NEXT:'..loopback)

		-- pr('IF INKEY$="" THEN '..lineno..' ELSE RUN ""')
		pr('GOTO'..lineno)

		data=''
        for j=0,h-1 do
			local px={}; for i=0,w-1 do px[i] = p(i,j) end
			local i=0
			while i<w do
			    local best,B,C = 1,px[i]+16,0
				for o=1,math.min(i,91) do
					local k=0
					while px[i+k]==px[i-o+k] and k<30 do k=k+1 end
					-- if o==1 and k>30  then k=30 end
					if o>=2 and k==2  then k=0  end
					if k>best then
						if o>=2 then 
							best,B,C = k,k-3+61,o
						else 
							best,B,C = k,k-2+32,o
						end
					end
				end
				local t=BASE90:sub(1+B,1+B)
				if C>=2 then t=t..BASE90:sub(C-1,C-1) end
				-- if i==1 then error(t..' '..B..' '..C) end
				if data:len()+t:len()>=maxlen then
                    pr("DATA " .. data)
                    data = t
                else
                    data = data..t
                end
				i=i+best
			end
			if j~=h-1 and data:len()+2<maxlen then
				data=data..','
			else
                pr("DATA " .. data)
                data = ''
			end
        end
		-- if data~='' then pr("DATA " .. data) end
		out:write("\r\nRUN")
        out:close()
    end

    local function saveb_old8(name, thomson)
		local BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' ..
		               'abcdefghijklmnopqrstuvwxyz' ..
					   '0123456789' ..
					   '+/'

        local out = io.open(name,"wb")
        local lineno = 30000
        local function pr(txt)
            out:write(lineno .. " " .. txt .. "\r\n")
            lineno = lineno+10
        end
		local ROTATE = false
		
		pr("CLEAR300:DEFINTA-W")
        pr("LOCATE0,0,0:COLOR0,0:SCREEN,,0:CLS:COLOR7")
        if thomson.w==160 then pr("IFPEEK(&HFFF0)=2THEN?CHR$(27);CHR$(&H5E);:SCREEN,,0ELSECONSOLE,,,,3") end

		-- thomson.h=2
		local data,maxlen='',256-12
		local w,h,p,IJ,IJC = thomson.w,thomson.h,thomson.point,'I,J','I+C,J'
		if ROTATE then w,h,p,IJ,IJC=h,w,function(x,y) return thomson.point(y,x) end,'J,I','J,I+C' end
		
		if not ROTATE then
			local asm = {
				'9EE0                      ORG    $A000-(fin-debut) ',
				'                                                   ',
				'9EE0                  debut                        ',
				'                                                   ',
				'9EE0                  multiple                     ',
				'9EE0  3432                PSHS    A,X,Y            ',
				'                                                   ',
				'9EE2  A6A4                LDA     ,Y               ',
				'9EE4  A686                LDA     A,X              ',
				'                                                   ',
				'9EE6  43                  COMA                     ',
				'9EE7  A789FF78            STA    mult1-BASE64,X    ',
				'9EEB  40                  NEGA                     ',
				'9EEC  A789FF7D            STA    mult2-BASE64,X    ',
				'                                                   ',
				'9EF0  1F98                TFR     B,A              ',
				'9EF2  8B02                ADDA    #2               ',
				'                                                   ',
				'9EF4  3730                PULU    X,Y              ',
				'                                                   ',
				'9EF6                  mult_loop                    ',
				'9EF6  30887B              LEAX    123,X            ',
				'9EF8                  mult1 SET *-1                ',
				'9EF9  8D77                BSR     POINT            ',
				'9EFB  30887B              LEAX    123,X            ',
				'9EFD                  mult2 SET *-1                ',
				'9EFE  8D77                BSR     PSET             ',
				'9F00  3001                LEAX    1,X              ',
				'9F02  4A                  DECA                     ',
				'9F03  26F1                BNE     mult_loop        ',
				'                                                   ',
				'9F05  3630                PSHU    X,Y              ',
				'                                                   ',
				'9F07  3532                PULS    A,X,Y            ',
				'9F09  3121                LEAY    1,Y              ',
				'9F0B  8002                SUBA    #2               ',
				'9F0D  2615                BNE     decode           ',
				'9F0F  202C                BRA     exit             ',
				'                                                   ',
				'9F11                  entry                        ',
				'9F11  CE0000              LDU     #$0              ',
				'9F14  3410                PSHS    X                ',
				'9F16  10AE01              LDY     1,X              ',
				'9F19  A684                LDA     ,X               ',
				'9F1B  2720                BEQ     exit             ',
				'9F1D  308C60              LEAX    BASE64,PCR       ',
				'9F20  E684                LDB     ,X               ',
				'9F22  2622                BNE     init             ',
				'                                                   ',
				'9F24                  decode                       ',
				'9F24  E6A0                LDB     ,Y+              ',
				'9F26  E685                LDB     B,X              ',
				'9F28  C520                BITB    #32              ',
				'9F2A  27B4                BEQ     multiple         ',
				'9F2C                  single                       ',
				'9F2C  C030                SUBB    #48              ',
				'9F2E  3430                PSHS    X,Y              ',
				'9F30  3730                PULU    X,Y              ',
				'9F32  8D43                BSR     PSET             ',
				'9F34  3001                LEAX    1,X              ',
				'9F36  3630                PSHU    X,Y              ',
				'9F38  3530                PULS    X,Y              ',
				'9F3A  4A                  DECA                     ',
				'9F3B  26E7                BNE     decode           ',
				'                                                   ',
				'9F3D                  exit                         ',
				'9F3D  8602                LDA     #2               ',
				'9F3F  EEC4                LDU     ,U               ',
				'9F41  3510                PULS    X                ',
				'9F43  EF02                STU     2,X ; FACMO/LO   ',
				'9F45  39                  RTS                      ',
				'                                                   ',
				'9F46                  init                         ',
				'9F46  C67F                LDB     #127             ',
				'9F48                  init1                        ',
				'9F48  6F85                CLR     B,X              ',
				'9F4A  5A                  DECB                     ',
				'9F4B  2AFB                BPL     init1            ',
				'9F4D                  init2                        ',
				'9F4D  4A                  DECA                     ',
				'9F4E  2B06                BMI     init3            ',
				'9F50  E6A6                LDB     A,Y              ',
				'9F52  A785                STA     B,X              ',
				'9F54  20F7                BRA     init2            ',
				'9F56                  init3                        ',
				'9F56  1FB8                TFR     DP,A             ',
				'9F58  8440                ANDA    #$40             ',
				'9F5A  27E1                BEQ     exit             ',
									'* setup TO                     ',
				'9F5C  8681                LDA     #$81 ; CMPA#     ',
				'9F5E  A71B                STA     PLOT-BASE64,X    ',
				'9F60  A712                STA     POINT-BASE64,X   ',
				'9F62  CCFE93              LDD     #$6038-$61A1-4   ',
				'9F65  ED19                STD     PLOT-2-BASE64,X  ',
				'                                                   ',
				'9F67  C6A1                LDB     #$A1             ',
				'9F69  1FB8                TFR     DP,A             ',
				'9F6B  1F03                TFR     D,U              ',
				'9F6D  EF8892              STU     entry+1-BASE64,X ',
				'                                                   ',
				'9F70  20CB                BRA     exit             ',
				'                                                   ',
				'9F72                  POINT                        ',
				'9F72  3F                  SWI                      ',
				'9F73  94                  FCB     $94              ',
				'9F74  7EE821              JMP     $E821            ',
				'                                                   ',
				'9F77                  PSET                         ',
				'9F77  E7C9FE84            STB     $2029-$21A1-4,U  ',
				'9F7B                  PLOT                         ',
				'9F7B  3F                  SWI                      ',
				'9F7C  90                  FCB     $90              ',
				'9F7D  7EE80F              JMP     $E80F            ',
				'                                                   ',
				'9F80                  BASE64                       ',
				'9F80  FF                  FCB     -1               ',
				'9F81                      RMB     127              ',
				'                                                   ',
				'A000                  fin                          ',
				'                                                   ',
				'A000                      END init                 '
			}                           
			local hex,start,stop,entry,debut=''
			for _,l in ipairs(asm) do                        
				local a,h = l:match('(%x%x%x%x)  (%x+)%s+')
				if h then
					hex = hex..h
					start = start or a
					stop = a
				else
					local e = l:match('(%x%x%x%x)%s+entry ')
					if e then entry = e end
				end
			end
			start = ((tonumber(start,16)+32768)%65536)-32768
			stop  = ((tonumber(stop,16)+32768)%65536)-32768
			local NOASM = lineno + 90
			pr("IFFRE(0)<32000THEN"..NOASM) 
			pr("CLEAR,"..(start-1)..":RESTORE"..lineno..':FORI='..start..'TO'..stop..':READB$:POKEI,VAL("&H"+B$):NEXT:DEFUSR=&H'..entry)
			for i=1,hex:len(),2 do
				local t = ','..hex:sub(i,i+1)
				if data:len()+t:len()>=maxlen then
					pr("DATA " .. data:sub(2))
					data = t
				 else
					data = data..t
				 end
			end
			pr("DATA " .. data:sub(2))

			if not thomson.isDefaultPalette() then
				local t = ''
				for i=0,15 do t = t..','..thomson.palette(i) end
				pr('FORI=0TO15:READJ:PALETTEI,J:NEXT:DATA' .. t:sub(2))
			end			
			
			pr('RESTORE'..lineno..':READA$:I=USR(A$):I=0:J=0')
			pr('PSET(I,J),POINT(I,J):READA$:I=USR(A$):IFI<'..w..'THEN'..lineno..'ELSEI=0:J=J+1:IFJ<'..h..'THEN'..lineno)
			pr("GOTO"..(NOASM+60))
			lineno = NOASM
		end
	   		
		pr('RESTORE'..lineno..':READA$:DIMT(122):FORI=1TOLEN(A$):T(ASC(MID$(A$,I,1)))=I-1:NEXT:I=0:J=0')
		pr('DATA ' .. BASE64)

		local loopback = 'IFA<L THEN'..(lineno+10)..'ELSEIFI<'..w..'THEN'..lineno ..'ELSEI=0:J=J+1:IFJ<'..h..'THEN'..lineno
		pr('READA$:L=LEN(A$):A=0')
        pr('A=A+1:B=T(ASC(MID$(A$,A,1))):IFB>31THENPSET('..IJ..'),B-48:I=I+1:' .. loopback .. 'ELSE'..(lineno+20))
		pr('A=A+1:C=NOTT(ASC(MID$(A$,A,1))):FORI=I TO1+I+B:PSET('..IJ..'),POINT('..IJC..'):NEXT:'..loopback)
		-- pr('IF INKEY$="" THEN '..lineno..' ELSE RUN ""')
		pr('GOTO'..lineno)

		data=''
        for j=0,h-1 do
			local px={}; for i=0,w-1 do px[i] = p(i,j) end
			local i=0
			while i<w do
			    local best,code = 1,px[i]+48
				for o=1,math.min(i,64) do
					local k=0
					while px[i+k]==px[i-o+k] and k<33 do k=k+1 end
					if k>best then best,code = k,(o-1)*64+k-2 end
				end
				local x,c = (code%64),math.floor(code/64)
                local t = BASE64:sub(1+x,1+x)..(x<32 and BASE64:sub(1+c,1+c) or '')
				if data:len()+t:len()>=maxlen then
                    pr("DATA " .. data)
                    data = t
                else
                    data = data..t
                end
				i=i+best
			end
			if j~=h-1 and data:len()+2<maxlen then
				data=data..','
			else
                pr("DATA " .. data)
                data = ''
			end
        end
		-- if data~='' then pr("DATA " .. data) end
		out:write("\r\nRUN")
        out:close()
    end

    local function saveb_old9(name, thomson)
		local BASE64 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' ..
		               'abcdefghijklmnopqrstuvwxyz' ..
					   '0123456789' ..
					   '+/'

        local out = io.open(name,"wb")
        local lineno = 30000
        local function pr(txt)
            out:write(lineno .. " " .. txt .. "\r\n")
            lineno = lineno+10
        end
		local ROTATE = false
		
		pr("CLEAR300:DEFINTA-W")
        pr("LOCATE0,0,0:COLOR0,0:SCREEN,,0:CLS:COLOR7")
        if thomson.w==160 then pr("IFPEEK(&HFFF0)=2THEN?CHR$(27);CHR$(&H5E);:SCREEN,,0ELSECONSOLE,,,,3") end

		-- thomson.h=2
		local data,maxlen='',256-12
		local w,h,p,IJ,IJC = thomson.w,thomson.h,thomson.point,'I,J','I-C,J'
		if ROTATE then w,h,p,IJ,IJC=h,w,function(x,y) return thomson.point(y,x) end,'J,I','J,I-C' end
		
		if not ROTATE then
			local asm = {
				'9EE0                      ORG    $A000-(fin-debut) ',
				'                                                   ',
				'9EE0                  debut                        ',
				'                                                   ',
				'9EE0                  multiple                     ',
				'9EE0  3432                PSHS    A,X,Y            ',
				'                                                   ',
				'9EE2  A6A4                LDA     ,Y               ',
				'9EE4  A686                LDA     A,X              ',
				'                                                   ',
				'9EE6  43                  COMA                     ',
				'9EE7  A789FF78            STA    mult1-BASE64,X    ',
				'9EEB  40                  NEGA                     ',
				'9EEC  A789FF7D            STA    mult2-BASE64,X    ',
				'                                                   ',
				'9EF0  1F98                TFR     B,A              ',
				'9EF2  8B02                ADDA    #2               ',
				'                                                   ',
				'9EF4  3730                PULU    X,Y              ',
				'                                                   ',
				'9EF6                  mult_loop                    ',
				'9EF6  30887B              LEAX    123,X            ',
				'9EF8                  mult1 SET *-1                ',
				'9EF9  8D77                BSR     POINT            ',
				'9EFB  30887B              LEAX    123,X            ',
				'9EFD                  mult2 SET *-1                ',
				'9EFE  8D77                BSR     PSET             ',
				'9F00  3001                LEAX    1,X              ',
				'9F02  4A                  DECA                     ',
				'9F03  26F1                BNE     mult_loop        ',
				'                                                   ',
				'9F05  3630                PSHU    X,Y              ',
				'                                                   ',
				'9F07  3532                PULS    A,X,Y            ',
				'9F09  3121                LEAY    1,Y              ',
				'9F0B  8002                SUBA    #2               ',
				'9F0D  2615                BNE     decode           ',
				'9F0F  202C                BRA     exit             ',
				'                                                   ',
				'9F11                  entry                        ',
				'9F11  CE0000              LDU     #$0              ',
				'9F14  3410                PSHS    X                ',
				'9F16  10AE01              LDY     1,X              ',
				'9F19  A684                LDA     ,X               ',
				'9F1B  2720                BEQ     exit             ',
				'9F1D  308C60              LEAX    BASE64,PCR       ',
				'9F20  E684                LDB     ,X               ',
				'9F22  2622                BNE     init             ',
				'                                                   ',
				'9F24                  decode                       ',
				'9F24  E6A0                LDB     ,Y+              ',
				'9F26  E685                LDB     B,X              ',
				'9F28  C520                BITB    #32              ',
				'9F2A  27B4                BEQ     multiple         ',
				'9F2C                  single                       ',
				'9F2C  C030                SUBB    #48              ',
				'9F2E  3430                PSHS    X,Y              ',
				'9F30  3730                PULU    X,Y              ',
				'9F32  8D43                BSR     PSET             ',
				'9F34  3001                LEAX    1,X              ',
				'9F36  3630                PSHU    X,Y              ',
				'9F38  3530                PULS    X,Y              ',
				'9F3A  4A                  DECA                     ',
				'9F3B  26E7                BNE     decode           ',
				'                                                   ',
				'9F3D                  exit                         ',
				'9F3D  8602                LDA     #2               ',
				'9F3F  EEC4                LDU     ,U               ',
				'9F41  3510                PULS    X                ',
				'9F43  EF02                STU     2,X ; FACMO/LO   ',
				'9F45  39                  RTS                      ',
				'                                                   ',
				'9F46                  init                         ',
				'9F46  C67F                LDB     #127             ',
				'9F48                  init1                        ',
				'9F48  6F85                CLR     B,X              ',
				'9F4A  5A                  DECB                     ',
				'9F4B  2AFB                BPL     init1            ',
				'9F4D                  init2                        ',
				'9F4D  4A                  DECA                     ',
				'9F4E  2B06                BMI     init3            ',
				'9F50  E6A6                LDB     A,Y              ',
				'9F52  A785                STA     B,X              ',
				'9F54  20F7                BRA     init2            ',
				'9F56                  init3                        ',
				'9F56  1FB8                TFR     DP,A             ',
				'9F58  8440                ANDA    #$40             ',
				'9F5A  27E1                BEQ     exit             ',
									'* setup TO                     ',
				'9F5C  8681                LDA     #$81 ; CMPA#     ',
				'9F5E  A71B                STA     PLOT-BASE64,X    ',
				'9F60  A712                STA     POINT-BASE64,X   ',
				'9F62  CCFE93              LDD     #$6038-$61A1-4   ',
				'9F65  ED19                STD     PLOT-2-BASE64,X  ',
				'                                                   ',
				'9F67  C6A1                LDB     #$A1             ',
				'9F69  1FB8                TFR     DP,A             ',
				'9F6B  1F03                TFR     D,U              ',
				'9F6D  EF8892              STU     entry+1-BASE64,X ',
				'                                                   ',
				'9F70  20CB                BRA     exit             ',
				'                                                   ',
				'9F72                  POINT                        ',
				'9F72  3F                  SWI                      ',
				'9F73  94                  FCB     $94              ',
				'9F74  7EE821              JMP     $E821            ',
				'                                                   ',
				'9F77                  PSET                         ',
				'9F77  E7C9FE84            STB     $2029-$21A1-4,U  ',
				'9F7B                  PLOT                         ',
				'9F7B  3F                  SWI                      ',
				'9F7C  90                  FCB     $90              ',
				'9F7D  7EE80F              JMP     $E80F            ',
				'                                                   ',
				'9F80                  BASE64                       ',
				'9F80  FF                  FCB     -1               ',
				'9F81                      RMB     127              ',
				'                                                   ',
				'A000                  fin                          ',
				'                                                   ',
				'A000                      END init                 '
			}                           
			local hex,start,stop,entry,debut=''
			for _,l in ipairs(asm) do                        
				local a,h = l:match('(%x%x%x%x)  (%x+)%s+')
				if h then
					hex = hex..h
					start = start or a
					stop = a
				else
					local e = l:match('(%x%x%x%x)%s+entry ')
					if e then entry = e end
				end
			end
			start = ((tonumber(start,16)+32768)%65536)-32768
			stop  = ((tonumber(stop,16)+32768)%65536)-32768
			local NOASM = lineno + 90
			-- pr("IFFRE(0)<32000THEN"..NOASM) 
			pr('GOTO'..NOASM)
			pr("CLEAR,"..(start-1)..":RESTORE"..lineno..':FORI='..start..'TO'..stop..':READB$:POKEI,VAL("&H"+B$):NEXT:DEFUSR=&H'..entry)
			for i=1,hex:len(),2 do
				local t = ','..hex:sub(i,i+1)
				if data:len()+t:len()>=maxlen then
					pr("DATA " .. data:sub(2))
					data = t
				 else
					data = data..t
				 end
			end
			pr("DATA " .. data:sub(2))

			if not thomson.isDefaultPalette() then
				local t = ''
				for i=0,15 do t = t..','..thomson.palette(i) end
				pr('FORI=0TO15:READJ:PALETTEI,J:NEXT:DATA' .. t:sub(2))
			end			
			
			pr('RESTORE'..lineno..':READA$:I=USR(A$):I=0:J=0')
			pr('PSET(I,J),POINT(I,J):READA$:I=USR(A$):IFI<'..w..'THEN'..lineno..'ELSEI=0:J=J+1:IFJ<'..h..'THEN'..lineno)
			pr("GOTO"..(NOASM+60))
			lineno = NOASM
		end
	   		
		pr('RESTORE'..lineno..':READA$:DIMT(122):FORI=1TOLEN(A$):T(ASC(MID$(A$,I,1)))=I-1:NEXT:I=0:J=0')
		pr('DATA ' .. BASE64)

		local loopback = 'IFA<L THEN'..(lineno+10)..'ELSEIFI<'..w..'THEN'..lineno ..'ELSEI=0:J=J+1:IFJ<'..h..'THEN'..lineno
		pr('READA$:L=LEN(A$):A=0')
        pr('A=A+1:B=T(ASC(MID$(A$,A,1))):IFB>31THENPSET('..IJ..'),B-48:I=I+1ELSEC=(3ANDB)+1:FORI=I TO1+I+(B@4):PSET('..IJ..'),POINT('..IJC..'):NEXT')
		pr(loopback)

		-- pr('IF INKEY$="" THEN '..lineno..' ELSE RUN ""')
		pr('GOTO'..lineno)

		data=''
        for j=0,h-1 do
			local px={}; for i=0,w-1 do px[i] = p(i,j) end
			local i=0
			while i<w do
			    local best,code = 1,px[i]+48
				for o=1,math.min(i,4) do
					local k=0
					while px[i+k]==px[i-o+k] and k<9 do k=k+1 end
					if k>best then best,code = k,(k-2)*4+(o-1) end
				end
			
                local t = BASE64:sub(1+code,1+code)
				if data:len()+t:len()>=maxlen then
                    pr("DATA " .. data)
                    data = t
                else
                    data = data..t
                end
				i=i+best
			end
			if j~=h-1 and data:len()+2<maxlen then
				data=data..','
			else
                pr("DATA " .. data)
                data = ''
			end
        end
		-- if data~='' then pr("DATA " .. data) end
		out:write("\r\nRUN")
        out:close()
    end
	
    local function saveb_old10(name, thomson)
		local BASE88 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' .. -- 26
		               'abcdefghijklmnopqrstuvwxyz' .. -- 26
					   '_`~.-+=*<>[](){}$%#?&@;!|/' .. -- 26 
					   "0123456789" -- 10
		-- 0..55 = 6*8+7 
		-- 56..87
		
        local out = io.open(name,"wb")
        local lineno = 30000
        local function pr(txt)
            out:write(lineno .. " " .. txt .. "\r\n")
            lineno = lineno+10
        end
		local ROTATE = false
		
		pr("CLEAR300:DEFINTA-Z:LOCATE0,0,0:COLOR0,0:SCREEN,,0:CLS:COLOR7")
        if thomson.w==160 then pr("IFPEEK(&HFFF0)=2THEN?CHR$(27);CHR$(&H5E);:SCREEN,,0ELSECONSOLE,,,,3") end

		-- thomson.h=2
		local data,maxlen='',256-12
		local w,h,p,IJ,IJC = thomson.w,thomson.h,thomson.point,'I,J','I-C,J'
		if ROTATE then w,h,p,IJ,IJC=h,w,function(x,y) return thomson.point(y,x) end,'J,I','J,I-C' end
		
		if not ROTATE then
			local asm = {
				'9EEF                      ORG    $A000-(fin-debut) ',
				'                                                   ',
				'9EEF                  debut                        ',
				'                                                   ',
				'9EEF                  init                         ',
				'9EEF  C67F                LDB     #127             ',
				'9EF1                  init1                        ',
				'9EF1  6F85                CLR     B,X              ',
				'9EF3  5A                  DECB                     ',
				'9EF4  2AFB                BPL     init1            ',
				'9EF6                  init2                        ',
				'9EF6  4A                  DECA                     ',
				'9EF7  2B06                BMI     init3            ',
				'9EF9  E6A6                LDB     A,Y              ',
				'9EFB  A785                STA     B,X              ',
				'9EFD  20F7                BRA     init2            ',
				'9EFF                  init3                        ',
				'9EFF  1FB8                TFR     DP,A             ',
				'9F01  8440                ANDA    #$40             ',
				'9F03  2764                BEQ     exit             ',
									'* setup TO                     ',
				'9F05  8681                LDA     #$81 ; CMPA#     ',
				'9F07  A71B                STA     PLOT-TABLE,X     ',
				'9F09  A712                STA     POINT-TABLE,X    ',
				'9F0B  CCFE93              LDD     #$6038-$61A1-4   ',
				'9F0E  ED19                STD     PLOT-2-TABLE,X   ',
				'                                                   ',
				'9F10  C6A1                LDB     #$A1             ',
				'9F12  1FB8                TFR     DP,A             ',
				'9F14  1F03                TFR     D,U              ',
				'9F16  EF88BE              STU     entry+1-TABLE,X  ',
				'                                                   ',
				'9F19  204E                BRA     exit             ',
				'                                                   ',
				'9F1B                  multiple                     ',
				'9F1B  1F98                TFR     B,A              ',
				'9F1D  44                  LSRA                     ',
				'9F1E  44                  LSRA                     ',
				'9F1F  44                  LSRA                     ',
				'9F20  8B02                ADDA    #2               ',
				'                                                   ',
				'9F22  C407                ANDB    #7               ',
				'9F24  5C                  INCB                     ',
				'9F25  E78C0B              STB    mult2,PCR         ',
				'9F28  50                  NEGB                     ',
				'9F29  C41F                ANDB   #$1F              ',
				'9F2B  E78C01              STB    mult1,PCR         ',
				'                                                   ',
				'9F2E                  mult_loop                    ',
				'9F2E  3018                LEAX    -8,X             ',
				'9F2F                  mult1 SET *-1                ',
				'9F30  8D40                BSR     POINT            ',
				'9F32  3008                LEAX    8,X              ',
				'9F33                  mult2 SET *-1                ',
				'9F34  8D41                BSR     PSET             ',
				'9F36  3001                LEAX    1,X              ',
				'9F38  4A                  DECA                     ',
				'9F39  26F3                BNE     mult_loop        ',
				'                                                   ',
				'9F3B  2025                BRA     decode2          ',
				'                                                   ',
				'9F3D                  entry                        ',
				'9F3D  CE0000              LDU     #$0              ',
				'9F40  3410                PSHS    X                ',
				'9F42  10AE01              LDY     1,X              ',
				'9F45  A684                LDA     ,X               ',
				'9F47  2720                BEQ     exit             ',
				'9F49  308C34              LEAX    TABLE,PCR        ',
				'9F4C  E684                LDB     ,X               ',
				'9F4E  269F                BNE     init             ',
				'                                                   ',
				'9F50                  decode                       ',
				'9F50  E6A0                LDB     ,Y+              ',
				'9F52  E685                LDB     B,X              ',
				'9F54  3432                PSHS    A,X,Y            ',
				'9F56  3730                PULU    X,Y              ',
				'9F58  C137                CMPB    #55              ',
				'9F5A  2FBF                BLE     multiple         ',
				'9F5C                  single                       ',
				'9F5C  C048                SUBB    #72              ',
				'9F5E  8D17                BSR     PSET             ',
				'9F60  3001                LEAX    1,X              ',
				'9F62                  decode2                      ',
				'9F62  3630                PSHU    X,Y              ',
				'9F64  3532                PULS    A,X,Y            ',
				'9F66  4A                  DECA                     ',
				'9F67  26E7                BNE     decode           ',
				'                                                   ',
				'9F69                  exit                         ',
				'9F69  8602                LDA     #2               ',
				'9F6B  EEC4                LDU     ,U               ',
				'9F6D  3510                PULS    X                ',
				'9F6F  EF02                STU     2,X ; FACMO/LO   ',
				'9F71  39                  RTS                      ',
				'                                                   ',
				'9F72                  POINT                        ',
				'9F72  3F                  SWI                      ',
				'9F73  94                  FCB     $94              ',
				'9F74  7EE821              JMP     $E821            ',
				'                                                   ',
				'9F77                  PSET                         ',
				'9F77  E7C9FE84            STB     $2029-$21A1-4,U  ',
				'9F7B                  PLOT                         ',
				'9F7B  3F                  SWI                      ',
				'9F7C  90                  FCB     $90              ',
				'9F7D  7EE80F              JMP     $E80F            ',
				'                                                   ',
				'9F80                  TABLE                        ',
				'9F80  FF                  FCB     -1               ',
				'9F81                      RMB     127              ',
				'                                                   ',
				'A000                  fin                          ',
				'                                                   ',
				'A000                      END init                 '
			}                           
			local hex,start,stop,entry,debut=''
			for _,l in ipairs(asm) do                        
				local a,h = l:match('(%x%x%x%x)  (%x+)%s+')
				if h then
					hex = hex..h
					start = start or a
					stop = a
				else
					local e = l:match('(%x%x%x%x)%s+entry ')
					if e then entry = e end
				end
			end
			start = ((tonumber(start,16)+32768)%65536)-32768
			stop  = ((tonumber(stop,16)+32768)%65536)-32768
			local NOASM = lineno + 90
			pr("IFFRE(0)<32000THEN"..NOASM) 
			-- pr('GOTO'..NOASM)
			pr("CLEAR,"..(start-1)..":RESTORE"..lineno..':FORI='..start..'TO'..stop..':READB$:POKEI,VAL("&H"+B$):NEXT:DEFUSR=&H'..entry)
			for i=1,hex:len(),2 do
				local t = ','..hex:sub(i,i+1)
				if data:len()+t:len()>=maxlen then
					pr("DATA " .. data:sub(2))
					data = t
				 else
					data = data..t
				 end
			end
			pr("DATA " .. data:sub(2))

			if not thomson.isDefaultPalette() then
				local t = ''
				for i=0,15 do t = t..','..thomson.palette(i) end
				pr('FORI=0TO15:READJ:PALETTEI,J:NEXT:DATA' .. t:sub(2))
			end			
			
			pr('RESTORE'..lineno..':READA$:I=USR(A$):I=0:J=0')
			pr('PSET(I,J),POINT(I,J):READA$:I=USR(A$):IFI<'..w..'THEN'..lineno..'ELSEI=0:J=J+1:IFJ<'..h..'THEN'..lineno)
			pr("GOTO"..(NOASM+50))
			lineno = NOASM
		end
	   		
		pr('RESTORE'..lineno..':READA$:DIMT(126):FORI=1TOLEN(A$):T(ASC(MID$(A$,I,1)))=I-1:NEXT:I=0:J=0')
		pr('DATA ' .. BASE88)

		local loopback = 'IFA<L THEN'..(lineno+10)..'ELSEIFI<'..w..'THEN'..lineno ..'ELSEI=0:J=J+1:IFJ<'..h..'THEN'..lineno
		pr('READA$:L=LEN(A$):A=0')
        pr('A=A+1:B=T(ASC(MID$(A$,A,1))):IFB>55THENPSET('..IJ..'),B-72:I=I+1ELSEC=(7ANDB)+1:FORI=I TO1+I+(B@8):PSET('..IJ..'),POINT('..IJC..'):NEXT')
		pr(loopback)

		-- pr('IF INKEY$="" THEN '..lineno..' ELSE RUN ""')
		pr('GOTO'..lineno)

		data=''
        for j=0,h-1 do
			local px={}; for i=0,w-1 do px[i] = p(i,j) end
			local i=0
			while i<w do
			    local best,code = 1,px[i]+72
				for o=1,math.min(i,8) do
					local k=0
					while px[i+k]==px[i-o+k] and k<8 do k=k+1 end
					if k>best then best,code = k,(k-2)*8+(o-1) end
				end
			
                local t = BASE88:sub(1+code,1+code)
				if data:len()+t:len()>=maxlen then
                    pr("DATA " .. data)
                    data = t
                else
                    data = data..t
                end
				i=i+best
			end
			if j~=h-1 and data:len()+2<maxlen then
				data=data..','
			else
                pr("DATA " .. data)
                data = ''
			end
        end
		-- if data~='' then pr("DATA " .. data) end
		out:write("\r\nRUN")
        out:close()
    end

    local function saveb_old11(name, thomson)
		local BASE88 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' .. -- 26
		               'abcdefghijklmnopqrstuvwxyz' .. -- 26
					   '_`~.-+=*<>[](){}$%#?&@;!|/' .. -- 26 
					   "0123456789" -- 10
		-- 0..55 = 6*8+7 (2+6) repeat (7+1) offset
		-- 56..87 -> 
		
        local out = io.open(name,"wb")
        local lineno = 10
        local function pr(txt)
            out:write(lineno .. " " .. txt .. "\r\n")
            lineno = lineno+10
        end
		local ROTATE = false
		out:write("NEW\r\n\r\n")
		
		pr("DEFINTA-Z:LOCATE0,0,0:COLOR0,0:SCREEN,,0:CLS:COLOR7")
		-- thomson.h=2
		local data,maxlen='',256-8-2
		local w,h,p,IJ,IJC = thomson.w,thomson.h,thomson.point,'I,J','I-C,J'
		if ROTATE then w,h,p,IJ,IJC=h,w,function(x,y) return thomson.point(y,x) end,'J,I','J,I-C' end
		
		local asm = ROTATE and {
			'0000                      ORG   $0000             ',
			'0000                      SETDP $FF               ',
			'                                                  ',
			'5555                  UNDEF  SET $5555            ',
			'0001                  ROTATE SET 1                ',
			'                                                  ',
			'0000                  init                        ',
			'					  * Fix STRING zone            ',
			'0000  AFA8C7              STX   STRINGZONE-TABLE,Y',
			'0003  270B                BEQ   init1             ',
			'0005  3402                PSHS  A                 ',
			'0007  DC22                LDD   <$22              ',
			'0009  EDA8C7              STD   STRINGZONE-TABLE,Y',
			'000C  33CB                LEAU  D,U               ',
			'000E  3502                PULS  A                 ',
			'0010                  init1                       ',
			'                                                  ',
			'					  * clear table                ',
			'0010  C67F                LDB   #127              ',
			'0012                  init2                       ',
			'0012  6FA5                CLR   B,Y               ',
			'0014  5A                  DECB                    ',
			'0015  C11F                CMPB  #31               ',
			'0017  26F9                BNE   init2             ',
			'                                                  ',
			'					  * setup decode               ',
			'0019  33C6                LEAU  A,U               ',
			'001B                  init3                       ',
			'001B  E6C2                LDB   ,-U               ',
			'001D  4A                  DECA                    ',
			'001E  A7A5                STA   B,Y               ',
			'0020  26F9                BNE   init3             ',
			'                                                  ',
			'					  * fix LINE ptr               ',
			'0022  30A90080            LEAX  LINE-TABLE,Y      ',
			'0026  AFA8EE              STX   PSET_LINE-TABLE,Y ',
			'                                                  ',
			'0029  1FB8                TFR   DP,A              ',
			'002B  8440                ANDA  #$40              ',
			'002D  273C                BEQ   exit              ',
			'					  *  fix PLOT for TO           ',
			'002F  8681                LDA   #$81 ; CMPA#      ',
			'0031  A73A                STA   PLOT-TABLE,Y      ',
			'					  * fix COLOUR for TO          ',
			'0033  8E6038              LDX   #$6038            ',
			'0036  AF31                STX   PSET_COLOR-TABLE,Y',
			'0038  2031                BRA   exit              ',
			'                                                  ',
			'						  IF    (*&1)-1            ',
			'003A  00                  FCB   0 ; align STR_PTR ',
			'						  ENDIF                    ',
			'                                                  ',
			'003B                  entry                       ',
			'003B  CE0000              LDU   #$0               ',
			'003C                  S_PTR SET *-2               ',
			'003E  318C42              LEAY  TABLE,PCR         ',
			'0041  AEB8E9              LDX   [I_PTR-TABLE,Y]   ',
			'                                                  ',
			'0044  A6C4                LDA   ,U                ',
			'0046  EE41                LDU   1,U               ',
			'0048  33C90000            LEAU  >0,U              ',
			'004A                  STRINGZONE SET *-2          ',
			'                                                  ',
			'004C  E6A820              LDB   32,Y              ',
			'004F  26AF                BNE   init              ',
			'                                                  ',
			'						  IF    (*&1)              ',
			'0051  12                  NOP ; align J_PTR       ',
			'						  ENDIF                    ',
			'                                                  ',
			'0052                  decode                      ',
			'0052  E6C0                LDB   ,U+               ',
			'0054  E6A5                LDB   B,Y               ',
			'0056  3422                PSHS  A,Y               ',
			'0058  10BE5555            LDY   UNDEF             ',
			'005A                  J_PTR SET   *-2             ',
			'005C  C137                CMPB  #55               ',
			'005E  2F22                BLE   multiple          ',
			'0060                  single                      ',
			'0060  C048                SUBB  #72               ',
			'0062  8D0B                BSR   PSET              ',
			'0064  3001                LEAX  1,X               ',
			'0066                  decode2                     ',
			'0066  3522                PULS  A,Y               ',
			'0068  4A                  DECA                    ',
			'0069  26E7                BNE   decode            ',
			'                                                  ',
			'						  IF    (*&1)-1            ',
			'						  NOP ; align I_PTR        ',
			'						  ENDIF                    ',
			'                                                  ',
			'006B                  exit                        ',
			'006B  BF5555              STX   UNDEF             ',
			'006C                  I_PTR SET *-2               ',
			'006E  39                  RTS                     ',
			'                                                  ',
			'006F                  PSET                        ',
			'006F  E7895555            STB   UNDEF,X           ',
			'0071                  PSET_LINE SET *-2           ',
			'0073  F72029              STB   $2029             ',
			'0074                  PSET_COLOR SET *-2          ',
			'						  IF    ROTATE             ',
			'0076  1E12                EXG   X,Y               ',
			'0078  8D03                BSR   PLOT              ',
			'007A  1E12                EXG   X,Y               ',
			'007C  39                  RTS                     ',
			'						  ENDIF                    ',
			'007D                  PLOT                        ',
			'007D  3F                  SWI                     ',
			'007E  90                  FCB   $90               ',
			'007F  7EE80F              JMP   $E80F             ',
			'                                                  ',
			'0082                  multiple                    ',
			'0082  3414                PSHS  B,X               ',
			'0084  C407                ANDB  #7                ',
			'0086  53                  COMB                    ',
			'0087  308C79              LEAX  LINE,PCR          ',
			'008A  3085                LEAX  B,X               ',
			'008C  AF8C09              STX   mult_BACK,PCR     ',
			'008F  3512                PULS  A,X               ',
			'0091  44                  LSRA                    ',
			'0092  44                  LSRA                    ',
			'0093  44                  LSRA                    ',
			'0094  8B02                ADDA  #2                ',
			'0096                  mult_loop                   ',
			'0096  E6895555            LDB   UNDEF,X           ',
			'0098                  mult_BACK SET *-2           ',
			'009A  8DD3                BSR   PSET              ',
			'009C  3001                LEAX  1,X               ',
			'009E  4A                  DECA                    ',
			'009F  26F5                BNE   mult_loop         ',
			'00A1  20C3                BRA   decode2           ',
			'                                                  ',
			'0083                  TABLE SET *-32              ',
			'00A3  FF                  FCB   $FF               ',
			'00A4                      RMB   127-32            ',
			'0103                  LINE                        ',
			'0103                      RMB   320               ',
			'                                                  ',
			'0243                  size SET  *                 ',
			'                                                  ',
			'0243                      END                     ',
		} or {
			'0000                      ORG   $0000             ',
			'0000                      SETDP $FF               ',
			'                                                  ',
			'5555                  UNDEF SET $5555             ',
			'                                                  ',
			'0000                  init                        ',
			'					* Fix STRING zone              ',
			'0000  AFA8CE              STX   STRINGZONE-TABLE,Y',
			'0003  270B                BEQ   init1             ',
			'0005  3402                PSHS  A                 ',
			'0007  DC22                LDD   <$22              ',
			'0009  EDA8CE              STD   STRINGZONE-TABLE,Y',
			'000C  33CB                LEAU  D,U               ',
			'000E  3502                PULS  A                 ',
			'0010                  init1                       ',
			'                                                  ',
			'					* clear table                  ',
			'0010  C67F                LDB   #127              ',
			'0012                  init2                       ',
			'0012  6FA5                CLR   B,Y               ',
			'0014  5A                  DECB                    ',
			'0015  C11F                CMPB  #31               ',
			'0017  26F9                BNE   init2             ',
			'                                                  ',
			'					* setup decode                 ',
			'0019  33C6                LEAU  A,U               ',
			'001B                  init3                       ',
			'001B  E6C2                LDB   ,-U               ',
			'001D  4A                  DECA                    ',
			'001E  A7A5                STA   B,Y               ',
			'0020  26F9                BNE   init3             ',
			'                                                  ',
			'					* fix LINE ptr                 ',
			'0022  30A90080            LEAX  LINE-TABLE,Y      ',
			'0026  AF35                STX   PSET_LINE-TABLE,Y ',
			'                                                  ',
			'0028  1FB8                TFR   DP,A              ',
			'002A  8440                ANDA  #$40              ',
			'002C  273B                BEQ   exit              ',
			'					*  fix PLOT for TO             ',
			'002E  8681                LDA   #$81 ; CMPA#      ',
			'0030  A73A                STA   PLOT-TABLE,Y      ',
			'					* fix COLOUR for TO            ',
			'0032  8E6038              LDX   #$6038            ',
			'0035  AF38                STX   PSET_COLOR-TABLE,Y',
			'0037  2030                BRA   exit              ',
			'                                                  ',
			'						IF    (*&1)-1              ',
			'						FCB   0 ; align STR_PTR    ',
			'						ENDIF                      ',
			'                                                  ',
			'0039                  entry                       ',
			'0039  CE0000              LDU   #$0               ',
			'003A                  S_PTR SET *-2               ',
			'003C  318C3B              LEAY  TABLE,PCR         ',
			'003F  AEB8F0              LDX   [I_PTR-TABLE,Y]   ',
			'                                                  ',
			'0042  A6C4                LDA   ,U                ',
			'0044  EE41                LDU   1,U               ',
			'0046  33C90000            LEAU  >0,U              ',
			'0048                  STRINGZONE SET *-2          ',
			'                                                  ',
			'004A  E6A820              LDB   32,Y              ',
			'004D  26B1                BNE   init              ',
			'                                                  ',
			'						IF    (*&1)                ',
			'004F  12                  NOP ; align J_PTR       ',
			'						ENDIF                      ',
			'                                                  ',
			'0050                  decode                      ',
			'0050  E6C0                LDB   ,U+               ',
			'0052  E6A5                LDB   B,Y               ',
			'0054  3422                PSHS  A,Y               ',
			'0056  10BE5555            LDY   UNDEF             ',
			'0058                  J_PTR SET   *-2             ',
			'005A  C137                CMPB  #55               ',
			'005C  2F1B                BLE   multiple          ',
			'005E                  single                      ',
			'005E  C048                SUBB  #72               ',
			'0060  8D0B                BSR   PSET              ',
			'0062  3001                LEAX  1,X               ',
			'0064                  decode2                     ',
			'0064  3522                PULS  A,Y               ',
			'0066  4A                  DECA                    ',
			'0067  26E7                BNE   decode            ',
			'                                                  ',
			'						IF    (*&1)-1              ',
			'						NOP ; align I_PTR          ',
			'						ENDIF                      ',
			'                                                  ',
			'0069                  exit                        ',
			'0069  BF5555              STX   UNDEF             ',
			'006A                  I_PTR SET *-2               ',
			'006C  39                  RTS                     ',
			'                                                  ',
			'006D                  PSET                        ',
			'006D  E7895555            STB   UNDEF,X           ',
			'006F                  PSET_LINE SET *-2           ',
			'0071  F72029              STB   $2029             ',
			'0072                  PSET_COLOR SET *-2          ',
			'0074                  PLOT                        ',
			'0074  3F                  SWI                     ',
			'0075  90                  FCB   $90               ',
			'0076  7EE80F              JMP   $E80F             ',
			'                                                  ',
			'0079                  multiple                    ',
			'0079  3414                PSHS  B,X               ',
			'007B  C407                ANDB  #7                ',
			'007D  53                  COMB                    ',
			'007E  308C79              LEAX  LINE,PCR          ',
			'0081  3085                LEAX  B,X               ',
			'0083  AF8C09              STX   mult_BACK,PCR     ',
			'0086  3512                PULS  A,X               ',
			'0088  44                  LSRA                    ',
			'0089  44                  LSRA                    ',
			'008A  44                  LSRA                    ',
			'008B  8B02                ADDA  #2                ',
			'008D                  mult_loop                   ',
			'008D  E6895555            LDB   UNDEF,X           ',
			'008F                  mult_BACK SET *-2           ',
			'0091  8DDA                BSR   PSET              ',
			'0093  3001                LEAX  1,X               ',
			'0095  4A                  DECA                    ',
			'0096  26F5                BNE   mult_loop         ',
			'0098  20CA                BRA   decode2           ',
			'                                                  ',
			'007A                  TABLE SET *-32              ',
			'009A  FF                  FCB   $FF               ',
			'009B                      RMB   127-32            ',
			'00FA                  LINE                        ',
			'00FA                      RMB   320               ',
			'                                                  ',
			'023A                  size SET  *                 ',
			'                                                  ',
			'023A                      END                     '
		}                           
		local hex,i_ptr,j_ptr,s_ptr,entry,last=''
		for _,l in ipairs(asm) do                        
			local a,h = l:match('(%x%x%x%x)  (%x+)%s+')
			if h then
				hex = hex..h
			else
				local e = l:match('(%x%x%x%x)%s+entry ')
				if e then entry = tonumber(e,16) end
				local e = l:match('(%x%x%x%x)%s+I_PTR ')
				if e then i_ptr = math.floor(tonumber(e,16)/2) end
				local e = l:match('(%x%x%x%x)%s+J_PTR ')
				if e then j_ptr = math.floor(tonumber(e,16)/2) end
				local e = l:match('(%x%x%x%x)%s+S_PTR ')
				if e then s_ptr = math.floor(tonumber(e,16)/2) end
				local e = l:match('(%x%x%x%x)%s+size ')
				if e then last  = math.floor(tonumber(e,16)/2+.5) end
			end
		end
		if hex:len()%4==2 then hex=hex.."00" end
		local size = math.floor(hex:len()/4)
	    pr('K!='..(last*2+184)..'-FRE(0):IFK!>0THEN?K!;"bytes missing.":END')
		pr('I=BANK>0:DIMA('..last..'):FORJ=0TO'..(size-1)..':READA$:K!=VAL("&H"+A$):IFK!>32767THENK=K!-65536ELSEK=K!')
		pr('A(J+I*(2*J-'..last..'))=K:NEXT')
		for i=1,hex:len(),4 do
			local t = ','..hex:sub(i,i+3)
			if data:len()+t:len()>=maxlen then
				pr("DATA" .. data:sub(2))
				data = t
			 else
				data = data..t
			 end
		end
		pr("DATA" .. data:sub(2))
		data=''
		local function asn(i,v)
			-- pr('K='..v..':IFI THENA('..(last-i)..')=K ELSEA('..i..')=K')
			-- pr("A("..last..'*-(i>0)+j*(1+2*(i>0))
			data=data.."A("..(2*i-last).."*I+"..i..")="..v..':'
		end
		asn(s_ptr,"VARPTR(A$)")	asn(j_ptr,"VARPTR(J)") asn(i_ptr,"VARPTR(I)")
		pr(data..'A$="'..BASE88..'":EXECVARPTR(A('..last..'ANDI))+'..entry)
		if not thomson.isDefaultPalette() then
			local t = ''
			for i=0,15 do t = t..','..thomson.palette(i) end
			pr('FORI=0TO15:READJ:PALETTEI,J:NEXT:DATA' .. t:sub(2))
		end			
		if thomson.w==160 then pr("IFPEEK(&HFFF0)=2THEN?CHR$(27);CHR$(&H5E);:SCREEN,,0ELSECONSOLE,,,,3") end
		pr('I=0:J=0')
		pr('READA$:EXEC:IFI<'..w..'THEN'..lineno..'ELSEI=0:J=J+1:IFJ<'..h..'THEN'..lineno)

		-- local loopback = 'IFA<L THEN'..(lineno+10)..'ELSEIFI<'..w..'THEN'..lineno ..'ELSEI=0:J=J+1:IFJ<'..h..'THEN'..lineno
		-- pr('READA$:L=LEN(A$):A=0')
        -- pr('A=A+1:B=T(ASC(MID$(A$,A,1))):IFB>55THENPSET('..IJ..'),B-72:I=I+1ELSEC=(7ANDB)+1:FORI=I TO1+I+(B@8):PSET('..IJ..'),POINT('..IJC..'):NEXT')
		-- pr(loopback)

		-- pr('IF INKEY$="" THEN '..lineno..' ELSE RUN ""')
		pr('GOTO'..lineno)

		data=''
        for j=0,h-1 do
			local px={}; for i=0,w-1 do px[i] = p(i,j) end
			local i=0
			while i<w do
			    local best,code = 1,px[i]+72
				for o=1,math.min(i,8) do
					local k=0
					while px[i+k]==px[i-o+k] and k<8 do k=k+1 end
					if k>best then best,code = k,(k-2)*8+(o-1) end
				end
			
                local t = BASE88:sub(1+code,1+code)
				if data:len()+t:len()>=maxlen then
                    pr("DATA" .. data)
                    data = t
                else
                    data = data..t
                end
				i=i+best
			end
			if j~=h-1 and data:len()+2<maxlen then
				data=data..','
			else
                pr("DATA" .. data)
                data = ''
			end
        end
		-- if data~='' then pr("DATA " .. data) end
		out:write("\r\nRUN")
        out:close()
    end
	
	local function saveb_old12(name, thomson)
		local BASE91 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' .. -- 26
		               'abcdefghijklmnopqrstuvwxyz' .. -- 26
					   '_`~.-+=*<>[](){}$%#?&@;!|/' .. -- 26 
					   '0123456789' .. -- 10
					   "^\\'" -- 3
		-- 0..55 = 6*8+7 (2+6) repeat (7+1) offset
		-- 56..87 -> 

		local ROTATE = false
	
        local out = io.open(name,"wb")
        local lineno = 10
        local function pr(txt)
            out:write(lineno .. " " .. txt .. "\r\n")
            lineno = lineno+10
        end
		out:write("NEW\r\n\r\n")
		
		local CONSOLE=''
		if thomson.mode~=0 then CONSOLE="CONSOLE,,,,"..thomson.mode..":" end
		pr("DEFINTA-Z:LOCATE0,0,0:COLOR0,0:"..CONSOLE.."SCREEN,,0:CLS:COLOR7")

		-- thomson.h=2
		local data,maxlen='',256-8-2
		local w,h,p,IJ,IJC = thomson.w,thomson.h,thomson.point,'I,J','I-C,J'
		if ROTATE then w,h,p,IJ,IJC=h,w,function(x,y) return thomson.point(y,x) end,'J,I','J,I-C' end
	
		local OFFSETS = {1,3,4}
		-- find best 2 offsets
		if true then
			local stat,stat2 = {},{}
			for j=0,h-1 do
				local px={}; for i=0,w-1 do px[i] = p(i,j) end
				local i=0
				while i<w do
					local best,offs=1

					for o=1,math.min(i,8) do
						local k=0
						while px[i+k]==px[i-o+k] and k<8 do k=k+1 end
						if k>best then best = k end
					end
					
					for o=1,math.min(i,128) do
						local k=0
						while px[i+k]==px[i-o+k] and k<107 do k=k+1 end
						if k>16 and k>best then best,offs = k,o end
					end 
					
					
					if offs then					
						local s = stat[offs]
						if not s then
							s = {o=offs, n=0, i=function(s) s.n=s.n+1 end}
							stat[offs] = s
							table.insert(stat2, s)
						end
						s:i()
					end
					i=i+best
				end
			end
			table.sort(stat2, function(s1,s2) return s1.n>s2.n end)
			local t=''
			for i,s in ipairs(stat2) do if OFFSETS[i] then OFFSETS[i] = s.o; t=t..' '..s.o..':'..s.n end end
			-- error(t)
		end
	
		local asm = ROTATE and {
			'0000                      ORG   $0000              ',
			'0000                      SETDP $FF                ',
			'                                                   ',
			'0001                  ROTATE SET 1                 ',
			'5555                  UNDEF  SET $5555             ',
			'                                                   ',
			'0000                  init                         ',
			'                      * Fix STRING zone            ',
			'0000  AFA8AF              STX   STRINGZONE-TABLE,Y ',
			'0003  270B                BEQ   init1              ',
			'0005  3402                PSHS  A                  ',
			'0007  DC22                LDD   <$22               ',
			'0009  EDA8AF              STD   STRINGZONE-TABLE,Y ',
			'000C  33CB                LEAU  D,U                ',
			'000E  3502                PULS  A                  ',
			'0010                  init1                        ',
			'                                                   ',
			'                      * clear table                ',
			'0010  C67F                LDB   #127               ',
			'0012                  init2                        ',
			'0012  6FA5                CLR   B,Y                ',
			'0014  5A                  DECB                     ',
			'0015  C11F                CMPB  #31                ',
			'0017  26F9                BNE   init2              ',
			'                                                   ',
			'                      * setup decode               ',
			'0019  33C6                LEAU  A,U                ',
			'001B                  init3                        ',
			'001B  E6C2                LDB   ,-U                ',
			'001D  4A                  DECA                     ',
			'001E  A7A5                STA   B,Y                ',
			'0020  26F9                BNE   init3              ',
			'                                                   ',
			'                      * fix LINE ptr               ',
			'0022  30A90080            LEAX  LINE-TABLE,Y       ',
			'0026  AF2C                STX   PSET_LINE-TABLE,Y  ',
			'                                                   ',
			'0028  1FB8                TFR   DP,A               ',
			'002A  8440                ANDA  #$40               ',
			'002C  274D                BEQ   exit               ',
			'                      *  fix PLOT for TO           ',
			'002E  8681                LDA   #$81 ; CMPA#       ',
			'0030  A7A818              STA   PLOT-TABLE,Y       ',
			'                      * fix COLOUR for TO          ',
			'0033  8E6038              LDX   #$6038             ',
			'0036  AF2F                STX   PSET_COLOR-TABLE,Y ',
			'0038  2041                BRA   exit               ',
			'                                                   ',
			'                          IF    (*&1)-1            ',
			'003A  12                  NOP ; align STR_PTR      ',
			'                          ENDIF                    ',
			'                                                   ',
			'003B                  entry                        ',
			'003B  CE0000              LDU   #$0                ',
			'003C                  S_PTR SET *-2                ',
			'003E  318C5C              LEAY  TABLE,PCR          ',
			'0041  AEB8DF              LDX   [I_PTR-TABLE,Y]    ',
			'                                                   ',
			'0044  A6C4                LDA   ,U                 ',
			'0046  A7E2                STA   ,-S                ',
			'0048  EE41                LDU   1,U                ',
			'004A  33C90000            LEAU  >0,U               ',
			'004C                  STRINGZONE SET *-2           ',
			'                                                   ',
			'004E  E6A820              LDB   32,Y               ',
			'0051  26AD                BNE   init               ',
			'                                                   ',
			'0053                  decode                       ',
			'0053  ECC0                LDD   ,U+                ',
			'0055  A6A6                LDA   A,Y                ',
			'                                                   ',
			'0057  813B                CMPA  #59                ',
			'0059  2C0F                BGE   single             ',
			'                                                   ',
			'005B  8138                CMPA  #56                ',
			'005D  2C21                BGE   special            ',
			'                                                   ',
			'005F  1F89                TFR   A,B                ',
			'0061  8407                ANDA  #7                 ',
			'0063  54                  LSRB                     ',
			'0064  54                  LSRB                     ',
			'0065  54                  LSRB                     ',
			'0066  CB02                ADDB  #2                 ',
			'0068  2021                BRA   multiple           ',
			'                                                   ',
			'                          IF    (*&1)              ',
			'                          NOP ; align J_PTR        ',
			'                          ENDIF                    ',
			'                                                   ',
			'006A                  single                       ',
			'006A  10BE5555            LDY   UNDEF              ',
			'006C                  J_PTR SET   *-2              ',
			'006E  804B                SUBA  #75                ',
			'0070  8D35                BSR   PSET               ',
			'0072  3001                LEAX  1,X                ',
			'                                                   ',
			'0074                  decode2                      ',
			'0074  318C26              LEAY  TABLE,PCR          ',
			'0077  6AE4                DEC   ,S                 ',
			'0079  26D8                BNE   decode             ',
			'                                                   ',
			'                          IF    (*&1)-1            ',
			'                          NOP ; align I_PTR        ',
			'                          ENDIF                    ',
			'                                                   ',
			'007B                  exit                         ',
			'007B  BF5555              STX   UNDEF              ',
			'007C                  I_PTR SET *-2                ',
			'007E  3582                PULS  A,PC               ',
			'                                                   ',
			'0080                  special                      ',
			'0080  6AE4                DEC   ,S                 ',
			'0082  3341                LEAU  1,U                ',
			'0084  E6A5                LDB   B,Y                ',
			'FFE5                  TMP set   offset-TABLE-56    ',
			'0086  C3E511              ADDD  #TMP*256+17        ',
			'0089  A6A6                LDA   A,Y                ',
			'                      *    BRA   multiple          ',
			'                                                   ',
			'008B                  multiple                     ',
			'008B  43                  COMA                     ',
			'008C  318D008D            LEAY  LINE,PCR           ',
			'0090  31A6                LEAY  A,Y                ',
			'0092  10AF8C06            STY   mult_BACK,PCR      ',
			'0096  10AE9CD2            LDY   [J_PTR,PCR]        ',
			'009A                  mult_loop                    ',
			'009A  A6895555            LDA   UNDEF,X            ',
			'009C                  mult_BACK SET *-2            ',
			'009E  8D07                BSR   PSET               ',
			'00A0  3001                LEAX  1,X                ',
			'00A2  5A                  DECB                     ',
			'00A3  26F5                BNE   mult_loop          ',
			'00A5  20CD                BRA   decode2            ',
			'                                                   ',
			'00A7                  PSET                         ',
			'00A7  A7895555            STA   UNDEF,X            ',
			'00A9                  PSET_LINE SET *-2            ',
			'00AB  B72029              STA    $2029             ',
			'00AC                  PSET_COLOR SET *-2           ',
			'                          IF    ROTATE             ',
			'00AE  1E12                EXG   X,Y                ',
			'00B0  8D03                BSR   PLOT               ',
			'00B2  1E12                EXG   X,Y                ',
			'00B4  39                  RTS                      ',
			'                          ENDIF                    ',
			'00B5                  PLOT                         ',
			'00B5  3F                  SWI                      ',
			'00B6  90                  FCB   $90                ',
			'00B7  7EE80F              JMP   $E80F              ',
			'                                                   ',
			'                          IF    (*&1)              ',
			'                          NOP ; align offset       ',
			'                          ENDIF                    ',
			'                                                   ',
			'00BA                  offset                       ',
			'00BA  000203              FCB   0,2,3              ',
			'                                                   ',
			'009D                  TABLE SET *-32               ',
			'00BD  FF                  FCB   $FF                ',
			'00BE                      RMB   127-32             ',
			'011D                  LINE                         ',
			'                          IF ROTATE                ',
			'011D                      RMB   200                ',
			'                          ELSE                     ',
			'                          RMB   320                ',
			'                          ENDIF                    ',
			'                                                   ',
			'01E5                  size SET  *                  ',
			'                                                   ',
			'01E5                      END                      '
		} or {        
			'0000                      ORG   $0000              ',
			'0000                      SETDP $FF                ',
			'                                                   ',
			'0000                  ROTATE SET 0                 ',
			'5555                  UNDEF  SET $5555             ',
			'                                                   ',
			'0000                  init                         ',
			'                      * Fix STRING zone            ',
			'0000  AFA8B5              STX   STRINGZONE-TABLE,Y ',
			'0003  270B                BEQ   init1              ',
			'0005  3402                PSHS  A                  ',
			'0007  DC22                LDD   <$22               ',
			'0009  EDA8B5              STD   STRINGZONE-TABLE,Y ',
			'000C  33CB                LEAU  D,U                ',
			'000E  3502                PULS  A                  ',
			'0010                  init1                        ',
			'                                                   ',
			'                      * clear table                ',
			'0010  C67F                LDB   #127               ',
			'0012                  init2                        ',
			'0012  6FA5                CLR   B,Y                ',
			'0014  5A                  DECB                     ',
			'0015  C11F                CMPB  #31                ',
			'0017  26F9                BNE   init2              ',
			'                                                   ',
			'                      * setup decode               ',
			'0019  33C6                LEAU  A,U                ',
			'001B                  init3                        ',
			'001B  E6C2                LDB   ,-U                ',
			'001D  4A                  DECA                     ',
			'001E  A7A5                STA   B,Y                ',
			'0020  26F9                BNE   init3              ',
			'                                                   ',
			'                      * fix LINE ptr               ',
			'0022  30A90080            LEAX  LINE-TABLE,Y       ',
			'0026  AFA812              STX   PSET_LINE-TABLE,Y  ',
			'                                                   ',
			'0029  1FB8                TFR   DP,A               ',
			'002B  8440                ANDA  #$40               ',
			'002D  274E                BEQ   exit               ',
			'                      *  fix PLOT for TO           ',
			'002F  8681                LDA   #$81 ; CMPA#       ',
			'0031  A7A817              STA   PLOT-TABLE,Y       ',
			'                      * fix COLOUR for TO          ',
			'0034  8E6038              LDX   #$6038             ',
			'0037  AFA815              STX   PSET_COLOR-TABLE,Y ',
			'003A  2041                BRA   exit               ',
			'                                                   ',
			'                          IF    (*&1)-1            ',
			'003C  12                  NOP ; align STR_PTR      ',
			'                          ENDIF                    ',
			'                                                   ',
			'003D                  entry                        ',
			'003D  CE0000              LDU   #$0                ',
			'003E                  S_PTR SET *-2                ',
			'0040  318C56              LEAY  TABLE,PCR          ',
			'0043  AEB8E5              LDX   [I_PTR-TABLE,Y]    ',
			'                                                   ',
			'0046  A6C4                LDA   ,U                 ',
			'0048  A7E2                STA   ,-S                ',
			'004A  EE41                LDU   1,U                ',
			'004C  33C90000            LEAU  >0,U               ',
			'004E                  STRINGZONE SET *-2           ',
			'                                                   ',
			'0050  E6A820              LDB   32,Y               ',
			'0053  26AB                BNE   init               ',
			'                                                   ',
			'0055                  decode                       ',
			'0055  ECC0                LDD   ,U+                ',
			'0057  A6A6                LDA   A,Y                ',
			'                                                   ',
			'0059  813B                CMPA  #59                ',
			'005B  2C0F                BGE   single             ',
			'                                                   ',
			'005D  8138                CMPA  #56                ',
			'005F  2C21                BGE   special            ',
			'                                                   ',
			'0061  1F89                TFR   A,B                ',
			'0063  8407                ANDA  #7                 ',
			'0065  54                  LSRB                     ',
			'0066  54                  LSRB                     ',
			'0067  54                  LSRB                     ',
			'0068  CB02                ADDB  #2                 ',
			'006A  2021                BRA   multiple           ',
			'                                                   ',
			'                          IF    (*&1)              ',
			'                          NOP ; align J_PTR        ',
			'                          ENDIF                    ',
			'                                                   ',
			'006C                  single                       ',
			'006C  10BE5555            LDY   UNDEF              ',
			'006E                  J_PTR SET   *-2              ',
			'0070  804B                SUBA  #75                ',
			'0072  8D35                BSR   PSET               ',
			'0074  3001                LEAX  1,X                ',
			'                                                   ',
			'0076                  decode2                      ',
			'0076  318C20              LEAY  TABLE,PCR          ',
			'0079  6AE4                DEC   ,S                 ',
			'007B  26D8                BNE   decode             ',
			'                                                   ',
			'                          IF    (*&1)-1            ',
			'                          NOP ; align I_PTR        ',
			'                          ENDIF                    ',
			'                                                   ',
			'007D                  exit                         ',
			'007D  BF5555              STX   UNDEF              ',
			'007E                  I_PTR SET *-2                ',
			'0080  3582                PULS  A,PC               ',
			'                                                   ',
			'0082                  special                      ',
			'0082  6AE4                DEC   ,S                 ',
			'0084  3341                LEAU  1,U                ',
			'0086  E6A5                LDB   B,Y                ',
			'FFE5                  TMP set   offset-TABLE-56    ',
			'0088  C3E511              ADDD  #TMP*256+17        ',
			'008B  A6A6                LDA   A,Y                ',
			'                      *    BRA   multiple          ',
			'                                                   ',
			'008D                  multiple                     ',
			'008D  43                  COMA                     ',
			'008E  318D0087            LEAY  LINE,PCR           ',
			'0092  31A6                LEAY  A,Y                ',
			'0094  10AF8C06            STY   mult_BACK,PCR      ',
			'0098  10AE9CD2            LDY   [J_PTR,PCR]        ',
			'009C                  mult_loop                    ',
			'009C  A6895555            LDA   UNDEF,X            ',
			'009E                  mult_BACK SET *-2            ',
			'00A0  8D07                BSR   PSET               ',
			'00A2  3001                LEAX  1,X                ',
			'00A4  5A                  DECB                     ',
			'00A5  26F5                BNE   mult_loop          ',
			'00A7  20CD                BRA   decode2            ',
			'                                                   ',
			'00A9                  PSET                         ',
			'00A9  A7895555            STA   UNDEF,X            ',
			'00AB                  PSET_LINE SET *-2            ',
			'00AD  B72029              STA    $2029             ',
			'00AE                  PSET_COLOR SET *-2           ',
			'                          IF    ROTATE             ',
			'                          EXG   X,Y                ',
			'                          BSR   PLOT               ',
			'                          EXG   X,Y                ',
			'                          RTS                      ',
			'                          ENDIF                    ',
			'00B0                  PLOT                         ',
			'00B0  3F                  SWI                      ',
			'00B1  90                  FCB   $90                ',
			'00B2  7EE80F              JMP   $E80F              ',
			'                                                   ',
			'                          IF    (*&1)              ',
			'00B5  12                  NOP ; align offset       ',
			'                          ENDIF                    ',
			'                                                   ',
			'00B6                  offset                       ',
			'00B6  000203              FCB   0,2,3              ',
			'                                                   ',
			'0099                  TABLE SET *-32               ',
			'00B9  FF                  FCB   $FF                ',
			'00BA                      RMB   127-32             ',
			'0119                  LINE                         ',
			'                          IF ROTATE                ',
			'                          RMB   200                ',
			'                          ELSE                     ',
			'0119                      RMB   320                ',
			'                          ENDIF                    ',
			'                                                   ',
			'0259                  size SET  *                  ',
			'                                                   ',
			'0259                      END                      '
		}                           
		local hex,i_ptr,j_ptr,s_ptr,entry,last,offset=''
		for _,l in ipairs(asm) do                        
			local a,h = l:match('(%x%x%x%x)  (%x+)%s+')
			if h then
				hex = hex..h
			else
				local e = l:match('(%x%x%x%x)%s+entry ')
				if e then entry = tonumber(e,16) end
				local e = l:match('(%x%x%x%x)%s+I_PTR ')
				if e then i_ptr = math.floor(tonumber(e,16)/2) end
				local e = l:match('(%x%x%x%x)%s+J_PTR ')
				if e then j_ptr = math.floor(tonumber(e,16)/2) end
				local e = l:match('(%x%x%x%x)%s+S_PTR ')
				if e then s_ptr = math.floor(tonumber(e,16)/2) end
				local e = l:match('(%x%x%x%x)%s+offset ')
				if e then offset = math.floor(tonumber(e,16)/2) end
				local e = l:match('(%x%x%x%x)%s+size ')
				if e then last  = math.floor(tonumber(e,16)/2+.5) end
			end
		end
		if hex:len()%4==2 then hex=hex.."00" end
		local size = math.floor(hex:len()/4)
	    pr('K!='..(last*2+184)..'-FRE(0):IFK!>0THEN?K!;"bytes missing.":END')
		pr('I=BANK>0:DIMA('..last..'):FORJ=0TO'..(size-1)..':READA$:K!=VAL("&H"+A$):IFK!>32767THENK=K!-65536ELSEK=K!')
		pr('A(J+I*(2*J-'..last..'))=K:NEXT')
		for i=1,hex:len(),4 do
			local t = ','..hex:sub(i,i+3)
			if data:len()+t:len()>=maxlen then
				pr("DATA" .. data:sub(2))
				data = t
			 else
				data = data..t
			 end
		end
		pr("DATA" .. data:sub(2))
		data=''
		local function asn(i,v)
			-- pr('K='..v..':IFI THENA('..(last-i)..')=K ELSEA('..i..')=K')
			-- pr("A("..last..'*-(i>0)+j*(1+2*(i>0))
			data=data.."A("..(2*i-last).."*I+"..i..")="..v..':'
		end
		asn(s_ptr,"VARPTR(A$)")	asn(j_ptr,"VARPTR(J)") asn(i_ptr,"VARPTR(I)")
		asn(offset+0,OFFSETS[1]*256+OFFSETS[2]-257)
		asn(offset+1,OFFSETS[3]*256-1)
		-- pr('?HEX$(VARPTR(A('..last..'ANDI))+'..entry.."):screen0,6:STOP")
		pr(data..'A$="'..BASE91..'":EXECVARPTR(A('..last..'ANDI))+'..entry)
		if not thomson.isDefaultPalette() then
			local t = ''
			for i=0,15 do t = t..','..thomson.palette(i) end
			pr('FORI=0TO15:READJ:PALETTEI,J:NEXT:DATA' .. t:sub(2))
		end			
		if thomson.w==160 then pr("IFPEEK(&HFFF0)=2THEN?CHR$(27);CHR$(&H5E);:SCREEN,,0ELSECONSOLE,,,,3") end
		pr('I=0:J=0')
		pr('READA$:EXEC:IFI<'..w..'THEN'..lineno..'ELSEI=0:J=J+1:IFJ<'..h..'THEN'..lineno)

		-- local loopback = 'IFA<L THEN'..(lineno+10)..'ELSEIFI<'..w..'THEN'..lineno ..'ELSEI=0:J=J+1:IFJ<'..h..'THEN'..lineno
		-- pr('READA$:L=LEN(A$):A=0')
        -- pr('A=A+1:B=T(ASC(MID$(A$,A,1))):IFB>55THENPSET('..IJ..'),B-72:I=I+1ELSEC=(7ANDB)+1:FORI=I TO1+I+(B@8):PSET('..IJ..'),POINT('..IJC..'):NEXT')
		-- pr(loopback)

		-- pr('IF INKEY$="" THEN '..lineno..' ELSE RUN ""')
		pr('GOTO'..lineno)

		data=''
        for j=0,h-1 do
			local px={}; for i=0,w-1 do px[i] = p(i,j) end
			local i=0
			while i<w do
			    local best,code,extra = 1,px[i]+75
				
				for o=1,math.min(i,8) do
					local k=0
					while px[i+k]==px[i-o+k] and k<8 do k=k+1 end
					if k>best then best,code = k,(k-2)*8+(o-1) end
				end
			
                for x,o in ipairs(OFFSETS) do if o<=i then
					local k=0
					while px[i+k]==px[i-o+k] and k<107 do k=k+1 end
					if k>16 and k>best then 
						best,code,extra = k,55+x,k-17
					end
				end end
				-- if extra and code==57 then error(extra) end
				
				local t = BASE91:sub(1+code,1+code)
				if extra then t = t..BASE91:sub(1+extra,1+extra) end
				if data:len()+t:len()>=maxlen then
                    pr("DATA" .. data)
                    data = t
                else
                    data = data..t
                end
				i=i+best
			end
			if j~=h-1 and data:len()+2<maxlen then
				data=data..','
			else
                pr("DATA" .. data)
                data = ''
			end
        end
		-- if data~='' then pr("DATA " .. data) end
		out:write("\r\nRUN")
        out:close()
    end
	
	local saveb = saveb_old12

    -- save raw data as well ?
    local moved, key, mx, my, mb = waitinput(0.01)
    if key==4123 then -- shift-ESC ==> save raw files as well
		-- local ramA,ramB = {},{}
		-- for i=1,#thomson.ramA do
			-- ramA[i] = thomson.ramA[i]
			-- ramB[i] = mo5to7(thomson.ramB[i])
		-- end
        -- savem(name .. ".rama", string.char(unpack(ramA)),0x4000)
        -- savem(name .. ".ramb", string.char(unpack(ramB)),0x4000)
        -- local pal = ""
        -- for i=0,15 do
            -- local val = thomson.palette(i)
            -- pal=pal..string.char(math.floor(val/256),val%256)
        -- end
        -- savem(name .. ".pal", pal, -1)
        saveb(name .. ".bas", thomson)
        messagebox('Saved MAP + RAMA/RAMB/PAL files.')
    end
end
waitbreak(0.01)

thomson.last_info = os.clock()
function thomson.info(...)
    local time = os.clock()
    if time>=thomson.last_info then
        thomson.last_info = time + .1
        local txt = ""
        for _,t in ipairs({...}) do txt = txt .. t end
        statusmessage(txt);
        if waitbreak(0)==1 then
            local ok=false
            selectbox("Abort ?", "Yes", function() ok = true end, "No", function() ok = false end)
            if ok then error('Operation aborted') end
        end
    end
end

-- copy ramA/B onto GrafX2 screen
function thomson.updatescreen()
    -- back out
    for i=0,255 do
        setcolor(i,i,i,i)
    end
    -- refresh screen content
    clearpicture(thomson._palette.offset + thomson.border())
    for y=0,thomson.h-1 do
        for x=0,thomson.w-1 do
            local p = thomson.point(x,y)
            if p<0 then p=-p-1 end
            thomson._putpixel(x,y,thomson._palette.offset + p)
        end
    end
    -- refresh palette
    for i=1,thomson._palette.max do
        local v=thomson._palette[i]
        local r=v % 16
        local g=math.floor(v/16)  % 16
        local b=math.floor(v/256) % 16
        setcolor(i+thomson._palette.offset-1,
                 thomson.levels.pc[r+1],
                 thomson.levels.pc[g+1],
                 thomson.levels.pc[b+1])
    end
    updatescreen()
	thomson.last_info = os.clock() -- enable next info()
end

-- bitmap 16 mode
function thomson.setBM16()
    -- put a pixel onto real screen
    function thomson._putpixel(x,y,c)
        putpicturepixel(x*2+0,y,c)
        putpicturepixel(x*2+1,y,c)
    end
    -- put a pixel in thomson screen
    function thomson.pset(x,y,c)
        local bank = x%4<2 and thomson.ramA or thomson.ramB
        local offs = math.floor(x/4)+y*40+1
        if x%2==0 then
            bank[offs] = (bank[offs]%16)+c*16
        else
            bank[offs] = math.floor(bank[offs]/16)*16+c
        end
        -- c=c+thomson._palette.offset
        -- putpicturepixel(x*2+0,y,c)
        -- putpicturepixel(x*2+1,y,c)
    end
    -- get thomson pixel at (x,y)
    function thomson.point(x,y)
        local bank = x%4<2 and thomson.ramA or thomson.ramB
        local offs = math.floor(x/4)+y*40+1
        if x%2==0 then
            return math.floor(bank[offs]/16)
        else
            return bank[offs]%16
        end
    end
    -- return internal MAP file
    function thomson._get_map_data()
        local tmp = {}
        for x=1,40 do
            for y=x,x+7960,40 do
                table.insert(tmp, thomson.ramA[y])
            end
            for y=x,x+7960,40 do
                table.insert(tmp, thomson.ramB[y])
            end
            wait(0) -- allow for key handling
        end
        local pal = {}
        for i=1,16 do
            pal[2*i-1] = math.floor(thomson._palette[i]/256)
            pal[2*i+0] =            thomson._palette[i]%256
        end
        -- build data
        local data={
            -- BM16
            0x40,
            -- ncols-1
            79,
            -- nlines-1
            24
        };
        thomson._compress(data, tmp)
        thomson._append(data,{0,0})
        -- padd to word
        if #data%2==1 then table.insert(data,0); end
        -- tosnap
        thomson._append(data,{0,128,0,thomson.border(),0,3})
        thomson._append(data, pal)
        thomson._append(data,{0xa5,0x5a})
        return data
    end

    thomson.w    = 160
    thomson.h    = 200
	thomson.mode = MODE_BM16
    thomson.palette(0,thomson.default_palette)
    thomson.border(0)
    thomson.clear()
end

-- helpers
local function bittst(val,mask)
    -- return bit32.btest(val,mask)
    return (val % (2*mask))>=mask;
end
local function bitset(val,mask)
    -- return bit32.bor(val, mask)
    return bittst(val,mask) and val or (val+mask)
end
local function bitclr(val,mask)
    -- return bit32.band(val,255-mask)
    return bittst(val,mask) and (val-mask) or val
end

-- mode MO5
function thomson.setMO5()
    -- put a pixel onto real screen
    thomson._putpixel = putpicturepixel
    -- put a pixel in thomson screen
    function thomson.pset(x,y,c)
        local offs = math.floor(x/8)+y*40+1
        local mask = 2^(7-(x%8))
        if c>=0 then
            thomson.ramA[offs] = (thomson.ramA[offs]%16)+c*16
            thomson.ramB[offs] = bitset(thomson.ramB[offs],mask)
        else
            c=-c-1
            thomson.ramA[offs] = math.floor(thomson.ramA[offs]/16)*16+c
            thomson.ramB[offs] = bitclr(thomson.ramB[offs],mask)
        end
    end
    -- get thomson pixel at (x,y)
    function thomson.point(x,y)
        local offs = math.floor(x/8)+y*40+1
        local mask = 2^(7-(x%8))
        if bittst(thomson.ramB[offs],mask) then
            return math.floor(thomson.ramA[offs]/16)
        else
            return -(thomson.ramA[offs]%16)-1
        end
    end
    -- return internal MAP file
    function thomson._get_map_data()
        -- create columnwise data
        local tmpA,tmpB={},{};
        for x=1,40 do
            for y=x,x+7960,40 do
                table.insert(tmpA, thomson.ramA[y])
                table.insert(tmpB, thomson.ramB[y])
            end
            wait(0) -- allow for key handling
        end
        if thomson.optiMAP then
            -- optimize
            for i=2,8000 do
                local c1,c2 = math.floor(tmpA[i-0]/16),tmpA[i-0]%16
                local d1,d2 = math.floor(tmpA[i-1]/16),tmpA[i-1]%16

                if tmpB[i-1]==255-tmpB[i] or c1==d2 and c2==c1 then
                    tmpB[i] = 255-tmpB[i]
                    tmpA[i] = c2*16+c1
                elseif tmpB[i]==255 and c1==d1 or tmpB[i]==0 and c2==d2 then
                    tmpA[i] = tmpA[i-1]
                end
            end
        else
            for i=1,8000 do
                local c1,c2 = math.floor(tmpA[i]/16),tmpA[i]%16

                if tmpB[i]==255 or c1<c2 then
                    tmpB[i] = 255-tmpB[i]
                    tmpA[i] = c2*16+c1
                end
            end
        end
        -- convert into to7 encoding
        for i=1,#tmpA do tmpA[i] = mo5to7(tmpA[i]); end
        -- build data
        local data={
            -- BM40
            0x00,
            -- ncols-1
            39,
            -- nlines-1
            24
        };
        thomson._compress(data, tmpB); tmpB=nil;
        thomson._append(data,{0,0})
        thomson._compress(data, tmpA); tmpA=nil;
        thomson._append(data,{0,0})
        -- padd to word (for compatibility with basic)
        if #data%2==1 then table.insert(data,0); end

        -- tosnap
        if not thomson.isDefaultPalette() then
            local pal = {}
            for i=0,15 do
                local v = thomson.palette(i)
                pal[2*i+1] = math.floor(v/256)
                pal[2*i+2] =            v%256
            end
            thomson._append(data,{0,0,0,thomson.border(),0,0})
            thomson._append(data, pal)
            thomson._append(data,{0xa5,0x5a})
        end

        return data
    end

    thomson.w    = 320
    thomson.h    = 200
	thomson.mode = MODE_40
    thomson.palette(0,thomson.default_palette)
    thomson.border(0)
    thomson.clear()
end

function thomson.setBM4()
    -- put a pixel onto real screen
    thomson._putpixel = putpicturepixel
    -- put a pixel in thomson screen
    function thomson.pset(x,y,c)
        local offs = math.floor(x/8)+y*40+1
        local mask = 2^(7-(x%8))
        thomson.ramA[offs] = (c%2)==1 and bitset(thomson.ramA[offs],mask)
		                              or  bitclr(thomson.ramA[offs],mask)
        thomson.ramB[offs] = (c%4)>=2 and bitset(thomson.ramB[offs],mask)
		                              or  bitclr(thomson.ramB[offs],mask)
    end
    -- get thomson pixel at (x,y)
    function thomson.point(x,y)
        local offs = math.floor(x/8)+y*40+1
        local mask = 2^(7-(x%8))
        return (bittst(thomson.ramA[offs],mask) and 1 or 0) 
		     + (bittst(thomson.ramB[offs],mask) and 2 or 0)
    end
    -- return internal MAP file
    function thomson._get_map_data()
        -- create columnwise data
        local tmpA,tmpB={},{};
        for x=1,40 do
            for y=x,x+7960,40 do
                table.insert(tmpA, thomson.ramA[y])
                table.insert(tmpB, thomson.ramB[y])
            end
            wait(0) -- allow for key handling
        end
        -- build data
        local data={
            -- BM4
            0x01,
            -- ncols-1
            39,
            -- nlines-1
            24
        };
        thomson._compress(data, tmpB); tmpB=nil;
        thomson._append(data,{0,0})
        thomson._compress(data, tmpA); tmpA=nil;
        thomson._append(data,{0,0})
        -- padd to word (for compatibility with basic)
        if #data%2==1 then table.insert(data,0); end

        local pal = {}
        for i=1,16 do
            pal[2*i-1] = math.floor(thomson._palette[i]/256)
            pal[2*i+0] =            thomson._palette[i]%256
        end
        -- tosnap
        thomson._append(data,{
                        0,0x01,             -- $605F (screenmode=interleaved)
                        0,thomson.border(), -- border
                        0,2                 -- console ,,,,?
                        })
        thomson._append(data, pal)
        thomson._append(data,{0xa5,0x5a})
        return data
    end

    thomson.w = 320
    thomson.h = 200
	thomson.mode = MODE_BM4
    thomson.palette(0,thomson.default_palette)
    thomson.border(0)
    thomson.clear()
end

end -- thomson
