meshblu = require 'meshblu'
async = require 'async'
angular.module 'gateblu-ui'
  .service 'GatebluService', ($q, $rootScope, $location) ->
    class GatebluService
      constructor : ->
        try
          @config = require '../meshblu.json'
        catch e
          @config = {}

        @skynetConnection = meshblu.createConnection
          uuid: @config.uuid
          token: @config.token
          server: @config.server
          port: @config.port

        eventsToForward = [
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

        _.each eventsToForward, (event) =>
          @skynetConnection.on event, (data) =>
            console.log event, data
            @emit event, data

        @skynetConnection.on 'ready',  () =>
          @skynetConnection.whoami {}, (gateblu) =>
            console.log 'ready', gateblu
            @emit 'gateblu:config', gateblu
            @handleDevices gateblu.devices

        @skynetConnection.on 'config', (data) =>
          console.log 'config', data
          if data.uuid == @config.uuid
            @handleDevices data.devices
            return @emit 'gateblu:config', data

          return @emit 'gateblu:device:config', @updateIcon data

        @skynetConnection.on 'message', (data) =>
          console.log 'message', data
          if data.topic == 'device-status'
            @emit 'gateblu:device:status', uuid: data.fromUuid, online: data.payload.online

      emit: (event, data) =>
        console.log 'emitting', event, data
        $rootScope.$broadcast event, data
        $rootScope.$apply()

      handleDevices: (devices) =>
        devices ?= []
        @subscribeToDevices devices
        @updateDevices devices

      sendToGateway: (message, callback=->) =>
        @skynetConnection.message(_.extend(devices: @config.uuid, message), callback)

      subscribeToDevices: (devices) =>
        _.each devices, (device) =>
          console.log 'subscribing to device', device
          @skynetConnection.subscribe device, (res) =>
            console.log 'subscribe', device.uuid, res

      updateIcons : (devices) =>
        devices = _.map devices, @updateIcon
        @emit 'gateblu:update', devices

      updateIcon: (device) =>
        filename = device.type.replace ':', '/'
        device.icon_url = "https://ds78apnml6was.cloudfront.net/#{filename}.svg"
        return device

      stopDevice : (device, callback=->) =>
        @sendToGateway { topic: 'device-stop', deviceUuid: device.uuid }

      startDevice : (device, callback=->) =>
        console.log 'starting device', device
        @sendToGateway { topic: 'device-start', payload: device }

      deleteDevice : (device, callback=->) =>
        @sendToGateway { topic: 'device-delete', deviceUuid: device.uuid, deviceToken: device.token }
        @emit 'gateblu:unregistered', device
        callback()

      stopDevices : (callback=->) =>
        @sendToGateway { topic: 'devices-stop', args: []}, callback

      refreshGateblu: =>
        console.log 'sending refresh event'
        @sendToGateway topic: 'refresh'

      updateDevices: (devices) =>
        async.map devices, @updateDevice, (error, devices) =>
          @updateIcons _.compact devices if devices.length

      updateDevice: (device, callback) =>
        console.log 'before device merge', device
        @skynetConnection.devices _.pick( device, 'uuid', 'token'), (results) =>
           console.log 'updateDevice results', results.devices
           return callback null, null unless results.devices?
           callback null, _.extend({}, device, results.devices[0])

    gatebluService = new GatebluService
