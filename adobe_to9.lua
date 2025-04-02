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
local ATT = .9 -- MAXCOL>8 and 0.9 or 1
local ATT2 = 0.7

local dither = {{1,2},{3,4}}
local DEBUG =  false
-- dither = {{1,3},{4,2}}
-- dither = {{1,2},{3,4}}
dither = bayer.double(dither)
dither = {{1,3,2,4},{9,11,10,12},{5,7,6,8},{13,15,14,16}} -- pas mal
-- dither = {{1,3,2,4},{11,9,11,12,10},{5,7,6,8},{15,13,16,14}} -- pas mal
-- dither = {{1,5,2,6},{9,13,10,14},{3,7,4,8},{11,15,12,16}}

-- dither = {{1,7,2,8},{9,15,10,16},{5,3,6,4},{13,11,14,12}} -- pas mal

dither = {{1,2},{4,3}} ATT=.7 -- <<<<
-- dither = {{1,2},{3,4}}
-- dither = {{1}}

-- dither = bayer.double(dither)
-- dither = {{1,2,3},{4,5,7},{6,8,9}}
-- dither = bayer.double{{1}}
-- dither = {{1,2},{3,4}} 	
-- dither = {{1,1},{3,3}}
-- dither = {{1,3,2,4},{5,7,6,8}}
-- dither = {{1,2,4},{3,5,6}}

-- dither = {{1,2,5,6},{4,3,8,7}}
unpack = unpack or table.unpack

dither = bayer.double(dither)
dither = bayer.double(dither)
-- dither = bayer.double(dither)
-- dither = bayer.double(dither)
-- dither = {{1,3},{4,2}}
-- dither ={{13, 7, 8,14,17,21,22,18},
         -- { 6, 1, 3, 9,28,31,29,23},
		 -- { 5, 2, 4,10,27,32,30,24},
		 -- {16,12,11,15,20,26,25,19},
		 -- {17,21,22,18,13, 7, 8,14},
         -- {28,31,29,23, 6, 1, 3, 9},
		 -- {27,32,30,24, 5, 2, 4,10},
		 -- {20,26,25,19,16,12,11,15}}
		 
	-- dither = {
		-- { 7,13,11, 4},
		-- {12,16,14, 8},
		-- {10,15, 6, 2},
		-- { 5, 9, 3, 1} 
	-- }
	
local dx,dy=#dither,#dither[1]

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



-- TO7/70 MO5 mode
local red = ColorReducer:new():analyzeWithDither(320,200,
	function(x,y) return getLinearPixel(x,y):mul(Color.ONE) end,
    function(y)
		thomson.info("Collecting stats...",math.floor(y*100),"%")
	end)
local palette = red
	-- :boostBorderColors()
	:boostBorderColors()
	:buildPalette(16)
thomson.setMO5()
thomson.palette(0, palette)


-- get thomson palette pixel (linear, 0-1 range)
local linearPalette = {}
function linearPalette.get(i)
	local p = linearPalette[i]
	if not p then
		local pal = thomson.palette(i-1)
		if pal==nil then error(i) end
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

function dist2(c1,c2)
	return c1:euclid_dist2(c2)
	-- return c1:dE2fast(c2)
	-- return c1:dE2000(c2)^2
end

-- closest color in the palette
linearPalette.proxCache={}
function linearPalette.index(c) 
	local eps = -.02
	if c.r<eps then c.r = eps elseif c.r>1-eps then c.r=1-eps end
	if c.g<eps then c.g = eps elseif c.g>1-eps then c.g=1-eps end
	if c.b<eps then c.b = eps elseif c.b>1-eps then c.b=1-eps end
	
	function f(x)
		-- return math.floor(.5+32*(x<0 and 0 or x>1 and 1 or x)^.45)
		return math.floor(.5+32*x^.45)
	end
	local k = string.char(f(c.r), f(c.g), f(c.b))
	local i = linearPalette.proxCache[k]
	if not i then
		i = 1
		if c.r>.5 then i=i+1 end
		if c.g>.5 then i=i+2 end
		if c.b>.5 then i=i+4 end
		local d = dist2(linearPalette.get(i),c)
		for e=9,MAXCOL do
		-- local d = 1e300; for e=1,MAXCOL do
			local t = dist2(linearPalette.get(e),c)
			if t<d then i,d = e,t end
		end
		linearPalette.proxCache[k] = i
	end
	return i
