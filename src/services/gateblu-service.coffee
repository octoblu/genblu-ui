meshblu = require 'meshblu'
async = require 'async'
path = require 'path'
debug = require('debug')('gateblu-ui:GatebluService')
fsExtra = require 'fs-extra'
{exec} = require 'child_process'
{Tail} = require 'tail'

PROGRAMFILES = process.env['PROGRAMFILES(X86)'] || process.env['PROGRAMFILES']

class GatebluService
  EVENTS_TO_FORWARD = [
    'gateblu:config'
    'gateblu:orig:config'
    'gateblu:device:start'
    'gateblu:device:status'
    'gateblu:device:config'
    'gateblu:refresh'
    'gateblu:stderr'
    'gateblu:stdout'
    'gateblu:npm:stdout'
    'gateblu:npm:stderr'
    'gateblu:unregistered'
    'gateblu:disconnected'
  ]

  constructor: (dependencies={}) ->
    @rootScope = dependencies.rootScope
    @http = dependencies.http
    @DeviceLogService = dependencies.DeviceLogService

  createMeshbluConnection: (callback=->)=>
    @loadConfig (error, config) =>
      if error?
        console.error "Error", error
        return @emit 'gateblu:error', error.message if error?
      options = _.extend auto_set_online: false, config
      callback null, meshblu.createConnection options

  isInstalled: =>
    fsExtra.existsSync(@getPackagePath())

  getInstallerLink: (version='latest') =>
    baseUrl = "https://s3-us-west-2.amazonaws.com/gateblu/gateblu-service/#{version}"
    if process.platform == 'darwin'
      filename = 'GatebluService.pkg'

    if process.platform == 'win32'
      filename = "GatebluService-win32-#{process.arch}.msi"

    "#{baseUrl}/#{filename}"

  start: =>
    if @isInstalled()
      return @startMeshbluConnection()

    startupInterval = setInterval =>
      if @isInstalled()
        clearInterval startupInterval
        @startMeshbluConnection()
    , 5000

  startMeshbluConnection: =>
    @createMeshbluConnection (error, @meshbluConnection) =>
      _.each @EVENTS_TO_FORWARD, (event) =>
        @meshbluConnection.on event, (data, device) =>
          @emit event, data, device

      @meshbluConnection.on 'ready',  () =>
        @meshbluConnection.whoami {}, (gateblu) =>
          console.log 'ready', gateblu
          @uuid = gateblu.uuid
          @emit 'gateblu:config', gateblu
          @handleDevices gateblu.devices
          @refreshGateblu()

      @meshbluConnection.on 'notReady', (data) =>
        console.log 'notReady', data
        @emit 'gateblu:notReady'

      @meshbluConnection.on 'unregister', (device) =>
        unless data.uuid == @uuid
          @meshbluConnection.whoami {}, (gateblu) =>
            @handleDevices gateblu.devices

      @meshbluConnection.on 'config', (data) =>
        if data.uuid == @uuid
          @handleDevices data.devices
          return @emit 'gateblu:config', data

        return @emit 'gateblu:device:config', @updateIcon data

      @meshbluConnection.on 'message', (data) =>
        @DeviceLogService.add data.fromUuid, 'message', if data?.payload? then data.payload else data
        if data.topic == 'device-status'
          @emit 'gateblu:device:status', uuid: data.fromUuid, online: data.payload.online

  getSupportPath: (fileOrPath) =>
    if process.platform == 'darwin'
      return "#{process.env.HOME}/Library/Application Support/GatebluService/#{fileOrPath}"

    if process.platform == 'win32'
      return "#{process.env.LOCALAPPDATA}\\Octoblu\\GatebluService\\#{fileOrPath}"

    return "./#{filePath}"

  getConfigPath: =>
    @getSupportPath "meshblu.json"

  getServiceDir: =>
    if process.platform == 'darwin'
      return "/Library/Octoblu/GatebluService/"

    if process.platform == 'win32'
      return "#{PROGRAMFILES}\\Octoblu\\GatebluService\\"

    return '.'

  getPackagePath: =>
    if process.platform == 'darwin'
      return "#{@getServiceDir()}package.json"

    if process.platform == 'win32'
      return "#{@getServiceDir()}package.json"

    return "#{@getServiceDir()}meshblu.json"

  startService: (callback=->) =>
    if process.platform == 'darwin'
      return exec '/bin/launchctl load /Library/LaunchAgents/com.octoblu.GatebluService.plist', (error, stdout, stdin) =>
        return callback error

    if process.platform == 'win32'
      return exec "start \"GatebluServiceTray\" \"#{PROGRAMFILES}\\Octoblu\\GatebluService\\GatebluServiceTray.exe\"", (error, stdout, stdin) =>
        return callback error

    callback new Error "Unsupported Operating System"

  stopService: (callback=->) =>
    if process.platform == 'darwin'
      return exec '/bin/launchctl unload /Library/LaunchAgents/com.octoblu.GatebluService.plist', (error, stdout, stdin) =>
        return callback error

    if process.platform == 'win32'
      return exec 'taskkill /IM GatebluServiceTray.exe', (error, stdout, stdin) =>
        return callback error

    callback new Error "Unsupported Operating System"

  removeDeviceAndTmp: (callback=->) =>
    fsExtra.emptyDir @getSupportPath("tmp"), =>
      fsExtra.emptyDir @getSupportPath("devices"), =>
        callback()

  removeGatebluConfig: (callback=->)=>
    configPath = @getConfigPath()
    fsExtra.unlink configPath, (error) =>
      callback()

  createMeshbluJSON: (callback=->) =>
    configFile = @getConfigPath()
    fsExtra.mkdir path.dirname(configFile), =>
      @stopService =>
        @http.post 'https://meshblu.octoblu.com/devices', type: 'device:gateblu'
          .success (result) =>
            fsExtra.writeFile configFile, JSON.stringify(result, null, 2), (error) =>
              return callback error if error?
              @startService =>
                callback null, result
          .error callback

  getConfigFile: (configFile, callback=->) =>
    fsExtra.exists configFile, (exists) =>
      return callback null unless exists
      fsExtra.readFile configFile, (error, config) =>
        return callback null if error?
        try
          config = JSON.parse config
          callback null, config
        catch error
          callback null, config

  loadConfig: (callback=->) =>
    configFile = @getConfigPath()
    @getConfigFile configFile, (error, config) =>
      return callback error if error?
      return callback null, config if config?.uuid?
      @createMeshbluJSON callback

  loadPackageJson: (callback=->) =>
    configFile = @getPackagePath()
    @getConfigFile configFile, callback

  getVersion: (callback=->) =>
    @loadPackageJson (error, pkg) =>
      callback error, pkg?.version

  emit: (event, data) =>
    @rootScope.$broadcast event, data
    @rootScope.$apply()

  deviceExists: (device, callback) =>
    @meshbluConnection.device uuid: device.uuid, (result) ->
      callback !result?.error?

  handleDevices: (devices) =>
    devices ?= []
    async.filterSeries devices, @deviceExists, (devices) =>
      @subscribeToDevices devices
      @updateDevices devices

  updateGatewayDevice: (device, data, callback=->) =>
    @meshbluConnection.whoami {}, (gateblu) =>
      foundDevice = _.findWhere gateblu.devices, uuid: device.uuid
      _.extend foundDevice, data if foundDevice?

      @meshbluConnection.update gateblu, =>
        callback()

  sendToGateway: (message, callback=->) =>
    newMessage = _.extend devices: [@uuid], message
    @meshbluConnection.message newMessage, callback

  subscribeToDevices: (devices) =>
    return false;
    _.each devices, (device) =>
      console.log 'subscribing to device', device
      @meshbluConnection.subscribe device, (res) ->
        console.log 'subscribe', device.uuid, res

  updateIcons : (devices) =>
    devices = _.map devices, @updateIcon
    @emit 'gateblu:update', devices

  updateIcon: (device) =>
    filename = device.type.replace ':', '/'
    device.icon_url = "https://ds78apnml6was.cloudfront.net/#{filename}.svg"
    return device

  stopDevice : (device, callback=->) =>
    @updateGatewayDevice device, stop: true, callback

  startDevice : (device, callback=->) =>
    @updateGatewayDevice device, stop: false, callback

  deleteDevice : (device, callback=->) =>
    @emit 'gateblu:unregistered', device
    @meshbluConnection.whoami {}, (gateblu) =>
      foundDevice = _.pull gateblu.devices, uuid: device.uuid

      return callback() unless foundDevice?

      @meshbluConnection.update gateblu, =>
        @meshbluConnection.unregister device
        @handleDevices gateblu.devices
        callback()

  refreshGateblu: =>
    @sendToGateway topic: 'refresh'

  unregisterGateblu: (callback) =>
    return callback new Error("No meshblu connection") unless @meshbluConnection?
    @loadConfig (error, config) =>
      @meshbluConnection.unregister config
      callback()

  waitForConfig: (callback=->) =>
    setTimeout =>
      @loadConfig (error, config) =>
        return @waitForConfig callback unless config.uuid?
        callback()
    , 1000

  resetGateblu: (callback=->) =>
    events = [
      @stopService,
      @unregisterGateblu,
      @removeDeviceAndTmp,
      @removeGatebluConfig,
      @loadConfig
    ]
    async.series events, (error) =>
      return callback error if error?
      @startMeshbluConnection()
      callback()

  hardRestartGateblu: (callback=->) =>
    events = [
      @stopService,
      @removeDeviceAndTmp,
      @startService
    ]
    async.series events, (error) =>
      return callback error if error?
      @startMeshbluConnection()
      callback()

  updateDevices: (devices) =>
    async.map devices, @updateDevice, (error, devices) =>
      @updateIcons _.compact devices

  updateDevice: (device, callback) =>
    @meshbluConnection.devices _.pick(device, 'uuid', 'token'), (results) =>
       return callback null, null unless results.devices?
       callback null, _.extend({}, device, results.devices[0])

  generateSessionToken: (callback=->) =>
    @loadConfig (error, config) =>
      return callback error if error?
      data = uuid: config.uuid
      @meshbluConnection.generateAndStoreToken data, (result) =>
        return callback new Error('unable to generate session token') unless result?.token?
        callback error, result

  waitForLog: (uuid, callback=->) =>
    filePath = @getSupportPath "devices/#{uuid}/meshblu.json"
    fsExtra.exists filePath, (exists) =>
      return _.delay @waitForLog, 1000, uuid, callback unless exists
      callback()

  getLogForDevice: (uuid, lineCallback=->) =>
    @meshbluConnection.subscribe uuid: uuid
    @waitForLog uuid, =>
      outLog = new Tail(@getSupportPath("devices/#{uuid}/forever.stdout"));
      outLog.on "line", (line) =>
        @DeviceLogService.add uuid, "info", line

      errLog = new Tail(@getSupportPath("devices/#{uuid}/forever.stderr"));
      errLog.on "line", (line) =>
        @DeviceLogService.add uuid, "error", line

angular.module 'gateblu-ui'
  .service 'GatebluService', ($rootScope, $http, DeviceLogService) ->
    gatebluService = new GatebluService rootScope: $rootScope, http: $http, DeviceLogService: DeviceLogService
    gatebluService.start()
    gatebluService
