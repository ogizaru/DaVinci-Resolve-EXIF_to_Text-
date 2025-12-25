--[[
Script Name: EXIF to Text+ V1.0
Description: 
  - REFRESH: Explicitly sets current timeline before processing to ensure correct context.
  - SECURITY: Robust error handling and track lock guarantees.
  - CORE: GCD Fraction Reduction, 1-frame extension logic.
--]]

local ui = fu.UIManager
local disp = bmd.UIDispatcher(ui)
local resolve = Resolve()

-- =============================================================================
--  0. CONTEXT HELPER
-- =============================================================================
function RefreshContext()
    local projectManager = resolve:GetProjectManager()
    local project = projectManager:GetCurrentProject()
    if not project then return nil, nil end
    
    local timeline = project:GetCurrentTimeline()
    if timeline then
        -- [CRITICAL UPDATE] Force set current timeline to ensure API sync
        project:SetCurrentTimeline(timeline)
    end
    return project, timeline
end

-- =============================================================================
--  1. MATH HELPERS
-- =============================================================================
function GetGCD(m, n)
    while n ~= 0 do
        local q = m
        m = n
        n = q % n
    end
    return m
end

function FormatShutterSpeed(val)
    if not val then return "" end
    local sVal = tostring(val)
    local nStr, dStr = string.match(sVal, "([%d]+)%s*/%s*([%d]+)")
    if nStr and dStr then
        local n = tonumber(nStr)
        local d = tonumber(dStr)
        if n and d and d ~= 0 then
            local common = GetGCD(n, d)
            if common > 1 then
                return string.format("%d/%d", n/common, d/common)
            end
        end
    else
        local num = tonumber(sVal)
        if num and num > 0 and num < 1 then
            local recip = math.floor((1 / num) + 0.5)
            return "1/" .. recip
        end
    end
    return sVal
end

-- =============================================================================
--  2. BINARY PARSER (Protected)
-- =============================================================================
function GetFNumberFromBinary(filePath)
    local success, result = pcall(function()
        local f = io.open(filePath, "rb")
        if not f then return nil end 
        local data = f:read(65536)
        f:close()
        
        if not data or #data < 100 then return nil end

        local function readU16(pos, le) 
            local b1, b2 = string.byte(data, pos, pos+1)
            if not b1 or not b2 then return nil end
            if le then return b2*256 + b1 else return b1*256 + b2 end
        end
        local function readU32(pos, le)
            local b1, b2, b3, b4 = string.byte(data, pos, pos+3)
            if not b4 then return nil end
            if le then return b4*16777216 + b3*65536 + b2*256 + b1 
            else return b1*16777216 + b2*65536 + b3*256 + b4 end
        end

        if string.byte(data, 1) ~= 0xFF or string.byte(data, 2) ~= 0xD8 then return nil end

        local pos = 3
        local tiffStart = nil
        while pos < #data - 10 do
            if string.byte(data, pos) ~= 0xFF then break end
            local size = readU16(pos+2, false)
            if not size then break end
            
            if string.byte(data, pos+1) == 0xE1 and string.sub(data, pos+4, pos+9) == "Exif\0\0" then
                tiffStart = pos + 10
                break
            end
            pos = pos + 2 + size
        end
        if not tiffStart then return nil end

        local le = (string.sub(data, tiffStart, tiffStart+1) == "II")
        local ifd0Offset = readU32(tiffStart + 4, le)
        if not ifd0Offset then return nil end
        
        local function scanIFD(offset, targetTag)
            local count = readU16(offset, le)
            if not count then return nil end
            local curr = offset + 2
            for i=1, count do
                local tag = readU16(curr, le)
                if not tag then break end
                if tag == targetTag then return readU32(curr + 8, le) end
                curr = curr + 12
            end
            return nil
        end

        local subIfdPtr = scanIFD(tiffStart + ifd0Offset, 34665)
        if subIfdPtr then
            local fPtr = scanIFD(tiffStart + subIfdPtr, 33437)
            if fPtr then
                local num = readU32(tiffStart + fPtr, le)
                local den = readU32(tiffStart + fPtr + 4, le)
                if den ~= 0 then return num / den end
            end
        end
        return nil
    end)

    if success then return result else return nil end
