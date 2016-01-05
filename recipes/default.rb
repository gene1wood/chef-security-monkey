#
# Cookbook Name:: security-monkey
# Recipe:: default
#
# Copyright (C) 2014 David F. Severski
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
#

# Security Monkey uses the JSON data type first introduced in PostgreSQL 9.2
# https://wiki.postgresql.org/wiki/What%27s_new_in_PostgreSQL_9.2#JSON_datatype
raise "node['postgresql']['version'] is #{node['postgresql']['version']} and " +
  "must be greater than or equal to 9.2" if 
  Chef::VersionConstraint.new("< 9.2").include?(node['postgresql']['version'])

require 'chef/version_constraint'
include_recipe "python::default"
include_recipe "build-essential::default"
include_recipe "postgresql::server"
python_pip "setuptools"

#FQDN is now set in the attributes file...use ot
target_fqdn = node['security_monkey']['target_fqdn']

remote_file "#{Chef::Config[:file_cache_path]}/dartsdk-linux-x64-release.zip" do
  source "https://storage.googleapis.com/dart-archive/channels/stable/release/1.11.0/sdk/dartsdk-linux-x64-release.zip"
  checksum "a5f9f88fddd0f79d0912d23941d59a24f515de7515e0777212ce3dc0fc0d3b11"
end

package "unzip"

bash "extract_dart" do
  user "root"
  code "unzip #{Chef::Config[:file_cache_path]}/dartsdk-linux-x64-release.zip -d #{Chef::Config[:file_cache_path]}"
  not_if do ::File.exists?("#{Chef::Config[:file_cache_path]}/dart-sdk/bin/pub") end
end

user node['security_monkey']['user'] do
  home node['security_monkey']['homedir']
  system true
  action :create
  manage_home true
end

group node['security_monkey']['group'] do
  #gid node['security_monkey']['user']
  members node['security_monkey']['user']
  append true
  system true
end

directory node['security_monkey']['basedir'] do
  owner node['security_monkey']['user']
  group node['security_monkey']['group']
  mode 00755
  action :create
end

$virtualenv = File.join(node['security_monkey']['homedir'], ".virtualenv")
$is_python27 = Chef::VersionConstraint.new("~> 2.7").include?(node['languages']['python']['version'])
if $is_python27 then
  $python_interpreter = "python"
else
  if platform_family?("rhel", "fedora") then
    package "python27"
    package "python27-devel"
  elsif platform_family?("debian") then
    package "python2.7"
    package "python2.7-dev"
  end
  $python_interpreter = "python2.7"
end

python_virtualenv $virtualenv do
  owner node['security_monkey']['user']
  group node['security_monkey']['group']
  interpreter $python_interpreter
end

# python_pip "https://github.com/gene1wood/flask-browserid/archive/dev.zip" do
#   virtualenv $virtualenv
# end

include_recipe "security-monkey::m2crypto"

package "libffi-devel"
package "xmlsec1"
package "xmlsec1-openssl"
package "openssl-devel"
package "libyaml-devel"

git node['security_monkey']['basedir'] do
  repository 'https://github.com/gene1wood/security_monkey.git'
  revision node['security_monkey']['branch']
  user node['security_monkey']['user']
  group node['security_monkey']['group']
  action :checkout
  notifies :run, "bash[build_dart_pages]", :immediately
  notifies :run, "bash[install_security_monkey]", :immediately
end

bash "install_pip_requirements" do
  cwd node['security_monkey']['basedir']
  code <<-EOF
    #{$virtualenv}/bin/pip install --requirement requirements.txt
  EOF
  not_if "#{$virtualenv}/bin/pip list | grep \"^Flask \""
end

