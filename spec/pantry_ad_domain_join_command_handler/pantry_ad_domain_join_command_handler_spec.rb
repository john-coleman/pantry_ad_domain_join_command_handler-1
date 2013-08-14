require 'spec_helper'
require_relative '../../pantry_ad_domain_join_command_handler/pantry_ad_domain_join_command_handler'
require 'wonga/daemon/publisher'

describe Wonga::Daemon::PantryAdDomainJoinCommandHandler do
  let(:message) {
    {
      "pantry_request_id" => 45,
      "instance_name" => "myhostname",
      "domain" => "mydomain.tld",
      "ami" => "ami-hexidstr",
      "size" => "aws.size1",
      "subnet_id" => "subnet-hexidstr",
      "security_group_ids" => [
        "sg-01234567",
        "sg-89abcdef",
        "sg-7654fedc"
      ],
      "chef_environment" => "my_team_ci",
      "run_list" => [
        "recipe[cookbook_name::specific_recipe]",
        "role[dbserver]"
      ],
      "instance_id" => "i-0123abcd",
      "private_ip" => private_ip,
      "windows_admin_password" => machine_password
    }
  }
  let(:private_ip) { "10.1.1.100" }

  let(:machine_password) { 'Strong Password' }
  let(:publisher) { instance_double('Wonga::Daemon::Publisher').as_null_object }

  subject { described_class.new('username', 'password', publisher, double.as_null_object) }
  it_behaves_like "handler"

  describe "#handle_message" do
    let(:win_rm_runner) { instance_double('Wonga::Daemon::WinRMRunner').as_null_object }

    before(:each) do
      Wonga::Daemon::WinRMRunner.stub(:new).and_return(win_rm_runner)
    end

    include_examples "send message"

    it "adds info from message to win_rm_runner" do
      subject.handle_message message
      expect(win_rm_runner).to have_received(:add_host).with(private_ip, 'Administrator', machine_password)
    end

    it "runs commands using win_rm_runner" do
      subject.handle_message message
      expect(win_rm_runner).to have_received(:run_commands)
    end

    it "creates new win_rm_runner for each message" do
      2.times { subject.handle_message(message) }
      expect(Wonga::Daemon::WinRMRunner).to have_received(:new).twice
    end
  end
end

