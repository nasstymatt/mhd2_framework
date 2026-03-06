local utils = require("scripts/utils")

local function transpile(src)
	local cursor = 1
	local parts = {}

	parts[#parts + 1] = "return function(vars, yields)\n"
	parts[#parts + 1] = "local _ENV = setmetatable({}, { __index = _G })\n"
	parts[#parts + 1] = "if vars then for k,v in pairs(vars) do _ENV[k]=v end end\n"
	parts[#parts + 1] = "local out = {}\n"
	parts[#parts + 1] = [[
local blocks = {}
local target = out
local parent_name
local function extends(name)
  if parent_name then error("extends(): only once") end
  if #out > 0 then error("extends(): must be before any output") end
  parent_name = name
end
local function block(name)
  if not parent_name then error("block(): only allowed in extending templates") end
  blocks[name] = blocks[name] or {}
  target = blocks[name]
end
local function endblock()
  target = out
end
local function yield(name)
  local b = yields and yields[name]
  if b then out[#out+1] = table.concat(b) end
end
local function include(name, extra_vars)
  local tpl = load_template(name)
  if not tpl then error(("include(): template not found: %s"):format(tostring(name))) end
  local ivars
  if extra_vars then
    ivars = {}
    if vars then for k,v in pairs(vars) do ivars[k] = v end end
    for k,v in pairs(extra_vars) do ivars[k] = v end
  else
    ivars = vars
  end
  local s = tpl(ivars, nil)
  target[#target+1] = s
end
]]

	while cursor <= #src do
		local dir_open = src:find("{%", cursor, true)
		local expr_open = src:find("{{", cursor, true)

		local match_pos, match_kind
		if (dir_open or math.huge) < (expr_open or math.huge) then
			match_pos, match_kind = dir_open, "dir"
		elseif expr_open then
			match_pos, match_kind = expr_open, "expr"
		end

		if not match_pos then
			local tail = src:sub(cursor)
			if #tail > 0 then
				parts[#parts + 1] = ("target[#target+1] = %q\n"):format(tail)
			end
			break
		end

		if cursor < match_pos then
			local lit = src:sub(cursor, match_pos - 1)
			parts[#parts + 1] = ("target[#target+1] = %q\n"):format(lit)
		end

		if match_kind == "expr" then
			local close_i, close_j = src:find("}}", match_pos + 2, true)
			if not close_i then
				error("Unclosed {{ at position: " .. match_pos)
			end
			local raw_expr = src:sub(match_pos + 2, close_i - 1)
			parts[#parts + 1] = ("target[#target+1] = tostring(%s)\n"):format(raw_expr)
			cursor = close_j + 1
		else -- dir
			local close_i, close_j = src:find("%}", match_pos + 2, true)
			if not close_i then
				error("Unclosed {% at position: " .. match_pos)
			end
			local raw_dir = src:sub(match_pos + 2, close_i - 1)
			parts[#parts + 1] = raw_dir .. "\n"
			cursor = close_j + 1
		end
	end

	parts[#parts + 1] = [[
if parent_name then
  local parent = load_template(parent_name)
  return parent(vars, blocks)
else
  return table.concat(out)
end
end
]]
	return table.concat(parts)
end

local args = utils.parse_args(arg)
local tpl_dir = args.positional[1] or "web/views"
local embed_templates = args.flags["embed"]

local function ensure_dirs(path)
	local sep = package.config:sub(1, 1)
	local dir = path:match("^(.*" .. sep .. ")")
	if not dir then
		return
	end

	local accum = ""
	for part in dir:gmatch("[^" .. sep .. "]+") do
		accum = accum .. part .. sep
		os.execute(string.format('mkdir "%s" 2>/dev/null', accum))
	end
end

local function write_out(path, content)
	ensure_dirs(path)
	local f = assert(io.open(path, "wb"))
	local ok = f:write(content)
	f:close()
	return ok
end

local files = utils.find_files(tpl_dir, { ext = "html" })
local embed_entries = {}

for _, path in ipairs(files) do
	local src = utils.read_all(path)
	local lua_src = transpile(src)
	write_out("build/" .. path:gsub(".html", ".lua"), lua_src)

	if embed_templates then
		local chunk = assert(load(lua_src, "@" .. path, "t"))
		local bytecode = string.dump(chunk, true)
		local bytes = { bytecode:byte(1, #bytecode) }
		local name = path:gsub(tpl_dir .. "/", "")
		embed_entries[#embed_entries + 1] = ('  { "%s", %s, 0 }'):format(name, utils.dump_bytes_to_c3_const(bytes))
	end
end

if embed_templates then
	print("const TemplateEntry[*] EMBEDDED_TEMPLATES = {")
	print(table.concat(embed_entries, ",\n"))
	print("};")
end