end

-- =============================================================================
--  3. METADATA LOGIC
-- =============================================================================
function IsManufacturerName(value)
    if not value then return false end
    local lowerVal = string.lower(value)
    local makers = {"canon", "sony", "nikon", "fujifilm", "panasonic", "olympus", "om digital", "leica", "blackmagic", "arri", "red digital"}
    for _, m in ipairs(makers) do
        if string.find(lowerVal, m) then return true end
    end
    return false
end

local ValidExtensions = {
    image = { [".jpg"]=true, [".jpeg"]=true, [".tif"]=true, [".tiff"]=true, [".cr2"]=true, [".arw"]=true, [".dng"]=true, [".nef"]=true, [".raf"]=true, [".orf"]=true },
    video = { [".mov"]=true, [".mp4"]=true, [".mxf"]=true, [".braw"]=true, [".r3d"]=true, [".mts"]=true, [".avi"]=true }
}

function GetClipMetadata(mpItem, selectedKeys)
    local filePath = mpItem:GetClipProperty("File Path")
    if not filePath then return "" end
    
    local ext = string.lower(string.sub(filePath, -4))
    if string.sub(ext, 1, 1) ~= "." then ext = string.lower(string.sub(filePath, -5)) end

    local isImage = ValidExtensions.image[ext]
    local isVideo = ValidExtensions.video[ext]
    if not isImage and not isVideo then return "" end

    local searchMap = {
        ["Date"] = { "Date Recorded", "Date Created", "DateTime Original", "Creation Date" },
        ["Camera"] = { "Camera TC Type", "Model", "Camera Model", "Device Model", "Product Name" }, 
        ["ISO"] = { "ISO", "ISO Speed Ratings", "Iso", "Sensitivity" },
        ["F-Stop"] = { "Aperture", "F-Number", "FNumber", "Aperture Value" }, 
        ["Shutter"] = { "Shutter Speed", "Shutter", "Exposure Time" },
        ["Focal Length"] = { "Focal Point (mm)", "Focal Length", "Lens Focal Length" },
        ["Lens"] = { "Lens Type", "Lens Model", "Lens" },
        ["Resolution"] = { "Resolution" },
        ["FPS"] = { "FPS", "Video Frame Rate" },
        ["Codec"] = { "Video Codec", "Codec" },
        ["Bit Depth"] = { "Bit Depth", "Video Bit Depth" }
    }
    
    local resultText = ""
    
    for _, uiKey in ipairs(selectedKeys) do
        local bestValue = nil
        
        if uiKey == "F-Stop" then
            if isImage then
                local binVal = GetFNumberFromBinary(filePath)
                if binVal then bestValue = tostring(binVal) 
                else bestValue = mpItem:GetMetadata("Aperture") end
            else
                bestValue = mpItem:GetMetadata("Aperture")
                if not bestValue or bestValue == "" then bestValue = mpItem:GetMetadata("F-Number") end
            end
        end

        if not bestValue and searchMap[uiKey] then
            for _, keyName in ipairs(searchMap[uiKey]) do
                local val = nil
                if uiKey == "Resolution" or uiKey == "FPS" or uiKey == "Codec" or uiKey == "Bit Depth" then
                    val = mpItem:GetClipProperty(keyName)
                else
                    val = mpItem:GetMetadata(keyName)
                end
                
                if val and val ~= "" then
                    if uiKey == "Camera" and IsManufacturerName(val) then 
                    else
                        bestValue = val
                        break
                    end
                end
            end
        end

        if bestValue and bestValue ~= "" then
            if uiKey == "F-Stop" then
                local num = tonumber(bestValue)
                if num then 
                    bestValue = string.format("f/%.1f", num)
                    bestValue = string.gsub(bestValue, "%.0", "")
                elseif not string.find(string.lower(bestValue), "f/") then
                     bestValue = "f/" .. bestValue
                end
            end
            if uiKey == "Shutter" then bestValue = FormatShutterSpeed(bestValue) end
            if (uiKey == "Focal Length") and not string.find(string.lower(bestValue), "mm") then
                 bestValue = bestValue .. "mm"
            end
            
            resultText = resultText .. uiKey .. ": " .. bestValue .. "\n"
        end
    end
    
    return resultText
