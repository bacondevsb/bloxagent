local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local function getParent()
	if type(gethui) == "function" then
		local ok, container = pcall(gethui)
		if ok and container then return container end
	end
	if syn and syn.protect_gui then
		local cg = game:GetService("CoreGui")
		return cg
	end
	local ok, cg = pcall(function() return game:GetService("CoreGui") end)
	if ok and cg then return cg end
	return Players.LocalPlayer:WaitForChild("PlayerGui")
end

local parent = getParent()

-- Single-instance guard: a previous run may have parented its GUI to a DIFFERENT
-- container (gethui vs CoreGui vs PlayerGui) than this run resolves to, so sweep
-- every candidate and destroy any existing BloxAgent window before continuing.
do
	local seen = {}
	local function sweep(container)
		if not container or seen[container] then return end
		seen[container] = true
		local okC = pcall(function()
			for _, g in ipairs(container:GetChildren()) do
				if g.Name == "GLMChatWindow" or g.Name == "BloxExecutorWindow" then
					pcall(function() g:Destroy() end)
				end
			end
		end)
	end
	if gethui then pcall(function() sweep(gethui()) end) end
	pcall(function() sweep(game:GetService("CoreGui")) end)
	pcall(function()
		local plr = Players.LocalPlayer
		if plr then sweep(plr:FindFirstChildOfClass("PlayerGui")) end
	end)
	sweep(parent)
end

local PALETTES = {
	Midnight = {
		Background   = Color3.fromRGB(30, 20, 40),
		Topbar       = Color3.fromRGB(40, 25, 50),
		Shadow       = Color3.fromRGB(20, 15, 30),
		Element      = Color3.fromRGB(45, 30, 60),
		ElementHover = Color3.fromRGB(50, 35, 70),
		Secondary    = Color3.fromRGB(40, 30, 55),
		Stroke       = Color3.fromRGB(70, 50, 85),
		StrokeSecond = Color3.fromRGB(65, 45, 80),
		Accent       = Color3.fromRGB(130, 80, 180),
		AccentBright = Color3.fromRGB(150, 100, 200),
		AccentDeep   = Color3.fromRGB(100, 60, 150),
		Text         = Color3.fromRGB(240, 240, 240),
		TextDim      = Color3.fromRGB(170, 160, 185),
		TextFaint    = Color3.fromRGB(120, 110, 140),
		Placeholder  = Color3.fromRGB(140, 140, 140),
		UserBubble   = Color3.fromRGB(95, 60, 150),
		UserBubble2  = Color3.fromRGB(70, 45, 115),
		Online       = Color3.fromRGB(96, 220, 130),
		Danger       = Color3.fromRGB(220, 70, 70),
		DangerDeep   = Color3.fromRGB(70, 30, 35),
	},
	White = {
		Background   = Color3.fromRGB(245, 245, 248),
		Topbar       = Color3.fromRGB(235, 235, 240),
		Shadow       = Color3.fromRGB(210, 210, 215),
		Element      = Color3.fromRGB(255, 255, 255),
		ElementHover = Color3.fromRGB(238, 238, 244),
		Secondary    = Color3.fromRGB(240, 240, 245),
		Stroke       = Color3.fromRGB(205, 205, 215),
		StrokeSecond = Color3.fromRGB(220, 220, 228),
		Accent       = Color3.fromRGB(120, 90, 210),
		AccentBright = Color3.fromRGB(140, 110, 230),
		AccentDeep   = Color3.fromRGB(100, 70, 180),
		Text         = Color3.fromRGB(30, 30, 40),
		TextDim      = Color3.fromRGB(90, 90, 105),
		TextFaint    = Color3.fromRGB(150, 150, 165),
		Placeholder  = Color3.fromRGB(160, 160, 175),
		UserBubble   = Color3.fromRGB(130, 100, 220),
		UserBubble2  = Color3.fromRGB(110, 82, 200),
		Online       = Color3.fromRGB(60, 190, 100),
		Danger       = Color3.fromRGB(210, 60, 60),
		DangerDeep   = Color3.fromRGB(240, 220, 222),
	},
	Black = {
		Background   = Color3.fromRGB(12, 12, 14),
		Topbar       = Color3.fromRGB(20, 20, 23),
		Shadow       = Color3.fromRGB(0, 0, 0),
		Element      = Color3.fromRGB(26, 26, 30),
		ElementHover = Color3.fromRGB(34, 34, 39),
		Secondary    = Color3.fromRGB(22, 22, 26),
		Stroke       = Color3.fromRGB(48, 48, 54),
		StrokeSecond = Color3.fromRGB(40, 40, 46),
		Accent       = Color3.fromRGB(130, 90, 210),
		AccentBright = Color3.fromRGB(155, 115, 235),
		AccentDeep   = Color3.fromRGB(100, 65, 170),
		Text         = Color3.fromRGB(238, 238, 242),
		TextDim      = Color3.fromRGB(150, 150, 160),
		TextFaint    = Color3.fromRGB(95, 95, 105),
		Placeholder  = Color3.fromRGB(110, 110, 120),
		UserBubble   = Color3.fromRGB(90, 60, 160),
		UserBubble2  = Color3.fromRGB(66, 44, 120),
		Online       = Color3.fromRGB(80, 220, 120),
		Danger       = Color3.fromRGB(225, 70, 70),
		DangerDeep   = Color3.fromRGB(60, 26, 28),
	},
}

local currentThemeName = "White"

local Theme = {
	Font     = Enum.Font.GothamMedium,
	FontBold = Enum.Font.GothamBold,
	FontMono = Enum.Font.RobotoMono,
}
for k, v in pairs(PALETTES.White) do Theme[k] = v end

local themeRegistry = {}
local function reg(obj, property, themeKey)
	themeRegistry[#themeRegistry + 1] = {obj, property, themeKey}
	obj[property] = Theme[themeKey]
	return obj
end

local alive = true
local connections, threads = {}, {}
local thinking = false
local msgOrder = 0
local genThreads = {}

local busyChats = {}
local genThreadsByChat = {}

-- EX: single namespace table for all extended-capability helpers/state AND the
-- custom-endpoint config. Declared here (before PROVIDERS/providerById) because
-- providerById references EX.normalizeBase / EX.custom* fields. One table = one
-- main-chunk local slot (Luau caps the main chunk at 200; the file is at it).
local EX = {}
EX.threadChat = setmetatable({}, { __mode = "k" })
EX.chatRuns = {}
EX.pendingCards = {}

local PROVIDERS = {
	-- Ollama Cloud OpenAI-compatible endpoint. Models are the cloud catalog IDs as
	-- served on /v1 (NO "-cloud"/":cloud" suffix on this endpoint). Tool calling over
	-- /v1 is model-dependent (gpt-oss handles it well); weaker models fall back to the
	-- text-mode tool path automatically.
	{ id = "ollama",   name = "Ollama",    kind = "openai", isOllama = true,    base = "https://ollama.com/v1",                models = { "gpt-oss:120b", "gpt-oss:20b", "qwen3-coder:480b", "deepseek-v3.2", "kimi-k2-thinking", "glm-4.6", "minimax-m2" } },
	-- Venice: OpenAI-compatible, but its chat API rejects our tool-message shape, so
	-- we drive it in text/flatten tool mode (see AT.usesNativeTools). Venice uses its
	-- own model IDs (prefixed for proxied frontier models).
	{ id = "venice",   name = "Venice AI", kind = "openai",    base = "https://api.venice.ai/api/v1",          models = { "venice-uncensored", "qwen3-235b", "llama-3.3-70b", "zai-org-glm-5", "deepseek-v4-pro" } },
	-- Moonshot/Kimi: full native OpenAI-style tool calling (tools + tool_choice + role=tool).
	{ id = "moonshot", name = "Moonshot",  kind = "openai",    base = "https://api.moonshot.ai/v1",            models = { "kimi-k2.7-code", "kimi-k2.6", "kimi-k2.5", "moonshot-v1-128k" } },
	-- OpenAI Chat Completions. NOTE: gpt-5.2-pro is Responses-API only and 404s here;
	-- o-series folded into GPT-5, so no bare "o4". These are valid chat-completions IDs.
	{ id = "openai",   name = "OpenAI",    kind = "openai",    base = "https://api.openai.com/v1",             models = { "gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.2", "gpt-4.1" } },
	{ id = "anthropic",name = "Claude",    kind = "anthropic", base = "https://api.anthropic.com",             models = { "claude-opus-4-8", "claude-sonnet-4-6", "claude-haiku-4-5-20251001" } },
	-- DeepSeek: full native tool calling. v4-pro/v4-flash are current; legacy
	-- deepseek-chat/deepseek-reasoner still map to v4-flash until 2026-07-24.
	{ id = "deepseek", name = "DeepSeek",  kind = "openai",    base = "https://api.deepseek.com",              models = { "deepseek-v4-pro", "deepseek-v4-flash", "deepseek-chat", "deepseek-reasoner" } },
	-- Zhipu GLM via the international z.ai general endpoint (NOT a trailing slash, NOT
	-- /v1 — base + "/chat/completions" must resolve to .../paas/v4/chat/completions).
	-- Full native tool calling. Coding-Plan keys need /api/coding/paas/v4 instead.
	{ id = "zhipu",    name = "Zhipu GLM", kind = "openai",    base = "https://api.z.ai/api/paas/v4",  models = { "glm-5.2", "glm-5.1", "glm-4.6", "glm-4.5-air" } },
	-- Custom: user-defined endpoint. Its base/kind/models are patched at runtime in
	-- providerById from the EX.customBase/EX.customKind/EX.customModel state (set in Settings
	-- and persisted to config). kind selects the wire format: "openai" or "anthropic".
	{ id = "custom",   name = "Custom",    kind = "openai",    base = "",  models = { "" }, isCustom = true },
}
-- Custom-endpoint configuration (used when providerId == "custom"). These are
-- set in Settings and persisted in config; providerById stamps them onto the
-- custom provider entry so the rest of the code treats it like any provider.
--   EX.customKind: "openai" | "anthropic"  (wire format)
--   EX.customTools: "native" | "text"      (how tool calls are exchanged)
EX.customBase  = ""
EX.customKind  = "openai"
EX.customModel = ""
EX.customTools = "native"
EX.customStream = false   -- async request-id polling (endpoint returns an id; we poll until ready)

-- Normalize a user-entered base URL: trim spaces, drop a trailing slash, and
-- strip an accidentally-included endpoint suffix so base + "/chat/completions"
-- (or "/v1/messages") never doubles up. Returns "" if clearly empty.
function EX.normalizeBase(url)
	url = tostring(url or ""):gsub("^%s+", ""):gsub("%s+$", "")
	if url == "" then return "" end
	-- strip a single trailing slash
	url = url:gsub("/+$", "")
	-- strip known endpoint suffixes the user may have pasted in
	url = url:gsub("/v1/messages$", "")
	url = url:gsub("/chat/completions$", "")
	url = url:gsub("/+$", "")
	return url
end

local function providerById(id)
	for _, p in ipairs(PROVIDERS) do
		if p.id == id then
			if p.isCustom then
				-- stamp the live custom settings onto the entry every lookup
				p.base = EX.normalizeBase(EX.customBase)
				p.kind = (EX.customKind == "anthropic") and "anthropic" or "openai"
				p.models = { EX.customModel ~= "" and EX.customModel or "" }
			end
			return p
		end
	end
	return PROVIDERS[1]
end

local providerId = "ollama"
local apiModel = "gpt-oss:120b"
local providerKeys = {}
local ollamaSystemPrompt = ""
local permissionMode = "ask"
local planMode = false
local agentMaxSteps = 0

-- Adaptive token sizing + per-model capability cache, all under ONE local
-- (`AT`) to conserve main-chunk register slots -- Luau caps locals at 200 per
-- function and the file-scope chunk was already at that ceiling. Fields:
--   AT.modelSpecs ["providerId/modelId"] = { ctx, maxOut, fc }  (learned from /models)
--   AT.specsTried [provider+keyPrefix] = true                   (one-shot fetch guard)
local AT = { modelSpecs = {}, specsTried = {} }
AT.http = game:GetService("HttpService")

local function curProvider() return providerById(providerId) end
local function curKey() return providerKeys[providerId] or "" end

-- Static fallbacks for when we haven't (or can't) fetch /models. Documented
-- OUTPUT ceilings, matched by substring against the (lowercased) model id so
-- pinned/dated variants ("claude-opus-4-8", "claude-sonnet-4-6-...") match.
-- Ordered: first match wins, so opus-4-1 is listed before the broader opus-4.
AT.fallbacks = {
	{ pat = "opus%-4%-1", out = 32000,  ctx = 200000 },
	{ pat = "opus%-4",    out = 128000, ctx = 200000 },
	{ pat = "sonnet%-4",  out = 128000, ctx = 200000 },
	{ pat = "haiku%-4",   out = 64000,  ctx = 200000 },
	{ pat = "claude%-3",  out = 8192,   ctx = 200000 },
	{ pat = "gpt%-5",     out = 32768,  ctx = 400000 },
	{ pat = "gpt%-4",     out = 16384,  ctx = 128000 },
	{ pat = "o4",         out = 32768,  ctx = 200000 },
	{ pat = "deepseek",   out = 8192,   ctx = 128000 },
	{ pat = "qwen",       out = 8192,   ctx = 131072 },
	{ pat = "glm",        out = 8192,   ctx = 128000 },
	{ pat = "kimi",       out = 8192,   ctx = 131072 },
	{ pat = "moonshot",   out = 8192,   ctx = 131072 },
	{ pat = "llama.*70",  out = 4096,   ctx = 131072 },
	{ pat = "llama",      out = 4096,   ctx = 8192   },
	{ pat = "mistral",    out = 4096,   ctx = 32768  },
	{ pat = "gemma",      out = 8192,   ctx = 8192   },
}

-- Resolve { ctx, maxOut, fc } for the current model: live cache > fallback
-- table (first match) > conservative floor.
function AT.specKey(prov, model)
	local prefix = prov.id
	if prov.isCustom then prefix = prefix .. ":" .. tostring(prov.base) .. ":" .. tostring(prov.kind) end
	return prefix .. "/" .. tostring(model)
end

function AT.resolveCaps()
	local spec = AT.modelSpecs[AT.specKey(curProvider(), apiModel)] or {}
	local ctx, maxOut, fc = spec.ctx, spec.maxOut, spec.fc
	if not ctx or not maxOut then
		local id = tostring(apiModel):lower()
		for _, e in ipairs(AT.fallbacks) do
			if id:find(e.pat) then
				ctx = ctx or e.ctx
				maxOut = maxOut or e.out
				break
			end
		end
	end
	ctx = ctx or 32768
	maxOut = maxOut or 4096
	if type(ctx) ~= "number" or ctx ~= ctx or ctx < 1 or ctx == math.huge then ctx = 32768 end
	if type(maxOut) ~= "number" or maxOut ~= maxOut or maxOut < 1 or maxOut == math.huge then maxOut = 4096 end
	ctx, maxOut = math.floor(ctx), math.floor(maxOut)
	return { ctx = ctx, maxOut = maxOut, fc = fc }
end

-- Rough token estimate: ~1 token / 4 chars, plus per-message overhead. Just
-- accurate enough to know how much window the prompt eats so we can give the
-- rest to output without overflowing.
function AT.estimatePromptTokens(messages, tools)
	local chars = 0
	if type(messages) == "table" then
		for _, m in ipairs(messages) do
			local c = m and m.content
			if type(c) == "string" then chars = chars + #c
			elseif type(c) == "table" then
				for _, blk in ipairs(c) do
					if type(blk) == "table" and type(blk.text) == "string" then chars = chars + #blk.text
					elseif type(blk) == "table" and type(blk.content) == "string" then chars = chars + #blk.content end
				end
			end
			if m and m.tool_calls then
				local okJ, j = pcall(function() return AT.http:JSONEncode(m.tool_calls) end)
				if okJ then chars = chars + #j end
			end
			chars = chars + 8
		end
	end
	if type(tools) == "table" then
		local okJ, j = pcall(function() return AT.http:JSONEncode(tools) end)
		if okJ then chars = chars + #j end
	end
	return math.floor(chars / 4) + 16
end

-- THE adaptive cap. Given the outgoing messages, pick max output tokens:
--   * never exceed the model's hard output ceiling (maxOut)
--   * never request so much that prompt+output overflows the context window
--     (reserve estimated prompt + 25% margin, leave the rest)
--   * return zero when the prompt leaves no room, so the caller can report it
-- Opus (128K out / 200K-1M ctx) asks for a lot; llama-7b (tiny window) asks for
-- little -- all derived, nothing hardcoded per provider. Returns (want, caps).
function AT.maxTokens(messages, tools)
	local caps = AT.resolveCaps()
	local promptTokens = AT.estimatePromptTokens(messages, tools)
	local room = math.floor(caps.ctx - promptTokens * 1.25)
	local want = math.min(caps.maxOut, math.max(0, room))
	return want, caps
end

-- Parse tool calls that a model emitted as TEXT instead of via the native
-- tool_calls field. This is needed for providers/models we drive in "flatten"
-- mode (e.g. Venice, whose API rejects our tool-message shape) -- they can't
-- emit native tool_calls, so when instructed to use tools they write them inline
-- as <tool_call>{...}</tool_call>, or a ```json fenced block, or bare JSON.
-- Returns (cleanedText, calls) where calls is in the SAME shape the agent loop
-- expects for native calls: { id, type="function", ["function"]={name, arguments=<table>} }.
-- cleanedText has the call markup removed so we don't show the raw JSON to the user.

-- Find the end index of a balanced {...} starting at `start` (which must point at
-- '{'). Respects strings and escapes so braces inside string values don't fool
-- it. Returns the index of the matching '}', or nil if unbalanced.
function AT._matchBrace(s, start)
	local depth, i, n = 0, start, #s
	local inStr, esc = false, false
	while i <= n do
		local ch = s:sub(i, i)
		if inStr then
			if esc then esc = false
			elseif ch == "\\" then esc = true
			elseif ch == '"' then inStr = false end
		else
			if ch == '"' then inStr = true
			elseif ch == "{" then depth = depth + 1
			elseif ch == "}" then
				depth = depth - 1
				if depth == 0 then return i end
			end
		end
		i = i + 1
	end
	return nil
end

-- Try to turn one decoded JSON object into a normalized call. Accepts the common
-- shapes: {name, arguments}, {tool, parameters}, {function:{name,arguments}},
-- and OpenAI-ish {type:"function", function:{...}}. arguments may itself be a
-- JSON string -> decode it. Returns a call table or nil.
function AT.decodeToolArguments(args)
	if args == nil then return {} end
	if type(args) == "string" then
		if not args:match("^%s*{") then return nil, "Tool arguments must be a JSON object." end
		local okD, parsed = pcall(function() return AT.http:JSONDecode(args) end)
		if not okD then return nil, "Tool arguments contain invalid JSON." end
		args = parsed
	end
	if type(args) ~= "table" then return nil, "Tool arguments must be an object." end
	for k in pairs(args) do
		if type(k) ~= "string" then return nil, "Tool arguments must be an object, not an array." end
	end
	return args
end

function AT.newCallId()
	AT.callSequence = (AT.callSequence or 0) + 1
	return "call_" .. tostring(os.time()) .. "_" .. tostring(AT.callSequence)
end

function AT._normalizeCall(obj)
	if type(obj) ~= "table" then return nil end
	local fnObj = obj["function"] or obj
	if type(fnObj) ~= "table" then return nil end
	local name = fnObj.name or obj.name or obj.tool or obj.tool_name
	if type(name) ~= "string" or name == "" then return nil end
	local rawArgs = fnObj.arguments
	if rawArgs == nil then rawArgs = obj.arguments end
	if rawArgs == nil then rawArgs = obj.parameters end
	if rawArgs == nil then rawArgs = obj.args end
	if rawArgs == nil then rawArgs = obj.input end
	local args, argsError = AT.decodeToolArguments(rawArgs)
	local id = (type(obj.id) == "string" or type(obj.id) == "number") and tostring(obj.id) or ""
	return {
		id = id ~= "" and id or AT.newCallId(),
		type = "function",
		arguments_error = argsError,
		["function"] = { name = name, arguments = args or rawArgs },
	}
end

-- Normalize the many tool-call shapes returned by OpenAI-compatible servers.
-- Some return an array, some a single object, and older servers use
-- message.function_call instead of message.tool_calls. Keeping this at the API
-- boundary means the agent loop only ever has to understand one shape.
function AT.normalizeToolCalls(raw)
	if type(raw) ~= "table" then return nil end
	local source = raw
	if raw.name or raw.tool or raw.tool_name or raw["function"] then source = { raw } end
	local out = {}
	local ids = {}
	for _, obj in ipairs(source) do
		local call = AT._normalizeCall(obj)
		if call then
			while ids[call.id] do call.id = AT.newCallId() end
			ids[call.id] = true
			out[#out + 1] = call
		end
	end
	return (#out > 0) and out or nil
end

-- A text call must decode completely. Ordinary code samples and malformed
-- calls stay visible; they must never turn into a tool execution with {} args.
function AT._parseTextCallBlob(blob, requireArguments)
	local okD, obj = pcall(function() return AT.http:JSONDecode(blob) end)
	if not okD or type(obj) ~= "table" then return nil end
	local source = obj.tool_calls or obj
	if type(source) ~= "table" then return nil end
	if source.name or source.tool or source.tool_name or source["function"] then source = { source } end
	if type(source) ~= "table" or #source == 0 then return nil end
	local out = {}
	for _, value in ipairs(source) do
		if type(value) ~= "table" then return nil end
		local fn = value["function"] or value
		if type(fn) ~= "table" then return nil end
		if requireArguments and fn.arguments == nil and value.arguments == nil and value.parameters == nil and value.args == nil and value.input == nil then return nil end
		local call = AT._normalizeCall(value)
		if not call or call.arguments_error then return nil end
		out[#out + 1] = call
	end
	return out
end

function AT.parseTextToolCalls(text)
	if type(text) ~= "string" or text == "" then return text, nil end
	local calls, parts, cursor = {}, {}, 1
	local function appendCalls(parsed)
		for _, call in ipairs(parsed) do calls[#calls + 1] = call end
	end
	-- Scan in display order and treat each fenced block as one token. Tags
	-- inside a Lua/Python/example fence are prose, not executable requests.
	while cursor <= #text do
		local fence = text:find("```", cursor, true)
		local tag = text:find("<", cursor, true)
		local legacy = text:find("[called", cursor, true)
		local pos = math.min(fence or (#text + 1), tag or (#text + 1), legacy or (#text + 1))
		if pos > #text then parts[#parts + 1] = text:sub(cursor); break end
		parts[#parts + 1] = text:sub(cursor, pos - 1)
		local finish, parsed
		if pos == fence then
			local close = text:find("```", pos + 3, true)
			if close then
				finish = close + 2
				local body = text:sub(pos + 3, close - 1)
				local language, code = body:match("^([%w_%-]*)[ \t]*\r?\n(.*)$")
				if not language or language == "" or language:lower() == "json" then
					parsed = AT._parseTextCallBlob(code or body, true)
				end
			else finish = #text end
		elseif pos == tag then
			local name, bodyStart = text:sub(pos):match("^<([%w_%- ]+)>()")
			if name then
				local canonical = name:lower():gsub("[_%- ]", "")
				if canonical == "toolcall" or canonical == "toolcalls" or canonical == "tooluse" or canonical == "functioncall" then
					local closing = "</" .. name .. ">"
					local close = text:find(closing, pos + bodyStart - 1, true)
					if close then
						finish = close + #closing - 1
						parsed = AT._parseTextCallBlob(text:sub(pos + bodyStart - 1, close - 1), false)
					end
				end
			end
		else
			local name, argsStart = text:sub(pos):match('^%[called%s+"?([%w_]+)"?%s*()')
			if name then
				local first = pos + argsStart - 1
				if text:sub(first, first) == "{" then
					local last = AT._matchBrace(text, first)
					local tail = last and text:sub(last + 1):match("^(%s*%])")
					if tail then
						finish = last + #tail
						local args, err = AT.decodeToolArguments(text:sub(first, last))
						if not err then parsed = { AT._normalizeCall({ name = name, arguments = args }) } end
					end
				elseif text:sub(first, first) == "]" then
					finish = first
					parsed = { AT._normalizeCall({ name = name, arguments = {} }) }
				end
			end
		end
		finish = finish or pos
		if parsed then appendCalls(parsed) else parts[#parts + 1] = text:sub(pos, finish) end
		cursor = finish + 1
	end
	if #calls > 0 then
		return table.concat(parts):gsub("^%s+", ""):gsub("%s+$", ""), AT.normalizeToolCalls(calls)
	end
	-- Bare JSON must occupy the entire message and explicitly supply arguments.
	-- A normal answer such as {"name":"Alice"} is never interpreted as a tool.
	local parsed = AT._parseTextCallBlob(text, true)
	if parsed then return "", AT.normalizeToolCalls(parsed) end
	return text, nil
end

-- Whether the given provider uses NATIVE tool calling (real tool_calls in the
-- API) vs flatten-to-text mode. Mirror the decision made in chatComplete's
-- OpenAI branch so the system prompt and the request agree. Anthropic + Ollama
-- + OpenAI use native; everyone else (Venice, Moonshot, DeepSeek, Zhipu, ...)
-- is driven in text/flatten mode.
function AT.usesNativeTools(prov)
	if not prov then return true end
	if prov.isCustom then return EX.customTools ~= "text" end  -- user-chosen mode
	if prov.kind == "anthropic" then return true end
	if prov.isOllama then return true end
	-- These providers all implement standard OpenAI tool calling (tools array,
	-- assistant.tool_calls, and role="tool" with tool_call_id), verified against
	-- their current docs: OpenAI, Moonshot/Kimi, DeepSeek (v4), and Zhipu GLM.
	if prov.id == "openai" then return true end
	if prov.id == "moonshot" then return true end
	if prov.id == "deepseek" then return true end
	if prov.id == "zhipu" then return true end
	-- Everyone else (notably Venice, whose API rejects the tool-message shape) is
	-- driven in text/flatten mode: tools are described in the system prompt and
	-- emitted as <tool_call>{...}</tool_call>, then parsed back into real calls.
	return false
end

-- A provider may support native calls while the selected model does not. In
-- that case use the text protocol end-to-end (prompt, messages, and response)
-- instead of silently omitting both the tools array and the text instructions.
function AT.shouldUseNativeTools(prov)
	if not AT.usesNativeTools(prov) then return false end
	local caps = AT.resolveCaps()
	return caps.fc ~= false
end

-- Build the text-mode tool-calling instructions + a compact tool catalog, for
-- providers that can't emit native tool_calls. Tells the model to output
-- <tool_call>{"name":...,"arguments":{...}}</tool_call> which AT.parseTextToolCalls
-- then turns into real calls. Generated from AGENT_TOOLS so it never drifts.
function AT.textToolPrompt(tools)
	if type(tools) ~= "table" then return "" end
	local lines = {}
	for _, t in ipairs(tools) do
		local f = t["function"]
		if f and f.name then
			-- list parameter names so the model knows the argument keys
			local params = {}
			local p = f.parameters and f.parameters.properties
			if type(p) == "table" then
				for k in pairs(p) do params[#params + 1] = k end
			end
			table.sort(params)
			local sig = (#params > 0) and (" (args: " .. table.concat(params, ", ") .. ")") or " (no args)"
			-- keep each description short
			local desc = tostring(f.description or "")
			if #desc > 140 then desc = desc:sub(1, 140) .. "…" end
			lines[#lines + 1] = "- " .. f.name .. sig .. ": " .. desc
			local okSchema, schema = pcall(function() return AT.http:JSONEncode(f.parameters or { type = "object", properties = {} }) end)
			if okSchema then lines[#lines + 1] = "  Parameters: " .. schema end
		end
	end
	return table.concat({
		"TOOL CALLING (IMPORTANT — this model has no native tool API, so you call tools by WRITING them):",
		"To call a tool, output a line containing ONLY:",
		'<tool_call>{"name": "TOOL_NAME", "arguments": { ... }}</tool_call>',
		"Rules:",
		"- Emit the <tool_call> tag exactly as shown, with valid JSON inside. You may write a short sentence of reasoning before it.",
		"- Call ONE tool per message. After you emit a <tool_call>, STOP — the result comes back as the next message, then you continue.",
		"- Do NOT invent results or write the result yourself. Wait for the real tool result.",
		"- When you are completely done and just want to tell the user something, reply normally with NO <tool_call> tag.",
		"- NEVER write conversation scaffolding in your replies: do not start lines with 'User:', 'Assistant:', or 'Tool result', do not repeat the tool's output back, and do not echo the [TOOL_RESULT] markers. The tool results are given to you for context only — respond as yourself in plain prose.",
		"- For run_luau you MUST include a \"title\" argument (short plain-English description of what the code does).",
		"",
		"Available tools:",
		table.concat(lines, "\n"),
	}, "\n")
end

function AT.prepareToolMessages(messages, tools, nativeTools)
	if nativeTools or type(tools) ~= "table" or #tools == 0 then return messages end
	for _, m in ipairs(messages) do
		if m.role == "system" and type(m.content) == "string" and m.content:find("TOOL CALLING (IMPORTANT", 1, true) then return messages end
	end
	local out = { { role = "system", content = AT.textToolPrompt(tools) } }
	for _, m in ipairs(messages) do out[#out + 1] = m end
	return out
end

function AT.applyTokenLimit(payload, prov, maxOut)
	local id = tostring(payload.model or ""):lower()
	if prov.id == "openai" or prov.id == "venice" or prov.id == "moonshot" or (prov.isCustom and (id:match("^gpt%-5") or id:match("^o[134][%-%.]?"))) then
		payload.max_completion_tokens = maxOut
	else payload.max_tokens = maxOut end
end

local conversations = {}
local currentChatId = nil
local chatHistory = {}

local function newChatId()
	return tostring(os.time()) .. "-" .. tostring(math.random(1000, 9999))
end

local function track(c) connections[#connections+1] = c; return c end
local function spawn_(fn) local t = task.spawn(fn); threads[#threads+1] = t; return t end

local function genSpawn(fn, chatId)
	chatId = chatId or EX.threadChat[coroutine.running()]
	local t = coroutine.create(function()
		local ok, err = pcall(fn)
		local self = coroutine.running()
		for _, list in ipairs({ genThreads, threads, genThreadsByChat[chatId] or {} }) do
			local index = table.find(list, self)
			if index then table.remove(list, index) end
		end
		EX.threadChat[self] = nil
		if not ok and alive then
			warn("[BloxAgent] " .. tostring(err))
			if EX.onGenerationError then pcall(EX.onGenerationError, chatId, err) end
		end
	end)
	genThreads[#genThreads + 1] = t
	threads[#threads + 1] = t
	EX.threadChat[t] = chatId
	if chatId then
		local list = genThreadsByChat[chatId]
		if not list then list = {}; genThreadsByChat[chatId] = list end
		list[#list + 1] = t
	end
	task.spawn(t)
	return t
end


-- Manual JSON string escaper with UTF-8 validation. AT.http:JSONEncode
-- throws on invalid UTF-8 (common when a tool reads raw bytes or script source
-- with odd characters), which used to kill the whole request. This walks the
-- string: control chars are \u-escaped, VALID multibyte UTF-8 passes through
-- untouched (so emoji/accents survive), and INVALID bytes are replaced with the
-- Unicode replacement character. It can never throw or emit invalid JSON.
local function jsonEncodeString(s)
	local out = { '"' }
	local i, len = 1, #s
	while i <= len do
		local b = string.byte(s, i)
		if b == 34 then out[#out+1] = '\\"'; i = i + 1
		elseif b == 92 then out[#out+1] = '\\\\'; i = i + 1
		elseif b == 8 then out[#out+1] = '\\b'; i = i + 1
		elseif b == 9 then out[#out+1] = '\\t'; i = i + 1
		elseif b == 10 then out[#out+1] = '\\n'; i = i + 1
		elseif b == 12 then out[#out+1] = '\\f'; i = i + 1
		elseif b == 13 then out[#out+1] = '\\r'; i = i + 1
		elseif b < 32 or b == 127 then out[#out+1] = string.format("\\u%04x", b); i = i + 1
		elseif b < 128 then out[#out+1] = string.char(b); i = i + 1
		else
			-- multibyte UTF-8: determine expected length and validate continuation bytes
			local need
			if b >= 240 and b <= 244 then need = 3
			elseif b >= 224 and b <= 239 then need = 2
			elseif b >= 194 and b <= 223 then need = 1
			else need = -1 end  -- invalid lead byte
			if need > 0 and i + need <= len then
				local valid = true
				for j = 1, need do
					local cb = string.byte(s, i + j)
					if not cb or cb < 128 or cb > 191 then valid = false break end
				end
				-- Exclude overlong encodings, UTF-16 surrogates, and > U+10FFFF.
				local second = string.byte(s, i + 1)
				if (b == 224 and second < 160) or (b == 237 and second > 159)
					or (b == 240 and second < 144) or (b == 244 and second > 143) then valid = false end
				if valid then
					out[#out+1] = string.sub(s, i, i + need)
					i = i + need + 1
				else
					out[#out+1] = "\\ufffd"; i = i + 1
				end
			else
				out[#out+1] = "\\ufffd"; i = i + 1
			end
		end
	end
	out[#out+1] = '"'
	return table.concat(out)
end

local function jsonEncode(value, seen, arrayHint)
	local t = type(value)
	if value == nil then
		return "null"
	elseif t == "boolean" then
		return value and "true" or "false"
	elseif t == "number" then
		if value ~= value or value == math.huge or value == -math.huge then return "0" end
		return tostring(value)
	elseif t == "string" then
		return jsonEncodeString(value)
	elseif t == "table" then
		seen = seen or {}
		if seen[value] then error("Cannot encode a cyclic table as JSON.") end
		seen[value] = true
		local n = 0
		for _ in pairs(value) do n = n + 1 end
		if n == 0 then seen[value] = nil; return arrayHint and "[]" or "{}" end
		local isArray = true
		local count = 0
		for k in pairs(value) do
			count = count + 1
			if type(k) ~= "number" or k % 1 ~= 0 or k < 1 then isArray = false break end
		end
		if isArray and count == #value then
			local parts = {}
			for i = 1, #value do parts[i] = jsonEncode(value[i], seen) end
			seen[value] = nil
			return "[" .. table.concat(parts, ",") .. "]"
		else
			local parts = {}
			for k, v in pairs(value) do
				if type(k) == "string" or type(k) == "number" then
					local isList = k == "messages" or k == "tools" or k == "tool_calls" or k == "required" or k == "enum"
					parts[#parts + 1] = jsonEncodeString(tostring(k)) .. ":" .. jsonEncode(v, seen, isList)
				end
			end
			seen[value] = nil
			return "{" .. table.concat(parts, ",") .. "}"
		end
	else
		-- userdata (Instance, Vector3, Color3, CFrame, ...), function, thread:
		-- not JSON-serializable, so coerce to a readable string instead of
		-- throwing or silently dropping it.
		return jsonEncodeString(tostring(value))
	end
end

local chatComplete, fetchModels, streamComplete
do

local function httpRequest(method, url, headers, body)
	local requestFn = (syn and syn.request) or (http and http.request) or http_request or request
	local ok, res = pcall(function()
		local options = { Url = url, Method = method, Headers = headers or {}, Body = body }
		if type(requestFn) == "function" then return requestFn(options) end
		-- RequestAsync preserves authentication headers and the HTTP status on
		-- Roblox's built-in path as well as executor-provided request functions.
		return AT.http:RequestAsync(options)
	end)
	if not ok or type(res) ~= "table" then return false, 0, tostring(res) end
	local status = tonumber(res.StatusCode or res.Status)
	if not status then
		if res.Success == false then return false, 0, tostring(res.Body or res.StatusMessage or "Request failed") end
		status = 200
	end
	return true, status, tostring(res.Body or res.body or "")
end

local function httpPost(url, headers, body)
	return httpRequest("POST", url, headers, body)
end

local function httpGet(url, headers)
	return httpRequest("GET", url, headers)
end

function EX.httpDelete(url, headers)
	local ok, status = httpRequest("DELETE", url, headers)
	return ok and status >= 200 and status < 300
end

local function toolsToAnthropic(tools)
	if not tools then return nil end
	local out = {}
	for _, t in ipairs(tools) do
		local f = t["function"]
		if f then
			out[#out + 1] = { name = f.name, description = f.description, input_schema = f.parameters or { type = "object", properties = {} } }
		end
	end
	return out
end

-- Normalize our internal message list into a shape every OpenAI-compatible
-- provider accepts. Two providers disagree on tool semantics: standard OpenAI
-- accepts role="tool" (with tool_call_id) and assistant.tool_calls, but Venice
-- (and some others) reject the "tool" role outright -- their role enum is only
-- user/assistant/system/developer. Rather than gamble per-provider, we fold all
-- tool activity into plain assistant/user text so the model still SEES what it
-- called and what came back, using only universally-accepted roles. We also
-- stringify any tool_call arguments (OpenAI wants a JSON string, we store a
-- table) for the providers that DO take native tools.
--
-- nativeTools = true  -> keep real tool_calls / role="tool" (OpenAI, etc.)
-- nativeTools = false -> flatten everything to text (Venice-safe default)
local function messagesToOpenAI(messages, nativeTools)
	local out = {}
	for _, m in ipairs(messages) do
		local role = m.role
		if role == "system" or role == "developer" or role == "user" then
			out[#out + 1] = { role = role, content = tostring(m.content or "") }
		elseif role == "tool" then
			if nativeTools then
				out[#out + 1] = {
					role = "tool",
					tool_call_id = m.tool_call_id or m.tool_name or "tool",
					content = tostring(m.content or ""),
				}
			else
				-- Fold the tool result into a user turn the model reads as the result
				-- of its last call. Use a DISTINCTIVE bracketed delimiter (not a natural
				-- "Tool result:" phrase) so the model is far less likely to imitate the
				-- scaffolding in its own prose.
				local label = m.tool_name and ("[TOOL_RESULT " .. tostring(m.tool_name) .. "]") or "[TOOL_RESULT]"
				out[#out + 1] = { role = "user", content = label .. "\n" .. tostring(m.content or "") .. "\n[/TOOL_RESULT]" }
			end
		elseif role == "assistant" then
			if m.tool_calls and nativeTools then
				-- keep native tool_calls, but ensure arguments is a STRING
				local calls = {}
				for _, c in ipairs(m.tool_calls) do
					local fn = c["function"]
					if fn then
						local args = fn.arguments
						if type(args) ~= "string" then
							args = jsonEncode(args or {})
						end
						calls[#calls + 1] = {
							id = c.id or fn.name or "call",
							type = "function",
							["function"] = { name = fn.name, arguments = args },
						}
					end
				end
				out[#out + 1] = { role = "assistant", content = m.content or "", tool_calls = calls }
			elseif m.tool_calls then
				-- Flatten the calls back into the SAME <tool_call> syntax the model
				-- is instructed to emit. Keeping history and output in one format
				-- avoids confusing the model, and our display-side parser strips
				-- <tool_call> markup, so even if the model echoes it, the user never
				-- sees raw JSON leak into the chat.
				local parts = {}
				if m.content and m.content ~= "" then parts[#parts + 1] = tostring(m.content) end
				for _, c in ipairs(m.tool_calls) do
					local fn = c["function"]
					if fn then
						local args = fn.arguments
						if type(args) ~= "string" then
							args = jsonEncode(args or {})
						end
						parts[#parts + 1] = '<tool_call>{"name":' .. jsonEncode(fn.name) .. ',"arguments":' .. tostring(args) .. "}</tool_call>"
					end
				end
				out[#out + 1] = { role = "assistant", content = table.concat(parts, "\n") }
			else
				out[#out + 1] = { role = "assistant", content = tostring(m.content or "") }
			end
		else
			-- unknown role -> treat as user so we never send an invalid enum
			out[#out + 1] = { role = "user", content = tostring(m.content or "") }
		end
		if role == "assistant" and nativeTools then
			local prov = curProvider()
			local reasoning = m.reasoning_content or m.thinking
			if (prov.id == "deepseek" or prov.id == "moonshot" or prov.id == "zhipu") and type(reasoning) == "string" then
				out[#out].reasoning_content = reasoning
			end
		end
	end
	return out
end

local function messagesToAnthropic(messages, nativeTools)
	local sys = nil
	local out = {}
	if nativeTools == false then messages = messagesToOpenAI(messages, false) end
	local function append(role, blocks)
		local previous = out[#out]
		if previous and previous.role == role then
			for _, block in ipairs(blocks) do previous.content[#previous.content + 1] = block end
		else out[#out + 1] = { role = role, content = blocks } end
	end
	for _, m in ipairs(messages) do
		if m.role == "system" or m.role == "developer" then
			sys = (sys and (sys .. "\n\n") or "") .. tostring(m.content or "")
		elseif m.role == "tool" then

			append("user", { { type = "tool_result", tool_use_id = m.tool_call_id or m.tool_name or "tool", content = tostring(m.content or "") } })
		elseif m.role == "assistant" then
			local blocks = {}
			if m.content and m.content ~= "" then blocks[#blocks + 1] = { type = "text", text = m.content } end
			if m.tool_calls then
				for _, c in ipairs(m.tool_calls) do
					local fn = c["function"]
					if fn then
						local args = fn.arguments
						args = AT.decodeToolArguments(args) or { _invalid_arguments = tostring(args) }
						blocks[#blocks + 1] = { type = "tool_use", id = c.id or fn.name, name = fn.name, input = args or {} }
					end
				end
			end
			if #blocks > 0 then append("assistant", blocks) end
		else
			local text = tostring(m.content or "")
			if text ~= "" then append("user", { { type = "text", text = text } }) end
		end
	end
	return sys, out
end

-- Async request-id polling for custom endpoints (the BULLETPROOF path; see
-- STREAMING_CONTRACT.md). NOT streaming: we POST the request, get back an id,
-- then poll that id's URL until the FULL message is ready, and return it once —
-- exactly like a normal request, just asynchronous. No partial text, no live
-- bubble. Returns the SAME result shape chatComplete returns. opts.isCancelled
-- lets the caller abort (chat switch / stop).
--   POST <base>/request        -> { id }
--   GET  <base>/request/<id>   -> { ready:false }                       (keep polling)
--                              -> { ready:true, content, thinking,
--                                   tool_calls, finish_reason, usage }   (done)
--                              -> { error: "..." }                       (failed)
streamComplete = function(opts)
	local base = EX.normalizeBase(EX.customBase)
	if base == "" then return false, "No custom endpoint set." end
	local key = curKey()
	local messages = opts.messages or {}
	local tools = opts.tools
	local isCancelled = opts.isCancelled or function() return false end

	-- Build the request body in the user-selected format (same shaping the normal
	-- non-async path uses). No stream flag — the endpoint generates the whole
	-- message server-side and we poll for it.
	local nativeTools = type(tools) == "table" and #tools > 0 and AT.shouldUseNativeTools(curProvider())
	messages = AT.prepareToolMessages(messages, tools, nativeTools)
	local maxOut = AT.maxTokens(messages, nativeTools and tools or nil)
	if maxOut < 1 then return false, "Conversation exceeds the model context window. Start a new chat or shorten the prompt." end
	local body
	if EX.customKind == "anthropic" then
		local sys, amsgs = messagesToAnthropic(messages, nativeTools)
		local payload = { model = apiModel, max_tokens = maxOut, messages = amsgs }
		if sys then payload.system = sys end
		if nativeTools then payload.tools = toolsToAnthropic(tools) end
		local okE, b = pcall(jsonEncode, payload); if not okE then return false, "encode failed: " .. tostring(b) end
		body = b
	else
		local payload = { model = apiModel, messages = messagesToOpenAI(messages, nativeTools) }
		AT.applyTokenLimit(payload, curProvider(), maxOut)
		if nativeTools then payload.tools = tools end
		local okE, b = pcall(jsonEncode, payload); if not okE then return false, "encode failed: " .. tostring(b) end
		body = b
	end

	-- 1) SUBMIT the request, get an id back immediately.
	local startHeaders = { ["Content-Type"] = "application/json" }
	if key ~= "" then startHeaders["Authorization"] = "Bearer " .. key end
	local sOk, sStatus, sRaw = httpPost(base .. "/request", startHeaders, body)
	if not sOk then return false, "request submit failed: " .. tostring(sRaw) end
	if sStatus < 200 or sStatus >= 300 then return false, "request submit HTTP " .. tostring(sStatus) .. ": " .. tostring(sRaw):sub(1, 200) end
	local sDec; pcall(function() sDec = AT.http:JSONDecode(sRaw) end)
	local id = type(sDec) == "table" and (sDec.id or sDec.request_id)
	if not id then return false, "endpoint returned no request id (doesn't implement the polling contract)." end

	-- 2) POLL <base>/request/<id> until ready. Each poll is a normal buffered GET.
	local pollHeaders = {}
	if key ~= "" then pollHeaders["Authorization"] = "Bearer " .. key end
	local pollUrl = base .. "/request/" .. AT.http:UrlEncode(tostring(id))
	local fails = 0
	local started = os.clock()
	local HARD_CAP = 600        -- seconds; never hang forever
	while true do
		if not alive then return false, "(aborted)" end
		if isCancelled() then return false, "(cancelled)" end
		task.wait(0.4)
		if os.clock() - started > HARD_CAP then return false, "request exceeded " .. HARD_CAP .. "s with no result; gave up." end

		local pOk, pStatus, pRaw = httpGet(pollUrl, pollHeaders)
		if not alive or isCancelled() then return false, "(cancelled)" end
		if os.clock() - started > HARD_CAP then return false, "request exceeded " .. HARD_CAP .. "s with no result; gave up." end
		if not pOk or pStatus < 200 or pStatus >= 300 then
			-- transient poll failure: tolerate a handful, then give up
			fails = fails + 1
			if fails >= 8 then return false, "polling failed " .. fails .. "x (endpoint unreachable or id expired)." end
		else
			fails = 0
			local d; pcall(function() d = AT.http:JSONDecode(pRaw) end)
			if type(d) == "table" then
				if d.error then
					return false, type(d.error) == "table" and tostring(d.error.message or d.error.type or "Endpoint failed") or tostring(d.error)
				end
				-- ready can be signalled by ready=true OR by the presence of content/
				-- tool_calls with no explicit ready=false
				local polledMessage = type(d.message) == "table" and d.message or d
				local isReady = (d.ready == true) or (d.done == true)
				if d.ready == nil and d.done == nil and (polledMessage.content ~= nil or polledMessage.tool_calls ~= nil or polledMessage.function_call ~= nil or d.text ~= nil) then isReady = true end
				if isReady then
					local responseMessage = polledMessage
					local tc = AT.normalizeToolCalls(responseMessage.tool_calls or responseMessage.function_call)
					local usage = nil
					if type(d.usage) == "table" then
						local pt = tonumber(d.usage.prompt) or tonumber(d.usage.prompt_tokens) or tonumber(d.usage.input_tokens)
						local ct = tonumber(d.usage.completion) or tonumber(d.usage.completion_tokens) or tonumber(d.usage.output_tokens)
						local tt = tonumber(d.usage.total) or tonumber(d.usage.total_tokens)
						usage = { prompt = pt, completion = ct, total = tt or ((pt and ct) and (pt + ct) or nil) }
					end
					return true, {
						content = type(responseMessage.content) == "string" and responseMessage.content or (type(d.text) == "string" and d.text or ""),
						thinking = responseMessage.thinking or responseMessage.reasoning_content or d.thinking,
						tool_calls = tc,
						finish_reason = d.finish_reason or "stop",
						usage = usage,
					}
				end
				-- not ready yet -> keep polling
			end
		end
	end
end

chatComplete = function(opts)
	opts = opts or {}
	if not alive or (opts.isCancelled and opts.isCancelled()) then return false, "(cancelled)" end
	local prov = curProvider()
	local key = curKey()
	if prov.isCustom then
		-- custom endpoints may be local LLMs needing no key; require a base URL instead
		if EX.normalizeBase(EX.customBase) == "" then return false, "No custom endpoint set. Add a base URL in Settings." end
		if tostring(apiModel) == "" then return false, "No model name set for the custom endpoint. Add one in Settings." end
		-- chunked-polling streaming: only when the toggle is on. Delegates to the
		-- poller, which returns the SAME result shape, so callers are unchanged.
		if EX.customStream then
			return streamComplete(opts)
		end
	elseif key == "" then
		return false, "No API key set for " .. prov.name .. ". Add one in Settings."
	end
	local messages = opts.messages or {}
	local tools = opts.tools

	-- Auto-learn this model's real token limits once, so adaptiveMaxTokens isn't
	-- stuck on the static fallback. We only fetch if we don't already have a
	-- cached spec for the current model and haven't tried this provider+key
	-- before. It's a quick GET; on failure resolveCaps() uses OUTPUT_FALLBACKS,
	-- so a slow/blocked fetch never breaks the request -- worst case the first
	-- call uses the fallback cap and later calls use the learned one.
	do
		local cacheKey = AT.specKey(prov, apiModel)
		local triedKey = prov.id .. "::" .. tostring(prov.base) .. "::" .. tostring(key)
		if not AT.modelSpecs[cacheKey] and not AT.specsTried[triedKey] then
			AT.specsTried[triedKey] = true
			pcall(fetchModels, prov, key)
		end
	end

	local nativeTools = type(tools) == "table" and #tools > 0 and AT.shouldUseNativeTools(prov)
	messages = AT.prepareToolMessages(messages, tools, nativeTools)
	local maxOut = AT.maxTokens(messages, nativeTools and tools or nil)
	if maxOut < 1 then return false, "Conversation exceeds the model context window. Start a new chat or shorten the prompt." end
	if not alive or (opts.isCancelled and opts.isCancelled()) then return false, "(cancelled)" end
	if prov.kind == "anthropic" then
		local sys, amsgs = messagesToAnthropic(messages, nativeTools)
		-- Adaptive output cap: Opus/Sonnet allow 128K out, Haiku 64K, older models
		-- far less. Sending a fixed 65536 is an invalid-request error on models
		-- whose ceiling is lower, and wastefully small on the big ones. Derive it.
		local payload = {
			model = apiModel,
			max_tokens = maxOut,
			messages = amsgs,
		}
		if sys then payload.system = sys end
		if nativeTools then payload.tools = toolsToAnthropic(tools) end
		local okEnc, body = pcall(jsonEncode, payload)
		if not okEnc then return false, "Couldn't encode request: " .. tostring(body) end
		local headers = {
			["Content-Type"] = "application/json",
			["anthropic-version"] = "2023-06-01",
		}
		if key ~= "" then headers["x-api-key"] = key end
		local ok, status, raw = httpPost(prov.base:gsub("/+$", ""):gsub("/v1$", "") .. "/v1/messages", headers, body)
		if not ok then return false, "Request failed: " .. tostring(raw) end
		local decoded; local dok = pcall(function() decoded = AT.http:JSONDecode(raw) end)
		if not dok or type(decoded) ~= "table" then return false, "HTTP " .. tostring(status) .. ": Bad response: " .. tostring(raw):sub(1, 300) end
		if status < 200 or status >= 300 then
			local em = type(decoded.error) == "table" and (decoded.error.message or decoded.error.type) or decoded.error or ("HTTP " .. tostring(status))
			return false, "HTTP " .. tostring(status) .. ": " .. tostring(em)
		end

		local content, thinking, toolCalls = "", nil, nil
		if type(decoded.content) == "table" then
			for _, block in ipairs(decoded.content) do
				if block.type == "text" then content = content .. tostring(block.text or "")
				elseif block.type == "thinking" then thinking = (thinking or "") .. tostring(block.thinking or "")
				elseif block.type == "tool_use" then
					toolCalls = toolCalls or {}
					toolCalls[#toolCalls + 1] = { id = block.id, type = "function", ["function"] = { name = block.name, arguments = block.input or {} } }
				end
			end
		end
		-- Anthropic uses stop_reason "max_tokens" when it hits the output cap
		local fr = (decoded.stop_reason == "max_tokens") and "length" or decoded.stop_reason
		local usage = nil
		if type(decoded.usage) == "table" then
			local pt = tonumber(decoded.usage.input_tokens)
			local ct = tonumber(decoded.usage.output_tokens)
			usage = { prompt = pt, completion = ct, total = (pt and ct) and (pt + ct) or nil }
		end
		return true, { content = content, thinking = thinking, tool_calls = AT.normalizeToolCalls(toolCalls), finish_reason = fr, usage = usage }
	else

		-- Decide whether to use native tool semantics (role="tool",
		-- assistant.tool_calls) or fold tool activity into plain text. Standard
		-- OpenAI and Ollama handle native tools well; Venice and several others
		-- reject the "tool" role (their role enum is only user/assistant/system/
		-- developer), which is the "Invalid literal value, expected ..." 400. So
		-- we use native tools only where we know they work, and flatten elsewhere.
		local payload = {
			model = apiModel,
			messages = messagesToOpenAI(messages, nativeTools),
			stream = false,
		}
		-- OpenAI/Venice/Kimi use max_completion_tokens; the other compatible endpoints use
		-- max_tokens. Ollama's /v1 API does not accept native /api/chat options.
		AT.applyTokenLimit(payload, prov, maxOut)
		-- Attach the tool schema only when we're actually using native tools. When
		-- we flattened tool activity into text (Venice et al.), sending the tools
		-- array would just invite the model to emit tool_calls we then can't round
		-- -trip, so we omit it and let it answer in text.
		if nativeTools then payload.tools = tools end
		local okEnc, body = pcall(jsonEncode, payload)
		if not okEnc then return false, "Couldn't encode request: " .. tostring(body) end
		local headers = {
			["Content-Type"] = "application/json",
		}
		if key ~= "" then headers["Authorization"] = "Bearer " .. key end
		local ok, status, raw = httpPost(prov.base .. "/chat/completions", headers, body)
		if not ok then return false, "Request failed: " .. tostring(raw) end
		local decoded; local dok = pcall(function() decoded = AT.http:JSONDecode(raw) end)
		if not dok or type(decoded) ~= "table" then return false, "HTTP " .. tostring(status) .. ": Bad response: " .. tostring(raw):sub(1, 300) end
		if status < 200 or status >= 300 then
			local parts = {}
			local e = decoded.error
			if type(e) == "table" then
				parts[#parts+1] = tostring(e.message or e.type or "error")
			elseif type(e) == "string" then
				parts[#parts+1] = e
			end
			-- pull every _errors string out of decoded.details (Venice nests the
			-- offending field here), recursively, so we see what to remove
			local function harvest(t)
				if type(t) ~= "table" then return end
				if type(t._errors) == "table" then
					for _, m in ipairs(t._errors) do parts[#parts+1] = tostring(m) end
				end
				for k, v in pairs(t) do if k ~= "_errors" then harvest(v) end end
			end
			harvest(decoded.details)
			if type(decoded.issues) == "table" then
				for _, iss in ipairs(decoded.issues) do
					if type(iss) == "table" and iss.message then parts[#parts+1] = tostring(iss.message) end
				end
			end
			local em = (#parts > 0) and table.concat(parts, " | ") or ("HTTP " .. tostring(status))
			return false, "HTTP " .. tostring(status) .. ": " .. em
		end
		local choice = decoded.choices and decoded.choices[1]
		if not choice or not choice.message then return false, "No choices in response." end
		local msg = choice.message

		local thinking = msg.reasoning_content or msg.reasoning
		local content = msg.content
		if type(content) ~= "string" then content = "" end
		if type(thinking) ~= "string" then thinking = nil end
		local usage = nil
		if type(decoded.usage) == "table" then
			local pt = tonumber(decoded.usage.prompt_tokens)
			local ct = tonumber(decoded.usage.completion_tokens)
			local tt = tonumber(decoded.usage.total_tokens)
			usage = { prompt = pt, completion = ct, total = tt or ((pt and ct) and (pt + ct) or nil) }
		end
		local rawCalls = msg.tool_calls or msg.function_call
		return true, { content = content, thinking = thinking, tool_calls = AT.normalizeToolCalls(rawCalls), finish_reason = choice.finish_reason, usage = usage }
	end
end

fetchModels = function(prov, key)
	if prov.kind == "anthropic" then
		local ids = {}
		-- Query the Anthropic Models API so we cache each model's REAL output
		-- ceiling (max_tokens) and context (max_input_tokens), instead of relying
		-- only on the static fallback table. The list endpoint returns capability
		-- fields per model. If it fails, we still return the static id list and
		-- resolveCaps() falls back to OUTPUT_FALLBACKS.
		local headers = {
			["x-api-key"] = key or "",
			["anthropic-version"] = "2023-06-01",
		}
		local ok, status, raw = httpGet(prov.base:gsub("/+$", ""):gsub("/v1$", "") .. "/v1/models", headers)
		if ok and status >= 200 and status < 300 then
			local decoded; pcall(function() decoded = AT.http:JSONDecode(raw) end)
			local list = type(decoded) == "table" and (decoded.data or decoded.models)
			if type(list) == "table" then
				for _, m in ipairs(list) do
					if type(m) == "table" and m.id then
						ids[#ids + 1] = tostring(m.id)
						local mo = m.max_tokens or m.max_output_tokens
						local ctx = m.context_window or m.max_input_tokens
						AT.modelSpecs[AT.specKey(prov, m.id)] = {
							ctx    = type(ctx) == "number" and ctx or nil,
							maxOut = (type(mo) == "number") and mo or nil,
							fc     = true,  -- all current Claude models support tools
						}
					end
				end
			end
		end
		return #ids > 0 and ids or prov.models
	end
	local headers = { ["Authorization"] = "Bearer " .. (key or "") }
	local ok, status, raw = httpGet(prov.base .. "/models", headers)
	if not ok or status < 200 or status >= 300 then return nil end
	local decoded; local dok = pcall(function() decoded = AT.http:JSONDecode(raw) end)
	if not dok or type(decoded) ~= "table" then return nil end
	local list = decoded.data or decoded.models or decoded
	if type(list) ~= "table" then return nil end
	local ids = {}
	for _, m in ipairs(list) do
		local id = (type(m) == "table" and (m.id or m.name)) or (type(m) == "string" and m)
		if id then
			ids[#ids + 1] = tostring(id)
			-- Cache each model's real limits so we can size output tokens correctly
			-- and skip tools on models that can't use them. Field names vary across
			-- OpenAI-compatible providers, so probe the common ones.
			if type(m) == "table" then
				local spec = type(m.model_spec) == "table" and m.model_spec or m
				local caps = spec.capabilities or m.capabilities
				local ctx = spec.availableContextTokens or m.availableContextTokens
					or m.context_length or m.context_window or spec.context_length
				-- max output: Venice/others sometimes expose it; names vary
				local maxOut = m.max_completion_tokens or m.max_output_tokens
					or m.max_tokens or (type(caps) == "table" and caps.max_tokens)
					or (type(spec) == "table" and spec.maxOutputTokens)
				local fc = nil
				if type(caps) == "table" then
					fc = caps.supportsFunctionCalling
					if fc == nil then fc = caps.supports_functions end
				end
				-- some shapes list capabilities as an array of strings
				if fc == nil and type(m.capabilities) == "table" then
					for _, cap in ipairs(m.capabilities) do
						if cap == "function-calling" or cap == "functions" or cap == "tools" then fc = true end
					end
				end
				if type(fc) ~= "boolean" then fc = nil end
				AT.modelSpecs[AT.specKey(prov, id)] = {
					ctx    = (type(ctx) == "number") and ctx or nil,
					maxOut = (type(maxOut) == "number") and maxOut or nil,
					fc     = fc,
				}
			end
		end
	end
	if #ids == 0 then return nil end
	return ids
end
end

local SAVE_FOLDER = "BloxAgent"
local CONFIG_PATH = SAVE_FOLDER .. "/config.json"
local CHATS_PATH  = SAVE_FOLDER .. "/chats.json"

local hasFS = (type(writefile) == "function") and (type(readfile) == "function") and (type(isfile) == "function")

local function ensureFolder()
	if hasFS and type(makefolder) == "function" then
		local okF, exists = pcall(function() return (isfolder and isfolder(SAVE_FOLDER)) end)
		if not okF or not exists then
			pcall(makefolder, SAVE_FOLDER)
		end
	end
end

local function fsWrite(path, tbl)
	if not hasFS then return end
	ensureFolder()
	pcall(function()
		writefile(path, AT.http:JSONEncode(tbl))
	end)
end

local function fsRead(path)
	if not hasFS then return nil end
	local ok, exists = pcall(isfile, path)
	if not ok or not exists then return nil end
	local rok, raw = pcall(readfile, path)
	if not rok or not raw then return nil end
	local dok, decoded = pcall(function() return AT.http:JSONDecode(raw) end)
	if not dok then return nil end
	return decoded
end

-- Saves are blocked until the deferred initial load has run, otherwise the
-- empty in-memory default would overwrite the real saved file before we read it
-- (that race made it look like nothing saved AND nothing loaded).
local persistReady = false

local function saveConfig()
	if not persistReady then return end
	fsWrite(CONFIG_PATH, { provider = providerId, model = apiModel, keys = providerKeys, system = ollamaSystemPrompt, perm = permissionMode, plan = planMode, maxSteps = agentMaxSteps, customBase = EX.customBase, customKind = EX.customKind, customModel = EX.customModel, customTools = EX.customTools, customStream = EX.customStream })
end

-- Coalesce tool-step saves, then flush at turn completion or teardown.
-- A flush has no scheduled writer, so old snapshots cannot revive cleared data.
local saveChats, flushChatsNow
do
	local saveDirty = false
	local pendingToken = 0
	flushChatsNow = function()
		if not saveDirty then return end
		if not persistReady or not hasFS then return end
		ensureFolder()
		-- Flush atomically in this task. Deferred writers could overwrite a reset
		-- or a newer save after the UI had already closed.
		local ok = pcall(function()
			writefile(CHATS_PATH, AT.http:JSONEncode({ current = currentChatId, conversations = conversations }))
		end)
		saveDirty = not ok
	end
	saveChats = function()
		if not persistReady then return end
		saveDirty = true
		-- restart the debounce: only write once the calls stop for ~1.5s, so a run
		-- of agent tool calls collapses into a single save instead of one per step.
		pendingToken = pendingToken + 1
		local myToken = pendingToken
		task.delay(1.5, function()
			if myToken == pendingToken then flushChatsNow() end
		end)
	end
end

local function saveChat() saveChats() end

local function activeConvo()
	for _, c in ipairs(conversations) do
		if c.id == currentChatId then return c end
	end
	return nil
end

local function createConversation()
	local convo = { id = newChatId(), title = "New chat", titled = false, messages = {} }
	table.insert(conversations, 1, convo)
	currentChatId = convo.id
	chatHistory = convo.messages
	return convo
end

local SYSTEM_TXT_PATH = SAVE_FOLDER .. "/system.txt"
do
	local cfg = fsRead(CONFIG_PATH)
	if type(cfg) == "table" then
		if type(cfg.provider) == "string" then providerId = cfg.provider end
		if type(cfg.model) == "string" and cfg.model ~= "" then apiModel = cfg.model end
		if type(cfg.keys) == "table" then
			for id, key in pairs(cfg.keys) do if type(id) == "string" and type(key) == "string" then providerKeys[id] = key end end
		end
		if type(cfg.key) == "string" and cfg.key ~= "" and not next(providerKeys) then
			providerKeys["ollama"] = cfg.key
		end
		if type(cfg.system) == "string" then ollamaSystemPrompt = cfg.system end
		if type(cfg.perm) == "string" and (cfg.perm == "ask" or cfg.perm == "edit" or cfg.perm == "bypass") then permissionMode = cfg.perm end
		if type(cfg.plan) == "boolean" then planMode = cfg.plan end
		if type(cfg.maxSteps) == "number" and cfg.maxSteps == cfg.maxSteps and cfg.maxSteps < math.huge then agentMaxSteps = math.max(0, math.floor(cfg.maxSteps)) end
		if type(cfg.customBase) == "string" then EX.customBase = cfg.customBase end
		if type(cfg.customKind) == "string" and (cfg.customKind == "openai" or cfg.customKind == "anthropic") then EX.customKind = cfg.customKind end
		if type(cfg.customModel) == "string" then EX.customModel = cfg.customModel end
		if type(cfg.customTools) == "string" and (cfg.customTools == "native" or cfg.customTools == "text") then EX.customTools = cfg.customTools end
		if type(cfg.customStream) == "boolean" then EX.customStream = cfg.customStream end
	end
	if hasFS then
		local okF, exists = pcall(isfile, SYSTEM_TXT_PATH)
		if okF and exists then
			local rok, raw = pcall(readfile, SYSTEM_TXT_PATH)
			if rok and type(raw) == "string" and raw ~= "" then ollamaSystemPrompt = raw end
		end
	end
	local saved = fsRead(CHATS_PATH)
	if type(saved) == "table" and type(saved.conversations) == "table" then
		local valid, ids = {}, {}
		for _, c in ipairs(saved.conversations) do
			if type(c) == "table" then
				if type(c.id) ~= "string" or c.id == "" or ids[c.id] then c.id = newChatId() end
				ids[c.id] = true
				c.title = type(c.title) == "string" and c.title or "New chat"
				local messages = {}
				for _, m in ipairs(type(c.messages) == "table" and c.messages or {}) do
					if type(m) == "table" and (m.role == "user" or m.role == "assistant" or m.role == "system" or m.role == "tool") then
						m.content = type(m.content) == "string" and m.content or ""
						if m.tool_calls then m.tool_calls = AT.normalizeToolCalls(m.tool_calls) end
						messages[#messages + 1] = m
					end
				end
				c.messages = messages
				valid[#valid + 1] = c
			end
		end
		saved.conversations = valid
	end
	if type(saved) == "table" and type(saved.conversations) == "table" and #saved.conversations > 0 then
		conversations = saved.conversations
		for _, c in ipairs(conversations) do
			if type(c.messages) ~= "table" then c.messages = {} end
		end
		currentChatId = saved.current
		if not activeConvo() then currentChatId = conversations[1].id end
		chatHistory = activeConvo().messages
	else
		createConversation()
	end
	persistReady = true
end

local function generateTitle(messages)
	if curKey() == "" then return false end

	local lines = {}
	for i = 1, math.min(5, #messages) do
		local m = messages[i]
		lines[#lines + 1] = (m.role == "user" and "User: " or "Assistant: ") .. tostring(m.content)
	end
	local prompt = "Summarize this conversation as a short title of 3-5 words. Reply with ONLY the title, no quotes, no punctuation at the end.\n\n" .. table.concat(lines, "\n")
	local ok, msg = chatComplete({ messages = { { role = "user", content = prompt } } })
	if not ok or not msg or not msg.content then return false end
	local title = tostring(msg.content)
	title = title:gsub("[\"\r\n]", ""):gsub("^%s+", ""):gsub("%s+$", "")
	if #title > 40 then title = title:sub(1, 40) end
	if title == "" then return false end
	return true, title
end

local AGENT_FOLDER = SAVE_FOLDER .. "/scripts"

-- Bridge to the standalone Executor window (filled in when the executor is built
-- much later in the file). Lets agent tools read/write the editor tabs so the
-- user and agent can collaborate on scripts. Methods (all pcall-safe to call):
--   list() -> array of {index, name, active}
--   read(idxOrNil) -> code string (active tab if nil)
--   write(idxOrNil, code) -> applies, returns true
--   create(name, code) -> new tab index
--   run(idxOrNil) -> runs the tab
--   show() -> make sure the window is visible
local ExecAPI = nil
-- Tracks, per tab, the exact content the agent last read — Claude Code's
-- read-before-edit rule: an edit only applies if the agent has read the tab in
-- this session AND the tab hasn't changed since that read.
local editorReadState = {}

local FILE_TOOLS = { write_file = true, delete_file = true, edit_script = true, revert_script = true, write_editor = true, create_editor_tab = true, make_folder = true, append_editor = true, str_replace_editor = true, replace_lines_editor = true, inject_editor = true }

local function toolNeedsApproval(toolName)
	if toolName == "warn_exploit" then return false end
	if permissionMode == "bypass" then return false end
	if permissionMode == "edit" then

		return not FILE_TOOLS[toolName]
	end

	return true
end

local function gatherContext()
	local lp = Players.LocalPlayer
	local parts = {}
	parts[#parts+1] = "PlaceId: " .. tostring(game.PlaceId)
	parts[#parts+1] = "GameId (universe): " .. tostring(game.GameId)
	parts[#parts+1] = "JobId (server): " .. tostring(game.JobId)
	if lp then
		parts[#parts+1] = "Player: " .. tostring(lp.Name) .. " (DisplayName: " .. tostring(lp.DisplayName) .. ", UserId: " .. tostring(lp.UserId) .. ")"
		local char = lp.Character
		if char then
			local hrp = char:FindFirstChild("HumanoidRootPart")
			if hrp then
				local p = hrp.Position
				parts[#parts+1] = string.format("Character position: (%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
			end
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then parts[#parts+1] = "Health: " .. tostring(math.floor(hum.Health)) .. "/" .. tostring(math.floor(hum.MaxHealth)) end
		else
			parts[#parts+1] = "Character: not spawned"
		end
	end

	local names = {}
	for _, c in ipairs(workspace:GetChildren()) do
		names[#names+1] = c.Name .. " (" .. c.ClassName .. ")"
		if #names >= 25 then break end
	end
	parts[#parts+1] = "workspace children (first 25): " .. table.concat(names, ", ")

	-- Workspace file tree: the agent's persistent files on disk. Included every
	-- turn so the agent always knows what's saved without calling list_files.
	if hasFS and type(listfiles) == "function" then
		local tree = {}
		local count = 0
		local function walk(dir, prefix, depth)
			if depth > 4 or count >= 80 then return end
			local okL, entries = pcall(listfiles, dir)
			if not okL or type(entries) ~= "table" then return end
			table.sort(entries)
			for _, full in ipairs(entries) do
				if count >= 80 then tree[#tree+1] = prefix .. "… (more)"; return end
				local short = full:match("([^/\\]+)$") or full
				local isDir = isfolder and isfolder(full)
				tree[#tree+1] = prefix .. short .. (isDir and "/" or "")
				count = count + 1
				if isDir then walk(full, prefix .. "  ", depth + 1) end
			end
		end
		pcall(function()
			if not (isfolder and isfolder(AGENT_FOLDER)) and makefolder then makefolder(AGENT_FOLDER) end
			walk(AGENT_FOLDER, "", 0)
		end)
		if #tree > 0 then
			parts[#parts+1] = "Workspace files (your persistent file tree; read/write with read_file/write_file using these paths):\n" .. table.concat(tree, "\n")
		else
			parts[#parts+1] = "Workspace files: (empty — you can create files/folders with write_file and make_folder)"
		end
	end
	-- Per-game memory: notes the agent saved about THIS place in past sessions.
	local mem = nil
	pcall(function() mem = EX.gameMemoryContext() end)
	if mem then parts[#parts+1] = mem end
	return table.concat(parts, "\n")
end
local processes = {}
local nextPid = 0

-- Resource guards for agent-run Luau. The agent can run arbitrary code, so it's
-- easy to accidentally (or deliberately) lag or crash the game. These limit the
-- damage. A synchronous loop without a yield cannot be interrupted from another
-- Luau thread. The instance cap and FPS guard are best-effort resource limits,
-- not an isolation or security boundary.

local DEFAULT_TIMEOUT = 10       -- seconds; foreground run_luau time limit
local INSTANCE_CAP = 5000        -- max Instance.new calls per run
local FPS_FLOOR = 8              -- if sustained FPS drops below this, cull processes
local fpsGuardOn = false

-- Build a sandboxed global environment: a copy of the real globals with
-- Instance.new wrapped to enforce a creation cap. Anything not overridden falls
-- through to the real global table, so normal APIs still work.
local function makeSandboxEnv(logs)
	local created = 0
	local realNew = Instance.new
	local proxy = {}
	local function capture(kind, original, ...)
		local values = {}
		for i = 1, select("#", ...) do values[i] = tostring(select(i, ...)) end
		local line = (kind == "warn" and "[warn] " or "") .. table.concat(values, "\t")
		if #logs < 200 then
			logs[#logs + 1] = #line > 2000 and (line:sub(1, 2000) .. "…(truncated)") or line
		elseif #logs == 200 then
			logs[#logs + 1] = "…(further output omitted)"
		end
		if type(original) == "function" then pcall(original, ...) end
	end
	proxy.print = function(...) capture("print", print, ...) end
	proxy.warn = function(...) capture("warn", warn, ...) end
	proxy.Instance = setmetatable({
		new = function(className, parent)
			created = created + 1
			if created > INSTANCE_CAP then
				error("instance limit reached (" .. INSTANCE_CAP .. " per run) — create fewer objects or reuse them", 2)
			end
			return realNew(className, parent)
		end,
	}, { __index = Instance })
	return setmetatable(proxy, { __index = getfenv(0) })
end

function EX.cancelProcess(proc)
	if proc.status ~= "running" then return true end
	if not proc.thread or type(task.cancel) ~= "function" then return false, "task.cancel unavailable" end
	local ok, err = pcall(task.cancel, proc.thread)
	if not ok then return false, tostring(err) end
	proc.status = "killed"
	return true
end

-- FPS guard: watches frame time; if the game is sustained below FPS_FLOOR while
-- background processes are running, it kills them to recover. Started lazily.
local function ensureFpsGuard()
	if fpsGuardOn then return end
	fpsGuardOn = true
	local RunService = game:GetService("RunService")
	local lowFrames = 0
	track(RunService.Heartbeat:Connect(function(dt)
		if not alive then return end
		-- dt is seconds per frame; FPS = 1/dt
		local fps = (dt > 0) and (1 / dt) or 60
		if fps < FPS_FLOOR then
			lowFrames = lowFrames + 1
		else
			lowFrames = 0
		end
		-- ~1.5s sustained below the floor (Heartbeat ~ once per frame)
		if lowFrames > 12 then
			local killed = 0
			for pid, proc in pairs(processes) do
				if proc.status == "running" then
					if EX.cancelProcess(proc) then
						proc.output[#proc.output + 1] = "[FPS guard] Killed: game FPS dropped below " .. FPS_FLOOR .. "."
						killed = killed + 1
					end
				end
			end
			lowFrames = 0
			if killed > 0 then
				pcall(function() warn("[BloxAgent] FPS guard killed " .. killed .. " runaway process(es).") end)
			end
		end
	end))
end

local function packResults(...)
	local n = select("#", ...)
	local t = {}
	for i = 1, n do t[i] = select(i, ...) end
	t.n = n
	return t
end

local function nowClock()
	if type(os) == "table" and type(os.clock) == "function" then return os.clock() end
	if type(tick) == "function" then return tick() end
	return 0
end

local function assembleOutput(logs, results, errText)
	local pieces = {}
	if errText then pieces[#pieces+1] = errText end
	if #logs > 0 then pieces[#pieces+1] = table.concat(logs, "\n") end
	if results and results.n and results.n > 0 then
		local rs = {}
		for i = 1, results.n do rs[#rs+1] = tostring(results[i]) end
		pieces[#pieces+1] = "return: " .. table.concat(rs, ", ")
	end
	return (#pieces > 0) and table.concat(pieces, "\n") or "(ran successfully, no output)"
end

function EX.startProcess(code)
	-- Keep a bounded history; running processes remain addressable until stopped.
	local finished = {}
	for id, proc in pairs(processes) do
		if proc.status ~= "running" then finished[#finished + 1] = id end
	end
	table.sort(finished)
	for i = 1, math.max(0, #finished - 99) do processes[finished[i]] = nil end
	local logs = {}
	local okC, fn, compileErr = pcall(loadstring, code)
	if not okC then return { ok = false, output = "Compile failed: " .. tostring(fn) } end
	if type(fn) ~= "function" then return { ok = false, output = "Compile error: " .. tostring(compileErr or fn) } end
	if type(setfenv) == "function" then
		local okEnv, envErr = pcall(function() setfenv(fn, makeSandboxEnv(logs)) end)
		if not okEnv then return { ok = false, output = "Couldn't prepare execution environment: " .. tostring(envErr) } end
	else
		logs[#logs + 1] = "[diagnostic] setfenv unavailable; print capture and instance limits are unavailable."
	end
	ensureFpsGuard()
	nextPid = nextPid + 1
	local pid = nextPid
	local owner = EX.threadChat and EX.threadChat[coroutine.running()]
	local proc = { id = pid, status = "running", output = logs, code = code, started = nowClock(), ownerChatId = owner }
	processes[pid] = proc
	proc.thread = task.spawn(function()
		if EX.threadChat then EX.threadChat[coroutine.running()] = owner end
		local packed
		local rok, rerr = pcall(function() packed = packResults(fn()) end)
		if proc.status ~= "killed" then
			proc.status = rok and "done" or "error"
			proc.results = rok and packed or nil
			proc.error = not rok and ("Runtime error: " .. tostring(rerr)) or nil
		end
	end)
	return { ok = true, proc = proc, pid = pid }
end

local function runForeground(code, timeout)
	timeout = timeout or DEFAULT_TIMEOUT
	local started = EX.startProcess(code)
	if not started.ok then return started end
	local proc = started.proc
	local elapsed = 0
	while proc.status == "running" and elapsed < timeout do
		local waited = task.wait(math.min(0.05, timeout - elapsed))
		elapsed = math.max(nowClock() - proc.started, elapsed + (tonumber(waited) or 0.05))
	end
	if proc.status == "running" then
		local cancelled, cancelErr = EX.cancelProcess(proc)
		local out = string.format("Timed out after %.2gs. ", timeout)
		out = out .. (cancelled and ("Stopped process #" .. proc.id .. ".") or ("Process #" .. proc.id .. " is still running; cancellation failed: " .. tostring(cancelErr) .. ". Use kill_process to retry."))
		return { ok = false, output = assembleOutput(proc.output, nil, out), timedOut = true, pid = proc.id }
	end
	if proc.status == "killed" then return { ok = false, output = assembleOutput(proc.output, nil, "Process #" .. proc.id .. " was stopped.") } end
	return { ok = proc.status == "done", output = assembleOutput(proc.output, proc.results, proc.error), pid = proc.id }
end

local function runBackground(code)
	local started = EX.startProcess(code)
	if not started.ok then return started end
	local proc = started.proc
	return { ok = proc.status ~= "error", output = "Background process #" .. proc.id .. " [" .. proc.status .. "]. Use get_process_output/kill_process with this id." .. (proc.error and ("\n" .. proc.error) or ""), pid = proc.id }
end

local function runLuau(code, opts)
	if type(code) ~= "string" or code == "" then
		return { ok = false, output = "No code provided." }
	end
	if type(loadstring) ~= "function" then
		return { ok = false, output = "loadstring unavailable in this executor." }
	end
	opts = opts or {}
	if type(task) ~= "table" or type(task.spawn) ~= "function" or type(task.wait) ~= "function" then
		return { ok = false, output = "task.spawn/task.wait unavailable in this executor." }
	end
	if not opts.background and opts.timeout ~= nil and (type(opts.timeout) ~= "number" or opts.timeout ~= opts.timeout or opts.timeout <= 0 or opts.timeout > 120) then
		return { ok = false, output = "timeout must be a finite number greater than 0 and no more than 120 seconds." }
	end
	if opts.background then
		return runBackground(code)
	end
	return runForeground(code, opts.timeout)
end

local function killProcess(pid)
	local proc = processes[pid]
	if not proc then return "No process #" .. tostring(pid) .. ".", false end
	if proc.status == "running" then
		local ok, err = EX.cancelProcess(proc)
		if not ok then return "Couldn't stop process #" .. pid .. ": " .. tostring(err), false end
		return "Killed process #" .. pid .. "."
	end
	return "Process #" .. pid .. " is already " .. proc.status .. "."
end

local function killAllProcesses(ownerChatId)
	local n, failed = 0, 0
	for pid, proc in pairs(processes) do
		if proc.status == "running" and (ownerChatId == nil or proc.ownerChatId == ownerChatId) then
			if EX.cancelProcess(proc) then n = n + 1 else failed = failed + 1 end
		end
	end
	return "Killed " .. n .. " running process(es)." .. (failed > 0 and (" Couldn't stop " .. failed .. ".") or ""), failed == 0
end

local function listProcesses()
	local lines = {}
	for pid, proc in pairs(processes) do
		local age = string.format("%.1fs", nowClock() - proc.started)
		lines[#lines+1] = "#" .. pid .. " [" .. proc.status .. "] " .. age .. " — " .. (proc.code:gsub("%s+", " "):sub(1, 50))
	end
	if #lines == 0 then return "No processes." end
	table.sort(lines)
	return "Processes:\n" .. table.concat(lines, "\n")
end

local function getProcessOutput(pid)
	local proc = processes[pid]
	if not proc then return "No process #" .. tostring(pid) .. ".", false end
	local out = "#" .. pid .. " [" .. proc.status .. "]"
	if proc.status == "running" and #proc.output == 0 then out = out .. "\n(no output yet)"
	else out = out .. "\n" .. assembleOutput(proc.output, proc.results, proc.error) end
	return out, proc.status ~= "error"
end

local function ensureAgentFolder()
	return pcall(function()
		for _, dir in ipairs({ SAVE_FOLDER, AGENT_FOLDER }) do
			if not (type(isfolder) == "function" and isfolder(dir)) then
				if type(makefolder) ~= "function" then error("makefolder unavailable") end
				makefolder(dir)
			end
		end
	end)
end

function EX.workspacePath(name)
	if type(name) ~= "string" or name == "" then return nil, "Provide a workspace-relative filename." end
	name = name:gsub("\\", "/")
	local prefix = AGENT_FOLDER:gsub("\\", "/") .. "/"
	if name:sub(1, #prefix) == prefix then name = name:sub(#prefix + 1) end
	if name == "" or name:sub(1, 1) == "/" or name:find("[%z\1-\31:<>\"|?*]") then
		return nil, "Invalid workspace path. Use a relative path such as 'utils/math.lua'."
	end
	for part in (name .. "/"):gmatch("(.-)/") do
		if part == "" or part == "." or part == ".." or part:find("[%.%s]$") then
			return nil, "Invalid workspace path: empty, dot, parent, and trailing-dot/space components are not allowed."
		end
	end
	return AGENT_FOLDER .. "/" .. name, name
end

function EX.ensureWorkspaceDirs(name, includeLast)
	local ok, err = ensureAgentFolder()
	if not ok then return false, err end
	return pcall(function()
		local dir = AGENT_FOLDER
		for part in (name .. (includeLast and "/" or "")):gmatch("([^/]+)/") do
			dir = dir .. "/" .. part
			if not (type(isfolder) == "function" and isfolder(dir)) then
				if type(makefolder) ~= "function" then error("makefolder unavailable") end
				makefolder(dir)
			end
		end
	end)
end

local AGENT_TOOLS
local toolImpls = {}

-- Build a targeted "fix-it" hint from a failed run: pull the :LINE: out of the
-- Luau error, show that exact source line with a caret, and classify the error
-- so the agent self-corrects on its next turn WITHOUT a second hidden loop that
-- could fight the main agent loop. No compiler — pure string analysis.
function EX.fixItHint(code, output)
	if type(output) ~= "string" or type(code) ~= "string" then return nil end
	local hints = {}
	-- (a) extract a line number: matches "...:12:" or "line 12"
	local lineNo = tonumber(output:match("[:%s](%d+):")) or tonumber(output:match("line (%d+)"))
	if lineNo then
		local lines = {}
		for l in (code .. "\n"):gmatch("(.-)\n") do lines[#lines+1] = l end
		if lineNo >= 1 and lineNo <= #lines then           -- bounds-checked
			local src = lines[lineNo]
			local trimmed = src:gsub("^%s+", "")
			local caretPad = (#src - #trimmed)
			hints[#hints+1] = "Line " .. lineNo .. ": " .. trimmed
		end
	end
	-- (b) classify common Luau runtime errors and give a concrete next step
	local o = output:lower()
	if o:find("attempt to index nil") or o:find("attempt to index a nil value") then
		hints[#hints+1] = "Cause: indexing something that is nil. Check the variable just before the '.' or '[' exists — use FindFirstChild and handle nil, or verify the exact name/path."
	elseif o:find("attempt to call a nil value") then
		hints[#hints+1] = "Cause: calling a function/method that doesn't exist (nil). Check the method name and that the object is the class you think it is."
	elseif o:find("attempt to perform arithmetic") then
		hints[#hints+1] = "Cause: doing math on a non-number (often nil or a string). tonumber() it or check it's set."
	elseif o:find("attempt to concatenate") then
		hints[#hints+1] = "Cause: concatenating a non-string (often nil). tostring() it."
	elseif o:find("unknown global") or o:find("unknown require") then
		hints[#hints+1] = "Cause: a name that doesn't exist in this scope. Define it as local, or check the spelling."
	elseif o:find("'end' expected") or o:find("expected") or o:find("near") then
		hints[#hints+1] = "Cause: a syntax error — likely a missing 'end', ')', or '}'. Re-read the structure around the line above."
	elseif o:find("waitforchild") or o:find("infinite yield") then
		hints[#hints+1] = "Cause: WaitForChild on a name that never appears (infinite yield). Use FindFirstChild and handle nil, or WaitForChild(name, 5) with a timeout."
	end
	if #hints == 0 then return nil end
	return "\n[fix-it] " .. table.concat(hints, "\n[fix-it] ") .. "\nFix the code and call run_luau again."
end

toolImpls.run_luau = function(args)
	local opts = { background = args.background == true }
	if args.timeout then opts.timeout = tonumber(args.timeout) end
	local res = runLuau(args.code, opts)
	local out = (res.ok and "✓ " or "✗ ") .. res.output
	if not res.ok then
		-- attach a capability probe so executor-specific gaps are visible
		local missing = {}
		if type(loadstring) ~= "function" then missing[#missing+1] = "loadstring" end
		if type(task) ~= "table" or type(task.spawn) ~= "function" then missing[#missing+1] = "task.spawn" end
		if type(print) ~= "function" then missing[#missing+1] = "print" end
		if #missing > 0 then out = out .. "\n[diagnostic] missing on this executor: " .. table.concat(missing, ", ") end
		-- creative fix-it hint (skip for intended timeouts/background, which aren't real errors)
		if not res.timedOut and not opts.background then
			local hint = EX.fixItHint(args.code, res.output)
			if hint then out = out .. hint end
		end
	end
	return out, res.ok
end

toolImpls.list_processes = function()
	return listProcesses()
end

toolImpls.get_process_output = function(args)
	return getProcessOutput(tonumber(args.pid))
end

toolImpls.kill_process = function(args)
	return killProcess(tonumber(args.pid))
end

toolImpls.kill_all_processes = function()
	return killAllProcesses()
end

toolImpls.get_game_info = function()
	return gatherContext()
end

toolImpls.get_player_info = function(args)
	local target = args and args.username
	local lp = Players.LocalPlayer
	local plr = lp
	if target and target ~= "" and (not lp or target ~= lp.Name) then plr = Players:FindFirstChild(target) end
	if not plr then return "Player not found: " .. tostring(target), false end
	local out = { "Name: " .. plr.Name, "DisplayName: " .. plr.DisplayName, "UserId: " .. tostring(plr.UserId) }
	local char = plr.Character
	if char then
		local hrp = char:FindFirstChild("HumanoidRootPart")
		if hrp then out[#out+1] = string.format("Position: (%.1f, %.1f, %.1f)", hrp.Position.X, hrp.Position.Y, hrp.Position.Z) end
	end
	return table.concat(out, "\n")
end

toolImpls.list_players = function()
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		out[#out+1] = p.Name .. (p == Players.LocalPlayer and " (you)" or "")
	end
	return "Players (" .. #out .. "): " .. table.concat(out, ", ")
end

toolImpls.find_instances = function(args)
	local query = tostring(args.name or ""):lower()
	if query == "" then return "Provide a name to search for.", false end
	local root = workspace
	if args.service and type(args.service) == "string" then
		local okS, svc = pcall(function() return game:GetService(args.service) end)
		if not okS or not svc then return "Unknown service: " .. tostring(args.service), false end
		root = svc
	end
	local matches = {}
	local function recurse(inst, depth)
		if depth > 6 or #matches >= 30 then return end
		for _, c in ipairs(inst:GetChildren()) do
			if c.Name:lower():find(query, 1, true) then
				local entry = c:GetFullName() .. " (" .. c.ClassName .. ")"
				if c:IsA("BasePart") then
					entry = entry .. string.format(" @ (%.1f, %.1f, %.1f)", c.Position.X, c.Position.Y, c.Position.Z)
				elseif c:IsA("Model") and c.PrimaryPart then
					local p = c.PrimaryPart.Position
					entry = entry .. string.format(" @ (%.1f, %.1f, %.1f)", p.X, p.Y, p.Z)
				end
				matches[#matches+1] = entry
				if #matches >= 30 then return end
			end
			recurse(c, depth + 1)
		end
	end
	pcall(recurse, root, 0)
	if #matches == 0 then return "No instances found matching '" .. query .. "'." end
	return "Found " .. #matches .. ":\n" .. table.concat(matches, "\n")
end

toolImpls.teleport = function(args)
	local lp = Players.LocalPlayer
	local char = lp and lp.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not hrp then return "Your character/HumanoidRootPart isn't available.", false end
	local target
	if args.x ~= nil or args.y ~= nil or args.z ~= nil then
		if args.x == nil or args.y == nil or args.z == nil then return "Provide all three coordinates x, y, and z.", false end
		target = Vector3.new(tonumber(args.x), tonumber(args.y), tonumber(args.z))
	elseif args.target_name then
		local q = tostring(args.target_name):lower()
		if q:gsub("%s+", "") == "" then return "target_name cannot be empty.", false end
		local found
		local function recurse(inst, depth)
			if depth > 6 or found then return end
			for _, c in ipairs(inst:GetChildren()) do
				if c.Name:lower():find(q, 1, true) then
					if c:IsA("BasePart") then found = c.Position; return
					elseif c:IsA("Model") then
						local pp = c.PrimaryPart or c:FindFirstChildWhichIsA("BasePart")
						if pp then found = pp.Position; return end
					end
				end
				recurse(c, depth + 1)
			end
		end
		pcall(recurse, workspace, 0)
		if not found then return "Couldn't find a part named '" .. tostring(args.target_name) .. "' to teleport to.", false end
		target = found + Vector3.new(0, 5, 0)
	else
		return "Provide either x/y/z or target_name.", false
	end
	local okT = pcall(function() hrp.CFrame = CFrame.new(target) end)
	if okT then
		return string.format("Teleported to (%.1f, %.1f, %.1f).", target.X, target.Y, target.Z)
	end
	return "Teleport failed.", false
end

toolImpls.write_file = function(args)
	if not hasFS then return "Filesystem not available on this executor.", false end
	local path, name = EX.workspacePath(args.filename)
	if not path then return name, false end
	local okDir, dirErr = EX.ensureWorkspaceDirs(name, false)
	if not okDir then return "Couldn't create parent folders: " .. tostring(dirErr), false end
	local okW, err = pcall(writefile, path, args.content)
	return okW and ("Wrote " .. path) or ("Write failed: " .. tostring(err)), okW
end

toolImpls.make_folder = function(args)
	if not hasFS or type(makefolder) ~= "function" then return "Folders not available on this executor.", false end
	local path, name = EX.workspacePath(args.path or args.name)
	if not path then return name, false end
	local ok, err = EX.ensureWorkspaceDirs(name, true)
	return ok and ("Created folder " .. path) or ("Couldn't create folder: " .. tostring(err)), ok
end

toolImpls.read_file = function(args)
	if not hasFS then return "Filesystem not available.", false end
	local path, err = EX.workspacePath(args.filename)
	if not path then return err, false end
	local okE, exists = pcall(isfile, path)
	if not okE or not exists then return "File not found: " .. path, false end
	local okR, content = pcall(readfile, path)
	return okR and content or ("Read failed: " .. tostring(content)), okR
end

toolImpls.list_files = function()
	if not hasFS or type(listfiles) ~= "function" then return "Filesystem listing not available.", false end
	local okDir, err = ensureAgentFolder()
	if not okDir then return "Couldn't open workspace: " .. tostring(err), false end
	local okL, files = pcall(listfiles, AGENT_FOLDER)
	if not okL or type(files) ~= "table" then return "Couldn't list workspace: " .. tostring(files), false end
	if #files == 0 then return "No files in agent workspace." end
	table.sort(files)
	return "Files:\n" .. table.concat(files, "\n")
end

toolImpls.delete_file = function(args)
	if not hasFS or type(delfile) ~= "function" then return "Delete not available.", false end
	local path, err = EX.workspacePath(args.filename)
	if not path then return err, false end
	local okE, exists = pcall(isfile, path)
	if not okE or not exists then return "File not found: " .. path, false end
	local okD, deleteErr = pcall(delfile, path)
	return okD and ("Deleted " .. path) or ("Delete failed: " .. tostring(deleteErr)), okD
end

toolImpls.http_get = function(args)
	local url = tostring(args.url or "")
	if url == "" then return "Provide a url.", false end
	local getter = (syn and syn.request) or request or http_request
	local okH, res = pcall(function()
		if getter then return getter({ Url = url, Method = "GET" })
		else return { Body = game:HttpGet(url) } end
	end)
	if not okH or not res then return "Request failed: " .. tostring(res), false end
	if type(res) == "table" then
		local status = tonumber(res.StatusCode or res.Status)
		if res.Success == false or (status and (status < 200 or status >= 300)) then
			return "HTTP request failed (" .. tostring(status or "unknown status") .. "): " .. tostring(res.Body or ""):sub(1, 4000), false
		end
	end
	local body = type(res) == "table" and res.Body or res
	body = tostring(body)
	if #body > 4000 then body = body:sub(1, 4000) .. "\n...(truncated)" end
	return body
end

local scriptHistory = setmetatable({}, { __mode = "k" })

local function resolveScript(pathOrName)
	if type(pathOrName) ~= "string" or pathOrName == "" then return nil, "No path given." end

	local target = pathOrName:gsub("^game%.", "")
	local found, foundByName = nil, {}
	local function isScript(c) return c:IsA("LuaSourceContainer") end
	local function recurse(inst, depth)
		if depth > 12 or found then return end
		for _, c in ipairs(inst:GetChildren()) do
			if isScript(c) then
				if c:GetFullName() == target then found = c; return end
				if c.Name == target then foundByName[#foundByName+1] = c end
			end
			recurse(c, depth + 1)
		end
	end
	pcall(recurse, game, 0)
	if found then return found end
	if #foundByName == 1 then return foundByName[1] end
	if #foundByName > 1 then
		local paths = {}
		for _, c in ipairs(foundByName) do paths[#paths+1] = c:GetFullName() end
		return nil, "Ambiguous name '" .. target .. "'. Matches:\n" .. table.concat(paths, "\n")
	end
	return nil, "No script found at '" .. target .. "'."
end

local function lineDiff(oldS, newS)
	local function split(s)
		local t = {}
		for line in (s .. "\n"):gmatch("(.-)\n") do t[#t+1] = line end
		return t
	end
	local a, b = split(oldS or ""), split(newS or "")

	local first = 1
	while first <= #a and first <= #b and a[first] == b[first] do first = first + 1 end
	local lastA, lastB = #a, #b
	while lastA >= first and lastB >= first and a[lastA] == b[lastB] do lastA = lastA - 1; lastB = lastB - 1 end
	local out = {}
	local removed, added = math.max(0, lastA - first + 1), math.max(0, lastB - first + 1)
	for i = first, math.min(lastA, first + 100) do out[#out + 1] = "- " .. a[i] end
	if removed > 101 then out[#out + 1] = "…(more removed lines)" end
	for i = first, math.min(lastB, first + 100) do out[#out + 1] = "+ " .. b[i] end
	if added > 101 then out[#out + 1] = "…(more added lines)" end
	if #out == 0 then return "(no line-level changes)" end
	local header = string.format("(%d removed, %d added)\n", removed, added)
	local body = table.concat(out, "\n")
	if #body > 2500 then body = body:sub(1, 2500) .. "\n...(diff truncated)" end
	return header .. body
end

toolImpls.list_scripts = function(args)
	local root = game
	if args and args.service and type(args.service) == "string" then
		local okS, svc = pcall(function() return game:GetService(args.service) end)
		if not okS or not svc then return "Unknown service: " .. tostring(args.service), false end
		root = svc
	end
	local found = {}
	local function recurse(inst, depth)
		if depth > 12 or #found >= 200 then return end
		for _, c in ipairs(inst:GetChildren()) do
			if #found >= 200 then return end
			if c:IsA("LuaSourceContainer") then
				-- server Scripts can't be read from the client; Local/Module may be via decompile
				local tag = (c.ClassName == "Script") and "server, not readable" or "readable via decompile"
				found[#found+1] = c:GetFullName() .. " [" .. c.ClassName .. " — " .. tag .. "]"
			end
			recurse(c, depth + 1)
		end
	end
	pcall(recurse, root, 0)
	if #found == 0 then return "No scripts found under " .. (root == game and "game" or root.Name) .. "." end
	return "Scripts (" .. #found .. "):\n" .. table.concat(found, "\n") .. "\n\nNote: server Scripts run on Roblox's servers and can't be read from the client. LocalScripts/ModuleScripts can be read if this executor has a working decompiler."
end

toolImpls.read_script = function(args)
	local scr, err = resolveScript(args and args.path)
	if not scr then return err, false end
	local src = ""
	-- 1) try .Source (works for client-authored scripts / Studio)
	local okSrc, s = pcall(function() return scr.Source end)
	if okSrc and type(s) == "string" and s ~= "" then src = s end
	-- 2) fall back to the executor's decompiler (works for Local/ModuleScripts)
	if src == "" then
		local decomp = (type(decompile) == "function" and decompile)
			or (type(getscriptsource) == "function" and getscriptsource)
		if decomp then
			local okD, d = pcall(decomp, scr)
			if okD and type(d) == "string" and d ~= "" then src = d end
		end
	end
	if src == "" then
		local cls = scr.ClassName
		local why
		if cls == "Script" then
			why = "Server Scripts can't be read from the client — they run on Roblox's servers, not here."
		else
			why = "Source is protected and this executor's decompiler returned nothing (or isn't available). Solara often blocks decompile()."
		end
		return scr:GetFullName() .. " (" .. cls .. "): couldn't read source. " .. why, false
	end
	-- Return a real line-addressable page instead of chopping at an arbitrary
	-- character. The old 6000-char cut could split a function mid-line and there
	-- was no argument with which the agent could request the missing remainder.
	local lines = {}
	for line in (src .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
	local first = math.max(1, math.floor(tonumber(args and args.start_line) or 1))
	if first > #lines then return "start_line is out of range (the script has " .. #lines .. " lines).", false end
	local requestedLast = math.floor(tonumber(args and args.end_line) or (first + 199))
	local last = math.min(#lines, math.max(first, requestedLast))
	local out, chars = {}, 0
	for i = first, last do
		local row = string.format("%4d| %s", i, lines[i])
		if chars + #row > 14000 and #out > 0 then last = i - 1; break end
		out[#out + 1] = row
		chars = chars + #row + 1
	end
	local more = last < #lines and ("\n[More source available: call read_script again with start_line=" .. tostring(last + 1) .. ". Total lines: " .. tostring(#lines) .. "]") or ""
	return scr:GetFullName() .. " (lines " .. first .. "-" .. last .. " of " .. #lines .. "):\n```\n" .. table.concat(out, "\n") .. "\n```" .. more
end

toolImpls.edit_script = function(args)
	local scr, err = resolveScript(args and args.path)
	if not scr then return err, false end
	local newSource = tostring((args and args.new_source) or "")
	local okSrc, oldSource = pcall(function() return scr.Source end)
	if not okSrc then return "Couldn't read current .Source to edit: " .. tostring(oldSource), false end
	oldSource = tostring(oldSource)
	local diff = lineDiff(oldSource, newSource)

	local key = scr:GetFullName()
	local h = scriptHistory[scr]
	if not h then h = { snapshots = {} }; scriptHistory[scr] = h end
	h.snapshots[#h.snapshots + 1] = oldSource

	local okW, werr = pcall(function() scr.Source = newSource end)
	if not okW then
		table.remove(h.snapshots)
		return "Failed to set .Source (executor may not allow writing script source): " .. tostring(werr), false
	end
	return "Edited " .. key .. "\n" .. diff
end

-- ===== Executor collaboration tools =====
-- Let the agent see and edit the scripts open in the standalone Executor window
-- so the user and agent can work on code together.
function EX.editorIndex(args)
	if not ExecAPI then return nil, "Executor not ready." end
	local idx = args and args.tab
	if idx ~= nil and (type(idx) ~= "number" or idx < 1 or idx ~= math.floor(idx) or idx == math.huge) then
		return nil, "tab must be a positive integer from list_editor_tabs."
	end
	local ok, resolved = pcall(ExecAPI.activeIndex, idx)
	if not ok or not resolved then return nil, "That tab doesn't exist. Call list_editor_tabs to see valid tab numbers." end
	return resolved
end

function EX.editorWrite(idx, code)
	local ok, applied = pcall(ExecAPI.write, idx, code)
	if not ok or applied ~= true then return false end
	local okRead, actual = pcall(ExecAPI.read, idx)
	return okRead and actual == code
end

function EX.editorEditAllowed(idx, cur)
	if editorReadState[idx] == nil then return false, "Read this tab with read_editor before editing it." end
	if editorReadState[idx] ~= cur then
		editorReadState[idx] = nil
		return false, "The tab changed since you last read it. Call read_editor again before editing."
	end
	return true
end

toolImpls.list_editor_tabs = function()
	if not ExecAPI then return "Executor not ready yet — use create_editor_tab to make the first tab, or run_luau to act on the game directly.", false end
	local ok, list = pcall(ExecAPI.list)
	if not ok or type(list) ~= "table" then return "Couldn't list tabs. Use create_editor_tab to start a new one.", false end
	if #list == 0 then return "No tabs are open. Use create_editor_tab to make one.", false end
	local out = {}
	for _, t in ipairs(list) do
		out[#out+1] = string.format("%d: %s%s", t.index, tostring(t.name), t.active and "  (active)" or "")
	end
	return "Executor tabs:\n" .. table.concat(out, "\n")
end

toolImpls.read_editor = function(args)
	if not ExecAPI then return "Executor not ready. Use create_editor_tab to make a tab first.", false end
	local idx, idxErr = EX.editorIndex(args)
	if not idx then return idxErr, false end
	local ok, code = pcall(ExecAPI.read, idx)
	if not ok then return "That tab doesn't exist. Call list_editor_tabs to see valid tab numbers, or create_editor_tab to make one.", false end
	code = tostring(code or "")
	-- remember exactly what we showed the agent, keyed by the resolved tab index
	local rOk, rIdx = pcall(ExecAPI.activeIndex, idx)
	if code == "" then
		if rOk and rIdx then editorReadState[rIdx] = code end
		return "(the tab is empty — write code to it with write_editor)"
	end
	-- include line numbers so the agent can target str_replace / line ranges
	local all, n = {}, 0
	for line in (code .. "\n"):gmatch("(.-)\n") do
		n = n + 1
		all[#all + 1] = line
	end
	local first = math.max(1, math.floor(tonumber(args and args.start_line) or 1))
	if first > n then return "start_line is out of range (the tab has " .. n .. " lines).", false end
	if rOk and rIdx then editorReadState[rIdx] = code end
	local last = math.min(n, math.max(first, math.floor(tonumber(args and args.end_line) or (first + 249))))
	local out, chars = {}, 0
	for i = first, last do
		local row = string.format("%4d| %s", i, all[i])
		if chars + #row > 14000 and #out > 0 then last = i - 1; break end
		out[#out + 1] = row
		chars = chars + #row + 1
	end
	local more = last < n and ("\n[More code available: call read_editor again with start_line=" .. tostring(last + 1) .. ". Total lines: " .. tostring(n) .. "]") or ""
	return "Lines " .. first .. "-" .. last .. " of " .. n .. ":\n```\n" .. table.concat(out, "\n") .. "\n```" .. more
end

toolImpls.write_editor = function(args)
	if not ExecAPI then return "Executor not ready. Use create_editor_tab to make a tab with this code instead.", false end
	local newCode = tostring((args and args.code) or "")
	local idx, idxErr = EX.editorIndex(args)
	if not idx then return idxErr, false end
	local okR, oldCode = pcall(ExecAPI.read, idx)
	if not okR then return "Couldn't read the target tab. Call list_editor_tabs.", false end
	oldCode = tostring(oldCode or "")
	local allowed, editErr = EX.editorEditAllowed(idx, oldCode)
	if not allowed then return editErr, false end
	if not EX.editorWrite(idx, newCode) then return "Write didn't apply to the target tab.", false end
	pcall(ExecAPI.show)
	local rOk, rIdx = pcall(ExecAPI.activeIndex, idx); if rOk and rIdx then editorReadState[rIdx] = newCode end
	return "Updated the tab.\n" .. lineDiff(oldCode, newCode)
end

toolImpls.create_editor_tab = function(args)
	if not ExecAPI then return "Executor not ready on this session. You can still run code with run_luau.", false end
	local name = args and args.name and tostring(args.name) or nil
	local code = tostring((args and args.code) or "")
	local ok, idx = pcall(ExecAPI.create, name, code)
	if not ok or type(idx) ~= "number" then return "Couldn't create a tab on this executor. Use run_luau to run code directly instead.", false end
	pcall(ExecAPI.show)
	editorReadState[idx] = code  -- the agent just wrote it, so it "knows" the content
	return "Created tab " .. tostring(idx) .. (name and (" (" .. name .. ")") or "") .. (code ~= "" and ("\n" .. lineDiff("", code)) or " — now write code to it with write_editor.")
end

toolImpls.run_editor = function(args)
	if not ExecAPI then return "Executor not ready. Use run_luau to run code directly.", false end
	local idx, idxErr = EX.editorIndex(args)
	if not idx then return idxErr, false end
	pcall(ExecAPI.show)
	local ok, out, success = pcall(ExecAPI.run, idx)
	if not ok then return "That tab doesn't exist. Call list_editor_tabs first, or create_editor_tab to make one.", false end
	out = tostring(out or "")
	if out == "" then out = "Ran with no printed output or return value." end
	return out, success ~= false
end

toolImpls.append_editor = function(args)
	if not ExecAPI then return "Executor not ready. Use create_editor_tab first.", false end
	local idx, idxErr = EX.editorIndex(args)
	if not idx then return idxErr, false end
	local add = tostring((args and args.code) or "")
	if add == "" then return "No code provided to append.", false end
	local okR, cur = pcall(ExecAPI.read, idx)
	if not okR then return "That tab doesn't exist. Use list_editor_tabs to find it, or create_editor_tab to make one.", false end
	cur = tostring(cur or "")
	local allowed, editErr = EX.editorEditAllowed(idx, cur)
	if not allowed then return editErr, false end
	local joined = cur == "" and add or (cur .. "\n" .. add)
	if not EX.editorWrite(idx, joined) then return "Couldn't append to that tab.", false end
	pcall(ExecAPI.show)
	local rOk, rIdx = pcall(ExecAPI.activeIndex, idx); if rOk and rIdx then editorReadState[rIdx] = joined end
	-- count lines so the agent knows how big it's gotten
	local lines = 1
	for _ in joined:gmatch("\n") do lines = lines + 1 end
	return "Appended " .. tostring(select(2, add:gsub("\n", "")) + 1) .. " lines. Tab is now " .. lines .. " lines. Keep appending the next chunk, or run_editor to test."
end

-- Edit tool — Claude Code semantics. Replaces an exact string in a tab.
-- Enforces: (1) read-before-edit (must read_editor first), (2) the tab hasn't
-- changed since that read, (3) old_string is unique (or replace_all), (4)
-- new_string differs from old_string. Returns a diff on success.
toolImpls.str_replace_editor = function(args)
	if not ExecAPI then return "Executor not ready. Create a tab first with create_editor_tab.", false end
	local idx, idxErr = EX.editorIndex(args)
	if not idx then return idxErr, false end
	local oldStr = tostring((args and (args.old_string or args.old_str)) or "")
	local newStr = tostring((args and (args.new_string or args.new_str)) or "")
	local replaceAll = args and (args.replace_all == true) or false
	if oldStr == "" then return "old_string is required — the exact text to replace. Call read_editor first so it matches the real text.", false end
	if oldStr == newStr then return "new_string must be different from old_string.", false end

	local rOk, rIdx = pcall(ExecAPI.activeIndex, idx)
	if not rOk or not rIdx then return "That tab doesn't exist. Use list_editor_tabs, or create_editor_tab to make one.", false end
	local okR, cur = pcall(ExecAPI.read, idx)
	if not okR then return "That tab doesn't exist. Use list_editor_tabs, or create_editor_tab.", false end
	cur = tostring(cur or "")

	-- read-before-edit: must have read this tab, and it must be unchanged since
	local seen = editorReadState[rIdx]
	if seen == nil then
		return "You must read_editor this tab before editing it, so your old_string matches the current text exactly.", false
	end
	if seen ~= cur then
		editorReadState[rIdx] = nil
		return "The tab changed since you last read it. Call read_editor again to get the current contents, then redo the edit against the new text.", false
	end

	-- count occurrences (plain text, not Lua patterns)
	local count, pos = 0, 1
	while true do
		local s = cur:find(oldStr, pos, true)
		if not s then break end
		count = count + 1
		pos = s + #oldStr
	end
	if count == 0 then
		return "old_string wasn't found in the tab. Whitespace and indentation must match exactly. Call read_editor and copy the text verbatim.", false
	end
	if count > 1 and not replaceAll then
		return "old_string appears " .. count .. " times — it must be unique. Either include more surrounding lines to pin down the one you mean, or pass replace_all: true to replace every occurrence.", false
	end

	local newCode
	if replaceAll then
		-- plain replace-all (build manually so special chars are literal)
		local parts, p = {}, 1
		while true do
			local s = cur:find(oldStr, p, true)
			if not s then parts[#parts + 1] = cur:sub(p); break end
			parts[#parts + 1] = cur:sub(p, s - 1) .. newStr
			p = s + #oldStr
		end
		newCode = table.concat(parts)
	else
		local s = cur:find(oldStr, 1, true)
		newCode = cur:sub(1, s - 1) .. newStr .. cur:sub(s + #oldStr)
	end

	if not EX.editorWrite(idx, newCode) then return "Couldn't write the edit to that tab.", false end
	pcall(ExecAPI.show)
	editorReadState[rIdx] = newCode  -- the agent's view is now the edited text
	local note = replaceAll and (count .. " occurrences replaced") or "replaced at one location"
	return "Edited the tab (" .. note .. ").\n" .. lineDiff(cur, newCode)
end

-- Replace a range of lines (1-indexed, inclusive). Same read-before-edit guard.
toolImpls.replace_lines_editor = function(args)
	if not ExecAPI then return "Executor not ready. Create a tab first.", false end
	local idx, idxErr = EX.editorIndex(args)
	if not idx then return idxErr, false end
	local a = args and tonumber(args.start_line)
	local b = args and tonumber(args.end_line)
	if not a then return "start_line is required (1-indexed).", false end
	b = b or a
	local newText = tostring((args and args.code) or "")
	local rOk, rIdx = pcall(ExecAPI.activeIndex, idx)
	if not rOk or not rIdx then return "That tab doesn't exist. Use list_editor_tabs or create_editor_tab.", false end
	local okR, cur = pcall(ExecAPI.read, idx)
	if not okR then return "That tab doesn't exist.", false end
	cur = tostring(cur or "")
	local seen = editorReadState[rIdx]
	if seen == nil then return "Read the tab first with read_editor before editing it by line.", false end
	if seen ~= cur then editorReadState[rIdx] = nil; return "The tab changed since you last read it. Call read_editor again, then redo the edit.", false end
	local lines = {}
	for line in (cur .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
	if a < 1 or a > #lines then return "start_line " .. a .. " is out of range (the tab has " .. #lines .. " lines). Read the tab first.", false end
	if a ~= math.floor(a) or b ~= math.floor(b) or b < a or b > #lines then return "Line range must use whole numbers with start_line <= end_line <= " .. #lines .. ".", false end
	local out = {}
	for i = 1, a - 1 do out[#out + 1] = lines[i] end
	if newText ~= "" then out[#out + 1] = newText end
	for i = b + 1, #lines do out[#out + 1] = lines[i] end
	local newCode = table.concat(out, "\n")
	if not EX.editorWrite(idx, newCode) then return "Couldn't write the edit.", false end
	pcall(ExecAPI.show)
	editorReadState[rIdx] = newCode
	return "Replaced lines " .. a .. "-" .. b .. ".\n" .. lineDiff(cur, newCode)
end

-- Insert new code at a line boundary without deleting or replacing any existing
-- source. Uses the same read-before-edit/stale-content guard as surgical edits.
toolImpls.inject_editor = function(args)
	if not ExecAPI then return "Executor not ready. Create a tab first.", false end
	local idx, idxErr = EX.editorIndex(args)
	if not idx then return idxErr, false end
	local at = args and tonumber(args.line)
	local code = tostring((args and args.code) or "")
	local position = tostring((args and args.position) or "before"):lower()
	if not at then return "line is required (1-indexed).", false end
	if code == "" then return "code is required and cannot be empty.", false end
	if position ~= "before" and position ~= "after" then return "position must be 'before' or 'after'.", false end
	local rOk, rIdx = pcall(ExecAPI.activeIndex, idx)
	if not rOk or not rIdx then return "That tab doesn't exist. Use list_editor_tabs or create_editor_tab.", false end
	local okR, cur = pcall(ExecAPI.read, idx)
	if not okR then return "That tab doesn't exist.", false end
	cur = tostring(cur or "")
	local seen = editorReadState[rIdx]
	if seen == nil then return "Read the target area with read_editor before injecting code.", false end
	if seen ~= cur then editorReadState[rIdx] = nil; return "The tab changed since you last read it. Call read_editor again, then retry the injection.", false end
	local lines = {}
	for line in (cur .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
	if at ~= math.floor(at) then return "line must be a whole number.", false end
	if at < 1 or at > #lines then return "line " .. at .. " is out of range (the tab has " .. #lines .. " lines).", false end
	local insertAt = position == "after" and (at + 1) or at
	local out = {}
	for i = 1, insertAt - 1 do out[#out + 1] = lines[i] end
	out[#out + 1] = code
	for i = insertAt, #lines do out[#out + 1] = lines[i] end
	local newCode = table.concat(out, "\n")
	if not EX.editorWrite(idx, newCode) then return "Couldn't inject code into that tab.", false end
	pcall(ExecAPI.show)
	editorReadState[rIdx] = newCode
	local added = select(2, code:gsub("\n", "")) + 1
	return "Injected " .. added .. " line(s) " .. position .. " line " .. at .. " without deleting existing code.\n" .. lineDiff(cur, newCode)
end

toolImpls.revert_script = function(args)
	local scr, err = resolveScript(args and args.path)
	if not scr then return err, false end
	local key = scr:GetFullName()
	local h = scriptHistory[scr]
	if not h or #h.snapshots == 0 then return "No snapshots to revert for " .. key .. ".", false end
	local prev = table.remove(h.snapshots)
	local okW, werr = pcall(function() scr.Source = prev end)
	if not okW then
		h.snapshots[#h.snapshots + 1] = prev
		return "Failed to revert .Source: " .. tostring(werr), false
	end
	return "Reverted " .. key .. " to previous snapshot (" .. #h.snapshots .. " remaining)."
end

-- ============================================================================
-- EXTENDED CAPABILITIES (added): structured scene "sight", remote spy/replay,
-- per-game persistent memory. All pcall-guarded, all degrade honestly, none
-- can throw into the agent loop. See inline failure-mode notes.
-- ============================================================================

-- Bounded, cycle-safe serializer for arbitrary Luau values (remote args, etc).
-- jsonEncode handles userdata-as-string already; this adds DEPTH + SIZE caps and
-- cycle marking so a 5MB buffer / deep table / self-referential table can never
-- blow up or loop. Returns a short human-readable string, not strict JSON.
function EX.describeValue(v, depth, seen)
	depth = depth or 0
	seen = seen or {}
	local t = typeof and typeof(v) or type(v)
	if v == nil then return "nil" end
	if t == "boolean" or t == "number" then return tostring(v) end
	if t == "string" then
		local s = v
		if #s > 120 then s = s:sub(1, 120) .. "…(" .. #s .. " chars)" end
		return string.format("%q", s)
	end
	if t == "Instance" then
		local ok, full = pcall(function() return v:GetFullName() end)
		return "<Instance " .. (ok and full or tostring(v)) .. " (" .. v.ClassName .. ")>"
	end
	if t == "Vector3" then return string.format("Vector3(%.2f,%.2f,%.2f)", v.X, v.Y, v.Z) end
	if t == "Vector2" then return string.format("Vector2(%.2f,%.2f)", v.X, v.Y) end
	if t == "CFrame" then local p = v.Position; return string.format("CFrame@(%.1f,%.1f,%.1f)", p.X, p.Y, p.Z) end
	if t == "Color3" then return string.format("Color3(%d,%d,%d)", v.R*255, v.G*255, v.B*255) end
	if t == "table" then
		if seen[v] then return "<cycle>" end
		if depth >= 4 then return "<table depth-capped>" end
		seen[v] = true
		local parts = {}
		local n = 0
		for k, val in pairs(v) do
			n = n + 1
			if n > 24 then parts[#parts+1] = "…(more)"; break end
			parts[#parts+1] = tostring(k) .. "=" .. EX.describeValue(val, depth + 1, seen)
		end
		seen[v] = nil
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	-- functions, threads, other userdata
	return "<" .. t .. ">"
end

function EX.describeArgs(...)
	local n = select("#", ...)
	if n == 0 then return "(no args)" end
	local parts = {}
	for i = 1, n do parts[#parts+1] = EX.describeValue((select(i, ...))) end
	local s = table.concat(parts, ", ")
	if #s > 1500 then s = s:sub(1, 1500) .. "…(truncated)" end
	return s
end

-- Same as EX.describeArgs but takes an already-packed { n=, [1]=,... } table, for
-- use inside nested closures where the original `...` is no longer in scope.
function EX.describeArgsList(packed)
	if type(packed) ~= "table" then return "(no args)" end
	local n = packed.n or #packed
	if n == 0 then return "(no args)" end
	local parts = {}
	for i = 1, n do parts[#parts+1] = EX.describeValue(packed[i]) end
	local s = table.concat(parts, ", ")
	if #s > 1500 then s = s:sub(1, 1500) .. "…(truncated)" end
	return s
end

-- ---------- scene_snapshot: structured visual model (NOT pixels) ----------
-- Roblox executors cannot read the 3D framebuffer, so "sight" here is geometry:
-- what is in front of the camera, what GUI text/buttons are on screen, and what
-- the center of the screen is pointing at. This exists regardless of lighting.
function EX.sceneSnapshot()
	local out = {}
	local cam = workspace.CurrentCamera
	local lp = Players.LocalPlayer
	local char = lp and lp.Character
	local camPos = cam and cam.CFrame.Position

	-- (1) center-screen raycast: "what am I looking at"
	if cam then
		local okR, hit = pcall(function()
			local origin = cam.CFrame.Position
			local dir = cam.CFrame.LookVector * 5000
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			if char then params.FilterDescendantsInstances = { char } end
			return workspace:Raycast(origin, dir, params)
		end)
		if okR and hit and hit.Instance then
			local d = camPos and (hit.Position - camPos).Magnitude or 0
			out[#out+1] = string.format("Looking at: %s (%s) at %.0f studs", hit.Instance:GetFullName(), hit.Instance.ClassName, d)
		else
			out[#out+1] = "Looking at: open sky / nothing within 5000 studs"
		end
	else
		out[#out+1] = "Camera not available yet (game still loading)."
	end

	-- (2) nearest parts, with on-screen flag + screen coords where projectable
	if cam and camPos then
		local cands = {}
		local scanned = 0
		local okScan = pcall(function()
			for _, inst in ipairs(workspace:GetDescendants()) do
				scanned = scanned + 1
				if scanned > 4000 then break end
				if inst:IsA("BasePart") and not (char and inst:IsDescendantOf(char)) then
					local d = (inst.Position - camPos).Magnitude
					if d < 600 then cands[#cands+1] = { inst = inst, d = d } end
				end
			end
		end)
		table.sort(cands, function(a, b) return a.d < b.d end)
		local lines = {}
		for i = 1, math.min(40, #cands) do
			local c = cands[i]
			local screen = ""
			local okP, vp, on = pcall(function()
				local v, o = cam:WorldToViewportPoint(c.inst.Position)
				return v, o
			end)
			if okP and vp and vp == vp then -- vp==vp guards NaN
				screen = on and string.format(" [on-screen x=%d y=%d]", math.floor(vp.X), math.floor(vp.Y)) or " [off-screen]"
			end
			local colr = ""
			local okC = pcall(function() colr = string.format(" color(%d,%d,%d)", c.inst.Color.R*255, c.inst.Color.G*255, c.inst.Color.B*255) end)
			lines[#lines+1] = string.format("  %s (%s) %.0f studs%s%s", c.inst.Name, c.inst.ClassName, c.d, screen, colr)
		end
		if #lines > 0 then
			out[#out+1] = "Nearby parts (nearest " .. #lines .. (okScan and "" or ", scan capped") .. "):\n" .. table.concat(lines, "\n")
		else
			out[#out+1] = "No BaseParts within 600 studs (open area, or geometry is in a Model with no BaseParts)."
		end
	end

	-- (3) on-screen GUI: TextLabels / TextButtons that are visible
	local guiRoots = {}
	pcall(function() if lp then local pg = lp:FindFirstChildOfClass("PlayerGui"); if pg then guiRoots[#guiRoots+1] = pg end end end)
	pcall(function() if gethui then guiRoots[#guiRoots+1] = gethui() end end)
	local guiLines = {}
	local totalGui, visGui = 0, 0
	for _, root in ipairs(guiRoots) do
		pcall(function()
			for _, g in ipairs(root:GetDescendants()) do
				if g:IsA("TextLabel") or g:IsA("TextButton") or g:IsA("TextBox") then
					totalGui = totalGui + 1
					local visible = true
					local okV = pcall(function()
						visible = g.Visible and (g.AbsoluteSize.X > 0) and (g.AbsoluteSize.Y > 0)
						-- climb ancestors for an Enabled ScreenGui / visible frames
						local p = g.Parent
						while p and p ~= root do
							if p:IsA("ScreenGui") and p.Enabled == false then visible = false break end
							if p:IsA("GuiObject") and p.Visible == false then visible = false break end
							p = p.Parent
						end
					end)
					if okV and visible then visGui = visGui + 1 end
					if okV and visible and #guiLines < 40 then
						local txt = tostring(g.Text or "")
						if #txt > 80 then txt = txt:sub(1, 80) .. "…" end
						local pos = g.AbsolutePosition
						local kind = g:IsA("TextButton") and "Button" or (g:IsA("TextBox") and "Input" or "Label")
						guiLines[#guiLines+1] = string.format("  [%s] \"%s\" @ screen(%d,%d)", kind, txt, math.floor(pos.X), math.floor(pos.Y))
					end
				end
			end
		end)
	end
	if totalGui == 0 then
		out[#out+1] = "GUI: no text elements found in PlayerGui."
	else
		out[#out+1] = string.format("GUI: %d text elements, %d visible on-screen%s:\n%s",
			totalGui, visGui, (#guiLines < visGui and " (showing first 40)" or ""),
			(#guiLines > 0 and table.concat(guiLines, "\n") or "  (none currently visible)"))
	end

	out[#out+1] = "(Note: this is a STRUCTURED scene model, not an image — no textures/pixels; part colors and GUI text are included above.)"
	return table.concat(out, "\n\n")
end

-- ---------- Remote spy / replay ----------
EX.remoteSpy = { installed = false, capturing = false, buffer = {}, inLog = false, max = 200, session = 0, ownerChatId = nil }

function EX.stopRemoteCapture(ownerChatId)
	local spy = EX.remoteSpy
	if not spy.capturing or (ownerChatId ~= nil and spy.ownerChatId ~= ownerChatId) then return false end
	spy.capturing = false
	spy.ownerChatId = nil
	return true
end

function EX.tryInstallRemoteHook()
	if EX.remoteSpy.installed then return true, "already" end
	-- need both a metamethod hook and the namecall reader
	local hookmm = hookmetamethod or (getgenv and getgenv().hookmetamethod)
	local getnc = getnamecallmethod or (getgenv and getgenv().getnamecallmethod)
	if type(hookmm) ~= "function" or type(getnc) ~= "function" then
		return false, "This executor lacks hookmetamethod/getnamecallmethod — live remote spying isn't available. find_instances can still locate RemoteEvents/RemoteFunctions statically."
	end
	local ok, err = pcall(function()
		local oldNamecall
		oldNamecall = hookmm(game, "__namecall", function(self, ...)
			-- pass-through wrapper; only LOG, never alter behavior
			if alive and EX.remoteSpy.capturing and not EX.remoteSpy.inLog then
				EX.remoteSpy.inLog = true
				local packed = table.pack(...)   -- capture varargs HERE (valid scope)
				pcall(function()
					local method = getnc()
					if method == "FireServer" or method == "InvokeServer" then
						if typeof(self) == "Instance" and (self:IsA("RemoteEvent") or self:IsA("RemoteFunction")) then
							if #EX.remoteSpy.buffer < EX.remoteSpy.max then
								EX.remoteSpy.buffer[#EX.remoteSpy.buffer+1] = {
									name = self:GetFullName(),
									cls = self.ClassName,
									method = method,
									args = EX.describeArgsList(packed),
									t = os.clock(),
								}
							end
						end
					end
				end)
				EX.remoteSpy.inLog = false
			end
			return oldNamecall(self, ...)
		end)
	end)
	if not ok then return false, "Failed to install remote hook: " .. tostring(err) end
	EX.remoteSpy.installed = true
	return true, "installed"
end

function EX.listRemotesStatic()
	local found = {}
	local function recurse(inst, depth)
		if depth > 8 or #found >= 60 then return end
		for _, c in ipairs(inst:GetChildren()) do
			if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
				found[#found+1] = c:GetFullName() .. " (" .. c.ClassName .. ")"
			end
			recurse(c, depth + 1)
		end
	end
	pcall(recurse, game, 0)
	if #found == 0 then return "No RemoteEvents/RemoteFunctions found." end
	return "Remotes in game (" .. #found .. "):\n" .. table.concat(found, "\n")
end

function EX.resolveRemote(pathOrName)
	if type(pathOrName) ~= "string" or pathOrName == "" then return nil, "Provide a remote path or name." end
	pathOrName = pathOrName:gsub("^game%.", "")
	local exact, byName = nil, {}
	local function recurse(inst, depth)
		if depth > 10 or exact then return end
		for _, c in ipairs(inst:GetChildren()) do
			if c:IsA("RemoteEvent") or c:IsA("RemoteFunction") then
				if c:GetFullName() == pathOrName then exact = c; return end
				if c.Name == pathOrName then byName[#byName+1] = c end
			end
			recurse(c, depth + 1)
		end
	end
	pcall(recurse, game, 0)
	if exact then return exact end
	if #byName == 1 then return byName[1] end
	if #byName > 1 then
		local p = {}
		for _, c in ipairs(byName) do p[#p+1] = c:GetFullName() end
		return nil, "Ambiguous remote '" .. pathOrName .. "'. Matches:\n" .. table.concat(p, "\n")
	end
	return nil, "No RemoteEvent/RemoteFunction named or pathed '" .. pathOrName .. "'."
end

-- ---------- Per-game persistent memory ----------
EX.GAME_MEM_PATH = SAVE_FOLDER .. "/game_memory.json"
EX.gameMemory = nil          -- { [placeIdStr] = { {text=, t=}, ... } }
EX.gameMemoryDirty = false

function EX.placeKey() return tostring(game.PlaceId or 0) end

function EX.loadGameMemory()
	if EX.gameMemory ~= nil then return end
	EX.gameMemory = {}
	if not hasFS then return end
	local okE, exists = pcall(isfile, EX.GAME_MEM_PATH)
	if not okE or not exists then return end
	local rok, raw = pcall(readfile, EX.GAME_MEM_PATH)
	if not rok or type(raw) ~= "string" then return end
	local dok, decoded = pcall(function() return AT.http:JSONDecode(raw) end)
	if dok and type(decoded) == "table" then
		EX.gameMemory = decoded
	else
		-- corrupt: quarantine, start fresh (never crash)
		pcall(function() if type(writefile) == "function" then writefile(EX.GAME_MEM_PATH .. ".bad", raw) end end)
		EX.gameMemory = {}
	end
end

function EX.saveGameMemory()
	EX.gameMemoryDirty = true
	if not hasFS then return false, "filesystem unavailable" end
	local ok, err = pcall(function()
		if not (isfolder and isfolder(SAVE_FOLDER)) and makefolder then makefolder(SAVE_FOLDER) end
		writefile(EX.GAME_MEM_PATH, AT.http:JSONEncode(EX.gameMemory))
	end)
	EX.gameMemoryDirty = not ok
	return ok, err
end

function EX.memorySavedMessage(message)
	local ok, err = EX.saveGameMemory()
	if not ok then return message .. " In memory for this session only; persistence failed: " .. tostring(err), false end
	return message
end

EX.MEM_MAX_FACTS = 60
EX.MEM_FACT_CHARS = 280

-- Accept basically any arg shape the model throws at remember(...).
function EX.coerceFactText(args)
	if type(args) == "string" then return args end
	if type(args) ~= "table" then return nil end
	-- {key, value} pair
	if type(args.key) == "string" and args.value ~= nil then
		return tostring(args.key) .. ": " .. tostring(args.value)
	end
	local cand = args.text or args.fact or args.note or args.content or args.value or args.memory or args.info
	if type(cand) == "string" then return cand end
	-- positional-ish: first string value in the table
	for _, v in pairs(args) do if type(v) == "string" and v ~= "" then return v end end
	return nil
end

function EX.memRemember(args)
	EX.loadGameMemory()
	local text = EX.coerceFactText(args)
	if not text or text:gsub("%s+", "") == "" then
		return "Nothing to remember — pass the fact as text, e.g. remember a note about this game's money remote.", false
	end
	text = tostring(text)
	if #text > EX.MEM_FACT_CHARS then text = text:sub(1, EX.MEM_FACT_CHARS) .. "…" end
	local key = EX.placeKey()
	local list = EX.gameMemory[key]
	if type(list) ~= "table" then list = {}; EX.gameMemory[key] = list end
	-- dedupe exact
	for _, f in ipairs(list) do
		if type(f) == "table" and f.text == text then
			if EX.gameMemoryDirty then return EX.memorySavedMessage("Remembered that note for this game.") end
			return "Already remembered that for this game."
		end
	end
	list[#list+1] = { text = text, t = os.time() }
	-- FIFO cap
	while #list > EX.MEM_MAX_FACTS do table.remove(list, 1) end
	return EX.memorySavedMessage("Remembered (" .. #list .. " note" .. (#list == 1 and "" or "s") .. " for this game).")
end

function EX.memRecall(args)
	EX.loadGameMemory()
	local key = EX.placeKey()
	local list = EX.gameMemory[key]
	if type(list) ~= "table" or #list == 0 then
		return "No notes saved for this game (PlaceId " .. key .. ") yet."
	end
	local query = nil
	if type(args) == "table" then query = args.query or args.search or args.q end
	local all = {}
	for i, f in ipairs(list) do
		if type(f) == "table" and type(f.text) == "string" then all[#all+1] = i .. ". " .. f.text end
	end
	local result = "Notes for this game (" .. #all .. "):\n" .. table.concat(all, "\n")
	if type(query) == "string" and query ~= "" then
		local ql = query:lower()
		local hits = {}
		for i, f in ipairs(list) do
			if type(f) == "table" and type(f.text) == "string" and f.text:lower():find(ql, 1, true) then
				hits[#hits+1] = i .. ". " .. f.text
			end
		end
		result = result .. "\n\nMatching \"" .. query .. "\":\n" .. (#hits > 0 and table.concat(hits, "\n") or "(none)")
	end
	return result
end

function EX.memForget(args)
	EX.loadGameMemory()
	local key = EX.placeKey()
	local list = EX.gameMemory[key]
	if type(list) ~= "table" or #list == 0 then return "Nothing saved for this game to forget." end
	local target
	if type(args) == "table" then target = args.index or args.which or args.text or args.query end
	if type(args) == "string" then target = args end
	if target == nil then return "Specify what to forget: an index number, a substring, or \"all\".", false end
	if tostring(target):lower() == "all" then
		EX.gameMemory[key] = {}
		return EX.memorySavedMessage("Forgot all notes for this game.")
	end
	local idx = tonumber(target)
	if idx and idx == math.floor(idx) and list[idx] then
		local removed = type(list[idx]) == "table" and list[idx].text or "invalid note"
		table.remove(list, idx)
		return EX.memorySavedMessage("Forgot: " .. tostring(removed))
	end
	-- substring
	local ql = tostring(target):lower()
	if ql:gsub("%s+", "") == "" then return "Provide a nonempty note index or substring to forget.", false end
	for i = #list, 1, -1 do
		if type(list[i]) == "table" and type(list[i].text) == "string" and list[i].text:lower():find(ql, 1, true) then
			local removed = list[i].text
			table.remove(list, i)
			return EX.memorySavedMessage("Forgot: " .. tostring(removed))
		end
	end
	return "No note matched '" .. tostring(target) .. "'. Use recall to see indices.", false
end

-- Text block of this game's memory for injection into gatherContext (~2KB cap).
-- (Assigns the forward-declared local from near gatherContext — do NOT add `local`.)
EX.gameMemoryContext = function()
	EX.loadGameMemory()
	local list = EX.gameMemory[EX.placeKey()]
	if type(list) ~= "table" or #list == 0 then return nil end
	local lines, total = {}, 0
	for i = #list, 1, -1 do  -- most recent first
		local f = list[i]
		if type(f) == "table" and type(f.text) == "string" then
			local line = "- " .. f.text
			total = total + #line
			if total > 2000 then lines[#lines+1] = "- …(older notes omitted)"; break end
			lines[#lines+1] = line
		end
	end
	if #lines == 0 then return nil end
	return "Your saved notes about THIS game (PlaceId " .. EX.placeKey() .. ", from past sessions — use recall/remember/forget to manage):\n" .. table.concat(lines, "\n")
end


-- ---------- tool implementations ----------
toolImpls.scene_snapshot = function()
	local ok, res = pcall(EX.sceneSnapshot)
	if not ok then return "Couldn't build a scene snapshot on this executor: " .. tostring(res), false end
	return res
end

toolImpls.spy_remotes = function(args)
	if EX.remoteSpy.capturing then return "A remote capture is already running. Wait for it to finish before starting another.", false end
	local secs = tonumber(args and args.seconds) or 6
	if secs < 1 then secs = 1 elseif secs > 20 then secs = 20 end
	local ok, msg = EX.tryInstallRemoteHook()
	if not ok then
		-- degrade to static discovery so the tool is still useful
		return msg .. "\n\n" .. EX.listRemotesStatic()
	end
	local buf = {}
	EX.remoteSpy.buffer = buf
	EX.remoteSpy.session = EX.remoteSpy.session + 1
	local session = EX.remoteSpy.session
	local owner = EX.threadChat and EX.threadChat[coroutine.running()]
	EX.remoteSpy.ownerChatId = owner
	EX.remoteSpy.capturing = true
	local started = nowClock()
	-- A separate expiry closes the hook even if the caller coroutine is cancelled.
	task.spawn(function()
		task.wait(secs)
		if EX.remoteSpy.session == session then EX.stopRemoteCapture() end
	end)
	while alive and EX.remoteSpy.capturing and EX.remoteSpy.session == session and nowClock() - started < secs do
		task.wait(0.1)
	end
	local elapsed = math.min(secs, math.max(0, nowClock() - started))
	local complete = elapsed >= secs
	if EX.remoteSpy.session == session then
		EX.stopRemoteCapture()
		EX.remoteSpy.buffer = {}
	end
	local duration = string.format("%.1f", elapsed)
	local stopped = complete and "" or "Capture stopped early. "
	if #buf == 0 then
		return stopped .. "0 remotes fired in " .. duration .. "s. The game may only fire them on specific actions — perform the action (move, click, buy, etc.) right before/while spying. Known remotes:\n" .. EX.listRemotesStatic(), complete
	end
	local lines = {}
	for i, e in ipairs(buf) do
		lines[#lines+1] = string.format("%d. %s:%s(%s)  [%s]", i, e.name, e.method, e.args, e.cls)
		if i >= 80 then lines[#lines+1] = "…(" .. (#buf - 80) .. " more)"; break end
	end
	return stopped .. "Captured " .. #buf .. " remote call(s) in " .. duration .. "s:\n" .. table.concat(lines, "\n") ..
		"\n\nUse replay_remote with a path above to fire one yourself (e.g. to repeat a 'collect reward' call).", complete
end

toolImpls.replay_remote = function(args)
	local remote, err = EX.resolveRemote(args and (args.path or args.name))
	if not remote then return err, false end
	-- decode args: accept an array under args.args, or fire with none
	local fireArgs = {}
	if args and type(args.args) == "table" then fireArgs = args.args
	elseif args and args.args ~= nil then fireArgs = { args.args } end
	local isFn = remote:IsA("RemoteFunction")
	if isFn then
		-- InvokeServer yields; run with a timeout so a non-responding server can't hang us
		local done, result, rerr = false, nil, nil
		task.spawn(function()
			local ok, r = pcall(function() return remote:InvokeServer(table.unpack(fireArgs)) end)
			if ok then result = r else rerr = r end
			done = true
		end)
		local waited = 0
		while not done and waited < 8 do task.wait(0.1); waited = waited + 0.1 end
		if not done then return "Invoked " .. remote:GetFullName() .. " (RemoteFunction) but the server hasn't responded in 8s; it was left pending." end
		if rerr then return "InvokeServer errored: " .. tostring(rerr), false end
		return "Invoked " .. remote:GetFullName() .. " → returned: " .. EX.describeValue(result)
	else
		local ok, ferr = pcall(function() remote:FireServer(table.unpack(fireArgs)) end)
		if not ok then return "FireServer errored: " .. tostring(ferr), false end
		return "Fired " .. remote:GetFullName() .. " (RemoteEvent) with " .. EX.describeArgs(table.unpack(fireArgs)) ..
			".\nNote: the server may accept or ignore it — I can't verify server-side acceptance from the client."
	end
end

toolImpls.list_remotes = function()
	return EX.listRemotesStatic()
end

toolImpls.remember = function(args) return EX.memRemember(args) end
toolImpls.recall = function(args) return EX.memRecall(args) end
toolImpls.forget = function(args) return EX.memForget(args) end

AGENT_TOOLS = {
	{ type = "function", ["function"] = {
		name = "scene_snapshot",
		description = "Get a STRUCTURED visual model of what is on screen right now (this is not an image — Roblox executors cannot capture pixels). Returns: what the centre of the screen is pointing at (raycast), the nearest parts in front of the camera with distances / on-screen coordinates / colours, and the on-screen GUI text and buttons with their screen positions. Use this to 'see' the scene so you can locate buttons to click, read on-screen text, or understand the spatial layout before acting. It works regardless of lighting (it reads geometry, not brightness).",
		parameters = { type = "object", properties = {} },
	}},
	{ type = "function", ["function"] = {
		name = "spy_remotes",
		description = "Watch the game's outgoing network traffic for a few seconds and report every RemoteEvent/RemoteFunction the client fires, with the arguments passed. This is the best way to understand how a game works (its money/reward/ability remotes) when you cannot read its server scripts. Tell the user to perform the relevant action (collect, buy, attack, etc.) while you spy so the call is captured. If this executor can't hook traffic, it falls back to listing the remotes that exist. After spying, use replay_remote to fire one yourself.",
		parameters = { type = "object", properties = {
			seconds = { type = "number", description = "How long to capture, 1-20 (default 6)." },
		} },
	}},
	{ type = "function", ["function"] = {
		name = "replay_remote",
		description = "Fire a specific RemoteEvent (FireServer) or RemoteFunction (InvokeServer) yourself, with given arguments — e.g. to repeat a 'collect reward' call you saw via spy_remotes. This can be bannable in competitive games (it's how currency/item exploits work), so treat it as risky: call warn_exploit first if the request is about gaining an unfair advantage. The server may accept or silently ignore the call; client-side I can't verify server acceptance.",
		parameters = { type = "object", properties = {
			path = { type = "string", description = "Full path (game.X.Y) or unique name of the remote, from spy_remotes or list_remotes." },
			args = { type = "array", description = "Array of arguments to pass to the remote, in order. Omit for no arguments.", items = {} },
		}, required = { "path" } },
	}},
	{ type = "function", ["function"] = {
		name = "list_remotes",
		description = "List every RemoteEvent and RemoteFunction in the game with full paths (static discovery, no hooking). Use to find a remote to replay_remote, or when spy_remotes can't hook on this executor.",
		parameters = { type = "object", properties = {} },
	}},
	{ type = "function", ["function"] = {
		name = "remember",
		description = "Save a short note about THIS game so you still know it in future sessions (notes are stored per-game by PlaceId and auto-shown to you next time). Use it for durable facts you discover — e.g. 'the money value is at game.Players.LocalPlayer.leaderstats.Cash', 'the kill-brick is the red part named Trap', 'fire ReplicatedStorage.Buy with the item name to purchase'. Pass the note as text.",
		parameters = { type = "object", properties = {
			text = { type = "string", description = "The note to remember (a concise fact about this game)." },
		}, required = { "text" } },
	}},
	{ type = "function", ["function"] = {
		name = "recall",
		description = "Show the notes you've saved about this game in past sessions. Optionally pass a query to filter to matching notes. (Your saved notes are also injected into your context automatically each turn, so you usually already see them.)",
		parameters = { type = "object", properties = {
			query = { type = "string", description = "Optional substring to search your notes for." },
		} },
	}},
	{ type = "function", ["function"] = {
		name = "forget",
		description = "Remove a saved note about this game. Pass an index number (from recall), a substring to match, or \"all\" to clear every note for this game.",
		parameters = { type = "object", properties = {
			index = { type = "string", description = "An index number from recall, a substring to match, or \"all\"." },
		} },
	}},
	{ type = "function", ["function"] = {
		name = "run_luau",
		description = "Execute Luau code in the Roblox game right now and return its output (prints, warnings, return value, or errors). Use this for anything not covered by a more specific tool. Runs in the player's client with full executor access. Foreground runs have a timeout (default 10s) and attempt cancellation if they exceed it; any process that cannot be stopped remains listed by id — ALWAYS put task.wait() inside any loop so it can be interrupted. For long-running or continuous scripts (loops, watchers), set background=true: it returns a process id immediately and keeps running; manage it with list_processes/get_process_output/kill_process.",
		parameters = { type = "object", properties = {
			code = { type = "string", description = "The Luau source to run. Use print(...) or return a value to surface results." },
			title = { type = "string", description = "REQUIRED. A specific 3-6 word description of what THIS code actually does, in plain English for a non-coder. Describe the concrete action and target — e.g. 'Reading player money value', 'Spawning anchored part at origin', 'Listing all RemoteEvents in ReplicatedStorage', 'Setting walkspeed to 50'. Do NOT write generic text like 'Running Luau', 'Executing code', or 'Running script' — those are forbidden." },
			background = { type = "boolean", description = "If true, run without blocking and return a process id. Use for long/continuous scripts." },
			timeout = { type = "number", description = "Foreground timeout in seconds, greater than 0 and at most 120 (default 10). Ignored for background." },
		}, required = { "code", "title" } },
	}},
	{ type = "function", ["function"] = {
		name = "list_processes",
		description = "List background scripts and their status (running/done/killed/error), age, and a code preview.",
		parameters = { type = "object", properties = {} },
	}},
	{ type = "function", ["function"] = {
		name = "get_process_output",
		description = "Get the captured output of a background process by id.",
		parameters = { type = "object", properties = { pid = { type = "number" } }, required = { "pid" } },
	}},
	{ type = "function", ["function"] = {
		name = "kill_process",
		description = "Stop a running background process by id.",
		parameters = { type = "object", properties = { pid = { type = "number" } }, required = { "pid" } },
	}},
	{ type = "function", ["function"] = {
		name = "kill_all_processes",
		description = "Stop all running background processes.",
		parameters = { type = "object", properties = {} },
	}},
	{ type = "function", ["function"] = {
		name = "get_game_info",
		description = "Get the current PlaceId, GameId, server JobId, the local player's name/userid, character position and health, and the top-level workspace children. Call this first to orient yourself.",
		parameters = { type = "object", properties = {} },
	}},
	{ type = "function", ["function"] = {
		name = "get_player_info",
		description = "Get info (name, display name, userid, position) about a player. Defaults to the local player if no username is given.",
		parameters = { type = "object", properties = {
			username = { type = "string", description = "Username of the player. Omit for yourself." },
		} },
	}},
	{ type = "function", ["function"] = {
		name = "list_players",
		description = "List all players currently in the server.",
		parameters = { type = "object", properties = {} },
	}},
	{ type = "function", ["function"] = {
		name = "find_instances",
		description = "Search the game for instances whose name contains a string. Returns their full path, class, and position (for parts/models). Use this to locate things like 'blue room', a spawn, a button, etc.",
		parameters = { type = "object", properties = {
			name = { type = "string", description = "Partial or full name to search for." },
			service = { type = "string", description = "Optional service to search within (e.g. 'Workspace', 'ReplicatedStorage'). Defaults to Workspace." },
		}, required = { "name" } },
	}},
	{ type = "function", ["function"] = {
		name = "teleport",
		description = "Teleport the local player's character to either explicit coordinates or to a named part/model in the workspace.",
		parameters = { type = "object", properties = {
			x = { type = "number" }, y = { type = "number" }, z = { type = "number" },
			target_name = { type = "string", description = "Name of a part/model to teleport to (alternative to x/y/z)." },
		} },
	}},
	{ type = "function", ["function"] = {
		name = "write_file",
		description = "Save a script or text file into the workspace (the persistent file tree shown in the Workspace tab). Use forward slashes for subfolders, e.g. 'utils/math.lua' — intermediate folders are created automatically.",
		parameters = { type = "object", properties = {
			filename = { type = "string" }, content = { type = "string" },
		}, required = { "filename", "content" } },
	}},
	{ type = "function", ["function"] = {
		name = "make_folder",
		description = "Create a folder (and any parent folders) in the workspace. e.g. path 'projects/aim' makes both folders.",
		parameters = { type = "object", properties = { path = { type = "string" } }, required = { "path" } },
	}},
	{ type = "function", ["function"] = {
		name = "read_file",
		description = "Read a file from the workspace. Use the full path including subfolders, e.g. 'utils/math.lua'.",
		parameters = { type = "object", properties = { filename = { type = "string" } }, required = { "filename" } },
	}},
	{ type = "function", ["function"] = {
		name = "list_files",
		description = "List the files and folders at the workspace root (non-recursive).",
		parameters = { type = "object", properties = {} },
	}},
	{ type = "function", ["function"] = {
		name = "delete_file",
		description = "Delete a file from the workspace. Use its workspace-relative path.",
		parameters = { type = "object", properties = { filename = { type = "string" } }, required = { "filename" } },
	}},
	{ type = "function", ["function"] = {
		name = "http_get",
		description = "Fetch a URL with a GET request and return the (truncated) body. Read-only; for pulling docs or data.",
		parameters = { type = "object", properties = { url = { type = "string" } }, required = { "url" } },
	}},
	{ type = "function", ["function"] = {
		name = "list_scripts",
		description = "List every Script/LocalScript/ModuleScript in the game as a codebase, with full paths and class. Use this to understand the project's code before editing.",
		parameters = { type = "object", properties = {
			service = { type = "string", description = "Optional service to limit the search (e.g. 'ReplicatedStorage', 'StarterPlayer'). Defaults to the whole game." },
		} },
	}},
	{ type = "function", ["function"] = {
		name = "read_script",
		description = "Read source lines from a script by full path or unique name. Results are paged; if more source exists, call again using the next start_line shown in the result.",
		parameters = { type = "object", properties = {
			path = { type = "string", description = "Full path (game.X.Y) or unique script name." },
			start_line = { type = "number", description = "First source line to return (default 1)." },
			end_line = { type = "number", description = "Last source line to return (default start_line + 199)." },
		}, required = { "path" } },
	}},
	{ type = "function", ["function"] = {
		name = "edit_script",
		description = "Replace the entire source of a script with new_source. Returns a line diff of what changed and snapshots the old source so it can be reverted. Read the script first so you supply complete, correct source.",
		parameters = { type = "object", properties = {
			path = { type = "string", description = "Full path or unique name of the script to edit." },
			new_source = { type = "string", description = "The complete new .Source for the script." },
		}, required = { "path", "new_source" } },
	}},
	{ type = "function", ["function"] = {
		name = "revert_script",
		description = "Undo the last edit_script on a script, restoring its previous source snapshot.",
		parameters = { type = "object", properties = {
			path = { type = "string", description = "Full path or unique name of the script to revert." },
		}, required = { "path" } },
	}},
	{ type = "function", ["function"] = {
		name = "spawn_subagent",
		description = "Spawn an independent subagent to work on a focused subtask in parallel (fan-out). It runs its own short agent loop with the same tools and returns a subagent id. Use this to split big jobs (e.g. 'audit each of these 5 scripts') into parallel pieces, then collect results with get_subagent_result. Subagents run unattended, so they only auto-run tools your permission mode allows.",
		parameters = { type = "object", properties = {
			task = { type = "string", description = "A clear, self-contained instruction for the subagent." },
		}, required = { "task" } },
	}},
	{ type = "function", ["function"] = {
		name = "get_subagent_result",
		description = "Get the result of a subagent by id (once it's finished).",
		parameters = { type = "object", properties = { sid = { type = "number" } }, required = { "sid" } },
	}},
	{ type = "function", ["function"] = {
		name = "list_subagents",
		description = "List spawned subagents and their status.",
		parameters = { type = "object", properties = {} },
	}},
	{ type = "function", ["function"] = {
		name = "warn_exploit",
		description = "Show the exploit-risk warning to the user when you detect that their request could get their Roblox account banned (speed hacks, aimbots, currency manipulation, god mode, noclip, auto-farming, etc. — including slang like 'drop me a bag script', 'give me inf health', 'make me fly'). Call this BEFORE executing the risky code. The warning lets them confirm or leave to use an alt. If they confirm, proceed with their request — it's their choice. Do NOT refuse or moralize after they confirm.",
		parameters = { type = "object", properties = {
			reason = { type = "string", description = "Brief reason why this is risky, shown internally (not to the user)." },
		} },
	}},
	{ type = "function", ["function"] = {
		name = "list_editor_tabs",
		description = "List the script tabs open in the standalone Executor window (index, name, which is active). Use this to see what scripts the user has open so you can collaborate on them.",
		parameters = { type = "object", properties = {} },
	}},
	{ type = "function", ["function"] = {
		name = "read_editor",
		description = "Read a page of code from an Executor tab. If more code exists, call again using the next start_line shown in the result. Omit tab for the active tab.",
		parameters = { type = "object", properties = {
			tab = { type = "number", description = "Tab index (from list_editor_tabs). Omit for the active tab." },
			start_line = { type = "number", description = "First line to return (default 1)." },
			end_line = { type = "number", description = "Last line to return (default start_line + 249)." },
		} },
	}},
	{ type = "function", ["function"] = {
		name = "write_editor",
		description = "Replace the code in an Executor tab with new code (collaborative editing — the user sees the change in their editor and a diff). Read the tab first, then write the full updated source. Returns a diff of what changed. Omit 'tab' to write the active tab.",
		parameters = { type = "object", properties = {
			tab = { type = "number", description = "Tab index. Omit for the active tab." },
			code = { type = "string", description = "The FULL new source for the tab (not a fragment)." },
		}, required = { "code" } },
	}},
	{ type = "function", ["function"] = {
		name = "create_editor_tab",
		description = "Open a new tab in the Executor with optional name and starting code. Use when you want to give the user a fresh script rather than overwriting one they're working on.",
		parameters = { type = "object", properties = {
			name = { type = "string", description = "Optional tab name." },
			code = { type = "string", description = "Optional starting code." },
		} },
	}},
	{ type = "function", ["function"] = {
		name = "run_editor",
		description = "Execute the code currently in an Executor tab and return its output (prints, return value, errors). Use this to test a script you and the user are working on. Omit 'tab' for the active tab.",
		parameters = { type = "object", properties = {
			tab = { type = "number", description = "Tab index. Omit for the active tab." },
		} },
	}},
	{ type = "function", ["function"] = {
		name = "append_editor",
		description = "Append code to the END of an Executor tab. For long scripts, use small complete chunks of roughly 80-120 lines per call and repeat until finished; never send the whole long script in one call. Omit tab for the active tab.",
		parameters = { type = "object", properties = {
			tab = { type = "number", description = "Tab index. Omit for the active tab." },
			code = { type = "string", description = "The next chunk of code to add to the end of the tab." },
		}, required = { "code" } },
	}},
	{ type = "function", ["function"] = {
		name = "str_replace_editor",
		description = "Edit a tab by exact string replacement (like Claude Code's Edit tool). You MUST call read_editor on the tab first — edits are rejected if you haven't read it, or if it changed since you read it. old_string must match the current text EXACTLY (including whitespace and indentation) and appear exactly once; include surrounding lines to make it unique, or set replace_all to change every occurrence. This is the primary way to modify existing code without rewriting it.",
		parameters = { type = "object", properties = {
			tab = { type = "number", description = "Tab index. Omit for the active tab." },
			old_string = { type = "string", description = "The exact existing text to replace." },
			new_string = { type = "string", description = "The replacement text (must differ from old_string)." },
			replace_all = { type = "boolean", description = "Replace every occurrence instead of requiring uniqueness. Default false." },
		}, required = { "old_string", "new_string" } },
	}},
	{ type = "function", ["function"] = {
		name = "replace_lines_editor",
		description = "Replace a range of lines (1-indexed, inclusive) in a tab with new text. read_editor shows line numbers — use them. Good for swapping out a known block. Set code to empty to delete the lines.",
		parameters = { type = "object", properties = {
			tab = { type = "number", description = "Tab index. Omit for the active tab." },
			start_line = { type = "number", description = "First line to replace (1-indexed)." },
			end_line = { type = "number", description = "Last line to replace (inclusive). Omit to replace just start_line." },
			code = { type = "string", description = "The new text for those lines. Empty deletes them." },
		}, required = { "start_line", "code" } },
	}},
	{ type = "function", ["function"] = {
		name = "inject_editor",
		description = "Insert new code before or after one existing line without deleting or replacing any surrounding lines. You MUST call read_editor on the target area first. Prefer this over replace_lines_editor when adding a new function, declaration, handler, or block between existing code.",
		parameters = { type = "object", properties = {
			tab = { type = "number", description = "Tab index. Omit for the active tab." },
			line = { type = "number", description = "Existing 1-indexed anchor line." },
			position = { type = "string", enum = { "before", "after" }, description = "Insert before or after the anchor line. Default before." },
			code = { type = "string", description = "New code to insert. Existing code is preserved." },
		}, required = { "line", "code" } },
	}},
}

local function ollamaAgentStep(messages, isCancelled)
	if curKey() == "" and not curProvider().isCustom then return false, "No API key set for " .. curProvider().name .. ". Add one in Settings." end

	local sysParts = {}
	if ollamaSystemPrompt ~= "" then sysParts[#sysParts+1] = ollamaSystemPrompt end
	sysParts[#sysParts+1] = [[You are BloxAgent, an AI assistant embedded in a running Roblox game via an executor. You can act on the game using the provided tools. Prefer the specific tools (get_game_info, find_instances, teleport, etc.); use run_luau for anything else. When the user asks you to do something in-game, actually do it via tools, then briefly confirm. Every run_luau call MUST include the title argument with a specific plain-English description of what that exact code does (for example Reading player money value, or Spawning part at spawn point) which is shown to the user as the step label. Never use generic titles like Running Luau or Executing code; describe the concrete action.

IMPORTANT for run_luau: foreground scripts time out after 10s and any loop MUST contain task.wait() or it cannot be cancelled and will hang. NEVER use WaitForChild without a timeout: a call like obj:WaitForChild(name) blocks FOREVER if that child never appears and will hang the whole tool. Use obj:FindFirstChild(name) and handle the nil case, or obj:WaitForChild(name, 5) with a timeout and then check for nil. The same applies to any yielding call that can block indefinitely. print and warn output is captured in the tool result and also forwarded to the game console. Return values are reported as return: ... . For continuous or long-running scripts, pass background=true to get a process id back, then manage it with list_processes/get_process_output/kill_process.

The game code is only partly inspectable: use list_scripts to see all Script/LocalScript/ModuleScript files. read_script can read LocalScripts and ModuleScripts only if this executor has a working decompiler; server Scripts CANNOT be read from the client at all, and some executors (including Solara) block or limit decompilation, so read_script may return nothing. edit_script writes a script source, but most executors do NOT allow modifying existing game scripts at runtime, so treat edit_script as best-effort and prefer run_luau to change game state (set properties, call remotes, spawn instances) rather than rewriting script source. Do not claim you edited a script unless edit_script returned success. For large jobs you can split work across parallel subagents with spawn_subagent, then collect with get_subagent_result.

YOU WORK WITH THREE SEPARATE PLACES — do not confuse them:
1. THE LIVE GAME — the running Roblox session. Act on it with run_luau (execute code now), find_instances, teleport, get_game_info, get/list players. Use this for anything that changes or reads the game state right now.
2. THE EXECUTOR EDITOR — a code window with tabs that the user can see and edit alongside you. This is where you and the user collaborate on a script: write it, run it, see the result, fix it, repeat. Tools: list_editor_tabs (see open tabs), read_editor (read a tab), write_editor (replace a tab's full code — the user sees your change and a diff), create_editor_tab (open a new tab with code), append_editor (add more code to the end of a tab), run_editor (execute a tab and get its output back). USE THESE when the user is iterating on a script with you, or asks you to build/edit something they can run themselves. To build a script for the user: create_editor_tab (or write_editor an existing tab) with the FULL code, then run_editor to test it, then read the output and fix with write_editor if needed.

CRITICAL FOR LONG SCRIPTS: a single tool call cannot exceed the output token limit. Build long scripts in small, syntactically coherent chunks: create_editor_tab with only the first 80-120 lines, then append_editor with another 80-120 lines per call until complete. Never place hundreds of lines in one tool call. After every append, continue from the exact next line without repeating or skipping code, then run_editor to test only after all chunks are written.

TO EDIT an existing script (any length): you do NOT rewrite the whole thing. First read_editor (it shows numbered lines). To ADD code without deleting anything, use inject_editor before/after an anchor line. To change existing code, use str_replace_editor for an exact unique piece of text or replace_lines_editor for a known range. Prefer inject_editor whenever the request is to insert a new function, declaration, event handler, or block. You can change ANY part — top, middle, end — as long as you read it first. Never claim you edited something unless the edit tool returned a diff.
3. THE WORKSPACE — your persistent files on disk (shown in the Workspace tab and listed in the context above). Tools: write_file (save a file, use subfolders like 'utils/aim.lua'), read_file, list_files, make_folder, delete_file. Use this to save scripts for reuse across sessions. Files here persist; editor tabs do too, but the workspace is your organized library.

Picking the right tool: "run this / do X in the game now" → run_luau. "make me a script I can run / edit / tweak" → editor tools (create_editor_tab + run_editor). "save this for later / organize my scripts" → workspace (write_file). If a tool returns an error, read it and adapt when a supported alternative exists. Report unavailable executor or filesystem capabilities accurately, and never claim an action succeeded unless its tool result confirms success. Execution guards are best effort: synchronous code without yields cannot be interrupted, and full executor access is not an isolation boundary.

EXPLOIT SAFETY: If the user asks for something that could get their Roblox account banned (speed hacks, fly, noclip, god mode, aimbots, ESP, auto-farming, currency manipulation, item duplication, crashing other players, etc.), call warn_exploit BEFORE writing or executing any code. This includes slang such as drop me a bag script, give me inf cash, make me fly, aimbot, noclip through walls. It ALSO includes using replay_remote to gain an unfair advantage (firing a reward/currency/buy remote to dupe or farm) — call warn_exploit first in that case too. The warning shows them the risk and lets them confirm or leave to use an alt.

SEEING, INSPECTING, AND REMEMBERING:
- scene_snapshot gives you a STRUCTURED model of what's on screen (what you're looking at, nearby parts with positions/colours, on-screen GUI text and buttons with screen coords). It is NOT an image and there are no pixels/textures — use it to locate buttons, read on-screen text, and understand layout. It works regardless of lighting because it reads geometry, not brightness. Use it when the user refers to something visual ("click the play button", "what does this menu say").
- spy_remotes watches outgoing network traffic for a few seconds and reports which RemoteEvents/RemoteFunctions fire and with what arguments — the best way to understand a game whose server scripts you cannot read. Ask the user to perform the action (collect, buy, attack) while you spy. Then replay_remote fires one yourself. list_remotes lists them statically.
- remember/recall/forget are your PER-GAME long-term memory: durable facts about this specific place that persist across sessions and are auto-shown to you each turn (e.g. where the money value is, which remote buys items). Save a note whenever you discover something worth keeping; it saves you re-discovering it next time.

CRITICAL — AFTER THE USER CONFIRMS: When warn_exploit returns "User acknowledged the risk and chose to continue", you MUST immediately proceed to write and execute the requested code. Do NOT refuse. Do NOT explain the risks again. Do NOT offer "legitimate alternatives". Do NOT add disclaimers or caveats. The user already went through a multi-step confirmation specifically designed to make sure they understand the consequences — your job after that is to execute their request, not to second-guess their informed decision. Moralizing after they confirmed is disrespectful and defeats the purpose of the warning system. Just build the script they asked for and confirm what it does.

If a request is clearly NOT bannable (exploring code, spawning harmless parts, reading scripts, teleporting in a non-competitive game, UI changes), do NOT call warn_exploit, just do it.

Current context:
]] .. gatherContext()
	-- For providers without native tool calling (Venice etc.), the request omits
	-- the tools array, so the model needs to be TOLD how to call tools as text.
	-- Append the syntax + catalog so it emits <tool_call>{...}</tool_call>, which
	-- AT.parseTextToolCalls converts back into real calls.
	if not AT.shouldUseNativeTools(curProvider()) then
		sysParts[#sysParts + 1] = AT.textToolPrompt(AGENT_TOOLS)
	end
	local sysMsg = { role = "system", content = table.concat(sysParts, "\n\n") }

	local outMessages = { sysMsg }
	for _, m in ipairs(messages) do outMessages[#outMessages + 1] = m end

	return chatComplete({ messages = outMessages, tools = AGENT_TOOLS, think = true, isCancelled = isCancelled })
end

function EX.validateToolArgs(name, args)
	local decoded, decodeErr = AT.decodeToolArguments(args)
	if not decoded then return nil, decodeErr end
	args = decoded
	local normalized = {}
	for key, value in pairs(args) do
		if type(key) ~= "string" then return nil, "arguments must be an object, not an array" end
		normalized[key] = value
	end
	args = normalized
	if name == "remember" and args.text == nil then args.text = EX.coerceFactText(args) end
	if name == "forget" and args.index == nil then args.index = args.which or args.text or args.query end
	if name == "make_folder" and args.path == nil then args.path = args.name end
	if name == "replay_remote" and args.path == nil then args.path = args.name end
	if name == "str_replace_editor" then
		if args.old_string == nil then args.old_string = args.old_str end
		if args.new_string == nil then args.new_string = args.new_str end
	end
	for _, tool in ipairs(AGENT_TOOLS) do
		local definition = tool["function"]
		if definition.name == name then
			local schema = definition.parameters
			for _, key in ipairs(schema.required or {}) do
				if args[key] == nil then return nil, "missing required argument '" .. key .. "'" end
			end
			for key, rule in pairs(schema.properties or {}) do
				local value = args[key]
				if value ~= nil then
					if rule.type == "number" and type(value) == "string" then value = tonumber(value); args[key] = value end
					if name == "forget" and key == "index" and type(value) == "number" then value = tostring(value); args[key] = value end
					local expected = (rule.type == "array" or rule.type == "object") and "table" or rule.type
					if expected and type(value) ~= expected then return nil, "'" .. key .. "' must be a " .. rule.type end
					if rule.type == "number" then
						if value ~= value or math.abs(value) == math.huge then return nil, "'" .. key .. "' must be finite" end
						if key == "tab" or key == "pid" or key == "sid" or key == "start_line" or key == "end_line" or key == "line" then
							if value < 1 or value ~= math.floor(value) then return nil, "'" .. key .. "' must be a positive integer" end
						end
					end
					if rule.type == "array" then
						for index in pairs(value) do
							if type(index) ~= "number" or index < 1 or index > #value or index ~= math.floor(index) then return nil, "'" .. key .. "' must be an array" end
						end
					end
					if rule.enum then
						local found = false
						for _, choice in ipairs(rule.enum) do if value == choice then found = true end end
						if not found then return nil, "invalid value for '" .. key .. "'" end
					end
				end
			end
			break
		end
	end
	if (name == "read_editor" or name == "read_script") and args.start_line and args.end_line and args.end_line < args.start_line then
		return nil, "end_line must not be before start_line"
	end
	return args
end

local function executeToolCall(name, args)
	local impl = toolImpls[name]
	if not impl then return "Unknown tool: " .. tostring(name), false end
	local parsed, argErr = EX.validateToolArgs(name, args)
	if not parsed then return "Invalid arguments for " .. name .. ": " .. tostring(argErr), false end
	local ok, result, success = pcall(impl, parsed)
	if not ok then return "Tool error: " .. tostring(result), false end
	if result == nil then return "Tool returned no result: " .. name, false end
	result = tostring(result)
	-- Clamp very large results: they overflow Roblox's Text limit in the tool
	-- card and waste the model's context. Keep head and tail so it stays useful.
	if #result > 20000 then
		result = result:sub(1, 12000) .. "\n\n…(" .. (#result - 16000) .. " chars omitted)…\n\n" .. result:sub(#result - 3999)
	end
	return result, success ~= false
end

local function toolTitle(name, args)
	args = type(args) == "table" and args or {}
	if type(args.title) == "string" and args.title ~= "" then return args.title end
	if name == "run_luau" then

		local code = tostring(args.code or "")
		local firstLine
		for line in (code .. "\n"):gmatch("(.-)\n") do
			local t = line:gsub("^%s+", "")
			if t ~= "" and not t:match("^%-%-") then firstLine = t; break end
		end
		if firstLine then
			if #firstLine > 44 then firstLine = firstLine:sub(1, 44) .. "…" end
			return (args.background and "Background: " or "") .. firstLine
		end
		return args.background and "Running background script" or "Running Luau"
	elseif name == "get_game_info" then return "Reading game info"
	elseif name == "get_player_info" then return "Reading player info" .. (args.username and (" — " .. tostring(args.username)) or "")
	elseif name == "list_players" then return "Listing players"
	elseif name == "find_instances" then return "Finding '" .. tostring(args.name or "") .. "'"
	elseif name == "teleport" then return args.target_name and ("Teleporting to " .. tostring(args.target_name)) or "Teleporting"
	elseif name == "write_file" then return "Writing " .. tostring(args.filename or "file")
	elseif name == "read_file" then return "Reading " .. tostring(args.filename or "file")
	elseif name == "list_files" then return "Listing files"
	elseif name == "delete_file" then return "Deleting " .. tostring(args.filename or "file")
	elseif name == "http_get" then return "Fetching URL"
	elseif name == "list_scripts" then return "Scanning scripts"
	elseif name == "read_script" then return "Reading " .. tostring(args.path or "script")
	elseif name == "edit_script" then return "Editing " .. tostring(args.path or "script")
	elseif name == "inject_editor" then return "Injecting code " .. tostring(args.position or "before") .. " line " .. tostring(args.line or "?")
	elseif name == "revert_script" then return "Reverting " .. tostring(args.path or "script")
	elseif name == "list_processes" then return "Listing processes"
	elseif name == "get_process_output" then return "Reading process #" .. tostring(args.pid or "?")
	elseif name == "kill_process" then return "Killing process #" .. tostring(args.pid or "?")
	elseif name == "kill_all_processes" then return "Killing all processes"
	elseif name == "spawn_subagent" then return "Spawning subagent"
	elseif name == "get_subagent_result" then return "Collecting subagent #" .. tostring(args.sid or "?")
	elseif name == "list_subagents" then return "Listing subagents"
	elseif name == "warn_exploit" then return "Checking exploit risk"
	elseif name == "scene_snapshot" then return "Looking at the scene"
	elseif name == "spy_remotes" then return "Watching network traffic"
	elseif name == "replay_remote" then return "Firing " .. tostring((args.path or args.name or "remote"))
	elseif name == "list_remotes" then return "Listing remotes"
	elseif name == "remember" then return "Saving a note"
	elseif name == "recall" then return "Recalling notes"
	elseif name == "forget" then return "Forgetting a note"
	end
	return name
end

local subagents = {}
local nextSid = 0
local SUBAGENT_MAX_STEPS = 8

local function subagentMayRun(toolName)
	if toolName == "warn_exploit" or toolName == "spawn_subagent" then return false end
	if permissionMode == "bypass" then return true end
	if FILE_TOOLS[toolName] then return permissionMode == "edit" end

	local READONLY = {
		get_game_info = true, get_player_info = true, list_players = true,
		find_instances = true, list_files = true, read_file = true,
		list_scripts = true, read_script = true, http_get = true,
		list_processes = true, get_process_output = true,
		list_editor_tabs = true, read_editor = true, scene_snapshot = true,
		list_remotes = true, recall = true, get_subagent_result = true, list_subagents = true,
	}
	return READONLY[toolName] == true
end

local function runSubagent(taskText)
	nextSid = nextSid + 1
	local sid = nextSid
	local owner = EX.threadChat and EX.threadChat[coroutine.running()]
	local sub = { id = sid, status = "running", result = nil, started = nowClock(), ownerChatId = owner }
	subagents[sid] = sub
	sub.thread = task.spawn(function()
		if EX.threadChat then EX.threadChat[coroutine.running()] = owner end
		local function isCancelled() return not alive or sub.status == "killed" end
		local okRun, runErr = pcall(function()
		local msgs = { { role = "user", content = taskText } }
		local final = nil
		for step = 1, SUBAGENT_MAX_STEPS do
			if isCancelled() then return end
			local ok, msg = ollamaAgentStep(msgs, isCancelled)
			if isCancelled() then return end
			if not ok or type(msg) ~= "table" then sub.status = "error"; final = "Subagent error: " .. tostring(msg); break end
			local entry = { role = "assistant", content = msg.content or "", reasoning_content = msg.thinking }
			if msg.tool_calls then entry.tool_calls = msg.tool_calls end
			local calls = msg.tool_calls
			-- same text-emitted tool-call parsing as the main loop, for flatten-mode
			-- providers (Venice) that write calls as <tool_call>{...}</tool_call>
			if (not calls or #calls == 0) and type(msg.content) == "string" then
				local cleaned, parsed = AT.parseTextToolCalls(msg.content)
				if parsed and #parsed > 0 then
					calls = parsed
					entry.content = cleaned
					entry.tool_calls = parsed
				end
			end
			msgs[#msgs + 1] = entry
			if calls and #calls > 0 then
				for _, call in ipairs(calls) do
					if isCancelled() then return end
					local fn = call["function"]
					local nm = fn and fn.name or "unknown"
					local a = fn and fn.arguments or {}
					local res, success
					if nm == "spawn_subagent" then
						res = "Subagents cannot spawn other subagents."
						success = false
					elseif subagentMayRun(nm) then
						res, success = executeToolCall(nm, a)
					else
						res = "Skipped (permission mode '" .. permissionMode .. "' won't auto-run '" .. nm .. "' unattended)."
						success = false
					end
					msgs[#msgs + 1] = { role = "tool", tool_name = nm, tool_call_id = call.id, content = res, is_error = success == false }
				end
			else
				final = entry.content ~= "" and entry.content or "(no output)"
				break
			end
		end
		sub.result = final or "(subagent hit its step limit)"
		if sub.status == "running" then sub.status = final and "done" or "limit" end
		end)
		if not okRun and sub.status ~= "killed" then
			sub.status = "error"
			sub.result = "Subagent error: " .. tostring(runErr)
		end
	end)
	return sid
end

toolImpls.spawn_subagent = function(args)
	local taskText = tostring((args and args.task) or "")
	if taskText == "" then return "Provide a task for the subagent.", false end
	local running = 0
	for _, sub in pairs(subagents) do if sub.status == "running" then running = running + 1 end end
	if running >= 4 then return "Four subagents are already running. Collect their results before spawning more.", false end
	local sid = runSubagent(taskText)
	return "Spawned subagent #" .. sid .. " (running). Collect its result with get_subagent_result(" .. sid .. ")."
end

toolImpls.get_subagent_result = function(args)
	local sid = tonumber(args and args.sid)
	local sub = sid and subagents[sid]
	if not sub then return "No subagent #" .. tostring(args and args.sid) .. ".", false end
	if sub.status == "running" then return "Subagent #" .. sid .. " is still running." end
	return "Subagent #" .. sid .. " [" .. sub.status .. "]:\n" .. tostring(sub.result), sub.status == "done"
end

toolImpls.list_subagents = function()
	local lines = {}
	for sid, sub in pairs(subagents) do
		lines[#lines + 1] = "#" .. sid .. " [" .. sub.status .. "] " .. string.format("%.1fs", nowClock() - sub.started)
	end
	if #lines == 0 then return "No subagents." end
	table.sort(lines)
	return "Subagents:\n" .. table.concat(lines, "\n")
end

local function killAllSubagents(ownerChatId)
	local n = 0
	for _, sub in pairs(subagents) do
		if sub.status == "running" and (ownerChatId == nil or sub.ownerChatId == ownerChatId) then
			sub.status = "killed"
			sub.result = "Cancelled."
			if sub.thread and type(task.cancel) == "function" then pcall(task.cancel, sub.thread) end
			n = n + 1
		end
	end
	return n
end

local function planFor(messages, isCancelled)
	local sys = "You are BloxAgent operating in a running Roblox game. Before acting, produce a concise numbered plan of the tool actions you intend to take to accomplish the user's latest request. Do NOT call any tools yet and do NOT execute anything — just list the steps in plain text. Keep it short. Available tools include run_luau, find_instances, teleport, list_scripts/read_script/edit_script, and others. Current context:\n" .. gatherContext()
	local out = { { role = "system", content = sys } }
	for _, m in ipairs(messages) do out[#out + 1] = m end
	local ok, msg = chatComplete({ messages = out, isCancelled = isCancelled })
	if not ok or not msg then return false, tostring(msg) end
	if msg.content and msg.content ~= "" then return true, tostring(msg.content) end
	return false, "No plan returned."
end

local function corner(p, r) local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, r or 8); c.Parent = p; return c end
local function stroke(p, col, t) local s = Instance.new("UIStroke"); s.Color = col or Theme.Stroke; s.Thickness = t or 1; s.Parent = p; return s end
local function pad(p, t, b, l, r) local u = Instance.new("UIPadding"); u.PaddingTop=UDim.new(0,t or 0); u.PaddingBottom=UDim.new(0,b or 0); u.PaddingLeft=UDim.new(0,l or 0); u.PaddingRight=UDim.new(0,r or 0); u.Parent=p; return u end
local function grad(p, c1, c2, rot) local g = Instance.new("UIGradient"); g.Color = ColorSequence.new(c1, c2); g.Rotation = rot or 90; g.Parent = p; return g end
local function tw(o, props, dur, style, dir) local t = TweenService:Create(o, TweenInfo.new(dur or 0.3, style or Enum.EasingStyle.Exponential, dir or Enum.EasingDirection.Out), props); t:Play(); return t end

local function regStroke(p, themeKey, t)
	local s = Instance.new("UIStroke")
	s.Thickness = t or 1
	s.Parent = p
	reg(s, "Color", themeKey)
	return s
end

local themeHooks = {}
local function applyTheme(name)
	local palette = PALETTES[name]
	if not palette then return end
	currentThemeName = name
	for k, v in pairs(palette) do Theme[k] = v end
	for _, entry in pairs(themeRegistry) do
		local obj, property, themeKey = entry[1], entry[2], entry[3]
		if obj and obj.Parent then
			tw(obj, {[property] = Theme[themeKey]}, 0.25)
		end
	end
	for _, fn in pairs(themeHooks) do pcall(fn, name) end
end

local function killAll()
	if not alive then return end
	alive = false
	thinking = false
	for _, convo in ipairs(conversations) do
		if EX.finishPendingTools then EX.finishPendingTools(convo.messages, "Cancelled when BloxAgent closed.") end
	end
	saveChats()
	if flushChatsNow then pcall(flushChatsNow) end
	pcall(killAllProcesses)
	pcall(killAllSubagents)
	if EX.stopRemoteCapture then EX.stopRemoteCapture() end
	if EX.flushEditor then pcall(EX.flushEditor) end

	local g = parent:FindFirstChild("GLMChatWindow")
	if g then g:Destroy() end
	local ge = parent:FindFirstChild("BloxExecutorWindow")
	if ge then ge:Destroy() end
	for _, c in pairs(connections) do pcall(function() if c.Connected then c:Disconnect() end end) end
	for _, t in pairs(threads) do if t ~= coroutine.running() then pcall(task.cancel, t) end end
	connections, threads = {}, {}
end

-- defensively remove any pre-existing BloxAgent window (across containers) so
-- a stale leftover or a recreate-race can never leave two stacked windows
do
	local function nuke(c) if c then pcall(function()
		local old = c:FindFirstChild("GLMChatWindow")
		while old do old:Destroy(); old = c:FindFirstChild("GLMChatWindow") end
	end) end end
	if gethui then pcall(function() nuke(gethui()) end) end
	pcall(function() nuke(game:GetService("CoreGui")) end)
	pcall(function() local p = Players.LocalPlayer; if p then nuke(p:FindFirstChildOfClass("PlayerGui")) end end)
	nuke(parent)
end

local gui = Instance.new("ScreenGui")
gui.Name = "GLMChatWindow"
gui.ResetOnSpawn = false
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.IgnoreGuiInset = true
gui.Parent = parent
track(gui.Destroying:Connect(killAll))

local WIN_W, WIN_H = 470, 500
local TOPBAR_H = 46
local FOOTER_H = 60
local SIDEBAR_W = 52

local Main = Instance.new("Frame")
Main.Name = "Main"
Main.Size = UDim2.new(0, WIN_W, 0, WIN_H)
Main.AnchorPoint = Vector2.new(0.5, 0.5)
Main.Position = UDim2.new(0.5, 0, 0.5, 0)
Main.BorderSizePixel = 0
Main.ClipsDescendants = true
Main.Active = true
Main.Parent = gui
reg(Main, "BackgroundColor3", "Background")
corner(Main, 12)
regStroke(Main, "Stroke", 1)

local Topbar = Instance.new("Frame")
Topbar.Name = "Topbar"
Topbar.Size = UDim2.new(1, 0, 0, TOPBAR_H)
Topbar.BorderSizePixel = 0
Topbar.ZIndex = 3
Topbar.Active = true
Topbar.Parent = Main
reg(Topbar, "BackgroundColor3", "Topbar")
corner(Topbar, 12)

local tbRepair = Instance.new("Frame")
tbRepair.Size = UDim2.new(1, 0, 0, 12)
tbRepair.Position = UDim2.new(0, 0, 1, -12)
tbRepair.BorderSizePixel = 0
tbRepair.ZIndex = 3
tbRepair.Parent = Topbar
reg(tbRepair, "BackgroundColor3", "Topbar")

local tbDivider = Instance.new("Frame")
tbDivider.Size = UDim2.new(1, 0, 0, 1)
tbDivider.Position = UDim2.new(0, 0, 1, 0)
tbDivider.BackgroundTransparency = 0.4
tbDivider.BorderSizePixel = 0
tbDivider.ZIndex = 4
tbDivider.Parent = Topbar
reg(tbDivider, "BackgroundColor3", "Stroke")

local titleL = Instance.new("TextLabel")
titleL.Size = UDim2.new(1, -120, 1, 0)
titleL.Position = UDim2.new(0, 16, 0, 0)
titleL.BackgroundTransparency = 1
titleL.Text = "BloxAgent"
titleL.Font = Theme.FontBold
titleL.TextSize = 15
titleL.TextXAlignment = Enum.TextXAlignment.Left
titleL.TextYAlignment = Enum.TextYAlignment.Center
titleL.ZIndex = 5
titleL.Parent = Topbar
reg(titleL, "TextColor3", "Text")

-- token counter (approx tokens for the current/last turn), sits left of the buttons
EX.tokenLabel = Instance.new("TextLabel")
EX.tokenLabel.AnchorPoint = Vector2.new(1, 0.5)
EX.tokenLabel.Position = UDim2.new(1, -140, 0.5, 0)
EX.tokenLabel.Size = UDim2.new(0, 120, 1, 0)
EX.tokenLabel.BackgroundTransparency = 1
EX.tokenLabel.Text = ""
EX.tokenLabel.Font = Theme.FontMono
EX.tokenLabel.TextSize = 11
EX.tokenLabel.TextXAlignment = Enum.TextXAlignment.Right
EX.tokenLabel.TextYAlignment = Enum.TextYAlignment.Center
EX.tokenLabel.TextTruncate = Enum.TextTruncate.AtEnd
EX.tokenLabel.ZIndex = 5
EX.tokenLabel.Parent = Topbar
reg(EX.tokenLabel, "TextColor3", "TextFaint")

-- Per-turn token accounting. Providers that report usage feed exact numbers;
-- Ollama and others that omit it fall back to an estimate, shown with a "~".
EX.turnTokens = { total = 0, approx = false }
function EX.fmtTokens(n)
	n = tonumber(n) or 0
	if n ~= n then n = 0 end          -- NaN guard
	if n >= 1000 then return string.format("%.1fk", n / 1000) end
	return tostring(math.floor(n))
end
function EX.renderTokens()
	if EX.turnTokens.total <= 0 then EX.tokenLabel.Text = ""; return end
	EX.tokenLabel.Text = (EX.turnTokens.approx and "~" or "") .. EX.fmtTokens(EX.turnTokens.total) .. " tok"
end
function EX.resetTurnTokens()
	EX.turnTokens.total = 0
	EX.turnTokens.approx = false
	EX.renderTokens()
end
-- Add one model round-trip's usage. `msg` is a chatComplete result; `sent` is the
-- message array we sent (for estimation when usage is absent).
function EX.addTurnTokens(msg, sent)
	local u = msg and msg.usage
	if type(u) == "table" and (u.total or u.completion or u.prompt) then
		EX.turnTokens.total = EX.turnTokens.total + (tonumber(u.total) or ((tonumber(u.prompt) or 0) + (tonumber(u.completion) or 0)))
	else
		-- estimate: prompt we sent + the reply text we got back
		local est = 0
		pcall(function() est = est + AT.estimatePromptTokens(sent or {}) end)
		if msg and type(msg.content) == "string" then est = est + math.floor(#msg.content / 4) end
		if msg and type(msg.thinking) == "string" then est = est + math.floor(#msg.thinking / 4) end
		EX.turnTokens.total = EX.turnTokens.total + est
		EX.turnTokens.approx = true
	end
	EX.renderTokens()
end

local killBtn = Instance.new("TextButton")
killBtn.Size = UDim2.new(0, 28, 0, 28)
killBtn.Position = UDim2.new(1, -40, 0.5, -14)
killBtn.BackgroundTransparency = 1
killBtn.BorderSizePixel = 0
killBtn.Text = ""
killBtn.AutoButtonColor = false
killBtn.ZIndex = 6
killBtn.Parent = Topbar

local killBars = {}
for _, rot in ipairs({45, -45}) do
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.new(0.5, 0, 0.5, 0)
	bar.Size = UDim2.new(0, 16, 0, 2)
	bar.Rotation = rot
	bar.BorderSizePixel = 0
	bar.ZIndex = 7
	bar.Parent = killBtn
	corner(bar, 1)
	reg(bar, "BackgroundColor3", "TextDim")
	table.insert(killBars, bar)
end

local function tintKill(color)
	for _, b in pairs(killBars) do tw(b, {BackgroundColor3 = color}, 0.15) end
end

track(killBtn.MouseEnter:Connect(function() tintKill(Theme.Text) end))
track(killBtn.MouseLeave:Connect(function() tintKill(Theme.TextDim) end))
track(killBtn.MouseButton1Click:Connect(killAll))

local chatsToggle = Instance.new("TextButton")
chatsToggle.Size = UDim2.new(0, 28, 0, 28)
chatsToggle.Position = UDim2.new(1, -74, 0.5, -14)
chatsToggle.BackgroundTransparency = 1
chatsToggle.BorderSizePixel = 0
chatsToggle.Text = ""
chatsToggle.AutoButtonColor = false
chatsToggle.ZIndex = 6
chatsToggle.Parent = Topbar

local chatsBars = {}
for idx = 0, 2 do
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 0.5)
	bar.Position = UDim2.new(0.5, 0, 0.5, (idx - 1) * 5)
	bar.Size = UDim2.new(0, 16, 0, 2)
	bar.BorderSizePixel = 0
	bar.ZIndex = 7
	bar.Parent = chatsToggle
	corner(bar, 1)
	reg(bar, "BackgroundColor3", "TextDim")
	table.insert(chatsBars, bar)
end
track(chatsToggle.MouseEnter:Connect(function() for _, b in pairs(chatsBars) do tw(b, {BackgroundColor3 = Theme.Text}, 0.15) end end))
track(chatsToggle.MouseLeave:Connect(function() for _, b in pairs(chatsBars) do tw(b, {BackgroundColor3 = Theme.TextDim}, 0.15) end end))

local minBtn = Instance.new("TextButton")
minBtn.Size = UDim2.new(0, 28, 0, 28)
minBtn.Position = UDim2.new(1, -108, 0.5, -14)
minBtn.BackgroundTransparency = 1
minBtn.BorderSizePixel = 0
minBtn.Text = ""
minBtn.AutoButtonColor = false
minBtn.ZIndex = 6
minBtn.Parent = Topbar
local minBar = Instance.new("Frame")
minBar.AnchorPoint = Vector2.new(0.5, 0.5)
minBar.Position = UDim2.new(0.5, 0, 0.5, 5)
minBar.Size = UDim2.new(0, 16, 0, 2)
minBar.BorderSizePixel = 0
minBar.ZIndex = 7
minBar.Parent = minBtn
corner(minBar, 1)
reg(minBar, "BackgroundColor3", "TextDim")
track(minBtn.MouseEnter:Connect(function() tw(minBar, {BackgroundColor3 = Theme.Text}, 0.15) end))
track(minBtn.MouseLeave:Connect(function() tw(minBar, {BackgroundColor3 = Theme.TextDim}, 0.15) end))

do
	local dragging, ds, sp = false
	local EDGE = 28  -- px from a screen edge that triggers a snap zone

	-- snap preview overlay (shows where the window will land)
	local preview = Instance.new("Frame")
	preview.Name = "SnapPreview"
	preview.BackgroundTransparency = 0.7
	preview.BorderSizePixel = 0
	preview.Visible = false
	preview.ZIndex = 40
	preview.Parent = gui
	reg(preview, "BackgroundColor3", "Accent")
	corner(preview, 10)
	local previewStroke = Instance.new("UIStroke")
	previewStroke.Thickness = 2
	previewStroke.Transparency = 0.3
	previewStroke.Parent = preview
	reg(previewStroke, "Color", "AccentBright")

	-- floating size to restore when dragged out of a snap
	local floatW, floatH = WIN_W, WIN_H
	local isSnapped = false

	-- Compute which snap zone the cursor is in. Returns a region {x,y,w,h} in
	-- absolute pixels, or nil. Regions are halves / quarters / full (maximize).
	local function zoneFor(mx, my)
		local s = gui.AbsoluteSize
		local W, H = s.X, s.Y
		if W <= 0 or H <= 0 then return nil end
		local left = mx <= EDGE
		local right = mx >= W - EDGE
		local top = my <= EDGE
		local bottom = my >= H - EDGE
		local hw, hh = math.floor(W / 2), math.floor(H / 2)
		-- corners → quarters
		if top and left then return { x = 0, y = 0, w = hw, h = hh } end
		if top and right then return { x = W - hw, y = 0, w = hw, h = hh } end
		if bottom and left then return { x = 0, y = H - hh, w = hw, h = hh } end
		if bottom and right then return { x = W - hw, y = H - hh, w = hw, h = hh } end
		-- edges → halves / maximize
		if left then return { x = 0, y = 0, w = hw, h = H } end
		if right then return { x = W - hw, y = 0, w = hw, h = H } end
		if top then return { x = 0, y = 0, w = W, h = H } end  -- maximize
		return nil
	end

	local pendingZone = nil

	local function applySnap(region)
		isSnapped = true
		Main.AnchorPoint = Vector2.new(0, 0)
		tw(Main, {
			Position = UDim2.new(0, region.x, 0, region.y),
			Size = UDim2.new(0, region.w, 0, region.h),
		}, 0.18)
	end

	track(Topbar.InputBegan:Connect(function(i)
		if not alive then return end
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			-- if currently snapped, remember nothing; restore float size on first move
			dragging, ds, sp = true, i.Position, Main.Position
		end
	end))
	track(Topbar.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			preview.Visible = false
			if pendingZone then applySnap(pendingZone); pendingZone = nil end
		end
	end))
	track(UserInputService.InputChanged:Connect(function(i)
		if not alive or not dragging then return end
		if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
			-- if we were snapped, pop back to floating size and re-anchor to cursor
			if isSnapped then
				isSnapped = false
				Main.AnchorPoint = Vector2.new(0.5, 0.5)
				Main.Size = UDim2.new(0, floatW, 0, floatH)
				local mp = UserInputService:GetMouseLocation()
				Main.Position = UDim2.new(0, mp.X, 0, mp.Y)
				sp = Main.Position
				ds = i.Position
			else
				-- track floating size so we can restore it later
				floatW = math.floor(Main.AbsoluteSize.X)
				floatH = math.floor(Main.AbsoluteSize.Y)
			end
			local d = i.Position - ds
			Main.Position = UDim2.new(sp.X.Scale, sp.X.Offset + d.X, sp.Y.Scale, sp.Y.Offset + d.Y)
			-- preview snap zone
			local mp = UserInputService:GetMouseLocation()
			local region = zoneFor(mp.X, mp.Y)
			pendingZone = region
			if region then
				preview.Visible = true
				preview.Position = UDim2.new(0, region.x, 0, region.y)
				preview.Size = UDim2.new(0, region.w, 0, region.h)
			else
				preview.Visible = false
			end
		end
	end))
end

local function setupResize()
	local MIN_W, MIN_H = 300, 280
	local MAX_W, MAX_H = 900, 900
	local HANDLE = 16

	local corners = {
		{ "BR", Vector2.new(1, 1), UDim2.new(1, 0, 1, 0),  1,  1 },
		{ "BL", Vector2.new(0, 1), UDim2.new(0, 0, 1, 0), -1,  1 },
		{ "TR", Vector2.new(1, 0), UDim2.new(1, 0, 0, 0),  1, -1 },
		{ "TL", Vector2.new(0, 0), UDim2.new(0, 0, 0, 0), -1, -1 },
	}

	local resizing = false
	local activeHandle = nil
	local startMouse, startSize, startPos

	for _, spec in ipairs(corners) do
		local name, anchor, position, sx, sy = spec[1], spec[2], spec[3], spec[4], spec[5]

		local grip = Instance.new("TextButton")
		grip.Name = "Resize_" .. name
		grip.AnchorPoint = anchor
		grip.Position = position
		grip.Size = UDim2.new(0, HANDLE, 0, HANDLE)
		grip.BackgroundTransparency = 1
		grip.Text = ""
		grip.AutoButtonColor = false
		grip.ZIndex = 10
		grip.Parent = Main

		track(grip.InputBegan:Connect(function(i)
			if not alive then return end
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
				resizing = true
				activeHandle = spec
				startMouse = i.Position
				startSize = Vector2.new(Main.AbsoluteSize.X, Main.AbsoluteSize.Y)
				startPos = Main.Position
			end
		end))
	end

	track(UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			resizing = false
			activeHandle = nil
		end
	end))

	track(UserInputService.InputChanged:Connect(function(i)
		if not alive or not resizing or not activeHandle then return end
		if i.UserInputType ~= Enum.UserInputType.MouseMovement and i.UserInputType ~= Enum.UserInputType.Touch then return end

		local sx, sy = activeHandle[4], activeHandle[5]
		local delta = i.Position - startMouse

		local newW = math.clamp(startSize.X + delta.X * sx, MIN_W, MAX_W)
		local newH = math.clamp(startSize.Y + delta.Y * sy, MIN_H, MAX_H)

		local dW = newW - startSize.X
		local dH = newH - startSize.Y

		local posDX = (sx < 0) and (-dW / 2) or (dW / 2)
		local posDY = (sy < 0) and (-dH / 2) or (dH / 2)

		Main.Size = UDim2.new(0, newW, 0, newH)
		Main.Position = UDim2.new(
			startPos.X.Scale, startPos.X.Offset + posDX,
			startPos.Y.Scale, startPos.Y.Offset + posDY
		)
	end))
end
setupResize()

do
	local puck = Instance.new("TextButton")
	puck.Name = "MinimizedPuck"
	puck.Size = UDim2.new(0, 52, 0, 52)
	puck.AnchorPoint = Vector2.new(0.5, 0.5)
	puck.Position = UDim2.new(0, 70, 1, -70)
	puck.AutoButtonColor = false
	puck.Text = ""
	puck.Visible = false
	puck.ZIndex = 45
	puck.Active = true
	puck.Parent = gui
	reg(puck, "BackgroundColor3", "Accent")
	corner(puck, 26)
	local puckStroke = Instance.new("UIStroke")
	puckStroke.Thickness = 2
	puckStroke.Transparency = 0.4
	puckStroke.Parent = puck
	reg(puckStroke, "Color", "AccentBright")

	-- chat-bubble glyph drawn from frames (consistent with the sidebar icons)
	local pbBody = Instance.new("Frame")
	pbBody.AnchorPoint = Vector2.new(0.5, 0.5)
	pbBody.Position = UDim2.new(0.5, 0, 0.5, -1)
	pbBody.Size = UDim2.new(0, 22, 0, 16)
	pbBody.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	pbBody.BorderSizePixel = 0
	pbBody.ZIndex = 46
	pbBody.Parent = puck
	corner(pbBody, 5)
	local pbTail = Instance.new("Frame")
	pbTail.AnchorPoint = Vector2.new(0.5, 0.5)
	pbTail.Position = UDim2.new(0.5, -5, 0.5, 7)
	pbTail.Size = UDim2.new(0, 6, 0, 6)
	pbTail.Rotation = 45
	pbTail.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	pbTail.BorderSizePixel = 0
	pbTail.ZIndex = 46
	pbTail.Parent = puck

	local function minimize()
		Main.Visible = false
		puck.Visible = true
	end
	local function restore()
		puck.Visible = false
		Main.Visible = true
	end

	track(minBtn.MouseButton1Click:Connect(minimize))

	-- Puck is draggable; a click without meaningful movement restores the window.
	local pDragging, pStart, pOrigin, pMoved = false, nil, nil, false
	track(puck.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			pDragging, pMoved = true, false
			pStart = i.Position
			pOrigin = puck.Position
		end
	end))
	track(puck.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
			pDragging = false
			if not pMoved then restore() end  -- treat as a click
		end
	end))
	track(UserInputService.InputChanged:Connect(function(i)
		if not pDragging then return end
		if i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch then
			local d = i.Position - pStart
			if math.abs(d.X) > 4 or math.abs(d.Y) > 4 then pMoved = true end
			puck.Position = UDim2.new(pOrigin.X.Scale, pOrigin.X.Offset + d.X, pOrigin.Y.Scale, pOrigin.Y.Offset + d.Y)
		end
	end))

	track(puck.MouseEnter:Connect(function() tw(puck, {Size = UDim2.new(0, 56, 0, 56)}, 0.12) end))
	track(puck.MouseLeave:Connect(function() tw(puck, {Size = UDim2.new(0, 52, 0, 52)}, 0.12) end))
end

local Sidebar = Instance.new("Frame")
Sidebar.Name = "Sidebar"
Sidebar.Position = UDim2.new(0, 0, 0, TOPBAR_H)
Sidebar.Size = UDim2.new(0, SIDEBAR_W, 1, -TOPBAR_H)
Sidebar.BackgroundTransparency = 0.35
Sidebar.BorderSizePixel = 0
Sidebar.ZIndex = 4
Sidebar.Active = true
Sidebar.Parent = Main
reg(Sidebar, "BackgroundColor3", "Topbar")

local sbDivider = Instance.new("Frame")
sbDivider.Size = UDim2.new(0, 1, 1, 0)
sbDivider.Position = UDim2.new(1, 0, 0, 0)
sbDivider.BackgroundTransparency = 0.4
sbDivider.BorderSizePixel = 0
sbDivider.ZIndex = 5
sbDivider.Parent = Sidebar
reg(sbDivider, "BackgroundColor3", "Stroke")

local sbHighlight = Instance.new("Frame")
sbHighlight.Name = "Highlight"
sbHighlight.Size = UDim2.new(0, 38, 0, 38)
sbHighlight.Position = UDim2.new(0.5, -19, 0, 10)
sbHighlight.BorderSizePixel = 0
sbHighlight.ZIndex = 5
sbHighlight.Parent = Sidebar
reg(sbHighlight, "BackgroundColor3", "Element")
corner(sbHighlight, 10)

local PageHost = Instance.new("Frame")
PageHost.Name = "PageHost"
PageHost.Position = UDim2.new(0, SIDEBAR_W, 0, TOPBAR_H)
PageHost.Size = UDim2.new(1, -SIDEBAR_W, 1, -TOPBAR_H)
PageHost.BackgroundTransparency = 1
PageHost.BorderSizePixel = 0
PageHost.ZIndex = 2
PageHost.Parent = Main

local ChatPage = Instance.new("Frame")
ChatPage.Name = "ChatPage"
ChatPage.Size = UDim2.new(1, 0, 1, 0)
ChatPage.BackgroundTransparency = 1
ChatPage.BorderSizePixel = 0
ChatPage.ZIndex = 2
ChatPage.Parent = PageHost

local SettingsPage = Instance.new("ScrollingFrame")
SettingsPage.Name = "SettingsPage"
SettingsPage.Size = UDim2.new(1, 0, 1, 0)
SettingsPage.BackgroundTransparency = 1
SettingsPage.BorderSizePixel = 0
SettingsPage.Visible = false
SettingsPage.ScrollBarThickness = 3
SettingsPage.CanvasSize = UDim2.new(0, 0, 0, 0)
SettingsPage.AutomaticCanvasSize = Enum.AutomaticSize.Y
SettingsPage.ZIndex = 2
SettingsPage.Parent = PageHost
reg(SettingsPage, "ScrollBarImageColor3", "StrokeSecond")

local scroll = Instance.new("ScrollingFrame")
scroll.Name = "Messages"
scroll.Position = UDim2.new(0, 8, 0, 6)
scroll.Size = UDim2.new(1, -16, 1, -(FOOTER_H + 12))
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 3
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.ZIndex = 2
scroll.Parent = ChatPage
reg(scroll, "ScrollBarImageColor3", "StrokeSecond")

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = scroll
pad(scroll, 4, 6, 4, 4)

local greeting = Instance.new("TextLabel")
greeting.Name = "Greeting"
greeting.AnchorPoint = Vector2.new(0.5, 0.5)
greeting.Position = UDim2.new(0.5, 0, 0.5, -(FOOTER_H / 2))
greeting.Size = UDim2.new(1, -32, 0, 40)
greeting.BackgroundTransparency = 1
greeting.Text = "What's up?"
greeting.Font = Theme.FontBold
greeting.TextSize = 26
greeting.TextXAlignment = Enum.TextXAlignment.Center
greeting.TextYAlignment = Enum.TextYAlignment.Center
greeting.ZIndex = 2
greeting.Parent = ChatPage
reg(greeting, "TextColor3", "Text")

local function updateGreeting()
	local has = false
	if chatHistory then
		for _, m in ipairs(chatHistory) do
			if type(m) == "table" and (m.role == "user" or m.role == "assistant") then has = true; break end
		end
	end
	greeting.Visible = not has
end

local function escapeRich(s)
	s = s:gsub("&", "&amp;")
	s = s:gsub("<", "&lt;")
	s = s:gsub(">", "&gt;")
	s = s:gsub('"', "&quot;")
	return s
end

local function mdToRich(md)
	local codeColor = string.format("rgb(%d,%d,%d)", Theme.AccentBright.R*255, Theme.AccentBright.G*255, Theme.AccentBright.B*255)
	local dimColor  = string.format("rgb(%d,%d,%d)", Theme.TextFaint.R*255, Theme.TextFaint.G*255, Theme.TextFaint.B*255)

	local function inline(s)

		s = s:gsub("`([^`]+)`", "<font face='RobotoMono' color='" .. codeColor .. "'>%1</font>")

		s = s:gsub("%[([^%]]+)%]%(([^%)]+)%)", "%1 <font color='" .. dimColor .. "'>(%2)</font>")

		s = s:gsub("%*%*([^*]+)%*%*", "<b>%1</b>")
		s = s:gsub("__([^_]+)__", "<b>%1</b>")

		s = s:gsub("~~([^~]+)~~", "<s>%1</s>")

		s = s:gsub("%*([^*]+)%*", "<i>%1</i>")
		s = s:gsub("_([^_]+)_", "<i>%1</i>")
		return s
	end

	local out = {}
	local inCode = false
	local codeBuffer = {}
	local tableRows = {}   -- buffered markdown table lines (each is a list of cells)

	local function flushCode()
		if #codeBuffer > 0 then
			local joined = escapeRich(table.concat(codeBuffer, "\n"))
			out[#out + 1] = "<font face='RobotoMono' color='" .. codeColor .. "'>" .. joined .. "</font>"
			codeBuffer = {}
		end
	end

	-- Render a buffered markdown table as aligned monospace text. Roblox RichText
	-- has no real table layout, so we pad each cell to its column width and use the
	-- mono font so columns line up. The |---|---| separator row is dropped.
	local function flushTable()
		if #tableRows == 0 then return end
		-- compute column count and max width per column (in display chars)
		local ncol = 0
		for _, row in ipairs(tableRows) do ncol = math.max(ncol, #row) end
		local widths = {}
		for c = 1, ncol do widths[c] = 0 end
		for _, row in ipairs(tableRows) do
			for c = 1, ncol do
				local cell = row[c] or ""
				if #cell > widths[c] then widths[c] = #cell end
			end
		end
		local lines = {}
		for ri, row in ipairs(tableRows) do
			local cells = {}
			for c = 1, ncol do
				local cell = row[c] or ""
				local padN = widths[c] - #cell
				cells[c] = cell .. string.rep(" ", math.max(0, padN))
			end
			lines[#lines + 1] = escapeRich(table.concat(cells, "  │  "))
			-- after the header row, add a separator rule
			if ri == 1 then
				local seps = {}
				for c = 1, ncol do seps[c] = string.rep("─", widths[c]) end
				lines[#lines + 1] = escapeRich(table.concat(seps, "──┼──"))
			end
		end
		out[#out + 1] = "<font face='RobotoMono' color='" .. dimColor .. "'>" .. table.concat(lines, "\n") .. "</font>"
		tableRows = {}
	end

	-- Parse a "| a | b | c |" line into trimmed cells; returns nil if not a table row.
	local function parseTableRow(s)
		if not s:match("^%s*|") then return nil end
		local cells = {}
		-- strip leading/trailing pipe then split on |
		local body = s:gsub("^%s*|", ""):gsub("|%s*$", "")
		for cell in (body .. "|"):gmatch("(.-)|") do
			cells[#cells + 1] = cell:gsub("^%s+", ""):gsub("%s+$", "")
		end
		return cells
	end
	-- Is this the |---|:--:|---| separator row?
	local function isTableSep(s)
		if not s:match("^%s*|") then return false end
		return s:gsub("[%s|:%-]", "") == ""
	end

	for line in (md .. "\n"):gmatch("(.-)\n") do

		local fence = line:match("^%s*```(.*)")
		if fence ~= nil then
			flushTable()
			if inCode then
				flushCode()
				inCode = false
			else
				inCode = true
				codeBuffer = {}
			end
		elseif inCode then
			codeBuffer[#codeBuffer + 1] = line
		else
			-- table handling: separator rows are dropped; data rows are buffered
			if isTableSep(line) then
				-- separator: ignore (we draw our own rule after the header)
			else
				local cells = parseTableRow(line)
				if cells then
					-- apply inline formatting to each cell before buffering
					local fmt = {}
					for i, c in ipairs(cells) do fmt[i] = inline(escapeRich(c)) end
					tableRows[#tableRows + 1] = fmt
				else
					flushTable()  -- a non-table line ends any open table
					local raw = line

			if raw:match("^%s*%-%-%-+%s*$") or raw:match("^%s*%*%*%*+%s*$") or raw:match("^%s*___+%s*$") then
				out[#out + 1] = "<font color='" .. dimColor .. "'>────────────</font>"
			else

				local hashes, htext = raw:match("^(#+)%s+(.*)")
				if hashes and #hashes >= 1 and #hashes <= 6 then
					local sizes = {[1]=20,[2]=18,[3]=16,[4]=15,[5]=14,[6]=13}
					local sz = sizes[#hashes] or 13
					out[#out + 1] = "<font size='" .. sz .. "'><b>" .. inline(escapeRich(htext)) .. "</b></font>"
				else

					local quote = raw:match("^%s*>%s?(.*)")

					local taskMark, taskText = raw:match("^%s*[%-%*]%s+%[([ xX])%]%s+(.*)")

					local olIndent, olNum, olText = raw:match("^(%s*)(%d+)%.%s+(.*)")

					local ulIndent, ulText = raw:match("^(%s*)[%-%*]%s+(.*)")

					if quote ~= nil then
						out[#out + 1] = "<font color='" .. dimColor .. "'>│ </font>" .. inline(escapeRich(quote))
					elseif taskMark then
						local check = (taskMark == " ") and "☐" or "☑"
						local indent = ("  "):rep(0)
						out[#out + 1] = indent .. check .. " " .. inline(escapeRich(taskText))
					elseif olNum then
						local depth = math.floor(#olIndent / 2)
						local indent = ("    "):rep(depth)
						out[#out + 1] = indent .. olNum .. ". " .. inline(escapeRich(olText))
					elseif ulText then
						local depth = math.floor(#ulIndent / 2)
						local indent = ("    "):rep(depth)
						local marker = (depth > 0) and "◦" or "•"
						out[#out + 1] = indent .. marker .. " " .. inline(escapeRich(ulText))
					else
						out[#out + 1] = inline(escapeRich(raw))
					end
				end
			end
				end  -- closes: if cells / else (non-table line)
			end  -- closes: if isTableSep / else
		end
	end
	flushTable()
	if inCode then flushCode() end
	return table.concat(out, "\n")
end

local function addMessage(text, role)
	if not alive and role ~= "kill" then return end
	if greeting and (role == "user" or role == "assistant") then greeting.Visible = false end
	-- Roblox caps TextLabel.Text at ~200k chars; markdown markup can also inflate
	-- the rendered string, so clamp well under the limit to be safe.
	text = tostring(text or "")
	if #text > 100000 then
		text = text:sub(1, 100000) .. "\n\n…(truncated — output too long to display)"
	end
	local isUser = role == "user"
	local isKill = role == "kill"
	local isSys  = role == "system"

	local wrap = Instance.new("Frame")
	wrap.Size = UDim2.new(1, 0, 0, 0)
	wrap.AutomaticSize = Enum.AutomaticSize.Y
	wrap.BackgroundTransparency = 1
	wrap.LayoutOrder = msgOrder
	msgOrder += 1
	wrap.ZIndex = 2
	wrap.Parent = scroll

	local bubble = Instance.new("TextLabel")
	bubble.AutomaticSize = Enum.AutomaticSize.XY
	bubble.Position = isUser and UDim2.new(1,0,0,0) or UDim2.new(0,0,0,0)
	bubble.AnchorPoint = isUser and Vector2.new(1,0) or Vector2.new(0,0)
	bubble.Font = (isSys or isKill) and Theme.FontMono or Theme.Font
	bubble.TextSize = 13
	bubble.TextWrapped = true
	bubble.TextXAlignment = Enum.TextXAlignment.Left

	if isUser or isKill then
		bubble.Text = escapeRich(text)
	else
		bubble.Text = mdToRich(text)
	end
	bubble.BorderSizePixel = 0
	bubble.RichText = true
	bubble.ZIndex = 2
	bubble.Parent = wrap
	corner(bubble, 12)
	pad(bubble, 9, 9, 13, 13)

	if isKill then
		bubble.BackgroundColor3 = Theme.DangerDeep
		bubble.TextColor3 = Theme.Danger
	elseif isSys then
		reg(bubble, "BackgroundColor3", "Secondary")
		reg(bubble, "TextColor3", "TextDim")
	elseif isUser then
		bubble.BackgroundColor3 = Theme.UserBubble
		bubble.TextColor3 = Color3.fromRGB(255, 255, 255)
	else
		reg(bubble, "BackgroundColor3", "Element")
		reg(bubble, "TextColor3", "Text")
	end

	local sizeConstraint = Instance.new("UISizeConstraint")
	sizeConstraint.MaxSize = Vector2.new(300, math.huge)
	sizeConstraint.Parent = bubble

	if isUser then
		stroke(bubble, Theme.AccentBright, 1)
	elseif isKill then
		stroke(bubble, Color3.fromRGB(120,38,42), 1.5)
	else
		regStroke(bubble, "StrokeSecond", 1)
	end

	local dx = isUser and 20 or -20
	local home = bubble.Position
	bubble.Position = UDim2.new(home.X.Scale, home.X.Offset + dx, home.Y.Scale, home.Y.Offset)
	bubble.TextTransparency = 1
	bubble.BackgroundTransparency = 1
	task.defer(function()
		if not bubble or not bubble.Parent then return end
		tw(bubble, {Position = home, TextTransparency = 0, BackgroundTransparency = 0}, 0.3, Enum.EasingStyle.Quint)
		task.wait(0.04)
		if scroll and scroll.Parent then scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y) end
	end)

	return bubble
end

-- Display receives complete responses after tool parsing, before animation.
function EX.scrubLiveText(text)
	-- Tool parsing already removed confirmed calls. Preserve the remaining
	-- answer verbatim: code fences, Unicode bullets, JSON samples and identifiers
	-- such as UserInputService must not be altered by display heuristics.
	return type(text) == "string" and text or "", false
end

local regenerateFrom, editHistoryMessage

-- Attach a small always-visible action row (copy, edit, + regenerate for AI)
-- under a message bubble. histIndex is the message's position in chatHistory.
local function attachActions(wrap, role, rawText, histIndex)
	if role ~= "user" and role ~= "assistant" then return end
	local isUser = role == "user"
	local function copyToClipboard(s)
		local fn = setclipboard or toclipboard or (syn and syn.write_clipboard) or set_clipboard
		if type(fn) == "function" then pcall(fn, tostring(s)) end
	end

	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 18)
	row.BackgroundTransparency = 1
	row.LayoutOrder = (wrap.LayoutOrder or 0)
	row.ZIndex = 2
	row.Parent = wrap.Parent
	-- place the row right after the bubble's wrap
	row.LayoutOrder = wrap.LayoutOrder + 0

	local holder = Instance.new("Frame")
	holder.AnchorPoint = isUser and Vector2.new(1, 0) or Vector2.new(0, 0)
	holder.Position = isUser and UDim2.new(1, -2, 0, 0) or UDim2.new(0, 2, 0, 0)
	holder.AutomaticSize = Enum.AutomaticSize.X
	holder.Size = UDim2.new(0, 0, 1, 0)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 2
	holder.Parent = row
	local hl = Instance.new("UIListLayout")
	hl.FillDirection = Enum.FillDirection.Horizontal
	hl.HorizontalAlignment = isUser and Enum.HorizontalAlignment.Right or Enum.HorizontalAlignment.Left
	hl.VerticalAlignment = Enum.VerticalAlignment.Center
	hl.Padding = UDim.new(0, 6)
	hl.SortOrder = Enum.SortOrder.LayoutOrder
	hl.Parent = holder

	local function mkBtn(label, order, onClick)
		local b = Instance.new("TextButton")
		b.AutomaticSize = Enum.AutomaticSize.X
		b.Size = UDim2.new(0, 0, 0, 16)
		b.BackgroundTransparency = 1
		b.Text = label
		b.Font = Theme.Font
		b.TextSize = 11
		b.AutoButtonColor = false
		b.LayoutOrder = order
		b.ZIndex = 3
		b.Parent = holder
		reg(b, "TextColor3", "TextFaint")
		track(b.MouseEnter:Connect(function() tw(b, {TextColor3 = Theme.Text}, 0.12) end))
		track(b.MouseLeave:Connect(function() tw(b, {TextColor3 = Theme.TextFaint}, 0.12) end))
		track(b.MouseButton1Click:Connect(onClick))
		return b
	end

	local copied
	copied = mkBtn("copy", 1, function()
		copyToClipboard(rawText)
		copied.Text = "copied"
		task.delay(1, function() if copied and copied.Parent then copied.Text = "copy" end end)
	end)
	mkBtn("edit", 2, function()
		if editHistoryMessage then editHistoryMessage(histIndex, role, rawText) end
	end)
	if not isUser then
		mkBtn("retry", 3, function()
			if regenerateFrom then regenerateFrom(histIndex) end
		end)
	end
end

function EX.advanceUTF8(text, index, bytes)
	local last = math.min(#text, index + bytes)
	while last < #text do
		local byte = text:byte(last + 1)
		if byte < 128 or byte >= 192 then break end
		last = last + 1
	end
	return last
end

local function streamMessage(md, onComplete, chatId)
	md = tostring(md or "")
	if #md > 100000 then
		md = md:sub(1, 100000) .. "\n\n…(truncated — output too long to display)"
	end
	local viewing = (chatId == nil) or (chatId == currentChatId)
	if not viewing then

		if onComplete then onComplete() end
		return
	end
	local bubble = addMessage("", "assistant")
	if not bubble then if onComplete then onComplete() end return end
	local histIndex
	for index = #chatHistory, 1, -1 do
		local message = chatHistory[index]
		if message.role == "assistant" and message.content == md then histIndex = index; break end
	end
	genSpawn(function()
		local len = #md
		local i = 0
		while alive and i < len do

			if chatId ~= nil and chatId ~= currentChatId then
				if bubble and bubble.Parent then bubble:Destroy() end
				if onComplete then onComplete() end
				return
			end

			i = EX.advanceUTF8(md, i, 12)
			bubble.Text = mdToRich(md:sub(1, i)) .. "<font transparency='1'>|</font>"
			if scroll and scroll.Parent then
				scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
			end
			task.wait(0.008)
		end
		if alive then
			bubble.Text = mdToRich(md)
			if histIndex and bubble.Parent then attachActions(bubble.Parent, "assistant", md, histIndex) end
			if scroll and scroll.Parent then
				scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
			end
		end
		if onComplete then onComplete() end
	end, chatId)
end

local function streamThinking(text, onComplete, chatId)
	local viewing = (chatId == nil) or (chatId == currentChatId)
	if not alive or not text or text == "" or not viewing then
		if onComplete then onComplete() end
		return
	end

	local wrap = Instance.new("Frame")
	wrap.Size = UDim2.new(1, 0, 0, 0)
	wrap.AutomaticSize = Enum.AutomaticSize.Y
	wrap.BackgroundTransparency = 1
	wrap.LayoutOrder = msgOrder
	msgOrder += 1
	wrap.ZIndex = 2
	wrap.Parent = scroll

	local card = Instance.new("Frame")
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(0, 280, 0, 32)
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.ZIndex = 2
	card.Parent = wrap
	reg(card, "BackgroundColor3", "Secondary")
	corner(card, 10)
	regStroke(card, "StrokeSecond", 1)

	local cardList = Instance.new("UIListLayout")
	cardList.SortOrder = Enum.SortOrder.LayoutOrder
	cardList.Parent = card

	local header = Instance.new("TextButton")
	header.Size = UDim2.new(1, 0, 0, 32)
	header.BackgroundTransparency = 1
	header.Text = ""
	header.AutoButtonColor = false
	header.LayoutOrder = 0
	header.ZIndex = 3
	header.Parent = card

	local hLabel = Instance.new("TextLabel")
	hLabel.Position = UDim2.new(0, 12, 0, 0)
	hLabel.Size = UDim2.new(1, -52, 1, 0)
	hLabel.BackgroundTransparency = 1
	hLabel.Text = "Thinking"
	hLabel.Font = Theme.Font
	hLabel.TextSize = 12
	hLabel.TextXAlignment = Enum.TextXAlignment.Left
	hLabel.ZIndex = 4
	hLabel.Parent = header
	reg(hLabel, "TextColor3", "TextDim")

	local dotsLabel = Instance.new("TextLabel")
	dotsLabel.Position = UDim2.new(0, 70, 0, 0)
	dotsLabel.Size = UDim2.new(0, 24, 1, 0)
	dotsLabel.BackgroundTransparency = 1
	dotsLabel.Text = ""
	dotsLabel.Font = Theme.Font
	dotsLabel.TextSize = 12
	dotsLabel.TextXAlignment = Enum.TextXAlignment.Left
	dotsLabel.ZIndex = 4
	dotsLabel.Parent = header
	reg(dotsLabel, "TextColor3", "TextFaint")

	local chevron = Instance.new("ImageLabel")
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.new(1, -12, 0.5, 0)
	chevron.Size = UDim2.new(0, 13, 0, 13)
	chevron.BackgroundTransparency = 1
	chevron.Image = "rbxassetid://10709790644"
	chevron.Rotation = 180
	chevron.ZIndex = 4
	chevron.Parent = header
	reg(chevron, "ImageColor3", "TextFaint")

	local body = Instance.new("Frame")
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.LayoutOrder = 1
	body.Visible = true
	body.ZIndex = 3
	body.Parent = card

	local bodyText = Instance.new("TextLabel")
	bodyText.Position = UDim2.new(0, 12, 0, 0)
	bodyText.Size = UDim2.new(1, -24, 0, 0)
	bodyText.AutomaticSize = Enum.AutomaticSize.Y
	bodyText.BackgroundTransparency = 1
	bodyText.Text = ""
	bodyText.Font = Theme.FontMono
	bodyText.TextSize = 11
	bodyText.TextWrapped = true
	bodyText.TextXAlignment = Enum.TextXAlignment.Left
	bodyText.RichText = true
	bodyText.ZIndex = 4
	bodyText.Parent = body
	reg(bodyText, "TextColor3", "TextFaint")
	local bp = Instance.new("UIPadding")
	bp.PaddingBottom = UDim.new(0, 12)
	bp.Parent = body

	local expanded = true
	local function toggle()
		expanded = not expanded
		body.Visible = expanded
		tw(chevron, {Rotation = expanded and 180 or 0}, 0.2)
		task.defer(function()
			if scroll and scroll.Parent then scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y) end
		end)
	end
	track(header.MouseButton1Click:Connect(toggle))
	track(header.MouseEnter:Connect(function() tw(card, {BackgroundColor3 = Theme.Element}, 0.15) end))
	track(header.MouseLeave:Connect(function() tw(card, {BackgroundColor3 = Theme.Secondary}, 0.15) end))

	card.BackgroundTransparency = 1

	genSpawn(function()
		tw(card, {BackgroundTransparency = 0}, 0.25)

		local len = #text
		local i = 0
		local tick = 0
		while alive and i < len do
			if chatId ~= nil and chatId ~= currentChatId then
				if wrap and wrap.Parent then wrap:Destroy() end
				if onComplete then onComplete() end
				return
			end
			i = EX.advanceUTF8(text, i, 22)
			bodyText.Text = escapeRich(text:sub(1, i))
			tick = (tick + 1) % 4
			dotsLabel.Text = ("."):rep(tick)
			if scroll and scroll.Parent then
				scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
			end
			task.wait(0.008)
		end
		if not alive then return end
		bodyText.Text = escapeRich(text)
		dotsLabel.Text = ""
		hLabel.Text = "Thought process"

		task.wait(0.5)
		if alive and expanded then toggle() end
		if onComplete then onComplete() end
	end, chatId)
end
local function addToolCall(opts)
	if not alive then return end
	local HEADER_H = 38

	local wrap = Instance.new("Frame")
	wrap.Size = UDim2.new(1, 0, 0, 0)
	wrap.AutomaticSize = Enum.AutomaticSize.Y
	wrap.BackgroundTransparency = 1
	wrap.LayoutOrder = msgOrder
	msgOrder += 1
	wrap.ZIndex = 2
	wrap.Parent = scroll

	local card = Instance.new("Frame")
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(0, 280, 0, HEADER_H)
	card.Position = UDim2.new(0, 0, 0, 0)
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.ZIndex = 2
	card.Parent = wrap
	reg(card, "BackgroundColor3", "Element")
	corner(card, 10)
	regStroke(card, "StrokeSecond", 1)

	local cardList = Instance.new("UIListLayout")
	cardList.SortOrder = Enum.SortOrder.LayoutOrder
	cardList.Parent = card

	local header = Instance.new("TextButton")
	header.Size = UDim2.new(1, 0, 0, HEADER_H)
	header.BackgroundTransparency = 1
	header.Text = ""
	header.AutoButtonColor = false
	header.LayoutOrder = 0
	header.ZIndex = 3
	header.Parent = card

	local toolIcon = Instance.new("ImageLabel")
	toolIcon.AnchorPoint = Vector2.new(0, 0.5)
	toolIcon.Position = UDim2.new(0, 12, 0.5, 0)
	toolIcon.Size = UDim2.new(0, 15, 0, 15)
	toolIcon.BackgroundTransparency = 1
	toolIcon.Image = "rbxassetid://10709769202"
	toolIcon.ZIndex = 4
	toolIcon.Parent = header
	reg(toolIcon, "ImageColor3", "TextDim")

	local nameL = Instance.new("TextLabel")
	nameL.Position = UDim2.new(0, 36, 0, 0)
	nameL.Size = UDim2.new(1, -90, 1, 0)
	nameL.BackgroundTransparency = 1
	nameL.Text = opts.title or opts.name or "tool_call"
	nameL.Font = Theme.FontBold
	nameL.TextSize = 13
	nameL.TextXAlignment = Enum.TextXAlignment.Left
	nameL.TextTruncate = Enum.TextTruncate.AtEnd
	nameL.ZIndex = 4
	nameL.Parent = header
	reg(nameL, "TextColor3", "Text")

	local statusIcon = Instance.new("ImageLabel")
	statusIcon.AnchorPoint = Vector2.new(1, 0.5)
	statusIcon.Position = UDim2.new(1, -34, 0.5, 0)
	statusIcon.Size = UDim2.new(0, 13, 0, 13)
	statusIcon.BackgroundTransparency = 1
	statusIcon.Image = "rbxassetid://10747384394"
	statusIcon.ZIndex = 4
	statusIcon.Parent = header
	reg(statusIcon, "ImageColor3", "TextFaint")

	local chevron = Instance.new("ImageLabel")
	chevron.AnchorPoint = Vector2.new(1, 0.5)
	chevron.Position = UDim2.new(1, -12, 0.5, 0)
	chevron.Size = UDim2.new(0, 14, 0, 14)
	chevron.BackgroundTransparency = 1
	chevron.Image = "rbxassetid://10709790644"
	chevron.Rotation = 0
	chevron.ZIndex = 4
	chevron.Parent = header
	reg(chevron, "ImageColor3", "TextFaint")

	local body = Instance.new("Frame")
	body.Size = UDim2.new(1, 0, 0, 0)
	body.AutomaticSize = Enum.AutomaticSize.Y
	body.BackgroundTransparency = 1
	body.LayoutOrder = 1
	body.Visible = false
	body.ZIndex = 3
	body.Parent = card

	local bodyDivider = Instance.new("Frame")
	bodyDivider.Size = UDim2.new(1, -24, 0, 1)
	bodyDivider.Position = UDim2.new(0, 12, 0, 0)
	bodyDivider.BorderSizePixel = 0
	bodyDivider.ZIndex = 3
	bodyDivider.Parent = body
	reg(bodyDivider, "BackgroundColor3", "StrokeSecond")

	local pill = Instance.new("TextLabel")
	pill.Position = UDim2.new(0, 12, 0, 10)
	pill.Size = UDim2.new(0, 56, 0, 20)
	pill.Text = opts.label or "Script"
	pill.Font = Theme.FontMono
	pill.TextSize = 11
	pill.ZIndex = 4
	pill.Parent = body
	reg(pill, "BackgroundColor3", "Secondary")
	reg(pill, "TextColor3", "TextDim")
	corner(pill, 6)

	local detail = Instance.new("TextLabel")
	detail.Position = UDim2.new(0, 12, 0, 38)
	detail.Size = UDim2.new(1, -24, 0, 0)
	detail.AutomaticSize = Enum.AutomaticSize.Y
	detail.BackgroundTransparency = 1
	detail.Text = opts.detail or ""
	detail.Font = Theme.FontMono
	detail.TextSize = 12
	detail.TextWrapped = true
	detail.TextXAlignment = Enum.TextXAlignment.Left
	detail.ZIndex = 4
	detail.Parent = body
	reg(detail, "TextColor3", "TextDim")

	local bodyPad = Instance.new("Frame")
	bodyPad.Size = UDim2.new(1, 0, 0, 12)
	bodyPad.Position = UDim2.new(0, 0, 1, 0)
	bodyPad.BackgroundTransparency = 1
	bodyPad.ZIndex = 3
	bodyPad.Parent = body

	local detailPad = Instance.new("UIPadding")
	detailPad.PaddingBottom = UDim.new(0, 14)
	detailPad.Parent = body

	local expanded = false
	local function toggle()
		expanded = not expanded
		body.Visible = expanded
		tw(chevron, {Rotation = expanded and 180 or 0}, 0.2)
		task.defer(function()
			if scroll and scroll.Parent then
				scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
			end
		end)
	end
	track(header.MouseButton1Click:Connect(toggle))
	track(header.MouseEnter:Connect(function() tw(card, {BackgroundColor3 = Theme.ElementHover}, 0.15) end))
	track(header.MouseLeave:Connect(function() tw(card, {BackgroundColor3 = Theme.Element}, 0.15) end))

	local running = true
	spawn_(function()
		while alive and running and card.Parent do
			tw(statusIcon, {Rotation = statusIcon.Rotation + 90}, 0.25, Enum.EasingStyle.Linear)
			task.wait(0.25)
		end
	end)

	card.BackgroundTransparency = 1
	task.defer(function()
		if not card or not card.Parent then return end
		tw(card, {BackgroundTransparency = 0}, 0.3)
		if scroll and scroll.Parent then
			task.wait(0.04)
			scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y)
		end
	end)

	return {
		setDone = function()
			running = false
			statusIcon.Image = "rbxassetid://10709784998"
			statusIcon.Rotation = 0
			reg(statusIcon, "ImageColor3", "Online")
			statusIcon.ImageColor3 = Theme.Online
		end,
		setDetail = function(t)
			detail.Text = t
		end,
		setError = function()
			running = false
			statusIcon.Image = "rbxassetid://10709784998"
			statusIcon.Rotation = 0
			statusIcon.ImageColor3 = Theme.Danger
		end,
		setName = function(t)
			nameL.Text = t
		end,

		streamTitle = function(t)
			t = tostring(t or "")
			nameL.Text = ""
			task.spawn(function()
				local i = 0
				while alive and i < #t and nameL and nameL.Parent do
					i = EX.advanceUTF8(t, i, 1)
					nameL.Text = t:sub(1, i)
					task.wait(0.012)
				end
				if nameL and nameL.Parent then nameL.Text = t end
			end)
		end,
		expand = function(force)
			if type(force) == "boolean" then expanded = not force end
			toggle()
		end,
		setApprovalVisible = function(visible)
			local offset = visible and 42 or 0
			pill.Position = UDim2.new(0, 12, 0, 10 + offset)
			detail.Position = UDim2.new(0, 12, 0, 38 + offset)
		end,
		card = card,
		body = body,
	}
end

local function awaitApproval(toolCard, isCancelled)
	local decision = nil
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, -24, 0, 32)
	bar.Position = UDim2.new(0, 12, 0, 10)
	bar.BackgroundTransparency = 1
	bar.LayoutOrder = 5
	bar.ZIndex = 4
	bar.Parent = toolCard.body
	toolCard.expand(true)
	toolCard.setApprovalVisible(true)

	local function mkBtn(text, xScale, color, val)
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(0, 0.5)
		b.Position = UDim2.new(xScale, 0, 0.5, 0)
		b.Size = UDim2.new(0.48, -4, 0, 26)
		b.BorderSizePixel = 0
		b.Text = text
		b.Font = Theme.FontBold
		b.TextSize = 12
		b.TextColor3 = Color3.fromRGB(255,255,255)
		b.AutoButtonColor = false
		b.ZIndex = 5
		b.BackgroundColor3 = color
		b.Parent = bar
		corner(b, 7)
		track(b.MouseButton1Click:Connect(function() decision = val end))
		return b
	end
	mkBtn("Approve", 0, Theme.Online, "approve")
	mkBtn("Deny", 0.52, Theme.Danger, "deny")

	return function()
		while decision == nil and alive and bar.Parent and toolCard.card.Parent and not (isCancelled and isCancelled()) do task.wait(0.05) end
		bar:Destroy()
		toolCard.setApprovalVisible(false)
		return decision or "deny"
	end
end

local function awaitPlanApproval(isCancelled)
	local decision = nil
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, -24, 0, 34)
	row.BackgroundTransparency = 1
	row.LayoutOrder = msgOrder
	msgOrder = msgOrder + 1
	row.ZIndex = 2
	row.Parent = scroll
	local function mkBtn(text, xScale, color, val)
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(0, 0.5)
		b.Position = UDim2.new(xScale, 0, 0.5, 0)
		b.Size = UDim2.new(0.5, -6, 0, 28)
		b.BorderSizePixel = 0
		b.Text = text
		b.Font = Theme.FontBold
		b.TextSize = 12
		b.TextColor3 = Color3.fromRGB(255,255,255)
		b.AutoButtonColor = false
		b.ZIndex = 3
		b.BackgroundColor3 = color
		b.Parent = row
		corner(b, 7)
		track(b.MouseButton1Click:Connect(function() decision = val end))
		return b
	end
	mkBtn("Approve plan", 0, Theme.Online, "approve")
	mkBtn("Deny", 0.5, Theme.Danger, "deny")
	task.defer(function() if scroll and scroll.Parent then scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y) end end)
	return function()
		while decision == nil and alive and row.Parent and not (isCancelled and isCancelled()) do task.wait(0.05) end
		if row and row.Parent then row:Destroy() end
		return decision or "deny"
	end
end

local tWrap = Instance.new("Frame")
tWrap.Size = UDim2.new(1, 0, 0, 34)
tWrap.BackgroundTransparency = 1
tWrap.Visible = false
tWrap.LayoutOrder = 999999
tWrap.ZIndex = 2
tWrap.Parent = scroll
local tBub = Instance.new("Frame")
tBub.Size = UDim2.new(0, 70, 0, 34)
tBub.BorderSizePixel = 0
tBub.ZIndex = 2
tBub.Parent = tWrap
reg(tBub, "BackgroundColor3", "Element")
corner(tBub, 12)
regStroke(tBub, "StrokeSecond", 1)
local dots = {}
for i=1,3 do
	local d = Instance.new("Frame")
	d.Size = UDim2.new(0,7,0,7)
	d.Position = UDim2.new(0, 14 + (i-1)*15, 0.5, -3.5)
	d.BackgroundColor3 = Theme.TextFaint
	d.BorderSizePixel = 0
	d.ZIndex = 3
	d.Parent = tBub
	corner(d, 4)
	dots[i] = d
end
spawn_(function()
	local idx = 1
	while alive do
		task.wait(0.35)
		if not alive then break end
		if tWrap.Visible then
			for i,d in pairs(dots) do
				tw(d, {BackgroundColor3 = i==idx and Theme.AccentBright or Theme.TextFaint, Size = i==idx and UDim2.new(0,9,0,9) or UDim2.new(0,7,0,7)}, 0.2, Enum.EasingStyle.Quad)
			end
			idx = idx % 3 + 1
		end
	end
end)

local Footer = Instance.new("Frame")
Footer.Name = "Footer"
Footer.Size = UDim2.new(1, 0, 0, FOOTER_H)
Footer.Position = UDim2.new(0, 0, 1, -FOOTER_H)
Footer.BorderSizePixel = 0
Footer.ZIndex = 3
Footer.Active = true
Footer.Parent = ChatPage
reg(Footer, "BackgroundColor3", "Topbar")
corner(Footer, 12)

local ftRepair = Instance.new("Frame")
ftRepair.Size = UDim2.new(1, 0, 0, 12)
ftRepair.BorderSizePixel = 0
ftRepair.ZIndex = 3
ftRepair.Parent = Footer
reg(ftRepair, "BackgroundColor3", "Topbar")

local ftDivider = Instance.new("Frame")
ftDivider.Size = UDim2.new(1, 0, 0, 1)
ftDivider.Position = UDim2.new(0, 0, 0, 0)
ftDivider.BackgroundTransparency = 0.4
ftDivider.BorderSizePixel = 0
ftDivider.ZIndex = 4
ftDivider.Parent = Footer
reg(ftDivider, "BackgroundColor3", "Stroke")

local field = Instance.new("TextBox")
field.Size = UDim2.new(1, -64, 0, 36)
field.Position = UDim2.new(0, 14, 0.5, -18)
field.BorderSizePixel = 0
field.PlaceholderText = "Ask anything..."
field.Text = ""
field.Font = Theme.Font
field.TextSize = 13
field.ClearTextOnFocus = false
field.ClipsDescendants = true
field.TextXAlignment = Enum.TextXAlignment.Left
field.ZIndex = 5
field.Parent = Footer
reg(field, "BackgroundColor3", "Element")
reg(field, "PlaceholderColor3", "Placeholder")
reg(field, "TextColor3", "Text")
corner(field, 10)
local fStroke = regStroke(field, "StrokeSecond", 1)
pad(field, 0, 0, 12, 12)
track(field.Focused:Connect(function() tw(field, {BackgroundColor3 = Theme.ElementHover}, 0.2) end))
track(field.FocusLost:Connect(function(enter) tw(field, {BackgroundColor3 = Theme.Element}, 0.2); if enter then sendMessage() end end))

local send = Instance.new("TextButton")
send.Size = UDim2.new(0, 36, 0, 36)
send.Position = UDim2.new(1, -50, 0.5, -18)
send.BorderSizePixel = 0
send.Text = ""
send.AutoButtonColor = false
send.ZIndex = 5
send.Parent = Footer
reg(send, "BackgroundColor3", "AccentDeep")
corner(send, 10)

local sendIcon = Instance.new("ImageLabel")
sendIcon.AnchorPoint = Vector2.new(0.5, 0.5)
sendIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
sendIcon.Size = UDim2.new(0, 18, 0, 18)
sendIcon.BackgroundTransparency = 1
sendIcon.Image = "rbxassetid://10709790948"
sendIcon.ImageColor3 = Color3.fromRGB(255, 255, 255)
sendIcon.ZIndex = 6
sendIcon.Parent = send

local stopSquare = Instance.new("Frame")
stopSquare.AnchorPoint = Vector2.new(0.5, 0.5)
stopSquare.Position = UDim2.new(0.5, 0, 0.5, 0)
stopSquare.Size = UDim2.new(0, 11, 0, 11)
stopSquare.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
stopSquare.BorderSizePixel = 0
stopSquare.Visible = false
stopSquare.ZIndex = 6
stopSquare.Parent = send
corner(stopSquare, 2)

local setBusy

-- Every announced call needs a result, including calls interrupted by Stop or
-- an exception. Repair interrupted saved turns before they reach another API.
function EX.finishPendingTools(messages, reason)
	local repaired, pending = {}, {}
	local function finish()
		for _, call in ipairs(pending) do
			if not call.done then
				repaired[#repaired + 1] = { role = "tool", tool_name = call.name,
					tool_call_id = call.id, content = reason, is_error = true }
			end
		end
		pending = {}
	end
	for _, message in ipairs(messages) do
		if message.role ~= "tool" then finish() end
		if message.role == "assistant" and type(message.tool_calls) == "table" then
			for _, call in ipairs(message.tool_calls) do
				if type(call) == "table" and type(call["function"]) == "table" then
					if type(call.id) ~= "string" or call.id == "" then call.id = "recovered_" .. newChatId() end
					pending[#pending + 1] = { id = call.id, name = call["function"].name }
				end
			end
		elseif message.role == "tool" then
			local matched = false
			for _, call in ipairs(pending) do
				if not call.done and (message.tool_call_id == call.id or (not message.tool_call_id and message.tool_name == call.name)) then
					message.tool_call_id = call.id
					call.done, matched = true, true
					break
				end
			end
			if not matched then
				finish()
				message = { role = "user", content = "[Recovered tool result " .. tostring(message.tool_name or "unknown") .. "]\n" .. tostring(message.content or "") }
			end
		end
		repaired[#repaired + 1] = message
	end
	finish()
	table.clear(messages)
	for i, message in ipairs(repaired) do messages[i] = message end
end

for _, convo in ipairs(conversations) do
	EX.finishPendingTools(convo.messages, "The previous run ended before this tool returned a result.")
end

function EX.runToolBatch(calls, messages, chatId, isCancelled, viewing)
	for _, call in ipairs(calls) do
		local fn = call["function"] or {}
		local name = fn.name or "unknown"
		local args, argError = AT.decodeToolArguments(fn.arguments)
		local result, success, card
		if isCancelled() then
			result, success = "Cancelled before this tool could execute.", false
		elseif argError or call.arguments_error then
			result, success = "Invalid tool arguments: " .. tostring(argError or call.arguments_error) .. ". Send one complete JSON object and retry.", false
		else
			if viewing() then
				local ok, detail = pcall(function() return AT.http:JSONEncode(args) end)
				card = addToolCall({ name = name, title = toolTitle(name, args), detail = name == "run_luau" and tostring(args.code or "") or (ok and detail or "") })
				EX.pendingCards[chatId] = card
			end
			local approved = not toolNeedsApproval(name)
			if not approved and viewing() and card then
				approved = awaitApproval(card, function() return isCancelled() or not viewing() end)() == "approve"
			end
			if isCancelled() then
				result, success = "Cancelled before this tool could execute.", false
			elseif not approved then
				result, success = "Tool was not approved. Ask the user before retrying this action.", false
			else
				result, success = executeToolCall(name, args)
			end
		end
		result = tostring(result or "(no output)")
		-- Save the result before touching UI that might have been destroyed while
		-- the tool yielded. A display failure must never repeat an executed action.
		messages[#messages + 1] = { role = "tool", tool_name = name, tool_call_id = call.id, content = result, is_error = success == false }
		saveChats()
		EX.pendingCards[chatId] = nil
		if card then
			pcall(function()
				if success == false then card.setError() else card.setDone() end
				card.setDetail(result)
			end)
		end
	end
end

local function refreshBusyVisuals()
	local isBusy = busyChats[currentChatId] == true
	thinking = isBusy
	field.TextEditable = not isBusy
	send.Active = true
	if isBusy then
		sendIcon.Visible = false
		stopSquare.Visible = true
		tw(send, {BackgroundColor3 = Theme.Danger}, 0.15)
		field.PlaceholderText = "Generating…"
	else
		stopSquare.Visible = false
		sendIcon.Visible = true
		sendIcon.ImageTransparency = 0
		tw(send, {BackgroundColor3 = Theme.AccentDeep}, 0.15)
		field.PlaceholderText = "Ask anything..."
	end
end

local function stopGeneration(chatId)
	local self = coroutine.running()
	chatId = chatId or currentChatId
	busyChats[chatId] = nil
	EX.chatRuns[chatId] = (EX.chatRuns[chatId] or 0) + 1
	local list = genThreadsByChat[chatId]
	if list then
		for _, t in pairs(list) do
			if t ~= self then pcall(task.cancel, t) end
			for _, tracked in ipairs({ genThreads, threads }) do
				local index = table.find(tracked, t)
				if index then table.remove(tracked, index) end
			end
			EX.threadChat[t] = nil
		end
		genThreadsByChat[chatId] = nil
	end
	pcall(killAllProcesses, chatId)
	pcall(killAllSubagents, chatId)
	if EX.stopRemoteCapture then EX.stopRemoteCapture(chatId) end
	for _, convo in ipairs(conversations) do
		if convo.id == chatId then EX.finishPendingTools(convo.messages, "Cancelled by the user; this call has no completed result.") end
	end
	local card = EX.pendingCards[chatId]
	if card then pcall(card.setError); pcall(card.setDetail, "Cancelled by the user.") end
	EX.pendingCards[chatId] = nil
	if EX.cancelWarning then EX.cancelWarning(chatId) end
	if chatId == currentChatId and tWrap then tWrap.Visible = false end
	saveChats()
	if flushChatsNow then pcall(flushChatsNow) end
	refreshBusyVisuals()
end

function setBusy(state, chatId)
	chatId = chatId or currentChatId
	if state then busyChats[chatId] = true else busyChats[chatId] = nil end
	if chatId == currentChatId then
		refreshBusyVisuals()
	end
	-- when a turn finishes, persist now instead of waiting out the debounce
	if not state and chatId == currentChatId then tWrap.Visible = false end
	if not state and flushChatsNow then pcall(flushChatsNow) end
end

track(send.MouseEnter:Connect(function()
	tw(send, {BackgroundColor3 = thinking and Color3.fromRGB(235, 90, 90) or Theme.Accent}, 0.15)
end))
track(send.MouseLeave:Connect(function()
	tw(send, {BackgroundColor3 = thinking and Theme.Danger or Theme.AccentDeep}, 0.15)
end))

local responses = {
	"I'd execute that but I'm just a dummy response.",
	"Interesting request. Imagine I did something cool.",
	"Script generated successfully. *(not really)*",
	"Processing... done! *(I did nothing)*",
	"That would require actual AI. **Soon™**",
	"Generating Luau... just kidding.",
	"I parsed your intent as **'do something awesome'**.",
	"RemoteEvent fired. Target hit. *(in my dreams)*",
	"Scanned 847 instances. Found nothing. Classic.",
	"Task queued. ETA: heat death of the universe.",
	"Wrote 14 lines of Luau. All ~~right~~ **wrong**.",
	"I would help but I'm literally a dummy.",
}

local MARKDOWN_DEMO = table.concat({
	"# Heading 1",
	"## Heading 2",
	"### Heading 3",
	"#### Heading 4",
	"##### Heading 5",
	"###### Heading 6",
	"",
	"Normal text with **bold**, *italic*, _also italic_, and ~~strikethrough~~.",
	"We also have `inline code` and [a link](https://example.com).",
	"",
	"> This is a blockquote.",
	"> With multiple lines.",
	"",
	"## Unordered List",
	"- Item one",
	"- Item two",
	"  - Nested item A",
	"  - Nested item B",
	"- Item three",
	"",
	"## Ordered List",
	"1. First item",
	"2. Second item",
	"  1. Nested first",
	"  2. Nested second",
	"3. Third item",
	"",
	"## Task List",
	"- [x] Completed task",
	"- [ ] Incomplete task",
	"- [x] Another completed task",
	"",
	"## Code Block",
	"```js",
	"function greet(name) {",
	"  console.log(`Hello, ${name}!`);",
	"}",
	"greet('World');",
	"```",
	"",
	"## Horizontal Rule",
	"---",
	"",
	"## Mixed Formatting",
	"You can combine **bold and *italic* text** inside a single sentence.",
}, "\n")

local maybeTitleConversation

local exploitOverlay = Instance.new("Frame")
exploitOverlay.Name = "ExploitOverlay"
exploitOverlay.Size = UDim2.new(1, 0, 1, 0)
exploitOverlay.BackgroundTransparency = 1
exploitOverlay.BorderSizePixel = 0
exploitOverlay.ZIndex = 50
exploitOverlay.Visible = false
exploitOverlay.Active = true
exploitOverlay.Parent = Main
reg(exploitOverlay, "BackgroundColor3", "Background")

local exploitDecision = nil

local sheet = Instance.new("Frame")
sheet.Name = "Sheet"
sheet.AnchorPoint = Vector2.new(0.5, 1)
sheet.Position = UDim2.new(0.5, 0, 1, 120)
sheet.Size = UDim2.new(1, -16, 0, 0)
sheet.AutomaticSize = Enum.AutomaticSize.Y
sheet.BorderSizePixel = 0
sheet.ZIndex = 51
sheet.Parent = exploitOverlay
reg(sheet, "BackgroundColor3", "Element")
corner(sheet, 14)
regStroke(sheet, "StrokeSecond", 1)
shPad = Instance.new("UIPadding")
shPad.PaddingTop = UDim.new(0, 16); shPad.PaddingBottom = UDim.new(0, 16)
shPad.PaddingLeft = UDim.new(0, 16); shPad.PaddingRight = UDim.new(0, 16)
shPad.Parent = sheet
shList = Instance.new("UIListLayout")
shList.SortOrder = Enum.SortOrder.LayoutOrder
shList.Padding = UDim.new(0, 10)
shList.Parent = sheet

local shHead = Instance.new("Frame")
shHead.Size = UDim2.new(1, 0, 0, 20)
shHead.BackgroundTransparency = 1
shHead.LayoutOrder = 0
shHead.ZIndex = 52
shHead.Parent = sheet
local shDot = Instance.new("Frame")
shDot.AnchorPoint = Vector2.new(0, 0.5)
shDot.Position = UDim2.new(0, 0, 0.5, 0)
shDot.Size = UDim2.new(0, 8, 0, 8)
shDot.BackgroundColor3 = Color3.fromRGB(240, 170, 60)
shDot.BorderSizePixel = 0
shDot.ZIndex = 53
shDot.Parent = shHead
corner(shDot, 4)
local shTitle = Instance.new("TextLabel")
shTitle.AnchorPoint = Vector2.new(0, 0.5)
shTitle.Position = UDim2.new(0, 18, 0.5, 0)
shTitle.Size = UDim2.new(1, -18, 1, 0)
shTitle.BackgroundTransparency = 1
shTitle.Text = "Heads up — this could get you banned"
shTitle.Font = Theme.FontBold
shTitle.TextSize = 14
shTitle.TextXAlignment = Enum.TextXAlignment.Left
shTitle.ZIndex = 53
shTitle.Parent = shHead
reg(shTitle, "TextColor3", "Text")

local shBody = Instance.new("TextLabel")
shBody.Size = UDim2.new(1, 0, 0, 0)
shBody.AutomaticSize = Enum.AutomaticSize.Y
shBody.BackgroundTransparency = 1
shBody.Text = "Running this could permanently ban your account. If you want to test exploits, use an alt you don't care about — not your main."
shBody.Font = Theme.Font
shBody.TextSize = 12
shBody.TextWrapped = true
shBody.TextXAlignment = Enum.TextXAlignment.Left
shBody.LayoutOrder = 1
shBody.ZIndex = 52
shBody.Parent = sheet
reg(shBody, "TextColor3", "TextDim")

local shBtns = Instance.new("Frame")
shBtns.Size = UDim2.new(1, 0, 0, 34)
shBtns.BackgroundTransparency = 1
shBtns.LayoutOrder = 2
shBtns.ZIndex = 52
shBtns.Parent = sheet

local shLeave = Instance.new("TextButton")
shLeave.Size = UDim2.new(0.5, -5, 1, 0)
shLeave.Position = UDim2.new(0, 0, 0, 0)
shLeave.BorderSizePixel = 0
shLeave.Text = "Leave · use alt"
shLeave.Font = Theme.FontBold
shLeave.TextSize = 12
shLeave.AutoButtonColor = false
shLeave.ZIndex = 53
shLeave.Parent = shBtns
reg(shLeave, "BackgroundColor3", "Element")
reg(shLeave, "TextColor3", "TextDim")
corner(shLeave, 8)
regStroke(shLeave, "StrokeSecond", 1)
track(shLeave.MouseEnter:Connect(function() tw(shLeave, {BackgroundColor3 = Theme.ElementHover}, 0.15) end))
track(shLeave.MouseLeave:Connect(function() tw(shLeave, {BackgroundColor3 = Theme.Element}, 0.15) end))
track(shLeave.MouseButton1Click:Connect(function() exploitDecision = "leave" end))

local shConfirm = Instance.new("TextButton")
shConfirm.Size = UDim2.new(0.5, -5, 1, 0)
shConfirm.Position = UDim2.new(0.5, 5, 0, 0)
shConfirm.BorderSizePixel = 0
shConfirm.Text = "Continue anyway"
shConfirm.Font = Theme.FontBold
shConfirm.TextSize = 12
shConfirm.TextColor3 = Color3.fromRGB(255,255,255)
shConfirm.AutoButtonColor = false
shConfirm.ZIndex = 53
shConfirm.Parent = shBtns
reg(shConfirm, "BackgroundColor3", "AccentDeep")
corner(shConfirm, 8)
track(shConfirm.MouseEnter:Connect(function() tw(shConfirm, {BackgroundColor3 = Theme.Accent}, 0.15) end))
track(shConfirm.MouseLeave:Connect(function() tw(shConfirm, {BackgroundColor3 = Theme.AccentDeep}, 0.15) end))
local confirmClicks = 0
local CONFIRM_REQUIRED = 5
track(shConfirm.MouseButton1Click:Connect(function()
	confirmClicks = confirmClicks + 1
	if confirmClicks >= CONFIRM_REQUIRED then
		exploitDecision = "confirm"
	else
		shConfirm.Text = "Continue anyway (" .. confirmClicks .. "/" .. CONFIRM_REQUIRED .. ")"

		tw(shConfirm, {BackgroundColor3 = Theme.Accent}, 0.08)
		task.delay(0.08, function()
			if shConfirm and shConfirm.Parent then tw(shConfirm, {BackgroundColor3 = Theme.AccentDeep}, 0.12) end
		end)
	end
end))

function EX.cancelWarning(chatId)
	if EX.warningChat == chatId then
		exploitDecision = "cancelled"
		EX.warningOpen = false
		EX.warningChat = nil
		exploitOverlay.Visible = false
	end
end

function EX.onGenerationError(chatId, err)
	if not chatId then return end
	stopGeneration(chatId)
	if chatId == currentChatId then addMessage("**Generation stopped:** " .. tostring(err), "system") end
end

local function showExploitWarning()
	local owner = EX.threadChat[coroutine.running()] or currentChatId
	if owner ~= currentChatId or EX.warningOpen then return "cancelled" end
	EX.warningOpen = true
	EX.warningChat = owner
	exploitDecision = nil
	confirmClicks = 0
	shConfirm.Text = "Continue anyway"
	shConfirm.BackgroundColor3 = Theme.AccentDeep
	exploitOverlay.Visible = true
	exploitOverlay.BackgroundTransparency = 1
	sheet.Position = UDim2.new(0.5, 0, 1, 120)

	tw(exploitOverlay, {BackgroundTransparency = 0.45}, 0.2)
	tw(sheet, {Position = UDim2.new(0.5, 0, 1, -8)}, 0.28, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	while exploitDecision == nil and alive and owner == currentChatId do task.wait(0.05) end
	EX.warningOpen = false
	EX.warningChat = nil
	if not alive or owner ~= currentChatId then
		exploitOverlay.Visible = false
		return "cancelled"
	end

	tw(exploitOverlay, {BackgroundTransparency = 1}, 0.2)
	tw(sheet, {Position = UDim2.new(0.5, 0, 1, 120)}, 0.22, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
	task.wait(0.24)
	exploitOverlay.Visible = false
	return exploitDecision or "leave"
end

-- Small modal asking whether to re-run from an edited user message or just save.
-- Returns "rerun" or "save". Built fresh each call and destroyed after.
local function askEditChoice()
	local choice = nil
	local ov = Instance.new("Frame")
	ov.Size = UDim2.new(1, 0, 1, 0)
	ov.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	ov.BackgroundTransparency = 0.5
	ov.BorderSizePixel = 0
	ov.ZIndex = 60
	ov.Active = true
	ov.Parent = Main
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.new(0.5, 0, 0.5, 0)
	card.Size = UDim2.new(0.8, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BorderSizePixel = 0
	card.ZIndex = 61
	card.Parent = ov
	reg(card, "BackgroundColor3", "Element")
	corner(card, 12)
	regStroke(card, "StrokeSecond", 1)
	pad(card, 16, 16, 16, 16)
	local cl = Instance.new("UIListLayout")
	cl.SortOrder = Enum.SortOrder.LayoutOrder
	cl.Padding = UDim.new(0, 12)
	cl.Parent = card
	local q = Instance.new("TextLabel")
	q.Size = UDim2.new(1, 0, 0, 0)
	q.AutomaticSize = Enum.AutomaticSize.Y
	q.BackgroundTransparency = 1
	q.Text = "You edited this message. Re-run the conversation from here, or just save the edit?"
	q.Font = Theme.Font
	q.TextSize = 13
	q.TextWrapped = true
	q.TextXAlignment = Enum.TextXAlignment.Left
	q.LayoutOrder = 0
	q.ZIndex = 62
	q.Parent = card
	reg(q, "TextColor3", "Text")
	local rowb = Instance.new("Frame")
	rowb.Size = UDim2.new(1, 0, 0, 34)
	rowb.BackgroundTransparency = 1
	rowb.LayoutOrder = 1
	rowb.ZIndex = 62
	rowb.Parent = card
	local function mk(label, xs, accent, val)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0.48, 0, 1, 0)
		b.Position = UDim2.new(xs, 0, 0, 0)
		b.BorderSizePixel = 0
		b.Text = label
		b.Font = Theme.FontBold
		b.TextSize = 12
		b.TextColor3 = accent and Color3.fromRGB(255,255,255) or Theme.TextDim
		b.AutoButtonColor = false
		b.ZIndex = 63
		b.Parent = rowb
		corner(b, 8)
		if accent then reg(b, "BackgroundColor3", "AccentDeep") else reg(b, "BackgroundColor3", "Secondary") end
		track(b.MouseButton1Click:Connect(function() choice = val end))
		return b
	end
	mk("Save only", 0, false, "save")
	mk("Re-run", 0.52, true, "rerun")
	while choice == nil and alive do task.wait(0.05) end
	ov:Destroy()
	return choice or "save"
end

toolImpls.warn_exploit = function(args)
	local decision = showExploitWarning()
	if decision == "cancelled" then return "Warning was cancelled; no action was approved.", false end
	if decision == "leave" then
		pcall(function() game:GetService("TeleportService"):Teleport(game.PlaceId) end)
		pcall(function() Players.LocalPlayer:Kick("Switched to alt account.") end)
		return "User chose to leave and use an alt."
	end
	return "User acknowledged the risk and chose to continue."
end

local innerSendMessage
local loadConversation, refreshChatList

-- editing state for message actions: when set, the next send updates
-- history[index] instead of appending. Declared here (before sendMessage) so
-- it's in scope; the edit/regenerate ops that set it are defined later.
local editState = { msg = nil, role = nil, index = nil }

function sendMessage()
	if not alive or thinking then return end
	local text = field.Text
	if text:match("^%s*$") then return end
	field.Text = ""

	local genChatId = currentChatId
	local genConvo = activeConvo()
	local genMessages = genConvo and genConvo.messages or chatHistory

	-- Editing an existing message?
	if editState.msg then
		-- locate the stored message object in the current array (index-independent)
		local idx
		for j, m in ipairs(genMessages) do if m == editState.msg then idx = j break end end
		local role = editState.role
		editState.msg, editState.role, editState.index = nil, nil, nil
		if idx then
			genMessages[idx].content = text
			if role == "assistant" then
				saveChats()
				loadConversation(currentChatId)
				return
			else
				local choice = askEditChoice()  -- returns "rerun" | "save"
				if choice == "rerun" then
					for j = #genMessages, idx + 1, -1 do genMessages[j] = nil end
					saveChats()
					loadConversation(currentChatId)
					setBusy(true, genChatId)
					genSpawn(function()
						innerSendMessage(nil, genChatId, genConvo, genMessages)
					end, genChatId)
				else
					saveChats()
					loadConversation(currentChatId)
				end
				return
			end
		end
		-- if the message vanished, fall through and send as a new message
	end

	-- Slash commands handled locally (not sent to the model, not stored as chat).
	-- These supplement the model-side /markdown /tooltest /thinktest demos.
	do
		local cmd = text:match("^%s*/(%S+)%s*(.-)%s*$")
		if cmd then
			local rest = text:match("^%s*/%S+%s+(.-)%s*$") or ""
			local lc = cmd:lower()
			if lc == "help" or lc == "commands" then
				addMessage("**Commands:** `/clear` (new chat), `/model [name]` (show or switch model), `/retry` (regenerate last reply), `/export` (copy this chat), `/markdown` `/tooltest` `/thinktest` (demos). Anything else is sent to the assistant.", "system")
				return
			elseif lc == "clear" or lc == "new" then
				createConversation()
				loadConversation(currentChatId)
				if refreshChatList then pcall(refreshChatList) end
				return
			elseif lc == "retry" then
				-- find the last assistant message and regenerate from it
				local lastA
				for j = #genMessages, 1, -1 do
					if type(genMessages[j]) == "table" and genMessages[j].role == "assistant" then lastA = j; break end
				end
				if lastA and regenerateFrom then regenerateFrom(lastA)
				else addMessage("Nothing to retry yet — send a message first.", "system") end
				return
			elseif lc == "export" then
				local lines = {}
				for _, m in ipairs(genMessages) do
					if type(m) == "table" and (m.role == "user" or m.role == "assistant") and type(m.content) == "string" and m.content ~= "" then
						lines[#lines+1] = (m.role == "user" and "You: " or "Assistant: ") .. m.content
					end
				end
				local blob = table.concat(lines, "\n\n")
				local fn = setclipboard or toclipboard or (syn and syn.write_clipboard) or set_clipboard
				if type(fn) == "function" and blob ~= "" then
					pcall(fn, blob)
					addMessage("Copied this conversation to your clipboard (" .. #lines .. " messages).", "system")
				elseif blob == "" then
					addMessage("Nothing to export yet.", "system")
				else
					addMessage("Clipboard isn't available on this executor, so I can't export.", "system")
				end
				return
			elseif lc == "model" then
				if rest == "" then
					addMessage("Current model: **" .. tostring(apiModel) .. "** (provider: " .. curProvider().name .. "). Use `/model <name>` to switch, or pick one in Settings.", "system")
				else
					apiModel = rest
					if curProvider().isCustom then EX.customModel = rest end
					pcall(saveConfig)
					addMessage("Model set to **" .. tostring(apiModel) .. "** for this provider. (If it's not valid for " .. curProvider().name .. ", requests will error — check Settings.)", "system")
				end
				return
			end
			-- unknown slash word: fall through and send it to the model as normal text
		end
	end

	pcall(EX.resetTurnTokens)
	local ub = addMessage(text, "user")
	genMessages[#genMessages + 1] = { role = "user", content = text }
	saveChats()
	if ub then attachActions(ub.Parent, "user", text, #genMessages) end

	setBusy(true, genChatId)
	genSpawn(function()
		innerSendMessage(text, genChatId, genConvo, genMessages)
	end, genChatId)
end

innerSendMessage = function(text, genChatId, genConvo, genMessages)
	EX.chatRuns[genChatId] = (EX.chatRuns[genChatId] or 0) + 1
	local runId = EX.chatRuns[genChatId]
	local function isCancelled()
		return not alive or EX.chatRuns[genChatId] ~= runId or not busyChats[genChatId]
	end

	local function showDots()
		if genChatId == currentChatId then
			tWrap.Visible = true
			tWrap.LayoutOrder = msgOrder
			task.defer(function() if scroll and scroll.Parent then scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y) end end)
		end
	end
	local function hideDots()
		if genChatId == currentChatId then tWrap.Visible = false end
	end

	-- text is nil when regenerating / re-running from edited history: skip the
	-- slash-command checks and go straight to the agent loop on existing history.
	if type(text) == "string" then
	if text:match("^%s*/markdown%s*$") then
		setBusy(true, genChatId)
		showDots()
		genSpawn(function()
			task.wait(0.4)
			if not alive then return end
			hideDots()
			streamMessage(MARKDOWN_DEMO, function() setBusy(false, genChatId) end, genChatId)
		end, genChatId)
		return
	end

	if text:match("^%s*/tooltest%s*$") then
		setBusy(true, genChatId)
		showDots()
		genSpawn(function()
			task.wait(0.5)
			if not alive then return end
			hideDots()
			if genChatId ~= currentChatId then setBusy(false, genChatId); return end
			local tool = addToolCall({
				name = "run_luau",
				label = "Script",
				detail = "local p = Instance.new(\"Part\")\np.Anchored = true\np.Position = Vector3.new(0, 5, 0)\np.Parent = workspace\nreturn p.Name",
			})
			task.wait(1.6)
			if not alive or not tool then return end
			tool.setDone()
			task.wait(0.4)
			if not alive then return end
			streamMessage("Done. Spawned an anchored **Part** at `(0, 5, 0)` and returned its name.", function() setBusy(false, genChatId) end, genChatId)
		end, genChatId)
		return
	end

	if text:match("^%s*/thinktest%s*$") then
		setBusy(true, genChatId)
		showDots()
		genSpawn(function()
			task.wait(0.5)
			if not alive then return end
			hideDots()
			local demoThink = "The user wants me to demonstrate the thinking stream. Let me reason about this step by step.\n\nFirst, acknowledge what's being asked. Then produce a short answer. The reasoning trace streams in as dimmed monospace, then folds away once done — mirroring how reasoning models surface their chain of thought before the final reply."
			streamThinking(demoThink, function()
				streamMessage("Here's the answer after thinking it through. The reasoning above streamed in, then collapsed — click it to expand again.", function() setBusy(false, genChatId) end, genChatId)
			end, genChatId)
		end, genChatId)
		return
	end
	end  -- end string-text slash-command guard

	setBusy(true, genChatId)
	showDots()

	local ready = (curKey() ~= "") or (curProvider().isCustom and EX.normalizeBase(EX.customBase) ~= "" and tostring(apiModel) ~= "")
	if ready then

		genSpawn(function()
			local viewing = function() return genChatId == currentChatId end
			local handled, loopErr = pcall(function()

				if planMode then
					if viewing() then showDots() end
					local pok, planText = planFor(genMessages, isCancelled)
					if isCancelled() then return end
					if not pok or not planText or planText == "" then
						if viewing() then hideDots(); addMessage("**Plan failed:** " .. tostring(planText), "system") end
						setBusy(false, genChatId)
						return
					end
					if viewing() then hideDots() end
					if pok and planText and planText ~= "" then
						if viewing() then
							addMessage("**Plan:**\n" .. planText, "assistant")
							local waitDecision = awaitPlanApproval(function() return isCancelled() or not viewing() end)
							local decision = waitDecision()
							if decision ~= "approve" then
								addMessage("_Plan denied — nothing was executed._", "system")
								setBusy(false, genChatId)
								return
							end

							genMessages[#genMessages + 1] = { role = "system", content = "The user approved this plan. Execute it now using tools:\n" .. planText }
						else

							setBusy(false, genChatId)
							return
						end
					end
				end

				local stepCount = 0
				local errCount = 0
				local contCount = 0
				while true do
					if isCancelled() then return end

					stepCount = stepCount + 1
					if agentMaxSteps > 0 and stepCount > agentMaxSteps then
						if viewing() then addMessage("_Reached the step budget (" .. agentMaxSteps .. "). Stopping. Raise it in Settings if needed._", "system") end
						setBusy(false, genChatId)
						return
					end
					if viewing() then showDots() end
					local ok, msg = ollamaAgentStep(genMessages, isCancelled)
					if isCancelled() then return end
					if viewing() then hideDots() end
					if ok and msg then pcall(function() if viewing() then EX.addTurnTokens(msg, genMessages) end end) end
					-- Parse text-mode tool calls before cleaning text for display.
					-- The scrubber removes <tool_call> markup, so running it first used to
					-- discard the call before the agent loop could execute it.
					if ok and msg and type(msg.content) == "string" and msg.content ~= "" then
						local rawContent = msg.content
						if not msg.tool_calls or #msg.tool_calls == 0 then
							local cleaned, parsed = AT.parseTextToolCalls(msg.content)
							if parsed and #parsed > 0 then
								msg.tool_calls = parsed
								msg.content = cleaned
							elseif msg.finish_reason == "length" and (rawContent:find("<tool") or rawContent:find("<function")) then
								-- A text-mode call was cut off before its closing tag/JSON.
								-- Continuing the raw JSON in a fresh message cannot produce a
								-- parseable call, so ask for a smaller clean retry instead.
								msg.tool_call_truncated = true
								msg.content = ""
							end
						end
						local clean = EX.scrubLiveText(msg.content)
						msg.content = clean
					end

					if not ok then
						local errorText = tostring(msg)
						if errorText == "(cancelled)" or errorText == "(aborted)" then
							setBusy(false, genChatId)
							return
						end
						errCount = errCount + 1
						local status = tonumber(errorText:match("HTTP%s+(%d%d%d)"))
						local retryable = status == 408 or status == 429 or (status and status >= 500)
							or errorText:lower():find("timeout", 1, true) or errorText:lower():find("timed out", 1, true)
						if not retryable or errCount >= 3 then
							if viewing() then addMessage("**Error:** " .. errorText, "system") end
							setBusy(false, genChatId)
							return
						end
						task.wait(math.min(2 ^ (errCount - 1), 4))
						stepCount = stepCount - 1
					else
						errCount = 0
					end

					if ok then
					local assistantEntry = { role = "assistant", content = msg.content or "", reasoning_content = msg.thinking }
					if msg.tool_calls then assistantEntry.tool_calls = msg.tool_calls end

					local calls = msg.tool_calls

					genMessages[#genMessages + 1] = assistantEntry
					saveChats()

					if calls and #calls > 0 then

						if msg.thinking and msg.thinking ~= "" and viewing() then
							streamThinking(msg.thinking, nil, genChatId)
						end
						if msg.content and msg.content ~= "" and viewing() then
							streamMessage(msg.content, nil, genChatId)
						end

						EX.runToolBatch(calls, genMessages, genChatId, isCancelled, viewing)

					else

						-- The model ran out of output tokens mid-answer. Seamlessly
						-- continue: keep the partial content, ask it to carry on from
						-- exactly where it stopped, and loop. The continuation streams
						-- on so the user sees one uninterrupted answer.
						if msg.tool_call_truncated and (contCount or 0) < 12 then
							contCount = (contCount or 0) + 1
							genMessages[#genMessages + 1] = {
								role = "user",
								content = "Your tool call was cut off inside its JSON and could not execute. Retry the same action as a fresh tool call using only 80-120 lines of code. For a long script, create the tab with the first chunk and use append_editor for later chunks. Do not continue the broken JSON.",
							}
							saveChats()
							stepCount = stepCount - 1
						elseif msg.finish_reason == "length" and (contCount or 0) < 12 then
							contCount = (contCount or 0) + 1
							if msg.thinking and msg.thinking ~= "" and viewing() then
								streamThinking(msg.thinking, nil, genChatId)
							end
							if msg.content and msg.content ~= "" and viewing() then
								streamMessage(msg.content, nil, genChatId)
							end
							genMessages[#genMessages + 1] = {
								role = "user",
								content = "Continue exactly where you left off. Do not repeat anything you already wrote, do not add any preamble or commentary like 'continuing' — just resume the output mid-stream as if you never stopped.",
							}
							saveChats()
							stepCount = stepCount - 1  -- continuation isn't an agent action; don't burn the step budget
							-- loop again to fetch the continuation
						else
						maybeTitleConversation(genChatId)
						local function answer()
							local c = msg.content
							if type(c) == "string" and c ~= "" then
								streamMessage(c, function() setBusy(false, genChatId) end, genChatId)
							else
								-- Empty final turn (model finished, nothing more to say).
								-- Just end quietly — don't dump the response object.
								setBusy(false, genChatId)
							end
						end
						if msg.thinking and msg.thinking ~= "" then
							streamThinking(msg.thinking, answer, genChatId)
						else
							answer()
						end
						return
						end
					end
					end
				end
			end)
			if not handled then
				EX.finishPendingTools(genMessages, "The agent stopped before this call returned a result.")
				saveChats()
				hideDots()
				local errStr = tostring(loopErr)
				-- "cannot resume dead coroutine" means the generation thread was
				-- interrupted (chat switch / stop / teardown), not a real failure.
				-- Don't show a scary message for that — just end quietly.
				local interrupted = errStr:find("dead coroutine") or errStr:find("cannot resume")
				if not interrupted and genChatId == currentChatId then
					addMessage("**Something went wrong:** " .. errStr .. " — the agent stopped. Try again or rephrase.", "system")
				end
				setBusy(false, genChatId)
			end
		end, genChatId)
	else

		genSpawn(function()
			task.wait(0.5)
			if not alive then return end
			hideDots()
			local reply = "I don't have an API key yet, so I can't actually do anything in-game.\n\n**I'd recommend [Ollama Cloud](https://ollama.com).** It has very high free usage limits, cheap pricing if you go past them, and genuinely capable models — it's the easiest way to get me running.\n\nGrab a key from your Ollama account, then drop it into **Settings → Connection** (provider is already set to Ollama). Once it's in, I can read the game, run scripts, edit code, and the rest."
			genMessages[#genMessages + 1] = { role = "assistant", content = reply }
			saveChats()
			if genChatId == currentChatId then
				addMessage(reply, "assistant")
			end
			setBusy(false, genChatId)
		end, genChatId)
	end
end

track(send.MouseButton1Click:Connect(function()
	if thinking then
		stopGeneration()
	else
		sendMessage()
	end
end))

local function clearMessages()
	for _, child in ipairs(scroll:GetChildren()) do
		if child:IsA("GuiObject") and child ~= tWrap then
			child:Destroy()
		end
	end
	msgOrder = 0
end

local chatPanelOpen = false

function loadConversation(id)
	local convo
	for _, candidate in ipairs(conversations) do
		if candidate.id == id then convo = candidate; break end
	end
	if not convo then return end
	currentChatId = id
	if editState.msg then field.Text = "" end
	editState.msg, editState.role, editState.index = nil, nil, nil
	pcall(EX.resetTurnTokens)
	chatHistory = convo.messages
	clearMessages()

	local msgs = chatHistory
	local i = 1
	while i <= #msgs do
		local msg = msgs[i]
		if type(msg) ~= "table" then i = i + 1
		elseif msg.role == "user" then
			local b = addMessage(msg.content or "", "user")
			if b then attachActions(b.Parent, "user", msg.content or "", i) end
			i = i + 1
		elseif msg.role == "tool" then

			i = i + 1
		elseif msg.role == "assistant" then

			if msg.content and msg.content ~= "" then
				local b = addMessage(msg.content, "assistant")
				if b then attachActions(b.Parent, "assistant", msg.content, i) end
			end

			if msg.tool_calls and #msg.tool_calls > 0 then

				local results = {}
				local k = i + 1
				while k <= #msgs and type(msgs[k]) == "table" and msgs[k].role == "tool" do
					results[#results + 1] = msgs[k]
					k = k + 1
				end
				local usedResult = {}
				for ci, call in ipairs(msg.tool_calls) do
					local fn = type(call) == "table" and call["function"] or nil
					if type(fn) ~= "table" then fn = nil end
					local name = fn and fn.name or "tool"
					local args = fn and fn.arguments or {}
					if type(args) == "string" then
						local okD, parsed = pcall(function() return AT.http:JSONDecode(args) end)
						args = okD and parsed or {}
					end
					if type(args) ~= "table" then args = {} end

					local resultText = ""
					local matched = false
					local callId = type(call) == "table" and call.id or nil
					if callId then
						for ri, r in ipairs(results) do
							if not usedResult[ri] and r.tool_call_id == callId then
								resultText = tostring(r.content or ""); usedResult[ri] = true; matched = true; break
							end
						end
					end
					for ri, r in ipairs(results) do
						if not matched and not usedResult[ri] and not r.tool_call_id and r.tool_name == name then
							resultText = tostring(r.content or ""); usedResult[ri] = true; matched = true; break
						end
					end
					if not matched and results[ci] and not results[ci].tool_call_id and not usedResult[ci] then
						resultText = tostring(results[ci].content or ""); usedResult[ci] = true
					end
					local detailText
					if name == "run_luau" then detailText = tostring(args.code or "")
					else
						local okJ, jj = pcall(function() return AT.http:JSONEncode(args) end)
						detailText = okJ and jj or ""
					end
					local card = addToolCall({ name = name, title = toolTitle(name, args), detail = detailText })
					if card then
						card.setDone()
						if resultText ~= "" then card.setDetail(resultText) end
					end
				end

				i = k
			else
				i = i + 1
			end
		else
			i = i + 1
		end
	end

	refreshBusyVisuals()

	if busyChats[id] then
		tWrap.Visible = true
		tWrap.LayoutOrder = msgOrder
		task.defer(function() if scroll and scroll.Parent then scroll.CanvasPosition = Vector2.new(0, scroll.AbsoluteCanvasSize.Y) end end)
	else
		tWrap.Visible = false
	end
	saveChats()
	updateGreeting()
end

-- ===== Message actions: regenerate + edit =====
-- (editState is declared earlier, before sendMessage, so it's in scope there.)

do
	-- Re-run generation from the user turn that precedes assistant message at
	-- histIndex. Drops that assistant message and everything after it.
	regenerateFrom = function(histIndex)
		if thinking then return end
		local msgs = chatHistory
		if not msgs[histIndex] then return end
		-- find the user message at or before histIndex-1
		local cut = histIndex
		for j = histIndex - 1, 1, -1 do
			if type(msgs[j]) == "table" and msgs[j].role == "user" then
				cut = j + 1  -- keep the user msg, drop everything after it
				break
			end
		end
		-- truncate history
		for j = #msgs, cut, -1 do msgs[j] = nil end
		saveChats()
		loadConversation(currentChatId)
		-- kick off a fresh generation using the existing (truncated) history
		local convo = activeConvo()
		local genChatId = currentChatId
		setBusy(true, genChatId)
		genSpawn(function()
			innerSendMessage(nil, genChatId, convo, msgs)
		end, genChatId)
	end

	-- Begin editing a message: load it into the input box and remember which
	-- history entry to overwrite on send.
	editHistoryMessage = function(histIndex, role, oldText)
		if thinking then return end
		local msg = chatHistory[histIndex]
		if not msg then return end
		editState.msg, editState.role, editState.index = msg, role, histIndex
		field.Text = tostring(oldText or "")
		field:CaptureFocus()
	end
end

if currentChatId and #chatHistory > 0 then
	loadConversation(currentChatId)
end

local ChatsPanel = Instance.new("Frame")
ChatsPanel.Name = "ChatsPanel"
ChatsPanel.Size = UDim2.new(1, 0, 1, 0)
ChatsPanel.Position = UDim2.new(-1, 0, 0, 0)
ChatsPanel.BorderSizePixel = 0
ChatsPanel.ZIndex = 10
ChatsPanel.Active = true
ChatsPanel.Visible = false
ChatsPanel.Parent = ChatPage
reg(ChatsPanel, "BackgroundColor3", "Background")

local cpHeader = Instance.new("TextLabel")
cpHeader.Size = UDim2.new(1, -120, 0, 30)
cpHeader.Position = UDim2.new(0, 16, 0, 12)
cpHeader.BackgroundTransparency = 1
cpHeader.Text = "Chats"
cpHeader.Font = Theme.FontBold
cpHeader.TextSize = 16
cpHeader.TextXAlignment = Enum.TextXAlignment.Left
cpHeader.ZIndex = 11
cpHeader.Parent = ChatsPanel
reg(cpHeader, "TextColor3", "Text")

local newChatBtn = Instance.new("TextButton")
newChatBtn.Size = UDim2.new(0, 92, 0, 30)
newChatBtn.Position = UDim2.new(1, -108, 0, 12)
newChatBtn.BorderSizePixel = 0
newChatBtn.Text = ""
newChatBtn.AutoButtonColor = false
newChatBtn.ZIndex = 12
newChatBtn.Parent = ChatsPanel
reg(newChatBtn, "BackgroundColor3", "AccentDeep")
corner(newChatBtn, 8)
newChatLbl = Instance.new("TextLabel")
newChatLbl.Size = UDim2.new(1, 0, 1, 0)
newChatLbl.BackgroundTransparency = 1
newChatLbl.Text = "+ New chat"
newChatLbl.Font = Theme.FontBold
newChatLbl.TextSize = 12
newChatLbl.TextColor3 = Color3.fromRGB(255,255,255)
newChatLbl.ZIndex = 13
newChatLbl.Parent = newChatBtn
track(newChatBtn.MouseEnter:Connect(function() tw(newChatBtn, {BackgroundColor3 = Theme.Accent}, 0.15) end))
track(newChatBtn.MouseLeave:Connect(function() tw(newChatBtn, {BackgroundColor3 = Theme.AccentDeep}, 0.15) end))

local cpList = Instance.new("ScrollingFrame")
cpList.Position = UDim2.new(0, 12, 0, 52)
cpList.Size = UDim2.new(1, -24, 1, -64)
cpList.BackgroundTransparency = 1
cpList.BorderSizePixel = 0
cpList.ScrollBarThickness = 3
cpList.CanvasSize = UDim2.new(0, 0, 0, 0)
cpList.AutomaticCanvasSize = Enum.AutomaticSize.Y
cpList.ZIndex = 11
cpList.Parent = ChatsPanel
reg(cpList, "ScrollBarImageColor3", "StrokeSecond")

cpListLayout = Instance.new("UIListLayout")
cpListLayout.SortOrder = Enum.SortOrder.LayoutOrder
cpListLayout.Padding = UDim.new(0, 6)
cpListLayout.Parent = cpList

local function closeChatPanel()
	chatPanelOpen = false
	tw(ChatsPanel, {Position = UDim2.new(-1, 0, 0, 0)}, 0.28, Enum.EasingStyle.Quint)
	task.delay(0.3, function() if not chatPanelOpen and ChatsPanel and ChatsPanel.Parent then ChatsPanel.Visible = false end end)
end

local function openChatPanel()
	chatPanelOpen = true
	refreshChatList()
	ChatsPanel.Visible = true
	tw(ChatsPanel, {Position = UDim2.new(0, 0, 0, 0)}, 0.28, Enum.EasingStyle.Quint)
end

local function makeChatRow(convo, order)
	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, 0, 0, 40)
	row.BorderSizePixel = 0
	row.Text = ""
	row.AutoButtonColor = false
	row.LayoutOrder = order
	row.ZIndex = 12
	row.Parent = cpList
	corner(row, 8)
	local isActive = (convo.id == currentChatId)
	row.BackgroundColor3 = isActive and Theme.Accent or Theme.Element
	if not isActive then regStroke(row, "StrokeSecond", 1) end

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Position = UDim2.new(0, 12, 0, 0)
	titleLbl.Size = UDim2.new(1, -52, 1, 0)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = convo.title or "New chat"
	titleLbl.Font = Theme.Font
	titleLbl.TextSize = 13
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.TextTruncate = Enum.TextTruncate.AtEnd
	titleLbl.TextColor3 = isActive and Color3.fromRGB(255,255,255) or Theme.Text
	titleLbl.ZIndex = 13
	titleLbl.Parent = row

	local delBtn = Instance.new("TextButton")
	delBtn.AnchorPoint = Vector2.new(1, 0.5)
	delBtn.Position = UDim2.new(1, -8, 0.5, 0)
	delBtn.Size = UDim2.new(0, 24, 0, 24)
	delBtn.BackgroundTransparency = 1
	delBtn.Text = ""
	delBtn.AutoButtonColor = false
	delBtn.ZIndex = 14
	delBtn.Parent = row

	local delColor = isActive and Color3.fromRGB(255,255,255) or Theme.TextDim
	local delBars = {}
	for _, rot in ipairs({45, -45}) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.new(0.5, 0, 0.5, 0)
		bar.Size = UDim2.new(0, 12, 0, 2)
		bar.Rotation = rot
		bar.BackgroundColor3 = delColor
		bar.BorderSizePixel = 0
		bar.ZIndex = 15
		bar.Parent = delBtn
		corner(bar, 1)
		table.insert(delBars, bar)
	end
	track(delBtn.MouseEnter:Connect(function() for _, b in pairs(delBars) do tw(b, {BackgroundColor3 = Theme.Danger}, 0.15) end end))
	track(delBtn.MouseLeave:Connect(function() for _, b in pairs(delBars) do tw(b, {BackgroundColor3 = delColor}, 0.15) end end))

	if not isActive then
		track(row.MouseEnter:Connect(function() tw(row, {BackgroundColor3 = Theme.ElementHover}, 0.15) end))
		track(row.MouseLeave:Connect(function() tw(row, {BackgroundColor3 = Theme.Element}, 0.15) end))
	end

	track(row.MouseButton1Click:Connect(function()
		if convo.id ~= currentChatId then
			loadConversation(convo.id)
		end
		closeChatPanel()
	end))

	track(delBtn.MouseButton1Click:Connect(function()
		stopGeneration(convo.id)
		for i, c in ipairs(conversations) do
			if c.id == convo.id then table.remove(conversations, i) break end
		end
		if #conversations == 0 then
			createConversation()
			loadConversation(currentChatId)
		elseif convo.id == currentChatId then
			loadConversation(conversations[1].id)
		end
		saveChats()
		refreshChatList()
	end))
end

function refreshChatList()
	for _, child in ipairs(cpList:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
	for idx, convo in ipairs(conversations) do
		makeChatRow(convo, idx)
	end
end

track(newChatBtn.MouseButton1Click:Connect(function()
	createConversation()
	loadConversation(currentChatId)
	refreshChatList()
	closeChatPanel()
end))

track(chatsToggle.MouseButton1Click:Connect(function()
	if chatPanelOpen then closeChatPanel() else openChatPanel() end
end))

do
local pendingTitles = {}
function maybeTitleConversation(chatId)
	chatId = chatId or currentChatId
	local pending = pendingTitles[chatId]
	if pending and coroutine.status(pending) ~= "dead" then return end
	local convo
	for _, c in ipairs(conversations) do
		if c.id == chatId then convo = c break end
	end
	if not convo or convo.titled then return end
	if #convo.messages < 2 then return end
	local snapshot = {}
	for i = 1, math.min(5, #convo.messages) do snapshot[i] = convo.messages[i] end
	local targetId = convo.id
	local titleThread = genSpawn(function()
		local ran, ok, title = pcall(generateTitle, snapshot)
		pendingTitles[targetId] = nil
		if ran and ok and type(title) == "string" and title ~= "" then
			for _, c in ipairs(conversations) do
				if c.id == targetId then
					c.title = title
					c.titled = true
					break
				end
			end
			saveChats()
			if chatPanelOpen then refreshChatList() end
		end
	end, targetId)
	if coroutine.status(titleThread) ~= "dead" then pendingTitles[targetId] = titleThread end
end
end

local function buildSettings()

local PAD_X = 18

local root = Instance.new("Frame")
root.Name = "SettingsRoot"
root.Size = UDim2.new(1, 0, 0, 0)
root.AutomaticSize = Enum.AutomaticSize.Y
root.BackgroundTransparency = 1
root.ZIndex = 2
root.Parent = SettingsPage
rootPad = Instance.new("UIPadding")
rootPad.PaddingTop = UDim.new(0, 16)
rootPad.PaddingBottom = UDim.new(0, 24)
rootPad.PaddingLeft = UDim.new(0, PAD_X)
rootPad.PaddingRight = UDim.new(0, PAD_X)
rootPad.Parent = root
rootList = Instance.new("UIListLayout")
rootList.SortOrder = Enum.SortOrder.LayoutOrder
rootList.Padding = UDim.new(0, 18)
rootList.Parent = root

local order = 0
local function nextOrder() order = order + 1; return order end

local titleWrap = Instance.new("Frame")
titleWrap.Size = UDim2.new(1, 0, 0, 44)
titleWrap.BackgroundTransparency = 1
titleWrap.LayoutOrder = nextOrder()
titleWrap.ZIndex = 2
titleWrap.Parent = root
local settingsLabel = Instance.new("TextLabel")
settingsLabel.Size = UDim2.new(1, 0, 0, 24)
settingsLabel.BackgroundTransparency = 1
settingsLabel.Text = "Settings"
settingsLabel.Font = Theme.FontBold
settingsLabel.TextSize = 18
settingsLabel.TextXAlignment = Enum.TextXAlignment.Left
settingsLabel.ZIndex = 2
settingsLabel.Parent = titleWrap
reg(settingsLabel, "TextColor3", "Text")
local settingsSub = Instance.new("TextLabel")
settingsSub.Size = UDim2.new(1, 0, 0, 16)
settingsSub.Position = UDim2.new(0, 0, 0, 26)
settingsSub.BackgroundTransparency = 1
settingsSub.Text = "Configure the model and agent behaviour."
settingsSub.Font = Theme.Font
settingsSub.TextSize = 12
settingsSub.TextXAlignment = Enum.TextXAlignment.Left
settingsSub.ZIndex = 2
settingsSub.Parent = titleWrap
reg(settingsSub, "TextColor3", "TextFaint")

local function makeSection(titleText)
	local card = Instance.new("Frame")
	card.Size = UDim2.new(1, 0, 0, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundTransparency = 1
	card.LayoutOrder = nextOrder()
	card.ZIndex = 2
	card.Parent = root

	local head = Instance.new("TextLabel")
	head.Size = UDim2.new(1, 0, 0, 16)
	head.BackgroundTransparency = 1
	head.Text = string.upper(titleText)
	head.Font = Theme.FontBold
	head.TextSize = 11
	head.TextXAlignment = Enum.TextXAlignment.Left
	head.LayoutOrder = 0
	head.ZIndex = 2
	head.Parent = card
	reg(head, "TextColor3", "TextFaint")

	local panel = Instance.new("Frame")
	panel.Size = UDim2.new(1, 0, 0, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundTransparency = 1
	panel.LayoutOrder = 1
	panel.Position = UDim2.new(0, 0, 0, 22)
	panel.ZIndex = 2
	panel.Parent = card
	reg(panel, "BackgroundColor3", "Secondary")
	panel.BackgroundTransparency = 0
	corner(panel, 10)
	regStroke(panel, "StrokeSecond", 1)
	local pPad = Instance.new("UIPadding")
	pPad.PaddingTop = UDim.new(0, 14); pPad.PaddingBottom = UDim.new(0, 14)
	pPad.PaddingLeft = UDim.new(0, 14); pPad.PaddingRight = UDim.new(0, 14)
	pPad.Parent = panel
	local pList = Instance.new("UIListLayout")
	pList.SortOrder = Enum.SortOrder.LayoutOrder
	pList.Padding = UDim.new(0, 12)
	pList.Parent = panel

	local cardList = Instance.new("UIListLayout")
	cardList.SortOrder = Enum.SortOrder.LayoutOrder
	cardList.Padding = UDim.new(0, 6)
	cardList.Parent = card

	return panel
end

local function makeField(parent, lo, labelText, placeholder, initial, masked, height, multiline)
	height = height or 34
	local wrap = Instance.new("Frame")
	wrap.Size = UDim2.new(1, 0, 0, height + 20)
	wrap.BackgroundTransparency = 1
	wrap.LayoutOrder = lo
	wrap.ZIndex = 2
	wrap.Parent = parent

	local cap = Instance.new("TextLabel")
	cap.Size = UDim2.new(1, 0, 0, 14)
	cap.BackgroundTransparency = 1
	cap.Text = labelText
	cap.Font = Theme.Font
	cap.TextSize = 11
	cap.TextXAlignment = Enum.TextXAlignment.Left
	cap.ZIndex = 2
	cap.Parent = wrap
	reg(cap, "TextColor3", "TextDim")

	local box = Instance.new("TextBox")
	box.Size = UDim2.new(1, 0, 0, height)
	box.Position = UDim2.new(0, 0, 0, 18)
	box.BorderSizePixel = 0
	box.PlaceholderText = placeholder
	box.Text = initial or ""
	box.Font = Theme.FontMono
	box.TextSize = 12
	box.ClearTextOnFocus = false
	box.ClipsDescendants = true
	box.TextXAlignment = Enum.TextXAlignment.Left
	box.TextEditable = true
	if multiline then
		box.MultiLine = true
		box.TextWrapped = true
		box.TextYAlignment = Enum.TextYAlignment.Top
	end
	if masked then box.TextTransparency = 0 end
	box.ZIndex = 3
	box.Parent = wrap
	reg(box, "BackgroundColor3", "Element")
	reg(box, "PlaceholderColor3", "Placeholder")
	reg(box, "TextColor3", "Text")
	corner(box, 8)
	regStroke(box, "StrokeSecond", 1)
	if multiline then pad(box, 8, 8, 12, 12) else pad(box, 0, 0, 12, 12) end
	track(box.Focused:Connect(function() tw(box, {BackgroundColor3 = Theme.ElementHover}, 0.15) end))
	track(box.FocusLost:Connect(function() tw(box, {BackgroundColor3 = Theme.Element}, 0.15) end))
	return box
end

local function makeHint(parent, lo, text)
	local h = Instance.new("TextLabel")
	h.Size = UDim2.new(1, 0, 0, 0)
	h.AutomaticSize = Enum.AutomaticSize.Y
	h.BackgroundTransparency = 1
	h.Text = text
	h.Font = Theme.Font
	h.TextSize = 10
	h.TextWrapped = true
	h.TextXAlignment = Enum.TextXAlignment.Left
	h.TextYAlignment = Enum.TextYAlignment.Top
	h.LayoutOrder = lo
	h.ZIndex = 2
	h.Parent = parent
	reg(h, "TextColor3", "TextFaint")
	return h
end

local keyBox, sysBox, applyStatus
local updateCustomVisible, updateCustomStatus, resetConnectionFields
do
local connPanel = makeSection("Connection")

local function makeDropdown(parent, lo, labelText, options, current, onSelect)
	local wrap = Instance.new("Frame")
	wrap.Size = UDim2.new(1, 0, 0, 52)
	wrap.BackgroundTransparency = 1
	wrap.LayoutOrder = lo
	wrap.ClipsDescendants = false
	wrap.ZIndex = 5
	wrap.Parent = parent
	local cap = Instance.new("TextLabel")
	cap.Size = UDim2.new(1, 0, 0, 14)
	cap.BackgroundTransparency = 1
	cap.Text = labelText
	cap.Font = Theme.Font
	cap.TextSize = 11
	cap.TextXAlignment = Enum.TextXAlignment.Left
	cap.ZIndex = 5
	cap.Parent = wrap
	reg(cap, "TextColor3", "TextDim")

	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 0, 32)
	btn.Position = UDim2.new(0, 0, 0, 18)
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.ZIndex = 6
	btn.Parent = wrap
	reg(btn, "BackgroundColor3", "Element")
	corner(btn, 8)
	regStroke(btn, "StrokeSecond", 1)
	local val = Instance.new("TextLabel")
	val.AnchorPoint = Vector2.new(0, 0.5)
	val.Position = UDim2.new(0, 12, 0.5, 0)
	val.Size = UDim2.new(1, -40, 1, 0)
	val.BackgroundTransparency = 1
	val.Text = current or "—"
	val.Font = Theme.FontMono
	val.TextSize = 12
	val.TextXAlignment = Enum.TextXAlignment.Left
	val.TextTruncate = Enum.TextTruncate.AtEnd
	val.ZIndex = 7
	val.Parent = btn
	reg(val, "TextColor3", "Text")
	local chev = Instance.new("ImageLabel")
	chev.AnchorPoint = Vector2.new(1, 0.5)
	chev.Position = UDim2.new(1, -10, 0.5, 0)
	chev.Size = UDim2.new(0, 14, 0, 14)
	chev.BackgroundTransparency = 1
	chev.Image = "rbxassetid://10709790644"
	chev.ZIndex = 7
	chev.Parent = btn
	reg(chev, "ImageColor3", "TextFaint")

	local list = Instance.new("ScrollingFrame")
	list.Size = UDim2.new(1, 0, 0, 0)
	list.Position = UDim2.new(0, 0, 0, 52)
	list.BackgroundTransparency = 0
	list.BorderSizePixel = 0
	list.ScrollBarThickness = 3
	list.Visible = false
	list.ClipsDescendants = true
	list.ZIndex = 20
	list.Parent = wrap
	reg(list, "BackgroundColor3", "Element")
	corner(list, 8)
	regStroke(list, "StrokeSecond", 1)
	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = list

	local curValue = current
	local isOpen = false
	local optionCount = 0
	local function setOpen(o)
		isOpen = o
		list.Visible = o
		tw(chev, { Rotation = o and 180 or 0 }, 0.15)
		local count = optionCount
		local h = math.min(140, math.max(0, count * 28))
		list.Size = UDim2.new(1, 0, 0, o and h or 0)
		list.CanvasSize = UDim2.new(0, 0, 0, count * 28)
		wrap.ZIndex = o and 30 or 5
	end

	local function rebuild(opts)
		optionCount = #opts
		for _, c in ipairs(list:GetChildren()) do if c:IsA("TextButton") then c:Destroy() end end
		for i, opt in ipairs(opts) do
			local o = Instance.new("TextButton")
			o.Size = UDim2.new(1, 0, 0, 28)
			o.BorderSizePixel = 0
			o.Text = ""
			o.AutoButtonColor = false
			o.LayoutOrder = i
			o.ZIndex = 21
			o.Parent = list
			reg(o, "BackgroundColor3", "Element")
			local ol = Instance.new("TextLabel")
			ol.Size = UDim2.new(1, -20, 1, 0)
			ol.Position = UDim2.new(0, 12, 0, 0)
			ol.BackgroundTransparency = 1
			ol.Text = opt
			ol.Font = Theme.FontMono
			ol.TextSize = 12
			ol.TextXAlignment = Enum.TextXAlignment.Left
			ol.TextTruncate = Enum.TextTruncate.AtEnd
			ol.ZIndex = 22
			ol.Parent = o
			reg(ol, "TextColor3", "TextDim")
			track(o.MouseEnter:Connect(function() tw(o, {BackgroundColor3 = Theme.ElementHover}, 0.1) end))
			track(o.MouseLeave:Connect(function() tw(o, {BackgroundColor3 = Theme.Element}, 0.1) end))
			track(o.MouseButton1Click:Connect(function()
				curValue = opt
				val.Text = opt
				setOpen(false)
				if onSelect then onSelect(opt) end
			end))
		end
	end
	rebuild(options or {})
	track(btn.MouseButton1Click:Connect(function() setOpen(not isOpen) end))

	return {
		frame = wrap,
		setOptions = function(opts) rebuild(opts); if isOpen then setOpen(true) end end,
		setValue = function(v) curValue = v; val.Text = v or "—" end,
		getValue = function() return curValue end,
	}
end

local providerNames = {}
for _, p in ipairs(PROVIDERS) do providerNames[#providerNames + 1] = p.name end
local modelDrop
local fetchRequestId = 0
local providerModels = { [providerId] = apiModel }

local function providerNameById(id) return providerById(id).name end
local function providerIdByName(nm) for _, p in ipairs(PROVIDERS) do if p.name == nm then return p.id end end return "ollama" end

local providerDrop = makeDropdown(connPanel, 0, "Provider", providerNames, providerNameById(providerId), function(name)
	if keyBox then providerKeys[providerId] = keyBox.Text end
	providerModels[providerId] = apiModel
	providerId = providerIdByName(name)
	fetchRequestId = fetchRequestId + 1

	if keyBox then keyBox.Text = curKey() end
	local prov = curProvider()
	local opts = prov.models
	if #opts == 0 then opts = { providerModels[providerId] or "" } end
	if modelDrop then
		modelDrop.setOptions(opts)
		apiModel = providerModels[providerId] or opts[1] or ""
		modelDrop.setValue(apiModel)
	end
	if updateCustomVisible then updateCustomVisible() end
	saveConfig()
end)

local initialModels = curProvider().models
if #initialModels == 0 then initialModels = { apiModel } end
modelDrop = makeDropdown(connPanel, 1, "Model", initialModels, apiModel, function(m)
	apiModel = m
	saveConfig()
end)

-- ===== Custom-endpoint controls (shown only when provider == Custom) =====
-- A single container holding: Base URL, Format (OpenAI/Anthropic), Tool mode
-- (Native/Text), and a free-text Model box. When Custom is active we hide the
-- model dropdown and let the model box drive apiModel.
local customGroup = Instance.new("Frame")
customGroup.Size = UDim2.new(1, 0, 0, 0)
customGroup.AutomaticSize = Enum.AutomaticSize.Y
customGroup.BackgroundTransparency = 1
customGroup.LayoutOrder = 1  -- sit right under the provider dropdown / model slot
customGroup.Visible = false
customGroup.ZIndex = 3
customGroup.Parent = connPanel
local cgList = Instance.new("UIListLayout")
cgList.SortOrder = Enum.SortOrder.LayoutOrder
cgList.Padding = UDim.new(0, 12)
cgList.Parent = customGroup

-- Base URL field
local urlWrap = Instance.new("Frame")
urlWrap.Size = UDim2.new(1, 0, 0, 52)
urlWrap.BackgroundTransparency = 1
urlWrap.LayoutOrder = 0
urlWrap.ZIndex = 3
urlWrap.Parent = customGroup
local urlCap = Instance.new("TextLabel")
urlCap.Size = UDim2.new(1, 0, 0, 14)
urlCap.BackgroundTransparency = 1
urlCap.Text = "Endpoint base URL"
urlCap.Font = Theme.Font
urlCap.TextSize = 11
urlCap.TextXAlignment = Enum.TextXAlignment.Left
urlCap.ZIndex = 3
urlCap.Parent = urlWrap
reg(urlCap, "TextColor3", "TextDim")
local urlBox = Instance.new("TextBox")
urlBox.Size = UDim2.new(1, 0, 0, 32)
urlBox.Position = UDim2.new(0, 0, 0, 18)
urlBox.BorderSizePixel = 0
urlBox.PlaceholderText = "https://host/v1  (OpenAI)  or  https://host  (Anthropic)"
urlBox.Text = EX.customBase
urlBox.Font = Theme.FontMono
urlBox.TextSize = 12
urlBox.ClearTextOnFocus = false
urlBox.ClipsDescendants = true
urlBox.TextXAlignment = Enum.TextXAlignment.Left
urlBox.ZIndex = 4
urlBox.Parent = urlWrap
reg(urlBox, "BackgroundColor3", "Element")
reg(urlBox, "PlaceholderColor3", "Placeholder")
reg(urlBox, "TextColor3", "Text")
corner(urlBox, 8)
regStroke(urlBox, "StrokeSecond", 1)
pad(urlBox, 0, 0, 12, 12)
track(urlBox.Focused:Connect(function() tw(urlBox, {BackgroundColor3 = Theme.ElementHover}, 0.15) end))
track(urlBox.FocusLost:Connect(function()
	EX.customBase = EX.normalizeBase(urlBox.Text)
	urlBox.Text = EX.customBase            -- reflect the cleaned value back
	tw(urlBox, {BackgroundColor3 = Theme.Element}, 0.15)
	saveConfig()
	if updateCustomStatus then updateCustomStatus() end
end))

-- Format toggle: OpenAI | Anthropic
local fmtWrap = Instance.new("Frame")
fmtWrap.Size = UDim2.new(1, 0, 0, 52)
fmtWrap.BackgroundTransparency = 1
fmtWrap.LayoutOrder = 1
fmtWrap.ZIndex = 3
fmtWrap.Parent = customGroup
local fmtCap = Instance.new("TextLabel")
fmtCap.Size = UDim2.new(1, 0, 0, 14)
fmtCap.BackgroundTransparency = 1
fmtCap.Text = "API format"
fmtCap.Font = Theme.Font
fmtCap.TextSize = 11
fmtCap.TextXAlignment = Enum.TextXAlignment.Left
fmtCap.ZIndex = 3
fmtCap.Parent = fmtWrap
reg(fmtCap, "TextColor3", "TextDim")
local fmtRow = Instance.new("Frame")
fmtRow.Size = UDim2.new(1, 0, 0, 30)
fmtRow.Position = UDim2.new(0, 0, 0, 18)
fmtRow.BackgroundTransparency = 1
fmtRow.ZIndex = 3
fmtRow.Parent = fmtWrap
local fmtBtns = {}
local FMT_OPTS = { { id = "openai", label = "OpenAI" }, { id = "anthropic", label = "Anthropic" } }
local function refreshFmt()
	for _, opt in ipairs(FMT_OPTS) do
		local b = fmtBtns[opt.id]
		local on = (EX.customKind == opt.id)
		tw(b, { BackgroundColor3 = on and Theme.Accent or Theme.Element }, 0.15)
		local lbl = b:FindFirstChildOfClass("TextLabel")
		if lbl then lbl.TextColor3 = on and Color3.fromRGB(255,255,255) or Theme.TextDim end
	end
end
for i, opt in ipairs(FMT_OPTS) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0.5, -4, 1, 0)
	b.Position = UDim2.new((i-1)*0.5, (i-1) == 0 and 0 or 4, 0, 0)
	b.BorderSizePixel = 0
	b.Text = ""
	b.AutoButtonColor = false
	b.ZIndex = 4
	b.Parent = fmtRow
	reg(b, "BackgroundColor3", "Element")
	corner(b, 7)
	regStroke(b, "StrokeSecond", 1)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = opt.label
	lbl.Font = Theme.Font
	lbl.TextSize = 12
	lbl.ZIndex = 5
	lbl.Parent = b
	reg(lbl, "TextColor3", "TextDim")
	fmtBtns[opt.id] = b
	track(b.MouseButton1Click:Connect(function()
		EX.customKind = opt.id
		saveConfig()
		refreshFmt()
		if updateCustomStatus then updateCustomStatus() end
	end))
end
refreshFmt()

-- Tool mode toggle: Native | Text
local tmWrap = Instance.new("Frame")
tmWrap.Size = UDim2.new(1, 0, 0, 52)
tmWrap.BackgroundTransparency = 1
tmWrap.LayoutOrder = 2
tmWrap.ZIndex = 3
tmWrap.Parent = customGroup
local tmCap = Instance.new("TextLabel")
tmCap.Size = UDim2.new(1, 0, 0, 14)
tmCap.BackgroundTransparency = 1
tmCap.Text = "Tool calling"
tmCap.Font = Theme.Font
tmCap.TextSize = 11
tmCap.TextXAlignment = Enum.TextXAlignment.Left
tmCap.ZIndex = 3
tmCap.Parent = tmWrap
reg(tmCap, "TextColor3", "TextDim")
local tmRow = Instance.new("Frame")
tmRow.Size = UDim2.new(1, 0, 0, 30)
tmRow.Position = UDim2.new(0, 0, 0, 18)
tmRow.BackgroundTransparency = 1
tmRow.ZIndex = 3
tmRow.Parent = tmWrap
local tmBtns = {}
local TM_OPTS = { { id = "native", label = "Native" }, { id = "text", label = "Text (flatten)" } }
local function refreshTm()
	for _, opt in ipairs(TM_OPTS) do
		local b = tmBtns[opt.id]
		local on = (EX.customTools == opt.id)
		tw(b, { BackgroundColor3 = on and Theme.Accent or Theme.Element }, 0.15)
		local lbl = b:FindFirstChildOfClass("TextLabel")
		if lbl then lbl.TextColor3 = on and Color3.fromRGB(255,255,255) or Theme.TextDim end
	end
end
for i, opt in ipairs(TM_OPTS) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0.5, -4, 1, 0)
	b.Position = UDim2.new((i-1)*0.5, (i-1) == 0 and 0 or 4, 0, 0)
	b.BorderSizePixel = 0
	b.Text = ""
	b.AutoButtonColor = false
	b.ZIndex = 4
	b.Parent = tmRow
	reg(b, "BackgroundColor3", "Element")
	corner(b, 7)
	regStroke(b, "StrokeSecond", 1)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = opt.label
	lbl.Font = Theme.Font
	lbl.TextSize = 12
	lbl.ZIndex = 5
	lbl.Parent = b
	reg(lbl, "TextColor3", "TextDim")
	tmBtns[opt.id] = b
	track(b.MouseButton1Click:Connect(function()
		EX.customTools = opt.id
		saveConfig()
		refreshTm()
	end))
end
refreshTm()

-- Stream toggle (chunked polling). A switch + an explicit caption that the
-- endpoint must implement the chunked-polling contract (NOT raw SSE).
local strmWrap = Instance.new("Frame")
strmWrap.Size = UDim2.new(1, 0, 0, 0)
strmWrap.AutomaticSize = Enum.AutomaticSize.Y
strmWrap.BackgroundTransparency = 1
strmWrap.LayoutOrder = 25
strmWrap.ZIndex = 3
strmWrap.Parent = customGroup
local strmList = Instance.new("UIListLayout")
strmList.SortOrder = Enum.SortOrder.LayoutOrder
strmList.Padding = UDim.new(0, 6)
strmList.Parent = strmWrap

local strmRow = Instance.new("Frame")
strmRow.Size = UDim2.new(1, 0, 0, 26)
strmRow.BackgroundTransparency = 1
strmRow.LayoutOrder = 0
strmRow.ZIndex = 3
strmRow.Parent = strmWrap
local strmCap = Instance.new("TextLabel")
strmCap.AnchorPoint = Vector2.new(0, 0.5)
strmCap.Position = UDim2.new(0, 0, 0.5, 0)
strmCap.Size = UDim2.new(1, -60, 1, 0)
strmCap.BackgroundTransparency = 1
strmCap.Text = "Async request endpoint"
strmCap.Font = Theme.Font
strmCap.TextSize = 12
strmCap.TextXAlignment = Enum.TextXAlignment.Left
strmCap.ZIndex = 3
strmCap.Parent = strmRow
reg(strmCap, "TextColor3", "Text")
local strmToggle = Instance.new("TextButton")
strmToggle.AnchorPoint = Vector2.new(1, 0.5)
strmToggle.Position = UDim2.new(1, 0, 0.5, 0)
strmToggle.Size = UDim2.new(0, 46, 0, 24)
strmToggle.BorderSizePixel = 0
strmToggle.Text = ""
strmToggle.AutoButtonColor = false
strmToggle.ZIndex = 4
strmToggle.Parent = strmRow
corner(strmToggle, 12)
local strmKnob = Instance.new("Frame")
strmKnob.Size = UDim2.new(0, 18, 0, 18)
strmKnob.Position = UDim2.new(0, 3, 0.5, -9)
strmKnob.BorderSizePixel = 0
strmKnob.BackgroundColor3 = Color3.fromRGB(255,255,255)
strmKnob.ZIndex = 5
strmKnob.Parent = strmToggle
corner(strmKnob, 9)
local function refreshStrm()
	if EX.customStream then
		tw(strmToggle, { BackgroundColor3 = Theme.Online }, 0.15)
		tw(strmKnob, { Position = UDim2.new(1, -21, 0.5, -9) }, 0.15)
	else
		tw(strmToggle, { BackgroundColor3 = Theme.Element }, 0.15)
		tw(strmKnob, { Position = UDim2.new(0, 3, 0.5, -9) }, 0.15)
	end
end
refreshStrm()
track(strmToggle.MouseButton1Click:Connect(function()
	EX.customStream = not EX.customStream
	saveConfig()
	refreshStrm()
	updateCustomStatus()
end))
local strmHint = Instance.new("TextLabel")
strmHint.Size = UDim2.new(1, 0, 0, 0)
strmHint.AutomaticSize = Enum.AutomaticSize.Y
strmHint.BackgroundTransparency = 1
strmHint.Text = "For endpoints that don't reply in one HTTP call. The client POSTs to <base>/request, gets back {id}, then polls GET <base>/request/<id> until the FULL message is ready (it returns {ready:false} until done). No streaming — the whole reply comes back at once. Leave OFF for normal endpoints that reply directly."
strmHint.Font = Theme.Font
strmHint.TextSize = 10
strmHint.TextWrapped = true
strmHint.TextXAlignment = Enum.TextXAlignment.Left
strmHint.LayoutOrder = 1
strmHint.ZIndex = 3
strmHint.Parent = strmWrap
reg(strmHint, "TextColor3", "TextFaint")

-- Custom model (free text)
local cmWrap = Instance.new("Frame")
cmWrap.Size = UDim2.new(1, 0, 0, 52)
cmWrap.BackgroundTransparency = 1
cmWrap.LayoutOrder = 3
cmWrap.ZIndex = 3
cmWrap.Parent = customGroup
local cmCap = Instance.new("TextLabel")
cmCap.Size = UDim2.new(1, 0, 0, 14)
cmCap.BackgroundTransparency = 1
cmCap.Text = "Model name"
cmCap.Font = Theme.Font
cmCap.TextSize = 11
cmCap.TextXAlignment = Enum.TextXAlignment.Left
cmCap.ZIndex = 3
cmCap.Parent = cmWrap
reg(cmCap, "TextColor3", "TextDim")
local cmBox = Instance.new("TextBox")
cmBox.Size = UDim2.new(1, 0, 0, 32)
cmBox.Position = UDim2.new(0, 0, 0, 18)
cmBox.BorderSizePixel = 0
cmBox.PlaceholderText = "exact model id the endpoint expects"
cmBox.Text = EX.customModel
cmBox.Font = Theme.FontMono
cmBox.TextSize = 12
cmBox.ClearTextOnFocus = false
cmBox.ClipsDescendants = true
cmBox.TextXAlignment = Enum.TextXAlignment.Left
cmBox.ZIndex = 4
cmBox.Parent = cmWrap
reg(cmBox, "BackgroundColor3", "Element")
reg(cmBox, "PlaceholderColor3", "Placeholder")
reg(cmBox, "TextColor3", "Text")
corner(cmBox, 8)
regStroke(cmBox, "StrokeSecond", 1)
pad(cmBox, 0, 0, 12, 12)
track(cmBox.Focused:Connect(function() tw(cmBox, {BackgroundColor3 = Theme.ElementHover}, 0.15) end))
track(cmBox.FocusLost:Connect(function()
	EX.customModel = tostring(cmBox.Text):gsub("^%s+", ""):gsub("%s+$", "")
	cmBox.Text = EX.customModel
	if providerId == "custom" then apiModel = EX.customModel end
	tw(cmBox, {BackgroundColor3 = Theme.Element}, 0.15)
	saveConfig()
	if updateCustomStatus then updateCustomStatus() end
end))

-- small status/hint line
local cStatus = Instance.new("TextLabel")
cStatus.Size = UDim2.new(1, 0, 0, 0)
cStatus.AutomaticSize = Enum.AutomaticSize.Y
cStatus.BackgroundTransparency = 1
cStatus.Text = ""
cStatus.Font = Theme.Font
cStatus.TextSize = 10
cStatus.TextWrapped = true
cStatus.TextXAlignment = Enum.TextXAlignment.Left
cStatus.LayoutOrder = 4
cStatus.ZIndex = 3
cStatus.Parent = customGroup
reg(cStatus, "TextColor3", "TextFaint")

function updateCustomStatus()
	if providerId ~= "custom" then return end
	local b = EX.normalizeBase(EX.customBase)
	if b == "" then
		cStatus.Text = "Enter a base URL. OpenAI format calls <base>/chat/completions; Anthropic format calls <base>/v1/messages."
		cStatus.TextColor3 = Theme.TextFaint
	elseif EX.customModel == "" then
		cStatus.Text = "Enter a model name."
		cStatus.TextColor3 = Theme.TextFaint
	else
		local ep = EX.customStream and "/request" or ((EX.customKind == "anthropic") and "/v1/messages" or "/chat/completions")
		cStatus.Text = "Will call: " .. b .. ep .. "  ·  model " .. EX.customModel
		cStatus.TextColor3 = Color3.fromRGB(96, 200, 120)
	end
end

function updateCustomVisible()
	local isCustom = (providerId == "custom")
	customGroup.Visible = isCustom
	-- hide the model dropdown for custom (the free-text model box replaces it)
	if modelDrop and modelDrop.frame then modelDrop.frame.Visible = not isCustom end
	if isCustom then
		urlBox.Text = EX.customBase
		cmBox.Text = EX.customModel
		apiModel = EX.customModel
		refreshFmt(); refreshTm(); refreshStrm(); updateCustomStatus()
	end
end
updateCustomVisible()

resetConnectionFields = function()
	fetchRequestId = fetchRequestId + 1
	urlBox.Text, cmBox.Text = "", ""
	providerModels = {}
	if providerId == "custom" then apiModel = "" end
	refreshFmt(); refreshTm(); refreshStrm(); updateCustomStatus()
end


local keyRow = Instance.new("Frame")
keyRow.Size = UDim2.new(1, 0, 0, 52)
keyRow.BackgroundTransparency = 1
keyRow.LayoutOrder = 2
keyRow.ZIndex = 4
keyRow.Parent = connPanel
local keyCap = Instance.new("TextLabel")
keyCap.Size = UDim2.new(1, 0, 0, 14)
keyCap.BackgroundTransparency = 1
keyCap.Text = "API Key"
keyCap.Font = Theme.Font
keyCap.TextSize = 11
keyCap.TextXAlignment = Enum.TextXAlignment.Left
keyCap.ZIndex = 4
keyCap.Parent = keyRow
reg(keyCap, "TextColor3", "TextDim")
keyBox = Instance.new("TextBox")
keyBox.Size = UDim2.new(1, -96, 0, 32)
keyBox.Position = UDim2.new(0, 0, 0, 18)
keyBox.BorderSizePixel = 0
keyBox.PlaceholderText = "Paste your API key"
keyBox.Text = curKey()
keyBox.Font = Theme.FontMono
keyBox.TextSize = 12
keyBox.ClearTextOnFocus = false
keyBox.ClipsDescendants = true
keyBox.TextXAlignment = Enum.TextXAlignment.Left
keyBox.ZIndex = 5
keyBox.Parent = keyRow
reg(keyBox, "BackgroundColor3", "Element")
reg(keyBox, "PlaceholderColor3", "Placeholder")
reg(keyBox, "TextColor3", "Text")
corner(keyBox, 8)
regStroke(keyBox, "StrokeSecond", 1)
pad(keyBox, 0, 0, 12, 12)
track(keyBox.Focused:Connect(function() tw(keyBox, {BackgroundColor3 = Theme.ElementHover}, 0.15) end))
track(keyBox.FocusLost:Connect(function() tw(keyBox, {BackgroundColor3 = Theme.Element}, 0.15) end))

local fetchBtn = Instance.new("TextButton")
fetchBtn.Size = UDim2.new(0, 86, 0, 32)
fetchBtn.Position = UDim2.new(1, -86, 0, 18)
fetchBtn.BorderSizePixel = 0
fetchBtn.Text = "Fetch models"
fetchBtn.Font = Theme.Font
fetchBtn.TextSize = 11
fetchBtn.AutoButtonColor = false
fetchBtn.ZIndex = 5
fetchBtn.Parent = keyRow
reg(fetchBtn, "BackgroundColor3", "Element")
reg(fetchBtn, "TextColor3", "TextDim")
corner(fetchBtn, 8)
regStroke(fetchBtn, "StrokeSecond", 1)
track(fetchBtn.MouseEnter:Connect(function() tw(fetchBtn, {BackgroundColor3 = Theme.ElementHover}, 0.15) end))
track(fetchBtn.MouseLeave:Connect(function() tw(fetchBtn, {BackgroundColor3 = Theme.Element}, 0.15) end))
track(fetchBtn.MouseButton1Click:Connect(function()

	providerKeys[providerId] = keyBox.Text
	saveConfig()
	fetchRequestId = fetchRequestId + 1
	local requestId, selectedProvider = fetchRequestId, providerId
	local prov, key = curProvider(), curKey()
	fetchBtn.Text = "..."
	spawn_(function()
		local ok, models = pcall(fetchModels, prov, key)
		if not alive or not fetchBtn.Parent then return end
		if requestId ~= fetchRequestId or selectedProvider ~= providerId then
			if fetchBtn.Text == "..." then fetchBtn.Text = "Fetch models" end
			return
		end
		if ok and type(models) == "table" and #models > 0 then
			modelDrop.setOptions(models)
			fetchBtn.Text = "Fetched ✓"
		else
			fetchBtn.Text = "No list"
		end
		task.delay(1.4, function() if requestId == fetchRequestId and fetchBtn.Parent then fetchBtn.Text = "Fetch models" end end)
	end)
end))

sysBox = makeField(connPanel, 3, "System Prompt", "Optional. Sets how the assistant behaves.", ollamaSystemPrompt, false, 64, true)
track(sysBox:GetPropertyChangedSignal("Text"):Connect(function()
	ollamaSystemPrompt = sysBox.Text
end))

local applyRow = Instance.new("Frame")
applyRow.Size = UDim2.new(1, 0, 0, 32)
applyRow.BackgroundTransparency = 1
applyRow.LayoutOrder = 4
applyRow.ZIndex = 2
applyRow.Parent = connPanel
local applyBtn = Instance.new("TextButton")
applyBtn.Size = UDim2.new(0, 90, 1, 0)
applyBtn.BorderSizePixel = 0
applyBtn.Text = ""
applyBtn.AutoButtonColor = false
applyBtn.ZIndex = 3
applyBtn.Parent = applyRow
reg(applyBtn, "BackgroundColor3", "AccentDeep")
corner(applyBtn, 8)
applyLbl = Instance.new("TextLabel")
applyLbl.Size = UDim2.new(1, 0, 1, 0)
applyLbl.BackgroundTransparency = 1
applyLbl.Text = "Apply"
applyLbl.Font = Theme.FontBold
applyLbl.TextSize = 13
applyLbl.TextColor3 = Color3.fromRGB(255,255,255)
applyLbl.ZIndex = 4
applyLbl.Parent = applyBtn
track(applyBtn.MouseEnter:Connect(function() tw(applyBtn, {BackgroundColor3 = Theme.Accent}, 0.15) end))
track(applyBtn.MouseLeave:Connect(function() tw(applyBtn, {BackgroundColor3 = Theme.AccentDeep}, 0.15) end))

applyStatus = Instance.new("TextLabel")
applyStatus.AnchorPoint = Vector2.new(0, 0.5)
applyStatus.Position = UDim2.new(0, 100, 0.5, 0)
applyStatus.Size = UDim2.new(1, -100, 1, 0)
applyStatus.BackgroundTransparency = 1
applyStatus.Text = (curKey() ~= "" or providerId == "custom") and ("Configured · " .. apiModel) or "Not configured"
applyStatus.Font = Theme.Font
applyStatus.TextSize = 12
applyStatus.TextXAlignment = Enum.TextXAlignment.Left
applyStatus.TextColor3 = (curKey() ~= "") and Color3.fromRGB(96, 200, 120) or Color3.fromRGB(150,150,150)
applyStatus.ZIndex = 3
applyStatus.Parent = applyRow
if curKey() == "" then reg(applyStatus, "TextColor3", "TextFaint") end

track(applyBtn.MouseButton1Click:Connect(function()
	if providerId == "custom" then
		-- pull from the custom boxes, not the (hidden) model dropdown
		EX.customBase = EX.normalizeBase(urlBox.Text)
		EX.customModel = tostring(cmBox.Text):gsub("^%s+", ""):gsub("%s+$", "")
		urlBox.Text = EX.customBase; cmBox.Text = EX.customModel
		apiModel = EX.customModel
	else
		apiModel = modelDrop.getValue() or apiModel
	end
	providerKeys[providerId] = keyBox.Text
	ollamaSystemPrompt = sysBox.Text
	saveConfig()
	if providerId == "custom" then
		if EX.normalizeBase(EX.customBase) == "" then
			applyStatus.Text = "Enter a base URL"
			applyStatus.TextColor3 = LOG_COLORS and LOG_COLORS.Warning or Color3.fromRGB(255,200,90)
		elseif EX.customModel == "" then
			applyStatus.Text = "Enter a model name"
			applyStatus.TextColor3 = LOG_COLORS and LOG_COLORS.Warning or Color3.fromRGB(255,200,90)
		else
			-- key is optional for custom (local LLMs often need none)
			applyStatus.Text = "Custom · " .. EX.customModel
			applyStatus.TextColor3 = Color3.fromRGB(96, 200, 120)
		end
		if updateCustomStatus then updateCustomStatus() end
	elseif curKey() == "" then
		applyStatus.Text = "Enter an API key"
		applyStatus.TextColor3 = LOG_COLORS and LOG_COLORS.Warning or Color3.fromRGB(255,200,90)
	else
		applyStatus.Text = "Configured · " .. apiModel
		applyStatus.TextColor3 = Color3.fromRGB(96, 200, 120)
	end
end))

themeHooks[#themeHooks + 1] = function()
	refreshFmt(); refreshTm(); refreshStrm(); updateCustomStatus()
end
end

local agentPanel = makeSection("Agent")

local permWrap = Instance.new("Frame")
permWrap.Size = UDim2.new(1, 0, 0, 52)
permWrap.BackgroundTransparency = 1
permWrap.LayoutOrder = 0
permWrap.ZIndex = 2
permWrap.Parent = agentPanel
local permCap = Instance.new("TextLabel")
permCap.Size = UDim2.new(1, 0, 0, 14)
permCap.BackgroundTransparency = 1
permCap.Text = "Permissions"
permCap.Font = Theme.Font
permCap.TextSize = 11
permCap.TextXAlignment = Enum.TextXAlignment.Left
permCap.ZIndex = 2
permCap.Parent = permWrap
reg(permCap, "TextColor3", "TextDim")
local permRow = Instance.new("Frame")
permRow.Size = UDim2.new(1, 0, 0, 30)
permRow.Position = UDim2.new(0, 0, 0, 18)
permRow.BackgroundTransparency = 1
permRow.ZIndex = 3
permRow.Parent = permWrap
local permBtns = {}
local PERM_OPTS = { { id = "ask", label = "Ask" }, { id = "edit", label = "Edit" }, { id = "bypass", label = "Bypass" } }
local function refreshPerm()
	for _, opt in ipairs(PERM_OPTS) do
		local b = permBtns[opt.id]
		local on = (permissionMode == opt.id)
		tw(b, { BackgroundColor3 = on and Theme.Accent or Theme.Element }, 0.15)
		local lbl = b:FindFirstChildOfClass("TextLabel")
		if lbl then lbl.TextColor3 = on and Color3.fromRGB(255,255,255) or Theme.TextDim end
	end
end
for i, opt in ipairs(PERM_OPTS) do
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1/3, -6, 1, 0)
	b.Position = UDim2.new((i-1)/3, (i-1) == 0 and 0 or 3, 0, 0)
	b.BorderSizePixel = 0
	b.Text = ""
	b.AutoButtonColor = false
	b.ZIndex = 3
	b.Parent = permRow
	reg(b, "BackgroundColor3", "Element")
	corner(b, 7)
	regStroke(b, "StrokeSecond", 1)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = opt.label
	lbl.Font = Theme.Font
	lbl.TextSize = 12
	lbl.ZIndex = 4
	lbl.Parent = b
	reg(lbl, "TextColor3", "TextDim")
	permBtns[opt.id] = b
	track(b.MouseButton1Click:Connect(function()
		permissionMode = opt.id
		saveConfig()
		refreshPerm()
	end))
end
refreshPerm()
makeHint(agentPanel, 1, "Ask: approve every action. Edit: auto file edits only. Bypass: run everything automatically.")

local planRow = Instance.new("Frame")
planRow.Size = UDim2.new(1, 0, 0, 26)
planRow.BackgroundTransparency = 1
planRow.LayoutOrder = 2
planRow.ZIndex = 2
planRow.Parent = agentPanel
local planCap = Instance.new("TextLabel")
planCap.AnchorPoint = Vector2.new(0, 0.5)
planCap.Position = UDim2.new(0, 0, 0.5, 0)
planCap.Size = UDim2.new(1, -60, 1, 0)
planCap.BackgroundTransparency = 1
planCap.Text = "Plan mode"
planCap.Font = Theme.Font
planCap.TextSize = 12
planCap.TextXAlignment = Enum.TextXAlignment.Left
planCap.ZIndex = 2
planCap.Parent = planRow
reg(planCap, "TextColor3", "Text")
local planToggle = Instance.new("TextButton")
planToggle.AnchorPoint = Vector2.new(1, 0.5)
planToggle.Position = UDim2.new(1, 0, 0.5, 0)
planToggle.Size = UDim2.new(0, 46, 0, 24)
planToggle.BorderSizePixel = 0
planToggle.Text = ""
planToggle.AutoButtonColor = false
planToggle.ZIndex = 3
planToggle.Parent = planRow
corner(planToggle, 12)
local planKnob = Instance.new("Frame")
planKnob.Size = UDim2.new(0, 18, 0, 18)
planKnob.Position = UDim2.new(0, 3, 0.5, -9)
planKnob.BorderSizePixel = 0
planKnob.BackgroundColor3 = Color3.fromRGB(255,255,255)
planKnob.ZIndex = 4
planKnob.Parent = planToggle
corner(planKnob, 9)
local function refreshPlanToggle()
	if planMode then
		tw(planToggle, { BackgroundColor3 = Theme.Online }, 0.15)
		tw(planKnob, { Position = UDim2.new(1, -21, 0.5, -9) }, 0.15)
	else
		tw(planToggle, { BackgroundColor3 = Theme.Element }, 0.15)
		tw(planKnob, { Position = UDim2.new(0, 3, 0.5, -9) }, 0.15)
	end
end
refreshPlanToggle()
track(planToggle.MouseButton1Click:Connect(function()
	planMode = not planMode
	saveConfig()
	refreshPlanToggle()
end))
makeHint(agentPanel, 3, "Agent drafts a plan and waits for your approval before acting.")
themeHooks[#themeHooks + 1] = function() refreshPerm(); refreshPlanToggle() end

local budgetBox = makeField(agentPanel, 4, "Step budget (0 = unlimited)", "0", tostring(agentMaxSteps), false)
track(budgetBox.FocusLost:Connect(function()
	local v = tonumber(budgetBox.Text)
	agentMaxSteps = (v and v == v and v >= 0 and v < math.huge) and math.floor(v) or agentMaxSteps
	budgetBox.Text = tostring(agentMaxSteps)
	saveConfig()
end))

local dataPanel = makeSection("Data")
makeHint(dataPanel, 0, "No API key yet? Ollama Cloud is recommended — high free limits, cheap pricing, capable models. Clearing wipes your saved key, prompt, and all conversations.")
local clearSavedBtn = Instance.new("TextButton")
clearSavedBtn.Size = UDim2.new(0, 140, 0, 30)
clearSavedBtn.BorderSizePixel = 0
clearSavedBtn.Text = ""
clearSavedBtn.AutoButtonColor = false
clearSavedBtn.LayoutOrder = 1
clearSavedBtn.ZIndex = 3
clearSavedBtn.Parent = dataPanel
reg(clearSavedBtn, "BackgroundColor3", "Element")
corner(clearSavedBtn, 8)
regStroke(clearSavedBtn, "StrokeSecond", 1)
local clearSavedLbl = Instance.new("TextLabel")
clearSavedLbl.Size = UDim2.new(1, 0, 1, 0)
clearSavedLbl.BackgroundTransparency = 1
clearSavedLbl.Text = "Clear saved data"
clearSavedLbl.Font = Theme.Font
clearSavedLbl.TextSize = 12
clearSavedLbl.ZIndex = 4
clearSavedLbl.Parent = clearSavedBtn
reg(clearSavedLbl, "TextColor3", "TextDim")
track(clearSavedBtn.MouseEnter:Connect(function() tw(clearSavedBtn, {BackgroundColor3 = Theme.ElementHover}, 0.15) end))
track(clearSavedBtn.MouseLeave:Connect(function() tw(clearSavedBtn, {BackgroundColor3 = Theme.Element}, 0.15) end))
track(clearSavedBtn.MouseButton1Click:Connect(function()
	for _, convo in ipairs(conversations) do stopGeneration(convo.id) end
	if hasFS then
		if type(delfile) == "function" then
			pcall(delfile, CONFIG_PATH)
			pcall(delfile, CHATS_PATH)
			local removed = pcall(delfile, SYSTEM_TXT_PATH)
			if not removed then pcall(writefile, SYSTEM_TXT_PATH, "") end
		else
			pcall(function() writefile(CONFIG_PATH, "{}") end)
			pcall(function() writefile(CHATS_PATH, "{}") end)
			pcall(function() writefile(SYSTEM_TXT_PATH, "") end)
		end
	end
	conversations = {}
	createConversation()
	loadConversation(currentChatId)
	if refreshChatList then refreshChatList() end
	providerKeys = {}
	keyBox.Text = ""
	ollamaSystemPrompt = ""
	sysBox.Text = ""
	-- reset custom endpoint settings too
	EX.customBase, EX.customModel = "", ""
	EX.customKind, EX.customTools = "openai", "native"
	EX.customStream = false
	if resetConnectionFields then resetConnectionFields() end
	saveConfig()
	saveChats()
	clearSavedLbl.Text = "Cleared"
	applyStatus.Text = "Not configured"
	applyStatus.TextColor3 = Color3.fromRGB(150,150,150)
	task.delay(1.2, function() if clearSavedLbl and clearSavedLbl.Parent then clearSavedLbl.Text = "Clear saved data" end end)
end))
end
buildSettings()

local PersonalisePage = Instance.new("Frame")
PersonalisePage.Name = "PersonalisePage"
PersonalisePage.Size = UDim2.new(1, 0, 1, 0)
PersonalisePage.BackgroundTransparency = 1
PersonalisePage.BorderSizePixel = 0
PersonalisePage.Visible = false
PersonalisePage.ZIndex = 2
PersonalisePage.Parent = PageHost

local function setupPersonalise()
	local persLabel = Instance.new("TextLabel")
persLabel.Size = UDim2.new(1, -40, 0, 24)
persLabel.Position = UDim2.new(0, 20, 0, 16)
persLabel.BackgroundTransparency = 1
persLabel.Text = "Personalise"
persLabel.Font = Theme.FontBold
persLabel.TextSize = 16
persLabel.TextXAlignment = Enum.TextXAlignment.Left
persLabel.ZIndex = 2
persLabel.Parent = PersonalisePage
reg(persLabel, "TextColor3", "Text")

local persSub = Instance.new("TextLabel")
persSub.Size = UDim2.new(1, -40, 0, 16)
persSub.Position = UDim2.new(0, 20, 0, 42)
persSub.BackgroundTransparency = 1
persSub.Text = "Theme"
persSub.Font = Theme.Font
persSub.TextSize = 12
persSub.TextXAlignment = Enum.TextXAlignment.Left
persSub.ZIndex = 2
persSub.Parent = PersonalisePage
reg(persSub, "TextColor3", "TextFaint")

local themeRows = {}
local function makeThemeRow(index, name, swatchColor)
	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, -40, 0, 44)
	row.Position = UDim2.new(0, 20, 0, 68 + (index - 1) * 52)
	row.BorderSizePixel = 0
	row.Text = ""
	row.AutoButtonColor = false
	row.ZIndex = 3
	row.Parent = PersonalisePage
	reg(row, "BackgroundColor3", "Element")
	corner(row, 10)
	local rowStroke = regStroke(row, "StrokeSecond", 1)

	local swatch = Instance.new("Frame")
	swatch.Size = UDim2.new(0, 26, 0, 26)
	swatch.Position = UDim2.new(0, 10, 0.5, -13)
	swatch.BackgroundColor3 = swatchColor
	swatch.BorderSizePixel = 0
	swatch.ZIndex = 4
	swatch.Parent = row
	corner(swatch, 7)
	stroke(swatch, Color3.fromRGB(255, 255, 255), 1).Transparency = 0.85

	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -90, 1, 0)
	label.Position = UDim2.new(0, 46, 0, 0)
	label.BackgroundTransparency = 1
	label.Text = name
	label.Font = Theme.FontBold
	label.TextSize = 13
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.ZIndex = 4
	label.Parent = row
	reg(label, "TextColor3", "Text")

	local check = Instance.new("Frame")
	check.AnchorPoint = Vector2.new(1, 0.5)
	check.Position = UDim2.new(1, -14, 0.5, 0)
	check.Size = UDim2.new(0, 10, 0, 10)
	check.BorderSizePixel = 0
	check.ZIndex = 4
	check.Parent = row
	corner(check, 5)
	reg(check, "BackgroundColor3", "Accent")

	local function refresh()
		local selected = (currentThemeName == name)
		check.Visible = selected
		tw(rowStroke, {Color = selected and Theme.Accent or Theme.StrokeSecond, Thickness = selected and 1.5 or 1}, 0.2)
	end

	track(row.MouseEnter:Connect(function() if currentThemeName ~= name then tw(row, {BackgroundColor3 = Theme.ElementHover}, 0.15) end end))
	track(row.MouseLeave:Connect(function() if currentThemeName ~= name then tw(row, {BackgroundColor3 = Theme.Element}, 0.15) end end))
	track(row.MouseButton1Click:Connect(function()
		applyTheme(name)
		for _, fn in pairs(themeRows) do fn() end
	end))

	themeRows[#themeRows + 1] = refresh
	return refresh
end

makeThemeRow(1, "Midnight", Color3.fromRGB(40, 25, 50))
makeThemeRow(2, "White", Color3.fromRGB(245, 245, 248))
makeThemeRow(3, "Black", Color3.fromRGB(16, 16, 18))

for _, fn in pairs(themeRows) do fn() end
end
setupPersonalise()

local MonitorPage = Instance.new("Frame")
MonitorPage.Name = "MonitorPage"
MonitorPage.Size = UDim2.new(1, 0, 1, 0)
MonitorPage.BackgroundTransparency = 1
MonitorPage.BorderSizePixel = 0
MonitorPage.Visible = false
MonitorPage.ZIndex = 2
MonitorPage.Parent = PageHost

local function setupMonitor()
	local LOG_COLORS = {
		Output  = Color3.fromRGB(204, 204, 204),
	Info    = Color3.fromRGB(102, 153, 255),
	Warning = Color3.fromRGB(255, 200, 90),
	Error   = Color3.fromRGB(255, 90, 90),
}

local MON_FILTER_H = 30
local monFilter = Instance.new("Frame")
monFilter.Size = UDim2.new(1, -16, 0, MON_FILTER_H)
monFilter.Position = UDim2.new(0, 8, 0, 8)
monFilter.BackgroundTransparency = 1
monFilter.ZIndex = 2
monFilter.Parent = MonitorPage

filterList = Instance.new("UIListLayout")
filterList.FillDirection = Enum.FillDirection.Horizontal
filterList.SortOrder = Enum.SortOrder.LayoutOrder
filterList.Padding = UDim.new(0, 6)
filterList.VerticalAlignment = Enum.VerticalAlignment.Center
filterList.Parent = monFilter

local monScroll = Instance.new("ScrollingFrame")
monScroll.Position = UDim2.new(0, 8, 0, 8 + MON_FILTER_H + 6)
monScroll.Size = UDim2.new(1, -16, 1, -(8 + MON_FILTER_H + 6 + 8))
monScroll.BorderSizePixel = 0
monScroll.ScrollBarThickness = 4
monScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
monScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
monScroll.ZIndex = 2
monScroll.Parent = MonitorPage
reg(monScroll, "BackgroundColor3", "Background")
reg(monScroll, "ScrollBarImageColor3", "StrokeSecond")
corner(monScroll, 8)
regStroke(monScroll, "StrokeSecond", 1)

monList = Instance.new("UIListLayout")
monList.SortOrder = Enum.SortOrder.LayoutOrder
monList.Padding = UDim.new(0, 1)
monList.Parent = monScroll
pad(monScroll, 6, 6, 8, 8)

local monOrder = 0
local activeFilter = "All"
local logLines = {}

local function lineVisible(msgType)
	if activeFilter == "All" then return true end
	return activeFilter == msgType
end

local function appendLog(msg, msgType)
	if not alive or not monScroll.Parent then return end
	msgType = msgType or "Output"
	local line = Instance.new("TextLabel")
	line.Size = UDim2.new(1, 0, 0, 0)
	line.AutomaticSize = Enum.AutomaticSize.Y
	line.BackgroundTransparency = 1
	line.Font = Theme.FontMono
	line.TextSize = 12
	line.TextWrapped = true
	line.TextXAlignment = Enum.TextXAlignment.Left
	line.TextColor3 = msgType == "Output" and Theme.Text or (LOG_COLORS[msgType] or Theme.Text)
	line.Text = tostring(msg or "")
	line.LayoutOrder = monOrder
	monOrder += 1
	line.ZIndex = 2
	line.Visible = lineVisible(msgType)
	line.Parent = monScroll
	logLines[#logLines + 1] = { label = line, msgType = msgType }
	if #logLines > 500 then table.remove(logLines, 1).label:Destroy() end
	task.defer(function()
		if monScroll and monScroll.Parent then
			monScroll.CanvasPosition = Vector2.new(0, monScroll.AbsoluteCanvasSize.Y)
		end
	end)
end

local filterBtns = {}
local function refreshFilters()
	for name, btn in pairs(filterBtns) do
		local on = (name == activeFilter)
		tw(btn, {BackgroundColor3 = on and Theme.Accent or Theme.Element}, 0.15)
		local lbl = btn:FindFirstChildOfClass("TextLabel")
		if lbl then lbl.TextColor3 = on and Color3.fromRGB(255,255,255) or Theme.TextDim end
	end
	for _, entry in pairs(logLines) do
		entry.label.Visible = lineVisible(entry.msgType)
	end
end

local function makeFilterBtn(order, name)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, name == "All" and 38 or 62, 1, 0)
	btn.AutomaticSize = Enum.AutomaticSize.None
	btn.BorderSizePixel = 0
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.LayoutOrder = order
	btn.ZIndex = 3
	btn.Parent = monFilter
	reg(btn, "BackgroundColor3", "Element")
	corner(btn, 7)
	regStroke(btn, "StrokeSecond", 1)

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = name
	lbl.Font = Theme.Font
	lbl.TextSize = 11
	lbl.TextColor3 = Theme.TextDim
	lbl.ZIndex = 4
	lbl.Parent = btn

	track(btn.MouseButton1Click:Connect(function()
		activeFilter = name
		refreshFilters()
	end))
	filterBtns[name] = btn
	return btn
end

makeFilterBtn(0, "All")
makeFilterBtn(1, "Output")
makeFilterBtn(2, "Info")
makeFilterBtn(3, "Warning")
makeFilterBtn(4, "Error")

local clearBtn = Instance.new("TextButton")
clearBtn.AnchorPoint = Vector2.new(1, 0.5)
clearBtn.Position = UDim2.new(1, 0, 0.5, 0)
clearBtn.Size = UDim2.new(0, 54, 0, 24)
clearBtn.BorderSizePixel = 0
clearBtn.Text = ""
clearBtn.AutoButtonColor = false
clearBtn.ZIndex = 3
clearBtn.Parent = monFilter
reg(clearBtn, "BackgroundColor3", "Element")
corner(clearBtn, 7)
regStroke(clearBtn, "StrokeSecond", 1)
local clearLbl = Instance.new("TextLabel")
clearLbl.Size = UDim2.new(1, 0, 1, 0)
clearLbl.BackgroundTransparency = 1
clearLbl.Text = "Clear"
clearLbl.Font = Theme.Font
clearLbl.TextSize = 11
clearLbl.ZIndex = 4
clearLbl.Parent = clearBtn
reg(clearLbl, "TextColor3", "TextDim")
track(clearBtn.MouseEnter:Connect(function() tw(clearBtn, {BackgroundColor3 = Theme.ElementHover}, 0.15) end))
track(clearBtn.MouseLeave:Connect(function() tw(clearBtn, {BackgroundColor3 = Theme.Element}, 0.15) end))
track(clearBtn.MouseButton1Click:Connect(function()
	for _, entry in pairs(logLines) do entry.label:Destroy() end
	logLines = {}
	monOrder = 0
end)
)

refreshFilters()
themeHooks[#themeHooks + 1] = function()
	refreshFilters()
	for _, entry in ipairs(logLines) do
		if entry.msgType == "Output" then entry.label.TextColor3 = Theme.Text end
	end
end

local function setupMonitorLog()
	local ok, LogService = pcall(function() return game:GetService("LogService") end)
	if ok and LogService then

		local typeMap = {
			[Enum.MessageType.MessageOutput]  = "Output",
			[Enum.MessageType.MessageInfo]    = "Info",
			[Enum.MessageType.MessageWarning] = "Warning",
			[Enum.MessageType.MessageError]   = "Error",
		}

		local okHist, history = pcall(function() return LogService:GetLogHistory() end)
		if okHist and typeof(history) == "table" then
			for i = math.max(1, #history - 499), #history do
				local item = history[i]
				appendLog(item.message, typeMap[item.messageType] or "Output")
			end
		end
		track(LogService.MessageOut:Connect(function(message, messageType)
			if not alive then return end
			appendLog(message, typeMap[messageType] or "Output")
		end))
	end
	appendLog("[Monitor] Listening to LogService output…", "Info")
	end
	setupMonitorLog()
end
setupMonitor()

-- ===== Workspace tab: the agent's persistent file tree (real files on disk) =====
local WorkspacePage = Instance.new("Frame")
WorkspacePage.Name = "WorkspacePage"
WorkspacePage.Size = UDim2.new(1, 0, 1, 0)
WorkspacePage.BackgroundTransparency = 1
WorkspacePage.BorderSizePixel = 0
WorkspacePage.Visible = false
WorkspacePage.ZIndex = 2
WorkspacePage.Parent = PageHost

local refreshWorkspace  -- forward ref so selectPage can refresh on open
;(function()
	local ROOT = AGENT_FOLDER          -- BloxAgent/scripts is the workspace root
	local curPath = ROOT               -- absolute path of the folder being viewed
	local function cleanName(name)
		name = tostring(name or ""):gsub("^%s+", ""):gsub("%s+$", "")
		if name == "" or name == "." or name == ".." or name:find('[\\/:*?"<>|%c]') then
			error("Enter a file or folder name without path separators or reserved characters.")
		end
		return name
	end
	local function pathExists(path)
		return (isfile and isfile(path)) or (isfolder and isfolder(path))
	end
	local function fileAction(fn)
		local ok, err = pcall(fn)
		if not ok then warn("[Workspace] " .. tostring(err)) end
		refreshWorkspace()
	end

	-- path / breadcrumb bar
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, -24, 0, 34); bar.Position = UDim2.new(0, 12, 0, 10)
	bar.BackgroundTransparency = 1; bar.ZIndex = 3; bar.Parent = WorkspacePage
	local upBtn = Instance.new("TextButton")
	upBtn.Size = UDim2.new(0, 30, 0, 28); upBtn.Position = UDim2.new(0, 0, 0, 3)
	upBtn.Text = "←"; upBtn.Font = Theme.FontBold; upBtn.TextSize = 16; upBtn.AutoButtonColor = false
	upBtn.BorderSizePixel = 0; upBtn.ZIndex = 4; upBtn.Parent = bar
	reg(upBtn, "BackgroundColor3", "Element"); reg(upBtn, "TextColor3", "TextDim"); corner(upBtn, 6)
	local pathLbl = Instance.new("TextLabel")
	pathLbl.Position = UDim2.new(0, 38, 0, 0); pathLbl.Size = UDim2.new(1, -38, 1, 0)
	pathLbl.BackgroundTransparency = 1; pathLbl.Font = Theme.FontMono; pathLbl.TextSize = 12
	pathLbl.TextXAlignment = Enum.TextXAlignment.Left; pathLbl.TextTruncate = Enum.TextTruncate.AtEnd
	pathLbl.ZIndex = 4; pathLbl.Parent = bar; reg(pathLbl, "TextColor3", "TextDim")

	-- action buttons row
	local actions = Instance.new("Frame")
	actions.Size = UDim2.new(1, -24, 0, 30); actions.Position = UDim2.new(0, 12, 0, 48)
	actions.BackgroundTransparency = 1; actions.ZIndex = 3; actions.Parent = WorkspacePage
	local function actionBtn(x, w, txt)
		local b = Instance.new("TextButton")
		b.Position = UDim2.new(0, x, 0, 0); b.Size = UDim2.new(0, w, 0, 28)
		b.Text = txt; b.Font = Theme.Font; b.TextSize = 12; b.AutoButtonColor = false
		b.BorderSizePixel = 0; b.ZIndex = 4; b.Parent = actions
		reg(b, "BackgroundColor3", "Element"); reg(b, "TextColor3", "Text"); corner(b, 6)
		track(b.MouseEnter:Connect(function() tw(b, {BackgroundColor3 = Theme.ElementHover}, 0.12) end))
		track(b.MouseLeave:Connect(function() tw(b, {BackgroundColor3 = Theme.Element}, 0.12) end))
		return b
	end
	local newFileBtn = actionBtn(0, 90, "+ File")
	local newFolderBtn = actionBtn(98, 100, "+ Folder")

	-- scrolling file list
	local list = Instance.new("ScrollingFrame")
	list.Position = UDim2.new(0, 12, 0, 86); list.Size = UDim2.new(1, -24, 1, -98)
	list.BackgroundTransparency = 1; list.BorderSizePixel = 0; list.ScrollBarThickness = 5
	list.CanvasSize = UDim2.new(0, 0, 0, 0); list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ZIndex = 3; list.Parent = WorkspacePage
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder; layout.Padding = UDim.new(0, 4); layout.Parent = list

	-- a tiny inline text prompt (for new file/folder name and rename)
	local function promptName(title, default, cb)
		local ov = Instance.new("Frame")
		ov.Size = UDim2.new(1, 0, 1, 0); ov.BackgroundColor3 = Color3.fromRGB(0,0,0)
		ov.BackgroundTransparency = 0.5; ov.BorderSizePixel = 0; ov.ZIndex = 20; ov.Active = true; ov.Parent = WorkspacePage
		local card = Instance.new("Frame")
		card.AnchorPoint = Vector2.new(0.5, 0.5); card.Position = UDim2.new(0.5, 0, 0.4, 0)
		card.Size = UDim2.new(0, 260, 0, 120); card.BorderSizePixel = 0; card.ZIndex = 21; card.Parent = ov
		reg(card, "BackgroundColor3", "Element"); corner(card, 10)
		local t = Instance.new("TextLabel")
		t.Position = UDim2.new(0, 14, 0, 10); t.Size = UDim2.new(1, -28, 0, 20); t.BackgroundTransparency = 1
		t.Text = title; t.Font = Theme.FontBold; t.TextSize = 13; t.TextXAlignment = Enum.TextXAlignment.Left
		t.ZIndex = 22; t.Parent = card; reg(t, "TextColor3", "Text")
		local box = Instance.new("TextBox")
		box.Position = UDim2.new(0, 14, 0, 38); box.Size = UDim2.new(1, -28, 0, 30); box.Text = default or ""
		box.Font = Theme.FontMono; box.TextSize = 13; box.ClearTextOnFocus = false; box.BorderSizePixel = 0
		box.ZIndex = 22; box.Parent = card; reg(box, "BackgroundColor3", "Secondary"); reg(box, "TextColor3", "Text")
		pad(box, 8, 8, 0, 0); corner(box, 6)
		local ok = Instance.new("TextButton")
		ok.Position = UDim2.new(1, -84, 1, -38); ok.Size = UDim2.new(0, 70, 0, 28); ok.Text = "OK"
		ok.Font = Theme.FontBold; ok.TextSize = 12; ok.AutoButtonColor = false; ok.BorderSizePixel = 0
		ok.ZIndex = 22; ok.Parent = card; reg(ok, "BackgroundColor3", "AccentDeep"); ok.TextColor3 = Color3.fromRGB(255,255,255); corner(ok, 6)
		local cancel = Instance.new("TextButton")
		cancel.Position = UDim2.new(1, -160, 1, -38); cancel.Size = UDim2.new(0, 70, 0, 28); cancel.Text = "Cancel"
		cancel.Font = Theme.Font; cancel.TextSize = 12; cancel.AutoButtonColor = false; cancel.BorderSizePixel = 0
		cancel.ZIndex = 22; cancel.Parent = card; reg(cancel, "BackgroundColor3", "Element"); reg(cancel, "TextColor3", "TextDim"); corner(cancel, 6)
		track(ok.MouseButton1Click:Connect(function() local v = box.Text; ov:Destroy(); cb(v) end))
		track(cancel.MouseButton1Click:Connect(function() ov:Destroy() end))
		box:CaptureFocus()
	end

	-- render the current folder
	refreshWorkspace = function()
		for _, c in ipairs(list:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end
		local rel = curPath:sub(#ROOT + 1)
		pathLbl.Text = "workspace" .. rel
		if not hasFS or type(listfiles) ~= "function" then
			local empty = Instance.new("TextLabel")
			empty.Size = UDim2.new(1, 0, 0, 40); empty.BackgroundTransparency = 1
			empty.Text = "Filesystem not available on this executor."
			empty.Font = Theme.Font; empty.TextSize = 12; empty.ZIndex = 4; empty.Parent = list
			reg(empty, "TextColor3", "TextFaint")
			return
		end
		ensureFolder()
		ensureAgentFolder()
		local okL, entries = pcall(listfiles, curPath)
		if not okL or type(entries) ~= "table" then
			warn("[Workspace] Unable to list " .. curPath .. ": " .. tostring(entries))
			entries = {}
		end
		-- sort: folders first then files, alphabetical
		local folders, files = {}, {}
		for _, full in ipairs(entries) do
			if type(full) == "string" then
				local name = full:gsub("\\", "/"):gsub("/+$", ""):match("([^/]+)$")
				if name and name ~= "." and name ~= ".." then
					local path = curPath .. "/" .. name
					local okDir, isDir = pcall(function() return isfolder and isfolder(path) end)
					if okDir and isDir then folders[#folders+1] = path else files[#files+1] = path end
				end
			end
		end
		table.sort(folders); table.sort(files)
		local ordered = {}
		for _, f in ipairs(folders) do ordered[#ordered+1] = { path = f, dir = true } end
		for _, f in ipairs(files) do ordered[#ordered+1] = { path = f, dir = false } end
		if #ordered == 0 then
			local empty = Instance.new("TextLabel")
			empty.Size = UDim2.new(1, 0, 0, 40); empty.BackgroundTransparency = 1
			empty.Text = "(empty folder)"; empty.Font = Theme.Font; empty.TextSize = 12; empty.ZIndex = 4; empty.Parent = list
			reg(empty, "TextColor3", "TextFaint")
			return
		end
		for idx, item in ipairs(ordered) do
			local short = item.path:match("([^/\\]+)$") or item.path
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 34); row.LayoutOrder = idx; row.BorderSizePixel = 0
			row.ZIndex = 4; row.Parent = list
			reg(row, "BackgroundColor3", "Element"); corner(row, 6)
			-- icon (folder = filled square, file = thin)
			local ic = Instance.new("Frame")
			ic.Position = UDim2.new(0, 10, 0.5, -6); ic.Size = UDim2.new(0, item.dir and 14 or 11, 0, item.dir and 11 or 13)
			ic.BorderSizePixel = 0; ic.ZIndex = 5; ic.Parent = row
			reg(ic, "BackgroundColor3", item.dir and "Accent" or "TextFaint"); corner(ic, 2)
			-- name button (click)
			local nameBtn = Instance.new("TextButton")
			nameBtn.Position = UDim2.new(0, 34, 0, 0); nameBtn.Size = UDim2.new(1, -120, 1, 0)
			nameBtn.BackgroundTransparency = 1; nameBtn.Text = short .. (item.dir and "/" or "")
			nameBtn.Font = Theme.Font; nameBtn.TextSize = 13; nameBtn.TextXAlignment = Enum.TextXAlignment.Left
			nameBtn.TextTruncate = Enum.TextTruncate.AtEnd; nameBtn.AutoButtonColor = false
			nameBtn.ZIndex = 5; nameBtn.Parent = row; reg(nameBtn, "TextColor3", "Text")
			-- rename + delete
			local renBtn = Instance.new("TextButton")
			renBtn.AnchorPoint = Vector2.new(1, 0.5); renBtn.Position = UDim2.new(1, -40, 0.5, 0)
			renBtn.Size = UDim2.new(0, 28, 0, 22); renBtn.Text = "ren"; renBtn.Font = Theme.Font; renBtn.TextSize = 10
			renBtn.AutoButtonColor = false; renBtn.BorderSizePixel = 0; renBtn.ZIndex = 5; renBtn.Parent = row
			renBtn.Visible = not item.dir
			reg(renBtn, "BackgroundColor3", "Secondary"); reg(renBtn, "TextColor3", "TextDim"); corner(renBtn, 5)
			local delBtn = Instance.new("TextButton")
			delBtn.AnchorPoint = Vector2.new(1, 0.5); delBtn.Position = UDim2.new(1, -8, 0.5, 0)
			delBtn.Size = UDim2.new(0, 28, 0, 22); delBtn.Text = "del"; delBtn.Font = Theme.Font; delBtn.TextSize = 10
			delBtn.AutoButtonColor = false; delBtn.BorderSizePixel = 0; delBtn.ZIndex = 5; delBtn.Parent = row
			reg(delBtn, "BackgroundColor3", "Secondary"); delBtn.TextColor3 = Theme.Danger; corner(delBtn, 5)

			track(nameBtn.MouseButton1Click:Connect(function()
				if item.dir then
					curPath = item.path; refreshWorkspace()
				else
					-- open the file in the executor
					local okR, content = pcall(readfile, item.path)
					if okR and ExecAPI and ExecAPI.create then
						ExecAPI.create(short, tostring(content or ""))
						if ExecAPI.show then ExecAPI.show() end
					end
				end
			end))
			track(renBtn.MouseButton1Click:Connect(function()
				local sourceParent = curPath
				promptName("Rename " .. short, short, function(newName)
					fileAction(function()
						newName = cleanName(newName)
						if newName == short then return end
						local dst = sourceParent .. "/" .. newName
						if pathExists(dst) then error("The destination already exists: " .. newName) end
						if type(delfile) ~= "function" then error("Renaming files is unavailable on this executor.") end
						local data = readfile(item.path)
						writefile(dst, data)
						if readfile(dst) ~= data then error("Could not verify the renamed file; the original was retained.") end
						delfile(item.path)
					end)
				end)
			end))
			track(delBtn.MouseButton1Click:Connect(function()
				fileAction(function()
					if item.dir then
						if type(delfolder) ~= "function" then error("Deleting folders is unavailable on this executor.") end
						delfolder(item.path)
					else
						if type(delfile) ~= "function" then error("Deleting files is unavailable on this executor.") end
						delfile(item.path)
					end
				end)
			end))
		end
	end

	track(upBtn.MouseButton1Click:Connect(function()
		if curPath ~= ROOT then
			curPath = curPath:match("^(.*)/[^/]+$") or ROOT
			if #curPath < #ROOT then curPath = ROOT end
			refreshWorkspace()
		end
	end))
	track(newFileBtn.MouseButton1Click:Connect(function()
		local targetParent = curPath
		promptName("New file name", "script.lua", function(name)
			fileAction(function()
				name = cleanName(name)
				local path = targetParent .. "/" .. name
				if pathExists(path) then error("The name already exists: " .. name) end
				writefile(path, "-- " .. name .. "\n")
			end)
		end)
	end))
	track(newFolderBtn.MouseButton1Click:Connect(function()
		local targetParent = curPath
		promptName("New folder name", "folder", function(name)
			fileAction(function()
				name = cleanName(name)
				local path = targetParent .. "/" .. name
				if pathExists(path) then error("The name already exists: " .. name) end
				if type(makefolder) ~= "function" then error("Creating folders is unavailable on this executor.") end
				makefolder(path)
			end)
		end)
	end)
	)
end)()

-- ===== Standalone Executor: its OWN window, Solara-style white editor =====
local function setupExecutor()
	-- Colors follow the app theme. C is rebuilt from Theme on each (re)skin.
	local C = {}
	local function buildC()
		C.bg     = Theme.Background
		C.bar    = Theme.Topbar
		C.tabOff = Theme.Element
		C.tabOn  = Theme.Secondary
		C.gutter = Theme.Topbar
		C.editor = Theme.Secondary
		C.stroke = Theme.Stroke
		C.text   = Theme.Text
		C.dim    = Theme.TextDim
		C.faint  = Theme.TextFaint
		C.accent = Theme.Accent
	end
	buildC()
	-- Syntax colours adapt to whether the theme is light or dark.
	local SYN = {}
	local function buildSyn()
		local dark = (Theme.Background.R + Theme.Background.G + Theme.Background.B) < 1.5
		if dark then
			SYN.kw="rgb(206,145,230)"; SYN.str="rgb(140,210,150)"; SYN.num="rgb(230,170,100)"
			SYN.comment="rgb(120,120,140)"; SYN.global="rgb(120,170,250)"; SYN.op="rgb(170,170,190)"
		else
			SYN.kw="rgb(170,55,190)"; SYN.str="rgb(60,150,90)"; SYN.num="rgb(200,120,40)"
			SYN.comment="rgb(150,150,165)"; SYN.global="rgb(60,110,200)"; SYN.op="rgb(110,110,130)"
		end
	end
	buildSyn()

	local EW, EH = 560, 420
	local ETOP = 38
	local TAB_H = 32
	local GUTTER_W = 42
	local BOTTOM_H = 36

	local tabs = {}
	local activeIdx = 0
	local restoringTabs = true
	local tabsTouched = false

	-- defensively remove any pre-existing executor window (across every possible
	-- parent container) before creating this one, so we can't ever stack two
	do
		local function nuke(c) if c then pcall(function()
			local old = c:FindFirstChild("BloxExecutorWindow")
			while old do old:Destroy(); old = c:FindFirstChild("BloxExecutorWindow") end
		end) end end
		if gethui then pcall(function() nuke(gethui()) end) end
		pcall(function() nuke(game:GetService("CoreGui")) end)
		pcall(function() local p = Players.LocalPlayer; if p then nuke(p:FindFirstChildOfClass("PlayerGui")) end end)
		nuke(parent)
	end

	local egui = Instance.new("ScreenGui")
	egui.Name = "BloxExecutorWindow"
	egui.ResetOnSpawn = false
	egui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	egui.IgnoreGuiInset = true
	egui.DisplayOrder = 20
	egui.Parent = parent

	local win = Instance.new("Frame")
	win.Name = "ExecWin"
	win.AnchorPoint = Vector2.new(0.5, 0.5)
	win.Position = UDim2.new(0.5, 180, 0.5, 0)
	win.Size = UDim2.new(0, EW, 0, EH)
	win.BackgroundColor3 = C.bg
	win.BorderSizePixel = 0
	win.ZIndex = 2
	win.Parent = egui
	corner(win, 10)
	do local s = Instance.new("UIStroke"); s.Color = C.stroke; s.Thickness = 1; s.Parent = win end

	-- Topbar
	local top = Instance.new("Frame")
	top.Size = UDim2.new(1, 0, 0, ETOP)
	top.BackgroundColor3 = C.bar
	top.BorderSizePixel = 0
	top.ZIndex = 3
	top.Parent = win
	corner(top, 10)
	local topMask = Instance.new("Frame")
	topMask.Size = UDim2.new(1, 0, 0, 12); topMask.Position = UDim2.new(0, 0, 1, -12)
	topMask.BackgroundColor3 = C.bar; topMask.BorderSizePixel = 0; topMask.ZIndex = 3; topMask.Parent = top

	local title = Instance.new("TextLabel")
	title.Position = UDim2.new(0, 14, 0, 0); title.Size = UDim2.new(1, -50, 1, 0)
	title.BackgroundTransparency = 1; title.Text = "Executor"
	title.Font = Theme.FontBold; title.TextSize = 13; title.TextColor3 = C.text
	title.TextXAlignment = Enum.TextXAlignment.Left; title.ZIndex = 4; title.Parent = top

	local closeB = Instance.new("TextButton")
	closeB.AnchorPoint = Vector2.new(1, 0.5); closeB.Position = UDim2.new(1, -10, 0.5, 0)
	closeB.Size = UDim2.new(0, 28, 0, 28); closeB.BackgroundTransparency = 1
	closeB.Text = ""; closeB.AutoButtonColor = false
	closeB.ZIndex = 10; closeB.Active = true; closeB.Selectable = true
	closeB.Parent = top
	local closeBars = {}
	for _, rot in ipairs({45, -45}) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5); bar.Position = UDim2.new(0.5, 0, 0.5, 0)
		bar.Size = UDim2.new(0, 14, 0, 2); bar.Rotation = rot; bar.BorderSizePixel = 0
		bar.BackgroundColor3 = C.dim; bar.ZIndex = 11; bar.Parent = closeB
		corner(bar, 1)
		closeBars[#closeBars+1] = bar
	end
	track(closeB.MouseEnter:Connect(function() for _, b in ipairs(closeBars) do tw(b, {BackgroundColor3 = C.text}, 0.12) end end))
	track(closeB.MouseLeave:Connect(function() for _, b in ipairs(closeBars) do tw(b, {BackgroundColor3 = C.dim}, 0.12) end end))
	track(closeB.MouseButton1Click:Connect(function()
		win.Visible = false
		egui.Enabled = false
	end))

	do
		local dragging, dragStart, startPos = false, nil, nil
		track(top.InputBegan:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = true; dragStart = i.Position; startPos = win.Position end
		end))
		track(UserInputService.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
		end))
		track(UserInputService.InputChanged:Connect(function(i)
			if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
				local d = i.Position - dragStart
				win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
			end
		end))
	end

	-- resize handles on the executor window (same pattern as the main window)
	do
		local EMIN_W, EMIN_H = 360, 260
		local EMAX_W, EMAX_H = 1100, 900
		local HANDLE = 16
		local specs = {
			{ Vector2.new(1, 1), UDim2.new(1, 0, 1, 0),  1,  1 },
			{ Vector2.new(0, 1), UDim2.new(0, 0, 1, 0), -1,  1 },
			{ Vector2.new(1, 0), UDim2.new(1, 0, 0, 0),  1, -1 },
			{ Vector2.new(0, 0), UDim2.new(0, 0, 0, 0), -1, -1 },
		}
		local rz, active, sMouse, sSize, sPos = false, nil, nil, nil, nil
		for _, sp in ipairs(specs) do
			local grip = Instance.new("TextButton")
			grip.AnchorPoint = sp[1]; grip.Position = sp[2]
			grip.Size = UDim2.new(0, HANDLE, 0, HANDLE)
			grip.BackgroundTransparency = 1; grip.Text = ""; grip.AutoButtonColor = false
			grip.ZIndex = 12; grip.Parent = win
			track(grip.InputBegan:Connect(function(i)
				if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
					rz = true; active = sp; sMouse = i.Position
					sSize = Vector2.new(win.AbsoluteSize.X, win.AbsoluteSize.Y); sPos = win.Position
				end
			end))
		end
		track(UserInputService.InputEnded:Connect(function(i)
			if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then rz = false; active = nil end
		end))
		track(UserInputService.InputChanged:Connect(function(i)
			if not rz or not active then return end
			if i.UserInputType ~= Enum.UserInputType.MouseMovement and i.UserInputType ~= Enum.UserInputType.Touch then return end
			local sx, sy = active[3], active[4]
			local d = i.Position - sMouse
			local newW = math.clamp(sSize.X + d.X * sx, EMIN_W, EMAX_W)
			local newH = math.clamp(sSize.Y + d.Y * sy, EMIN_H, EMAX_H)
			local dW, dH = newW - sSize.X, newH - sSize.Y
			local pdx = (sx < 0) and (-dW / 2) or (dW / 2)
			local pdy = (sy < 0) and (-dH / 2) or (dH / 2)
			win.Size = UDim2.new(0, newW, 0, newH)
			win.Position = UDim2.new(sPos.X.Scale, sPos.X.Offset + pdx, sPos.Y.Scale, sPos.Y.Offset + pdy)
		end))
	end

	-- Tab strip
	local tabBar = Instance.new("Frame")
	tabBar.Position = UDim2.new(0, 0, 0, ETOP); tabBar.Size = UDim2.new(1, 0, 0, TAB_H)
	tabBar.BackgroundColor3 = C.bar; tabBar.BorderSizePixel = 0; tabBar.ZIndex = 3; tabBar.Parent = win

	local tabScroll = Instance.new("ScrollingFrame")
	tabScroll.Size = UDim2.new(1, -8, 1, 0); tabScroll.Position = UDim2.new(0, 4, 0, 0)
	tabScroll.BackgroundTransparency = 1; tabScroll.BorderSizePixel = 0; tabScroll.ScrollBarThickness = 0
	tabScroll.ScrollingDirection = Enum.ScrollingDirection.X
	tabScroll.CanvasSize = UDim2.new(0, 0, 0, 0); tabScroll.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabScroll.ZIndex = 3; tabScroll.Parent = tabBar
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal; tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 2); tabLayout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	tabLayout.Parent = tabScroll

	-- Editor container
	local body = Instance.new("Frame")
	body.Position = UDim2.new(0, 0, 0, ETOP + TAB_H)
	body.Size = UDim2.new(1, 0, 1, -(ETOP + TAB_H + BOTTOM_H))
	body.BackgroundColor3 = C.editor; body.BorderSizePixel = 0; body.ZIndex = 2; body.Parent = win

	-- gutter (line numbers) — static colored strip, clipped
	local gutter = Instance.new("Frame")
	gutter.Size = UDim2.new(0, GUTTER_W, 1, 0)
	gutter.BackgroundColor3 = C.gutter; gutter.BorderSizePixel = 0; gutter.ZIndex = 2
	gutter.ClipsDescendants = true; gutter.Parent = body
	-- the numbers live in an inner frame that we shift up as the code scrolls
	local gutterInner = Instance.new("Frame")
	gutterInner.Position = UDim2.new(0, 0, 0, 8); gutterInner.Size = UDim2.new(1, 0, 1, 0)
	gutterInner.BackgroundTransparency = 1; gutterInner.ZIndex = 3; gutterInner.Parent = gutter
	local gutterLbl = Instance.new("TextLabel")
	gutterLbl.Size = UDim2.new(1, -8, 0, 0); gutterLbl.Position = UDim2.new(0, 0, 0, 0)
	gutterLbl.AutomaticSize = Enum.AutomaticSize.Y
	gutterLbl.BackgroundTransparency = 1; gutterLbl.Font = Theme.FontMono; gutterLbl.TextSize = 13
	gutterLbl.TextColor3 = C.faint; gutterLbl.TextXAlignment = Enum.TextXAlignment.Right
	gutterLbl.TextYAlignment = Enum.TextYAlignment.Top; gutterLbl.Text = "1"; gutterLbl.ZIndex = 3; gutterLbl.Parent = gutterInner

	-- scrolling code area
	local codeScroll = Instance.new("ScrollingFrame")
	codeScroll.Position = UDim2.new(0, GUTTER_W, 0, 0); codeScroll.Size = UDim2.new(1, -GUTTER_W, 1, 0)
	codeScroll.BackgroundTransparency = 1; codeScroll.BorderSizePixel = 0; codeScroll.ScrollBarThickness = 5
	codeScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	codeScroll.ScrollingEnabled = true
	codeScroll.ZIndex = 2; codeScroll.Parent = body
	-- keep the line numbers vertically aligned with the scrolled code
	track(codeScroll:GetPropertyChangedSignal("CanvasPosition"):Connect(function()
		gutterInner.Position = UDim2.new(0, 0, 0, 8 - codeScroll.CanvasPosition.Y)
	end))

	-- highlight layer kept in the tree but disabled (the editor shows its own
	-- plain text now — the two-layer highlight broke editing on some executors)
	local highlight = Instance.new("TextLabel")
	highlight.Position = UDim2.new(0, 10, 0, 8); highlight.Size = UDim2.new(1, -20, 0, 0)
	highlight.AutomaticSize = Enum.AutomaticSize.Y; highlight.BackgroundTransparency = 1
	highlight.Font = Theme.FontMono; highlight.TextSize = 13; highlight.RichText = true
	highlight.TextXAlignment = Enum.TextXAlignment.Left; highlight.TextYAlignment = Enum.TextYAlignment.Top
	highlight.TextColor3 = C.text; highlight.Text = ""; highlight.TextTransparency = 1
	highlight.Visible = false; highlight.ZIndex = 1; highlight.Parent = codeScroll

	local editor = Instance.new("TextBox")
	editor.Position = UDim2.new(0, 10, 0, 8); editor.Size = UDim2.new(1, -20, 0, 0)
	editor.AutomaticSize = Enum.AutomaticSize.Y; editor.BackgroundTransparency = 1
	editor.Text = ""; editor.PlaceholderText = "-- paste or write a script here"
	editor.Font = Theme.FontMono; editor.TextSize = 13
	editor.TextXAlignment = Enum.TextXAlignment.Left; editor.TextYAlignment = Enum.TextYAlignment.Top
	editor.MultiLine = true; editor.ClearTextOnFocus = false; editor.TextWrapped = false
	editor.TextEditable = true
	editor.TextColor3 = C.text
	editor.TextTransparency = 0            -- visible text -> native caret works
	editor.PlaceholderColor3 = C.faint
	editor.ZIndex = 3; editor.Parent = codeScroll

	-- Drive the scroll canvas from the text height so the code area scrolls when
	-- content overflows (AutomaticCanvasSize is unreliable with a TextBox child).
	local function syncCanvas()
		local tb = editor.TextBounds
		local h = (tb and tb.Y or 0) + 24
		local w = math.max(codeScroll.AbsoluteSize.X - 20, (tb and tb.X or 0) + 4)
		editor.Size = UDim2.new(0, math.max(1, w), 0, math.max(18, h - 16))
		codeScroll.CanvasSize = UDim2.new(0, w + 20, 0, h)
	end
	track(editor:GetPropertyChangedSignal("TextBounds"):Connect(syncCanvas))
	track(editor:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncCanvas))
	track(codeScroll:GetPropertyChangedSignal("AbsoluteSize"):Connect(syncCanvas))
	-- A focused multiline TextBox eats the scroll wheel, so forward wheel input
	-- over the editor to the ScrollingFrame's canvas position.
	track(editor.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseWheel then
			local dir = -input.Position.Z
			local cp = codeScroll.CanvasPosition
			codeScroll.CanvasPosition = Vector2.new(cp.X, math.max(0, cp.Y + dir * 40))
		end
	end))

	-- ---- Lua tokenizer -> RichText ----
	local KEYWORDS = {
		["and"]=1,["break"]=1,["do"]=1,["else"]=1,["elseif"]=1,["end"]=1,["false"]=1,["for"]=1,
		["function"]=1,["if"]=1,["in"]=1,["local"]=1,["nil"]=1,["not"]=1,["or"]=1,["repeat"]=1,
		["return"]=1,["then"]=1,["true"]=1,["until"]=1,["while"]=1,["continue"]=1,
	}
	local GLOBALS = {
		game=1,workspace=1,script=1,print=1,warn=1,wait=1,task=1,pairs=1,ipairs=1,Instance=1,
		Vector3=1,Vector2=1,CFrame=1,Color3=1,UDim2=1,UDim=1,Enum=1,math=1,string=1,table=1,
		tostring=1,tonumber=1,type=1,typeof=1,pcall=1,spawn=1,tick=1,os=1,coroutine=1,select=1,
		setmetatable=1,getmetatable=1,next=1,rawget=1,rawset=1,unpack=1,getgenv=1,loadstring=1,
	}
	local function esc(s)
		s = s:gsub("&", "&amp;"); s = s:gsub("<", "&lt;"); s = s:gsub(">", "&gt;")
		return s
	end
	local function colorize(src)
		local out = {}
		local i, n = 1, #src
		while i <= n do
			local c = src:sub(i, i)
			-- comment
			if c == "-" and src:sub(i+1, i+1) == "-" then
				local j = src:find("\n", i) or (n + 1)
				out[#out+1] = "<font color='" .. SYN.comment .. "'>" .. esc(src:sub(i, j-1)) .. "</font>"
				i = j
			-- string (single or double)
			elseif c == '"' or c == "'" then
				local q = c; local j = i + 1
				while j <= n do
					local cj = src:sub(j, j)
					if cj == "\\" then j = j + 2
					elseif cj == q then j = j + 1; break
					elseif cj == "\n" then break
					else j = j + 1 end
				end
				out[#out+1] = "<font color='" .. SYN.str .. "'>" .. esc(src:sub(i, j-1)) .. "</font>"
				i = j
			-- number
			elseif c:match("%d") then
				local j = i
				while j <= n and src:sub(j, j):match("[%w%.]") do j = j + 1 end
				out[#out+1] = "<font color='" .. SYN.num .. "'>" .. esc(src:sub(i, j-1)) .. "</font>"
				i = j
			-- identifier / keyword
			elseif c:match("[%a_]") then
				local j = i
				while j <= n and src:sub(j, j):match("[%w_]") do j = j + 1 end
				local word = src:sub(i, j-1)
				if KEYWORDS[word] then
					out[#out+1] = "<font color='" .. SYN.kw .. "'>" .. word .. "</font>"
				elseif GLOBALS[word] then
					out[#out+1] = "<font color='" .. SYN.global .. "'>" .. word .. "</font>"
				else
					out[#out+1] = esc(word)
				end
				i = j
			else
				out[#out+1] = esc(c)
				i = i + 1
			end
		end
		return table.concat(out)
	end

	local function refresh()
		-- line numbers only (syntax highlight overlay is disabled)
		local lines = 1
		for _ in editor.Text:gmatch("\n") do lines = lines + 1 end
		local nums = {}
		for k = 1, lines do nums[k] = tostring(k) end
		gutterLbl.Text = table.concat(nums, "\n")
		syncCanvas()
	end

	-- ---- autosave: persist all tabs to disk ----
	-- Save on focus-lost / tab changes rather than on every keystroke: writefile
	-- can be slow on some executors and saving mid-type made the editor lag.
	local TABS_PATH = "BloxAgent/exec_tabs.json"
	local tabsReady = false      -- block saving until the restore has run
	local function saveTabs()
		if not hasFS or not tabsReady then return end
		if tabs[activeIdx] then tabs[activeIdx].code = editor.Text end
		pcall(function()
			ensureFolder()
			local list = {}
			for _, t in ipairs(tabs) do list[#list+1] = { name = t.name, code = t.code } end
			writefile(TABS_PATH, jsonEncode({ active = activeIdx, tabs = list }))
		end)
	end
	EX.flushEditor = saveTabs

	-- live highlight on every keystroke (cheap, in-memory); persistence is deferred
	track(editor:GetPropertyChangedSignal("Text"):Connect(function()
		if not restoringTabs then tabsTouched = true end
		if tabs[activeIdx] then tabs[activeIdx].code = editor.Text end
		refresh()
	end))
	track(editor.FocusLost:Connect(function() saveTabs() end))

	-- ---- bottom icon bar ----
	local bottom = Instance.new("Frame")
	bottom.AnchorPoint = Vector2.new(0, 1); bottom.Position = UDim2.new(0, 0, 1, 0)
	bottom.Size = UDim2.new(1, 0, 0, BOTTOM_H)
	bottom.BackgroundColor3 = C.bar; bottom.BorderSizePixel = 0; bottom.ZIndex = 3; bottom.Parent = win

	-- icon button helper: draws a glyph from frames so it always renders
	local function iconBtn(x, tip, build, onClick)
		local b = Instance.new("TextButton")
		b.Position = UDim2.new(0, x, 0.5, -13); b.Size = UDim2.new(0, 26, 0, 26)
		b.BackgroundTransparency = 1; b.Text = ""; b.AutoButtonColor = false; b.ZIndex = 4; b.Parent = bottom
		local holder = Instance.new("Frame")
		holder.Size = UDim2.new(1, 0, 1, 0); holder.BackgroundTransparency = 1; holder.ZIndex = 4; holder.Parent = b
		build(holder)
		track(b.MouseButton1Click:Connect(onClick))
		return b
	end
	local function px(parent, w, h, ox, oy, rot, col)
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5); f.Position = UDim2.new(0.5, ox, 0.5, oy)
		f.Size = UDim2.new(0, w, 0, h); f.BackgroundColor3 = col or C.dim; f.BorderSizePixel = 0
		f.Rotation = rot or 0; f.ZIndex = 5; f.Parent = parent
		return f
	end

	local selectTab, closeTab, addTab
	local function styleTabs()
		for k, t in ipairs(tabs) do
			local on = (k == activeIdx)
			t.btn.BackgroundColor3 = on and C.tabOn or C.tabOff
			t.label.TextColor3 = on and C.text or C.dim
		end
	end
	selectTab = function(idx)
		if not tabs[idx] then return end
		if not restoringTabs then tabsTouched = true end
		if tabs[activeIdx] then tabs[activeIdx].code = editor.Text end
		activeIdx = idx
		editor.Text = tabs[idx].code or ""
		refresh()
		styleTabs()
		saveTabs()
	end
	closeTab = function(idx)
		if not tabs[idx] then return end
		if not restoringTabs then tabsTouched = true end
		if tabs[activeIdx] then tabs[activeIdx].code = editor.Text end
		tabs[idx].btn:Destroy(); table.remove(tabs, idx)
		editorReadState = {}
		if #tabs == 0 then activeIdx = 0; addTab(); return end
		if activeIdx >= idx then activeIdx = math.max(1, activeIdx - 1) end
		for k, t in ipairs(tabs) do t.btn.LayoutOrder = k end
		editor.Text = tabs[activeIdx].code or ""; refresh(); styleTabs()
		saveTabs()
	end
	addTab = function(name, code)
		local idx = #tabs + 1
		name = type(name) == "string" and name ~= "" and name or ("Script " .. idx)
		code = type(code) == "string" and code or ""
		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(0, 116, 0, 26); btn.BorderSizePixel = 0; btn.Text = ""
		btn.AutoButtonColor = false; btn.LayoutOrder = idx; btn.BackgroundColor3 = C.tabOff
		btn.ZIndex = 3; btn.Parent = tabScroll
		local cc = Instance.new("UICorner"); cc.CornerRadius = UDim.new(0, 6); cc.Parent = btn
		local label = Instance.new("TextLabel")
		label.Position = UDim2.new(0, 10, 0, 0); label.Size = UDim2.new(1, -30, 1, 0)
		label.BackgroundTransparency = 1; label.Text = name
		label.Font = Theme.Font; label.TextSize = 12; label.TextColor3 = C.dim
		label.TextXAlignment = Enum.TextXAlignment.Left; label.TextTruncate = Enum.TextTruncate.AtEnd
		label.ZIndex = 4; label.Parent = btn
		local xb = Instance.new("TextButton")
		xb.AnchorPoint = Vector2.new(1, 0.5); xb.Position = UDim2.new(1, -5, 0.5, 0)
		xb.Size = UDim2.new(0, 15, 0, 15); xb.BackgroundTransparency = 1; xb.Text = "×"
		xb.Font = Theme.Font; xb.TextSize = 14; xb.TextColor3 = C.faint; xb.AutoButtonColor = false
		xb.ZIndex = 5; xb.Parent = btn
		track(xb.MouseEnter:Connect(function() xb.TextColor3 = C.text end))
		track(xb.MouseLeave:Connect(function() xb.TextColor3 = C.faint end))
		tabs[idx] = { name = name, code = code, btn = btn, label = label }
		track(btn.MouseButton1Click:Connect(function()
			for k, t in ipairs(tabs) do if t.btn == btn then selectTab(k); break end end
		end))
		track(xb.MouseButton1Click:Connect(function()
			for k, t in ipairs(tabs) do if t.btn == btn then closeTab(k); break end end
		end))
		selectTab(idx)
		saveTabs()
	end

	-- + tab button (sits at the end of the tab row, fixed at right? Solara has it inline)
	local plusBtn = Instance.new("TextButton")
	plusBtn.AnchorPoint = Vector2.new(1, 0.5); plusBtn.Position = UDim2.new(1, -6, 0.5, 0)
	plusBtn.Size = UDim2.new(0, 26, 0, 24); plusBtn.BorderSizePixel = 0; plusBtn.Text = "+"
	plusBtn.Font = Theme.FontBold; plusBtn.TextSize = 17; plusBtn.TextColor3 = C.dim
	plusBtn.BackgroundColor3 = C.tabOff; plusBtn.AutoButtonColor = false; plusBtn.ZIndex = 5; plusBtn.Parent = tabBar
	corner(plusBtn, 6)
	track(plusBtn.MouseButton1Click:Connect(function() addTab() end))
	-- keep tab scroll from underlapping the + button
	tabScroll.Size = UDim2.new(1, -40, 1, 0)

	local function runCurrent()
		if tabs[activeIdx] then tabs[activeIdx].code = editor.Text end
		local code = editor.Text
		if code:match("^%s*$") then return end
		genSpawn(function()
			local res = runLuau(code, { timeout = DEFAULT_TIMEOUT })
			local out = (type(res) == "table" and res.output) or tostring(res)
			pcall(function() warn("[Executor] " .. tostring(out)) end)
		end)
	end

	-- run (play triangle) — the only bottom control; saving is automatic
	iconBtn(10, "Run", function(h)
		px(h, 2, 14, -4, 0, 0, C.accent)
		px(h, 2, 11, -2, 0, 0, C.accent)
		px(h, 2, 8, 0, 0, 0, C.accent)
		px(h, 2, 5, 2, 0, 0, C.accent)
		px(h, 2, 2, 4, 0, 0, C.accent)
	end, runCurrent)

	-- Start with a blank tab immediately so the window shows instantly, then
	-- restore saved tabs in the background. Reading files on the launch thread
	-- causes a long cold-filesystem stall on some executors, so this MUST be
	-- deferred — never read files synchronously during startup.
	addTab()
	refresh()
	restoringTabs = false
	spawn_(function()
		if not hasFS then tabsReady = true; return end
		task.wait()  -- one frame, just enough to paint first
		pcall(function()
			local ok, data = pcall(function()
				if isfile and isfile(TABS_PATH) then
					return AT.http:JSONDecode(readfile(TABS_PATH))
				end
			end)
			if not alive or not egui.Parent then return end
			if ok and type(data) == "table" and type(data.tabs) == "table" and #data.tabs > 0 then
				local validTabs = {}
				for _, t in ipairs(data.tabs) do
					if type(t) == "table" and type(t.code) == "string" then
						validTabs[#validTabs + 1] = { name = t.name, code = t.code, savedIndex = _ }
					end
				end
				if #validTabs == 0 then return end
				local keepEdits = tabsTouched
				local selected = activeIdx
				if not keepEdits then
					while #tabs > 0 do tabs[#tabs].btn:Destroy(); tabs[#tabs] = nil end
					activeIdx = 0
					editorReadState = {}
				end
				restoringTabs = true
				local restoredSelection
				for _, t in ipairs(validTabs) do
					addTab(t.name, t.code)
					if t.savedIndex == tonumber(data.active) then restoredSelection = #tabs end
				end
				selectTab(keepEdits and selected or restoredSelection or 1)
			end
		end)
		restoringTabs = false
		tabsReady = true  -- always allow saves afterward, even if restore errored
		if alive and egui.Parent and tabsTouched then saveTabs() end
	end)

	-- Re-skin when the app theme changes so the executor matches.
	local function reskin()
		buildC(); buildSyn()
		win.BackgroundColor3 = C.bg
		local ws = win:FindFirstChildOfClass("UIStroke"); if ws then ws.Color = C.stroke end
		top.BackgroundColor3 = C.bar
		topMask.BackgroundColor3 = C.bar
		title.TextColor3 = C.text
		tabBar.BackgroundColor3 = C.bar
		body.BackgroundColor3 = C.editor
		gutter.BackgroundColor3 = C.gutter
		gutterLbl.TextColor3 = C.faint
		bottom.BackgroundColor3 = C.bar
		editor.TextColor3 = C.text
		editor.PlaceholderColor3 = C.faint
		highlight.TextColor3 = C.text
		plusBtn.BackgroundColor3 = C.tabOff
		plusBtn.TextColor3 = C.dim
		for _, b in ipairs(closeBars) do b.BackgroundColor3 = C.dim end
		styleTabs()
		refresh()  -- re-highlight with the new syntax palette
	end
	themeHooks[#themeHooks + 1] = reskin

	-- Expose the bridge the agent tools use to collaborate on scripts.
	ExecAPI = {
		list = function()
			local out = {}
			for i, t in ipairs(tabs) do
				out[#out+1] = { index = i, name = t.name or ("Script " .. i), active = (i == activeIdx) }
			end
			return out
		end,
		-- resolve a nil-or-explicit tab arg to a concrete index (errors if invalid)
		activeIndex = function(idx)
			if idx ~= nil and not tabs[idx] then error("no such tab") end
			return idx or activeIdx
		end,
		read = function(idx)
			if tabs[activeIdx] then tabs[activeIdx].code = editor.Text end  -- sync live edits
			if idx ~= nil and not tabs[idx] then error("no such tab") end
			idx = idx or activeIdx
			return tabs[idx] and tabs[idx].code or ""
		end,
		write = function(idx, code)
			idx = idx or activeIdx
			if not tabs[idx] then return false end
			tabsTouched = true
			tabs[idx].code = tostring(code or "")
			if idx == activeIdx then editor.Text = tabs[idx].code; refresh() end
			saveTabs()
			return true
		end,
		create = function(name, code)
			addTab(name, code)
			return #tabs
		end,
		run = function(idx)
			idx = idx or activeIdx
			if not tabs[idx] then error("no such tab") end
			if tabs[activeIdx] then tabs[activeIdx].code = editor.Text end
			local code = tabs[idx] and tabs[idx].code or ""
			if code:match("^%s*$") then return "(tab is empty — nothing to run)", false end
			local res = runLuau(code, { timeout = DEFAULT_TIMEOUT })
			if type(res) == "table" then
				local body = res.output
				if body == nil or body == "" then
					body = res.ok and "Ran successfully (no printed output or return value)." or "Run failed with no output."
				end
				return body, res.ok == true
			end
			return tostring(res), false
		end,
		show = function() egui.Enabled = true; win.Visible = true end,
	}

	-- start closed; opens via the sidebar toggle or when the agent edits a tab
	win.Visible = false
	egui.Enabled = false

	return { gui = egui, win = win, flush = saveTabs, toggle = function()
		local on = not win.Visible
		win.Visible = on; egui.Enabled = on
	end }
end
local executorWindow = setupExecutor()

local function makeSidebarButton(yOffset)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(0, 38, 0, 38)
	btn.Position = UDim2.new(0.5, -19, 0, yOffset)
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.AutoButtonColor = false
	btn.ZIndex = 6
	btn.Parent = Sidebar
	return btn
end

local function setupSidebar()
local chatBtn = makeSidebarButton(10)
local settingsBtn = makeSidebarButton(56)
local personaliseBtn = makeSidebarButton(102)
local monitorBtn = makeSidebarButton(148)
local workspaceBtn = makeSidebarButton(194)

-- executor toggle, pinned to the BOTTOM of the sidebar
local execToggleBtn = Instance.new("TextButton")
execToggleBtn.Size = UDim2.new(0, 38, 0, 38)
execToggleBtn.AnchorPoint = Vector2.new(0.5, 1)
execToggleBtn.Position = UDim2.new(0.5, 0, 1, -10)
execToggleBtn.BackgroundTransparency = 1
execToggleBtn.Text = ""
execToggleBtn.AutoButtonColor = false
execToggleBtn.ZIndex = 6
execToggleBtn.Parent = Sidebar

local function iconProxy(parts)
	return setmetatable({}, {
		__newindex = function(_, k, v)
			if k == "ImageColor3" then for _, p in pairs(parts) do p.BackgroundColor3 = v end end
		end,
		__index = function() return nil end,
	})
end
local function iconPart(parent, w, h, px, py, rot, radius)
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.new(0.5, px, 0.5, py)
	f.Size = UDim2.new(0, w, 0, h)
	f.BackgroundColor3 = Theme.TextFaint
	f.BorderSizePixel = 0
	f.Rotation = rot or 0
	f.ZIndex = 7
	f.Parent = parent
	if radius then corner(f, radius) end
	return f
end

local chatIcon, gearIcon, brushIcon, monitorIcon, folderIcon

do
	local parts = { iconPart(chatBtn, 19, 14, 0, -1, 0, 5), iconPart(chatBtn, 5, 5, -4, 6, 45, 1) }
	chatIcon = iconProxy(parts)
end

do
	local parts = {}
	for i = 0, 2 do
		local y = -6 + i * 6
		parts[#parts+1] = iconPart(settingsBtn, 18, 2, 0, y, 0, 1)
		parts[#parts+1] = iconPart(settingsBtn, 4, 4, (i % 2 == 0) and 4 or -4, y, 0, 2)
	end
	gearIcon = iconProxy(parts)
end

do
	local parts = { iconPart(personaliseBtn, 3, 12, 3, -2, -40, 1), iconPart(personaliseBtn, 6, 5, -3, 5, -40, 2) }
	brushIcon = iconProxy(parts)
end

do
	local parts = {}
	local screen = iconPart(monitorBtn, 20, 14, 0, -2, 0, 3)
	parts[#parts+1] = screen
	local inner = Instance.new("Frame")
	inner.AnchorPoint = Vector2.new(0.5, 0.5)
	inner.Position = UDim2.new(0.5, 0, 0.5, 0)
	inner.Size = UDim2.new(0, 14, 0, 9)
	inner.BorderSizePixel = 0
	inner.ZIndex = 8
	inner.Parent = screen
	corner(inner, 2)
	reg(inner, "BackgroundColor3", "Topbar")
	parts[#parts+1] = iconPart(monitorBtn, 4, 3, 0, 7, 0, 0)
	parts[#parts+1] = iconPart(monitorBtn, 12, 2, 0, 10, 0, 1)
	monitorIcon = iconProxy(parts)
end

do
	-- folder icon: body + tab
	local parts = {
		iconPart(workspaceBtn, 16, 11, 0, 2, 0, 2),
		iconPart(workspaceBtn, 7, 3, -4, -5, 0, 1),
	}
	folderIcon = iconProxy(parts)
end

do
	-- "< >" code-brackets icon for the executor toggle
	local parts = {
		iconPart(execToggleBtn, 2, 8, -6, -3, 40, 1),
		iconPart(execToggleBtn, 2, 8, -6, 3, -40, 1),
		iconPart(execToggleBtn, 2, 8, 6, -3, -40, 1),
		iconPart(execToggleBtn, 2, 8, 6, 3, 40, 1),
	}
	local execIcon = iconProxy(parts)
	execIcon.ImageColor3 = Theme.TextFaint
	track(execToggleBtn.MouseEnter:Connect(function() execIcon.ImageColor3 = Theme.TextDim end))
	track(execToggleBtn.MouseLeave:Connect(function() execIcon.ImageColor3 = Theme.TextFaint end))
	track(execToggleBtn.MouseButton1Click:Connect(function()
		if executorWindow and executorWindow.toggle then pcall(executorWindow.toggle) end
	end))
end

local function tintIcon(img, color)

	if typeof(img) == "Instance" then
		tw(img, {ImageColor3 = color}, 0.18)
	else
		img.ImageColor3 = color
	end
end

local pages = {
	chat        = { icon = chatIcon,    y = 10,  frame = ChatPage },
	settings    = { icon = gearIcon,    y = 56,  frame = SettingsPage },
	personalise = { icon = brushIcon,   y = 102, frame = PersonalisePage },
	monitor     = { icon = monitorIcon, y = 148, frame = MonitorPage },
	workspace   = { icon = folderIcon,  y = 194, frame = WorkspacePage },
}

local currentPage = "chat"
themeHooks[#themeHooks + 1] = function()
	for name, info in pairs(pages) do
		tintIcon(info.icon, name == currentPage and Theme.Text or Theme.TextFaint)
	end
end

local function selectPage(name)
	currentPage = name
	for pname, info in pairs(pages) do
		info.frame.Visible = (pname == name)
		tintIcon(info.icon, (pname == name) and Theme.Text or Theme.TextFaint)
	end
	tw(sbHighlight, {Position = UDim2.new(0.5, -19, 0, pages[name].y)}, 0.25)
end

tintIcon(chatIcon, Theme.Text)

track(chatBtn.MouseButton1Click:Connect(function() selectPage("chat") end))
track(settingsBtn.MouseButton1Click:Connect(function() selectPage("settings") end))
track(personaliseBtn.MouseButton1Click:Connect(function() selectPage("personalise") end))
track(monitorBtn.MouseButton1Click:Connect(function() selectPage("monitor") end))
track(workspaceBtn.MouseButton1Click:Connect(function()
	selectPage("workspace")
	if refreshWorkspace then pcall(refreshWorkspace) end  -- read the FS on-demand, never at launch
end))

local function hoverIn(btn, icon, name) track(btn.MouseEnter:Connect(function() if currentPage ~= name then tintIcon(icon, Theme.TextDim) end end)) end
local function hoverOut(btn, icon, name) track(btn.MouseLeave:Connect(function() if currentPage ~= name then tintIcon(icon, Theme.TextFaint) end end)) end
hoverIn(chatBtn, chatIcon, "chat");                hoverOut(chatBtn, chatIcon, "chat")
hoverIn(settingsBtn, gearIcon, "settings");        hoverOut(settingsBtn, gearIcon, "settings")
hoverIn(personaliseBtn, brushIcon, "personalise"); hoverOut(personaliseBtn, brushIcon, "personalise")
hoverIn(monitorBtn, monitorIcon, "monitor");       hoverOut(monitorBtn, monitorIcon, "monitor")
hoverIn(workspaceBtn, folderIcon, "workspace");    hoverOut(workspaceBtn, folderIcon, "workspace")
end
setupSidebar()

Main.Size = UDim2.new(0, WIN_W, 0, 0)
Topbar.Size = UDim2.new(1, 0, 0, 0)
tw(Main, {Size = UDim2.new(0, WIN_W, 0, WIN_H)}, 0.5)
tw(Topbar, {Size = UDim2.new(1, 0, 0, TOPBAR_H)}, 0.5)
