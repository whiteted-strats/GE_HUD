-- Needs access to Wyster's data from the GE map directory.
require "Data\\GE\\PlayerData"
require "Data\\GE\\PositionData"
require "Data\\GE\\GameData"

-- _lib contains simple stuff, _clip does the line (and pont) clipping in the coordinate system
require "HUD_Matt\\HUD_Matt_lib"
require "HUD_Matt\\HUD_Matt_clip"

-- ============== HUD Matt core ================
-- The 'improved' (different) core for building a heads up display

-- =========== Improvements on v1.732 ============
-- Uses the rotation matrices for a 'perfect HUD'
-- Understands the double frame buffer.. but not very well (see issues)
-- This is actually an encapsulated core now, rather than being an entire HUD example.
--  => polygons and circles are supported cleanly
-- 4:3 resolution detection on each frame

-- * Has parameter for calling 

-- ========= Known Issues ==========
-- BIG: isn't selecting the right matrix very much & only s1 & aztec have matrices
-- Kinda Big: haven't actually tested clipping, it may not be doing it's job.
-- Doesn't cope with the shake from explosions
-- Draws over borders: it's a feature
-- Recently changed to also cache the zoom: probably problems here


-- Adjusting for different 4:3 resolutions. Updated every frame.
local scale = client.bufferwidth()/320
local centerP = {x=scale*160,y=scale*120}


-- Determines the size of the border due to wide,cinema etc.
-- Not using this just yet..
function getBorder()
    local border = {}
    border.topBase = mainmemory.readfloat(0x07C114,true) * scale
    border.bottomCeil = mainmemory.readfloat(0x07C11C,true) * scale
    return border
end


-- ==========  Moving things to the coordinate system (camera at origin, looking down z, zoom = 1) ==========

local function moveToCoordinateSystem(camera, p)
    -- Translate and rotate so that we are at (0,0,0), looking down z
    local rotV = applyHomMatrix(p, camera.rotM)
    -- Apply zoom
    rotV.z = rotV.z / camera.zoom

    -- Seems to be inverted: probably just a convention
    rotV = scaleVector(rotV, -1)

    return rotV
end

local function coord_line(camera, ln)
    coord_ln = {}
    for _, pnt in ipairs(ln) do
        table.insert(coord_ln, moveToCoordinateSystem(camera, pnt))
    end
    return coord_ln
end

local function coord_circle(camera, circle)
    -- Well we needed some linear algebra..
    circle.coarseness = math.max(1, circle.coarseness)
    circle.normal = normalise(circle.normal)

    -- Apply just the rotation to the normal.. and don't use the original normal!
    local n = applyDim3Matrix(circle.normal, camera.rotM)

    -- Orothonormal basis looks fine
    local v,w = getOrthonormalBasis(n)
    local coord_center = moveToCoordinateSystem(camera, circle.center)
    local conv = math.pi / 180

    -- Work out how shallow an angle we're looking at the nearest side of the circle
    -- Think of the circle in a plane, nearest point may actually be inside the circle
    local pn = dotProduct(coord_center,n)
    local inPlane = vectorSubtract(coord_center, scaleVector(n, pn))
    local d = math.abs(length(inPlane) - circle.radius)
    local theta = math.atan(pn / d)
    local sin_theta = math.sin(theta)
    local sin_theta_sq = sin_theta * sin_theta

    -- Now determine the angle around the circle where the near side is. Call v 0, w 90.
    -- Get cos of angle between -(inPlane) and v
    -- We don't know if w or -w is clockwise, but it all comes out in the wash when we rotate
    local len_inPlane = length(inPlane)
    local plv = dotProduct(inPlane,v)
    local cos_azimuth = -plv / len_inPlane
    local plw = dotProduct(inPlane,w)
    -- If it fails, flip a sign here :P
    local sin_azimuth = plw / len_inPlane

    -- Now rotate v and w, so v heads towards the camera (in the plane),
    --   and w is still orthogonal to v, though we've not sure which way
    local t = vectorAdd(scaleVector(v, cos_azimuth), scaleVector(w, sin_azimuth))
    w = vectorAdd(scaleVector(v, -sin_azimuth), scaleVector(w, cos_azimuth))
    v =  t
    
    -- Scale v,w to the circle's radius
    v = scaleVector(v, circle.radius)
    w = scaleVector(w, circle.radius)

    -- Advance around the circle in steps intending to move by a fixed amount (1 pixel atm) when projected
    --   This step is based on:
    --      1. how far the current point is from the eye
    --      2. considering that movement in v is further supressed by atleast sin_theta when we project
    -- It relies on the tangent to the circle at that point being reasonably accurate for our whole step
    -- In future we may also consider the next point's tangent too
    
    -- Keep adding the points to ps and taking steps, until we wrap around (within 1 degree)
    local ps = {}
    local ang = 0
    local s, c
    local p, dSq, estRateSq, estRate, step
    while ang < 359 do
        c = math.cos(conv*ang)
        s = math.sin(conv*ang)
        p = vectorAdd(vectorAdd(coord_center, scaleVector(v,c)), scaleVector(w,s))
        table.insert(ps, p)

        dSq = lengthSq(p)
        estRateSq = (sin_theta_sq * s * s + c * c) / dSq
        estRate = math.sqrt(estRateSq) * circle.radius

        -- Coarseness the number of pixels (at 640/480 res) to aim to draw with a single line
        step = (circle.coarseness / 320) / estRate
        step = step / conv
        step = math.min(step, 60)
        step = math.max(step, 3)
        
        ang = ang + step
    end

    -- Add the first point a second time (shallow copy), so that this is a poly-line
    table.insert(ps, ps[1])

    return ps
