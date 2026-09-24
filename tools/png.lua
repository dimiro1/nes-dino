-- ---------------------------------------------------------------------------
--  png.lua -- reading and writing PNGs with nothing but Lua
-- ---------------------------------------------------------------------------
--  Lua has no zlib, so both halves are here.
--
--  Writing does not compress anything itself.  gzip already exists on every
--  machine this could run on and its payload is a deflate stream, so the
--  bytes go out through it and the gzip wrapper is unpicked and replaced with
--  a zlib one.  Where there is no gzip it falls back to deflate's stored
--  blocks, which compress nothing and are perfectly legal, just fat.
--
--  Reading has to do the real thing, since the emulator's screenshots are
--  compressed properly: there is an inflate below, fixed and dynamic Huffman
--  both.  That is the half a simpler image format would not have saved.
-- ---------------------------------------------------------------------------

local M = {}

-- --- checksums -------------------------------------------------------------

local crc_table
local function crc32(s, crc)
    if not crc_table then
        crc_table = {}
        for i = 0, 255 do
            local c = i
            for _ = 1, 8 do
                if c & 1 == 1 then c = 0xEDB88320 ~ (c >> 1) else c = c >> 1 end
            end
            crc_table[i] = c
        end
    end
    crc = (crc or 0) ~ 0xFFFFFFFF
    for i = 1, #s do
        crc = crc_table[(crc ~ s:byte(i)) & 0xFF] ~ (crc >> 8)
    end
    return (crc ~ 0xFFFFFFFF) & 0xFFFFFFFF
end

local function adler32(s)
    local a, b, n = 1, 0, #s
    local i = 1
    while i <= n do
        local stop = math.min(i + 5551, n)      -- as far as it can go unreduced
        for j = i, stop do
            a = a + s:byte(j)
            b = b + a
        end
        a = a % 65521
        b = b % 65521
        i = stop + 1
    end
    return (b << 16) | a
end

-- --- writing ---------------------------------------------------------------

