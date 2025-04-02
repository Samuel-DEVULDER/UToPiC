-- BM4.lua : convert a color image to a BM4
-- BM4.lua : convert a color image to a BM4
-- (320x200x4) thomson image using the Ostromoukhov's
-- error diffusion algorithm or Ordered dither
--
-- Version: 01-juil-2024
--
-- Copyright 2024 by Samuel Devulder
--
-- This program is free software; you can redistribute
-- it and/or modify it under the terms of the GNU
-- General Public License as published by the Free
-- Software Foundation; version 2 of the License.
-- See <http://www.gnu.org/licenses/>

pcall(function() require('lib/cmdline') end)
run('lib/color.lua')
run('lib/thomson.lua')
run('lib/ostromoukhov.lua')
run('lib/color_reduction.lua')
run('lib/bayer.lua')
unpack = unpack or table.unpack
Color.NORMALIZE = 0

-- dither = {{1}}
-- dither = {{1,2},{2,1}}
dither = bayer.double{{1}}
dither = bayer.double(dither)
dither = bayer.double(dither)
-- dither = bayer.double(dither)

-- dither = {
	-- {7,2,6},
	-- {9,1,3},
	-- {5,4,8}
-- }

-- dither = {
	-- {2,5,8},
	-- {7,1,3},
	-- {4,9,6}
-- }

-- dither = {
	-- { 7, 13, 11, 4},
    -- {12, 16, 14, 8},
	-- {10, 15,  6, 2},
	-- { 5,  9,  3, 1}
-- }

-- dither = {
	-- {1, 21, 16, 15,  4},
	-- {5, 17, 20, 19, 14},
    -- {6, 21, 25, 24, 12},
	-- {7, 18, 22, 23, 11},
	-- {2,  8,  9, 10,  3}
-- }

-- dither = {{1,4},{2,3}}

-- dither = {
	-- {16,49,25,43,28,50,38,11},
	-- {31,6,52,10,58,2,24,55},
	-- {41,21,59,15,33,48,9,63},
	-- {4,45,36,27,42,19,35,28},
	-- {51,18,8,64,3,53,60,14},
	-- {39,54,30,47,23,12,44,26},
	-- {1,22,13,56,40,32,7,57},
	-- {34,61,37,5,17,62,20,46}
-- }

	-- dither = {
		-- { 4, 2, 7, 5},
		-- { 3, 1, 8, 6},
		-- { 7, 5, 4, 2},
		-- { 8, 6, 3, 1} 
	-- }

	-- dither = {
		-- {13, 7, 8,14,17,21,22,18},
		-- { 6, 1, 3, 9,28,31,29,23},
		-- { 5, 2, 4,10,27,32,30,24},
		-- {16,12,11,15,20,26,25,19},
		-- {17,21,22,18,13, 7, 8,14},
		-- {28,31,29,23, 6, 1, 3, 9},
		-- {27,32,30,24, 5, 2, 4,10},
		-- {20,26,25,19,16,12,11,15}
	-- }
	
	-- dither = {
		-- { 7,21,33,43,36,19, 9, 4},
		-- {16,27,51,55,49,29,14,11},
		-- {31,47,57,61,59,45,35,23},
		-- {41,53,60,64,62,52,40,38},
		-- {37,44,58,63,56,46,30,22},
		-- {15,28,48,54,50,26,17,10},
		-- { 8,18,34,42,32,20, 6, 2},
		-- { 5,13,25,39,24,12, 3, 1}
	-- }
	
	-- dither = {
		-- { 7,13,11, 4},
		-- {12,16,14, 8},
		-- {10,15, 6, 2},
		-- { 5, 9, 3, 1} 
	-- }

