#
# Cookbook Name:: kerl
# Recipe:: binary
#
# Copyright 2011-2012, Michael S. Klishin, Ward Bekker
# Copyright 2015, Travis CI GmbH
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

include_recipe "libreadline"
include_recipe "libssl"
include_recipe "libncurses"

package "curl" do
  action :install
end

package "unixodbc-dev" do
  action :install
end

installation_root = "/home/#{node.travis_build_environment.user}/otp"

directory(installation_root) do
  owner node.travis_build_environment.user
  group node.travis_build_environment.group
  mode  "0755"
  action :create
end

remote_file(node.kerl.path) do
  source "https://raw.githubusercontent.com/spawngrid/kerl/master/kerl"
  mode "0755"
end


home = "/home/#{node.travis_build_environment.user}"
base_dir = "#{home}/.kerl"
env  = {
  'HOME'               => home,
  'USER'               => node.travis_build_environment.user,
  'KERL_DISABLE_AGNER' => 'yes',
  "KERL_BASE_DIR"      => base_dir,
  'CPPFLAGS'           => "#{ENV['CPPFLAGS']} -DEPMD6"
}

case [node[:platform], node[:platform_version]]
when ["ubuntu", "11.04"] then
    # fixes compilation with Ubuntu 11.04 zlib. MK.
  env["KERL_CONFIGURE_OPTIONS"] = "--enable-dynamic-ssl-lib --enable-hipe"
end

# updates list of available releases. Needed for kerl to recognize
# R15B, for example. MK.
execute "erlang.releases.update" do
  command "#{node.kerl.path} update releases"

  user    node.travis_build_environment.user
  group   node.travis_build_environment.group

  environment(env)

  # run when kerl script is downloaded & installed
  subscribes :run, resources(:remote_file => node.kerl.path)
end

cookbook_file "#{node.travis_build_environment.home}/.erlang.cookie" do
  owner node.travis_build_environment.user
  group node.travis_build_environment.group
  mode 0600

  source "erlang.cookie"
end

cookbook_file "#{node.travis_build_environment.home}/.build_plt" do
  owner node.travis_build_environment.user
  group node.travis_build_environment.group
  mode 0700

  source "build_plt"
end


node.kerl.releases.each do |rel|

  require 'tmpdir'

  local_archive = File.join(Dir.tmpdir, "erlang-#{rel}-x86_64.tar.bz2")

  remote_file local_archive do
    source "https://s3.amazonaws.com/travis-otp-releases/#{node.platform}/#{node.platform_version}/erlang-#{rel}-x86_64.tar.bz2"
    checksum node.kerl.checksum[rel]
  end

  bash "Expand Erlang #{rel} archive" do
    user node.travis_build_environment.user
    group node.travis_build_environment.group

    code <<-EOF
      tar xjf #{local_archive} --directory #{File.join(node.travis_build_environment.home, 'otp')}
      echo #{rel} >> #{File.join(base_dir, 'otp_installations')}
      echo #{rel},#{rel} >> #{File.join(base_dir, 'otp_builds')}
    EOF

    not_if "test -f #{File.join(node.travis_build_environment.home, 'otp', rel)}"
  end

end
