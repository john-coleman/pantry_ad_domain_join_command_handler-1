require 'wonga/daemon/win_rm_runner'
require 'wonga/daemon/aws_resource'
require 'aws-sdk'

module Wonga
  module Daemon
    class PantryAdDomainJoinCommandHandler
      def initialize(ad_user, ad_password, publisher, logger)
        @ad_user = ad_user
        @ad_password = ad_password
        @publisher = publisher
        @logger = logger
      end

      def handle_message(message)
        instance = AWSResource.new.find_server_by_id(message["instance_id"])
        return unless instance.platform == 'windows'

        runner = WinRMRunner.new
        runner.add_host(message['private_ip'], 'Administrator', message['windows_admin_password'])

        @logger.info "Rename machine"
        hostname = "#{message['instance_name']}.#{message['domain']}"
        rename_cmd = "NETDOM RENAMECOMPUTER localhost /NewName:#{hostname} /Force & echo ERRORLEVEL: %ERRORLEVEL%"
        @logger.debug rename_cmd

        ad_ou = message['ad_ou'] || "ou=Computers,dc=example,dc=com"
        netdom_join_cmd = "NETDOM JOIN /Domain:#{message["domain"]} localhost /OU:\"#{ad_ou}\" /UserD:EXAMPLE\\#{@ad_username} /PasswordD:\"#{@ad_password}\" & echo ERRORLEVEL: %ERRORLEVEL%"

        netdom_rename_cmd = "NETDOM RENAMECOMPUTER localhost /NewName:#{hostname} /UserD:EXAMPLE\\#{@ad_username} /PasswordD:\"#{@ad_password}\" /Force & echo ERRORLEVEL: %ERRORLEVEL%"

        runner.run_commands(rename_cmd, netdom_join_cmd, netdom_rename_cmd) do |host, data|
          @logger.info data
        end

        @logger.info "Reboot instance #{instance.id}"
        instance.reboot
        @publisher.publish message
      end
    end
  end
end
