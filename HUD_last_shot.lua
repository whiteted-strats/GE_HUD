require "Utilities\\GE\\GuardDataReader"
require "HUD_Matt\\HUD_Matt_core"
require "HUD_Matt\\HUD_Matt_lib"

-- List of guards to draw now (alive & who have shot at some point)
local guards = {}
-- Guards who have ever shot (could be dead)
-- Map from guard addr -> bool (nil = false)
-- ! Respawning guards will no doubt confuse it
local hasShot = {}

-- Currently draw arbitrarily long lines, 100,000 units
local shotLength = 100000

function selectGuards()
    guards = {}
    function processGuard(g)
        local flags = g:get_value("shooting_stage_flag") -- type hex, should be int
        -- Update hasShot using flags
        if flags ~= 0xFF then
            hasShot[g.current_address] = true
        end

        -- If we've ever shot, then since we're alive add us.
        if hasShot[g.current_address] then
            local gData = {}
            gData.barrel = g:get_value("shot_origin")
            gData.bullet_dirc = g:get_value("bullet_dirc")
            table.insert(guards, gData)
        end
    end

    GuardDataReader.for_each(processGuard)
end

-- Place a marker at the shot's origin
function markBarrels()
    local ms = {}
    for addr, gData in pairs(guards) do
        local marker = {}
        marker.pnt = gData.barrel
        marker.thickness = 2
        marker.colour = 0xFFAA0000
        table.insert(ms, marker)
    end

    return ms
end

-- Draw the gunshot line
function drawGunshot()
    local ls = {}
    for addr, gData in pairs(guards) do
        local lnObj = {}
        lnObj.colour = 0xFFFFAA00
        
        -- Bullet dirc is a unit (by inspection atleast) so scale big
        local imaginaryFinish = vectorAdd(gData.barrel, scaleVector(gData.bullet_dirc, shotLength))
        lnObj.ps = {gData.barrel, imaginaryFinish}
        table.insert(ls, lnObj)
    end

    return ls
end

-- Do the thing!
showHUD(selectGuards, markBarrels, drawGunshot)