local function zlib_stored(data)
    local parts = { '\x78\x01' }
    local n, i = #data, 1
    repeat
        local size = math.min(65535, n - i + 1)
        local final = (i + size > n) and 1 or 0
        parts[#parts + 1] = string.pack('<B I2 I2', final, size, (~size) & 0xFFFF)
        parts[#parts + 1] = data:sub(i, i + size - 1)
        i = i + size
    until i > n
    parts[#parts + 1] = string.pack('>I4', adler32(data))
    return table.concat(parts)
end

--- Hand the bytes to gzip and take the deflate stream back out of the middle
--- of what it returns.  Nil if gzip is not there or would not play.
local function deflate_via_gzip(data)
    local name = os.tmpname()
    local raw = io.open(name, 'wb')
    if not raw then return nil end
    raw:write(data)
    raw:close()

    local pipe = io.popen("gzip -9 -n -c < '" .. name .. "' 2>/dev/null")
    local gz = pipe and pipe:read('a')
    if pipe then pipe:close() end
    os.remove(name)
    if not gz or #gz < 20 or gz:byte(1) ~= 0x1F or gz:byte(2) ~= 0x8B then
        return nil
    end

    -- Walk the gzip header rather than assuming its length: FLG says which
    -- optional fields are in there.
    local flags = gz:byte(4)
    local at = 11
    if flags & 0x04 ~= 0 then                       -- FEXTRA
        at = at + 2 + string.unpack('<I2', gz, at)
    end
    if flags & 0x08 ~= 0 then at = gz:find('\0', at, true) + 1 end   -- FNAME
    if flags & 0x10 ~= 0 then at = gz:find('\0', at, true) + 1 end   -- FCOMMENT
    if flags & 0x02 ~= 0 then at = at + 2 end                        -- FHCRC
    return gz:sub(at, #gz - 8)                      -- less the crc and length
end

local function chunk(kind, body)
    local payload = kind .. body
    return string.pack('>I4', #body) .. payload .. string.pack('>I4', crc32(payload))
end

--- Write an 8-bit RGB PNG.  rows is an array of strings, each width*3 bytes.
function M.write(path, width, height, rows)
    local raw = {}
    for y = 1, height do
        raw[#raw + 1] = '\0'                    -- filter: none
        raw[#raw + 1] = rows[y]
    end
    raw = table.concat(raw)

    local file = assert(io.open(path, 'wb'))
    file:write('\137PNG\r\n\26\n')
    file:write(chunk('IHDR', string.pack('>I4 I4 BBBBB', width, height, 8, 2, 0, 0, 0)))
    local squeezed = deflate_via_gzip(raw)
    local zlib = squeezed
        and ('\x78\x01' .. squeezed .. string.pack('>I4', adler32(raw)))
        or zlib_stored(raw)
    file:write(chunk('IDAT', zlib))
    file:write(chunk('IEND', ''))
    file:close()
end

-- --- inflate ---------------------------------------------------------------

local LEN_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35,
                   43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3,
                    4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DIST_BASE = { 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193,
                    257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145,
                    8193, 12289, 16385, 24577 }
local DIST_EXTRA = { 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8,
                     9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
-- The order the code-length code's own lengths arrive in, as 1-based symbols
local CLEN_ORDER = { 17, 18, 19, 1, 9, 8, 10, 7, 11, 6, 12, 5, 13, 4, 14, 3,
                     15, 2, 16 }

--- Canonical Huffman: count how many codes there are of each length, and list
--- the symbols in the order the codes are handed out.
local function build(lengths, count)
    local counts, symbols = {}, {}
    for i = 0, 15 do counts[i] = 0 end
    for i = 1, count do counts[lengths[i]] = counts[lengths[i]] + 1 end
    counts[0] = 0
    local offset, total = {}, 0
    for len = 1, 15 do
        offset[len] = total
        total = total + counts[len]
    end
    for i = 1, count do
        local len = lengths[i]
        if len > 0 then
            symbols[offset[len]] = i - 1
            offset[len] = offset[len] + 1
        end
    end
    return { counts = counts, symbols = symbols }
end

local function inflate(data)
    local pos, bitbuf, bitcount = 1, 0, 0

    local function bits(n)
        while bitcount < n do
            bitbuf = bitbuf | (data:byte(pos) << bitcount)
            pos = pos + 1
            bitcount = bitcount + 8
        end
        local value = bitbuf & ((1 << n) - 1)
        bitbuf = bitbuf >> n
        bitcount = bitcount - n
        return value
    end

    local function decode(tree)
        local code, first, index = 0, 0, 0
        for len = 1, 15 do
            code = code | bits(1)
            local count = tree.counts[len]
            if code - first < count then
                return tree.symbols[index + code - first]
            end
            index = index + count
            first = (first + count) << 1
            code = code << 1
        end
        error('malformed deflate stream')
    end

    local fixed_lit, fixed_dist
    local out, n = {}, 0
    local final
    repeat
        final = bits(1)
        local kind = bits(2)

        if kind == 0 then                       -- stored
            bitbuf, bitcount = 0, 0
            local size = data:byte(pos) | (data:byte(pos + 1) << 8)
            pos = pos + 4
            for i = 0, size - 1 do
                n = n + 1
                out[n] = data:byte(pos + i)
            end
            pos = pos + size
        else
            local lit, dist
            if kind == 1 then                   -- fixed Huffman
                if not fixed_lit then
                    local l = {}
                    for i = 1, 144 do l[i] = 8 end
                    for i = 145, 256 do l[i] = 9 end
                    for i = 257, 280 do l[i] = 7 end
                    for i = 281, 288 do l[i] = 8 end
                    fixed_lit = build(l, 288)
                    local d = {}
                    for i = 1, 30 do d[i] = 5 end
                    fixed_dist = build(d, 30)
                end
                lit, dist = fixed_lit, fixed_dist
            else                                -- dynamic Huffman
                local hlit = bits(5) + 257
                local hdist = bits(5) + 1
                local hclen = bits(4) + 4
                local clen = {}
                for i = 1, 19 do clen[i] = 0 end
                for i = 1, hclen do clen[CLEN_ORDER[i]] = bits(3) end
                local code_tree = build(clen, 19)

                local lengths, at = {}, 1
                while at <= hlit + hdist do
                    local symbol = decode(code_tree)
                    if symbol < 16 then
                        lengths[at] = symbol
                        at = at + 1
                    elseif symbol == 16 then
                        local previous = lengths[at - 1]
                        for _ = 1, bits(2) + 3 do lengths[at] = previous; at = at + 1 end
                    elseif symbol == 17 then
                        for _ = 1, bits(3) + 3 do lengths[at] = 0; at = at + 1 end
                    else
                        for _ = 1, bits(7) + 11 do lengths[at] = 0; at = at + 1 end
                    end
                end

                local ll, dl = {}, {}
                for i = 1, hlit do ll[i] = lengths[i] end
                for i = 1, hdist do dl[i] = lengths[hlit + i] end
                lit = build(ll, hlit)
                dist = build(dl, hdist)
            end

            while true do
                local symbol = decode(lit)
                if symbol < 256 then
                    n = n + 1
                    out[n] = symbol
                elseif symbol == 256 then
                    break
                else
                    local i = symbol - 256
                    local length = LEN_BASE[i] + bits(LEN_EXTRA[i])
                    local j = decode(dist) + 1
                    local back = n - (DIST_BASE[j] + bits(DIST_EXTRA[j]))
                    for k = 1, length do
                        n = n + 1
                        out[n] = out[back + k]
                    end
                end
            end
        end
    until final == 1

    return out, n
end

-- --- reading ---------------------------------------------------------------

--- Read a PNG.  Returns width, height, channels and an array of rows, each
--- row a 1-based array of bytes.
function M.read(path)
    local file = assert(io.open(path, 'rb'))
    local data = file:read('a')
    file:close()
    assert(data:sub(2, 4) == 'PNG', path .. ' is not a PNG')

    local pos, idat = 9, {}
    local width, height, channels
    while pos <= #data do
        local size = string.unpack('>I4', data, pos)
        local kind = data:sub(pos + 4, pos + 7)
        local body = data:sub(pos + 8, pos + 7 + size)
        if kind == 'IHDR' then
            local depth, colour
            width, height, depth, colour = string.unpack('>I4 I4 BB', body)
            assert(depth == 8, 'only 8-bit PNGs are handled')
            channels = ({ [0] = 1, [2] = 3, [4] = 2, [6] = 4 })[colour]
            assert(channels, 'colour type ' .. colour .. ' is not handled')
        elseif kind == 'IDAT' then
            idat[#idat + 1] = body
        elseif kind == 'IEND' then
            break
        end
        pos = pos + size + 12
    end

    local raw = inflate(table.concat(idat):sub(3))   -- past the zlib header
    local stride = width * channels
    local rows, previous = {}, {}
    for i = 1, stride do previous[i] = 0 end

    local at = 1
    for y = 1, height do
        local filter = raw[at]
        local line = {}
        for i = 1, stride do line[i] = raw[at + i] end
        at = at + stride + 1

        if filter ~= 0 then
            for i = 1, stride do
                local a = (i > channels) and line[i - channels] or 0
                local b = previous[i]
                local value = line[i]
                if filter == 1 then
                    value = (value + a) & 0xFF
                elseif filter == 2 then
                    value = (value + b) & 0xFF
                elseif filter == 3 then
                    value = (value + ((a + b) // 2)) & 0xFF
                else
                    local c = (i > channels) and previous[i - channels] or 0
                    local p = a + b - c
                    local pa, pb, pc = math.abs(p - a), math.abs(p - b), math.abs(p - c)
                    local guess = (pa <= pb and pa <= pc) and a or (pb <= pc and b or c)
                    value = (value + guess) & 0xFF
                end
                line[i] = value
            end
        end
        rows[y] = line
        previous = line
    end
    return width, height, channels, rows
end

return M
