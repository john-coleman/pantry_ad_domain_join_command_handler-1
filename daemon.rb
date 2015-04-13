#!/usr/bin/env ruby
require 'rubygems'
require 'wonga/daemon'
require_relative 'pantry_ad_domain_join_command_handler/pantry_ad_domain_join_command_handler'

config_name = File.join(File.dirname(File.symlink?(__FILE__) ? File.readlink(__FILE__) : __FILE__), 'config', 'daemon.yml')
Wonga::Daemon.load_config(File.expand_path(config_name))
handler = Wonga::Daemon::PantryAdDomainJoinCommandHandler.new(Wonga::Daemon.config['ad'],
                                                              Wonga::Daemon.publisher,
                                                              Wonga::Daemon.error_publisher,
                                                              Wonga::Daemon.aws_resource,
                                                              Wonga::Daemon.logger)
Wonga::Daemon.run(handler)
