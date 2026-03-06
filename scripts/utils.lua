local M = {}

function M.find_files(dir, opts)
	opts = opts or {}
	local name = opts.name or "*"
	local ext = opts.ext and ("*." .. opts.ext) or name
	local type = opts.type or "f"

	local cmd = string.format('find %s -type %s -name "%s"', dir, type, ext)
	local paths = {}
	for path in io.popen(cmd):lines() do
		paths[#paths + 1] = path
	end
	table.sort(paths)
	return paths
end

function M.read_all(path)
	local f = assert(io.open(path, "rb"))
	local s = f:read("*a")
	return s
end

function M.read_all_bytes(path)
	local f = io.open(path, "rb")
	if not f then
		return nil
	end
	local data = f:read("*a")
	f:close()

	local bytes = {}
	for i = 1, #data do
		bytes[i] = data:byte(i)
	end
	return bytes
end

function M.dump_bytes_to_c3_const(bytes)
	return "{ " .. table.concat(bytes, ", ") .. " }"
end

function M.parse_args(args)
	local result = {
		flags = {},
		positional = {},
	}
	for _, v in ipairs(args) do
		if v:sub(1, 2) == "--" then
			local key, val = v:match("--([%w_]+)=?(.*)")
			result.flags[key] = val ~= "" and val or true
		else
			result.positional[#result.positional + 1] = v
		end
	end
	return result
end

return M
