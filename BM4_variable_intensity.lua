-- ostro_to8.lua : convert a color image to a BM16
-- (160x200x16) thomson image using the Ostromoukhov's
-- error diffusion algorithm.
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

pcall(function() require('lib/cmdline') end)
run('lib/thomson.lua')
run('lib/ostromoukhov.lua')
run('lib/color_reduction.lua')
run('lib/bayer.lua')
unpack = unpack or table.unpack
	
-- get screen size
local screen_w, screen_h = getpicturesize()
local QUANT = 16
local FRACT = .97*0+.99
local FINE_TUNE = true
local ORDERED = false

-- Converts thomson coordinates (0-159,0-199) into screen coordinates
local function thom2screen(x,y)
	local i,j;
	if screen_w/screen_h < 1.6 then
		i = x*screen_h/200
		j = y*screen_h/200
	else
		i = x*screen_w/320
		j = y*screen_w/320
	end
	return math.floor(i), math.floor(j)
end

-- return the Color @(x,y) in normalized linear space (0-1)
-- corresonding to the thomson screen (x in 0-319, y in 0-199)
local dim_f=1
local function getLinearPixel(x,y)
	local x1,y1 = thom2screen(x,y)
	local x2,y2 = thom2screen(x+1,y+1)
	if x2==x1 then x2=x1+1 end
	if y2==y1 then y2=y1+1 end

	p = Color:new(0,0,0)
	for j=y1,y2-1 do
		for i=x1,x2-1 do
			p:add(getLinearPictureColor(i,j))
		end
	end
	p:div((y2-y1)*(x2-x1))
	-- local z=1-.333333*math.exp(-(1-p:intensity()/Color.white:intensity()))
	-- print(z)
	-- p:mul(z)
	-- p:map(function(x) return math.max(0,math.min(Color.ONE, x*(1 + (math.random()-.5)*.25))) end)
	-- if p.r + p.g + p.b>1*Color.ONE then p:mul(0*2*Color.ONE/(p.r+p.g+p.b)) end
	
	return  p:mul(dim_f)
end

local function shuffle(t)
	for i=#t,2,-1 do local j=math.random(i); t[i],t[j]=t[j],t[i] end
end

local function round(x,y,z) 
	return math.floor(x+.5),y and math.floor(y+.5),z and math.floor(z+.5) 
end

local function pt(p)
	return '('..p[1]..','..p[2]..','..p[3]..')' 
end

local function tetra(a,b)
	local function sub(u,v)
		return {u[1]-v[1],u[2]-v[2],u[3]-v[3]}
	end
	local function cross(u,v)
		return {u[2]*v[3] - u[3]*v[2], 
				u[3]*v[1] - u[1]*v[3], 
				u[1]*v[2] - u[2]*v[1]}
	end
	local function dot(u,v)
		return u[1]*v[1] + u[2]*v[2] + u[3]*v[3]
	end
-- c
-- |  b
-- | / 
-- |/
-- 0-------a
	return {
		a=a,b=b,n0ab=cross(a,b),
		tetra=function(self,c) 
			self.c,self.v,
			self.n0bc,self.n0ca,self.nacb = c,dot(c,self.n0ab)
			if self.v<0 then
				self.v,self.a,self.b,self.n0ab[1],self.n0ab[2],self.n0ab[3] = 
					-self.v,self.b,self.a,-self.n0ab[1],-self.n0ab[2],-self.n0ab[3]			
			end
			return self.v>1 and self
		end,
		inside=function(self,p)
			self.n0bc = self.n0bc or cross(self.b,self.c)
			local va,t = dot(p,self.n0ab),dot(p,self.n0bc)
			if va==0 then va=t elseif va*t<0 then return false end
			
			self.n0ca = self.n0ca or cross(self.c,self.a)
			t = dot(p,self.n0ca)
			if va==0 then va=t elseif va*t<0 then return false end
			
			self.nacb = self.nacb or cross(sub(self.c,self.a),sub(self.b,self.a))
			return va*dot(sub(p,self.a),self.nacb)>=0
		end, weights=function(self,r,g,b)
			local p = {r,g,b}
			self.n0bc = self.n0bc or cross(self.b,self.c)
			self.n0ca = self.n0ca or cross(self.c,self.a)
			self.nacb = self.nacb or cross(sub(self.c,self.a),sub(self.b,self.a))

			local wc = dot(p,self.n0ab)
			local wa = dot(p,self.n0bc)
			local wb = dot(p,self.n0ca)
			local w0 = dot(sub(p,self.a),self.nacb)
			
			return w0,wa,wb,wc
		end
	}