end

tetras = nil
if tetras == nil then
	local EPS,push = 1e-12,table.insert
	local function tetra(a,b,c,d) 
		local function sub(a,b) return {a[1]-b[1],a[2]-b[2],a[3]-b[3]} end
		local function mul(a,x) return {a[1]*x, a[2]*x, a[3]*x} end
		local function dot(a,b) return a[1]*b[1]+a[2]*b[2]+a[3]*b[3] end
		local function prd(a,b) return {a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1]} end
		local function nrm(a) return mul(a,dot(a,a)^-.5) end
		--  |d
		--  |____c
		-- a\
		--   \b
		local ba,ca,da = sub(b,a),sub(c,a),sub(d,a)
		local na,nb,nc,nd = 
			prd(sub(d,b),sub(c,b)),
			prd(ca,da),
			prd(da,ba),
			prd(ba,ca)
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
			if t<=EPS then return 1,0 end
			t = dot(sub(p,v0),v10)/t
			t = t<=EPS and 0 or t>1 and 1 or t
			return 1-t,t
		end
		local coord = function(p)
			local pa,pb = sub(p,a),sub(p,b)
			local x,y,z,t,D = dot(pb,na),dot(pa,nb),dot(pa,nc),dot(pa,nd)
			if x>=-EPS and y>=-EPS and z>=-EPS and t>=-EPS then
				x,y,z,t = x<=EPS and 0 or x, y<=EPS and 0 or y, z<=EPS and 0 or z, t<=EPS and 0 or t
				D = x+y+z+t; D=D>0 and 1/D or 0
				return x*D,y*D,z*D,t*D
			end
			return nil
		end
		local t = {v=0,a=a,b=b,c=c,d=d,
		basic_coord = function(p)
			local pa,pb = sub(p,a),sub(p,b)
			return dot(pb,na),dot(pa,nb),dot(pa,nc),dot(pa,nd)
		end,
		coord=(a.__supertriangle or b.__supertriangle or c.__supertriangle or d.__supertriangle) and function(p)
			local x,y,z,t = coord(p)
			if x then
				-- print("super:", x,y,z,t)
				-- print(a[1],b[1],c[1],d[1])
				-- print(a[2],b[2],c[2],d[2])
				-- print(a[3],b[3],c[3],d[3])
				
				x,y,z,t = 0,0,0,0
				if a.__supertriangle then
					if b.__supertriangle then
						if c.__supertriangle then
							t = 1
						elseif d.__supertriangle then
							z = 1
						else
							z,t = proj2(p,c,d)
						end
					elseif c.__supertriangle then
						if d.__supertriangle then
							y = 1
						else
							y,t = proj2(p,b,d)
						end
					elseif d.__supertriangle then
						y,z = proj2(p,b,c)
					else
						y,z,t = proj3(p,b,c,d)
					end
				elseif b.__supertriangle then
					if c.__supertriangle then
						if d.__supertriangle then
							x = 1
						else
							x,t = proj2(p,a,d)
						end
					elseif d.__supertriangle then
						x,z = proj2(p,a,c)
					else
						x,z,t = proj3(p,a,c,d)
					end
				elseif c.__supertriangle then
					if d.__supertriangle then
						x,y = proj2(p,a,b)
					else
						x,y,t = proj3(p,a,b,d)
					end
				elseif d.__supertriangle then
					x,y,z = proj3(p,a,b,c)
				end
			end
			return x,y,z,t
		end	or coord}
		t.v = dot(ba,na)
		if t.v>EPS         then na = mul(na,-1) else t.v = -t.v end
		if dot(ba,nb)<-EPS then nb = mul(nb,-1) end
		if dot(ca,nc)<-EPS then nc = mul(nc,-1) end
		if dot(da,nd)<-EPS then nd = mul(nd,-1) end
		return t
	end
	local function BowyerWatson()
		-- https://en.wikipedia.org/wiki/Bowyer%E2%80%93Watson_algorithm
		local push = table.insert
		local function sub(U,V) return {U[1]-V[1],U[2]-V[2],U[3]-V[3]} end
		local function dot(U,V) return U[1]*V[1] + U[2]*V[2] + U[3]*V[3] end
		local function dist2(U,V) local T=sub(U,V) return dot(T,T) end
		local function det(M)
			local det,n,abs = 1,#M,math.abs
			for i=1,n do
				for j=i+1,n do
					if abs(M[j][i])>abs(M[i][i]) then
						det,M[i],M[j] = -det,M[j],M[i]
					end
				end
				if M[i][i]==0 then return 0 end
				for j=i+1,n do
					local c = M[j][i]/M[i][i]
					for k=i,n do
						M[j][k] = M[j][k] - c*M[i][k]
					end
				end
			end
			for i=1,n do det = det*M[i][i] end
			return det
		end
		local function circumSphere(tetra)
			local sphere = tetra.__circumSphere
			if not sphere then
				-- https://mathworld.wolfram.com/Circumsphere.html
				local x1,y1,z1 = tetra[1][1],tetra[1][2],tetra[1][3]
				local x2,y2,z2 = tetra[2][1],tetra[2][2],tetra[2][3]
				local x3,y3,z3 = tetra[3][1],tetra[3][2],tetra[3][3]
				local x4,y4,z4 = tetra[4][1],tetra[4][2],tetra[4][3]
				local a =   det{{x1, y1, z1, 1},
								{x2, y2, z2, 1},
								{x3, y3, z3, 1},
								{x4, y4, z4, 1}}
				if math.abs(a)<=EPS then return nil end -- coplanar
				local s1 = x1^2 + y1^2 + z1^2
				local s2 = x2^2 + y2^2 + z2^2
				local s3 = x3^2 + y3^2 + z3^2
				local s4 = x4^2 + y4^2 + z4^2
				local Dx =  det{{s1, y1, z1, 1},
								{s2, y2, z2, 1},
								{s3, y3, z3, 1},
								{s4, y4, z4, 1}}              		
				local Dy = -det{{s1, x1, z1, 1},
								{s2, x2, z2, 1},
								{s3, x3, z3, 1},
								{s4, x4, z4, 1}}              		
				local Dz =  det{{s1, x1, y1, 1},
								{s2, x2, y2, 1},
								{s3, x3, y3, 1},
								{s4, x4, y4, 1}}    
				local c =   det{{s1, x1, y1, z1},
								{s2, x2, y2, z2},
								{s3, x3, y3, z3},
								{s4, x4, y4, z4}}
				local ia2 = 1/(2*a)
				sphere = {{Dx*ia2, Dy*ia2, Dz*ia2},(Dx^2+Dy^2+Dz^2 - 4*a*c)*ia2^2}
				tetra.__circumSphere = sphere
			end
			return sphere[1],sphere[2]
		end
		local function boundary(tetras)
			local code={n=0}
			local encode = function(pts)
				local t = {}
				for _,pt in ipairs(pts) do
					local k = code[pt]
					if not k then 
						k = code.n+1
						code[k],code[pt],code.n = pt,k,k
					end
					table.insert(t,k)
				end
				table.sort(t)
				return table.concat(t,',')
			end
			local function decode(str)
				local t,i,j = {},1,str:find(',')
				while j do
					push(t, code[tonumber(str:sub(i,j-1))])
					i,j = j+1,str:find(',',j+1)
				end
				push(t, code[tonumber(str:sub(i))])
				return t
			end
			local set = {}
			local function inc(pts)
				local k = encode(pts)
				set[k] = (set[k] or 0)+1
			end
			for T in pairs(tetras) do
				inc{T[1],T[2],T[3]}
				inc{T[1],T[2],T[4]}
				inc{T[1],T[3],T[4]}
				inc{T[2],T[3],T[4]}
			end
			local t = {}
			for k,v in pairs(set) do
				if v==1 then table.insert(t, decode(k)) end
			end
			return t
		end
		return {
			vertices = {},
			cleanup = function(self)
				local facets = self.facets or {}
				for i=#facets,1,-1 do
					local tetra = facets[i]
					tetra.__circumSphere = nil
					if tetra[1].__supertriangle
					or tetra[2].__supertriangle
					or tetra[3].__supertriangle
					or tetra[4].__supertriangle
					then table.remove(facets,i) end
				end
			end,
			add = function(self,pt) 
				local vertices,facets = self.vertices,self.facets
				if vertices then
					push(vertices, pt)
					if #vertices==4 then
						for i=1,4 do vertices[i].__supertriangle = true end
						self.facets = { {vertices[1],vertices[2],vertices[3],vertices[4]} }
						self.vertices = nil
					end
				else
					-- print("adding ", pt[1], pt[2], pt[3], pt[4])
					local badTetras = {}
					for _,tetra in ipairs(facets) do
						local c,r2 = circumSphere(tetra)
						if dist2(c,pt)<=r2 then badTetras[tetra] = true end
					end
					local poly = boundary(badTetras)
					for i=#facets,1,-1 do
						if badTetras[facets[i]] then table.remove(facets,i) end
					end
					for i,tri in ipairs(poly) do
						push(tri,pt)
						push(facets, tri)	
						if not circumSphere(tri) then
							for j=1,i do table.remove(facets,#facets) end
							for f in pairs(badTetras) do push(facets,f) end
							local pert = {}
							for k,v in pairs(pt) do pert[k]=v end
							for j=1,3 do pert[j] = pert[j]*(1 + (pert[j]>=1 and -1 or 1)*math.random()/100000) end
							-- print("pert", pt[1],pt[2],pt[3],"\n=>",pert[1],pert[2],pert[3])
							return self:add(pert)
						end
					end
				end
				return self
			end
		}
	end
	local h = BowyerWatson():add{-2,-2,-2}:add{10,-2,-2}:add{-2,10,-2}:add{-2,-2,10}
	for i=1,MAXCOL do 
		local pal = linearPalette.get(i)
		h:add{pal.r, pal.g, pal.b, index = i} 
	end
	h:cleanup()
	tetras = {}
	for _,F in ipairs(h.facets) do
		local t = tetra(F[1],F[2],F[3],F[4])
		push(tetras, t) 
	end	
	local function mark_opp(tetras)
		local code,tet={n=0},{}
		local encode = function(pts)
			local t = {}
			for _,pt in ipairs(pts) do
				local k = code[pt]
				if not k then 
					k = code.n+1
					code[pt],code.n = pt,k,k
				end
				table.insert(t,k)
			end
			table.sort(t)
			return table.concat(t,',')
		end
		local process = function(tetra, a,b,c, d)
			local k = encode(a,b,c)
			local t = tet[k]
			if t then
				t.tet[t.face] = tetra
				tetra[d] = t.tet
			else
				tet[k] = {face=d, tet=tetra}
			end
		end
		local triangles = {}
		for i,tetra in ipairs(tetras) do
			tetra.no = i
			process(tetra, tetra.a, tetra.b, tetra.c, "opp_d")
			process(tetra, tetra.a, tetra.b, tetra.d, "opp_c")
			process(tetra, tetra.a, tetra.c, tetra.d, "opp_b")
			process(tetra, tetra.b, tetra.c, tetra.d, "opp_a")
		end
	end	
	-- mark_opp(tetras)
	h = nil
end

-- adobe dithering
linearPalette.ditherCache={}
function linearPalette.dither(c)
	local function f(x) return math.floor(.5*0+24*math.max(0,x)^.45) end
	local k = string.char(f(c.r),f(c.g),f(c.b))
	local s = linearPalette.ditherCache[k]
	
	if not s then
		local p = {c.r, c.g, c.b}
		local n = dx*dy
		for i,tetra in ipairs(tetras) do
			local x,y,z,t = tetra.coord(p)
			if x then 
				if i>4 then table.insert(tetras,1,table.remove(tetras,i)) end
				local sorted = {
					{x,tetra.a.index},{y,tetra.b.index},
					{z,tetra.c.index},{t,tetra.d.index}
				}
				-- print(tetra.a.index, tetra.b.index, tetra.c.index, tetra.d.index)
				if tetra.a.index>MAXCOL then error(tetra.a.index) end
				if tetra.b.index>MAXCOL then error(tetra.b.index) end
				if tetra.c.index>MAXCOL then error(tetra.c.index) end
				if tetra.d.index>MAXCOL then error(tetra.d.index) end
				
				table.sort(sorted, function(a,b) return a[1]>b[1] end)
				x,y,z,t = sorted[1][1],sorted[2][1],sorted[3][1],sorted[4][1]
				x,y,z,t = math.min(x*n,n),math.min((x+y)*n,n),math.min((x+y+z)*n,n),{}
				local push = table.insert
				while #t<x do push(t,sorted[1][2]) end
				while #t<y do push(t,sorted[2][2]) end
				while #t<z do push(t,sorted[3][2]) end
				while #t<n do push(t,sorted[4][2]) end
				local function f(x) return x:intensity() end
				table.sort(t, function(a,b) return f(linearPalette.get(a))<f(linearPalette.get(b)) end)
				s = string.char(unpack(t))
				linearPalette.ditherCache[k] = s
				break
			end
		end
	end
	
	if not s then
		if not linearPalette.matrix then
			linearPalette.matrix = {}
			for i=1,MAXCOL-1 do
				linearPalette.matrix[i] = linearPalette.matrix[i] or {}
				local ci = linearPalette.get(i)
				for j=i+1,MAXCOL do
					local cj = linearPalette.get(j)
					local dj = cj:sub(ci)
					local n2 = dj.r*dj.r + dj.g*dj.g + dj.b*dj.b
					linearPalette.matrix[i][j] = {dj = dj, nj2 = n2}
				end
			end
		end
		local dm,a,b,g = 1e300
		for i=1,MAXCOL-1 do
			local ci = linearPalette.get(i)
			local di = c:clone():sub(ci)
			local ni = math.sqrt(di.r*di.r + di.g*di.g + di.b*di.b)
			if ni==0 then
				a,b,g = i,i,1
				break
			else 
				for j=i+1,MAXCOL do
					local mtx = linearPalette.matrix[i][j]
					local dj = mtx.dj
					-- print(di:tostring(), dj:tostring())
					local f =  (di.r*dj.r + di.g*dj.g + di.b*dj.b)/mtx.nj2
					f = f<0 and 0 or f>1 and 1 or f
					-- f = f<.5 and 0 or 1
					local p = ci:clone():add(dj,f)
					local d = dist2(c,p)
					-- print(i,j,f,p:tostring(), d)
					if d<dm then dm,a,b,g = d,i,j,f end
				end
			end
		end
		-- print(a,b,g,dm)
		-- print(c:tostring())
		-- print(linearPalette.get(a):tostring())
		-- print(linearPalette.get(b):tostring())
		local gg,t = g*dx*dy,{}
		for k=1,dx*dy do t[k] = k>gg and a or b end
		local function f(x) return x:intensity() end
		table.sort(t, function(a,b) return f(linearPalette.get(a))<f(linearPalette.get(b)) end)
		local unpack = unpack or table.unpack
		s = string.char(unpack(t))
		linearPalette.ditherCache[k] = s
	end

	if not s then
		local t,d = {},Color:new()
		local function module(c)
			-- return math.abs(c.r) + math.abs(c.g) + math.abs(c.b)
			-- return c.r*c.r + c.g*c.g + c.b*c.b
			-- return math.max(math.abs(c.r), math.abs(c.g), math.abs(c.b))
			return c.r*c.r + c.g*c.g + c.b*c.b
			-- local r,g,b = math.abs(c.r),math.abs(c.g),math.abs(c.b)
			-- local m = math.max(r,g,b)*.9
			-- r,g,b = r<m and 0 or r,g<m and 0 or g,b<m and 0 or b
			-- return r*r + g*g + b*b
		end
		for i=1,dx*dy do
			local k=1
			-- if c.r>.5 then k=k+1 end
			-- if c.g>.5 then k=k+2 end
			-- if c.b>.5 then k=k+4 end
			local kk = linearPalette.get(k):add(d)
			local dm = module(kk)
			for j=2,MAXCOL do
				local e = linearPalette.get(j):add(d)
				-- local t = 2*e.r*e.r + 4*e.g*e.g + e.b*e.b
				local t = module(e)
				if t<dm then dm,k,kk = t,j,e end
			end
			t[i],d = k,kk:sub(c)
		end
		-- local function f(x) return math.abs(x.r)^.5 + math.abs(x.g)^.5 + math.abs(x.b)^.5 end
		local function f(x) return x:intensity() end
		table.sort(t, function(a,b) return f(linearPalette.get(a))<f(linearPalette.get(b)) end)
		s = string.char(unpack(t))
		linearPalette.ditherCache[k] = s
	end
	
	if not s then
		local t = {}
		local d = Color:new()
		for i=1,dx*dy do
			local j = linearPalette.index(c:clone():add(d,ATT2))
			t[i] = j
			d:sub(linearPalette.get(j):sub(c))
		end
		table.sort(t, function(a,b) return linearPalette.get(a):intensity()>linearPalette.get(b):intensity() end)
		s = string.char(unpack(t))
		linearPalette.ditherCache[k] = s
	end
	return s
end

-- distance between two colors
local distance = {}
function distance.between(c1,c2)
	local k = c1..','..c2
	local d = distance[k]
	if not d then
		d = dist2(linearPalette.get(c1),linearPalette.get(c2))
		distance[k] = d
	end
	-- if not d then
		-- local x = linearPalette.get(c1):sub(linearPalette.get(c2))
		-- local c,c1,c2,c3=1.8,8,11,8
		-- local f = function(c,x) return math.abs(x)*c end
		-- d = f(c1,x.r)^c + f(c2,x.g)^c + f(c3,x.b)^c
		-- distance[k] = d
	-- end
	return d
end

-- compute a set of best couples for a given histogram
local best_couple = {}
function best_couple:init()
	self.cache = {}
	self.n = 0
	for i=1,MAXCOL do 
		self.cache[8^(i+1)] = {c1=1,c2=i}
		self.n = self.n+1 
	end
	for i=1,MAXCOL-1 do 
		for j=i+1,MAXCOL do
			for k=1,7 do
				self.cache[k*8^i + (8-k)*8^j] = {c1=j,c2=i} 
				self.n = self.n+1
			end
		end
	end
end
best_couple:init()
function best_couple:get(h)
	local best_found = self.cache[h]
	if not best_found then
		local dm=1000000
		for i=1,MAXCOL-1 do
			for j=i+1,MAXCOL do
				local d,k,p,n=0,h/8,0
				repeat
					p,n,k = p+1,k%8,math.floor(k/8)
					if p==17 then error(string.format("%20.0f %20.0f %20.0f\n", k,  h, h/8)) end
					local d1,d2=distance.between(p,i),distance.between(p,j)
					d = d + n*(d1<d2 and d1 or d2)
					if d>=dm then break end
				until k==0
				if d<dm then dm,best_found=d,{c1=i,c2=j} end
			end
		end
	
		if self.n>65535 then 
			print()
			print('flush')
			print()
			
			-- keep memory usage low
			self:init()
		end 
		self.cache[h] = best_found
		self.n        = self.n+1
	end
	return best_found
end

if DEBUG then
	local tab = {}
	for y=0,199 do
		for x=0,319 do
			local d=dither[1+(y%dx)][1+(x%dx)]
			-- local p=getLinearPixel(x,y)
			local p=Color:new(0,y/200,z/320)
			local c=linearPalette.dither(p):byte(d)
			table.insert(tab,c-1)
		end
	end
	setpicturesize(thomson.w,thomson.h)
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
	for i=0,63999 do
		putpicturepixel(i%320,math.floor(i/320),tab[i+1])
	end
	-- finalizepicture()
	return 
end

-- print(linearPalette.dither(Color:new(0,.1,0)))
-- os.exit(0)


-- convert picture
local err = {}
for x=-1,320 do err[x] = Color:new() end
for y = 0,199 do
	for x=-1,320 do err[x]:mul(0) end
	for x = 0,319,8 do
		local h,q = 0,{} -- histo, expected color
		for z=x,x+7 do
			local d=dither[1+(y%dx)][1+(z%dx)]
			local p=getLinearPixel(z,y):add(err[z])
			local c=linearPalette.dither(p):byte(d)
			if c>MAXCOL then error(c .. ' //// ' .. p:tostring()) end
			table.insert(q,c)			
			h = h + 8^c
		end
		
		local best_found = best_couple:get(h)
		local c1,c2 = best_found.c1,best_found.c2
		
		-- thomson.pset(x,y,c1-1)
		-- thomson.pset(x,y,-c2)
		
		for k=0,7 do
			local z=x+k
			local q=q[k+1]
			local p=distance.between(q,c1)<distance.between(q,c2) and c1 or c2
			local d=
			linearPalette.get(q)
				-- getLinearPixel(z,y)
				:sub(linearPalette.get(p))
			-- err[z]:add(d,.9)
			ATT=.9
			err[z]  :add(d, ATT*.5)
			err[z-1]:add(d, ATT*.2)
			err[z+1]:add(d, ATT*.2)
			thomson.pset(z,y,p==c1 and c1-1 or -c2)
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

