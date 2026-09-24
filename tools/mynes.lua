-- ---------------------------------------------------------------------------
--  mynes.lua -- find an emulator to test with, or fetch one
-- ---------------------------------------------------------------------------
--  Looked for in this order:
--
--    1. $MYNES, if it is set
--    2. whatever was found last time, remembered in tools/.mynes/path
--    3. a build or an unpacked release sitting next to this project
--    4. asked for, if there is a terminal to ask at
--    5. downloaded from the project's own releases, checksum first
--
--  Nothing here knows any particular machine's layout, so a checkout works
--  the same wherever it is put.
-- ---------------------------------------------------------------------------

local M = {}

local HERE = (debug.getinfo(1, 'S').source:sub(2):match('^(.*)[/\\]') or '.')
local ROOT = HERE .. '/..'
local CACHE = HERE .. '/.mynes'
local REMEMBERED = CACHE .. '/path'
local REPO = 'dimiro1/mynes'

local function quote(s) return "'" .. s:gsub("'", "'\\''") .. "'" end

local function exists(path)
    local file = io.open(path, 'rb')
    if file then file:close() return true end
    return false
end

local function capture(command)
    local pipe = io.popen(command .. ' 2>/dev/null')
    if not pipe then return nil end
    local out = pipe:read('a')
    pipe:close()
    return out
end

local function first_line(s)
    return s and s:match('[^\r\n]+') or nil
end

local function read_file(path)
    local file = io.open(path, 'r')
    if not file then return nil end
    local text = file:read('a')
    file:close()
    return text
end

local function remember(jar)
    os.execute('mkdir -p ' .. quote(CACHE))
    local file = io.open(REMEMBERED, 'w')
    if file then
        file:write(jar, '\n')
        file:close()
    end
    return jar
end

local function interactive()
    return os.execute('test -t 0') and true or false
end

-- --- the places a jar might already be -------------------------------------

local function search()
    local nearby = {
        ROOT .. '/mynes.jar',
        CACHE .. '/mynes.jar',
        ROOT .. '/../mynes/mynes-desktop/target/mynes.jar',
        ROOT .. '/../mynes/mynes.jar',
        ROOT .. '/../../java/mynes/mynes-desktop/target/mynes.jar',
    }
    for _, path in ipairs(nearby) do
        if exists(path) then return path end
    end
    -- anything unpacked into the cache by a previous download
    return first_line(capture('find ' .. quote(CACHE) ..
                              ' -name mynes.jar -type f 2>/dev/null'))
end

-- --- fetching one ----------------------------------------------------------

local function download()
    if not capture('command -v curl') then
        error('curl is needed to download the emulator, and is not installed')
    end
    os.execute('mkdir -p ' .. quote(CACHE))

    io.stderr:write('Fetching the latest MyNES release from github.com/', REPO, ' ...\n')
    local api = 'https://api.github.com/repos/' .. REPO .. '/releases/latest'
    local release = capture('curl -fsSL --max-time 60 ' .. quote(api))
    if not release or release == '' then
        error('could not reach the GitHub API; set MYNES to a jar instead')
    end

    local zip_url = release:match('"browser_download_url"%s*:%s*"(https://[^"]-%.zip)"')
    local sums_url = release:match('"browser_download_url"%s*:%s*"(https://[^"]-SHA256SUMS)"')
    local tag = release:match('"tag_name"%s*:%s*"([^"]+)"') or '?'
    if not zip_url then
        error('the latest release has no zip in it; set MYNES to a jar instead')
    end

    local name = zip_url:match('([^/]+)$')
    local zip = CACHE .. '/' .. name
    io.stderr:write('  ', tag, ' -> ', name, '\n')
    if not os.execute('curl -fsSL --max-time 300 -o ' .. quote(zip) .. ' ' .. quote(zip_url)) then
        error('downloading ' .. zip_url .. ' failed')
    end

    -- Verify it before unpacking, if the release publishes sums (it does).
    if sums_url then
        local sums = capture('curl -fsSL --max-time 60 ' .. quote(sums_url))
        local want = sums and sums:match('(%x+)%s+%*?' .. name:gsub('%p', '%%%0'))
        local got = first_line(capture('shasum -a 256 ' .. quote(zip)) or '')
        got = got and got:match('^(%x+)')
        if want and got then
            if want:lower() ~= got:lower() then
                os.remove(zip)
                error('checksum mismatch on ' .. name .. ' -- refusing to use it')
            end
            io.stderr:write('  sha256 verified\n')
        else
            io.stderr:write('  warning: could not check the sha256\n')
        end
    end

    if not os.execute('unzip -q -o ' .. quote(zip) .. ' -d ' .. quote(CACHE)) then
        error('unzipping ' .. zip .. ' failed')
    end
    os.remove(zip)

    local jar = first_line(capture('find ' .. quote(CACHE) .. ' -name mynes.jar -type f'))
    if not jar then error('no mynes.jar inside ' .. name) end
    io.stderr:write('  ready: ', jar, '\n\n')
    return jar
end

local function ask()
    io.stderr:write('\nMyNES was not found.  Give the path to mynes.jar, or press\n',
                    'Enter to download the latest release from github.com/', REPO, '\n> ')
    io.flush()
    local answer = io.read('l')
    if answer then
        answer = answer:gsub('^%s+', ''):gsub('%s+$', '')
        answer = answer:gsub('^~', os.getenv('HOME') or '~')
    end
    if answer and answer ~= '' then
        if not exists(answer) then error('no such file: ' .. answer) end
        return answer
    end
    return download()
end

-- --- the one thing this module is for --------------------------------------

--- Return a path to mynes.jar, finding, asking for or fetching one as needed.
function M.jar()
    local fromenv = os.getenv('MYNES')
    if fromenv and fromenv ~= '' then
        if not exists(fromenv) then
            error('MYNES is set to ' .. fromenv .. ', which is not there')
        end
        return fromenv
    end

    local saved = first_line(read_file(REMEMBERED) or '')
    if saved and exists(saved) then return saved end

    local found = search()
    if found then return remember(found) end

    if interactive() then return remember(ask()) end
    io.stderr:write('MyNES not found; fetching a release (set MYNES to skip this).\n')
    return remember(download())
end

-- Run as a script rather than required, it prints the path it settled on --
-- which is how the Makefile gets hold of one.
if arg and arg[0] and arg[0]:match('mynes%.lua$') then
    print(M.jar())
end

return M
