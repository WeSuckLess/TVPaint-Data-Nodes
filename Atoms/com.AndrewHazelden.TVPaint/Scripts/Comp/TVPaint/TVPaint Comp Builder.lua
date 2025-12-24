--[[--
TVPaint Comp Builder 2.9
2025-12-24

Authors:
Andrew Hazelden (andrew@andrewhazelden.com)
Pieter Van Houte (pieter@secondman.com)

Auto-build a comp node-graph based upon the active TVPaintLoader node selection.

Usage:

Add a TVPaintLoader node to your Fusion comp. Use the node's (Browse) button to select a TVPaint exported .json file.
Select the TVPaintLoader node in the node graph area.
Launch the script. A dialog appears that allows you to customize the settings. Click the "Run" button to continue.
A TVPaint for Fusion nodegraph will be generated. A new undo state is created automatically.
Controls:
The "addNode" control selects between standard Loader or TVPaintLinkImage nodes.
The "mergeLoaders" control sets the output method (LifeSaver, MultiMerge, Merge, Merge3D, or Swizzler).
The "groupByColor" control merges consecutive layers of the same color into sub-groups.
The "textureProjection" and "depthOffset" controls manage 3D space parallax and projection types.
The "addBackground" and "bgColorSource" controls add a project-synced or custom background.
The "adjustRenderRange" control syncs the Fusion timeline to the TVPaint clip duration.
The "reverseLayerOrder" and "reverseDirection" controls flip the stacking and spatial layout.
The "autoNameLayers" and "tileColor" controls sync node metadata with TVPaint layer data.
--]]

local TVP = {
-- Should the RenderEnd range be set to match the TVPaint image count
adjustRenderRange = true,

-- TVPaintLinkImage Options
baseImageFolder = "Comp:/",
reverseLayerOrder = false,

-- Merge Options
autoNameLayers = true,
alphaGain = false,

-- LifeSaver Options
exrSubFolder = "exr/",

-- Should a TVPaintBackground node be added
addBackground = false,

-- Background Options
bgAlphaMode = 0, -- 0: Solid, 1: Transparent
bgColorSource = 0, -- 0: TVPaint, 1: Black, 2: White, 3: Custom
bgCustomR = 0.5,
bgCustomG = 0.5,
bgCustomB = 0.5,

-- Should the UI Manager window be skipped
skipShowingUI = false,

-- Should the nodes be built horizontal (1) or vertical (0)
direction = 1,

-- Should the spatial build direction be reversed (Up/Down or Left/Right)
reverseDirection = false,

-- Distance between the Loaders and the Merge/Output nodes
nodeSpacing = 5,

-- Should a Loader (0) or TVPaint Layer (1) node be used
addNode = 0,

-- Should textures be projected through Camera3D (0) or ImagePlane3D (1)
textureProjection = 0,

-- Should the 2D textures be merged before going into the 3D space
texturePreComps = 0,

-- Allows Camera3D based texture projections to add multi-plane parallax
depthOffset = 0.0,

-- Are source tiles enabled in the flow
showTiles = false,

-- Are tile colors enabled in the flow
tileColor = true,

-- Which merge tool to use (0: LifeSaver, 1: MultiMerge, 2: Merge, 3: Merge3D, 4: Swizzler)
mergeLoaders = 1,

-- Which tool to use for sub-groups (0: Merge, 1: MultiMerge)
subMergeTool = 0,

-- How should missing frames be handled with Loader nodes
missingFrames = 1,

-- Should consecutive layers of the same color be grouped
groupByColor = false,

-- The cancel button was pressed
cancelScript = false,

-- Debugging log detail
verbose = true,
}


-------------------------------------------------------------------------------
-- 1. UTILITIES
-------------------------------------------------------------------------------

-- Get a value from a table with optional error reporting
function get(t, key)
	local value = nil
	local found = false

for k, v in pairs(t) do
	if k == key then
		value = v
		found = true
		break
	end
end

if not found and TVP.verbose then
	print(string.format("[Get Element] No key '%s' found in table", key))
end

return value
end


-- Read a fusion specific preference value. If nothing exists set and return a default value
function getPreferenceData(pref, defaultValue, debugPrint)
	local newPreference = fu:GetData(pref)

if newPreference ~= nil then
	if debugPrint then
		print("[Reading " .. tostring(pref) .. " Preference Data] " .. tostring(newPreference))
	end
else
	newPreference = defaultValue
	fu:SetData(pref, defaultValue)

	if debugPrint then
		print("[Creating " .. tostring(pref) .. " Preference Entry] " .. tostring(newPreference))
	end
end

return newPreference
end


-- Set a fusion specific preference value
function setPreferenceData(pref, value, debugPrint)
	fu:SetData(pref, value)

if debugPrint then
	print("[Setting " .. tostring(pref) .. " Preference Data] " .. tostring(value))
end
end


-- parseFilename() from bmd.scriptlib for ripping a filepath into bits
function parseFilename(filename)
	local seq = {}
	seq.FullPath = filename
	seq.FullPathMap = comp:MapPath(filename)
	string.gsub(seq.FullPath, "^(.+[/\\])(.+)", function(path, name) seq.Path = path seq.FullName = name end)
	string.gsub(seq.FullPath, "^(.+[/\\])(.+)", function(path, name) seq.PathMap = comp:MapPath(path) seq.FullName = name end)
	string.gsub(seq.FullName, "^(.+)(%..+)$", function(name, ext) seq.Name = name seq.Extension = ext end)

if not seq.Name then seq.Name = seq.FullName end

string.gsub(seq.Name, "^(.-)(%d+)$", function(name, SNum) seq.CleanName = name seq.SNum = SNum end)

if seq.SNum then
	seq.Number = tonumber(seq.SNum)
	seq.Padding = string.len(seq.SNum)
