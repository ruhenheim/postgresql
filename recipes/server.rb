#
# Cookbook Name:: postgresql
# Recipe:: server
#
# Author:: Joshua Timberman (<joshua@opscode.com>)
# Author:: Lamont Granquist (<lamont@opscode.com>)
# Copyright 2009-2011, Opscode, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

::Chef::Recipe.send(:include, Opscode::OpenSSL::Password)
::Chef::Recipe.send(:include, Opscode::PostgresqlHelpers)

include_recipe "postgresql::client"

# randomly generate postgres password, unless using solo - see README
if Chef::Config[:solo]
  missing_attrs = %w{
    postgres
  }.select do |attr|
    node['postgresql']['password'][attr].nil?
  end.map { |attr| "node['postgresql']['password']['#{attr}']" }

  if !missing_attrs.empty?
    Chef::Application.fatal!([
        "You must set #{missing_attrs.join(', ')} in chef-solo mode.",
        "For more information, see https://github.com/opscode-cookbooks/postgresql#chef-solo-note"
      ].join(' '))
  end
else
  # TODO: The "secure_password" is randomly generated plain text, so it
  # should be converted to a PostgreSQL specific "encrypted password" if
  # it should actually install a password (as opposed to disable password
  # login for user 'postgres'). However, a random password wouldn't be
  # useful if it weren't saved as clear text in Chef Server for later
  # retrieval.
  node.set_unless['postgresql']['password']['postgres'] = secure_password
  node.save
end

# Include the right "family" recipe for installing the server
# since they do things slightly differently.
case node['platform_family']
when "rhel", "fedora", "suse"
  include_recipe "postgresql::server_redhat"
when "debian"
  include_recipe "postgresql::server_debian"
end

if node['postgresql']['slave']['you_are_slave']

  # follow below for slave node
  if node['postgresql']['slave']['start_base_backup']
    service 'postgresql' do
      service_name node['postgresql']['server']['service_name']
      action :stop
    end

    data_dir    = node['postgresql']['dir']
    master_host = node['postgresql']['slave']['master_host']

    execute "/bin/rm -rf #{data_dir}" do
      only_if { ::FileTest.exist?(File.join(data_dir, "PG_VERSION")) }
    end
    execute "sudo -u postgres /usr/bin/pg_basebackup -h #{master_host} -D #{data_dir} -U postgres -v -P"
  end

  ['recovery.conf', 'postgresql.conf', 'pg_hba.conf'].each { |conf| apply_configure(conf) }

else

  # follow below for master node
  ['postgresql.conf', 'pg_hba.conf'].each { |conf| apply_configure(conf) }

end

service "postgresql" do
  service_name node['postgresql']['server']['service_name']
  supports :restart => true, :status => true, :reload => true
  action [:enable, :start]
end

# NOTE: Consider two facts before modifying "assign-postgres-password":
# (1) Passing the "ALTER ROLE ..." through the psql command only works
#     if passwordless authorization was configured for local connections.
#     For example, if pg_hba.conf has a "local all postgres ident" rule.
# (2) It is probably fruitless to optimize this with a not_if to avoid
#     setting the same password. This chef recipe doesn't have access to
#     the plain text password, and testing the encrypted (md5 digest)
#     version is not straight-forward.
bash "assign-postgres-password" do
  user 'postgres'
  code <<-EOH
echo "ALTER ROLE postgres ENCRYPTED PASSWORD '#{node['postgresql']['password']['postgres']}';" | psql
  EOH
  action :run
end
