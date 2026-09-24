#!/usr/bin/env lua
-- ---------------------------------------------------------------------------
--  playtest.lua -- drive the ROM through MyNES headless and check what it did
-- ---------------------------------------------------------------------------
--  The emulator is deterministic, so every one of these is a real regression
--  test: the same ROM and the same buttons always produce the same RAM and
--  the same pixels.  Game state is read straight out of the zero page using
--  the labels ld65 wrote, which is more honest than squinting at a
--  screenshot; the two checks that are about pixels really do read pixels.
-- ---------------------------------------------------------------------------

local HERE = (debug.getinfo(1, 'S').source:sub(2):match('^(.*)[/\\]') or '.')
package.path = HERE .. '/?.lua;' .. package.path
local png = require('png')
local mynes = require('mynes')

local ROOT = HERE .. '/..'
local ROM = ROOT .. '/build/dino.nes'
local OUT = ROOT .. '/build/test'
local JAR

local ST_READY, ST_RUN, ST_DYING, ST_OVER = 0, 1, 2, 3
local failures = {}

local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

-- --- what the build produced -----------------------------------------------

local function load_labels()
    local labels = {}
    for line in io.lines(ROOT .. '/build/dino.labels') do
        local address, name = line:match('^al%s+(%x+)%s+%.([%w_]+)%s*$')
        if address then labels[name] = tonumber(address, 16) end
    end
    return labels
end

local SYM = load_labels()

-- --- driving the emulator --------------------------------------------------

