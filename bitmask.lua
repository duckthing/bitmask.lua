--[[
Copyright (C) 2025 duckthing

This software is provided 'as-is', without any express or implied
warranty.  In no event will the authors be held liable for any damages
arising from the use of this software.

Permission is granted to anyone to use this software for any purpose,
including commercial applications, and to alter it and redistribute it
freely, subject to the following restrictions:

1. The origin of this software must not be misrepresented; you must not
   claim that you wrote the original software. If you use this software
   in a product, an acknowledgment in the product documentation would be
   appreciated but is not required.
2. Altered source versions must be plainly marked as such, and must not be
   misrepresented as being the original software.
3. This notice may not be removed or altered from any source distribution.
--]]
local ffi = require "ffi"
local bit = require "bit"

local band, bor, bnot, brshift, blshift =
	bit.band, bit.bor, bit.bnot, bit.rshift, bit.lshift
local min, max, ceil, floor = math.min, math.max, math.ceil, math.floor

---@class Bitmask
local Bitmask = {}
local BitmaskMT = {
	__index = Bitmask
}

---Normalizes the parameters to prevent going out of bounds
---@param dest Bitmask
---@param source Bitmask
---@param dx integer
---@param dy integer
---@param sx integer
---@param sy integer
---@param sw integer
---@param sh integer
---@return integer
---@return integer
---@return integer
---@return integer
---@return integer
---@return integer
local function normalizeParams(dest, source, dx, dy, sx, sy, sw, sh)
	-- Based off the Love2D source code, but modified to work in Lua.
	-- https://github.com/love2d/love/blob/4770ca009dcc9f223dd934d3f440b9defdc1db48/src/modules/image/ImageData.cpp#L641

	--[[
	Copyright (c) 2006-2024 LOVE Development Team

	 This software is provided 'as-is', without any express or implied
	 warranty.  In no event will the authors be held liable for any damages
	 arising from the use of this software.

	 Permission is granted to anyone to use this software for any purpose,
	 including commercial applications, and to alter it and redistribute it
	 freely, subject to the following restrictions:

	 1. The origin of this software must not be misrepresented; you must not
	    claim that you wrote the original software. If you use this software
	    in a product, an acknowledgment in the product documentation would be
	    appreciated but is not required.
	 2. Altered source versions must be plainly marked as such, and must not be
	    misrepresented as being the original software.
	 3. This notice may not be removed or altered from any source distribution.
 	]]

	local dstW, dstH = dest.width, dest.height
	local srcW, srcH = source.width, source.height
	if dx < 0 then
			sw = sw + dx
			sx = sx - dx
			dx = 0
	end
	if dy < 0 then
		sh = sh + dy
		sy = sy - dy
		dy = 0
	end
	if sx < 0 then
		sw = sw + sx
		dx = dx - sx
		sx = 0
	end
	if sy < 0 then
		sh = sh + sy
		dy = dy - sy
		sy = 0
	end
	if dx + sw > dstW then
		sw = dstW - dx
	end
	if dy + sh > dstH then
		sh = dstH - dy
	end
	if sx + sw > srcW then
		sw = srcW - sx
	end
	if sy + sh > srcH then
		sh = srcH - sy
	end
	return dx, dy, sx, sy, sw, sh
end

---Creates a new BitMask
---@param width integer
---@param height integer
---@return Bitmask
function Bitmask.new(width, height)
	---@class Bitmask
	local self = {}
	local bytes = ceil(width * height * 0.125)

	self.data = ffi.new("uint8_t[?]", bytes)
	self.width, self.height = width, height
	self._active = false

	---@type boolean # If the bitmask changed since last boundary check, this should be true
	self._dirty = false

	---@type integer, integer, integer, integer, integer, integer # Cached bitmask boundary, use :getBounds() instead
	self._bleft, self._btop, self._bright, self._bbottom, self._bw, self._bh =
		0, 0, 0, 0, 0, 0

	return setmetatable(self, BitmaskMT)
end

---(Recalculates if dirty, and) returns the bounds of the true bits
---@return integer left
---@return integer top
---@return integer right
---@return integer bottom
---@return integer width
---@return integer height
function Bitmask:getBounds()
	-- In case you're wondering how to get the width and height from this:
	-- w, h =
	--    right - left + 1,
	--    bottom - top + 1
	-- This is also returned as the last 2 parameters
	-- If w or h is zero, this mask is empty

	if not self._dirty then
		-- No changes, return cached bounds
		return self._bleft, self._btop, self._bright, self._bbottom, self._bw, self._bh
	end

	-- The bitmask changed since last boundary check
	-- Update the bounds, then return them
	self._dirty = false

	local w, h = self.width, self.height
	local left = -1
	local top = 0
	local right = -1
	local bottom = 0

	-- Top boundary
	for y = 0, h - 1 do
		for x = 0, w - 1 do
			if self:get(x, y) then
				top = y
				goto checkTop
			end
		end
	end
	::checkTop::

	-- Bottom boundary
	for y = h - 1, 0, -1 do
		for x = 0, w - 1 do
			if self:get(x, y) then
				bottom = y
				goto checkBottom
			end
		end
	end
	::checkBottom::

	-- Left boundary
	for x = 0, w - 1 do
		for y = top, bottom do
			if self:get(x, y) then
				left = x
				goto checkLeft
			end
		end
	end
	::checkLeft::

	-- Right boundary
	for x = w - 1, 0, -1 do
		for y = top, bottom do
			if self:get(x, y) then
				right = x
				goto checkRight
			end
		end
	end
	::checkRight::

	if left == -1 then
		-- Invalid boundary
		left, top = 0, 0
		right, bottom = -1, -1
	end

	self._bleft, self._btop, self._bright, self._bbottom, self._bw, self._bh =
		left, top, right, bottom,
		right - left + 1,
		bottom - top + 1

	return self._bleft, self._btop, self._bright, self._bbottom, self._bw, self._bh