-- dither = {
		-- {392,985,503,140,452,709,180,387,952,122,855,52,679,135,972,293,386,760,35,225,853,419,1006,353,925,415,718,492,115,969,175,737},
		-- {823,2,617,888,75,541,1016,48,495,707,416,304,882,606,439,827,96,1019,567,335,512,635,25,539,656,77,590,916,373,626,889,259},
		-- {570,191,695,252,808,332,625,783,287,603,207,981,519,236,63,671,499,265,893,720,87,804,244,843,169,879,264,16,784,514,57,455},
		-- {322,922,475,382,937,167,431,872,91,914,743,3,802,379,938,740,199,628,407,159,968,377,703,474,321,749,454,984,299,162,714,1012},
		-- {125,782,70,744,592,21,730,223,524,369,165,449,652,142,547,338,870,109,822,487,598,189,915,46,997,572,112,681,552,842,389,607},
		-- {865,527,216,974,291,502,956,323,643,989,576,858,297,1004,789,33,456,945,320,5,792,288,536,663,395,226,814,368,202,960,90,253},
		-- {687,361,638,445,147,834,668,66,790,120,240,721,76,484,206,685,586,172,754,633,1005,432,78,884,151,735,923,64,480,646,765,465},
		-- {160,1002,36,881,712,375,198,458,898,399,505,933,362,610,904,283,975,397,520,250,132,698,821,315,622,448,278,564,895,312,11,932},
		-- {333,800,254,517,101,609,995,555,271,741,54,658,176,773,417,117,729,45,828,910,355,579,230,939,523,22,977,690,141,831,430,571},
		-- {110,615,420,747,918,303,12,806,145,591,1013,311,848,13,560,880,345,219,667,424,55,739,463,89,769,374,801,214,402,621,233,734},
		-- {876,203,950,339,164,846,436,689,343,887,204,444,530,951,246,644,493,1022,554,161,954,851,186,991,262,648,111,498,868,80,966,482},
		-- {32,696,557,69,662,546,208,953,504,43,786,701,92,381,738,138,847,74,793,276,639,532,391,684,565,906,336,999,704,302,774,372},
		-- {993,289,826,464,1015,385,751,106,627,404,266,588,825,184,990,460,300,390,699,473,9,327,127,886,41,422,170,594,17,534,158,649},
		-- {515,411,150,772,242,39,912,292,835,983,129,931,326,516,661,24,616,944,196,839,979,724,803,232,507,755,836,256,437,920,816,229},
		-- {869,82,935,634,337,585,692,479,187,538,686,457,50,864,255,894,781,95,584,367,146,562,447,1014,313,85,949,642,726,347,59,600},
		-- {316,715,209,497,857,134,393,807,4,356,776,227,604,742,396,171,526,440,261,913,664,279,56,619,702,551,378,105,193,1010,459,762},
		-- {978,574,438,47,964,757,231,992,595,900,103,1018,341,126,965,674,324,1009,761,28,819,413,871,156,911,221,785,488,867,561,274,155},
		-- {1,365,909,691,285,542,71,453,719,275,421,660,818,469,556,38,840,133,593,476,200,540,732,366,467,10,971,282,624,73,813,670},
		-- {874,249,798,174,412,655,838,331,139,863,525,31,195,929,270,736,418,237,716,351,942,102,996,241,830,568,665,414,166,958,384,478},
		-- {553,632,94,518,1023,124,927,563,678,218,962,752,318,645,83,891,608,980,58,854,672,308,601,72,694,330,114,856,710,310,758,188},
		-- {994,314,746,866,352,243,477,18,799,400,86,581,433,794,508,359,153,491,280,558,163,441,791,511,897,181,1024,535,29,494,899,68},
		-- {683,152,451,40,612,693,771,306,998,629,269,903,148,1007,213,833,680,926,408,745,902,19,973,267,394,756,450,234,812,613,263,435},
		-- {360,849,569,963,194,907,79,434,173,513,824,371,675,62,577,298,7,779,104,211,618,358,708,121,640,49,597,921,364,88,731,940},
		-- {14,228,764,295,405,522,841,602,934,44,706,224,496,768,406,957,637,340,543,1017,468,837,178,489,947,796,301,149,673,877,179,549},
		-- {659,1008,481,97,717,144,346,248,750,328,883,119,976,272,859,168,462,878,260,797,53,294,583,873,334,205,550,987,409,510,305,809},
		-- {123,380,605,829,928,575,982,666,108,471,578,398,647,26,533,614,67,728,143,669,401,961,767,34,423,697,844,20,763,100,970,446},
		-- {268,875,201,60,442,235,8,403,815,1020,183,778,924,350,753,245,988,370,908,485,98,528,238,651,1011,116,466,284,641,222,587,722},
		-- {943,500,705,348,650,775,890,531,215,620,42,296,509,131,832,425,676,182,573,281,852,723,136,383,559,190,919,537,810,901,354,51},
		-- {623,154,820,1000,290,490,157,688,307,941,428,860,713,210,967,84,501,817,15,1003,630,344,948,788,861,319,727,65,388,137,483,777},
		-- {329,426,37,545,113,959,376,805,81,725,548,93,636,410,582,325,936,257,711,427,197,61,461,258,6,631,429,946,247,682,1021,212},
		-- {566,917,677,217,748,589,30,472,905,342,177,1001,251,896,23,733,611,128,349,795,544,892,596,700,506,986,99,599,850,529,27,862},
		-- {107,273,787,363,930,277,845,654,239,580,770,486,357,780,521,185,885,470,653,955,118,286,759,130,220,811,309,192,766,317,443,657}
	-- }	
-- get screen size
local screen_w, screen_h = getpicturesize()
local CENTERED = true
local GLB_MULT = 241/250 -- 215/255 -- 241/255 --215/255 --0.89803921568627450980392156862745 -- .98
local OSTRO = true

local G_R, G_G, G_B = 
	-- .2, .7, .1
	-- 0.2126,0.7152,0.0722
	-- 0.299, 0.587, 0.114
	-- .25,.61,.14
	2/7,4/7,1/7
	-- .3,.55,.15

local border = Color:new()
-- border.n = 0
-- for r=0,math.ceil(math.min(screen_w,screen_h)*.05) do
	-- for x=r,screen_w-1-r do
		-- border.n = border.n + 2
		-- border:add(getLinearPictureColor(x,r))
		-- border:add(getLinearPictureColor(x,screen_h-1-r))
	-- end
	-- for y=r+1,screen_h-2-r do
		-- border.n = border.n + 2
		-- border:add(getLinearPictureColor(r,y))
		-- border:add(getLinearPictureColor(screen_w-1-r,y))		
	-- end
-- end
-- Color.border = border:div(border.n) border.n = nil

-- border = Color:new()
for x=0,screen_w-1 do for y=0,screen_h-1 do border:add(getLinearPictureColor(x,y)) end end
border:div(screen_w*screen_h)
Color.border = border

local DLT = {}
for _,r in ipairs{-1,0,1} do
	for _,g in ipairs{-1,0,1} do
		for _,b in ipairs{-1,0,1} do
			local t = r+g*16+b*256
			if t~=0 then table.insert(DLT,t+4096) end
		end
	end
end

-- 0       0       0
-- 1       34.586499062077 0.13563332965521
-- 2       56.923129115786 0.22322795731681
-- 3       76.638667576023 0.30054379441578
-- 4       94.665608520908 0.37123768047415
-- 5       112.11257932943 0.43965717384092
-- 6       128.23604679831 0.50288645803257
-- 7       144.00143395476 0.56471150570493
-- 8       159.10989987714 0.62396039167508
-- 9       173.28332975644 0.67954246963309
-- 10      188.16715423705 0.73791040877273
-- 11      201.78097478482 0.79129794033263
-- 12      215.95267403501 0.84687323150986
-- 13      228.54868511044 0.89626935337427
-- 14      241.56316686697 0.9473065367332
-- 15      255     1

