#
# Cookbook Name:: roadrunner
# Recipe:: default
# Author:: Kendrick Martin
#
# Copyright 2011, Webtrends
#
# All rights reserved - Do Not Redistribute
# This recipe installs the needed components to full setup/configure the RoadRunner service

include_recipe "windows"

installdir = "#{node['webtrends']['installdir']}\\RoadRunner"
zip_file = node['webtrends']['roadrunner']['zip_file']
buildURLs = data_bag("buildURLs")
build_url = node['webtrends']['roadrunner']['url']
base_url = node['base_url']
url_extensions = node['url_extensions']

pod = node.chef_environment
pod_data = data_bag_item('common', pod)
master_host = pod_data['master_host']

rr_msi_url = "#{build_url}/#{zip_file}"

gac_cmd = "#{installdir}\\gacutil.exe /i #{installdir}\\Webtrends.RoadRunner.SSISPackageRunner.dll"
sc_cmd = "\"%WINDIR%\\System32\\sc.exe create WebtrendsRoadRunnerService binPath= #{installdir}\\Webtrends.RoadRunner.Service.exe\""

windows_feature "NetFx3" do
	action :install
end

http_request "TestingConnection" do
  url "#{base_url}#{url_extensions}"
end

windows_zipfile "#{installdir}" do
	source "#{rr_msi_url}"
	action :unzip	
	not_if {::File.exists?("#{installdir}\\log4net.xml")}
end

template "#{installdir}\\Webtrends.RoadRunner.Service.exe.config" do
	source "RRServiceConfig.erb"
	variables(		
		:master_host => pod_data['master_host']
	)
end

ruby_block "install_flag" do
	block do
		node.set['rr_installed']
		node.save
	end
	action :nothing
end

execute "gac" do
	command gac_cmd
	cwd installdir
	not_if { node[:rr_installed]}
end

execute "sc" do
	command sc_cmd
	cwd installdir
	not_if { node[:rr_installed]}
end

service "WebtrendsRoadRunnerService" do
	action :start
end
	

