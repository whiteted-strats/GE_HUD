require "HUD_Matt\\HUD_matt_core"
require "HUD_Matt\\HUD_matt_lib"
require "Data\\GE\\PlayerData"
require "Data\\GE\\PositionData"
require "HUD_Matt\\matrix_inverse"

function readPtr(addr, offset)
    if addr == 0 then
        return 0
    end
    addr = mainmemory.read_u32_be(addr + offset)
    if addr == 0 then
        return 0
    else
        return addr - 0x80000000
    end
end

local function getGuardAzimuthAngle(modelDataAddr)
    -- Finally this old discovery comes good
    unknown = readPtr(modelDataAddr, 0x10)
    -- Very similar values at 0x20, 0x30
    return mainmemory.readfloat(unknown + 0x14, true)
end

local function getMatrixNumber(skeletonObjPtr)
    -- 7f06c570 NTSC-U
    local type = 0
    local embeddedObjAddr = 0
    while skeletonObjPtr ~= 0 do
        type = mainmemory.read_u8(skeletonObjPtr + 0x1)
        embeddedObjAddr = readPtr(skeletonObjPtr, 0x4)

        if type == 1 then
            return mainmemory.read_u16_be(embeddedObjAddr + 0x2)
        elseif type == 2 or type == 3 then
            return mainmemory.read_u16_be(embeddedObjAddr + 0xe)
        elseif type == 0x15 then
            return mainmemory.read_u16_be(embeddedObjAddr + 0xc)
        end

        skeletonObjPtr = readPtr(skeletonObjPtr, 0x8)
    end

    return -1
end

local function walkSkeletonForEach(skeletonRoot, f)
    -- In the style of Henrik's .for_each
    -- Mimicing 7f06f0d0, though skeletonRoot is already read
    sdr = {}
    sdr.current_address = skeletonRoot
    while true do
        sdr.type = mainmemory.read_u8(sdr.current_address + 0x1)
        f(sdr)

        nextAddr = readPtr(sdr.current_address, 0x14)
        if nextAddr == 0 then
            nextAddr = readPtr(sdr.current_address, 0xc)
            innerAddr = sdr.current_address
            -- RE here was interesting, the compiler has been pretty smart
            while nextAddr == 0 do
                innerAddr = readPtr(innerAddr, 0x8)
                if innerAddr == 0 then  -- Reached root once more
                    return
                end
                nextAddr = readPtr(innerAddr, 0xc)
            end
        end

        sdr.current_address = nextAddr
    end

end

local function getHitboxCorners(bodyPartPtr, M)
    flts = {}
    for off=0x4,0x18,0x4 do
        table.insert(flts, mainmemory.readfloat(bodyPartPtr + off, true))
    end

    xs = {1,2,2,1}
    zs = {5,5,6,6}
    lowPnts = {}
    highPnts = {}
    for i=1,4,1 do
        table.insert(lowPnts, applyHomMatrix({
            ["x"] = flts[xs[i]],
            ["y"] = flts[3],
            ["z"] = flts[zs[i]],
        }, M))
        table.insert(highPnts, applyHomMatrix({
            ["x"] = flts[xs[i]],
            ["y"] = flts[4],
            ["z"] = flts[zs[i]],
        }, M))
    end

    return {
        ["low"] = lowPnts,
        ["high"] = highPnts,
    }
end

-- Body part number 7 coincides with the guard's position (just by HUD-observation, including during death anim)

BP_LEFT_FOOT = 1
BP_LEFT_SHIN = 2
BP_LEFT_THIGH = 3

BP_RIGHT_FOOT = 4
BP_RIGHT_SHIN = 5
BP_RIGHT_THIGH = 6

BP_HIPS = 7
BP_HEAD = 8

BP_LEFT_HAND = 9
BP_LEFT_FOREARM = 10
BP_LEFT_UPPER_ARM = 11

BP_RIGHT_HAND = 12
BP_RIGHT_FOREARM = 13
BP_RIGHT_UPPER_ARM = 14

BP_CHEST = 15