-- Converts thomson coordinates (0-159,0-199) into screen coordinates
local function thom2screen(x,y)
	local i,j,k=0,0,1.6
	if screen_w/screen_h <= k then
		local o = CENTERED and (screen_w-screen_h*k)/2 or 0
		i = x*screen_h/200+o
		j = y*screen_h/200
	else
		local o = CENTERED and (screen_h-screen_w/k)/2 or 0
		i = x*screen_w/320
		j = y*screen_w/320+o
	end
	return math.floor(i+.5), math.floor(j+.5)
end

-- return the Color @(x,y) in normalized linear space (0-1)
-- corresonding to the thomson screen (x in 0-319, y in 0-199)
local function getLinearPixel(x,y)
	local c = Color:new(0,0,0)
	local x1,y1 = thom2screen(x,y)
	local x2,y2 = thom2screen(x+1,y+1)
	if x2==x1 then x2=x1+1 end
	if y2==y1 then y2=y1+1 end

	for i=x1,x2-1 do
		for j=y1,y2-1 do
			c:add(getLinearPictureColor(i,j))
		end	
	end

	return c:div((y2-y1)*(x2-x1))
	       :map(function(x) return x<6 and 0 or x>250 and 250 or x end)
		   -- :mul(GLB_MULT)
end

-- for i=0,15 do print(i, thomson.levels.linear[1+i], thomson.levels.linear[1+i]/255) end
local err_t 