local function run(name, frames, options)
    options = options or {}
    local out = OUT .. '/' .. name
    os.execute('mkdir -p ' .. quote(out))

    local command = {
        'java', '-jar', quote(JAR), '--headless',
        '--rom', quote(options.rom or ROM),
        '--frames', tostring(frames),
        '--out', quote(out), '--dump', 'ram',
        '--report', quote(out .. '/report.json'), '--quiet',
    }
    for _, spec in ipairs(options.inputs or {}) do
        command[#command + 1] = '--input'
        command[#command + 1] = quote(spec)
    end
    if options.shots then
        command[#command + 1] = '--screenshot'
        command[#command + 1] = quote(table.concat(options.shots, ','))
    end
    for _, expect in ipairs(options.expect or {}) do
        command[#command + 1] = expect
    end
    command[#command + 1] = '>/dev/null 2>&1'

    local ok, _, code = os.execute(table.concat(command, ' '))
    code = ok and 0 or (code or 1)

    local file = assert(io.open(out .. '/ram.bin', 'rb'),
                        name .. ': the emulator wrote no RAM dump')
    local ram = file:read('a')
    file:close()
    return ram, code, out
end

local function peek(ram, name)
    local at = assert(SYM[name], 'no label called ' .. name)
    return ram:byte(at + 1)
end

local function digits(ram, name)
    local at = assert(SYM[name], 'no label called ' .. name)
    local value = 0
    for i = 0, 4 do value = value * 10 + ram:byte(at + 1 + i) end
    return value
end

local function check(label, ok, detail)
    io.write(ok and '  ok    ' or '  FAIL  ', label)
    if not ok and detail then io.write('   [', detail, ']') end
    io.write('\n')
    if not ok then failures[#failures + 1] = label end
end

-- --- the tests -------------------------------------------------------------

local tests = {}

tests[#tests + 1] = { 'boot', function()
    local ram, code = run('boot', 40, { expect = { '--expect-not-blank' } })
    check('waits on the ready state', peek(ram, 'game_state') == ST_READY,
          'state=' .. peek(ram, 'game_state'))
    check('camera has not moved', peek(ram, 'cam_lo') == 0)
    check('something is on screen', code == 0, 'exit=' .. code)
    check('score starts at zero', digits(ram, 'score') == 0)
end }

tests[#tests + 1] = { 'starting and scrolling', function()
    local ram = run('start', 200, { inputs = { '60:start' } })
    check('start begins the run', peek(ram, 'game_state') == ST_RUN,
          'state=' .. peek(ram, 'game_state'))
    local moved = peek(ram, 'cam_lo') | (peek(ram, 'cam_hi') << 8)
    check('the world scrolled', moved > 150, 'camera=' .. moved)
    check('the score is counting', digits(ram, 'score') > 0,
          'score=' .. digits(ram, 'score'))
end }

tests[#tests + 1] = { 'the split', function()
    -- The sprite-0 hit is the only thing keeping the score bar off the scroll,
    -- and it is a timing behaviour: nothing but the picture can show it.
    local _, _, out = run('split', 320,
        { inputs = { '60:start' }, shots = { 80, 300 } })
    local _, _, channels, early = png.read(out .. '/frame-000080.png')
    local _, _, _, late = png.read(out .. '/frame-000300.png')

    -- PNG row 9 is scanline 16, where the bar's glyphs are.  The digits
    -- themselves change as the score counts, so this looks at the fixed HI
    -- label -- tile columns 16 and 17, x 128 to 143.
    local same = true
    for y = 9, 15 do
        for i = 128 * channels + 1, 144 * channels do
            if early[y][i] ~= late[y][i] then same = false end
        end
    end
    check('score bar does not scroll with the world', same)

    -- ...and the ground really did move, or the check above proves nothing.
    -- Row 186 is scanline 193: the speckled row under the ground line, where
    -- a scroll shows.  The line itself is solid and looks the same wherever
    -- it has got to.
    local moved = false
    for i = 1, #early[186] do
        if early[186][i] ~= late[186][i] then moved = true end
    end
    check('the ground underneath did move', moved)
end }

tests[#tests + 1] = { 'the jump', function()
    local height = {}
    for _, frame in ipairs({ 100, 112, 122, 132, 145 }) do
        local ram = run('jump' .. frame, frame,
            { inputs = { '60:start', '100-140:a' } })
        height[frame] = peek(ram, 'dino_y')
    end
    local ground = 192 - 24
    check('on the ground before jumping', height[100] == ground,
          'y=' .. height[100])
    check('rising 12 frames in', height[112] < ground - 20, 'y=' .. height[112])
    local peak = math.min(height[112], height[122], height[132])
    check('clears a large cactus', ground - peak >= 30,
          ('peaked %dpx up'):format(ground - peak))
    check('back on the ground by frame 145', height[145] == ground,
          'y=' .. height[145])
end }

tests[#tests + 1] = { 'running into a cactus', function()
    local ram = run('crash', 700, { inputs = { '60:start' } })
    local state = peek(ram, 'game_state')
    check('a cactus ends the run', state == ST_DYING or state == ST_OVER,
          'state=' .. state)
    check('the dead pose is showing', peek(ram, 'dino_state') == 3)
    check('the high score was kept', digits(ram, 'hi_score') > 0,
          'hi=' .. digits(ram, 'hi_score'))
end }

tests[#tests + 1] = { 'restarting', function()
    local ram = run('restart', 900, { inputs = { '60:start', '760/40x4:start' } })
    local state = peek(ram, 'game_state')
    check('a second go is possible', state == ST_READY or state == ST_RUN,
          'state=' .. state)
    check('the high score survived it', digits(ram, 'hi_score') > 0,
          'hi=' .. digits(ram, 'hi_score'))
end }

tests[#tests + 1] = { 'playing beats standing still', function()
    -- Measured on the high score, not the live one: the repeated presses that
    -- do the jumping also restart the game from the game-over screen, so the
    -- live score is only whatever the latest attempt has got to.
    local idle = run('idle', 1200, { inputs = { '60:start' } })
    local plays = run('plays', 1200, { inputs = { '60:start', '150/26:a' } })
    local a, b = digits(idle, 'hi_score'), digits(plays, 'hi_score')
    check('jumping outscores standing still', b > a,
          ('idle=%d jumping=%d'):format(a, b))
end }

tests[#tests + 1] = { 'the noises', function()
    local _, code = run('sound', 700,
        { inputs = { '60:start', '150/26:a' },
          expect = { '--expect-audio', '--expect-motion', '300' } })
    check('it makes a sound, and the picture moves', code == 0, 'exit=' .. code)
end }

tests[#tests + 1] = { 'birds keep their distance from cacti', function()
    -- A bird used to appear on its own timer, knowing nothing about where the
    -- cacti were, and it flies faster than the ground -- so it could arrive
    -- sitting on one, which is a pair nothing can get through.  Birds now take
    -- their turn in the same queue.  This walks a long run frame by frame
    -- through the debugger and measures how close the two ever come.
    local rom = ROOT .. '/build/dino-god.nes'
    local probe = io.open(rom, 'rb')
    if not probe then
        check('god build present (run: make debug)', false)
        return
    end
    probe:close()

    local script = { 'run 20', 'hold start', 'run 4', 'release' }
    for _ = 1, 4000 do
        script[#script + 1] = 'run 3'
        script[#script + 1] = 'read $' .. ('%X'):format(SYM.obst_kind) .. ' 22'
    end
    script[#script + 1] = 'quit'
    local path = os.tmpname()
    local file = assert(io.open(path, 'w'))
    file:write(table.concat(script, '\n'), '\n')
    file:close()

    os.execute('mkdir -p ' .. quote(OUT .. '/gap'))
    local pipe = io.popen(("java -jar %s --headless --rom %s --interactive "
        .. "--script %s --format text --out %s 2>/dev/null")
        :format(quote(JAR), quote(rom), quote(path), quote(OUT .. '/gap')))

    -- obst_kind[6], obst_x_lo[6], obst_x_hi[6], ptero_on, x_lo, x_hi, y
    local WIDTH = { [0] = 0, 8, 16, 24, 16, 32, 24 }
    local BIAS = 512
    local closest, overlaps, birds, detail = 9999, 0, 0, ''
    local flying = false
    for line in pipe:lines() do
        local hex = line:match('^bytes%s*:%s*(%x+)%s*$')
        if hex and #hex == 44 then
            local b = {}
            for i = 1, 22 do b[i] = tonumber(hex:sub(i * 2 - 1, i * 2), 16) end
            if b[19] == 0 then
                flying = false
            else
                if not flying then birds = birds + 1; flying = true end
                local bx = ((b[21] << 8) | b[20]) - BIAS
                if bx > -60 and bx < 300 then
                    for i = 0, 5 do
                        local kind = b[1 + i]
                        if kind ~= 0 then
                            local cx = ((b[13 + i] << 8) | b[7 + i]) - BIAS
                            if cx > -60 and cx < 300 then
                                local gap
                                if bx >= cx then gap = bx - (cx + WIDTH[kind])
                                else gap = cx - (bx + 24) end
                                if gap < closest then
                                    closest = gap
                                    detail = ('bird at %d, cactus at %d'):format(bx, cx)
                                end
                                if gap < 0 then overlaps = overlaps + 1 end
                            end
                        end
                    end
                end
            end
        end
    end
    pipe:close()
    os.remove(path)

    check('the run actually produced birds', birds >= 5, 'saw ' .. birds)
    check('a bird never lands on a cactus', overlaps == 0,
          overlaps .. ' frames overlapping')
    check('and always leaves room to deal with one first', closest >= 150,
          ('closest was %dpx -- %s'):format(closest, detail))
end }

tests[#tests + 1] = { 'flying into a bird', function()
    -- A build with no cacti in it, so a bird is the only way to die.
    local rom = ROOT .. '/build/dino-birds.nes'
    local probe = io.open(rom, 'rb')
    if not probe then
        check('bird build present (run: make debug)', false)
        return
    end
    probe:close()
    local ram = run('birds', 2500, { inputs = { '60:start' }, rom = rom })
    local state = peek(ram, 'game_state')
    check('a bird ends the run', state == ST_DYING or state == ST_OVER,
          'state=' .. state)
    check('it got past the first hundred first', digits(ram, 'hi_score') > 100,
          'hi=' .. digits(ram, 'hi_score'))
end }

-- --- go --------------------------------------------------------------------

local probe = io.open(ROM, 'rb')
if not probe then
    io.stderr:write('build/dino.nes is missing; run make first\n')
    os.exit(1)
end
probe:close()

JAR = mynes.jar()

for _, test in ipairs(tests) do
    print(test[1])
    test[2]()
end

print()
if #failures > 0 then
    print(('%d failed: %s'):format(#failures, table.concat(failures, ', ')))
    os.exit(1)
end
print('all good')