end

local function coord_all(camera, pnts, lns, plys, circs)
    -- Points are easy, insert each
    coord_pntObjs = {}
    for _, p in ipairs(pnts) do
        table.insert(coord_pntObjs, {pnt=moveToCoordinateSystem(camera, p.pnt), colour=p.colour, thickness=p.thickness})
    end

    coord_lnObjs = {}
    -- Polygons we can convert to poly-lines, and back
    for _, ply in ipairs(plys) do
        table.insert(ply.ps, ply.ps[1])
        table.insert(coord_lnObjs, {ps=coord_line(camera, ply.ps), colour=ply.colour})
        -- pops that last element back off
        table.remove(ply.ps)
    end

    -- Add the (poly-) lines
    for _, ln in ipairs(lns) do
        table.insert(coord_lnObjs, {ps=coord_line(camera, ln.ps), colour=ln.colour} )
    end

    -- The big one, add the circles
    for _, circle in ipairs(circs) do
        table.insert(coord_lnObjs, {ps=coord_circle(camera, circle), colour=circle.colour})
    end

    return coord_pntObjs, coord_lnObjs
end

-- ============ Projecting from coordinate system to the screen ==============

local function projectCoordPoint(p)
    -- Get the vector within the virtual screen (just x and y), scaling up by our K
    -- * (-1) to flip it, as it seems to be a vector from point to camera.
    -- .. oh dear
    local K = scale*160
    local screenV = scaleVector(p, (-1) * (1/p.z) * K)

    -- Add to center point and return
    return {x=centerP.x+screenV.x, y=centerP.y-screenV.y}
end

-- Inplace project the points
local function projectLineObjs(lns)
    for _, lnObj in ipairs(lns) do
        for i, pnt in ipairs(lnObj.ps) do
            lnObj.ps[i] = projectCoordPoint(pnt)
        end
    end
end
local function projectPointObjs(lns)
    for _, pntObj in ipairs(lns) do
        pntObj.pnt = projectCoordPoint(pntObj.pnt)
    end
end

-- ================== Get / show / hide the HUD ==================

-- Defaults show nothing / do nothing
local userInit = function ()
    --
end
local getMarkers = function ()
    return {}
end
local getLines = function ()
    return {}
end
local getPolygons = function ()
    return {}
end
local getCircles = function ()
    return {}
end
local initEveryFrame

-- The name of our frame_end event function
local funcName = "Whiteted_HUD_Matt_core"
-- To hide the HUD, all end_frame events created by HUD core are cleared
function hideHUD()
    while event.unregisterbyname(funcName) do
        --
    end