end

-- =============================================================================
--  4. MAIN PROCESS
-- =============================================================================
function FramesToTimecode(frames, fps)
    local fpsInt = math.floor(fps + 0.5)
    local f = math.floor(frames % fpsInt)
    local s = math.floor((frames / fpsInt) % 60)
    local m = math.floor((frames / (fpsInt * 60)) % 60)
    local h = math.floor(frames / (fpsInt * 60 * 60))
    return string.format("%02d:%02d:%02d:%02d", h, m, s, f)
end

function ProcessTimeline(selectedKeys, srcTrackIndex)
    -- [UPDATE] Force Refresh Context
    local project, timeline = RefreshContext()
    if not timeline then return 0 end
    
    resolve:OpenPage("edit")
    local fps = timeline:GetSetting("timelineFrameRate") or 24
    local count = 0
    
    -- Safe Execution Wrapper
    local status, err = pcall(function()
        local clips = timeline:GetItemListInTrack("video", srcTrackIndex)
        timeline:SetTrackLock("video", srcTrackIndex, true)
        
        for i, clip in ipairs(clips) do
            local mpItem = clip:GetMediaPoolItem()
            if mpItem then
                local textContent = GetClipMetadata(mpItem, selectedKeys)
                if textContent ~= "" then
                    local startFrame = clip:GetStart()
                    local endFrame = clip:GetEnd()
                    
                    local tcStr = FramesToTimecode(startFrame, fps)
                    if timeline.SetCurrentTimecode then timeline:SetCurrentTimecode(tcStr) end
                    
                    local newClip = nil
                    if timeline.InsertFusionTitleIntoTimeline then
                        newClip = timeline:InsertFusionTitleIntoTimeline("Text+")
                    elseif timeline.InsertTitle then
                        newClip = timeline:InsertTitle("Text+")
                    end
                    
                    if newClip then
                        newClip:SetProperty("Start", tostring(startFrame))
                        newClip:SetProperty("End", tostring(endFrame))
                        
                        local comp = newClip:GetFusionCompByIndex(1)
                        if comp then
                            local toolList = comp:GetToolList(false, "TextPlus")
                            if toolList and toolList[1] then
                                toolList[1].StyledText = textContent
                                toolList[1].Size = 0.04
                                toolList[1].Style = "Bold"
                                toolList[1].HorizontalJustificationTop = 1
                                toolList[1].HorizontalJustificationLeft = 1
                                toolList[1].Center = {0.5, 0.5}
                            end
                        end
                        count = count + 1
                        print("Processed: " .. clip:GetName())
                    end
                end
            end
        end
    end)

    timeline:SetTrackLock("video", srcTrackIndex, false)
    if not status then print("[ERROR] " .. tostring(err)) return 0 end
    return count
end

