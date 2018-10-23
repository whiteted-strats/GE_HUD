require "Utilities\\GE\\GuardDataReader"
require "Data\\GE\\GuardData"
require "Data\\GE\\PositionData"
require "HUD_Matt\\HUD_Matt_core"
require "HUD_Matt\\HUD_Matt_lib"

local guards = {}

function selectGuards()
    guards = {}
    -- Determine which guards we're interested in, and get various bits of data for reuse
    -- These are the VISIBLE (more general than just in-view) guards
    function processGuard(g)
        local flags = PositionData:get_value(g:get_value("position_data_pointer") - 0x80000000, "flags")
        local visible = (flags % 4) / 2

        if visible == 1 then
            local data = {pos = g:get_position()}
            data.cr = g:get_value("collision_radius")
            data.collision_diamond = { vectorAdd(data.pos, {x=0,y=0,z=data.cr}),
                vectorAdd(data.pos, {x=data.cr,y=0,z=0}),
                vectorAdd(data.pos, {x=0,y=0,z=-data.cr}),
                vectorAdd(data.pos, {x=-data.cr,y=0,z=0})
            }

            guards[g.current_address] = data
        end
    end

    GuardDataReader.for_each(processGuard)
end

-- Place a marker at their position
function markGuards()
    local ms = {}
    for addr, data in pairs(guards) do
        local marker = {}
        marker.pnt = data.pos
        marker.thickness = 2
        marker.colour = 0xFFAA0000
        table.insert(ms, marker)
    end

    return ms
end

-- Draw a cross over the guards diamond: testing the lines
function crossGuards()
    local ls = {}
    for addr, data in pairs(guards) do
        for i=1,2,1 do
            local lnObj = {}
            lnObj.colour = 0xFF00AA00
            lnObj.ps = {data.collision_diamond[i], data.collision_diamond[i+2]}
            table.insert(ls, lnObj)
        end
    end

    return ls
end

function drawCollisionDiamonds()
    local ps = {}
    for addr, data in pairs(guards) do
        local ply = {ps=data.collision_diamond, colour=0xFF0000AA}
        table.insert(ps,ply)
    end

    return ps
end

function drawCollisionCircles()
    local cs = {}
    for addr, data in pairs(guards) do
        local circle = {radius=data.cr,
            center=data.pos,
            normal={x=0,y=1,z=0},
            coarseness = 5}
        table.insert(cs, circle)
    end
    return cs
end

-- nil is the (poly-)line function, can replace with 'crossGuards'
showHUD(selectGuards, markGuards, nil, drawCollisionDiamonds, drawCollisionCircles)