quality = {
	cache = {},
	sub = function(u,v)
		return {u[1]-v[1],u[2]-v[2],u[3]-v[3]}
	end,
	cross = function(u,v)
		return {u[2]*v[3] - u[3]*v[2], 
				u[3]*v[1] - u[1]*v[3], 
				u[1]*v[2] - u[2]*v[1]}
	end,
	dot = function(u,v)
		return u[1]*v[1] + u[2]*v[2] + u[3]*v[3]
	end,
	inside = function(self, p)
		local dot,sub = self.dot,self.sub
		local q = sub(p, self.p0)
		local s,t = dot(q,self.n012),dot(q,self.n023)
		if s==0 then s=t elseif s*t<0 then return false end
		t = dot(q,self.n031)
		if s==0 then s=t elseif s*t<0 then return false end
		return s*dot(sub(p,self.p1),self.n132)>=0
	end,
	weight = function(self, p)
		local dot,sub = self.dot,self.sub
		local q = sub(p,self.p0)
		local w3 = dot(q, self.n012)
		local w1 = dot(q, self.n023)
		local w2 = dot(q, self.n031)
		local w0 = dot(sub(p,self.p1),self.n132)
		
		if w0>=0 and w1>=0 and w2>=0 and w3>=0 then
			local wt = w0+w1+w2+w3
			wt = wt==0 and 0 or 1/wt
			return w0*wt,w1*wt,w2*wt,w3*wt
		end
		
		-- point is outside tetrahedron
		-- project it onto closest point of hull
		local proj3 = function(point, v0,v1,v2)
		-- https://www.geometrictools.com/Documentation/DistancePoint3Triangle3.pdf
			local diff,edge0,edge1 = sub(point,v0),sub(v1,v0),sub(v2,v0)
			local a00,a01,a11 = dot(edge0,edge0),dot(edge0,edge1),dot(edge1,edge1)
			local b0,b1= -dot(diff,edge0),-dot(diff,edge1)
			local det,t0,t1 = a00 * a11 - a01 * a01,  a01 * b1 - a11 * b0, a01 * b0 - a00 * b1
			
			if t0 + t1 <= det then
				if t0 < 0 then 
					if t1<0 then -- region 4
						if b0<0 then
							t0,t1 = -b0>=a00 and 1 or -b0/a00,0
						else
							t0,t1 = 0,b1>=0 and 0 or -b1>=a11 and 1 or -b1/a11
						end
					else  -- region 3
						t0,t1 = 0,b1>=0 and 0 or -b1>=a11 and 1 or -b1/a11	
					end
				elseif t1<0 then -- region 5
					t0,t1 = b0>=0 and 0 or -b0>=a00 and 1 or -b0/a00,0
				else -- region 0, interior
					t0,t1 = t0/det,t1/det
				end
			else
				local tmp0,tmp1, numer,denom
				if t0<0 then -- region 2
					tmp0,tmp1 = a01+b0,a11+b1
					if tmp1>tmp0 then
						numer,denom = tmp1-tmp0,a00-a01-a01+a11
						t0 = numer>=denom and 1 or numer/denom
						t1 = 1-t0
					else
						t0,t1 = 0,tmp1<=0 and 1 or b1>=0 and 0 or -b1/a11
					end
				elseif t1<0 then -- region 6
					tmp0,tmp1 = a01 + b1,a00 + b0
					if tmp1>tmp0 then
						numer,denom = tmp1-tmp0,a00-a01-a01+a11
						t1 = numer>=denom and 1 or numer/denom
						t0 = 1-t1
					else
						t1,t0 = 0,tmp1<=0 and 1 or b0>=0 and 0 or -b0/a00
					end
				else -- region 1
					numer,denom = a11 + b1 - a01 - b0,a00 - a01 - a01 + a11
					t0 = numer<=0 and 0 or numer>=denom and 1 or numer/denom
					t1 = 1-t0
				end
			end
		   
			return 1-t0-t1,t0,t1
		end
		local proj2 = function(p, v0,v1)
			local v10 = sub(v1,v0)
			local t = dot(v10,v10)
			if t<=0 then return 1,0 end
			t = dot(sub(p,v0),v10)/t
			t = t<=0 and 0 or t>1 and 1 or t
			return 1-t,t
		end
		
		local a,b,c,d = w0<0,w1<0,w2<0,w3<0
		w0,w1,w2,w3 = 0,0,0,0
		if a then
			if b then
				if c then	
					w3 = 1
				elseif d then
					w2 = 1
				else
					w2,w3 = proj2(p,self.p2,self.p3)
				end
			elseif c then
				if d then
					w1 = 1
				else
					w1,w3 = proj2(p,self.p1,self.p3)
				end
			elseif d then
				w1,w2 = proj2(p,self.p1,self.p2)
			else
				w1,w2,w3 = proj3(p,self.p1,self.p2,self.p3)
			end
		elseif b then
			if c then
				if d then
					w0 = 1
				else
					w0,w3 = proj2(p,self.p0,self.p3)
				end
			elseif d then
				w0,w2 = proj2(p,self.p0,self.p2)
			else
				w0,w2,w3 = proj3(p,self.p0,self.p2,self.p3)
			end
		elseif c then
			if d then
				w0,w1 = proj2(p,self.p0,self.p1)
			else
				w0,w1,w3 = proj3(p,self.p0,self.p1,self.p3)
			end
		elseif d then
			w0,w1,w2 = proj3(p,self.p0,self.p1,self.p2)
		end
		return w0,w1,w2,w3
	end,
	pt = function(p) 
		return string.format('(%.1f %.1f %.1f)', unpack(p))
	end,
	setPal = function(self, pal)
		self.pal, self.cache = {},{}
		local floor,cross,sub=math.floor,self.cross,self.sub
		for i,p in ipairs(pal) do
			local r,g,b = p%16, floor(p/16)%16,floor(p/256)
			p = Color:new(thomson.levels.linear[1+r],
			  	          thomson.levels.linear[1+g],
						  thomson.levels.linear[1+b])
			p.index = i
			self.pal[i] = p
		end
		
		local p0,p1,p2,p3 = {self.pal[1]:toRGB()},{self.pal[2]:toRGB()},
		                    {self.pal[3]:toRGB()},{self.pal[4]:toRGB()}

		-- 3      
		-- |  2   
		-- | /    
		-- |/     
		-- 0-----1
		
		local vol_thr = .1
		local p01,p02,p03,p12,p13
		repeat
			p01,p02,p03,p12,p13 = sub(p1,p0), sub(p2,p0), sub(p3,p0), sub(p2,p1), sub(p3,p1)
			self.n012 = cross(p01,p02)
			self.n023 = cross(p02,p03)
			self.n031 = cross(p03,p01)
			self.n132 = cross(p13,p12)
			self.vol  = self.dot(self.n012, p03)/6
			if self.vol<0 then -- swap 1 & 2
				p1,p2,self.pal[2],self.pal[3] = p2,p1,self.pal[3],self.pal[2]
			elseif self.vol<=vol_thr then
				-- degenerate case => perturbate
				local i=math.random(6)
				local p = i==1 and p1 or i==2 and p2 or i==3 and p3 or p0
				i = math.random(3)
				p[i] = math.min(math.max(0,p[i] + (math.random()-.5)/100),Color.ONE)
				self.vol = -1
			end
			-- print(self.vol..' p0'..self.pt(p0)..' p1'..self.pt(p1)..' p2'..self.pt(p2)..' p3'..self.pt(p3))
		until self.vol>vol_thr
	
		self.p0, self.p1, self.p2, self.p3 = p0, p1, p2, p3
		
		-- return self.vol/(255^3/3)
		-- local function d(a,b) return ((1+0.299^2)*(a[1]-b[1])^2 + (1+0.587^2)*(a[2]-b[2])^2 + (1+0.114^2)*(a[3]-b[3])^2) end
		local function d(a,b) return ((
			(a[1]-b[1])^2 + (a[2]-b[2])^2 + (a[3]-b[3])^2 + (0.299*(a[1]-b[1]) + 0.587*(a[2]-b[2]) + 0.114*(a[3]-b[3]))^2
			) / (4*Color.ONE^2))
		end
		local d01,d02,d03,d12,d13,d23 = d(p0,p1),d(p0,p2),d(p0,p3),d(p1,p2),d(p1,p3),d(p2,p3)
		-- return (d01+d02+d03+d12+d13+d23)*(math.max(d01,d02,d03,d12,d13,d23)/math.min(d01,d02,d03,d12,d13,d23))/6
		-- return (math.max(d01,d02,d03,d12,d13,d23)/math.min(d01,d02,d03,d12,d13,d23))^.5
		-- return (d01+d02+d03+d12+d13+d23)/6
		return (math.max(d01,d02,d03,d12,d13,d23) / math.min(d01,d02,d03,d12,d13,d23))
		-- return 1000*Color.ONE/math.min(d01,d02,d03,d12,d13,d23)^.5
	end,
	hash = function(self, pix)
		local function t(x) return math.floor(x*64/Color.ONE + .5) end
		return string.format("%x,%x,%x", t(pix.r), t(pix.g), t(pix.b))
	end,
	n_weight = function(self, n, p)
		local w0,w1,w2,w3 = self:weight(p)
		local tot,l,a,b,c,d = 0, {}
		local function f(x)
			local a,b=math.floor(x*n),math.ceil(x*n)
			if a==b then return ipairs{a} else return ipairs{a,b} end
		end
		local s=1e300
		for _,m0 in f(w0) do
			for _,m1 in f(w1) do
				for _,m2 in f(w2) do
					for _,m3 in f(w3) do
						if m0+m1+m2+m3==n then
							local t,r,g,b_=0,(p[1]/Color.ONE),(p[2]/Color.ONE),(p[3]/Color.ONE) --^(1/2.2)
							if true then
								local w = 
									-- {1,1,1} 
									-- {(2+r),4,(3-r)}
									-- {1+(g+b_)^2/4,1+(r+b_)^2/4,1+(r+g)^2/4}
									-- {Color.ONE*2/7,Color.ONE*4/7,Color.ONE*1/7}
									-- {Color.ONE*0.2126, Color.ONE*0.7152, Color.ONE*0.0722}
									-- {G_R*Color.ONE,G_G*Color.ONE,G_B*Color.ONE}
									{G_R, G_G, G_B}
								for i=1,3 do 
									local q = (m0*self.p0[i] + m1*self.p1[i] + m2*self.p2[i] + m3*self.p3[i])/n
									local x = math.abs(q - p[i])
									-- local x = (q - p[i])
									t = t +	w[i]*x -- *math.log(1+x)
									-- t = t + w[i]*math.abs(q^2 - p[i]^2)
								end
								t = t*Color.ONE
								for i=1,3 do 
									local q = (m0*self.p0[i] + m1*self.p1[i] + m2*self.p2[i] + m3*self.p3[i])/n
									-- local x = ((1+q)/(1+p[i])) 
									-- x = x^.5
									t = t + (q-p[i])^2
									-- t = t + math.abs(q-p[i])^2 + (x+1/x)^4 --math.abs(x-1)
									-- t = t + math.abs(q-p[i])^2 + math.abs(x-1) -- relative error
								end
							else
								local w = 
									-- {1,1,1} 
									-- {(2+r),4,(3-r)}
									-- {1+(g+b_)^2/4,1+(r+b_)^2/4,1+(r+g)^2/4}
									{2/7,4/7,1/7}
								for i=1,3 do 
									local q = (m0*self.p0[i] + m1*self.p1[i] + m2*self.p2[i] + m3*self.p3[i])/n
									local x = math.abs(q - p[i])
									t = t +	w[i]*x -- *math.log(1+x)
								end
								t = t*t/Color.ONE
								-- w = {1+(g^2+b_^2)/2,1+(r^2+b_^2)/2,1+(r^2+g^2)/2}
								-- w = {2+r,4,3-r}
								-- w = {2,4,1}
								-- w = {2,3,1}
								w = {1,1,1}
								-- w = {1+(g+b_)/2,1+(r+b_)/2,1+(r+g)/2}
								for i=1,3 do w[i]=w[i]/Color.ONE/(w[1]+w[2]+w[3]) end
								for i=1,3 do 
									local q = (m0*self.p0[i] + m1*self.p1[i] + m2*self.p2[i] + m3*self.p3[i])/n
									local e = .6863 -- .85 -- .66 -- .85
									local x = math.abs(Color.ONE*((q/Color.ONE)^e - (p[i]/Color.ONE)^e))^(2/e)
									t = t +	w[i]*x--*math.log(1+x)
								end
							end
							if t<s then s,a,b,c,d = t,m0,m1,m2,m3 end
						end
					end
				end
			end
		end
		return s,a,b,c,d
		
		-- return s,a,b,c,d
		-- return (s+.1)*(a*a+b*b+c*c+d*d),a,b,c,d 
		-- local z=n
		-- if 0<a and a<z then z=a end
		-- if 0<b and b<z then z=b end
		-- if 0<c and c<z then z=c end
		-- if 0<d and d<z then z=d end
		-- return (s+1)*math.max(a,b,c,d)/z,a,b,c,d 
		-- return s/z,a,b,c,d 
		-- return s*z,a,b,c,d
		-- return s*math.max(a,b,c,d)/z,a,b,c,d 
		-- return s*(4+n/math.max(a,b,c,d)),a,b,c,d
		-- return s + 0*((a*a+b*b+c*c+d*d)/(n*n)) + ((a>0 and 1 or 0) + (b>0 and 1 or 0) + (c>0 and 1 or 0) + (d>0 and 1 or 0))
	end,
	dither_len = function(self)
		local n = 1
		for _,r in ipairs(self.matrix) do n = math.max(n,unpack(r)) end
		return n
	end,
	eval = function(self, pix)
		-- local s = self:n_weight(OSTRO and err_t*0+30 or self:dither_len(),{pix:toRGB()})
		local s,n,p = 0,OSTRO and 64 or math.min(64,self:dither_len()),{pix:toRGB()}
		-- for n=(n<2 and 1 or n<4 and 2 or n<6 and 4 or 6),n do
		-- for _,n in ipairs{6,12,15,16,24} do
		-- for _,n in pairs{2,4,8,16,32} do
		-- for _,n in pairs{8,16,32,64} do --- ok
		local i,j,k,t = OSTRO and 8 or n,0,2^(1/4),0
		while i<=n do
		-- for _,n in pairs{n-6,n-4,n-2,n-1,n} do
		-- for _,n in pairs{n-5,n-4,n-3,n-2,n-1,n} do
		-- for _,n in pairs{n-8,n-7,n-6,n-5,n-4,n-3,n-2,n-1,n} do
		-- for _,n in pairs{n-32,n-16,n-8,n-4,n-2,n-1,n} do
		-- for n=9,n do
		-- while n>=8 do
			j,i = math.floor(i+.5),i*k
			s,t = s + self:n_weight(j,p)*j,t+j
		end
		-- s = s + self:n_weight(n,p)
		return s/t
	end,
	matrix = dither,
	dx = #dither,	
	dy = #dither[1],
	get = function(self, x, y, c)
		local k = "x"..self:hash(c)
		local s = self.cache[k]
		if not s then
			local _,n0,n1,n2,n3 = self:n_weight(self:dither_len(), {c:toRGB()})
			s = ""
			for i=1,n0 do s=s..string.char(self.pal[1].index) end
			for i=1,n1 do s=s..string.char(self.pal[2].index) end
			for i=1,n2 do s=s..string.char(self.pal[3].index) end
			for i=1,n3 do s=s..string.char(self.pal[4].index) end
			self.cache[k] = s
		end
		return s:byte(self.matrix[1+(x%self.dx)][1+(y%self.dy)])
	end
}

