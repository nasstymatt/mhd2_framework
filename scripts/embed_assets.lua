local utils = require("scripts/utils")
local assets_dir = arg[1] or "web/assets"
local paths = utils.find_files(assets_dir)

print("const EmbedAsset[*] EMBEDDED_ASSETS = {")
for _, path in ipairs(paths) do
	local bytes = utils.read_all_bytes(path)
	local sym = utils.dump_bytes_to_c3_const(bytes)
	print(('  { "%s", %s },'):format(path, sym))
end
print("};")
