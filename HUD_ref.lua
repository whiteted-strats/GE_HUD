require "Utilities\\GE\\GuardDataReader"
require "Data\\GE\\GuardData"
require "Data\\GE\\PositionData"
require "HUD_matt_core"
require "HUD_matt_lib"

-- Places a marker at a single peak in s1, for reference
-- (Guards are more complex because they move, so this is good for testing the HUD's lag)
function markPeak()
    local marker = {}
    -- Taken from the GE editor
    marker.pnt = scaleVector({x=-7328, y=225, z=-9363}, 1/0.4544571340)
    marker.thickness = 2
    marker.colour = 0xFFAA0000

    return {marker}
end

showHUD(nil, markPeak, nil, nil, nil)