require "HUD_Matt\\HUD_matt_lib"

function det(M,i)
    if i == nil then
        i = 1
    end
    local n = table.getn(M)

    -- Base case
    if n == 0 then
        return 1
    end

    local d = 0
    for j=1,n,1 do
        -- i in, j down
        local v = M[j][i]

        -- Build matrix ignoring this row
        local T = {}
        for k=1,n,1 do
            if k ~= j then
                table.insert(T,M[k])
            end
        end

        -- Get det of this
        local childDet = det(T,i+1)

        -- Alternately add and subtract (add first)
        local sign = (j % 2) * 2 - 1
        d = d + sign * childDet * v
    end

    return d
end

function transpose(M)
    local n = table.getn(M)
    local T = {}
    for i=1,n,1 do
        table.insert(T, {})
        for j=1,n,1 do
            -- T[i][j] = M[j][i]
            table.insert(T[i], M[j][i])
        end
    end

    return T
end

local function minor(M, i, j)
    local n = table.getn(M)
    local m = {}
    for x=1,n,1 do
        if x ~= i then
            local temp = {}
            for y=1,n,1 do
                if y ~= j then
                    table.insert(temp, M[x][y])
                end
            end
            table.insert(m, temp)
        end
    end

    return m
end

local function sign(i,j)
    -- (1,1) return 1, sign flips with each change of 1
    sum = (i+j) % 2
    return (-1) ^ (sum)
end


function inverse(M)
    local d = det(M)
    local dInv = 1 / d
    local n = table.getn(M)
    local T = transpose(M)

    local inv = {}

    for i=1,n,1 do
        table.insert(inv, {})
        for j=1,n,1 do
            local val = dInv * sign(i,j) * det(minor(T,i,j))
            table.insert(inv[i], val)
        end
    end

    return inv
end


-- Testing

if false then
    local testM = {
        {1,2,3},
        {0,1,4},
        {5,6,0},
    }

    printMatrix(testM)

    local testInv = inverse(testM)

    printMatrix(testInv)

    local product =  matMult(testM, testInv)
    printMatrix(product)
end