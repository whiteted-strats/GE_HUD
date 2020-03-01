require "Utilities\\GE\\ProjectileDataReader"
require "HUD_Matt\\HUD_matt_core"
require "Data\\GE\\MotionData"

-- ======================================================
-- Settings:

-- Number of arcs to display (fade with relative age) (displays all active mines Regardless)
nToDisplay = 3
-- The RRGGBB colour of arcs (currently green)
baseColour = 0x008800
-- Raise to keep lag from the HUD lowest: read a point on the arc, then skip this number
-- 0 for perfect accuracy, 2 is sensible
-- Will always show first and last point!
nToSkip = 2
-- Change Display key: cycles through the display types below
displayKey = "D"

-- For real precision, update trails at 60Hz: good for placing bounces exactly,
--  but adds many more points to the trail, and so a lot of lag.
trackTrailsEachFrame = true

rippleColour = 0xFFFF0000
markerColour = 0xFFAA0000

-- ======================================================

DT_hidden = 1
DT_trail_only = 2
DT_bounces_too = 3
DT_markers_too = 4
DT_name = {"Display hidden, lower lag", "Trail only", "Trail & bounces", "Trail, bounces & markers"}

DT_count = 4
curr_DT = DT_trail_only


-- ======================================================

-- Features:
--  . smooth fading with age
--  . resiliant to save-state loading (have no active mines in the save-state and all is good)
--  . drawing precision control via nToSkip (always shows throw start and end points)
--  . show/hide display with key (default "D")
--  . draws 'ripples' around bounce points
--  . can track trails at 60hz
--  . can display actual positions which the mine was at, for tracking the affect of lag

-- ======================================================
-- Code:

keyHeldPrev = false

savedTrails = {}

mineProp = {}
mines = {}

-- Remove all alpha
baseColour = baseColour % 0x01000000

function noteProjs()
    -- Update display type.. but actually Track mines regardless
    -- note nil is false
    keyHeld = input.get()[displayKey]
    if keyHeld and not keyHeldPrev then
        curr_DT = (curr_DT % DT_count) + 1
    end
    keyHeldPrev = keyHeld

    gui.drawText(0,15, string.format("(Setting %i) ", curr_DT) .. DT_name[curr_DT] .. " (press " .. displayKey .. " to cycle)")

    -- Assume all have become inactive
    for _, addr in ipairs(mines) do
        mineProp[addr].active = false
    end

    local projCount = 0

    function processProjectile(p)
        local addr = p.current_address
        -- Ignore type 07.. apparently there are lots of these of s2, permenantly, and I don't know what they are
        local type = p:get_value("type")
        if type ~= 0x07 then
            projCount = projCount + 1

            -- If it's new then add it to the end
            if mineProp[addr] == nil then
                console.log(string.format("New at %X", addr))
                mineProp[addr] = {}
                mineProp[addr].spline = {}
                mineProp[addr].ripples = {}
                table.insert(mines, addr)
                mineProp[addr].mod = -1
            end

            -- Update activity
            mineProp[addr].active = true
            -- Update modulo
            mineProp[addr].mod = (mineProp[addr].mod + 1) % (nToSkip + 1)

            -- Either add the point to the trail, or note that it is the most recent point
            if mineProp[addr].mod == 0 then
                table.insert(mineProp[addr].spline, p:get_value("position"))
                mineProp[addr].lastPnt = nil
            else
                mineProp[addr].lastPnt = p:get_value("position")
            end

            local mdp = p:get_value("motion_data_pointer") - 0x80000000
            if mdp >= 0 then
                local bounces = MotionData:get_value(mdp, "bounce_count")
                gui.drawText(0,70, bounces .. " bounces")
                -- If we detect a bounce, add a single riple around it for now
                if bounces ~= mineProp[addr].bounces and bounces > 0 then
                    table.insert(mineProp[addr].ripples, {colour=rippleColour, center=p:get_value("position"), normal={x=0,y=1,z=0}, radius=15, coarseness=10})
                end

                -- Update bounces follower
                mineProp[addr].bounces = bounces
            end
        end
    end

    -- Process all current projectiles
    ProjectileDataReader.for_each(processProjectile)

    gui.drawText(0,30, projCount .. " projectiles tracked.")

    -- Move all inactive mine trails to cold storage, preserve order of remaining mines
    newMines = {}
    nActiveMines = 0
    for _, addr in ipairs(mines) do
        if mineProp[addr].active then
            table.insert(newMines, addr)
            nActiveMines = nActiveMines + 1
        else
            -- Add the most recent point if necessary
            if mineProp[addr].lastPnt ~= nil then
                table.insert(mineProp[addr].spline, mineProp[addr].lastPnt)
            end
            -- Save the trail & bounces
            table.insert(savedTrails, {spline=mineProp[addr].spline, ripples=mineProp[addr].ripples})
            -- Clean up memory
            mineProp[addr] = nil
        end
    end
    --gui.drawText(0,15, "There are " .. nActiveMines .. " active mines.")


    mines = newMines

    -- Kill oldest saved trail first, down to the desired number,
    --  or as close as possible without killing active mines.
    nOldToShow = nToDisplay - table.getn(mines)
    if nOldToShow <= 0 then
        savedTrails = {}
    else
        local N = table.getn(savedTrails)
        if nOldToShow < N then
            local newTrails = {}
            for j = N - nOldToShow + 1, N, 1 do
                table.insert(newTrails, savedTrails[j])
            end
            savedTrails = newTrails
        end
    end