local function collectStats()
	local stat,ncols,nmax,err = {},0,0,{}
	local tab = thomson.levels.linear2to
	local bat = thomson.levels.linear
	for i=1,16 do
		local a,b = (bat[i+1] or 256),bat[i]
		for j=math.ceil(b),math.floor(a) do err[j] = a-b end
	end
	local f=function(x,r) 
		x = math.floor(x+.5)
		local e = err[x]
		r = math.random()
		return math.min(Color.ONE,math.max(0,math.floor(x+e*(r-.5)+.5))) 
	end
	local dither = bayer.double{{1}}
	dither = bayer.double(dither)
	-- dither = bayer.double(dither)
	-- dither = bayer.double(dither)
	-- dither = bayer.double(dither)
	
	-- dither = bayer.double(bayer.double{
		-- {16,49,25,43,28,50,38,11},
		-- {31,6,52,10,58,2,24,55},
		-- {41,21,59,15,33,48,9,63},
		-- {4,45,36,27,42,19,35,28},
		-- {51,18,8,64,3,53,60,14},
		-- {39,54,30,47,23,12,44,26},
		-- {1,22,13,56,40,32,7,57},
		-- {34,61,37,5,17,62,20,46}
	-- })

	-- dither = {
		-- { 7, 13, 11, 4},
		-- {12, 16, 14, 8},
		-- {10, 15,  6, 2},
		-- { 5,  9,  3, 1}
	-- }

	local dx,dy,dm = #dither,#dither[1],0
	for _,r in ipairs(dither) do dm = math.max(dm, unpack(r)) end
	-- print((dm+1)..'            ')
	for y=0,199 do 
		for x=0,319 do
			local p,z = getLinearPixel(x,y),(dither[1+(x%dx)][1+(y%dy)]-1)/dm--*0+math.random()
			-- z = (z+math.random())/2
			-- z = z*z*z
			-- print(z,math.random())
			-- z = ((x+y)%32)/32
			-- z = math.random()
			local r,g,b = tab[f(p.r,z)],tab[f(p.g,z)],tab[f(p.b,z)]
			local rgb = r+g*16+b*256-273
			local s = stat[rgb]
			if s then s.n = s.n + 1 else
				s = {n=1, rgb=rgb, p=Color:new(bat[r],bat[g],bat[b])}
				stat[rgb] = s
				ncols = ncols+1
			end
		end 
		statusmessage('Counting cols (' .. math.floor(y/2) .. '% '..ncols..')')
		waitbreak(0)
	end
	-- tri par frequence
	local sorted = {}
	for _,s in pairs(stat) do nmax = math.max(nmax, s.n) table.insert(sorted, s) end
	table.sort(sorted, function(a,b) return a.n>b.n end)
	
	-- for i,s in pairs(sorted) do print(i,s.n) end	
	local thr = 0
	for i=2,math.ceil(#sorted/10) do thr = thr + sorted[i].n end
	thr = thr/5000
	-- print('    '..thr..'     ')

	for k,s in pairs(stat) do if s.n<=thr then ncols=ncols-1; stat[k]=nil end end
	statusmessage('Counting cols ('..ncols..')') waitbreak(0)

	return sorted
end

local stat = collectStats()

err_t={0,0} for _,s in pairs(stat) do err_t[1],err_t[2]=err_t[1]+s.n,err_t[2]+1 end 
err_t[1],err_t[2],err_t[3] = 6,err_t[1]/err_t[2],4
while err_t[1]*err_t[3] <= err_t[2] do err_t[1],err_t[3] = err_t[1]*err_t[3],err_t[3]+1 end
err_t = err_t[1]

-- print(ncols .. ' colors '..nmax..' max')

-- quality based
function err(palette, dmax)
	local z = quality:setPal(palette)
	local dist = 0 -- z/32*160*100
	
	-- 4/3*pi*r^3
	-- dist = (dist*3/(4*math.pi)/255^3)^(2/3) -- to make it homogeneous to a distance
	-- dist = 0*dist/256

	for _,s in pairs(stat) do
		dist = dist + s.n * quality:eval(s.p) -- *(6+z)
		-- local d = quality:n_weight(err_t,{s.p:toRGB()})
		-- dist = dist + s.n * d;
		if dist>dmax then break end
	end 
	
	return dist
end

local t,dmax,pal = os.clock(),1e300

local changed,done,known,to = true,false,{},t
local ZZ
local function chk(pp)
	if done then return end
	table.sort(pp)
	local h = string.format('%03x%03x%03x%03x', unpack(pp))
	if known[h]==nil then 
		known[h] = true h=nil
		local dd = err(pp, dmax)
		if dd<dmax then 
			dmax,pal,changed = dd,pp,true
			statusmessage(string.format('%2s %03x,%03x,%03x %f', ZZ, pp[2],pp[3],pp[4], dmax))		
			-- statusmessage(string.format("(%s) %4.1f %13.1f", ZZ or ' ', os.clock()-t,dmax))
		end
	end
	local t=os.clock()
	if t>=to then 
		to=t+.2
		if waitbreak(0.01)==1 then done,changed = true,false end 
	end
end

-- pal = {0,0,0,0}
ZZ='--' chk({0x000,0x222,0x666,0xEEE}) 
ZZ='++' chk({0x000,0xE00,0x0E0,0x00E}) 
if false then
	local l  = {0x00F,0x0F0,0x0FF,0xF00,0xF0F,0xFF0,0xFFF}
	for i=1,#l-2 do for j=i+1,#l-1 do for k=j+1,#l do
		ZZ ='**' chk({0,l[i],l[j],l[k]})
	end end end
end

if false then
	local l  = {0x222,0x666,0xEEE,0xE00,0x0E0,0x00E}
	for i=1,#l-2 do for j=i+1,#l-1 do for k=j+1,#l do
		ZZ ='**' chk({0,l[i],l[j],l[k]})
	end end end
end

-- ZZ='++' chk(ColorReducer:new():analyzeWithDither(320,200,
	-- getLinearPixel,
    -- function(y)
		-- thomson.info("Collecting stats...",math.floor(y*100),"%")
	-- end):buildPalette(4))

if true then
	for _,s in ipairs{7,4,2} do
		local PAL={}
		for b=0,15,s do
			for g=0,15,s do
				for r=0,15,s do
					table.insert(PAL, r+g*16+b*256)
				end
			end
		end
		repeat
			local pal = {pal[1], pal[2], pal[3], pal[4]}
			changed = false
			for _,p in ipairs(PAL) do ZZ="3"..s chk{pal[1], pal[2], pal[3], p} end
			for _,p in ipairs(PAL) do ZZ="2"..s chk{pal[1], pal[2], p, pal[4]} end
			for _,p in ipairs(PAL) do ZZ="1"..s chk{pal[1], p, pal[3], pal[4]} end
			for _,p in ipairs(PAL) do ZZ="0"..s chk{p, pal[2], pal[3], pal[4]} end
		until not changed
	end
end

if false then
	local function map(vals, histo)
		local k,v0,v1,e=1,0,thomson.levels.linear[1+vals[1]],0
		for i=1,16 do
			local v = thomson.levels.linear[i]
			if v>=v1 and vals[k+1] then 
				k,v0,v1=k+1,v1,thomson.levels.linear[1+vals[k+1]]
			end
			local f = (v-v0)/(v1-v0); if f>=1 then f=1 end
			local Q=6
			f = math.floor(.5+Q*f)/Q
			e = e + histo[i]*math.abs(v0 + f*(v1-v0) - v)^2
		end
		return e
	end
	local function best(base)
		local h = {} for i=1,16 do h[i]=0 end
		for _,s in ipairs(stat) do 
			local k = 1+(math.floor(s.rgb/base)%16)
			h[k] = h[k] + s.n
		end
		local a,b,c,d,e=0,0,0,0,1e300
		for i=1,13 do for j=i+1,14 do for k=j+1,15 do
			d = map({i,j,k}, h)
			if d<e then a,b,c,e = i,j,k,d end
		end end end
		return {0,a,b,c}
	end
	local lR,lG,lB = best(1),best(16),best(256)
	-- print()
	-- print('r', unpack(lR))
	-- print('g', unpack(lG))
	-- print('b', unpack(lB))
	local PAL={}
	for _,b in ipairs(lB) do
		for _,g in ipairs(lG) do
			for _,r in ipairs(lR) do 
				table.insert(PAL, r+g*16+b*256)
			end
		end
	end
	table.sort(PAL, function(a,b) return (a%15)<(b%15) end)
	
	-- pal = {0,0X088,0x880,0x808}
	-- repeat
		-- changed = false
		-- for p=1,4095 do ZZ='z1' chk{pal[1],pal[2],pal[3],p} end
		-- for p=1,4095 do ZZ='z2' chk{pal[1],pal[2],p,pal[4]} end
		-- for p=1,4095 do ZZ='z3' chk{pal[1],p,pal[3],pal[4]} end
	-- until not changed
	
	-- pal = {0,0,0,0} dmax=1e300
	-- repeat
		-- local pal = {pal[1], pal[2], pal[3], pal[4]}
		-- changed = false
		-- for _,p in ipairs(PAL) do ZZ="3" chk{pal[1], pal[2], pal[3], p} end
		-- for _,p in ipairs(PAL) do ZZ="2" chk{pal[1], pal[2], p, pal[4]} end
		-- for _,p in ipairs(PAL) do ZZ="1" chk{pal[1], p, pal[3], pal[4]} end
		-- for _,p in ipairs(PAL) do ZZ="0" chk{p, pal[2], pal[3], pal[4]} end
	-- until not changed
	
	if true then
	local n,t=0,100/((1+0*#PAL)*(#PAL-1)*(#PAL-2)*(#PAL-3)/6)
	for i=1,1+0*#PAL do
		for j=i+1,#PAL do
			for k=j+1,#PAL do
				for l=k+1,#PAL do
					ZZ=math.floor(n)..'%' chk{PAL[i],PAL[j],PAL[k],PAL[l]}
					n=n+t
				end
			end
		end
	end
	end
end

-- pal = {0,0,0,0} dmax=1e300
-- PAL = {} s=2 for r=0,15,s do for g=0,15,s do for b=0,15,s do table.insert(PAL,r+g*16+b*256) end end end

if false then
	dmax = 1e300 pal = {0,0,0,0}	
	for _,LVL in ipairs{
		{0,15},
		{0,6,15},
		{0,3,9,15},
		{0,1,5,10,15},
		{0,1,3,8,11,15},
		{0,1,3,5,7,9,12,15},
		{0,2,4,6,8,10,11,13,14},
		{0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15},
		nil
	} do 
		local PAL={}
		for _,r in ipairs(LVL) do
			for _,g in ipairs(LVL) do
				for _,b in ipairs(LVL) do
					table.insert(PAL, r+g*16+b*256)
				end
			end
		end
		repeat
			local pal = {pal[1], pal[2], pal[3], pal[4]}
			changed = false
			ZZ='0' for i=1,#PAL do chk{PAL[i], pal[2], pal[3], pal[4]} end
			ZZ='1' for i=1,#PAL do chk{pal[1], PAL[i], pal[3], pal[4]} end
			ZZ='2' for i=1,#PAL do chk{pal[1], pal[2], PAL[i], pal[4]} end
			ZZ='3' for i=1,#PAL do chk{pal[1], pal[2], pal[3], PAL[i]} end
		until not changed
	end
end
if true then
for i=1,1 do
	for _,s in ipairs{4,3,2,1} do -- {4,3,2,1} do --{4,3,2,1,4,3,2,1} do -- 4,3,2,1,4,2,1,2,1} do --{4,3,2,1,4,3,2,1,4,2,1} do
		repeat
			local pal = {pal[1], pal[2], pal[3], pal[4]}
			changed = false
			-- ZZ='0' for i,p in ipairs{0x000,0x001,0x010,0x011,0x100,0x101,0x110,0x111} do chk{p, pal[2], pal[3], pal[4]}	end
			for _,dlt in ipairs(DLT) do local d = dlt*s
				ZZ='@'..s chk{(pal[1]+d)%4096, pal[2], pal[3], pal[4]}
				ZZ='a'..s chk{pal[1], (pal[2]+d)%4096, pal[3], pal[4]}
				ZZ='b'..s chk{pal[1], pal[2], (pal[3]+d)%4096, pal[4]}
				ZZ='c'..s chk{pal[1], pal[2], pal[3], (pal[4]+d)%4096}
				
				ZZ='A'..s chk{pal[1], pal[2], (pal[3]+d)%4096, (pal[4]+d)%4096}
				ZZ='B'..s chk{pal[1], (pal[2]+d)%4096, pal[3], (pal[4]+d)%4096}
				ZZ='C'..s chk{pal[1], (pal[2]+d)%4096, (pal[3]+d)%4096, pal[4]}

				-- ZZ='/'..s chk{pal[1], (pal[2]+d)%4096, (pal[3]+d)%4096, (pal[4]+d)%4096}
			end
		until not changed
	end
end
end

-- print(dmax)
-- quality:setPal(pal)
-- print(quality:eval(Color:new()))
-- pal[1] = 0x010
-- quality:setPal(pal)
-- print(quality:eval(Color:new()))
-- print(chk{0x010,pal[2],pal[3],pal[4]})

local function intens(p)
	local r,g,b = p%16, math.floor(p/16)%16,math.floor(p/256)
	local t = thomson.levels.linear
	return .2126*t[r+1] + .7152*t[g+1] + .0722*t[b+1]
	-- return 2*t[r+1]+4*t[g+1]+t[b+1]
	-- return math.sqrt(0.299*t[r+1]^2 + 0.587*t[g+1]^2 + 0.114*t[b+1]^2)
	-- return G_R*t[r+1] + G_G*t[g+1] + G_B*t[b+1]
	-- return 2*r+4*g+b
	-- return b+g*16+g*256
end
table.sort(pal, function(a,b) return intens(a)<intens(b) end)
-- pal[2],pal[3] = pal[3],pal[2]

-- table.sort(pal, function(a,b) 
	-- local t=thomson.levels.pc
	-- a = Color:new(t[1+(a%16)],
				  -- t[1+(math.floor(a/16)%16)],
				  -- t[1+math.floor(a/256)])
	-- b = Color:new(t[1+(b%16)],
				  -- t[1+(math.floor(b/16)%16)],
				  -- t[1+math.floor(b/256)])
	-- local ah,as,av=a:HSV()
	-- local bh,bs,bv=b:HSV()
	-- as,bs=a:intensity()/255,b:intensity()/255
	-- function lum(a) return ((.241*a.r + .691*a.g + .068*a.b)/255)^.5 end
	-- as,bs=lum(a),lum(b)
	-- local sat,int=32,256
	-- local function quant(ah,as,av)
		-- return math.floor(ah*8),
			   -- math.floor(as*sat),
			   -- math.floor(av*int+.5)
	-- end
	-- ah,as,av=quant(ah,as,av)
	-- bh,bs,bv=quant(bh,bs,bv)
	-- if true then return ah<bh end
	-- if true then return av<bv or av==bv and as<bs end
	-- if true then return as<bs or as==bs and av<bv end
	-- if ah%2==1 then as,av=sat-as,int-av end
	-- if bh%2==1 then bs,bv=sat-bs,int-bv end
	-- return ah<bh or (ah==bh and (as<bs or (as==bs and av<bv)))
-- end)
-- tab.sort(pal, function(a,b) return a<b end)

-- print(string.format('%03x %03x %03x %03x                ', unpack(pal)))
-- print(dmax)
-- Color.border = Color.black
Color.border = border
thomson.setBM4()
thomson.palette(0, pal)
for i=4,15 do thomson.palette(i,0) end
if OSTRO then
	OstroDither:new(pal)
           :dither(320,200, getLinearPixel, thomson.pset, true,
			function(x) thomson.info("Converting...",math.floor(x*100),"%") end)
else
	local d = quality
	d:setPal(pal)	
	for y=0,199 do
		for x=0,319 do
			local p = getLinearPixel(x,y)
			local c = d:get(x,y,p)
			thomson.pset(x,y, c-1)
		end
		thomson.info("Converting...",math.floor(y/2),"%")
	end
end

-- local floor=math.floor
-- for i,p in ipairs(pal) do
	-- local r,g,b = p%16, floor(p/16)%16,floor(p/256)
	-- pal[i] = Color:new(thomson.levels.linear[1+r],
					   -- thomson.levels.linear[1+g],
					   -- thomson.levels.linear[1+b])
-- end
-- local err={} for i=-1,320*DIV do err[i] = Color:new(0,0,0) end
-- for y=0,199 do
	-- for x=0,319 do
		-- local p = err[x]:add(getLinearPixel(x,y)) --:map(function(x) return x<0 and 0 or x>Color.ONE and Color.ONE or x end)
		-- local c = col(pal, p)
		-- thomson.pset(x,y,c-1)
		-- err[x+1]:add(p:sub(pal[c]),.5)
		-- err[x-1]:add(p:mul(.25))
	-- end
-- end

io.stderr:write(string.format('                                                                                %03x %03x %03x %03x  \r', unpack(pal)))
io.stderr:flush()

-- refresh screen
setpicturesize(320,200)
thomson.updatescreen()
finalizepicture()

-- save picture
thomson.savep()
-- print(dmax)