else
	seq.SNum = ""
	seq.CleanName = seq.Name
end

if seq.Extension == nil then seq.Extension = "" end
seq.UNC = (string.sub(seq.Path, 1, 2) == [[\\]])

return seq
end


-------------------------------------------------------------------------------
-- 2. UI MANAGER
-------------------------------------------------------------------------------

function AskForInput()
	-- Fetch verbose first to control logging of subsequent preferences
	TVP.verbose = getPreferenceData("TVPaint.verbose", TVP.verbose, TVP.verbose)

TVP.direction = getPreferenceData("TVPaint.direction", TVP.direction, TVP.verbose)
TVP.reverseDirection = getPreferenceData("TVPaint.reverseDirection", TVP.reverseDirection, TVP.verbose)
TVP.nodeSpacing = getPreferenceData("TVPaint.nodeSpacing", TVP.nodeSpacing, TVP.verbose)
TVP.addNode = getPreferenceData("TVPaint.addNode", TVP.addNode, TVP.verbose)
TVP.mergeLoaders = getPreferenceData("TVPaint.mergeLoaders", TVP.mergeLoaders, TVP.verbose)
TVP.subMergeTool = getPreferenceData("TVPaint.subMergeTool", TVP.subMergeTool, TVP.verbose)
TVP.adjustRenderRange = getPreferenceData("TVPaint.adjustRenderRange", TVP.adjustRenderRange, TVP.verbose)
TVP.addBackground = getPreferenceData("TVPaint.addBackground", TVP.addBackground, TVP.verbose)
TVP.bgAlphaMode = getPreferenceData("TVPaint.bgAlphaMode", TVP.bgAlphaMode, TVP.verbose)
TVP.bgColorSource = getPreferenceData("TVPaint.bgColorSource", TVP.bgColorSource, TVP.verbose)
TVP.bgCustomR = getPreferenceData("TVPaint.bgCustomR", TVP.bgCustomR, TVP.verbose)
TVP.bgCustomG = getPreferenceData("TVPaint.bgCustomG", TVP.bgCustomG, TVP.verbose)
TVP.bgCustomB = getPreferenceData("TVPaint.bgCustomB", TVP.bgCustomB, TVP.verbose)
TVP.autoNameLayers = getPreferenceData("TVPaint.autoNameLayers", TVP.autoNameLayers, TVP.verbose)
TVP.alphaGain = getPreferenceData("TVPaint.alphaGain", TVP.alphaGain, TVP.verbose)
TVP.reverseLayerOrder = getPreferenceData("TVPaint.reverseLayerOrder", TVP.reverseLayerOrder, TVP.verbose)
TVP.showTiles = getPreferenceData("TVPaint.showTiles", TVP.showTiles, TVP.verbose)
TVP.tileColor = getPreferenceData("TVPaint.tileColor", TVP.tileColor, TVP.verbose)
TVP.textureProjection = getPreferenceData("TVPaint.textureProjection", TVP.textureProjection, TVP.verbose)
TVP.texturePreComps = getPreferenceData("TVPaint.texturePreComps", TVP.texturePreComps, TVP.verbose)
TVP.depthOffset = getPreferenceData("TVPaint.depthOffset", TVP.depthOffset, TVP.verbose)
TVP.groupByColor = getPreferenceData("TVPaint.groupByColor", TVP.groupByColor, TVP.verbose)

local ui = fu.UIManager
local disp = bmd.UIDispatcher(ui)
local win = disp:AddWindow({
	ID = "TVPaint", WindowTitle = "TVPaint Comp Builder", Geometry = {100, 100, 520, 715}, Spacing = 10,
	ui:VGroup{
		ui:HGroup{ ui:Label{Text = "Build Direction"}, ui:ComboBox{ID = "BuildDirection"} },
		ui:HGroup{ ui:Label{Text = "Node Spacing"}, ui:SpinBox{ID = "NodeSpacing", Minimum = 2, Maximum = 20, Value = TVP.nodeSpacing} },
		ui:HGroup{ ui:Label{Text = "Add Media Node"}, ui:ComboBox{ID = "AddNode"} },
		ui:HGroup{ ID = "MissingFramesGroup", ui:Label{Text = "Missing Frames"}, ui:ComboBox{ID = "MissingFrames"} },
		ui:HGroup{ ui:Label{Text = "Merge Loaders"}, ui:ComboBox{ID = "MergeLoaders"} },
		ui:HGroup{ ID = "SubMergeToolGroup", ui:Label{Text = "Sub-Merge Tool"}, ui:ComboBox{ID = "SubMergeTool"} },
		ui:HGroup{ ID = "TextureProjectionGroup", ui:Label{Text = "Texture Projection"}, ui:ComboBox{ID = "TextureProjection"} },
		ui:HGroup{ ID = "TexturePreCompsGroup", ui:Label{Text = "Texture PreComps"}, ui:ComboBox{ID = "TexturePreComps"} },
		ui:HGroup{ ID = "DepthOffsetGroup", ui:Label{Text = "Texture Depth Offset"}, ui:DoubleSpinBox{ID = "DepthOffset", Minimum = 0, Maximum = 100, Decimals = 4, Value = TVP.depthOffset} },
		
		-- Background Options Group
		ui:VGroup{
			ID = "BGOptionsGroup",
			ui:HGroup{ ui:Label{Text = "BG Color Source"}, ui:ComboBox{ID = "BGColorSource"} },
			ui:HGroup{ ui:Label{Text = "BG Alpha Channel"}, ui:ComboBox{ID = "BGAlphaMode"} },
			ui:VGroup{
				ID = "BGCustomColorGroup",
				ui:HGroup{ ui:Label{Text = "Custom RGB"}, ui:ColorPicker{ID = 'BGColorPicker', Color = {R = TVP.bgCustomR, G = TVP.bgCustomG, B = TVP.bgCustomB} } },
			},
		},

		ui:HGroup{
			ui:VGroup{
				ui:CheckBox{ID = "AdjustRenderRange", Text = "Adjust Render Range", Checked = TVP.adjustRenderRange},
				ui:CheckBox{ID = "AutoNameLayers", Text = "Auto Name Layers", Checked = TVP.autoNameLayers},
				ui:CheckBox{ID = "TileColor", Text = "Tile Color", Checked = TVP.tileColor},
				ui:CheckBox{ID = "ShowTiles", Text = "Source Tiles Enabled", Checked = TVP.showTiles},
				ui:CheckBox{ID = "GroupByColor", Text = "Group by Tile Color", Checked = TVP.groupByColor},
				ui:CheckBox{ID = "AddBackground", Text = "Add Background", Checked = TVP.addBackground},
			},
			ui:VGroup{
				ui:CheckBox{ID = "AlphaGain", Text = "Alpha Gain Zero", Checked = TVP.alphaGain},
				ui:CheckBox{ID = "ReverseLayerOrder", Text = "Reverse Layer Order", Checked = TVP.reverseLayerOrder},
				ui:CheckBox{ID = "ReverseDirection", Text = "Reverse Build Direction", Checked = TVP.reverseDirection},
				ui:CheckBox{ID = "Verbose", Text = "Verbose", Checked = TVP.verbose},
			},
		},
		ui:HGroup{ ui:Button{ID = "OKButton", Text = "Run"}, ui:Button{ID = "CancelButton", Text = "Cancel"} },
	}
})

