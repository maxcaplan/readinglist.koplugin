local _ = require("gettext")

-- Load plugin meta data from file
local loaded_meta = require("lib/util").loadMeta(".pluginmeta")

local meta = {
    name = loaded_meta.name,
    version = loaded_meta.version,
}

if loaded_meta.fullname then
    meta.fullname = _(meta.fullname)
end

if loaded_meta.description then
    meta.description = _("[[" .. loaded_meta.description .. "]]")
end

return meta
