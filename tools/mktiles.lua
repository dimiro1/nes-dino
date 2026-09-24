#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
--  mktiles.lua -- turn human-readable ASCII tile art into NES CHR data
-- ---------------------------------------------------------------------------
--  Every graphic in this game is authored as plain text in assets/*.tiles so
--  it can be read, diffed and edited by hand.  This script is the only thing
--  that turns that text into the binary the PPU wants, and it also writes
--  contact sheets beside the art so it can be checked without an emulator.
--
--  Pixel characters
--      .   colour 0   (the backdrop; transparent in a sprite)
--      o   colour 1
--      #   colour 2
--      *   colour 3
--
--  Directives
--      @bank bg|spr        which 4KB half of the CHR the art below goes into
--      @tile NAME $XX      one 8x8 tile at tile index $XX
--      @sprite NAME $XX WxH   a W-by-H block of tiles, row major from $XX
-- ---------------------------------------------------------------------------

local HERE = (debug.getinfo(1, 'S').source:sub(2):match('^(.*)[/\\]') or '.')
package.path = HERE .. '/?.lua;' .. package.path
local png = require('png')

local ROOT = HERE .. '/..'
local TILE = 8
local BANK_TILES = 256
local PIXELS = { ['.'] = 0, ['o'] = 1, ['#'] = 2, ['*'] = 3 }

-- What the four colour indices look like in a preview.  Colour 0 and colour 1
-- are the CLASSIC scheme the game opens in; colour 2 and colour 3 are both the
-- backdrop in that scheme and so would be invisible, and are drawn as a sand
-- and an off-white instead, so the ground band and the sprite-0 marker can be
-- seen at all.
local PREVIEW = {
    [0] = { 0xFF, 0xFF, 0xFF },
    [1] = { 0x75, 0x75, 0x75 },
    [2] = { 0xF0, 0xDF, 0xB8 },
    [3] = { 0xE8, 0xE8, 0xE8 },
}

local function fail(message)
    io.stderr:write('mktiles: ', message, '\n')
    os.exit(1)
end

-- --- reading the art -------------------------------------------------------

local function sources()
    local list = {}
    local pipe = io.popen('ls ' .. ROOT .. "/assets/*.tiles 2>/dev/null")
    for line in pipe:lines() do list[#list + 1] = line end
    pipe:close()
    table.sort(list)
    if #list == 0 then fail('no .tiles files in assets/') end
    return list
end

local function parse(paths)
    local arts, bank = {}, nil
    local current, wanted = nil, 0

    for _, path in ipairs(paths) do
        local number = 0
        for raw in io.lines(path) do
            number = number + 1
            local where = ('%s:%d'):format(path:match('[^/]+$'), number)

            if current and wanted > 0 then
                local row = raw:gsub(';.*', ''):gsub('%s+$', '')
                local width = current.w * TILE
                if #row < width then row = row .. ('.'):rep(width - #row) end
                if #row > width then
                    fail(('%s: row is %d wide, expected %d'):format(where, #row, width))
                end
                local pixels = {}
                for i = 1, width do
                    local value = PIXELS[row:sub(i, i)]
                    if not value then
                        fail(('%s: %q is not one of . o # *'):format(where, row:sub(i, i)))
                    end
                    pixels[i] = value
                end
                current.rows[#current.rows + 1] = pixels
                wanted = wanted - 1
            else
                local line = raw:gsub(';.*', ''):gsub('^%s+', ''):gsub('%s+$', '')
                if line ~= '' and line:sub(1, 1) ~= '#' then
                    local word = {}
                    for piece in line:gmatch('%S+') do word[#word + 1] = piece end

                    if word[1] == '@bank' then
                        bank = word[2]
                        if bank ~= 'bg' and bank ~= 'spr' then
                            fail(where .. ': bank must be bg or spr')
                        end
                    elseif word[1] == '@tile' or word[1] == '@sprite' then
                        if not bank then fail(where .. ': art before any @bank') end
                        local w, h = 1, 1
                        if word[1] == '@sprite' then
                            w, h = word[4]:lower():match('^(%d+)x(%d+)$')
                            if not w then fail(where .. ': size must look like 3x2') end
                            w, h = tonumber(w), tonumber(h)
                        end
                        current = {
                            name = word[2],
                            bank = bank,
                            index = tonumber(word[3]:gsub('^%$', ''), 16),
                            w = w, h = h, rows = {},
                        }
                        wanted = h * TILE
                        arts[#arts + 1] = current
                    else
                        fail(where .. ': unknown directive ' .. word[1])
                    end
                end
            end
        end
    end

    if wanted > 0 then
        fail(('%s: ran out of file with %d rows to go'):format(current.name, wanted))
    end
    return arts
end

-- --- packing it into CHR ---------------------------------------------------

local function encode(arts)
    local banks = { bg = {}, spr = {} }
    local owner = { bg = {}, spr = {} }
    for _, which in ipairs({ 'bg', 'spr' }) do
        for i = 0, BANK_TILES * 16 - 1 do banks[which][i] = 0 end
    end

    for _, art in ipairs(arts) do
        for ty = 0, art.h - 1 do
            for tx = 0, art.w - 1 do
                local index = art.index + ty * art.w + tx
                if index >= BANK_TILES then
                    fail(('%s: tile $%02X runs off the end of the bank')
                        :format(art.name, index))
                end
                if owner[art.bank][index] then
                    fail(('%s: tile $%02X is already %s')
                        :format(art.name, index, owner[art.bank][index]))
                end
                owner[art.bank][index] = art.name

                -- A tile is two bitplanes: eight bytes of bit 0, then bit 1.
                for y = 0, TILE - 1 do
                    local low, high = 0, 0
                    local row = art.rows[ty * TILE + y + 1]
                    for x = 0, TILE - 1 do
                        local colour = row[tx * TILE + x + 1]
                        local bit = 7 - x
                        low = low | ((colour & 1) << bit)
                        high = high | (((colour >> 1) & 1) << bit)
                    end
                    banks[art.bank][index * 16 + y] = low
                    banks[art.bank][index * 16 + 8 + y] = high
                end
            end
        end
    end
    return banks, owner
end

local function write_chr(path, banks)
    local out = {}
    for _, which in ipairs({ 'bg', 'spr' }) do
        local bank = banks[which]
        for i = 0, BANK_TILES * 16 - 1, 64 do
            local piece = {}
            for j = i, math.min(i + 63, BANK_TILES * 16 - 1) do
                piece[#piece + 1] = string.char(bank[j])
            end
            out[#out + 1] = table.concat(piece)
        end
    end
    local file = assert(io.open(path, 'wb'))
    file:write(table.concat(out))
    file:close()
end

local function write_inc(path, arts)
    local file = assert(io.open(path, 'w'))
    file:write('; Generated by tools/mktiles.lua -- do not edit.\n')
    file:write('; Edit assets/*.tiles and rebuild instead.\n\n')
    for _, which in ipairs({ 'bg', 'spr' }) do
        file:write('; ---- ', which, ' bank ----\n')
        for _, art in ipairs(arts) do
            if art.bank == which then
                file:write(('%-24s = $%02X\n'):format(art.name, art.index))
            end
        end
        file:write('\n')
    end
    file:close()
end

-- --- the previews ----------------------------------------------------------

local function canvas(width, height, rgb)
    local rows = {}
    local blank = string.char(rgb[1], rgb[2], rgb[3]):rep(width)
    for y = 1, height do rows[y] = { blank:byte(1, -1) } end
    return rows
end

local function put(rows, x, y, rgb)
    local at = x * 3
    rows[y + 1][at + 1] = rgb[1]
    rows[y + 1][at + 2] = rgb[2]
    rows[y + 1][at + 3] = rgb[3]
end

local function flatten(rows, width, height)
    local out = {}
    for y = 1, height do
        local row, piece = rows[y], {}
        for i = 1, width * 3, 96 do
            piece[#piece + 1] = string.char(table.unpack(row, i,
                math.min(i + 95, width * 3)))
        end
        out[y] = table.concat(piece)
    end
    return out
end

local function blit(rows, x0, y0, pixel, w, h, zoom)
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            local rgb = PREVIEW[pixel(x, y)]
            for dy = 0, zoom - 1 do
                for dx = 0, zoom - 1 do
                    put(rows, x0 + x * zoom + dx, y0 + y * zoom + dy, rgb)
                end
            end
        end
    end
end

local function contact_sheet(path, bank, owner, zoom)
    zoom = zoom or 4
    local cell = TILE * zoom + 1
    local size = 16 * cell + 1
    local rows = canvas(size, size, { 0x18, 0x18, 0x20 })

    for index = 0, BANK_TILES - 1 do
        local x0 = (index % 16) * cell + 1
        local y0 = (index // 16) * cell + 1
        if owner[index] then
            blit(rows, x0, y0, function(x, y)
                local low = bank[index * 16 + y]
                local high = bank[index * 16 + 8 + y]
                local bit = 7 - x
                return ((low >> bit) & 1) | (((high >> bit) & 1) << 1)
            end, TILE, TILE, zoom)
        else
            for y = 0, TILE * zoom - 1 do
                for x = 0, TILE * zoom - 1 do
                    put(rows, x0 + x, y0 + y, { 0x22, 0x22, 0x2C })
                end
            end
        end
    end

    for n = 0, 16 do
        local at = n * cell
        local rgb = (n % 4 == 0) and { 0xD8, 0xE8, 0xFF } or { 0x30, 0x60, 0xC0 }
        for i = 0, size - 1 do
            put(rows, i, at, rgb)
            put(rows, at, i, rgb)
        end
    end
    png.write(path, size, size, flatten(rows, size, size))
end

local function assembled_sheet(path, arts, zoom, gap)
    zoom, gap = zoom or 6, gap or 8
    local width, height = gap, 0
    for _, art in ipairs(arts) do
        width = width + art.w * TILE * zoom + gap
        height = math.max(height, art.h * TILE * zoom)
    end
    height = height + gap * 2
    local rows = canvas(width, height, { 0x18, 0x18, 0x20 })

    local x = gap
    for _, art in ipairs(arts) do
        local w, h = art.w * TILE * zoom, art.h * TILE * zoom
        for y = -1, h do
            for dx = -1, w do
                put(rows, x + dx, gap + y, { 0x28, 0x28, 0x34 })
            end
        end
        blit(rows, x, gap, function(px, py) return art.rows[py + 1][px + 1] end,
             art.w * TILE, art.h * TILE, zoom)
        x = x + w + gap
    end
    png.write(path, width, height, flatten(rows, width, height))
end

-- --- ready ------------------------------------------------------------------

local arts = parse(sources())
local banks, owner = encode(arts)

os.execute('mkdir -p ' .. ROOT .. '/build ' .. ROOT .. '/assets/preview')
write_chr(ROOT .. '/build/dino.chr', banks)
write_inc(ROOT .. '/build/tiles.inc', arts)

contact_sheet(ROOT .. '/assets/preview/tiles-background.png', banks.bg, owner.bg)
contact_sheet(ROOT .. '/assets/preview/tiles-sprites.png', banks.spr, owner.spr)
local multi = {}
for _, art in ipairs(arts) do
    if art.w * art.h > 1 then multi[#multi + 1] = art end
end
assembled_sheet(ROOT .. '/assets/preview/graphics.png', multi)

local counted = {}
for _, which in ipairs({ 'bg', 'spr' }) do
    local n = 0
    for _ in pairs(owner[which]) do n = n + 1 end
    counted[which] = n
end
print(('%d graphics -> %d bg tiles, %d sprite tiles')
    :format(#arts, counted.bg, counted.spr))
print('wrote build/dino.chr, build/tiles.inc, and assets/preview/*.png')