local itm = win:GetItems()
itm.BuildDirection:AddItems({"Vertical", "Horizontal"})
itm.BuildDirection.CurrentIndex = TVP.direction
itm.AddNode:AddItems({"Using Loader", "Using TVPaint"})
itm.AddNode.CurrentIndex = TVP.addNode
itm.MergeLoaders:AddItems({"Using LifeSaver", "Using MultiMerge", "Using Merge", "Using Merge3D", "Using Swizzler"})
itm.MergeLoaders.CurrentIndex = TVP.mergeLoaders
itm.SubMergeTool:AddItems({"Using Merge", "Using MultiMerge"})
itm.SubMergeTool.CurrentIndex = TVP.subMergeTool
itm.TextureProjection:AddItems({"Camera3D", "ImagePlane3D"})
itm.TextureProjection.CurrentIndex = TVP.textureProjection
itm.TexturePreComps:AddItems({"Skip", "MultiMerge", "Merge"})
itm.TexturePreComps.CurrentIndex = TVP.texturePreComps
itm.MissingFrames:AddItems({"Fail", "Hold Previous", "Output Color", "Wait"})
itm.MissingFrames.CurrentIndex = TVP.missingFrames
itm.BGAlphaMode:AddItems({"Solid", "Transparent"})
itm.BGAlphaMode.CurrentIndex = TVP.bgAlphaMode
itm.BGColorSource:AddItems({"TVPaint Project", "Black", "White", "Custom"})
itm.BGColorSource.CurrentIndex = TVP.bgColorSource

-- Dynamic Visibility Logic
local function updateVisibility()
	itm.SubMergeToolGroup.Visible = itm.GroupByColor.Checked
	itm.MissingFramesGroup.Visible = (itm.AddNode.CurrentIndex == 0)
	
	local is3D = (itm.MergeLoaders.CurrentIndex == 3)
	itm.TextureProjectionGroup.Visible = is3D
	itm.TexturePreCompsGroup.Visible = is3D
	itm.DepthOffsetGroup.Visible = is3D

	itm.BGOptionsGroup.Visible = itm.AddBackground.Checked
	itm.BGCustomColorGroup.Visible = (itm.AddBackground.Checked and itm.BGColorSource.CurrentIndex == 3)
end

function win.On.GroupByColor.Clicked(ev) updateVisibility() end
function win.On.AddBackground.Clicked(ev) updateVisibility() end
function win.On.AddNode.CurrentIndexChanged(ev) updateVisibility() end
function win.On.MergeLoaders.CurrentIndexChanged(ev) updateVisibility() end
function win.On.BGColorSource.CurrentIndexChanged(ev) updateVisibility() end

updateVisibility()

-- Capture hotkeys to close window 
app:AddConfig("TVPaint", {
	Target { ID = "TVPaint" },
	Hotkeys {
		Target = "TVPaint", Defaults = true,
		CONTROL_W = "Execute{cmd = [[app.UIManager:QueueEvent(obj, 'Close', {})]]}",
		CONTROL_F4 = "Execute{cmd = [[app.UIManager:QueueEvent(obj, 'Close', {})]]}",
		ESCAPE = "Execute{cmd = [[app.UIManager:QueueEvent(obj, 'Close', {})]]}"
	},
})