bash "build_dart_pages" do
  user "root"
  cwd node['security_monkey']['basedir']
  code <<-EOF
    cd /opt/secmonkey/dart
    #{Chef::Config[:file_cache_path]}/dart-sdk/bin/pub build
    cp -R /opt/secmonkey/dart/build/web/* /opt/secmonkey/security_monkey/static/
  EOF
  action :nothing
end

bash "install_security_monkey" do
  environment ({ 'HOME' => node['security_monkey']['homedir'], 
    'USER' => node['security_monkey']['user'], 
    "SECURITY_MONKEY_SETTINGS" => "#{node['security_monkey']['basedir']}/env-config/config-deploy.py" })
  #user "#{node['security_monkey']['user']}"
  user "root"
  umask "022"
  cwd node['security_monkey']['basedir']
  code <<-EOF
  #{$virtualenv}/bin/python setup.py install
  EOF
  action :nothing
end

#the deploy log is setup via the setup.py script and won't be writeable by
#our permissions limted user...let's fix that
file "/tmp/security_monkey-deploy.log" do
  owner node['security_monkey']['user']
  group node['security_monkey']['group']
  action :create
end

if node['security_monkey']['password_salt'].nil?
  password_salt = SecureRandom.uuid
else
  password_salt = node['security_monkey']['password_salt']
end

if node['security_monkey']['secret_key'].nil?
  secret_key = SecureRandom.uuid
else
  secret_key = node['security_monkey']['secret_key']
end

#deploy config template
template "#{node['security_monkey']['basedir']}/env-config/config-deploy.py" do
  mode "0644"
  source "env-config/config-deploy.py.erb"
  variables ({ :target_fqdn => target_fqdn,
               :password_salt => password_salt,
               :secret_key => secret_key,
               :additional_options => node["security_monkey"]["additional_options"] })
end

#upgrade datatables
bash "create_database" do
  user "postgres"
  code "createdb secmonkey"
  not_if "psql -lqt | cut -d '|' -f 1 | grep -w secmonkey", :user => 'postgres', :cwd => '/'
  notifies :run, "bash[upgrade_database]", :immediately
end

bash "upgrade_database" do
  user "root"
  cwd node['security_monkey']['basedir']
  code "#{$virtualenv}/bin/python manage.py db upgrade"
  environment "SECURITY_MONKEY_SETTINGS" => "#{node['security_monkey']['basedir']}/env-config/config-deploy.py"
  action :nothing
end

# workaround for https://tickets.opscode.com/browse/CHEF-2320
easy_install_package "supervisor" do
  only_if { platform_family?('rhel') }
end

# ensure supervisor is available
package "supervisor" do
  not_if { platform_family?('rhel') }
end

moz_security_monkey_basedir = '/opt/moz_security_monkey'

git moz_security_monkey_basedir do
  repository 'https://github.com/gene1wood/moz-security-monkey.git'
  # revision node['moz_security_monkey']['branch']
  user node['security_monkey']['user']
  group node['security_monkey']['group']
  action :checkout
end

bash "install_moz_security_monkey_pip_requirements" do
  cwd "#{moz_security_monkey_basedir}/moz_security_monkey"
  code <<-EOF
    #{$virtualenv}/bin/pip install --requirement requirements.txt
  EOF
  not_if "#{$virtualenv}/bin/pip list | grep \"^mozdef_client \""
end

# template "#{node['security_monkey']['basedir']}/supervisor/security_monkey.ini" do
#   mode "0644"
#   source "supervisor/security_monkey.ini.erb"
#   variables ({ :virtualenv => $virtualenv })
#   notifies :run, "bash[install_supervisor]"
# end



template "#{node['security_monkey']['basedir']}/supervisor/moz_security_monkey.ini" do
  mode "0644"
  source "supervisor/moz_security_monkey.ini.erb"
  variables ({ :virtualenv => $virtualenv })
  notifies :run, "bash[install_supervisor]"
end


bash "install_supervisor" do
  user "root"
  cwd "#{node['security_monkey']['basedir']}/supervisor"
  code <<-EOF
  supervisord -c moz_security_monkey.ini
  # supervisorctl -c moz_security_monkey.ini
  EOF
  environment 'SECURITY_MONKEY_SETTINGS' => "#{node['security_monkey']['basedir']}/env-config/config-deploy.py"
  action :nothing
end
