-- bayer4_to7.lua : converts an image into TO7
-- mode for thomson machines (MO/TO)
--
-- Version: 08-jan-2024
--
-- Copyright 2024 by Samuel Devulder
--
-- This program is free software; you can redistribute
-- it and/or modify it under the terms of the GNU
-- General Public License as published by the Free
-- Software Foundation; version 2 of the License.
-- See <http://www.gnu.org/licenses/>

-- This is my first code in lua, so excuse any bad
-- coding practice.

-- debug: displays histograms
local debug = false

-- enhance luminosity since our mode divide it by three
local enhance_lum = enhance_lum or true

-- use void-and-cluster 8x8 matrix (default=false)
local use_vac = use_vac or false

pcall(function() require('lib/cmdline') end)
run("lib/color.lua")
run("lib/thomson.lua")
run("lib/bayer.lua")

-- get screen size
local screen_w, screen_h = getpicturesize()
local BLOC = 3
local thom_w,thom_h = math.floor(0.5+320/BLOC),math.floor(0.5+200/3)

-- Converts thomson coordinates (0-159,0-99) into screen coordinates
local CENTERED = true
local function thom2screen(x,y)
	local i,j,k=0,0,1.6
	y = y*3/BLOC
	if screen_w/screen_h < k then
		local o = CENTERED and (screen_w-screen_h*k)/2 or 0
		i = x*screen_h/thom_h+o
		j = y*screen_h/thom_h
	else
		local o = CENTERED and (screen_h-screen_w/k)/2 or 0
		i = x*screen_w/thom_w
		j = y*screen_w/thom_w+o
	end
	return math.floor(i), math.floor(j)
end

-- return the pixel @(x,y) in linear space corresonding to the thomson screen (x in 0-159, y in 0-99)
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

	return p:div((y2-y1)*(x2-x1)):floor()
end

--[[ make a bayer matrix
function bayer(matrix)
	local m,n=#matrix,#matrix[1]
	local r,i,j = {}
	for j=1,m*2 do
		local t = {}
		for i=1,n*2 do t[i]=0; end
		r[j] = t;
	end
	
	-- 0 3
	-- 2 1
	for j=1,m do
		for i=1,n do
			local v = 4*matrix[j][i]
			r[m*0+j][n*0+i] = v-3
			r[m*1+j][n*1+i] = v-2
			r[m*1+j][n*0+i] = v-1
			r[m*0+j][n*1+i] = v-0
		end
	end
	
	return r;
end
--]]

-- dither matrix
local dither = bayer.make(2)

if use_vac then
	-- vac8: looks like FS
	dither = bayer.norm{
		{35,57,19,55,7,51,4,21},
		{29,6,41,27,37,17,59,45},
		{61,15,53,12,62,25,33,9},
		{23,39,31,49,2,47,13,43},
		{3,52,8,22,36,58,20,56},
		{38,18,60,46,30,5,42,28},
		{63,26,34,11,64,16,54,10},
		{14,48,1,44,24,40,32,50}
	}
end

-- get color statistics
local stat = {};
function stat:clear() 
	self.r = {}
	self.g = {}
	self.b = {}
	for i=1,16 do self.r[i] = 0; self.g[i] = 0; self.b[i] = 0; end
end
function stat:update(px) 
	local pc2to = thomson.levels.pc2to
	local r,g,b=pc2to[px.r], pc2to[px.g], pc2to[px.b];
	self.r[r] = self.r[r] + 1;
	self.g[g] = self.g[g] + 1;
	self.b[b] = self.b[b] + 1;
end
function stat:coversThr(perc)
	local function f(stat)
		local t=-stat[1]
		for i,n in ipairs(stat) do t=t+n end
		local thr = t*perc; t=-stat[1]
		for i,n in ipairs(stat) do 
			t=t+n 
			if t>=thr then return i end
		end
		return 0
	end
	return f(self.r),f(self.g),f(self.b)
end
stat:clear();
for y = 0,thom_h-1 do
	for x = 0,thom_w-1 do
		stat:update(getLinearPixel(x,y))
	end
	thomson.info("Collecting stats...",y,"%")
end

-- enhance luminosity since our mode divide it by two
local gain = 1
if enhance_lum then
	-- findout level that covers 98% of all non-black pixels
	local max = math.max(stat:coversThr(.999))

	gain = math.min(3,255/thomson.levels.linear[max])

	if gain>1 then
		-- redo stat with enhanced levels
		-- messagebox('gain '..gain..' '..table.concat({stat:coversThr(.98)},','))
		stat:clear();
		for y = 0,thom_h-1 do
			for x = 0,thom_w-1 do
				stat:update(getLinearPixel(x,y):mul(gain):floor())
			end
			thomson.info("Enhancing levels..",y,"%")
		end
	end
end

-- put a pixel at (x,y) with dithering
local function pset(x,y,px)
	local thr = dither[1+(y % #dither)][1+(x % #dither[1])]
	x,y=x*BLOC,y*3
	local function dither(val,thr)
		val = val*(BLOC+1)/Color.ONE
		return math.floor(val)+((val % 1)>=thr and 1 or 0)
	end
	local function pset(x,y,col)
		if x<thomson.w and y<thomson.h then
			thomson.pset(x,y,col)
		end
	end
	local function seg(x,y,val,col)
		for i=0,BLOC-1 do
			pset(x+i,y,i<val and col or -1)
		end
	end
	seg(x,y  , dither(px.r, thr), 1)
	seg(x,y+1, dither(px.g, thr), 2)
	seg(x,y+2, dither(px.b, thr), 4)
end

thomson.setMO5()

-- convert picture
for y = 0,thom_h-1 do
	for x = 0,thom_w-1 do
		pset(x,y, getLinearPixel(x,y):mul(gain):floor())
	end
	thomson.info("Converting...",y,"%")
end

-- refresh screen
setpicturesize(320,200)
thomson.updatescreen()
finalizepicture()

-- save picture
do
	local function exist(file)
		local f=io.open(file,'rb')
		if not f then return false else io.close(f); return true; end
	end
	local name,path = getfilename()
	local mapname = string.gsub(name,"%.%w*$","") .. ".map"
	local fullname = path .. '/' .. mapname
	-- fullname = 'D:/tmp/toto.map'
	local ok = not exist(fullname)
	if not ok then
		selectbox("Ovr " .. mapname .. "?", "Yes", function() ok = true; end, "No", function() ok = false; end)
	end
	if ok then thomson.savep(fullname) end
end