function win.On.CancelButton.Clicked(ev) TVP.cancelScript = true disp:ExitLoop() end
function win.On.TVPaint.Close(ev) TVP.cancelScript = true disp:ExitLoop() end
function win.On.OKButton.Clicked(ev)
	TVP.direction = itm.BuildDirection.CurrentIndex
	TVP.reverseDirection = itm.ReverseDirection.Checked
	TVP.nodeSpacing = itm.NodeSpacing.Value
	TVP.addNode = itm.AddNode.CurrentIndex
	TVP.mergeLoaders = itm.MergeLoaders.CurrentIndex
	TVP.subMergeTool = itm.SubMergeTool.CurrentIndex
	TVP.missingFrames = itm.MissingFrames.CurrentIndex
	TVP.adjustRenderRange = itm.AdjustRenderRange.Checked
	TVP.addBackground = itm.AddBackground.Checked
	TVP.bgAlphaMode = itm.BGAlphaMode.CurrentIndex
	TVP.bgColorSource = itm.BGColorSource.CurrentIndex
	
	local customColor = itm.BGColorPicker.Color
	TVP.bgCustomR = customColor.R
	TVP.bgCustomG = customColor.G
	TVP.bgCustomB = customColor.B
	
	TVP.autoNameLayers = itm.AutoNameLayers.Checked
	TVP.alphaGain = itm.AlphaGain.Checked
	TVP.reverseLayerOrder = itm.ReverseLayerOrder.Checked
	TVP.showTiles = itm.ShowTiles.Checked
	TVP.tileColor = itm.TileColor.Checked
	TVP.textureProjection = itm.TextureProjection.CurrentIndex
	TVP.texturePreComps = itm.TexturePreComps.CurrentIndex
	TVP.depthOffset = itm.DepthOffset.Value
	TVP.groupByColor = itm.GroupByColor.Checked
	TVP.verbose = itm.Verbose.Checked

	setPreferenceData("TVPaint.direction", TVP.direction, TVP.verbose)
	setPreferenceData("TVPaint.reverseDirection", TVP.reverseDirection, TVP.verbose)
	setPreferenceData("TVPaint.nodeSpacing", TVP.nodeSpacing, TVP.verbose)
	setPreferenceData("TVPaint.addNode", TVP.addNode, TVP.verbose)
	setPreferenceData("TVPaint.mergeLoaders", TVP.mergeLoaders, TVP.verbose)
	setPreferenceData("TVPaint.subMergeTool", TVP.subMergeTool, TVP.verbose)
	setPreferenceData("TVPaint.missingFrames", TVP.missingFrames, TVP.verbose)
	setPreferenceData("TVPaint.adjustRenderRange", TVP.adjustRenderRange, TVP.verbose)
	setPreferenceData("TVPaint.addBackground", TVP.addBackground, TVP.verbose)
	setPreferenceData("TVPaint.bgAlphaMode", TVP.bgAlphaMode, TVP.verbose)
	setPreferenceData("TVPaint.bgColorSource", TVP.bgColorSource, TVP.verbose)
	setPreferenceData("TVPaint.bgCustomR", TVP.bgCustomR, TVP.verbose)
	setPreferenceData("TVPaint.bgCustomG", TVP.bgCustomG, TVP.verbose)
	setPreferenceData("TVPaint.bgCustomB", TVP.bgCustomB, TVP.verbose)
	setPreferenceData("TVPaint.autoNameLayers", TVP.autoNameLayers, TVP.verbose)
	setPreferenceData("TVPaint.alphaGain", TVP.alphaGain, TVP.verbose)
	setPreferenceData("TVPaint.reverseLayerOrder", TVP.reverseLayerOrder, TVP.verbose)
	setPreferenceData("TVPaint.showTiles", TVP.showTiles, TVP.verbose)
	setPreferenceData("TVPaint.tileColor", TVP.tileColor, TVP.verbose)
	setPreferenceData("TVPaint.textureProjection", TVP.textureProjection, TVP.verbose)
	setPreferenceData("TVPaint.texturePreComps", TVP.texturePreComps, TVP.verbose)
	setPreferenceData("TVPaint.depthOffset", TVP.depthOffset, TVP.verbose)
	setPreferenceData("TVPaint.groupByColor", TVP.groupByColor, TVP.verbose)
	setPreferenceData("TVPaint.verbose", TVP.verbose, TVP.verbose)
	disp:ExitLoop()
end

win:Show()
disp:RunLoop()
win:Hide()
end


-------------------------------------------------------------------------------
-- 3. MAIN BUILDER
-------------------------------------------------------------------------------

function Main()
	print("[TVPaint] Comp Builder Script Started")

-- Read the node selection
local selectedTool = comp.ActiveTool
if not selectedTool then 
	error("[Error] Please select a TVPaintLoader node before running this script.") 
end

-- Check the node attributes
local toolAttrs = selectedTool:GetAttrs()
if toolAttrs.TOOLS_RegID ~= "Fuse.TVPaintLoader" then
	error("[Error] Please select a TVPaintLoader node.")
end

-- Name the JSON
local baseJSONFilename = selectedTool["Filename"][fu.TIME_UNDEFINED]

-- File fallback handling
if baseJSONFilename == "" or not bmd.fileexists(comp:MapPath(baseJSONFilename)) then
	print("[Error][TVPaintLoader] JSON file not found. Requesting manual selection.")
	baseJSONFilename = fu:RequestFile(comp:MapPath('Comp:/'), "*.json")
	if baseJSONFilename ~= "" then 
		selectedTool["Filename"][fu.TIME_UNDEFINED] = baseJSONFilename 
	else
		return -- User cancelled
	end
end

-- Display UI
if not TVP.skipShowingUI then
	AskForInput()
	if TVP.cancelScript then return end
end

-- Log settings if verbose
if TVP.verbose then
	print("[Base Image Folder] ", TVP.baseImageFolder)
	print("[Auto Media Node] ", TVP.addNode)
	print("[Auto Output Node] ", TVP.mergeLoaders)
	print("[Auto Name Layers] ", TVP.autoNameLayers)
	print("[Alpha Gain Zero] ", TVP.alphaGain)
	print("[Add Background] ", TVP.addBackground)
	print("[Reverse Layer Order] ", TVP.reverseLayerOrder)
	print("[Adjust Render Range] ", TVP.adjustRenderRange)
	print("[Node Build Direction] ", (TVP.direction == 1 and "Horizontal" or "Vertical"))
end

-- Start Undo
comp:StartUndo("TVPaint Comp Builder")

-- Disable the file browser dialog
local AutoClipBrowse = app:GetPrefs("Global.UserInterface.AutoClipBrowse")
app:SetPrefs("Global.UserInterface.AutoClipBrowse", false)

