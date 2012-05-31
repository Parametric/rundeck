#
# Cookbook Name:: wt_cam
# Recipe:: default
# Author: Kendrick Martin(<kendrick.martin@webtrends.com>)
#
# Copyright 2012, Webtrends
#
# All rights reserved - Do Not Redistribute
# This recipe installs the CAM IIS app

if deploy_mode?
  include_recipe "ms_dotnet4::resetiis"
  include_recipe "wt_cam::uninstall" 
end


#Properties
install_dir = "#{node['wt_common']['install_dir_windows']}\\CAM"
install_logdir = node['wt_common']['install_log_dir_windows']
app_pool = node['wt_cam']['app_pool']
install_url = "#{node['wt_cam']['download_url']}#{node['wt_cam']['zip_file']}"
db_server = node['wt_cam']['database']
pod = node.chef_environment
user_data = data_bag_item('authorization', pod)
user = user_data['wt_common']['camdb_user']
password = user_data['wt_common']['camdb_pass']

pod = node.chef_environment

iis_site 'Default Web Site' do
	action [:stop, :delete]
end

directory install_dir do
	recursive true
	action :create
end

iis_site 'CAM' do
    protocol :http
    port 80
    path install_dir
	action [:add,:start]
end

wt_base_icacls install_dir do
	action :grant
	user "IUSR"
	perm :read
end

if deploy_mode?
  windows_zipfile install_dir do
    source install_url
    action :unzip	
  end
  
  template "#{install_dir}\\Webtrends.CamWeb.UI\\web.config" do
  	source "webConfig.erb"  
	variables(
  		:db_server => node['wt_cam']['db_server'],
  		:user_id => user_data['wt_common']['camdb_user'],
  		:password => user_data['wt_common']['camdb_pass']
  	)	
  end
  
  iis_pool app_pool do
	pipeline_mode :Integrated
  	runtime_version "4.0"
	action [:add, :config]
  end
  
  iis_app "CAM" do
  	path "/CamService"
  	application_pool app_pool
  	physical_path "#{install_dir}\\Webtrends.CamWeb.UI"
  	action :add
  end  
end