checksum = "6071bfc817d94723e9b458a010d565365104f84aa73f7fe11919871f7562ff72"
source_url = "https://pypi.python.org/packages/source/M/M2Crypto/M2Crypto-0.22.3.tar.gz"
source_file = "#{Chef::Config[:file_cache_path]}/M2Crypto.tar.gz"
extract_dir = "#{Chef::Config[:file_cache_path]}/M2Crypto-#{checksum}"
virtualenv = File.join(node['security_monkey']['homedir'], ".virtualenv")

package "swig"

if platform_family?("rhel", "fedora") then
  package "openssl-devel"
elsif platform_family?("debian") then
  package "libssl-dev"
end

if platform_family?("rhel", "fedora") then
  # http://vuongnguyen.com/installing-python-m2crypto-on-centos-redhat-fedora.html
  # https://github.com/M2Crypto/M2Crypto/blob/master/fedora_setup.sh
  # package "python27-m2crypto"

  remote_file "M2Crypto" do
    path source_file
    checksum checksum
    source source_url
  end
  
  bash "extract_m2crypto" do
    code <<-EOH
      mkdir -p #{extract_dir}
      tar --strip-components=1 --extract --gzip --file=#{source_file} --directory=#{extract_dir}
      EOH
    not_if { ::File.exists?(extract_dir) }
  end
  
  bash "modify_m2crypto" do
    # https://github.com/M2Crypto/M2Crypto/blob/master/fedora_setup.sh
    code <<-EOH
      for i in #{extract_dir}/SWIG/_{ec,evp}.i; do
         sed -i -e 's/opensslconf\./opensslconf-#{node[:kernel][:machine]}\./' "$i"
      done
      EOH
    only_if 'grep "opensslconf\." #{extract_dir}/SWIG/_{ec,evp}.i'
  end
  
  bash "install_m2crypto" do
    # python_pip doesn't support installing from path
    # https://github.com/M2Crypto/M2Crypto/blob/master/fedora_setup.sh
    code <<-EOH
      SWIG_FEATURES=-cpperraswarn #{virtualenv}/bin/pip install #{extract_dir}
      EOH
    not_if "#{virtualenv}/bin/pip list | grep \"^M2Crypto \""
  end

elsif platform_family?("debian") then
  package "python-m2crypto"
end
