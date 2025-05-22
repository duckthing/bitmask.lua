## bitmask.lua
A LuaJIT-dependent implementation of a bitmask. Specifically, this library relies on the `ffi` and `bit` libraries
that are often included with LuaJIT.

## Quick Example
```lua
local Bitmask = require "bitmask"

-- Create a 32 by 32 bitmask, which is an array of 128 bytes
local mask = Bitmask.new(32, 32)

-- Make a region at (0, 0) to (9, 19) true, making a 10 by 20 rectangular region true.
mask:markRegion(0, 0, 10, 20, true)

-- Remember, this library is 0-indexed.
-- This function will *only* run if the width and height is greater than 0.
-- A region of (5, 5, 1, 1) will make (5, 5) true, and nothing else.

-- Subtract a region from (15, 6) to (-10, -100) false, making an L shape of true bits.
mask:markRegion(15, 15, -25, -115, false)
-- The parameters are processed to stay within a bitmask's bounds.
-- It's okay to go in reverse and out of bounds in :markRegion().

-- Print out the left, top, right, and bottom edges of the true bits. Also print the width and height of it.
print(mask:getBounds()) -- 0, 0, 9, 19, 10, 20

-- Invert all bits manually
-- Since we're using a byte array created through the FFI, remember we start at 1 and end at size - 1, inclusive.
for x = 0, mask.width - 1 do
	for y = 0, mask.height - 1 do
		-- :get() and :set() can read out of bounds.
		-- :set() does not mark the mask as "dirty", meaning :getBounds() will return a cached boundary
		-- instead of recalculating the boundary.
		mask:set(x, y, not mask:get(x, y))
	end
end

-- Mark the mask as dirty after doing manual changes with :set()
mask._dirty = true

-- Since the mask is "dirty", the bounds is recalculated.
print(mask:getBounds()) -- 0, 0, 31, 31, 32, 32

-- Alternatively...
mask:invert()
print(mask:getBounds()) -- 0, 0, 9, 19, 10, 20

-- Shift all bits right and downwards by 25.
-- This clips 3 bits off.
mask:shift(25, 25)
print(mask:getBounds()) -- 25, 25, 31, 31, 7, 7

-- Clear the mask
mask:reset()
print(mask:getBounds()) -- 0, 0, -1, -1, 0, 0
```

## Usage
Either paste `bitmask.lua` into your project, or add it with a git submodule:

`git submodule add https://github.com/duckthing/bitmask.lua.git ./lib/bitmask`

Then require it however you want.

## License
This project is licensed under the terms of the zlib license.