end

---Moves all of the bits a certain direction. Positive X makes the first X bits 0.
---@param x integer
---@param y integer
function Bitmask:shift(x, y)
	if x > 0 then
		-- Moving to the right (X is positive)
		-- Move these bits to the right, but go from right to left
		for i = self.width - 1, max(x - 1, 0), -1 do
			for j = 0, self.height - 1 do
				self:set(i, j, self:get(i - x, j))
			end
		end
		-- The first X bits are zeroed
		for i = 0, min(x, self.width) - 1 do
			for j = 0, self.height - 1 do
				self:set(i, j, false)
			end
		end
	elseif x < 0 then
		-- Moving to the left (X is negative, adding with it will subtract)
		-- Move these bits to the right, but go from left to right
		for i = 0, max(0, self.width + x) do
			for j = 0, self.height - 1 do
				self:set(i, j, self:get(i - x, j))
			end
		end
		-- The last X bits are zeroed
		for i = max(0, self.width + x), self.width - 1 do
			for j = 0, self.height - 1 do
				self:set(i, j, false)
			end
		end
	end

	if y > 0 then
		-- Moving up (Y is positive)
		-- Move these bits up, but go from bottom to top
		for i = self.height - 1, max(y - 1, 0), -1 do
			for j = 0, self.width - 1 do
				self:set(j, i, self:get(j, i - y))
			end
		end
		-- The first Y bits are zeroed
		for i = 0, min(y, self.height) - 1 do
			for j = 0, self.width - 1 do
				self:set(j, i, false)
			end
		end
	elseif y < 0 then
		-- Moving down (Y is negative, adding with it will subtract)
		-- Move these bits down, but go from top to bottom
		for i = 0, max(0, self.height + y) do
			for j = 0, self.width - 1 do
				self:set(j, i, self:get(j, i - y))
			end
		end
		-- The last Y bits are zeroed
		for i = max(0, self.height + y), self.height - 1 do
			for j = 0, self.width - 1 do
				self:set(j, i, false)
			end
		end
	end

	-- Mark the bitmask as changed if the shift amount is not zero
	self._dirty = not (x == 0 and y == 0)
end

---Resets the BitMask. Can pass 'true' to set all bits to 1.
---@param makeAllTrue boolean?
function Bitmask:reset(makeAllTrue)
	local value = (makeAllTrue and 255) or 0
	local data = self.data
	for i = 0, ceil(self.width * self.height * 0.125) - 1 do
		data[i] = value
	end
	self._dirty = true
end

---Pastes the bits from source into self
---@param source Bitmask
---@param dx integer
---@param dy integer
---@param sx integer
---@param sy integer
---@param w integer
---@param h integer
function Bitmask:paste(source, dx, dy, sx, sy, w, h)
	dx, dy, sx, sy, w, h = normalizeParams(self, source, dx, dy, sx, sy, w, h)
	local diffX, diffY = sx - dx, sy - dy
	for i = dx, dx + w - 1 do
		for j = dy, dy + h - 1 do
			self:set(i, j, source:get(i + diffX, j + diffY))
		end
	end
	self._dirty = true
end

---Sets whether this bitmask is active
---@param active boolean
function Bitmask:setActive(active)
	if active == self._active then return end
	self._active = active
end

---Returns the index and shift amount of a specific X and Y position, 0-indexed
---@param x integer
---@param y integer
---@return integer # Index
---@return integer # RShift
function Bitmask:getIndexAndShiftAmount(x, y)
	local pos = x + y * self.width
	local index = floor(pos * 0.125)
	local shiftAmount = pos % 8
	return index, shiftAmount
end

---Marks a square region
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@param value boolean
function Bitmask:markRegion(x, y, w, h, value)
	if x + w < 1 or x > self.width - 1 or y + h < 1 or y > self.height - 1 then return end
	local diffX = x - max(0, min(self.width - 1, x))
	local diffY = y - max(0, min(self.height - 1, y))
	x = x - diffX
	y = y - diffY
	w = max(0, min(self.width - 1, x + w + diffX - 1) - x)
	h = max(0, min(self.height - 1, y + h + diffY - 1) - y)

	for cx = x, x + w do
		for cy = y, y + h do
			self:set(cx, cy, value)
		end
	end
end

---Returns the value at a point, 0-indexed. CAN READ OUT OF BOUNDS!
---@param x integer
---@param y integer
---@return boolean
function Bitmask:get(x, y)
	local index, shiftAmount = self:getIndexAndShiftAmount(x, y)
	return band(brshift(self.data[index], shiftAmount), 1) == 1
end

---Sets the bit at the point, 0-indexed. CAN SET OUT OF BOUNDS!
---@param x integer
---@param y integer
---@param value boolean
function Bitmask: set(x, y, value)
	local index, shiftAmount = self:getIndexAndShiftAmount(x, y)
	if value then
		self.data[index] = bor(self.data[index], blshift(0b00000001, shiftAmount))
	else
		self.data[index] = band(self.data[index], bnot(blshift(0b00000001, shiftAmount)))
	end
	self._dirty = true
end

---Inverts all bits
function Bitmask:invert()
	for i = 0, ceil(self.width * self.height * 0.125) - 1 do
		self.data[i] = bnot(self.data[i])
	end
	self._dirty = true
end

---Resizes the bitmask, removing the original data
function Bitmask:resize(width, height)
	self.width, self.height = width, height
	self.data = ffi.new("uint8_t[?]", ceil(width * height * 0.125))
end

return Bitmask
