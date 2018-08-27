-- Basic vector functions, 'missionActive', various get[property]s and matrix functions
-- Matrices are a table of rows, which are tables of entries

function dotProduct(v,w)
    return v.x*w.x + v.y*w.y + v.z*w.z
end
function vectorSubtract(v,w)
    return {x=v.x-w.x, y=v.y-w.y, z=v.z-w.z}
end
function vectorAdd(v,w)
    return {x=v.x+w.x, y=v.y+w.y, z=v.z+w.z}
end
function scaleVector(v,a)
    return {x=v.x*a, y=v.y*a, z=v.z*a}
end
function lengthSq(v)
    return dotProduct(v,v)
end
function length(v)
    return math.sqrt(lengthSq(v))
end
function normalise(v)
    return scaleVector(v, 1 / length(v))
end


-- Reads the draw counter, which ticks in steps of 2, mod 32
function getDrawCounter()
    return mainmemory.readbyte(0x0607CB)
end

-- Camera zoom value
function getCameraZoom() 
    return mainmemory.readfloat(0x0607E0,true)
end


function missionActive()
    -- Currently avoids the cutscene and the brief loading bit before that,
    --   but now in version 3, we should support the cutscenes really..
    local state = GameData.get_mission_state()
    local res = (GameData.get_global_timer() > 0
        and state ~= 0x3
        and GameData.get_mission_time() > 0
        and state ~= 0x0)

    return res and true or false
end


-- Multiplies two matrices A,B => AB
function matMult(A,B)
    local rows = table.getn(A)
    local cols = table.getn(B[1])
    local k_A = table.getn(A[1])
    local k_B = table.getn(B)
    if k_A ~= k_B then
        error("Attempted to multiply matrices of dimensions " .. rows .. "x" .. k_A .. " and " .. k_B .. "x" .. cols .. ".")
    end

    local AB = {}
    for i=1,rows,1 do
        local rowOut = {}
        for j=1,cols,1 do
            local sum = 0
            for k=1,k_A,1 do
                sum = sum + A[i][k]*B[k][j]
            end
            table.insert(rowOut,sum)
        end
        table.insert(AB,rowOut)
    end
    
    return AB
end


-- Builds a 4x4 matrix of floats from the given address
function matrixFromMainMemory(addr)
    local M = {}
    for i = 0,3,1 do
        local R = {}
        for j = 0,3,1 do
            local val = mainmemory.readfloat(addr + 0x10 * i + 0x04 * j, true)
            table.insert(R,val)
        end
        table.insert(M,R)
    end

    return M
end

-- Applies a 4x4 matrix to a {x,y,z} vector by homogeneity and right multiplication
function applyHomMatrix(v,M)
    local hom_v = {{v.x, v.y, v.z, 1}}
    local res = matMult(hom_v,M)
    return {x=res[1][1], y=res[1][2], z=res[1][3]}
end

-- Applies just the 3x3 (rotation) matrix
function applyDim3Matrix(v,M)
    local num_v = {{v.x, v.y, v.z}}
    -- Overly long rows won't be an issue, though it may compute the last row actually
    local T = {M[1], M[2], M[3]}
    local res = matMult(num_v, T)
    return {x=res[1][1], y=res[1][2], z=res[1][3]}
end


-- Given a normal vector, get two unit vectors, at 90 degrees to each other, in the plane defined by that normal
function getOrthonormalBasis(n)
    -- Obtain 2 vectors in the plane, not linearly dependent
    local v, w, vw
    -- 3 vectors, each in the plane, one potentially 0, PAIRWISE INDEPENDENT
    local a = {x=0, y=-n.z, z=n.y}
    local b = {x=-n.z, y=0, z=n.x}
    local c = {x=-n.y, y=n.x, z=0}

    -- Crucially m ~= 0, but not small is good too
    local m = math.max(math.abs(n.x), math.abs(n.y), math.abs(n.z))
    -- Choose 2 from a,b,c, which we know are not 0, i.e. contain m
    if math.abs(n.x) == m then
        v = b
        w = c
    elseif math.abs(n.y) == m then
        v = a
        w = c
    elseif math.abs(n.z) == m then
        v = a
        w = b
    else
        error("Dropped out of if.. elseif..")
    end

    -- Now apply Gram–Schmidt
    v = normalise(v)
    vw = dotProduct(v,w)
    w = vectorSubtract(w, scaleVector(v,vw))
    w = normalise(w)

    return v,w
end
