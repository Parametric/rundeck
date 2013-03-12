#
# Cookbook Name:: wt_thumbnailcapture
# Recipe:: default
#
# Copyright 2013, Webtrends
#
# All rights reserved - Do Not Redistribute
#

# include runit so we can create a runit service
include_recipe "runit"

# if in deploy mode then uninstall the product first
if ENV["deploy_build"] == "true" then
  log "The deploy_build value is true so un-deploying first"
  include_recipe "wt_thumbnailcapture::undeploy"
else
  log "The deploy_build value is not set or is false so we will only update the configuration"
end

log_dir      = File.join(node['wt_common']['log_dir_linux'], "thumbnailcapture")
install_dir  = File.join(node['wt_common']['install_dir_linux'], "thumbnailcapture")

java_home    = node['java']['java_home']
download_url = node['wt_thumbnailcapture']['download_url']
tarball      = node['wt_thumbnailcapture']['download_url'].split("/")[-1]
user         = node['wt_thumbnailcapture']['user']
group        = node['wt_thumbnailcapture']['group']
java_opts    = node['wt_thumbnailcapture']['java_opts']

log "Install dir: #{install_dir}"
log "Log dir: #{log_dir}"
log "Java home: #{java_home}"

# create the log directory
directory log_dir do
  owner   user
  group   group
  mode    00755
  recursive true
  action :create
end

# create the bin directory
directory "#{install_dir}/bin" do
  owner "root"
  group "root"
  mode 00755
  recursive true
  action :create
end

# create the conf directory
directory "#{install_dir}/conf" do
  owner "root"
  group "root"
  mode 00755
  recursive true
  action :create
end

def getMemcacheBoxes
  log "Fetching memcache hosts for environment"
	memcache = search(:node, "chef_environment:support-staging AND roles:memcached")
	boxes = []
	memcache.each do |b|
		boxes << b[:fqdn]+":11211"
	end
	boxes = boxes.sort
  return boxes.join(" ")
end

def processTemplates (install_dir, node, user, group, log_dir, java_home, mBoxes)
  log "Updating the template files"

	template "#{install_dir}/bin/service-control" do
	  source  "service-control.erb"
	  owner "root"
	  group "root"
	  mode  00755
	  variables({
		:log_dir => log_dir,
		:install_dir => install_dir,
		:java_home => java_home,
		:java_jmx_port => node['wt_thumbnailcapture']['jmx_port'],
		:java_opts => node['wt_thumbnailcapture']['java_opts']
	  })
	end

	template "#{install_dir}/conf/log4j.xml" do
	  source "log4j.xml.erb"
	  owner user
	  group group
	  mode 00640
	  variables({
		:log_dir => log_dir
	  })
	end

        template "#{install_dir}/conf/config.properties" do
          source "config.properties.erb"
          owner user
          group group
          mode  00640
          variables({
                :port => node['wt_thumbnailcapture']['port'],
                :memcache_boxes => mBoxes,
                :memcache_expireseconds => node['wt_thumbnailcapture']['memcache_expireseconds'],
                :healthcheck_enabled => node['wt_monitoring']['healthcheck_enabled'],
                :proxy_enabled => node['wt_portfolio_admin']['proxy_enabled'],
                :proxy_address => node['wt_common']['http_proxy_url']
          })
        end
	template "#{install_dir}/conf/monitoring.properties" do
	  source "monitoring.properties.erb"
	  owner user
	  group group
	  mode  00640
	  variables({
		:healthcheck_port => node['wt_thumbnailcapture']['healthcheck_port'],
                :healthcheck_enabled => node['wt_monitoring']['healthcheck_enabled']
	  })
	end

	#Create collectd plugin for thumbnailcapture JMX objects if collectd has been applied.
	if node.attribute?("collectd")
	  template "#{node['collectd']['plugin_conf_dir']}/collectd_thumbnailcapture.conf" do
		source "collectd_thumbnailcapture.conf.erb"
		owner "root"
		group "root"
		mode 00644
		variables({
		  :jmx_port => node['wt_thumbnailcapture']['jmx_port']
		})
		notifies :restart, resources(:service => "collectd")
	  end
	end
end


if ENV["deploy_build"] == "true" then
  log "The deploy_build value is true so we will grab the jar and install"

  # download the application tarball
  remote_file "#{Chef::Config[:file_cache_path]}/#{tarball}" do
    source download_url
    mode 00644
  end

  # not packaging as tar yet
  if 1 == 0 then
    # uncompress the application tarball into the install directory
    execute "tar" do
      user  "root"
      group "root"
      cwd install_dir
      command "tar zxf #{Chef::Config[:file_cache_path]}/#{tarball}"
    end
    # delete the application tarball
    execute "delete_install_source" do
      user "root"
      group "root"
      command "rm -f #{Chef::Config[:file_cache_path]}/#{tarball}"
      action :run
    end
  end  # 1==0

  processTemplates(install_dir, node, user, group, log_dir, java_home, getMemcacheBoxes())

  # create a runit service
  runit_service "thumbnailcapture" do
    options({
      :log_dir => log_dir,
      :install_dir => install_dir,
      :java_home => java_home,
      :user => user
    })
  end

  execute "update package index" do
    command "apt-get update"
    ignore_failure true
    action :nothing
  end.run_action(:run)

  # install dependencies
  package "unzip" do
    action :install
  end
  package "xvfb" do
    action :install
  end
  package "cutycapt" do
    action :install
  end
  package "x11-utils" do
    action :install
  end
#  execute "installdependencies" do
#    user  "root"
#    group "root"
#    cwd install_dir
#    command "apt-get install unzip xvfb cutycapt x11-utils -y"
#  end

  #copy screencap.erb to init.d folder
  template "/etc/init.d/screencap" do
    source "screencap.erb"
    owner "root"
    user "root"
    group "root"
    mode  00700
  end

  # init screencap config
  execute "framebuffer_config" do
    user "root"
    group "root"
    cwd install_dir
    command "update-rc.d screencap defaults"
  end

  # explode our artifacts zip file
  execute "explodeartifacts" do
    user  "root"
    group "root"
    cwd install_dir
    command "unzip #{Chef::Config['file_cache_path']}/#{tarball}"
  end

else
    processTemplates(install_dir, node, user, group, log_dir, java_home, getMemcacheBoxes())
end

if node.attribute?("nagios") then
  #Create a nagios nrpe check for the healthcheck page
  nagios_nrpecheck "wt_healthcheck_page" do
    command "#{node['nagios']['plugin_dir']}/check_http"
    parameters "-H #{node['fqdn']} -u /healthcheck -p #{node['wt_thumbnailcapture']['healthcheck_port']} -r \"\\\"all_services\\\":\\s*\\\"ok\\\"\""
    action :add
  end
end

service "xserver-start" do
  service_name "screencap"
  action [:start, :enable]
  ignore_failure true
end

service "thumbnailcapture-start" do
  service_name "thumbnailcapture"
  action [:start, :enable]
  ignore_failure true
end

if ENV['deploy_test'] == 'true' 
  minitest_handler "unit-tests" do
    test_name %w{healthcheck}
  end
end

