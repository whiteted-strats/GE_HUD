-- Although not required for drawing points, drawing lines requires clipping
-- We also clip points since it is pretty free.
-- Exports:
--  1. clipPointObjs(ps)
--  2. clipPolyLineObjs(lns)

require "HUD_Matt_lib"

-- The faces of the viewing frustrum, in the VIEW COORDINATE SYSTEM, with the camera eye at the origin
-- ref: http://n64.icequake.net/doc/n64intro/kantan/step3/index3.html (3.3.4 View Co-ordinate System)
-- These are with distance 1 from eye to screen center, 1 from center to right edge, 3/4 from center to top edge.
-- Top & Bottom, even Left & Right, could actually be around the wrong way but it's all good.
-- Normals point into the frustum
local leftNormal = {x=1, y=0, z=1}
local rightNormal = {x=-1, y=0, z=1}
local topNormal = {x=0, y=-1, z=3/4}
local bottomNormal = {x=0, y=1, z=3/4}
local ns = {leftNormal, rightNormal, topNormal, bottomNormal}

-- Returns p if in view, else nil
local function clipPoint(p)
    for _, normal in ipairs(ns) do
        if dotProduct(p,normal) < 0 then
            return nil
        end
    end
    
    return p
end

-- Takes a table of point objects, returns a table of those in view
function clipPointObjs(ps)
    local res
    local inView = {}
    for _, pntObj in ipairs(ps) do
        res = clipPoint(pntObj.pnt)
        if res then
            table.insert(inView, pntObj)
        end
    end

    return inView
end

-- Returns the sub-seqment {p',q'} of the line that is in the view, or nil if none of it is.
local function clipLine(p,q)
    --print("Begin clipLine")
    -- Handle degenerate case (line direction undefined), using clipPoint
    if p == q then
        print("Degenerate case")
        p = clipPoint(p)
        if p == nil then
            return nil
        else
            return {p, q}
        end
    end

    -- The line segment is f(k) = p+k*v, for k in [0,1]
    -- So f(k).n = p.n + k*v.n. Interested when this is 0, and how it changes with k
    -- Encode the currently clipped line segment by k-values, initially 0 and 1.
    v = vectorSubtract(q,p)
    l = 0
    h = 1

    -- Clip against each of the 4 planes
    for _, normal in pairs(ns) do
        vn = dotProduct(v,normal)
        pn = dotProduct(p,normal)
        -- Handle the parallel case: The inf. line is entirely in, or out, of view
        if vn == 0 then
            if pn < 0 then
                return nil, false
            end
        else
            -- Else, get the value of k for which the line pierces intersects the plane
            k_0 = -pn / vn
            -- Consider the direction, to determine if [k_0, inf) or (-inf, k_0] is the portion in view.
            -- As k increases (from k_0), d/dk( f(k).n) = v.n
            if vn > 0 then
                -- Intersect [l,h] with [k_0, inf)
                l = math.max(l,k_0)
            else
                -- Intersect [l,h] with (inf, k_0]
                h = math.min(h,k_0)
            end

            -- If no line segment remains, return nil
            if h < l then
                return nil, false
            end
        end
    end

    -- Recover p' and q' from l,h, and return:
    -- 1. the line
    -- 2. whether the endpoint, q, is inView
    q_ = vectorAdd(p, scaleVector(v,h))
    p_ = vectorAdd(p, scaleVector(v,l))
    return {p_, q_}, (h == 1)
end

function clipPolyLineObjs(lns)
    local inView = {}
    local currPolyLine
    local p, q
    local lnSeg, trimmedEnd
    for _, lnObj in ipairs(lns) do
        local ln = lnObj.ps
        local n = table.getn(ln)
        currPolyLine = {}
        trimmedEnd = false
        for i = 1,(n-1),1 do
            -- Clip this segment
            p = ln[i]
            q = ln[i+1]
            lnSeg, qInview = clipLine(p, q)

            if lnSeg == nil then
                -- If none of the line is visible, then p isn't, so q was out of view last iteration, or it's the first iteration
                if table.getn(currPolyLine) ~= 0 then
                    error("Algorithm error: currPolyLine should be empty")
                end
            else
                -- Either insert the whole lnSeg, or just the last point
                if table.getn(currPolyLine) == 0 then
                    currPolyLine = lnSeg
                else
                    table.insert(currPolyLine, lnSeg[2])
                end

                -- If q wasn't in view, then add this segment and reset the currPolyLine
                -- Also if i == n-1, for cleanness
                if (not qInview) or (i == n-1) then
                    table.insert(inView, {ps = currPolyLine, colour=lnObj.colour})
                    currPolyLine = {}
                end
            end
        end
    end

    return inView      
end
