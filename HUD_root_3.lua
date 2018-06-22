-- Needs access to Wyster's data from the GE map directory.
require "Data\\GE\\PlayerData"
require "Utilities\\GE\\GuardDataReader"

-- ============== HUD v1.732 ================
-- Currently draws red squares over all alive guards who are in the field of view.
-- Could easily be adapted to mark objects, i.e. the radios in surface 2.

-- ========= Improvements on v1.0 ===========
-- Updates only when frames are drawn
-- Caches camera early: no lag even as Bond turns sharply, nor on zoom
-- Bond wobble accounted for: The HUD properly accounts for Bond's aim swaying slightly
-- Look-down / up fixed: HUD no longer gets severely warped

-- ============= Minor issues ===============
-- Occassionally a draw happens 1 frame earlier than we predicted, and so HUD is behind.
--   This mistake does not snowball, and is probably unnoticable when playing in real time.

function dotProduct(v,w)
    return v.x*w.x + v.y*w.y + v.z*w.z
end
function vectorSubtract(v,w)
    return {x=v.x-w.x, y=v.y-w.y, z=v.z-w.z}
end
function scaleVector(v,a)
    return {x=v.x*a, y=v.y*a, z=v.z*a}
end

-- Determines the size of the border due to wide,cinema etc.
function getBorder()
    local border = {}
    border.topBase = mainmemory.readfloat(0x07C114,true)
    border.bottomCeil = mainmemory.readfloat(0x07C11C,true)
    return border
end

-- Determines all important properties of the camera in this instance, 
--   assuming that the camera is "Bond's eye" (which is not the case in most cutscenes)
function determineCamera()
    local camera = {}

    -- "Zoom" : treated as the distance from camera eye to the viewing rectangle.
    --      This is equivalent to just scaling points 'outwards' by this factor
    --      Results suggest we are interpretting it correctly.
    camera.zoom = mainmemory.readfloat(0x0607E0,true)

    -- Get camera location - assumed to be at bond
    camera.loc = PlayerData.get_value("position")

    pdStart = PlayerData.get_start_address()

    -- We are satisfied that these represent the wobbled-inclination sine and cosine
    sinI = mainmemory.readfloat(pdStart+0x04C4,true)
    cosI = mainmemory.readfloat(pdStart+0x04D0,true)
    
    -- But other nearby values seem to be slightly conflicting products which we can't deal with.
    -- So for the azimuth values, we use the 'left_wobble' that we found,
    --   we mimican Observed relation between 'up_wobble' and the sinI,cosI values above.
    -- This is adding 1/sqrt(3) * the left_wobble to the azimuth angle.
    up_wobble_addr = pdStart + 0x0530
    left_wobble_addr = pdStart + 0x052c
    left_wobble = mainmemory.readfloat(left_wobble_addr,true)
    A = PlayerData.get_value("azimuth_angle")
    adjusted_A = A - left_wobble/math.sqrt(3)

    -- Convert to radians and determine the sine, cosine.
    adjusted_A = adjusted_A * (math.pi / 180)
    cosA = math.cos(adjusted_A)
    sinA = math.sin(adjusted_A)

    -- 0 degrees azimuth is +z, 90 is -x.

    -- The camera's unit direction. Relatively straightforward
    camera.dirc = {["x"]= -sinA*cosI, ["z"] = cosA*cosI, ["y"] = sinI}
    -- The camera up vector. This has the same azimuth but with inclination increased 90 degrees.
    --   This relies on broadening the idea of inclination angle, which is normally in the range 270-90
    -- Recalling cos(x) = sin(x+90), -sin(x) = cos(x+90), we have
    camera.up = {["x"]=-sinA*(-sinI), ["z"]=cosA*(-sinI), ["y"]=cosI}
    -- With some thought, observe that the cameraRight vector has y = 0 (camera has no roll)
    -- Then the azimuth is incremented by 90. So as above sinA->cosA, cosA->-sinA, cosI->1:
    camera.right = {["x"] = -cosA, ["z"]=-sinA, ["y"]=0}

    return camera
end

-- Takes a point p and performs our projection to get the vector in the virtual screen,
--  then maps it onto the actual screen. Returns nil if it isn't in view.
-- For resolutions different to 320x240, say AxB, change K to be A/2 and this should work.
-- The center point in drawHUD will also need to move.
function getHUDpoint(p,camera,border)
    -- Get the displacement from the camera, and ahead component length.
    v = vectorSubtract(p,camera.loc)
    dp = dotProduct(v,camera.dirc)

    -- Insist that the point lies in front of the screen, else drop it
    -- Potentially this should be 1/zoom..
    if dp >= 1 then
        -- Get the vector within the virtual screen
        screenV = vectorSubtract(scaleVector(v,1/dp),camera.dirc)
        
        -- Now project onto up/right vectors
        up = dotProduct(screenV,camera.up)
        right = dotProduct(screenV,camera.right)

        -- Scale in using zoom: literally multiply by it
        -- ALSO by my magical K. Without K it appears that the edge of the screen is 1 unit from the center.
        -- K is half the width of the screen. Oddly this seems to also be correct value for adjusting height too.
        K = 160
        up = up * camera.zoom * K
        right = right * camera.zoom * K

        -- Check the point is in the viewing frustrum (accounting for the borders too)
        if right >= -K and right <= K then
            if up + 0.75*K >= border.topBase and up + 0.75*K <= border.bottomCeil then
                -- If so return the point to draw
                return {x=centerP.x+right, y=centerP.y-up}
            end
        end
    end
    -- Return nil for no point
    return nil
end

function getHUDps(camera,border)
    nHUDps = {}

    function projectGuard(g)
        -- Presumably could use get_value equivelently
        pos = g:get_position()

        p = getHUDpoint(pos,camera,border)
        if p ~= nil then
            table.insert(nHUDps,p)
        end
    end

    -- Call the guardDataReader to populate nHUDps
    GuardDataReader.for_each(projectGuard)

    return nHUDps
end

function drawHUD(ps)
    -- Draw the center point green (potentially a pixel off)
    centerP = {x=160,y=120}
    gui.drawRectangle(centerP.x-1,centerP.y-1,3,3,0xFF00FF00)

    -- Draw all other points red atm
    for _, p in pairs(ps) do
        gui.drawRectangle(p.x-1,p.y-1,3,3,0xFFFF0000)
    end
end

-- =====================================================

local counter = mainmemory.read_u32_be(0x04837C)
local updateOn = {}
local HUDps = {}

-- Loop allows for toggling of the script.
while true do
    -- Odd hack to find out if we are drawing a frame.
    -- Seems that this global timer or counter increases 2 frames before any draw.
    prevCounter = counter
    counter = mainmemory.read_u32_be(0x04837C)

    fc = emu.framecount()

    if prevCounter ~= counter then
        -- A draw has begun. Store the previous frame's camera, ready for when the frame has been drawn
        updateOn[fc+2] = prevFrameCamera
    end

    -- If we predicted a draw would finish on this frame, remember the correct camera, and update the HUD
    if updateOn[fc] ~= nil then
        -- Get fresh border and use current positions.. but the previous game-frame's previous frame's camera.
        border = getBorder()
        HUDps = getHUDps(updateOn[fc], border)
    end
    -- Destroy the old camera: no memory trouble here.
    updateOn[fc] = nil

    -- Draw the HUD again regardless (potentially with the same image)
    drawHUD(HUDps)

    -- Store the current frame's camera, for if we detect that a draw has begun in the next frame.
    prevFrameCamera = determineCamera()

    emu.frameadvance()
end