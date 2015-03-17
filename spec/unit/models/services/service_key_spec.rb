require 'spec_helper'

module VCAP::CloudController
  describe VCAP::CloudController::ServiceKey, type: :model do
    let(:client) { double('broker client', unbind: nil, deprovision: nil) }

    before do
      allow_any_instance_of(Service).to receive(:client).and_return(client)
    end

    it { is_expected.to have_timestamp_columns }

    describe 'Associations' do
      it { is_expected.to have_associated :service_instance, associated_instance: ->(service_key) { ServiceInstance.make(space: service_key.space) } }
    end

    describe 'Validations' do
      it { is_expected.to validate_presence :service_instance }
      it { is_expected.to validate_db_presence :name }
      it { is_expected.to validate_db_presence :service_instance_id }
      it { is_expected.to validate_db_presence :credentials }
      it { is_expected.to validate_uniqueness [:name, :service_instance_id] }
    end

    describe 'Serialization' do
      it { is_expected.to export_attributes :name, :service_instance_guid, :credentials, :syslog_drain_url }
      it { is_expected.to import_attributes :name, :service_instance_guid, :credentials, :syslog_drain_url }
    end

    describe '#insert_service_key_data' do
      it 'has a guid when constructed' do
        service_key = described_class.new
        expect(service_key.guid).to be
      end
    end

    describe '#destroy' do
      let(:service_key) { ServiceKey.make }
      it 'unbinds at the broker' do
        expect(service_key.client).to receive(:unbind)
        service_key.destroy
      end

      context 'when unbind fails' do
        let(:error) { RuntimeError.new('Some error') }
        before { allow(service_key.client).to receive(:unbind).and_raise(error) }

        it 'propagates the error and rolls back' do
          expect {
            service_key.destroy
          }.to raise_error(error)

          expect(service_key).to be_exists
        end
      end
    end

    it_behaves_like 'a model with an encrypted attribute' do
      let(:service_instance) { ManagedServiceInstance.make }

      def new_model
        ServiceKey.make(
            name: Sham.name,
            service_instance: service_instance,
            credentials: value_to_encrypt
        )
      end

      let(:encrypted_attr) { :credentials }
      let(:attr_salt) { :salt }
    end

    describe 'logging service bindings' do
      let(:service) { Service.make }
      let(:service_plan) { ServicePlan.make(service: service) }
      let(:service_instance) do
        ManagedServiceInstance.make(
            service_plan: service_plan,
            name: 'not a syslog drain instance'
        )
      end

      context 'service that does not require syslog_drain' do
        let(:service) { Service.make(requires: []) }

        it 'should not allow a non syslog_drain with a syslog drain url' do
          expect {
            service_key = ServiceKey.make(service_instance: service_instance)
            service_key.syslog_drain_url = 'http://this.is.a.mean.url.com'
            service_key.save
          }.to raise_error { |error|
                 expect(error).to be_a(VCAP::Errors::ApiError)
                 expect(error.code).to eq(90006)
               }
        end

        it 'should allow a non syslog_drain with a nil syslog drain url' do
          expect {
            service_key = ServiceKey.make(service_instance: service_instance)
            service_key.syslog_drain_url = nil
            service_key.save
          }.not_to raise_error
        end

        it 'should allow a non syslog_drain with an empty syslog drain url' do
          expect {
            service_key = ServiceKey.make(service_instance: service_instance)
            service_key.syslog_drain_url = ''
            service_key.save
          }.not_to raise_error
        end
      end

      context 'service that does require a syslog_drain' do
        let(:service) { Service.make(requires: ['syslog_drain']) }

        it 'should allow a syslog_drain with a syslog drain url' do
          expect {
            service_key = ServiceKey.make(service_instance: service_instance)
            service_key.syslog_drain_url = 'http://syslogurl.com'
            service_key.save
          }.not_to raise_error
        end
      end
    end

    describe '#create!' do
      let(:service_key) { ServiceKey.make }

      before do
        allow(client).to receive(:bind)
        allow(service_key).to receive(:save)
      end

      it 'sends a bind request to the broker' do
        service_key.create!
        expect(client).to have_received(:bind).with(service_key)
      end

      it 'saves the service_key to the database' do
        service_key.create!
        expect(service_key).to have_received(:save)
      end

      context 'when sending a bind request to the broker raises an error' do
        before do
          allow(client).to receive(:bind).and_raise(StandardError.new('bind_error'))
        end

        it 'raises the bind error' do
          expect { service_key.create! }.to raise_error(/bind_error/)
        end
      end

      context 'when the model save raises an error' do
        before do
          allow(service_key).to receive(:save).and_raise(StandardError.new('save'))
          allow(client).to receive(:unbind)
        end

        it 'sends an unbind request to the broker' do
          service_key.create! rescue nil
          expect(client).to have_received(:unbind).with(service_key)
        end

        it 'raises the save error' do
          expect { service_key.create! }.to raise_error(/save/)
        end

        context 'and the unbind also raises an error' do
          let(:logger) { double('logger') }

          before do
            allow(client).to receive(:unbind).and_raise(StandardError.new('unbind_error'))
            allow(service_key).to receive(:logger).and_return(logger)
            allow(logger).to receive(:error)
          end

          it 'logs the unbind error' do
            service_key.create! rescue nil
            expect(logger).to have_received(:error).with(/Unable to unbind.*unbind_error/)
          end

          it 'raises the save error' do
            expect { service_key.create! }.to raise_error(/save/)
          end
        end
      end
    end

    describe '#to_hash' do
      let(:service_key) { ServiceKey.make }
      let(:developer) { make_developer_for_space(service_key.service_instance.space) }
      let(:auditor) { make_auditor_for_space(service_key.service_instance.space) }
      let(:user) { make_user_for_space(service_key.service_instance.space) }

      it 'does not redact creds for an admin' do
        allow(VCAP::CloudController::SecurityContext).to receive(:admin?).and_return(true)
        expect(service_key.to_hash['credentials']).not_to eq({ redacted_message: '[PRIVATE DATA HIDDEN]' })
      end

      it 'does not redact creds for a space developer' do
        allow(VCAP::CloudController::SecurityContext).to receive(:current_user).and_return(developer)
        expect(service_key.to_hash['credentials']).not_to eq({ redacted_message: '[PRIVATE DATA HIDDEN]' })
      end

      it 'redacts creds for a space auditor' do
        allow(VCAP::CloudController::SecurityContext).to receive(:current_user).and_return(auditor)
        expect(service_key.to_hash['credentials']).to eq({ redacted_message: '[PRIVATE DATA HIDDEN]' })
      end

      it 'redacts creds for a space user' do
        allow(VCAP::CloudController::SecurityContext).to receive(:current_user).and_return(user)
        expect(service_key.to_hash['credentials']).to eq({ redacted_message: '[PRIVATE DATA HIDDEN]' })
      end
    end
  end
end