end
-- To show a new HUD, we clear any old ones, update markers func and add the event
-- The followers are initialised
-- initEveryFrame defaults to nil, hence false
function showHUD(userInitFunc, getMarkersFunc, getLinesFunc, getPolygonsFunc, getCirclesFunc, paramInitEveryFrame)
    hideHUD()

    -- If the user doesn't supply a new function, the previous one / default of nothing is used
    if getMarkersFunc ~= nil then
        getMarkers = getMarkersFunc
    end
    if getLinesFunc ~= nil then
        getLines = getLinesFunc
    end
    if getPolygonsFunc ~= nil then
        getPolygons = getPolygonsFunc
    end
    if getCirclesFunc ~= nil then
        getCircles = getCirclesFunc
    end
    if userInitFunc ~= nil then
        userInit = userInitFunc
    end
    initEveryFrame = paramInitEveryFrame

    prev_dc = getDrawCounter()
    the_HUD = nil
    cameraBuffer = {}

    event.onframeend(onFrameEnd,funcName)
end

local function getHUD(camera)
    -- Call user init func
    userInit()
    -- Call all the user functions, and move all to the coordinate system
    coord_pntObjs, coord_lnObjs = coord_all(camera, getMarkers(), getLines(), getPolygons(), getCircles())
    local HUD = {}

    -- Clip these
    HUD.pntObjs = clipPointObjs(coord_pntObjs)
    HUD.lnObjs = clipPolyLineObjs(coord_lnObjs)

    -- Project these inPlace
    projectPointObjs(HUD.pntObjs)
    projectLineObjs(HUD.lnObjs)

    return HUD
end

-- =================== Drawing the HUD (markers and lines) ========================

-- Draws a marker at the 2D location, of the specified thickness
-- Could even specify how big the unmarked inside should be
local function drawMarker(pntObj)
    for i=1, pntObj.thickness, 1 do
        gui.drawRectangle(pntObj.pnt.x-i, pntObj.pnt.y-i, 2*i+1,2*i+1, pntObj.colour)
    end
end

-- Draws a single poly-line
local function drawPolyLine(lnObj)
    local n = table.getn(lnObj.ps) 
    local p,q
    for i = 1, n-1, 1 do
        p = lnObj.ps[i]
        q = lnObj.ps[i+1]
        gui.drawLine(p.x, p.y, q.x, q.y, lnObj.colour)
    end
end

local function drawHUD(HUD)
    if not (HUD == nil) then
        -- Draw the markers over the lines
        for _, lnObj in ipairs(HUD.lnObjs) do
            drawPolyLine(lnObj)
        end
        for _, pntObj in ipairs(HUD.pntObjs) do
            drawMarker(pntObj)
        end
    end
end

-- ============================ Main routine ==============================


-- Caches and follower for drawing the HUD
local the_HUD = nil
local prev_dc
local cameraBuffer = {[0] = nil, [2] = nil}


-- Maps (mission #) -> (drawCounter mod 4) -> (player data offset of matrix)
local matricesOffsets = {
    -- Aztec
    [0x1A]={[2]=0x20B40, [0]=0x2AB40},
    -- Surface 1
    [0x05]={[2]=0x25B40, [0]=0x32340},
    -- Caverns
    [0x17]={[2]=0x34B40, [0]=0x41340}
}

-- The function which we run every frame while the HUD is active
function onFrameEnd()
    local dc = getDrawCounter()
    local border = getBorder()

    local missionNum = GameData.get_current_mission()
    if missionActive() and (not (matricesOffsets[missionNum] == nil))  then
        -- Update scale and center point
        scale = client.bufferwidth()/320
        centerP = {x=scale*160,y=scale*120}

        -- If we Detect a draw on this frame,
        if (dc ~= prev_dc)  then
            gui.drawText(0,0,"Draw! (parity " .. (dc % 4) .. ")")
            -- Offsets from playerdata as there is something of a pattern here..
            local matAddr = PlayerData.get_start_address() + matricesOffsets[missionNum][dc % 4]
            local camera = cameraBuffer[dc % 4]
            if camera ~= nil then
                -- Update the HUD
                the_HUD = getHUD(camera)
            end
            
            -- Update this camera buffer
            -- Makes us behave well in low lag, awfully in high lag..
            cameraBuffer[dc % 4] = {}
            cameraBuffer[dc % 4].rotM = matrixFromMainMemory(matAddr)
            cameraBuffer[dc % 4].zoom = getCameraZoom()
        else
            -- Still call userInit if they've requested this every frame
            if initEveryFrame then
                userInit()
            end
        end

        -- Draw the HUD again regardless (potentially with the same image)
        drawHUD(the_HUD)
    else
        -- If no supported mission is active, clear the HUD
        the_HUD = nil
        cameraBuffer = {}
    end
    
    -- Regardless of whether the mission is active, update our follower
    prev_dc = dc
end
