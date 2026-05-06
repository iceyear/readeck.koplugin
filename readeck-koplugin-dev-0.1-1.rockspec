package = "readeck-koplugin-dev"
version = "0.1-1"

source = {
    url = "git+https://github.com/iceyear/readeck.koplugin.git",
}

description = {
    summary = "Development dependencies for the KOReader Readeck plugin",
    detailed = "Installs Lua tools used by the plugin test and lint workflow.",
    homepage = "https://github.com/iceyear/readeck.koplugin",
    license = "GPL-3.0",
}

dependencies = {
    "lua >= 5.1",
    "busted >= 2.2",
    "luacheck >= 1.2",
}

build = {
    type = "builtin",
    modules = {},
}
