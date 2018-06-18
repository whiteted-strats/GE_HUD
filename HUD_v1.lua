-- Needs access to Wyster's data from the GE map directory.
require "Data\\GE\\PlayerData"
require "Data\\GE\\GuardData"


-- ============== HUD v1 ================
-- Currently draws red squares over all guards who are in the field of view.
-- Boasts Bond-wobble-stabilisation (tm)
-- Could easily be adapted to mark objects, i.e. the radios in surface 2.

-- Main issue: 'Anti-lag': When bond turns or zooms, the HUD appears to lag.
--  In fact it appears to update ahead of the main game image.
--  I think this will be solved if I only update the HUD when the game actually draws a frame.
--  I don't know where to read if we're on a lag frame or not though..


function dotProduct(v,w)
    return v.x*w.x + v.y*w.y + v.z*w.z
end
function vectorSubtract(v,w)
    return {x=v.x-w.x, y=v.y-w.y, z=v.z-w.z}
end
function scaleVector(v,a)
    return {x=v.x*a, y=v.y*a, z=v.z*a}
end

function updateGlblVars()
    -- "Zoom" : treated as the distance from camera eye to the viewing rectangle.
    --      This is equivalent to just scaling points 'outwards' by this factor
    --      Results suggest we are interpretting it correctly.
    zoom = mainmemory.readfloat(0x0607E0,true)
    -- Values for the thickness of the borders (for if cinema is selected for example)
    topBorderBase = mainmemory.readfloat(0x07C114,true)
    bottomBorderCeiling = mainmemory.readfloat(0x07C11C,true)

    -- Get camera location - assumed to be at bond
    b = PlayerData.get_value("position")

    pdStart = PlayerData.get_start_address()
    -- Azimuth and inclination angles which SEEM to account for Bond's wobbling.
    -- There appear to several such values. These addresses are chosen to be from the same block,
    --   which seems to update the most often.
    -- Particularly sinA is wierd, as the sign is wrong, but we flip it.
    cosA = mainmemory.readfloat(pdStart+0x04C8,true)
    sinA = -mainmemory.readfloat(pdStart+0x04C0,true)
    sinI = mainmemory.readfloat(pdStart+0x04C4,true)
    cosI = mainmemory.readfloat(pdStart+0x04D0,true)

    -- 0 degrees azimuth is +z, 90 is -x.
end

function determineCameraVectors()
    -- The camera's unit direction. Relatively straightforward
    cameraDirc = {["x"]= -sinA*cosI, ["z"] = cosA*cosI, ["y"] = sinI}
    -- The camera up vector. This has the same azimuth but with inclination increased 90 degrees.
    --   This relies on broadening the idea of inclination angle, which is normally in the range 270-90
    -- Recalling cos(x) = sin(x+90), -sin(x) = cos(x+90), we have
    cameraUp = {["x"]=-sinA*(-sinI), ["z"]=cosA*(-sinI), ["y"]=cosI}
    -- With some thought, observe that the cameraRight vector has y = 0 (camera has no roll)
    -- Then the azimuth is incremented by 90. So as above sinA->cosA, cosA->-sinA, cosI->1:
    cameraRight = {["x"] = -cosA, ["z"]=-sinA, ["y"]=0}
end

function addPointToHUD(p)
    -- Take point p and perform our projection to get the vector in the virtual screen
    v = vectorSubtract(p,b)
    dp = dotProduct(v,cameraDirc)

    -- Insist that the point lies in front of the screen, else drop it
    if dp >= 1 then
        screenV = vectorSubtract(scaleVector(v,1/dp),cameraDirc)
        
        -- Now project onto up/right vectors
        up = dotProduct(screenV,cameraUp)
        right = dotProduct(screenV,cameraRight)

        -- Scale in using zoom: literally multiply by it
        -- ALSO by my magical K. Without K it appears that the edge of the screen is 1 unit from the center.
        -- K is half the width of the screen. Oddly this seems to also be correct value for adjusting height too.
        K = 160
        up = up * zoom * K
        right = right * zoom * K

        -- Check the point is in the viewing frustrum (accounting for the borders too)
        if right >= -160 and right <= 160 then
            if up + 120 >= topBorderBase and up + 120 <= bottomBorderCeiling then
                -- Draw it to the screen!
                gui.drawRectangle(centerP.x+right-1,centerP.y-up-1,3,3,0xFFFF0000)
            end
        end
    end
end

HUDdoFrameName = "HUDdoFrame"
function HUDdoFrame()
    -- Get lots of values
    updateGlblVars()
    determineCameraVectors()

    -- Draw the center point
    centerP = {x=160,y=120}
    gui.drawRectangle(centerP.x-1,centerP.y-1,3,3,0xFF00FF00)

    -- Initialise for looping through all the guards
    local lastSlot = GuardData.get_capacity()-1
    local startAddr = GuardData.get_start_address()

    for slotI = 0,lastSlot,1 do
        -- Get this guard's position, p
        local slot_address = (startAddr + (slotI * GuardData.size))
        p = GuardData:get_value(slot_address, "position")

        addPointToHUD(p)
    end
end

-- Don't use events to allow for toggling of the script.
while true do
    HUDdoFrame()
    emu.frameadvance()
end

--while event.unregisterbyname(HUDdoFrameName) do
--    console.log("Existing registered '".. HUDdoFrameName .. "' removed")
--end
--event.onframeend(HUDdoFrame,HUDdoFrameName)
