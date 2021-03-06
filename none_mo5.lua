-- ostro_mo5.lua : converts a color image into a 
-- MO5 image (16 fixed colors with color clash) 
-- using Ostromoukhov's error diffusion algorithm.
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
run('lib/ostromoukhov.lua')

local dith=OstroDither:new()
local tmp=dith.setLevelsFromPalette
dith.setLevelsFromPalette = function(self)
	tmp(self)
	self.attenuation=0
end
dith:dither40cols(function(w,h,getLinearPixel)
	local pal={}
	for i=0,15 do pal[i+1] = thomson.palette(i) end
	return pal
end)