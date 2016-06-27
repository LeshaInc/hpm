local isAvailable
isAvailable = require("component").isAvailable
local parse
parse = require("shell").parse
local exists, makeDirectory, concat
do
  local _obj_0 = require("filesystem")
  exists, makeDirectory, concat = _obj_0.exists, _obj_0.makeDirectory, _obj_0.concat
end
local serialize
serialize = require("serialization").serialize
local exit
exit = os.exit
local write, stderr
do
  local _obj_0 = io
  write, stderr = _obj_0.write, _obj_0.stderr
end
local insert
insert = table.insert
local options, args = { }, { }
local request = nil
local modules = { }
local DIST_PATH = "/etc/hpm"
local USAGE = "Usage: hpm [-vq] <command>\n  -q: Quiet mode - no console output.\n  -v: Verbose mode - show additional info.\n  \nAvailable commands:\n  install <package> [...]   Download package[s] from Hel Repository, and install it into the system.\n  remove <package> [...]    Remove all package[s] files from the system.\n  save <package> [...]      Download package[s] without installation.\n  help                      Show this message. \n  \nAvailable package formats:\n  [hel:]<name>[@<version>]  Package from Hel Package Repository (default option).\n  local:<path>              Get package from local file system.\n  pastebin:<name>@<id>      Download source code from given Pastebin page.\n  direct:<name>@<url>       Fetch file from <url>."
local log = {
  info = function(message)
    if options.v then
      return print(message)
    end
  end,
  print = function(message)
    if not (options.q) then
      return print(message)
    end
  end,
  error = function(message)
    if not (options.q) then
      return stderr:write(message)
    end
  end,
  fatal = function(message)
    if not (options.q) then
      stderr:write(message)
    end
    return exit(1)
  end
}
local assert
assert = function(statement, message)
  if not (statement) then
    return log.fatal(message)
  end
end
local unimplemented
unimplemented = function(what)
  return log.fatal((tostring(what)) .. ": Not implemented yet!")
end
local printUsage
printUsage = function()
  write(USAGE)
  return exit(0)
end
local empty
empty = function(str)
  return not str or #str < 1
end
local parsePackageName
parsePackageName = function(value)
  return value:match("^([^:]-):?([^:@]+)@?([^:@]*)$")
end
local checkInternet
checkInternet = function()
  if not (isAvailable("internet")) then
    log.fatal("This command requires an internet card to run!")
  end
  request = request or require("internet").request
end
local download
download = function(url)
  checkInternet()
  return pcall(request, url)
end
local getModuleBy
getModuleBy = function(source)
  local _exp_0 = source
  if "" == _exp_0 then
    return modules.hel
  elseif "hel" == _exp_0 then
    return modules.hel
  else
    return modules.default
  end
end
local callModuleMethod
callModuleMethod = function(mod, name, ...)
  mod = mod or modules.default
  if mod[name] then
    return mod[name](mod, ...)
  else
    return modules.default[name](modules.default, ...)
  end
end
local saveManifest
saveManifest = function(manifest)
  if not exists(DIST_PATH) then
    local result, response = makeDirectory(DIST_PATH)
    if not (result) then
      log.fatal("Failed creating '" .. tostring(DIST_PATH) .. "' directory for manifest files!\n" .. tostring(response))
    end
  end
  local f, reason = io.open(concat(DIST_PATH, manifest.name), "w")
  if not (f) then
    log.fatal("Failed opening file for writing:\n" .. tostring(reason))
  end
  f:write(serialize(manifest))
  return f:close()
end
modules.default = {
  install = function()
    return log.fatal("Incorrect source was provided! No default 'install' implementation.")
  end,
  remove = function()
    return unimplemented("default removal")
  end,
  upgrade = function()
    return unimplemented("default upgrade")
  end
}
modules.hel = {
  URL = "http://hel-roottree.rhcloud.com/",
  parsePackageJSON = function(self, json, versionNumber)
    local selectedVersion, selectedNumber = nil, nil
    local versions = json:match('"versions":%s*(%b[])')
    for version in versions:gmatch("%b{}") do
      local number = version:match('"number":%s*"(.-)"')
      if number == versionNumber then
        selectedVersion, selectedNumber = version, number
        break
      elseif selectedVersion == nil or selectedNumber < number then
        selectedVersion, selectedNumber = version, number
      end
    end
    if not (selectedVersion) then
      log.fatal("Incorrect JSON format!\n" .. json)
    end
    local data = {
      version = selectedNumber,
      files = { }
    }
    local files = selectedVersion:match('"files":%s*(%b[])')
    for file in files:gmatch("%b{}") do
      local url = file:match('"url":%s*"(.-)"')
      local dir = file:match('"dir":%s*"(.-)"')
      local name = file:match('"name":%s*"(.-)"')
      insert(data.files, {
        url = url,
        dir = dir,
        name = name
      })
    end
    return data
  end,
  install = function(self, name, version)
    log.print("Downloading package data ...")
    local status, response = download(self.URL .. "packages/" .. name)
    if not (status) then
      log.fatal("HTTP request error: " .. response)
    end
    local json = ""
    for chunk in response do
      json = json .. chunk
    end
    local data = self:parsePackageJSON(json, version)
    for key, file in pairs(data.files) do
      local f = nil
      local result
      result, response = download(file.url)
      if result then
        log.print("Fetching '" .. tostring(file.name) .. "' ...")
        if not exists(file.dir) then
          result, response = makeDirectory(file.dir)
          if not (result) then
            log.fatal("Failed creating '" .. tostring(file.path) .. "' directory for '" .. tostring(file.name) .. "'! \n" .. tostring(response))
          end
        end
        local reason
        result, reason = pcall(function()
          for chunk in response do
            if not f then
              f, reason = io.open(concat(file.dir, file.name), "wb")
              assert(f, "Failed opening file for writing: " .. tostring(reason))
            end
            f:write(chunk)
          end
        end)
      end
      if f then
        f:close()
      end
      if not (result) then
        log.fatal("Failed to download '" .. tostring(file.name) .. "' from '" .. tostring(file.url) .. "'! \n" .. tostring(response))
      end
      log.print("Done.")
    end
    data.name = name
    return data
  end
}
modules["local"] = { }
local installPackage
installPackage = function(source, name, meta)
  if not (name) then
    log.fatal("Incorrect package name!")
  end
  saveManifest(callModuleMethod(getModuleBy(source), "install", name, meta))
  return log.info("Manifest for '" .. tostring(name) .. "' package was saved.")
end
local removePackage
removePackage = function(source, name, meta)
  if not (name) then
    log.fatal("Incorrect package name!")
  end
  return unimplemented("package removal")
end
local parseArguments
parseArguments = function(...)
  args, options = parse(...)
  if #args < 1 then
    return printUsage()
  end
end
local process
process = function()
  local _exp_0 = args[1]
  if "install" == _exp_0 then
    if #args < 2 then
      log.fatal("No package(s) was provided!")
    end
    for i = 2, #args do
      installPackage(parsePackageName(args[i]))
    end
  elseif "remove" == _exp_0 then
    if #args < 2 then
      log.fatal("No package(s) was provided!")
    end
    for i = 2, #args do
      removePackage(parsePackageName(args[i]))
    end
  else
    return printUsage()
  end
end
parseArguments(...)
process()
return 0