end

-- Return the tails to be drawn
-- Colour the most recent the base colour, then fade alpha s.t.
--   At full capacity, the 0th would be invisible
-- Returns {} if the display is disabled.
function getColouredTrails()
    local ls = {}

    if curr_DT ~= DT_hidden then
        -- We display all active mines regardless
        local numberDisplayed = math.max(nToDisplay, table.getn(mines))
        -- Work out the space
        local space = numberDisplayed - table.getn(mines) - table.getn(savedTrails)

        local i = 0
        -- Add all the saved trails first
        for _, trail in ipairs(savedTrails) do
            i = i + 1
            local lnObj = {}
            lnObj.colour = baseColour + math.floor(0xFF * (space + i) / numberDisplayed) * 0x1000000
            lnObj.ps = trail.spline
            table.insert(ls, lnObj)
        end
        -- Then add the current trails
        for _, addr in ipairs(mines) do
            i = i + 1
            local lnObj = {}
            lnObj.colour = baseColour + math.floor(0xFF * (space + i) / numberDisplayed) * 0x1000000
            lnObj.ps = mineProp[addr].spline
            table.insert(ls, lnObj)
        end
        -- Boom
    end

    return ls
end

function getAllRipples()
    local cs = {}

    if curr_DT >= DT_bounces_too then
        for _, addr in ipairs(mines) do
            for _, ripple in ipairs(mineProp[addr].ripples) do
                table.insert(cs, ripple)
            end
        end

        for _, trail in ipairs(savedTrails) do
            for _, ripple in ipairs(trail.ripples) do
                table.insert(cs, ripple)
            end
        end
    end

    return cs
end


function getMarkers()
    local ms = {}

    if curr_DT >= DT_markers_too then
        for _, addr in ipairs(mines) do
            for _, point in ipairs(mineProp[addr].spline) do
                table.insert(ms, {pnt=point, thickness = 2, colour = markerColour})
            end
        end

        for _, trail in ipairs(savedTrails) do
            for _, point in ipairs(trail.spline) do
                table.insert(ms, {pnt=point, thickness = 2, colour = markerColour})
            end
        end
    end

    return ms
end


-- Just draws the lines returned by getColouredTrails
showHUD(noteProjs, getMarkers, getColouredTrails, nil, getAllRipples, trackTrailsEachFrame)