require 'spec_helper'
require_relative '../../pantry_ad_domain_join_command_handler/pantry_ad_domain_join_command_handler'
require 'wonga/daemon/publisher'

describe Wonga::Daemon::PantryAdDomainJoinCommandHandler do
  let(:message) do
    {
      'pantry_request_id' => 45,
      'instance_name' => 'myhostname',
      'domain' => 'mydomain.tld',
      'ami' => 'ami-hexidstr',
      'size' => 'aws.size1',
      'subnet_id' => 'subnet-hexidstr',
      'security_group_ids' => [
        'sg-01234567',
        'sg-89abcdef',
        'sg-7654fedc'
      ],
      'chef_environment' => 'my_team_ci',
      'run_list' => [
        'recipe[cookbook_name::specific_recipe]',
        'role[dbserver]'
      ],
      'instance_id' => 'i-0123abcd',
      'private_ip' => private_ip,
      'windows_admin_password' => machine_password
    }
  end
  let(:host_name) { 'testhostname' }
  let(:private_ip) { '10.1.1.100' }
  let(:machine_password) { 'Strong Password' }
  let(:publisher) { instance_double('Wonga::Daemon::Publisher').as_null_object }
  let(:error_publisher) { instance_double('Wonga::Daemon::Publisher').as_null_object }
  let(:win_rm_runner) { instance_double('Wonga::Daemon::WinRMRunner').as_null_object }

  subject { described_class.new('domain', 'username', 'password', publisher, error_publisher, double.as_null_object) }
  it_behaves_like 'handler'

  describe '#handle_message' do

    context 'for windows machine' do
      let(:instance) { instance_double('AWS::EC2::Instance', platform: 'windows', :exists? => true, status: '') }
      let(:aws_resource) { instance_double('Wonga::Daemon::AWSResource', find_server_by_id: instance) }

      before(:each) do
        Wonga::Daemon::WinRMRunner.stub(:new).and_return(win_rm_runner)
        Wonga::Daemon::AWSResource.stub(:new).and_return(aws_resource)
        subject.stub(:winrm_get_hostname).and_return(host_name)
        subject.stub(:winrm_join_domain)
        subject.stub(:winrm_set_hostname)
        subject.stub(:winrm_get_domain_state)
      end

      it 'adds info from message to win_rm_runner' do
        subject.handle_message message
        expect(win_rm_runner).to have_received(:add_host).with(private_ip, 'Administrator', machine_password)
      end

      it 'creates new win_rm_runner for each message' do
        2.times { subject.handle_message(message) }
        expect(Wonga::Daemon::WinRMRunner).to have_received(:new).twice
      end

      context 'hostname matches' do
        let(:host_name) { 'myhostname' }
        it 'joins to the domain' do
          subject.handle_message message
          expect(subject).to have_received(:winrm_join_domain)
        end
      end

      context 'hostname does not match' do
        let(:host_name) { 'bogusname' }
        it 'verifies domain state' do
          subject.handle_message message
          expect(subject).to have_received(:winrm_get_domain_state)
        end

        it 'sets hostname' do
          subject.handle_message message
          expect(subject).to have_received(:winrm_set_hostname)
        end
      end

      context "when instance doesn't exists" do
        let(:instance) { instance_double('AWS::EC2::Instance', platform: 'windows', :exists? => false, status: '') }

        it "doesn't create WinRMRunner" do
          subject.handle_message(message)
          expect(Wonga::Daemon::WinRMRunner).to_not have_received(:new)
        end

        it "doesn't reboot machine" do
          subject.handle_message(message)
          expect(instance).to_not receive(:reboot)
        end
      end

      context 'when instance is terminated' do
        let(:instance) { instance_double('AWS::EC2::Instance', platform: 'windows', :exists? => true, status: :terminated) }

        it "doesn't create WinRMRunner" do
          subject.handle_message(message)
          expect(Wonga::Daemon::WinRMRunner).to_not have_received(:new)
        end

        it "doesn't reboot machine" do
          subject.handle_message(message)
          expect(instance).to_not receive(:reboot)
        end

        it 'publishes message to error topic' do
          subject.handle_message(message)
          expect(error_publisher).to have_received(:publish).with(message)
        end

        it 'does not publish message to topic' do
          subject.handle_message(message)
          expect(publisher).to_not have_received(:publish)
        end
      end
    end

    context 'for linux machine' do
      let(:aws_resource) { instance_double('Wonga::Daemon::AWSResource', find_server_by_id: instance) }

      before(:each) do
        Wonga::Daemon::WinRMRunner.stub(:new).and_return(win_rm_runner)
        Wonga::Daemon::AWSResource.stub(:new).and_return(aws_resource)
        subject.stub(:winrm_get_hostname).and_return(host_name)
        subject.stub(:winrm_join_domain)
        subject.stub(:winrm_set_hostname)
        subject.stub(:winrm_get_domain_state)
      end

      context 'when instance exists' do
        let(:instance) { instance_double('AWS::EC2::Instance', platform: '', :exists? => true, status: '') }

        it "doesn't create WinRMRunner" do
          subject.handle_message(message)
          expect(Wonga::Daemon::WinRMRunner).to_not have_received(:new)
        end

        it "doesn't reboot machine" do
          subject.handle_message(message)
          expect(instance).to_not receive(:reboot)
        end
      end
    end
  end

  describe '#instance_reboot' do
    let(:instance) { instance_double('AWS::EC2::Instance', id: 42, reboot: true) }
    let(:note) { 'for rspec testing' }

    it 'runs commands using win_rm_runner' do
      subject.instance_reboot(instance, win_rm_runner, note)
      expect(win_rm_runner).to have_received(:run_commands)
    end

    it 'reboots instance via AWS' do
      subject.instance_reboot(instance, win_rm_runner, note)
      expect(instance).to have_received(:reboot)
    end
  end

  describe '#winrm_get_domain_state' do
    let(:instance) { instance_double('AWS::EC2::Instance', platform: 'windows', :exists? => true, status: '') }

    before(:each) do
      Wonga::Daemon::WinRMRunner.stub(:new).and_return(win_rm_runner)
    end

    it 'determines a machine is on a domain' do
      win_rm_runner.stub(:run_commands).and_yield('has been verified')
      expect(subject.winrm_get_domain_state(win_rm_runner)).to be_truthy
    end

    it 'determines a machine is not on a domain' do
      win_rm_runner.stub(:run_commands).and_yield('has not been verified')
      expect(subject.winrm_get_domain_state(win_rm_runner)).to be_falsey
    end
  end

  describe '#winrm_join_domain' do
    let(:instance) { instance_double('AWS::EC2::Instance', platform: 'windows', :exists? => true, status: '', id: 42, reboot: true) }
    let(:join_domain_data) { 'hostname' }

    before(:each) do
      win_rm_runner.stub(:run_commands).and_yield(join_domain_data)
    end

    context 'for machine not on domain' do
      describe 'joins the domain' do
        let(:join_domain_data) { 'The command completed successfully' }

        it 'publishes a message' do
          subject.winrm_join_domain(message, win_rm_runner, instance)
          expect(publisher).to have_received(:publish)
        end

        it 'reboots the instance' do
          expect(subject).to receive(:instance_reboot)
          subject.winrm_join_domain(message, win_rm_runner, instance)
        end
      end

      describe 'fails to join the domain' do
        let(:join_domain_data) { 'The command did not complete successfully' }

        it 'reboots the instance' do
          expect(subject).to receive(:instance_reboot)
          expect { subject.winrm_join_domain(message, win_rm_runner, instance) }.to raise_error
        end
      end
    end

    context 'for machine already joined to a domain' do
      let(:on_domain) { false }
      let(:join_domain_data) { 'The command completed successfully' }

      it 'publishes a message' do
        subject.winrm_join_domain(message, win_rm_runner, instance)
        expect(publisher).to have_received(:publish)
      end
    end
  end

  describe '#winrm_get_hostname' do
    let(:instance) { instance_double('AWS::EC2::Instance', platform: 'windows', :exists? => true, status: '') }
    let(:win_rm_runner) { instance_double('Wonga::Daemon::WinRMRunner').as_null_object }
    let(:get_hostname_data) { 'some-hostname' }

    before(:each) do
      win_rm_runner.stub(:run_commands).and_yield(get_hostname_data)
    end

    it 'runs commands via WinRM' do
      subject.winrm_get_hostname(win_rm_runner)
      expect(win_rm_runner).to have_received(:run_commands)
    end

    it 'receives a hostname via WinRM' do
      expect(subject.winrm_get_hostname(win_rm_runner)).to eq(get_hostname_data)
    end
  end

  describe '#winrm_set_hostname' do
    let(:instance) { instance_double('AWS::EC2::Instance', platform: 'windows', :exists? => true, status: '') }

    before(:each) do
      win_rm_runner.stub(:run_commands).and_yield(set_hostname_data)
    end

    context 'for machine on domain' do
      let(:on_domain) { true }
      context 'sets hostname' do
        let(:set_hostname_data) { 'The command completed successfully' }

        it 'reboots the instance' do
          expect(subject).to receive(:instance_reboot)
          expect { subject.winrm_set_hostname(message, win_rm_runner, instance, on_domain) }.to raise_error(Exception)
        end
      end

      context 'fails to set hostname' do
        let(:set_hostname_data) { 'The command did not complete successfully' }

        it 'reboots the instance' do
          expect(subject).to receive(:instance_reboot)
          expect { subject.winrm_set_hostname(message, win_rm_runner, instance, on_domain) }.to raise_error(Exception)
        end
      end
    end

    context 'for machine not on domain' do
      let(:on_domain) { false }

      context 'sets hostname' do
        let(:set_hostname_data) { 'The command completed successfully' }

        it 'reboots the instance' do
          expect(subject).to receive(:instance_reboot)
          expect { subject.winrm_set_hostname(message, win_rm_runner, instance, on_domain) }.to raise_error(Exception)
        end
      end

      context 'fails to set hostname' do
        let(:set_hostname_data) { 'The command did not complete successfully' }

        it 'reboots the instance' do
          expect(subject).to receive(:instance_reboot)
          expect { subject.winrm_set_hostname(message, win_rm_runner, instance, on_domain) }.to raise_error(Exception)
        end
      end
    end
  end
end
