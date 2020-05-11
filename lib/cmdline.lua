#!/usr/bin/env lua

-- Emulates GrafX2 API for cmdline calls

if not run then 
	local PWD = os.getenv("PWD") or os.getenv("CD")
	PWD=PWD:gsub('^/cygdrive/(%w)/','%1:/')
	run=function(filename)
		local dir,name=filename:match("(.-)([^\\/]+)$")
		local old=PWD
		PWD = PWD .. '/' .. dir
		dofile(PWD .. '/' .. name)
		PWD = old
	end
end

if not unpack then
	unpack= table.unpack
end

if not CMDLINE and type(arg)=='table' and type(arg[1])=='string' then 
	CMDLINE = true
	
	-- append "b" if os require binary mode files
	local function binmode(rw)
		local t = os.getenv("SystemDrive")
		if t and t:match("^.:$") then rw = rw .. 'b' end
		return rw
	end
	
	-- support for bmp (https://www.gamedev.net/forums/topic/572784-lua-read-bitmap/)
	local function read_bmp24(file) 
		if not file then return nil end
		local bytecode = file:read('*all')
		file:close()
		if bytecode:len()<32 then return nil end 
		
		-- Helper function: Parse a 16-bit WORD from the binary string
		local function ReadWORD(str, offset)
			local loByte = str:byte(offset);
			local hiByte = str:byte(offset+1);
			return hiByte*256 + loByte;
		end

		-- Helper function: Parse a 32-bit DWORD from the binary string
		local function ReadDWORD(str, offset)
			local loWord = ReadWORD(str, offset);
			local hiWord = ReadWORD(str, offset+2);
			return hiWord*65536 + loWord;
		end

		-------------------------
		-- Parse BITMAPFILEHEADER
		-------------------------
		local offset = 1;
		local bfType = ReadWORD(bytecode, offset);
		if(bfType ~= 0x4D42) then
			-- error("Not a bitmap file (Invalid BMP magic value)");
			return nil
		end
		local bfOffBits = ReadWORD(bytecode, offset+10);

		-------------------------
		-- Parse BITMAPINFOHEADER
		-------------------------
		offset = 15; -- BITMAPFILEHEADER is 14 bytes long
		local biWidth = ReadDWORD(bytecode, offset+4);
		local biHeight = ReadDWORD(bytecode, offset+8);
		local biBitCount = ReadWORD(bytecode, offset+14);
		local biCompression = ReadDWORD(bytecode, offset+16);
		if(biBitCount ~= 24) then
			-- error("Only 24-bit bitmaps supported (Is " .. biBitCount .. "bpp)");
			return nil;
		end
		if(biCompression ~= 0) then
			-- error("Only uncompressed bitmaps supported (Compression type is " .. biCompression .. ")");
			return nil;
		end
		
		return {
			width = biWidth,
			height = biHeight,
			bytecode = bytecode,
			bytesPerRow = 4*math.floor((biWidth*biBitCount/8 + 3)/4),
			offset = bfOffBits,
			norm = norm and norm>0 and norm_max/norm,
			getLinearPixel = function(self,x,y)
				if x<0 or y<0 or x>=self.width or y>=self.height then
					return Color.black
				else
					local i = self.offset + (self.height-1-y)*self.bytesPerRow + 3*x
					local b = self.bytecode
					local c = Color:new(b:byte(i+3), b:byte(i+2), b:byte(i+1)):toLinear()
					if self.norm then c:map(function(x) x=x*self.norm; return x<1 and x or 1 end) end
					return c
				end
			end
		}
	end


	-- magick goes here
    local filename = arg[1]:gsub('^/cygdrive/(%w)/','%1:/')
    local dir,name=filename:match("(.-)([^\\/]+)$");
    if name:lower():match("%.map$") or
       name:lower():match("%.tap$") then os.exit(0) end
    dir = dir=='' and '.' or dir -- prevent empty dir
    local bmp = read_bmp24(io.open(filename, binmode("r")))
    if not bmp then
        local convert = 'convert "' .. filename .. '" -type truecolor -depth 8 bmp:-'
        bmp = read_bmp24(assert(io.popen(convert,binmode('r'))))
    end
    if not bmp then error("Can't open image: " .. filename) end
    -- emulate GrafX2 function for cmdline
    function getfilename()  return name,dir end
    function getpicturesize() return bmp.width or 0,bmp.height or 0 end
    function getLinearPictureColor(x,y) return bmp:getLinearPixel(x,y) end
    function waitbreak() return 0 end
    function statusmessage(msg) 
        local txt = name .. ': ' .. msg
        if txt:len()>79 then txt="..." .. txt:sub(-76) else txt = txt .. string.rep(' ', 79-txt:len()) end
        io.stderr:write(txt .. '\r') 
        io.stderr:flush() 
    end
    function selectbox(msg, yes, cb) cb() end
    function setpicturesize(w,h) 
        -- io.stderr:write(string.rep(' ',79) .. '\r')
		-- io.stderr:write(name .. '...done') 
		statusmessage("done")
        io.stderr:write('\n')
        io.stderr:flush() 
    end
    function putpicturepixel(x,y,c) end
    function setcolor(i,r,g,b) end
	function clearpicture() end
	function updatescreen() end
	function finalizepicture() end
	function wait() end
	function waitinput() end
	function getbackuppixel(x,y) return 255 end
end
