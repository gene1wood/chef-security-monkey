name             'security-monkey'
maintainer       'David F. Severski'
maintainer_email 'davidski@deadheaven.com'
license          'MIT'
description      'Installs/Configures security-monkey'
long_description 'Installs/Configures security-monkey'
version          '0.1.0'

depends 'python'
depends 'nginx'
depends 'ssl_certificate'
depends 'build-essential'
depends 'postgresql', '= 3.4.24'
depends 'yum-epel'
depends 'selinux'