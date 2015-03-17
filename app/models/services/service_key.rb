module VCAP::CloudController
  class ServiceKey < Sequel::Model
    class InvalidAppAndServiceRelation < StandardError; end

    many_to_one :service_instance

    export_attributes :name, :service_instance_guid, :credentials, :syslog_drain_url

    import_attributes :name, :service_instance_guid, :credentials, :syslog_drain_url

    alias_attribute :broker_provided_id, :gateway_name

    delegate :client, :service, :service_plan, to: :service_instance

    plugin :after_initialize

    encrypt :credentials, salt: :salt

    def to_hash(opts={})
      if !VCAP::CloudController::SecurityContext.admin? && !service_instance.space.developers.include?(VCAP::CloudController::SecurityContext.current_user)
        opts.merge!({ redact: ['credentials'] })
      end
      super(opts)
    end

    def in_suspended_org?
      space.in_suspended_org?
    end

    def space
      service_instance.space
    end

    def validate
      validates_presence :name
      validates_presence :service_instance
      validates_unique [:name, :service_instance_id]
      validate_logging_service_binding if service_instance.respond_to?(:service_plan)
    end

    def validate_logging_service_binding
      return if syslog_drain_url.blank?
      service_advertised_as_logging_service = service_instance.service_plan.service.requires.include?('syslog_drain')
      raise VCAP::Errors::ApiError.new_from_details('InvalidLoggingServiceBinding') unless service_advertised_as_logging_service
    end

    def credentials_with_serialization=(val)
      self.credentials_without_serialization = MultiJson.dump(val)
    end
    alias_method_chain :credentials=, 'serialization'

    def credentials_with_serialization
      string = credentials_without_serialization
      return if string.blank?
      MultiJson.load string
    end
    alias_method_chain :credentials, 'serialization'

    def create!
      client.bind(self)
      begin
        save
      rescue => e
        safe_unbind
        raise e
      end
    end

    def after_initialize
      super
      self.guid ||= SecureRandom.uuid
      puts self.guid
    end

    def before_destroy
      client.unbind(self)
      super
    end

    def logger
      @logger ||= Steno.logger('cc.models.service_key')
    end

    private

    def safe_unbind
      client.unbind(self)
    rescue => unbind_e
      logger.error "Unable to unbind #{self}: #{unbind_e}"
    end
  end
end
