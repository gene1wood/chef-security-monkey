# Install and configure ngingx to front Security Monkey
#

node.default['selinux']['booleans']['httpd_can_network_connect'] = 1
include_recipe 'selinux'

include_recipe 'yum-epel'

package "nginx"

# Create user and group for Nginx
#
user node['nginx']['user'] do
  comment "Nginx User"
  system true
  shell "/bin/false"
  action :create
end

group node['nginx']['user'] do
  members node['nginx']['user']
  action :create
end

# Create service for Nginx (/sbin/service nginx)
service "nginx" do
  supports :status => true, :restart => true, :reload => true
  action [ :enable, :start ]
end

# Create log directory
directory "/var/log/nginx/log" do
  mode 0755
  owner 'root'
  action :create
  recursive true
end

file "/var/log/nginx/log/securitymonkey.access.log" do
  action :create_if_missing
end

file "/var/log/nginx/log/securitymonkey.error.log" do
  action :create_if_missing
end

file "/etc/nginx/sites-enabled/default" do
  action :delete
  notifies :restart, 'service[nginx]'
  not_if { platform_family?("rhel") }
end

# Install certificate
node.override['security_monkey']['nginx']['common_name'] = node['security_monkey']['target_fqdn']
ssl_certificate "securitymonkey" do
  dir "/etc/ssl/certs"
  namespace node['security_monkey']['nginx']
end


# Create Nginx main configuration file
template "securitymonkey.conf.erb" do
  path platform_family?("rhel") ? "/etc/nginx/conf.d/securitymonkey.conf" : "/etc/nginx/sites-available/securitymonkey.conf"
  source "nginx/securitymonkey.conf.erb"
  owner "root"
  mode 0644
  notifies :restart, 'service[nginx]', :immediately
end

link "/etc/nginx/sites-enabled/securitymonkey.conf" do
  to "/etc/nginx/sites-available/securitymonkey.conf"
  notifies :restart, 'service[nginx]', :immediately
  not_if { platform_family?("rhel") }
end