-- Lock the comp flow area
comp:Lock()

local flow = comp.CurrentFrame.FlowView
local origin_x, origin_y = flow:GetPos(selectedTool)
local tbl = selectedTool["ScriptVal"][comp.CurrentTime] or {}

-- Get the TVPaint .json file defined image path
TVP.baseImageFolder = tostring(parseFilename(baseJSONFilename).PathMap)

-- Extract the number of clip layers
local layer_max = (tbl.project and tbl.project.clip and tbl.project.clip.layers) and #tbl.project.clip.layers or 0

-- Adjust Render Range
if TVP.adjustRenderRange and tbl.project and tbl.project.clip and tbl.project.clip["image-count"] then
	local rEnd = tonumber(tbl.project.clip["image-count"] - 1)
	comp.CurrentTime = 0
	comp:SetAttrs({COMPN_GlobalStart = 0, COMPN_GlobalEnd = rEnd, COMPN_RenderStart = 0, COMPN_RenderEnd = rEnd})
end

-- Default layer build order
local startLayer, endLayer, stepBy = layer_max, 1, -1
if TVP.reverseLayerOrder then startLayer, endLayer, stepBy = 1, layer_max, 1 end

local imgTbl, imgNameTbl, imgColorTbl = {}, {}, {}
local offsetX, offsetY = 2, (TVP.showTiles and 3 or 1)
local bgNode = nil

-- Spatial direction modifier
local dirMod = TVP.reverseDirection and -1 or 1


---------------------------------------------------------------------------
-- INTERNAL BUILD FUNCTIONS
---------------------------------------------------------------------------

local function BuildMultiMerge(images, names, startX, startY)
	local mm = comp:AddTool("MultiMerge", startX, startY)
	local revImg, revName = {}, {}

	-- Separate layers and BG to ensure correct stacking
	local layers, lNames = {}, {}
	local bg, bName = nil, nil
	for i, v in ipairs(images) do
		if names[i] == "bg" then 
			bg = v bName = "bg"
		else 
			table.insert(layers, v) table.insert(lNames, names[i]) 
		end
	end

	-- Corrected Logic: If the list is Top-to-Bottom, reverse it to Bottom-to-Top for MultiMerge
	if not TVP.reverseLayerOrder then
		local tempL, tempN = {}, {}
		for i = #layers, 1, -1 do 
			table.insert(tempL, layers[i]) table.insert(tempN, lNames[i]) 
		end
		layers, lNames = tempL, tempN
	end

	-- Assemble revImg: Background is always the first input (bottom)
	if bg then table.insert(revImg, bg) table.insert(revName, bName) end
	for i=1, #layers do 
		table.insert(revImg, layers[i]) table.insert(revName, lNames[i]) 
	end

	for k, v in pairs(revImg) do
		if k == 1 then 
			mm:ConnectInput("Background", v)
		else
			local layerID = "Layer"..(k-1)
			mm:ConnectInput(layerID..".Foreground", v)
			
			if TVP.autoNameLayers then mm["LayerName"..(k-1)] = revName[k] end
			if TVP.alphaGain then mm[layerID..".Gain"] = 0 end

			-- Incorporate Blend Modes, Opacity, and Visibility from Comments
			local comms = v.Comments and v.Comments[fu.TIME_UNDEFINED] or ""
			if comms ~= "" then
				-- Set Apply Mode (Blend Mode)
				if string.match(comms, 'Multiply') then 
					mm[layerID..".ApplyMode"] = "Multiply" 
				elseif string.match(comms, 'Screen') then
					mm[layerID..".ApplyMode"] = "Screen"
				elseif string.match(comms, 'Overlay') then
					mm[layerID..".ApplyMode"] = "Overlay"
				end

				-- Set Blend (Opacity) and Visibility
				if string.match(comms, 'false') then 
					mm[layerID..".Blend"] = 0
				else
					local opacity = tonumber(string.match(comms, '%d[%d.,]*')) or 1.0
					mm[layerID..".Blend"] = opacity
				end
			end
		end
		if TVP.verbose then print(string.format("[%03d][MultiMerge Connection] %s -> %s", k, v.Name, mm.Name)) end
	end
	return mm
end


