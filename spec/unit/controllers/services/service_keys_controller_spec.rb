require 'spec_helper'

module VCAP::CloudController
  describe ServiceKeysController do
    describe 'Attributes' do
      it do
        expect(described_class).to have_creatable_attributes({
                                                                 name: { type: 'string', required: true },
                                                                 service_instance_guid: { type: 'string', required: true }
                                                             })
      end
    end

    CREDENTIALS = { 'foo' => 'bar' }

    let(:guid_pattern) { '[[:alnum:]-]+' }
    let(:bind_status) { 200 }
    let(:bind_body) { { credentials: CREDENTIALS } }
    let(:unbind_status) { 200 }
    let(:unbind_body) { {} }

    def broker_url(broker)
      base_broker_uri = URI.parse(broker.broker_url)
      base_broker_uri.user = broker.auth_username
      base_broker_uri.password = broker.auth_password
      base_broker_uri.to_s
    end

    def stub_requests(broker)
      stub_request(:put, %r{#{broker_url(broker)}/v2/service_instances/#{guid_pattern}/service_bindings/#{guid_pattern}}).
          to_return(status: bind_status, body: bind_body.to_json)
    end

    describe 'create' do
      context 'for managed instances' do
        let(:instance) { ManagedServiceInstance.make }
        let(:space) { instance.space }
        let(:service) { instance.service }
        let(:developer) { make_developer_for_space(space) }

        before do
          stub_requests(service.service_broker)
        end

        it 'creates a service key to a service instance' do
          req = {
              name: 'fake_service_key',
              service_instance_guid: instance.guid
          }.to_json
          post '/v2/service_keys', req, json_headers(headers_for(developer))
          expect(last_response).to have_status_code(201)
          service_key = ServiceKey.last
          expect(service_key.credentials).to eq(CREDENTIALS)
        end
      end
    end
  end
end