-- GLOBAL VARS

local bodyParts = {}
local guardPos = {x=0,y=0,z=0}
-- The guard position must be set globally, because we've decoupled reading the matrices & using them,
--   in order to solve the matrices being overwritten.
local guardPosAddr = nil
-- These matrices are at [0 -> 17], the matrix numbers.
-- Be sure to check that it's not nil
Ms = {}


local function getReg(s)
	local v = emu.getregister(s) -- why are these signed?
	if v < 0 then
		return v + 0x100000000
	else
		return v
	end
end

local function updateHitboxMatrices()
    if guardPosAddr == nil then
        return
    end

	-- We've just written to a matrix - if it's one we're interested in then update
    local outMatrixAddr = getReg("a2_lo")
    local guardDataAddr = readPtr(guardPosAddr, 0x4)
    local modelDataAddr = readPtr(guardDataAddr, 0x1c)
	local matrixListAddr = mainmemory.read_u32_be(modelDataAddr + 0xC)

	local offset = outMatrixAddr - matrixListAddr
	if offset < 0 then
		return
	end
	if offset % 0x40 ~= 0 then
		return
	end

	offset = bit.band(offset / 0x40, 0xFFFFFFFF)
    if offset < 18 then
        -- We're interested, read the matrix
        Ms[offset] = matrixFromMainMemory(outMatrixAddr - 0x80000000)
        -- Final value is set in the delay slot, we may not catch it.
        -- Fuck luas 1-based indices
        Ms[offset][4][4] = 1.0
	end
end


local function positionBodyParts()
    local guardDataAddr = readPtr(guardPosAddr, 0x4)
    local modelDataAddr = readPtr(guardDataAddr, 0x1c)

    -- We need [4] and the gut's matrix to correct these matrices.
    if Ms[4] == nil or Ms[bodyParts[7].matrixNumber] == nil then
        return
    end

    -- Fixes the guard's position, and his facing direction,
    --  but all other aspects of the animation are preserved.
    local correctionMatrix = scaleMatrix(
        inverse(Ms[4]),
        0.1 -- don't ask.
    )
    local guardAziAngle = getGuardAzimuthAngle(modelDataAddr)
    local guardAziMatrix = {
        {math.cos(guardAziAngle), 0, -math.sin(guardAziAngle), 0},
        {0,1,0,0},
        {math.sin(guardAziAngle), 0, math.cos(guardAziAngle), 0},
        {0,0,0,1},
    }

    -- Then apply the azimuth rotation
    correctionMatrix = matMult(correctionMatrix, guardAziMatrix)


    -- Apply against [7] first, and use that to determine the correction offset
    -- Note that repeating this for [7] below isn't an issue
    local gutMatrix = matMult(Ms[bodyParts[7].matrixNumber], correctionMatrix)
    local offset = {
        guardPos.x - gutMatrix[4][1],   -- guardPos global, because it's used by the drawing
        guardPos.y - gutMatrix[4][2],
        guardPos.z - gutMatrix[4][3],
    }

    for _, data in pairs(bodyParts) do
        if Ms[data.matrixNumber] ~= nil then
            data.M = matMult(Ms[data.matrixNumber], correctionMatrix)
            for j = 1,3,1 do
                data.M[4][j] = data.M[4][j] + offset[j]
            end

            data.pos = applyHomMatrix(
                {
                    ["x"] = 0,
                    ["y"] = 0,
                    ["z"] = 0,
                }, 
                data.M
            )
            corners = getHitboxCorners(data.bodyPartPtr, data.M)
            data.high = corners.high
            data.low = corners.low
            data.positioned = true
        end
    end

end


