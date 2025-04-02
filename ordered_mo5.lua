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

-- get screen size
local screen_w, screen_h = getpicturesize()
local MAXCOL = 16
local ATT = .9 -- MAXCOL>8 and 0.9 or 1
local ATT2 = 0.7

local dither = {{1,2},{3,4}}
local DEBUG =  false
-- dither = {{1,3},{4,2}}
-- dither = {{1,2},{3,4}}
dither = bayer.double(dither)
dither = {{1,3,2,4},{9,11,10,12},{5,7,6,8},{13,15,14,16}} -- pas mal
dither = {{1,3,2,4},{11,9,11,12,10},{5,7,6,8},{15,13,16,14}} -- pas mal
-- dither = {{1,5,2,6},{9,13,10,14},{3,7,4,8},{11,15,12,16}}

-- dither = {{1,7,2,8},{9,15,10,16},{5,3,6,4},{13,11,14,12}} -- pas mal

dither = {{1,2},{4,3}} ATT=.8
-- dither = {{1,2},{3,4}}
-- dither = {{1}}

-- dither = bayer.double(dither)
-- dither = {{1,2,3},{4,5,7},{6,8,9}}
-- dither = {{1}}
-- dither = {{1,2},{3,4}}
-- dither = {{1,1},{3,3}}
-- dither = {{1,3,2,4},{5,7,6,8}}
-- dither = {{1,2,4},{3,5,6}}

-- dither = {{1,2,5,6},{4,3,8,7}}

dither = bayer.double(dither)
dither = bayer.double(dither)
dither = bayer.double(dither)
-- dither = bayer.double(dither)
-- dither = {{1,3},{4,2}}

-- dither = {
		-- { 7,13,11, 4},
		-- {12,16,14, 8},
		-- {10,15, 6, 2},
		-- { 5, 9, 3, 1} 
	-- }

dither = bayer.norm(dither)
local dy,dx=#dither,#dither[1]

-- Converts thomson coordinates (0-319,0-199) into screen coordinates
local CENTERED = true
local function thom2screen(x,y)
	local i,j;
	if screen_w/screen_h < 1.6 then
		local o = CENTERED and (screen_w-screen_h*1.6)/2 or 0
		i = x*screen_h/200+o
		j = y*screen_h/200
	else
		local o = CENTERED and (screen_h-screen_w/1.6)/2 or 0
		i = x*screen_w/320
		j = y*screen_w/320+o
	end
	return math.floor(i), math.floor(j)
end


-- return the pixel @(x,y) in normalized linear space (0-1)
-- corresonding to the thomson screen (x in 0-319, y in 0-199)
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

-- TO7/70 MO5 mode
thomson.setMO5()

-- print(linearPalette.dither(Color:new(0,.1,0)))
-- os.exit(0)

-- setup
linearPalette.matrix = {}
for i=1,MAXCOL do
	linearPalette.matrix[i] = linearPalette.matrix[i] or {}
	for j=1,MAXCOL do
		local ci = linearPalette.get(i)
		local cj = linearPalette.get(j)
		local c1,c2 = i,j
		if ci:intensity()>cj:intensity() then ci,cj,c1,c2 = cj,ci,c2,c1 end
		local dj = cj:clone():sub(ci)
		local n2 = dj.r*dj.r + dj.g*dj.g + dj.b*dj.b
		linearPalette.matrix[i][j] = {
			c1 = c1-1,
			c2 = -c2,
			ci = ci, 
			cj = cj,
			dj = dj, 
			n2 = n2,
			djn2 = dj:clone():div(n2)
		}
	end
end


-- convert picture
local err = {}
for x=-1,320 do err[x] = Color:new() end
for y = 0,199 do
	for x=-1,320 do err[x]:mul(0) end
	for x = 0,319,8 do
		local px,th = {},{}
		for z=x,x+7 do 
			-- table.insert(px, Color:new(0,y/200,z/320))
			local p = getLinearPixel(z,y):add(err[z])
			p.r,p.g,p.b = Color.clamp(p.r,p.g,p.b)
			table.insert(px, p) 
			table.insert(th, dither[1+(y%dy)][1+(z%dx)])
		end
		
		local dm,mt  = 1e300
		-- MAXCOL=8
		for i=1,MAXCOL-1 do
			local mxi = linearPalette.matrix[i]
			for j=i+1,MAXCOL do
				local mx = mxi[j]
				local ci = mx.ci
				local dj = mx.djn2
				local d  = 0
				for ix,px in ipairs(px) do
					local di = px:clone():sub(ci)
					local rt = di.r*dj.r + di.g*dj.g + di.b*dj.b
					local pt = ci:clone():add(mx.dj, rt<0 and 0 or rt>1 and 1 or rt)
					local er = pt:euclid_dist2(px)
					-- local er = pt:dE2000(px)
					d = math.max(er, d)
				end
				if d<dm then dm,mt = d,mx end
			end
		end
		local ci = mt.ci
		local dj = mt.djn2
		for k,px in ipairs(px) do
			local z=x+k-1
			local di = px:sub(ci)
			local rt = di.r*dj.r + di.g*dj.g + di.b*dj.b
			local co = rt>=th[k] and mt.c2 or mt.c1
			thomson.pset(z,y, co)
			err[z]:add(linearPalette.get(co<0 and -co or co+1):sub(getLinearPixel(z,y)))
		end
	end
	thomson.info("Converting...",math.floor(y/2),"%")
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
	local ok = not exist(fullname)
	if not ok then
		selectbox("Ovr " .. mapname .. "?", "Yes", function() ok = true; end, "No", function() ok = false; end)
	end
	if ok then thomson.savep(fullname) end
end