local function BuildStandardMerge(images, startX, startY)
	local mrgTbl = {}
	for k, v in pairs(images) do
		if k > 1 then
			-- Align with loaders on the spread axis
			local lx, ly = flow:GetPos(v)
			local mX = (TVP.direction == 0) and (startX) or lx
			local mY = (TVP.direction == 0) and ly or (startY)
			
			local mrg = comp:AddTool("Merge", mX, mY)
			if TVP.alphaGain then mrg.Gain = 0 end
			
			-- Extract blend modes from comments
			local comms = images[k-1].Comments and images[k-1].Comments[fu.TIME_UNDEFINED] or ""
			if string.match(comms, 'Multiply') then mrg.ApplyMode = "Multiply" end
			if string.match(comms, 'true') then 
				mrg.Blend = tonumber(string.match(comms, '%d[%d.,]*')) or 1.0
			elseif string.match(comms, 'false') then
				mrg.Blend = 0
			end
			
			if not TVP.reverseLayerOrder then
				mrg:ConnectInput("Foreground", images[k-1])
				if k == 2 then mrg:ConnectInput("Background", images[k]) end
			else
				mrg:ConnectInput("Foreground", images[k])
				mrg:ConnectInput("Background", (k == 2 and images[k-1] or mrgTbl[#mrgTbl]))
			end
			table.insert(mrgTbl, mrg)
			if TVP.verbose then print(string.format("[%03d][Merge Connection] %s -> %s", k, images[k].Name, mrg.Name)) end
		end
	end

	-- Second pass for standard Merges (if not reversed)
	if not TVP.reverseLayerOrder and #mrgTbl > 0 then
		for k, v in pairs(mrgTbl) do 
			if mrgTbl[k+1] then v:ConnectInput("Background", mrgTbl[k+1]) end
		end
		mrgTbl[#mrgTbl]:ConnectInput("Background", images[#images])
	end

	-- Return the head of the chain (the node providing the final output)
	if not TVP.reverseLayerOrder then
		return mrgTbl[1] or images[1]
	else
		return mrgTbl[#mrgTbl] or images[1]
	end
end


---------------------------------------------------------------------------
-- BRANCH A: LOADER NODES
---------------------------------------------------------------------------

if TVP.addNode == 0 then
	-- Deselect all nodes
	flow:Select()

	-- Add the Background node
	if TVP.addBackground then
		local bgPos = (TVP.mergeLoaders == 2 or TVP.mergeLoaders == 3) and (layer_max + 1) or 0
		local bgX = (TVP.direction == 0) and (origin_x + 2) or (origin_x + (offsetX * (bgPos - 1) * dirMod))
		local bgY = (TVP.direction == 0) and (origin_y + (offsetY * (bgPos - 1) * dirMod)) or (origin_y + 2)
		bgNode = comp:AddTool("Background", bgX, bgY)

		-- Color Logic
		local r, g, b, a = 0, 0, 0, (TVP.bgAlphaMode == 0 and 1 or 0)
		if TVP.bgColorSource == 0 then -- TVPaint
			if tbl.project.clip.bg then
				r, g, b = tbl.project.clip.bg.red / 255, tbl.project.clip.bg.green / 255, tbl.project.clip.bg.blue / 255
			end
		elseif TVP.bgColorSource == 1 then -- Black
			r, g, b = 0, 0, 0
		elseif TVP.bgColorSource == 2 then -- White
			r, g, b = 1, 1, 1
		elseif TVP.bgColorSource == 3 then -- Custom
			r, g, b = TVP.bgCustomR, TVP.bgCustomG, TVP.bgCustomB
		end

		bgNode.TopLeftRed, bgNode.TopLeftGreen, bgNode.TopLeftBlue, bgNode.TopLeftAlpha = r, g, b, a
		bgNode.Width, bgNode.Height = tonumber(tbl.project.clip.width), tonumber(tbl.project.clip.height)
		bgNode.UseFrameFormatSettings = 0
		table.insert(imgTbl, bgNode)
		table.insert(imgNameTbl, "bg")
		table.insert(imgColorTbl, "bg")
	end

	-- Add the Loader nodes
	for i = startLayer, endLayer, stepBy do
		flow:Select()
		local lX = (TVP.direction == 0) and (origin_x + 2) or (origin_x + (offsetX * (i - 1) * dirMod))
		local lY = (TVP.direction == 0) and (origin_y + (offsetY * (i - 1) * dirMod)) or (origin_y + 2)
		local ldr = comp:AddTool("Loader", lX, lY)

		-- Extract the layer name
		local groupTbl = get(tbl.project.clip.layers, i)
		if groupTbl.name then 
			ldr:SetAttrs({TOOLS_Name = "layer_" .. groupTbl.name}) 
			table.insert(imgNameTbl, groupTbl.name) 
		end

		-- Tile Color
		local colorKey = "none"
		if TVP.tileColor and groupTbl.group then 
			ldr.TileColor = {R = groupTbl.group.red, G = groupTbl.group.green, B = groupTbl.group.blue} 
			colorKey = string.format("%d,%d,%d", groupTbl.group.red, groupTbl.group.green, groupTbl.group.blue)
		end
		table.insert(imgColorTbl, colorKey)

		-- Hold previous frames
		ldr.MissingFrames = TVP.missingFrames
		if groupTbl.link and groupTbl.link[1] then 
			ldr.Clip = TVP.baseImageFolder .. groupTbl.link[1].file 
		end
		
		-- TVPaint Layer behaviours
		local layerstart, layerend = get(groupTbl, "start"), get(groupTbl, "end")
		local highestindex = 0
		for _, link in pairs(groupTbl.link) do
			local cur = get(link, "instance-index") or 0
			if cur > highestindex then highestindex = cur end
		end

		ldr.GlobalIn, ldr.GlobalOut = layerstart, layerend
		ldr.ClipTimeStart, ldr.ClipTimeEnd = 0, highestindex - layerstart
		ldr.HoldLastFrame = layerend - highestindex

		local post = get(groupTbl, "post-behavior")
		if post == 1 then ldr.Loop = 1 elseif post == 3 then ldr.HoldLastFrame = 1000000 end

		-- Extract Blend modes and insert them in Loader comments
		ldr.Comments = string.format("%s\n%s\n%s", get(groupTbl, "blending-mode"), (1/255 * get(groupTbl, "opacity")), tostring(get(groupTbl, "visible")))
		table.insert(imgTbl, ldr)
	end

	-- Sort image table for Merges
	if TVP.mergeLoaders == 2 or TVP.mergeLoaders == 3 then
		local syncMap = {}
		for k, v in ipairs(imgTbl) do syncMap[v] = {name = imgNameTbl[k], color = imgColorTbl[k]} end
		table.sort(imgTbl, function(a,b)
			local ax, ay = flow:GetPos(a) local bx, by = flow:GetPos(b)
			if TVP.direction == 0 then
				if TVP.reverseDirection then return ay > by else return ay < by end
			else
				if TVP.reverseDirection then return ax > bx else return ax < bx end
			end
		end)
		imgNameTbl, imgColorTbl = {}, {}
		for k, v in ipairs(imgTbl) do
			table.insert(imgNameTbl, syncMap[v].name)
			table.insert(imgColorTbl, syncMap[v].color)
		end
	end


---------------------------------------------------------------------------
-- BRANCH B: TVPAINT NODES
---------------------------------------------------------------------------

else
	-- Add the TVPaintBackground node
	if TVP.addBackground then
		local bgPos = (TVP.mergeLoaders == 2) and (layer_max + 1) or 0
		local bgX = (TVP.direction == 0) and (origin_x + 2) or (origin_x + (offsetX * (bgPos - 1) * dirMod))
		local bgY = (TVP.direction == 0) and (origin_y + (offsetY * (bgPos - 1) * dirMod)) or (origin_y + 2)
		
		-- If using TVPaint Project color, use the Fuse. Otherwise, use standard Background.
		if TVP.bgColorSource == 0 then
			bgNode = comp:AddTool("Fuse.TVPaintBackground", bgX, bgY)
			bgNode:ConnectInput("ScriptVal", selectedTool)
			bgNode.TopLeftAlpha = (TVP.bgAlphaMode == 0 and 1 or 0)
		else
			bgNode = comp:AddTool("Background", bgX, bgY)
			local r, g, b, a = 0, 0, 0, (TVP.bgAlphaMode == 0 and 1 or 0)
			if TVP.bgColorSource == 1 then r, g, b = 0, 0, 0
			elseif TVP.bgColorSource == 2 then r, g, b = 1, 1, 1
			elseif TVP.bgColorSource == 3 then r, g, b = TVP.bgCustomR, TVP.bgCustomG, TVP.bgCustomB end
			bgNode.TopLeftRed, bgNode.TopLeftGreen, bgNode.TopLeftBlue, bgNode.TopLeftAlpha = r, g, b, a
		end

		bgNode.Width, bgNode.Height = tonumber(tbl.project.clip.width), tonumber(tbl.project.clip.height)
		bgNode.UseFrameFormatSettings = 0
		table.insert(imgTbl, bgNode)
		table.insert(imgNameTbl, "bg")
		table.insert(imgColorTbl, "bg")
	end

	-- Add the TVPaintLinkImage nodes
	for i = startLayer, endLayer, stepBy do
		local iX = (TVP.direction == 0) and (origin_x + 2) or (origin_x + (offsetX * (i - 1) * dirMod))
		local iY = (TVP.direction == 0) and (origin_y + (offsetY * (i - 1) * dirMod)) or (origin_y + 2)
		local img = comp:AddTool("Fuse.TVPaintLinkImage", iX, iY)
		img:ConnectInput("ScriptVal", selectedTool)
		img.TimeMode, img.Layer, img.BaseFolder = 2, tonumber(i), TVP.baseImageFolder
		
		local groupTbl = get(tbl.project.clip.layers, i)
		if groupTbl.name then 
			img:SetAttrs({TOOLS_Name = "layer_" .. groupTbl.name}) 
			table.insert(imgNameTbl, groupTbl.name) 
		end

		local colorKey = "none"
		if TVP.tileColor and groupTbl.group then 
			img.TileColor = {R = groupTbl.group.red, G = groupTbl.group.green, B = groupTbl.group.blue} 
			colorKey = string.format("%d,%d,%d", groupTbl.group.red, groupTbl.group.green, groupTbl.group.blue)
		end
		table.insert(imgColorTbl, colorKey)
		table.insert(imgTbl, img)
	end

	-- Sort image table for Merges
	if TVP.mergeLoaders == 2 or TVP.mergeLoaders == 3 then
		local syncMap = {}
		for k, v in ipairs(imgTbl) do syncMap[v] = {name = imgNameTbl[k], color = imgColorTbl[k]} end
		table.sort(imgTbl, function(a,b)
			local ax, ay = flow:GetPos(a) local bx, by = flow:GetPos(b)
			if TVP.direction == 0 then
				if TVP.reverseDirection then return ay > by else return ay < by end
			else
				if TVP.reverseDirection then return ax > bx else return ax < bx end
			end
		end)
		imgNameTbl, imgColorTbl = {}, {}
		for k, v in ipairs(imgTbl) do
			table.insert(imgNameTbl, syncMap[v].name)
			table.insert(imgColorTbl, syncMap[v].color)
		end
	end
end


---------------------------------------------------------------------------
-- TIER 2: GROUPING LOGIC (Applied to both branches)
---------------------------------------------------------------------------

local finalNodes, finalNames = {}, {}
local tier2Offset = TVP.nodeSpacing

if TVP.groupByColor then
	local i = 1
	while i <= #imgTbl do
		local currentColor = imgColorTbl[i]
		local groupNodes, groupNames = {imgTbl[i]}, {imgNameTbl[i]}
		local j = i + 1
		-- Explicitly exclude Background from sub-merging
		if currentColor ~= "none" and currentColor ~= "bg" then
			while j <= #imgTbl and imgColorTbl[j] == currentColor do
				table.insert(groupNodes, imgTbl[j])
				table.insert(groupNames, imgNameTbl[j])
				j = j + 1
			end
		end

		if #groupNodes > 1 then
			local avgX, avgY = 0, 0
			for _, n in ipairs(groupNodes) do
				local nx, ny = flow:GetPos(n)
				avgX, avgY = avgX + nx, avgY + ny
			end
			local smX = (TVP.direction == 0) and (origin_x + 2 + tier2Offset) or (avgX / #groupNodes)
			local smY = (TVP.direction == 1) and (origin_y + 2 + tier2Offset) or (avgY / #groupNodes)
			
			local subMergeHead = nil
			if TVP.subMergeTool == 0 then 
				subMergeHead = BuildStandardMerge(groupNodes, smX, smY)
			else
				subMergeHead = BuildMultiMerge(groupNodes, groupNames, smX, smY)
			end
			
			subMergeHead:SetAttrs({TOOLS_Name = "Group_" .. groupNames[1]})
			subMergeHead.TileColor = groupNodes[1].TileColor
			table.insert(finalNodes, subMergeHead)
			table.insert(finalNames, "Group_" .. groupNames[1])
		else
			table.insert(finalNodes, imgTbl[i])
			table.insert(finalNames, imgNameTbl[i])
		end
		i = j
	end
else
	finalNodes, finalNames = imgTbl, imgNameTbl
end


---------------------------------------------------------------------------
-- TIER 3: MASTER OUTPUT LOGIC
---------------------------------------------------------------------------

local tier3Offset = TVP.groupByColor and (TVP.nodeSpacing * 2) or TVP.nodeSpacing
local avgX, avgY = 0, 0
for _, n in ipairs(finalNodes) do
	local nx, ny = flow:GetPos(n)
	avgX, avgY = avgX + nx, avgY + ny
end
local masterX = (TVP.direction == 0) and (origin_x + 2 + tier3Offset) or (avgX / #finalNodes)
local masterY = (TVP.direction == 1) and (origin_y + 2 + tier3Offset) or (avgY / #finalNodes)

if TVP.mergeLoaders == 0 then -- LifeSaver
	local ls = comp:AddTool("Fuse.LifeSaver", masterX, masterY)
	ls.Filename = TVP.baseImageFolder .. TVP.exrSubFolder .. parseFilename(baseJSONFilename).Name .. "_${VERSION}.0000.exr"
	for k, v in pairs(finalNodes) do
		ls["Name"..k] = finalNames[k]
		ls:ConnectInput("Input"..k, v)
		if k < #finalNodes then ls.AddOutput = 1 end
	end

elseif TVP.mergeLoaders == 1 then -- MultiMerge
	BuildMultiMerge(finalNodes, finalNames, masterX, masterY)

elseif TVP.mergeLoaders == 2 then -- Merge 2D
	BuildStandardMerge(finalNodes, masterX, masterY)

elseif TVP.mergeLoaders == 3 then -- Merge3D
	local img3DTbl, cam3D, preCompNode = {}, nil, nil
	local preCompOffset = (TVP.texturePreComps >= 1) and 4 or 0
	
	if TVP.texturePreComps == 1 then
		preCompNode = BuildMultiMerge(finalNodes, finalNames, masterX, masterY + 2)
	elseif TVP.texturePreComps == 2 then
		preCompNode = BuildStandardMerge(finalNodes, masterX, masterY + 2)
	end

	for k, v in pairs(finalNodes) do
		local lx, ly = flow:GetPos(v)
		
		if k == 1 then
			local camX = (TVP.direction == 0) and (masterX + preCompOffset) or lx
			local camY = (TVP.direction == 1) and (masterY + 1 + preCompOffset) or ly
			cam3D = comp:AddTool("Camera3D", camX, camY)
			cam3D["Transform3DOp.Translate.Z"] = (TVP.textureProjection == 0) and 2 or 1.66
			table.insert(img3DTbl, cam3D)
		end

		if TVP.texturePreComps == 0 or (TVP.texturePreComps >= 1 and k == 1) then
			local nodeX = (TVP.direction == 0) and (masterX + 2 + preCompOffset) or lx
			local nodeY = (TVP.direction == 1) and (masterY + 3 + preCompOffset) or ly
			local img3D = comp:AddTool((TVP.textureProjection == 0 and "Camera3D" or "ImagePlane3D"), nodeX, nodeY)
			local texSource = (TVP.texturePreComps == 0) and v or preCompNode
			
			if TVP.addNode == 1 then -- TVPaint nodes need Texture2DOperator
				local texX = (TVP.direction == 0) and (masterX) or lx
				local texY = (TVP.direction == 1) and (masterY + 2) or ly
				local tex2D = comp:AddTool("Texture2DOperator", texX, texY)
				tex2D:ConnectInput("Input", texSource)
				texSource = tex2D
			end

			if TVP.textureProjection == 0 then
				img3D:ConnectInput("ImageInput", texSource)
				img3D.IDepth = 100 + (tonumber(TVP.depthOffset) * k)
				img3D["Transform3DOp.Translate.Z"] = 2
			else
				img3D:ConnectInput("MaterialInput", texSource)
			end
			table.insert(img3DTbl, img3D)
		end
	end

	local m3d = comp:AddTool("Merge3D", masterX + 4 + preCompOffset, masterY + 5 + preCompOffset)
	for k, v in pairs(img3DTbl) do m3d:ConnectInput("SceneInput"..k, v) end
	local r3d = comp:AddTool("Renderer3D", masterX + 6 + preCompOffset, masterY + 7 + preCompOffset)
	r3d:ConnectInput("SceneInput", m3d)
	r3d.RendererType = "RendererOpenGL"
	if cam3D then r3d.CameraSelector = cam3D.Name end
	
	-- Set Renderer Dimensions based on TVPaint project
	r3d.Width = tonumber(tbl.project.clip.width)
	r3d.Height = tonumber(tbl.project.clip.height)
	r3d.UseFrameFormatSettings = 0

elseif TVP.mergeLoaders == 4 then -- Swizzler
	local sz = comp:AddTool("Swizzler", masterX, masterY)
	for k, v in pairs(finalNodes) do
		sz["LayerName"..k] = finalNames[k]
		sz:ConnectInput("Input"..k, v)
		sz["Layer"..k..".RInput"] = k
		if k < #finalNodes then sz.AddLayer = 1 end
	end
end

-- Re-enable the file browser dialog
app:SetPrefs("Global.UserInterface.AutoClipBrowse", AutoClipBrowse)

-- Unlock the comp flow area
comp:Unlock()

-- End Undo
comp:EndUndo()

print("[Done] TVPaint Comp Build Complete.")
end


Main()