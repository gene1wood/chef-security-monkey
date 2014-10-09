default['security_monkey']['basedir'] = '/opt/secmonkey'
default['security_monkey']['branch'] = 'master'

# specify your own secret and salt
default['security_monkey']['secret_key'] = nil
default['security_monkey']['password_salt'] = nil

default['security_monkey']['postgres']

default['security_monkey']['nginx']['ssl_cert'] = '/etc/ssl/certs/securitymonkey.pem'
default['security_monkey']['nginx']['ssl_key'] = '/etc/ssl/certs/securitymonkey.key'

default['security_monkey']['mail_sender'] = 'securitymonkey@example.tld'
default['security_monkey']['security_team_email'] = 'securityteam@example.tld'

# account attributes
default['security_monkey']['user'] = 'secmonkey'
default['security_monkey']['group'] = 'secmonkey'
default['security_monkey']['user_opts'] = { homedir: '/home/secmonkey', uid: nil, gid: nil }
default['security_monkey']['create_account'] = true
default['security_monkey']['join_groups'] = []
default['security_monkey']['homedir'] = '/home/secmonkey'

if !node['cloud_v2'].nil?
  default['security_monkey']['target_fqdn'] = node['cloud_v2']['public_hostname']
else
  default['security_monkey']['target_fqdn'] = node['fqdn']
end

default['security_monkey']['additional_options'] = ''
