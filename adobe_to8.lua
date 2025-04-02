-- adobe_mo5.lua : converts an image into TO7/70-MO5
-- mode for thomson machines (MO6,TO8,TO9,TO9+)
-- using special bayer matrix that fits well with
-- color clashes.
--
-- Version: avril 2020
--
-- Copyright 2020 by Samuel Devulder
--
-- This program is free software; you can redistribute
-- it and/or modify it under the terms of the GNU
-- General Public License as published by the Free
-- Software Foundation; version 2 of the License.
-- See <http://www.gnu.org/licenses/>

pcall(function() require('lib/cmdline') end)
run("lib/thomson.lua")
run("lib/color.lua")
run("lib/bayer.lua")
run('lib/color_reduction.lua')

Color.NORMALIZE = 0

-- get screen size
local screen_w, screen_h = getpicturesize()
local MAXCOL = 16
local ATT = .5 -- .5 -- MAXCOL>8 and 0.9 or 1
local unpack = unpack or table.unpack

local dither = {{1,4},{3,2}}
dither = bayer.double{{1},{2}} -- {{1,7},{5,3},{8,2},{6,4}}
-- dither = bayer.double(dither)
local dx,dy=#dither,#dither[1]

-- Converts thomson coordinates (0-160,0-199) into screen coordinates
local CENTERED = true
local function thom2screen(x,y)
	local i,j;
	if screen_w/screen_h < 1.6 then
		local o = CENTERED and (screen_w-screen_h*1.6)/4 or 0
		i = x*screen_h/200+o
		j = y*screen_h/200
	else
		local o = CENTERED and (screen_h-screen_w/1.6)/2 or 0
		i = x*screen_w/320
		j = y*screen_w/320+o
	end
	return math.floor(i*2), math.floor(j)
end

-- return the pixel @(x,y) in normalized linear space (0-1)
-- corresonding to the thomson screen (x in 0-159, y in 0-199)
local function getLinearPixel(x,y)
	local x1,y1 = thom2screen(x,y)
	local x2,y2 = thom2screen(x+1,y+1)
	if x2==x1 then x2=x1+1 end
	if y2==y1 then y2=y1+1 end
	
	local p,i,j = Color:new(0,0,0);
	for i=x1,x2-1 do
		for j=y1,y2-1 do
			p:add(getLinearPictureColor(i,j))
		end
	end
	p:div((y2-y1)*(x2-x1)*Color.ONE)
	return p
end
-- 0 .22 .44 .66 .88 1

local function getLinearPixelQ(x,y)
	return getLinearPixel(x,y):map(function(t) return math.floor(t*6)/6 end)
end

-- get thomson palette pixel (linear, 0-1 range)
local linearPalette = {}
function linearPalette.get(i)
	local p = linearPalette[i]
	if not p then
		local pal = thomson.palette(i-1)
		local b=math.floor(pal/256)
		local g=math.floor(pal/16)%16
		local r=pal%16
		p = Color:new(thomson.levels.linear[r+1],
					  thomson.levels.linear[g+1],
					  thomson.levels.linear[b+1]):div(Color.ONE)
		linearPalette[i] = p
	end
	return p:clone()
end

-- closest color in the palette
linearPalette.proxCache={}
function linearPalette.index(c) 
	function f(x)
		return math.floor(.5+32*(x<0 and 0 or x>1 and 1 or x)^.45)
	end
	local k = string.char(f(c.r), f(c.g), f(c.b))
	local i = linearPalette.proxCache[k]
	local dist = Color.dE2fast 
	if not i then
		i = 1
		local d = dist(linearPalette.get(i),c)
		for e=i+1,MAXCOL do
			local t = dist(linearPalette.get(e),c)
			if t<d then i,d = e,t end
		end
		linearPalette.proxCache[k] = i
	end
	return i
end

-- adobe dithering
linearPalette.ditherCache={}
function linearPalette.dither(c)
	local function f(x) return math.floor(.5+21*x^.45) end
	local k = string.char(f(c.r),f(c.g),f(c.b))
	local s = linearPalette.ditherCache[k]
	if not s then
		local t = {}
		local d = Color:new()
		for i=1,dx*dy do
			local j = linearPalette.index(c:clone():add(d,ATT))
			t[i] = j
			d:sub(linearPalette.get(j):sub(c))
		end
		table.sort(t, function(a,b) return linearPalette.get(a):intensity()<linearPalette.get(b):intensity() end)
		s = string.char(unpack(t))
		linearPalette.ditherCache[k] = s
	end
	return s
end


local red = ColorReducer:new():analyzeWithDither(160,200,
	function(x,y) return getLinearPixel(x,y):mul(Color.ONE) end,
    function(y)
		thomson.info("Collecting stats...",math.floor(y*100),"%")
	end)
local palette = red
	-- :boostBorderColors()
	:boostBorderColors()
	:buildPalette(MAXCOL)
	
-- BM16 mode
thomson.setBM16()

-- define palette
thomson.palette(0, palette)
-- for i=0,15 do thomson.palette(i,i*273) end 	

local tab = {}
for y=0,199 do
	for x=0,159 do
		local d=dither[1+(math.floor(y/1)%dx)][1+(x%dy)]
		local p=getLinearPixel(x,y)
		local c=linearPalette.dither(p):byte(d)
		table.insert(tab,c-1)
	end
	thomson.info("Converting...",math.floor(y/2),"%")
end
for i=0,31999 do
	thomson.pset(i%160,math.floor(i/160),tab[i+1])
end
setpicturesize(320,200)
thomson.updatescreen()
thomson.savep()
finalizepicture()