local function getBodyParts()
    -- Pos Data -> Guard Data -> model Data -> ? -> skeleton root
    local guardDataAddr = readPtr(guardPosAddr, 0x4)
    local modelDataAddr = readPtr(guardDataAddr, 0x1c)
    local skeletonRoot = readPtr(readPtr(modelDataAddr, 0x8), 0x0)

    bodyParts = {}
    local count = 0

    local function noteHitboxes(sdr)
        if sdr.type == 0xA then
            count = count + 1

            local data = {}
            data.bodyPartPtr = readPtr(sdr.current_address, 0x4)
            data.bodyPartNumber = mainmemory.read_u16_be(data.bodyPartPtr + 0x2)
            data.matrixNumber = getMatrixNumber(sdr.current_address)
            data.positioned = false

            bodyParts[data.bodyPartNumber] = data
            
            --gui.drawText(10,25 + count*15, string.format("Body part #" .. data.bodyPartNumber .. " 0x%X, matrix # = " .. data.matrixNumber, sdr.current_address))
            
        end
    end

    walkSkeletonForEach(skeletonRoot, noteHitboxes)

end

-- Place a marker at their position
local function markBodyParts()
    local ms = {}

    -- Special guard marker
    local marker = {}
    marker.pnt = guardPos
    marker.thickness = 3
    marker.colour = 0xFF00AA00

    table.insert(ms, marker)

    for _, data in pairs(bodyParts) do
        if data.positioned then
            local marker = {}
            marker.pnt = data.pos
            marker.thickness = 2
            marker.colour = 0xFFAA0000
            table.insert(ms, marker)
        end
    end

    return ms
end

local colourful = {0xFFFF0000, 0xFF00BB00, 0xFF0000FF}
local colourless = {0xFF884444, 0xFF448844, 0xFF444488}
local colour = colourful

local function drawFaces()
    local ps = {}
    
    for _, data in pairs(bodyParts) do
        if data.positioned then
            local lowPly = {}
            local highPly = {}
            lowPly.colour=colour[1] -- red bottom, green top
            highPly.colour=colour[2]
            lowPly.ps = {}
            highPly.ps = {}

            for i = 1,4,1 do
                table.insert(lowPly.ps, data.low[i])
                table.insert(highPly.ps, data.high[i])
            end

            table.insert(ps, lowPly)
            table.insert(ps, highPly)
        end
    end

    return ps
end

local function linkFaces()
    local ps = {}

    for _, data in pairs(bodyParts) do
        if data.positioned then
            for i = 1,4,1 do
                local ln = {}
                ln.colour = colour[3]
                ln.ps = {
                    data.low[i],
                    data.high[i],
                }
                table.insert(ps, ln)
            end
        end
    end

    return ps
end

local function eachFrame()
    -- Find an on-screen guard
    local stop = mainmemory.read_u32_be(0x071df0) - 0x80000000
    local start = 0x071620
    local posDataAddr = 0x0
    for addr=start,stop,4 do
        posDataAddr = readPtr(addr, 0)
        if posDataAddr ~= 0 then
            if mainmemory.read_u8(posDataAddr) == 0x3 then
                break
            end
        end
    end

    -- Trev on statue
    --posDataAddr = 0x69e40

    if posDataAddr == 0 then
        gui.drawText(10,10, "No guard on screen")
        guardPosAddr = nil
        guardPos = {x=0,y=0,z=0}
        Ms = {}
        bodyParts = {}
    else
        -- If the guard is new, clear the matrices, and find the bodyParts again
        if guardPosAddr ~= posDataAddr then
            gui.drawText(10,10, "New guard")

            Ms = {}
            guardPosAddr = posDataAddr
            getBodyParts()
        end

        -- Update the guard position
        guardPos = PositionData:get_value(guardPosAddr, "position")

        positionBodyParts()
    end
end




-- On the return from the matrixMultiply call. We set '[3][3]' = 1 ourselves
event.onmemoryexecute(updateHitboxMatrices, 0x7f05826c)

-- Main call to set up the HUD
showHUD(eachFrame, markBodyParts, linkFaces, drawFaces, nil, true)


-- NOTES
-- For the shot direction,
-- 0x7f03b1ac is just after the call to "makeTheShot"
-- *(sp + 0x4) points to the point3D of the direction - from Bond's POV, but we've effectively recovered the global matrix
-- => still would be nice to have somewhere to read this, lets make some brute-forcer.