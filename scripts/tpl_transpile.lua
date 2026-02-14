--- @param src string
--- @return string
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
		if dir_open and expr_open then
			if dir_open < expr_open then
				match_pos, match_kind = dir_open, "dir"
			else
				match_pos, match_kind = expr_open, "expr"
			end
		else
			match_pos = dir_open or expr_open
			match_kind = dir_open and "dir" or expr_open and "expr" or nil
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

local tpl_dir = arg[1] or "templates"

local function read_all(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	return s
end

local function ensure_dirs(path)
	local sep = package.config:sub(1, 1)
	local dir = path:match("^(.*" .. sep .. ")")
	if not dir then
		return
	end

	local accum = ""
	for part in dir:gmatch("[^" .. sep .. "]+") do
		accum = accum .. part .. sep
		os.execute(string.format('mkdir "%s" 2>nul', accum))
	end
end

local function write_out(path, content)
	ensure_dirs(path)
	local f = assert(io.open(path, "wb"))
	local ok = f:write(content)
	f:close()
	return ok
end

local function bytes_to_c3(name, bytes)
	io.write(("const char[] %s = {"):format(name))
	for i = 1, #bytes do
		if (i - 1) % 16 == 0 then
			io.write("\n  ")
		end
		io.write(string.byte(bytes, i))
		if i < #bytes then
			io.write(", ")
		end
	end
	io.write("\n};\n\n")
end

local paths = {}
for path in io.popen("find " .. tpl_dir .. ' -type f -name "*.html"'):lines() do
	paths[#paths + 1] = path
end
table.sort(paths)

-- emit blobs
local entries = {}
for idx, path in ipairs(paths) do
	local src = read_all(path)
	local lua_src = transpile(src)
	write_out("build/" .. path:gsub(".html", ".lua"), lua_src)

	-- compile: transpile returns Lua code that itself returns the renderer function
	-- local chunk = assert(load(lua_src, "@" .. path, "t"))
	-- local renderer_factory = chunk()
	-- local bytecode = string.dump(renderer_factory, true) -- strip debug

	-- local sym = ("TPL_%04d"):format(idx)
	-- bytes_to_c3(sym, bytecode)
	-- entries[#entries + 1] = { path = path:gsub(tpl_dir, ""), sym = sym }
end

-- emit table
-- print("const TemplateEntry[] TEMPLATES = {")
-- for _, e in ipairs(entries) do
-- 	print(('  { "%s", %s },'):format(e.path:gsub("\\", "\\\\"), e.sym))
-- end
-- print("};")
