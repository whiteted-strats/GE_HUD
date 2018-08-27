require "Data\\GE\\PlayerData"

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

function potMatrix(addr)
    -- Check the right collumn
    for i=0,2,1 do
        local homoAddr = addr + 0xC + 0x10 * i
        if mainmemory.readfloat(homoAddr, true) ~= 0 then
            return nil
        end
    end
    if mainmemory.readfloat(addr + 0x3C, true) ~= 1 then
        return nil
    end

    -- Read the other values into a actual matrixy structure
    -- Reject if any are outside [-1,1] or are NaN
    local M = {}
    for i = 0,2,1 do
        local R = {}
        for j = 0,2,1 do
            local val = mainmemory.readfloat(addr + 0x10 * i + 0x04 * j, true)
            if val > 1 or val < -1 then
                return nil
            end
            if val ~= val then
                return nil
            end

            table.insert(R,val)
        end
        table.insert(M,R)
    end

    -- Return the plausible matrix
    return M
end

if true then

    plausible = {}

    -- After 130000 we get loads of guards I think
    -- Seems our address of interest is usually just after 0xF0000
    for addr = 0,0x130000,4 do
        if mainmemory.readfloat(addr,true) == 1 then
            local matrixAddr = addr - 0x3C
            local M = potMatrix(matrixAddr)

            if not (M == nil) then
                -- If it passes the first test, check det is good
                local d = det(M)
                d = math.abs(d)
                if (d > 0.9 and d < 1.1) then
                    local obj = {addr=matrixAddr, det=d}
                    table.insert(plausible,obj)
                end
            end
        end
    end

    print("Started, waiting 30 frames..")

    -- Wait some time
    for i = 1,30,1 do
        emu.frameadvance()
    end

    -- See if the dets have changed, if so print.
    -- ! Everyone comes in pairs for drawing!
    local start = nil

    -- Get player data start since we suspect the matrix we want is an offset from this
    local pdStart = PlayerData.get_start_address()
    print("Player data start: " .. string.format("%X", pdStart))


    for _, obj in pairs(plausible) do
        local M = potMatrix(obj.addr)

        -- Use determinant to measure if it has changed, kind of a hash
        if not (M == nil) then
            local d = det(M)
            if d ~= obj.det then
                if start == nil then
                    start = obj.addr
                end
                print(string.format("%X",obj.addr) .. " [" .. string.format("%X",obj.addr-start) .. "]" .. " => " .. string.format("%X", obj.addr-pdStart) .. " offset from pd start")
            end
        end
    end
end

print("Done")
