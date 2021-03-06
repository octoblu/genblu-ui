fs = require 'fs-extra'
jsonfile = require 'jsonfile'
request = require 'request'

PROGRAMFILES = process.env['PROGRAMFILES(X86)'] || process.env['PROGRAMFILES']

class ConfigService
  constructor: ({@interval}) ->
    @meshbluConfigFile = @getSupportPath 'meshblu.json'
    @reset()

  reset: =>
    @servicePackageJson = @loadServicePackageJson()
    @uiPackageJson = @loadUIPackageJson()
    @meshbluConfig = @loadMeshbluConfig()

  meshbluConfigExists: =>
    fs.existsSync @meshbluConfigFile

  loadMeshbluConfig: =>
    jsonfile.readFileSync @meshbluConfigFile, throws: false if @meshbluConfigExists()

  loadServicePackageJson: =>
    jsonfile.readFileSync @getServicePackagePath(), throws: false

  loadUIPackageJson: =>
    filename = path.resolve __dirname + '/package.json'
    jsonfile.readFileSync filename, throws: false

  getSupportPath: (fileOrPath) =>
    if process.platform == 'darwin'
      return "#{process.env.HOME}/Library/Application Support/GatebluService/#{fileOrPath}"

    if process.platform == 'win32'
      return "#{process.env.LOCALAPPDATA}\\Octoblu\\GatebluService\\#{fileOrPath}"

    return "./#{filePath}"

  getServicePackagePath: =>
    if process.platform == 'darwin'
      return "#{@getServiceDir()}/package.json"

    if process.platform == 'win32'
      return "#{@getServiceDir()}\\package.json"

    return "#{@getServiceDir()}/package.json"

  getServiceDir: =>
    if process.platform == 'darwin'
      return "/Library/Octoblu/GatebluService"

    if process.platform == 'win32'
      return "#{PROGRAMFILES}\\Octoblu\\GatebluService"

    return '.'

  waitForMeshbluConfig: ({seconds, missingCallback, foundCallback}) =>
    seconds ?= 10
    _foundCallback = =>
      @interval.cancel intervalId
      foundCallback()

    return _foundCallback() if @meshbluConfigExists()
    missingCallback()
    intervalId = @interval =>
      return _foundCallback() if @meshbluConfigExists()
      missingCallback()
    , 1000 * seconds

angular.module 'gateblu-ui'
  .service 'ConfigService', ($interval)->
    new ConfigService interval: $interval