end

function newHull(qnt)
	qnt = qnt or 64
	local hull = {scale_factor=1,red={},grn={},blu={}}		
	for i=0,Color.ONE do
		local x = round(i*(qnt-1)/Color.ONE)
		hull.red[i],hull.grn[i],hull.blu[i]	= x,x*qnt,x*qnt*qnt
	end
	function hull:analyze()
		local t,w={},screen_w-1
		for y=0,screen_h-1 do
			for x=0,w do
				local c = getLinearPictureColor(x,y)
				if not c.n then
					local r,g,b = c:toRGB()
					local x = thomson.levels.linear
					x = x[3]/math.max(r,g,b,1)
					if x>=1 then r,g,b=r*x,g*x,b*x end
					r,g,b = round(r,g,b)
					local k = hull.red[r] + hull.grn[g] + hull.blu[b]
					local q = t[k]; if q then c=q else c=Color:new(r,g,b); t[k],c.n=c,0 end
				end
				c.n = c.n+1
			end
			thomson.info("Analyzing picture: ", round(100*y/screen_h), "%")
		end
		
		local l,tot={},0
		for h,p in pairs(t) do
			if h>0 
			-- and math.max(p:toRGB())>thomson.levels.linear[2]/2
			then
				tot = tot + p.n
				table.insert(l,p)
			end
		end
		
		-- trim non-reresentative pixels
		if true then
			table.sort(l, function(a,b) return a.n>b.n end)
			local t,tot,stop = tot*FRACT,0
			for i,p in ipairs(l) do
				tot,p.n = tot+p.n,nil
				if tot>t then l[i]=nil end
			end
		end
		
		local h = ConvexHull:new(function(c) return {c:toRGB()} end)
		h:addPoint(Color.black)
		
		local maxi = 0
		shuffle(l)
		for i,p in ipairs(l) do
			thomson.info("Building hull: ", round(100*i/#l), "%")
			h:addPoint(p)
			maxi = math.max(maxi,p:toRGB())
		end
		-- print('maxi=',maxi,'           ')
		if maxi<255 then
			__maxi = true
			dim_f = 255/maxi
		end
		
		t = {}
		if h.hull then
			for p in pairs(h:verticesSet()) do
				if p~=Color.black then 
					p[1],p[2],p[3] = p:toRGB()
					table.insert(t, p) 
				end
			end
			shuffle(t)
		else
			table.insert(t, h.points[1])
			table.insert(t, h.points[2])
		end
		
		self.hull = h
		self.pts = t
		
		return self
	end
	function hull:scale(k)
		k = k or 1
		if k~=self.scale_factor then
			k,self.scale_factor = k/self.scale_factor,k
			for _,p in ipairs(self.pts) do
				p[1],p[2],p[3] = p:mul(k):toRGB()
			end
			if k>1 then self.best = nil end
		end
		return self
	end
	function hull:isContainedIn(tetra)
		for _,p in ipairs(self.pts) do
			if not tetra:inside(p) then return false end
		end
		return true
	end
	function hull:distToHull(c)
		return self.hull:distToHull(c)
	end
	return hull
end
function newHull_full()
	local hull = {scale_factor=1}
	function hull:analyze()
		local h = ConvexHull:new(function(c) return {c:toRGB()} end)
		h:addPoint(Color.black)
		
		local t,w={},screen_w-1
		for y=0,screen_h-1 do
			for x=0,w do
				h:addPoint(getLinearPictureColor(x,y))
			end
			thomson.info("Analyzing picture: ", round(100*y/screen_h), "%")
		end
			
		t = {}
		if h.hull then
			for p in pairs(h:verticesSet()) do
				if p~=Color.black then 
					p[1],p[2],p[3] = p:toRGB()
					table.insert(t, p) 
				end
			end
			shuffle(t)
		else
			table.insert(t, h.points[1])
			table.insert(t, h.points[2])
		end
		
		self.hull = h
		self.pts = t
		
		return self
	end
	function hull:scale(k)
		k = k or 1
		if k~=self.scale_factor then
			k,self.scale_factor = k/self.scale_factor,k
			for _,p in ipairs(self.pts) do
				p[1],p[2],p[3] = p:mul(k):toRGB()
			end
			self.best = nil
		end
		return self
	end
	function hull:isContainedIn(tetra)
		for _,p in ipairs(self.pts) do
			if not tetra:inside(p) then return false end
		end
		return true
	end
	function hull:distToHull(c)
		return self.hull:distToHull(c)
	end
	return hull
end
local hull=newHull(QUANT):analyze()

cube = {}
for i=0,4095 do
	local r,g,b=i%16,math.floor(i/16)%16,math.floor(i/256)
	local c = Color:new(thomson.levels.linear[1+r],
						thomson.levels.linear[1+g],
						thomson.levels.linear[1+b])
	cube[i],c.p,c[1],c[2],c[3] = c,i,c:toRGB()
end

local function subCube(T)
	local t = {}
	for _,i in ipairs(T) do
		for _,j in ipairs(T) do
			for _,k in ipairs(T) do
				table.insert(t, cube[i+16*j+256*k])
			end
		end
	end
	return t
end

local function search2(intens,T,quick,info)
	print('hull scale') io.stdout:flush()
	hull:scale(intens)

	print('build pts') io.stdout:flush()
	local pts={}
	for _,i in ipairs(T) do
		for _,j in ipairs(T) do
			for _,k in ipairs(T) do
				local c = cube[i+16*j+256*k]
				local d = hull:distToHull(c)
				if d>=0 then c[1],c[2],c[3]=c:toRGB(); table.insert(pts, c) end
			end
		end
	end
	
	print('build tetra') io.stdout:flush()
	local tetras,np = {},#pts
	for i=1,np-2 do
		local a=pts[i]
		for j=i+1,np-1 do
			local b=pts[j]
			for k=j+1,np do
				local c = pts[k]
				local t = tetra(a,b,c)
				if t then table.insert(tetras, t) end
			end
		end
	end
	print('sort tetra') io.stdout:flush()
	table.sort(tetras, function(a,b) return a.v > b.v end)
	
	-- make liked list
	print('make chain') io.stdout:flush()
	local first
	for i=#tetras,1,-1 do first,tetras[i].nxt = tetras[i],first end
	tetras = #tetras
	print("TETRA  "..tetras.."        ")
			
	local n,best=0
	while first do
		if hull:isContainedIn(first) then
			best = first
			if quick then first.nxt=nil; break end
		else 
			local t,l = first,{}
			local function inside(p)
				if not p.inside then 
					table.insert(l,p)
					p.inside = first:inside(p)
				end
				return p.inside
			end
			while t.nxt do
				local z = t.nxt
				if 	inside(first, z.a)
				and	inside(first, z.b)
				and inside(first, z.a)
				then
					t.nxt,z.nxt,z.a,z.b,z.c,z.na,z.nb,z.nc,z.v = z.nxt
					n=n+1
		if n%2000==0 then 
			if false and info then
				info(n/tetras)
			else
				thomson.info('Search(',round(100*intens),') ', round(100*n/tetras),'% ',
					(best and math.floor(best.v/1000)	or "n/a"))
			end
		end
				end
				t = z or t
			end
			for _,p in ipairs(l) do p.inside = nil end
		end
		n,first,first.nxt = n+1,first.nxt,nil
		if n%2000==0 then 
			if false and info then
				info(n/tetras)
			else
				thomson.info('Search(',round(100*intens),') ', round(100*n/tetras),'% ',
					(best and math.floor(best.v/1000)	or "n/a"))
			end
		end
	end
	
	print('best=',best) io.stdout:flush()

	return best
end

local function search3(hull,intens,T,quick,info)
	hull:scale(intens)

	local pts={}
	for _,i in ipairs(T) do
		for _,j in ipairs(T) do
			for _,k in ipairs(T) do
				local c = cube[i+16*j+256*k]
				local d = hull:distToHull(c)
				if d>=0 then table.insert(pts, c) end
			end
		end
	end
	-- shuffle(pts)	
	table.sort(pts, function(a,b) 
		local function f(x) return math.abs(x-.5) end
		local function g(x) return math.max(f(x.r),f(x.g),f(x.b)) end
		return g(a)>g(b) end)
	
	local cnt,np,best = 0,#pts
	local tot = np*(np-1)*(np-2)/6
	info = info or function() thomson.info('Search(',round(100*intens),") ",
		 math.floor(100*cnt/tot),'% ',
		 (best and math.floor(best.v/1000) or "n/a")) 
	end
	for i=2,np do
		for j=i+1,np-1 do
			local tet=tetra(pts[i],pts[j])
			for k=j+1,np do
				local t = tet:tetra(pts[k])
				if t and (best==nil or t.v<best.v) then
					if hull:isContainedIn(t) then
						best = {a=t.a,b=t.b,c=t.c,v=t.v}
						if quick then return best end
					elseif false and not quick and (hull.zz==nil or hull.zz.v<t.v) then
						function set(t,f)
							local a,b,c =t.a.p,t.b.p,t.c.p
							for i=0,math.max(a,b,c) do 
								cube[i].zz = f(t,cube[i])
							end
						end
						if hull.zz then set(hull.zz, function() end) end
						hull.zz = t
						print(t.v) io.stdout:flush()
						set(hull.zz, function(t,p) return t:inside(p) end)
					end
				end
				if cnt%2000==0 then info(cnt/tot) end cnt=cnt+1
			end
		end
	end
	if hull.zz then set(hull.zz, function() end) end
	return best
end

local function search(hull,intens,pts,quick,info)
	hull:scale(intens)

	for i=#pts,1,-1 do
		local d = hull:distToHull(pts[i])
		if d<0 then table.remove(pts,i) end
	end
	-- shuffle(pts)	
	table.sort(pts, function(a,b) 
		local function f(x) return math.abs(x-.5) end
		local function g(x) return math.max(f(x.r),f(x.g),f(x.b)) end
		return g(a)>g(b) end)
	
	local cnt,np = 0,#pts
	local tot = np*(np-1)*(np-2)/6
	info = info or function() thomson.info('Search(',round(100*intens),") ",
		 math.floor(100*cnt/tot),'% ',
		 (hull.best and math.floor(hull.best.v/1000) or "n/a")) 
	end
	for i=1,np do
		for j=i+1,np-1 do
			local tet=tetra(pts[i],pts[j])
			for k=j+1,np do
				local t = tet:tetra(pts[k])
				if t 
				and (hull.best==nil or t.v<hull.best.v)
				and hull:isContainedIn(t)
				then
					hull.best = {a=t.a,b=t.b,c=t.c,v=t.v}
					if quick then return hull.best end
				end
				if cnt%2000==0 then info(cnt/tot) end cnt=cnt+1
			end
		end
	end

	return hull.best
end


-- 1: 0,15
-- 2: 0,6,15
-- 3: 0,3,9,15
-- 4: 0,2,6,10,15
-- 5: 0,2,4,8,11,15
-- 6: 0,1,3,6,9,12,15
-- 7: 0,1,3,5,7,10,12,15
-- 8: 0,1,2,4,6,8,10,13,15

local best
local start = os.time()
if #hull.pts==2 then
	local a,b = hull.pts[1],hull.pts[2]
	a = Color.black:euclid_dist2(b)<=Color.black:euclid_dist2(a) and a or b
	b = a:clone():mul(2/3)
	c = a:clone():mul(1/3)
	local function f(p,k) return (thomson.levels.linear2to[round(p)]-1)*k end
	local function g(p) p.p=f(p.r,1) + f(p.g,16) + f(p.b,256); p[1],p[2],p[3]=p:toRGB(); return p end
	best = {a=g(a:clone():mul(1/3)),b=g(a:clone():mul(2/3)),c=g(a:clone())}
else
	local intens,Tfast,Tslow = dim_f,{0,3,9,15},{0,3,9,15} -- {0,1,3,6,9,12,15}
	best = search(hull,intens,subCube(Tfast),true,function(y) thomson.info("Checking: ",math.floor(y*100),"%") end)
	if not best then
		local min,max=1/3,intens
		while max-min>=.01 do
			local med = (max+min)/2
			best = search(hull,med,subCube(Tfast),true,function(y) thomson.info("Adjusting: ", math.floor(min*100),"..",math.floor(max*100)) end)
			if best then min = med else max = med end
		end
		intens = min
	end

	repeat
		best,dim_f,intens = search(hull,intens,subCube(Tslow)),intens,intens*.95
	until best
	
	if FINE_TUNE then
		local function vois2(p)
			local r,g,b,t=p%16,math.floor(p/16)%16,math.floor(p/256),{}
			for i=-1,1 do 
				local x=r+i
				if 0<=x and x<16 then for j=-1,1 do 
					local y=g+j
					if 0<=y and y<16 then for k=-1,1 do
						local z=b+k 
						if 0<=z and z<16 then
							local k=x+y*16+z*256
							if k>0 then table.insert(t,cube[k]) end
						end
					end end
				end end
			end
			return t
		end
		local function vois(a,b,c)
			local t = {}
			for _,p in ipairs(vois2(a)) do t[p] = true end
			for _,p in ipairs(vois2(b)) do t[p] = true end
			for _,p in ipairs(vois2(c)) do t[p] = true end
			local r = {}
			for p in pairs(t) do table.insert(r,p) end
			return r
		end
		local v
		repeat
			v=best.v
			best = search(hull,dim_f,vois(best.a.p, best.b.p, best.c.p),false,function(y) thomson.info("Fine Tuning(",round(100*dim_f),") ",  -- round(y*100),"% ", 
			hull.best and round(hull.best.v/1000) or v) end)
		until v==best.v
	end
	
	hull:scale()
end
if best then
	thomson.setBM4()
	local pal,img = {best.a, best.b, best.c},{}
	table.sort(pal, function(a,b) return a:intensity()<b:intensity() end)
	best.a,best.b,best.c = pal[1],pal[2],pal[3]
	pal = {0, best.a.p, best.b.p, best.c.p}
	if not ORDERED then	
		OstroDither:new(pal,1):dither(320,200,
			function(x,y) return getLinearPixel(x,y) end,
			function(x,y,c) img[x + 320*y] = c+1 end,
			true and false,
			function(x) thomson.info("Converting...",math.floor(x*.5),"%") end)
	else
		local tetra = tetra(best.a,best.b):tetra(best.c)
		if tetra and tetra.a~=best.a then
			pal[2],pal[3] = pal[3],pal[2]
		end
		if not tetra then
			tetra = {}
			tetra.weights = function(self,r,g,b)
				-- local d = ((r/best.c.r)^2 + (g/best.c.g)^2 + (b/best.c.b)^2)^.5
				d = math.max(r/best.c.r,g/best.c.g,b/best.c.b)
				if d<1/3 then
					return 1/3-d,d,0,0
				elseif d<2/3 then
					return 0,2/3-d,d-1/3,0
				else
					return 0,0,1-d,d-2/3
				end
			end
		end
		local b = bayer.double
		local matrix = b(b(b{{1}}))
		local function vac(n,m, fakeunif)
			local function mat(w,h)
				local t={}
				for i=1,h do
					local r={}
					for j=1,w do
						table.insert(r,0)
					end
					table.insert(t,r)
				end
				t.mt={}
				setmetatable(t, t.mt)
				function t.mt.__tostring(t)
					local s=''
					for i=1,#t do
						for j=1,#t[1] do
							if j>1 then s=s..',' end
							s = s..string.format("%9.6f",t[i][j])
						end
						s = s..'\n'
					end
					return s
				end
				return t
			end
			local function rangexy(w,h)
				local l = {}
				for y=1,h do
					for x=1,w do
						table.insert(l,{x,y})
					end
				end
				local size = #l
				for i = size, 2, -1 do
					local j = math.random(i)
					l[i], l[j] = l[j], l[i]
				end
				local i=0
				return function()
					i = i + 1
					if i<=size then
						-- print(i, l[i][1], l[i][2]    )
						return l[i][1], l[i][2]
					else
						-- print("")
					end
				end
			end
			local function makegauss(w,h)
				local w2 = math.ceil(w/2)
				local h2 = math.ceil(h/2)
				local m = mat(w,h)
				for x,y in rangexy(w, h) do
					-- local i = ((x-1+w2)%w)-w/2
					-- local j = ((y-1+h2)%h)-h/2
					-- m[y][x] = math.exp(-40*(i^2+j^2)/(w*h))
					local i = ((x-1+w2)%w)/w-1/2
					local j = ((y-1+h2)%h)/h-1/2
					m[y][x] = math.exp(-40*(i^2+j^2))
				end
				-- print(m)
				return m
			end
			local function countones(m)
				local t=0
				for _,l in ipairs(m) do
					for _,x in ipairs(l) do
						if x>0.5 then t=t+1 end
					end
				end
				return t
			end
			local GAUSS = makegauss(n,m)
			local function getminmax(m, c)
				local min,max,max_x,max_y,min_x,min_y=1e38,0
				local h,w = #m, #m[1]
				local z = mat(w,h)
				for x,y in rangexy(w,h) do
					if math.abs(m[y][x]-c)<0.5 then
						local t=0
						for i,j in rangexy(#GAUSS[1],#GAUSS) do
							if m[1+((y+j-2)%h)][1+((x+i-2)%w)]>0.5 then
								t = t + GAUSS[j][i]
							end
						end
						z[y][x] = t
						if t>max then max,max_x,max_y = t,x,y end
						if t<min then min,min_x,min_y = t,x,y end
					end
				end
				-- print(m)
				-- print(z)
				-- print(max,max_y,max_x, c)
				-- print(min,min_y,min_x)
				return min_x, min_y, max_x, max_y
			end
			local function makeuniform(n,m)
				local t = mat(n,m)
				for i=0,math.floor(m*n/10) do
					t[math.random(m)][math.random(n)] = 1
				end
				for i=1,m*n*10 do
					local a1,b1,x1,y1 = getminmax(t,1)
					t[y1][x1] = 0
					local x2,y2,a2,b2 = getminmax(t,0)
					t[y2][x2] = 1
					-- print(t)
					if x1==x2 and y1==y2 then break end
				end
				return t
			end
			if fakeunif then
				function makeuniform(n,m)
					local t = mat(n,m)
					t[1][1] = 1
					t[math.floor(2+m/2)][math.floor(1+n/2)] = 1
					return t
				end
			end
			local vnc = mat(n,m)
			local m2  = mat(n,m)
			local m1  = makeuniform(n,m)
			local rank = countones(m1)
			for x,y in rangexy(n,m) do m2[y][x] = m1[y][x] end
			for r=rank,1,-1 do
				local a,b,x,y = getminmax(m1,1)
				m1[y][x] = 0
				-- print(m1)
				vnc[y][x] = r
			end
			for r=rank+1,n*m do
				local x,y,a,b = getminmax(m2,0)
				m2[y][x] = 1
				-- print(m2)
				vnc[y][x] = r
			end
			-- print(vnc)
			return vnc
		end
		-- matrix = vac(8,8,true)
		local n,m,nm = #matrix,#matrix[1],#matrix*#matrix[1]

		local cache = {}
		local base = 64
		local coef = (base-1)/Color.ONE
		for y=0,199 do for x=0,319 do
			local p = getLinearPixel(x,y)
			local r,g,b = p:toRGB()
			r,g,b = round(r*coef,g*coef,b*coef)
			local k = r + g*base + b*base^2
			local s = cache[k]
			if not s then
				local w0,wa,wb,wc = tetra:weights(r/coef,g/coef,b/coef)
				w0 = w0<0 and 0 or w0
				wa = wa<0 and 0 or wa
				wb = wb<0 and 0 or wb
				wc = wc<0 and 0 or wc
				local wt = w0 + wa + wb + wc
				wa = wa>0 and round(nm*wa/wt) or 0
				wb = wb>0 and round(nm*wb/wt) or 0
				wc = wc>0 and round(nm*wc/wt) or 0
				w0 = nm - wa - wb - wc 
				if w0<0 then 
					if wa<math.min(wb,wc) then wa,w0=wa+w0,0 end
					if wb<math.min(wa,wc) then wb,w0=wb+w0,0 end
					if wc<math.min(wb,wa) then wc,w0=wc+w0,0 end
				end
				s = ""
				for i=1,w0 do s=s..string.char(1) end
				for i=1,wa do s=s..string.char(2) end
				for i=1,wb do s=s..string.char(3) end
				for i=1,wc do s=s..string.char(4) end
				cache[k] = s
			end
			local d = matrix[1+(x%n)][1+(y%m)]
			img[x + 320*y] = s:byte(d)
		end thomson.info("Converting...",round(y*.5),"%") end
	end
		
	best = {
		0,1,2,3,
		n=-1,
		find = function(self,a)
			local function f(n)
				if n==0 then
					local c0,c1,c2,t={},{},{0,0}
					if not self.cost then
						c = {} 
						for i=0,255 do c[i*0x10101] = 0 end
						self.cost = c
						self.t1 = {[0]=0,[1]=1,[2]=0,[3]=1}
						self.t2 = {[0]=0,[1]=0,[2]=1,[3]=1}
					end
					for p=-1,318,8 do c1[1],c1[2] = 1,1
						repeat        c0[1],c0[2] = 0,0
							for i,m in ipairs{128,64,32,16,8,4,2,1} do
								t = a[img[p+i]]
								c0[1],c0[2] = c0[1]+self.t1[t]*m,c0[2]+self.t2[t]*m
							end
							n,c0,c1,c2,p = n 
								+ (self.cost[c0[1]*0x10000+c1[1]*0x100+c2[1]] or 1)
								+ (self.cost[c0[2]*0x10000+c1[2]*0x100+c2[2]] or 1),
								c1,c2,c0,p+320
						until p>=63999
						if n>best.n or n==best.n and a[1]~=0 then return end
					end
					-- n=-n
					if 	n<self.n 
					or	n==self.n and a[1]==0 
					then
						self.n = n; for i,v in ipairs(a) do self[i]=v end
					end
				else
					for i=1,n do
						a[n],a[i] = a[i],a[n]
						f(n-1)
						a[n],a[i] = a[i],a[n]
					end
				end
			end
			f(#a)
		end
	}
	best:find{3,0,1,2}
	for p=0,63999 do thomson.pset(p%320,math.floor(p/320),best[img[p]]) end
	pal[best[1]+1],pal[best[2]+1],pal[best[3]+1],pal[best[4]+1] = 
		pal[1],pal[2],pal[3],pal[4]
	
	if CMDLINE then
		local z=statusmessage
		statusmessage=function(msg)
			if msg=="done" then 
				msg=msg.."(".. 
					round(100*(os.time()-start))/100 .. "s, " ..
					round(100*dim_f) .. 
					(__maxi and "*" or "") ..
					")"
			end
			z(msg)
		end
	end
	thomson.palette(0,pal)
	for i=4,15 do thomson.palette(i,0) end
	
	-- refresh screen
	setpicturesize(320,200)
	thomson.updatescreen()
	-- finalizepicture()

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
else
	error('Internal bug: conversion failed')
end

-- error(os.time()-start)