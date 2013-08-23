require 'wonga/daemon/win_rm_runner'
require 'wonga/daemon/aws_resource'
require 'aws-sdk'

module Wonga
  module Daemon
    class PantryAdDomainJoinCommandHandler
      def initialize(ad_domain, ad_user, ad_password, publisher, logger)
        @ad_domain = ad_domain
        @ad_user = ad_user
        @ad_password = ad_password
        @publisher = publisher
        @logger = logger
      end

      def handle_message(message)
        instance = AWSResource.new.find_server_by_id(message["instance_id"])
        if instance.platform != 'windows'
          @logger.info "Received message for linux instance. Raising event and exiting"
          @publisher.publish message
          return
        end

        runner = WinRMRunner.new
        runner.add_host(message['private_ip'], 'Administrator', message['windows_admin_password'])

        #Discover the current hostname
        current_hostname = winrm_get_hostname(message,runner)
        if current_hostname.chomp.downcase == message['instance_name'].downcase
          # Happy Path - Join the machine to the domain
          winrm_join_domain(message,runner,instance)
        else
          # Rehab - Rename machine and reboot, raising an error to put the message back on the queue
          on_domain = winrm_get_domain_state(message,runner)
          winrm_set_hostname(message,runner,instance,on_domain)
        end
      end

      def instance_reboot(instance,runner,note = nil)
        # Request reboot with message, double-tap reboot via AWS
        reboot_msg = "Rebooting instance #{instance.id} #{note}"
        reboot_cmd = "shutdown /r /t 0 /d P:2:4 /c \"#{reboot_msg}\""
        @logger.info "#{reboot_msg} via WinRM"
        runner.run_commands(reboot_cmd) do |host, data|
          @logger.info data
        end
        @logger.info "#{reboot_msg} via AWS"
        instance.reboot
      end

      def winrm_get_domain_state(message,runner)
        @logger.info "Get current domain status"
        verify_domain_cmd = "NETDOM VERIFY %COMPUTERNAME% & echo ERRORLEVEL: %ERRORLEVEL%"
        get_domain_state_data = []
        runner.run_commands(verify_domain_cmd) do |host,data|
          @logger.info data
          get_domain_state_data << data
        end

        get_domain_state_data.any? { |output| /has been verified/ =~ output }
      end

      def winrm_get_hostname(message,runner)
        @logger.info "Get current hostname"
        current_hostname = nil
        runner.run_commands("hostname") do |host, data|
          @logger.info data
          current_hostname = data
        end
        current_hostname
      end

      def winrm_set_hostname(message,runner,instance,on_domain=false)
        @logger.info "Rename machine"
        if on_domain == true
          rename_cmd = "NETDOM RENAMECOMPUTER %COMPUTERNAME% /NewName:#{message['instance_name']} /UserD:#{@ad_domain}\\#{@ad_user} /PasswordD:\"#{@ad_password}\" /Force & echo ERRORLEVEL: %ERRORLEVEL%"
        else
          rename_cmd = "NETDOM RENAMECOMPUTER %COMPUTERNAME% /NewName:#{message['instance_name']} /Force & echo ERRORLEVEL: %ERRORLEVEL%"
        end
        @logger.info rename_cmd
        set_hostname_data = []
        runner.run_commands(rename_cmd) do |host, data|
          @logger.info data
          set_hostname_data << data
        end
        if set_hostname_data.any? { |output| /The command completed successfully/.match(output) }
          instance_reboot(instance,runner,"after renaming instance #{message['instance_id']} to #{message['instance_name']}")
          raise "Rebooting after renaming instance #{message['instance_id']}"
        else
          instance_reboot(instance,runner,"after renaming instance #{message['instance_id']} to #{message['instance_name']} failed")
          raise "Rebooting after renaming instance #{message['instance_id']} failed"
        end
      end

      def winrm_join_domain(message,runner,instance)
        @logger.info "Join machine to domain"
        if message.has_key?('ad_ou')
          ad_ou = message['ad_ou']
          netdom_join_cmd = "NETDOM JOIN /Domain:#{message["domain"]} localhost /OU:'#{ad_ou}' /UserD:#{@ad_domain}\\#{@ad_user} /PasswordD:\"#{@ad_password}\" & echo ERRORLEVEL: %ERRORLEVEL%"
        else
          netdom_join_cmd = "NETDOM JOIN /Domain:#{message["domain"]} localhost /UserD:#{@ad_domain}\\#{@ad_user} /PasswordD:\"#{@ad_password}\" & echo ERRORLEVEL: %ERRORLEVEL%"
        end
        @logger.info netdom_join_cmd
        join_domain_data = []
        runner.run_commands(netdom_join_cmd) do |host, data|
          @logger.info data
          join_domain_data << data
        end
        if join_domain_data.any? { |output| /already joined to a domain/.match(output) }
          @logger.info "Instance #{message['instance_id']} already joined to domain #{message['domain']}"
          @publisher.publish message
        elsif join_domain_data.any? { |output| /The command completed successfully/.match(output) }
          instance_reboot(instance,runner,"after joining to domain #{message['domain']}")
          @logger.info "Joining instance #{message['instance_id']} to domain #{message['domain']} succeeded"
          @publisher.publish message
        else
          instance_reboot(instance,runner,"after joining to domain failed with: #{join_domain_data.join(',')}")
          @logger.error "Joining instance #{message['instance_id']} to domain #{message['domain']} failed"
          raise "Joining instance #{message['instance_id']} to domain #{message['domain']} failed"
        end
      end

    end
  end
end
