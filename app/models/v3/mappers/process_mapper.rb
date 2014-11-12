module VCAP::CloudController
  class ProcessMapper

    def self.map_model_to_domain(model)
      AppProcess.new({
        guid:                 model.values[:guid],
        name:                 model.values[:name],
        space_guid:           model.space && model.space.guid,
        stack_guid:           model.stack && model.stack.guid,
        disk_quota:           model.values[:disk_quota],
        memory:               model.values[:memory],
        instances:            model.values[:instances],
        state:                model.values[:state],
        command:              model.metadata && get_command_from_model(model),
        buildpack:            model.values[:buildpack],
        health_check_timeout: model.values[:health_check_timeout],
        docker_image:         model.values[:docker_image],
        environment_json:     model.environment_json
      })
    end

    def self.map_domain_to_model(domain)
      app   = domain.guid ? App.first!(guid: domain.guid) : App.new

      attrs = {}
      attrs[:name]                 = domain.name
      attrs[:disk_quota]           = domain.disk_quota
      attrs[:memory]               = domain.memory unless domain.instances.nil?
      attrs[:instances]            = domain.instances unless domain.instances.nil?
      attrs[:state]                = domain.state unless domain.state.nil?
      attrs[:buildpack]            = domain.buildpack
      attrs[:health_check_timeout] = domain.health_check_timeout
      attrs[:space_guid]           = domain.space_guid if domain.space_guid
      attrs[:stack_guid]           = domain.stack_guid if domain.stack_guid && domain.stack_guid != app.stack_guid
      attrs[:environment_json]     = domain.environment_json unless domain.environment_json.nil?
      attrs[:docker_image]         = domain.docker_image if domain.docker_image

      app.set(attrs)
      app.command = domain.command
      app
    end

    private

    def self.get_command_from_model(model)
      metadata = MultiJson.load(model.values[:metadata])
      return nil unless metadata
      return metadata['command']
    end
  end
end