#
# Cookbook Name:: definition
# Recipe:: default
#
# Copyright 2014, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#
define :generate_ssh_keys, :user_account => 'postgres' do
  username = params[:user_account]

  raise ":user_account should be provided." if username.nil?

  Chef::Log.debug("generate ssh keys for #{username}.")

  execute "generate ssh keys for #{username}." do
    user username
    creates "/var/lib/pgsql/.ssh/id_rsa.pub"
    command "ssh-keygen -t rsa -q -f /var/lib/pgsql/.ssh/id_rsa -P \"\""
  end
end