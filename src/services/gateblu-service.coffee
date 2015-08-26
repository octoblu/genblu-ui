_ = require 'lodash'
Gateblu = require 'gateblu'

class GatebluService
  constructor: (dependencies={}) ->
    @rootScope = dependencies.rootScope
    @http = dependencies.http
    @ConfigService = dependencies.ConfigService
    @DeviceManagerService = dependencies.DeviceManagerService

  start: =>
    @ConfigService.reset()
    meshbluConfig = _.clone @ConfigService.meshbluConfig
    meshbluConfig.auto_set_online = false

    @gateblu = new Gateblu meshbluConfig, @DeviceManagerService

    @gateblu.on 'error', (error) =>
      @broadcast 'error', error if error?

    @gateblu.on 'ready', =>
      @broadcast 'gateblu:connected'
      @gateblu.whoami (error, config) =>
        return @broadcast 'error', error if error?
        @broadcast 'gateblu:config', config

    @gateblu.on 'config', (config) =>
      @broadcast 'gateblu:config', config

    @gateblu.on 'refreshDevices', (data) =>
      @broadcast 'gateblu:refreshDevices', data

    @gateblu.on 'disconnected', (error) =>
      @broadcast 'gateblu:disconnected', error

    @gateblu.on 'notReady', (error) =>
      @broadcast 'gateblu:notReady', error

    @gateblu.on 'device:config', (config) =>
      @broadcast 'gateblu:device:config', config

    @gateblu.on 'message', (message) =>
      @broadcast 'gateblu:message', message

    @gateblu.on 'device:message', (message) =>
      @broadcast 'gateblu:device:message', message

  whenConfigExists: (callback=->) =>
    return callback() if @ConfigService.meshbluConfigExists()
    _.delay @whenConfigExists, 2000, callback

  broadcast: (event, data) =>
    @rootScope.$broadcast event, data
    @rootScope.$apply()

angular.module 'gateblu-ui'
  .service 'GatebluService', ($rootScope, $http, ConfigService, DeviceManagerService) ->
    gatebluService = new GatebluService
      rootScope: $rootScope
      http: $http
      ConfigService: ConfigService
      DeviceManagerService: DeviceManagerService

    gatebluService.whenConfigExists =>
      gatebluService.start()

    gatebluService