-- =============================================================================
--  UI
-- =============================================================================
function ShowUI()
    -- [UPDATE] Refresh Context before showing UI
    local project, timeline = RefreshContext()
    if not timeline then print("No active timeline found.") return end
    
    local trackCount = timeline:GetTrackCount("video")
    local trackItems = {}
    for i=1, trackCount do table.insert(trackItems, "Video " .. i) end
    
    local winWidth = 340
    local winHeight = 520
    local win = disp:AddWindow({
        ID = "LuaV32Win",
        WindowTitle = "Auto EXIF V32 (Context Fix)",
        Geometry = {800, 400, winWidth, winHeight},
        ui:VGroup{
            Spacing = 10,
            
            ui:Label{ ID = "Lbl_Tracks", Text = "Source Track:", Font = ui:Font{PixelSize = 16, Bold = true} },
            ui:HGroup{
                ui:Label{ Text = "Read Images From:", Weight=0.5 },
                ui:ComboBox{ ID = "Combo_Src", Weight=1.5 },
            },
            ui:Label{ Text = "* Target = Currently Selected Red Box Track", Font = ui:Font{PixelSize=11, Italic=true}, Alignment={AlignHCenter=true} },
            ui:VGap(10),

            ui:Label{ ID = "Lbl_Title", Text = "Select Metadata:", Font = ui:Font{PixelSize = 16, Bold = true} },
            ui:VGroup{
                Weight = 1.0,
                ui:Label{ Text = "-- Photo --", Font = ui:Font{Weight=75} },
                ui:HGroup{ ui:CheckBox{ ID = "CB_Camera", Text = "Camera", Checked = true }, ui:CheckBox{ ID = "CB_Lens", Text = "Lens", Checked = true } },
                ui:HGroup{ ui:CheckBox{ ID = "CB_ISO", Text = "ISO", Checked = true }, ui:CheckBox{ ID = "CB_FStop", Text = "F-Stop", Checked = true } },
                ui:HGroup{ ui:CheckBox{ ID = "CB_Shutter", Text = "Shutter", Checked = true }, ui:CheckBox{ ID = "CB_Focal", Text = "Focal Len", Checked = true } },
                ui:VGap(5),
                ui:Label{ Text = "-- Video --", Font = ui:Font{Weight=75} },
                ui:HGroup{ ui:CheckBox{ ID = "CB_Res", Text = "Resolution", Checked = false }, ui:CheckBox{ ID = "CB_FPS", Text = "FPS", Checked = false } },
                ui:HGroup{ ui:CheckBox{ ID = "CB_Codec", Text = "Codec", Checked = false }, ui:CheckBox{ ID = "CB_BitDepth", Text = "Bit Depth", Checked = false } },
                ui:CheckBox{ ID = "CB_Date", Text = "Date Created", Checked = false },
            },
            ui:VGap(10),
            ui:Label{ ID = "Lbl_Status", Text = "Ready", Alignment = {AlignHCenter = true} },
            ui:HGroup{
                Weight = 0,
                ui:Button{ ID = "Btn_Cancel", Text = "Cancel" },
                ui:Button{ ID = "Btn_Run", Text = "Generate", Weight = 2 }
            }
        }
    })

    local comboSrc = win:Find("Combo_Src")
    for i, name in ipairs(trackItems) do comboSrc:AddItem(name) end
    if trackCount >= 1 then comboSrc.CurrentIndex = 0 end 

    function win.On.LuaV32Win.Close(ev) disp:ExitLoop() end
    function win.On.Btn_Cancel.Clicked(ev) disp:ExitLoop() end
    function win.On.Btn_Run.Clicked(ev)
        win:Find("Lbl_Status").Text = "Processing..."
        local srcIdx = win:Find("Combo_Src").CurrentIndex + 1
        
        local keys = {}
        if win:Find("CB_Date").Checked then table.insert(keys, "Date") end
        if win:Find("CB_Camera").Checked then table.insert(keys, "Camera") end
        if win:Find("CB_ISO").Checked then table.insert(keys, "ISO") end
        if win:Find("CB_FStop").Checked then table.insert(keys, "F-Stop") end
        if win:Find("CB_Shutter").Checked then table.insert(keys, "Shutter") end
        if win:Find("CB_Focal").Checked then table.insert(keys, "Focal Length") end
        if win:Find("CB_Lens").Checked then table.insert(keys, "Lens") end
        if win:Find("CB_Res").Checked then table.insert(keys, "Resolution") end
        if win:Find("CB_FPS").Checked then table.insert(keys, "FPS") end
        if win:Find("CB_Codec").Checked then table.insert(keys, "Codec") end
        if win:Find("CB_BitDepth").Checked then table.insert(keys, "Bit Depth") end
        
        local count = ProcessTimeline(keys, srcIdx)
        print("Done. Created " .. count .. " overlays.")
        win:Find("Lbl_Status").Text = "Finished (" .. count .. ")"
    end

    win:Show()
    disp:RunLoop()
    win:Hide()
end

ShowUI()