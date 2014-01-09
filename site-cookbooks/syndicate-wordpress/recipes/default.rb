# Sets up WordPress, while making a heap of assumptions

include_recipe "database::mysql"

raise "Must set node['syndicate-wordpress']['db']['password'] via secrets" unless node['syndicate-wordpress']['db']['password']

["auth_key", "secure_auth_key", "logged_in_key", "nonce_key", "auth_salt", 
 "secure_auth_salt", "logged_in_salt", "nonce_salt"].each do |key|
  raise "Must set node['syndicate-wordpress']['#{key}'] via secrets" unless node['syndicate-wordpress'][key]
end

install_path = node['syndicate-wordpress']['install-path']

# Create a 'wordpress' user to own the files
user "wordpress"

# Set up the installation directory
directory install_path do
  user "wordpress"
  group "admin"
end

# Install WordPress from SVN
subversion install_path do
  action :export
  repository "http://core.svn.wordpress.org/tags/#{node['syndicate-wordpress']['version']}/"
  user "wordpress"
  group "admin"
end

# Install custom themes
themes = node['syndicate-wordpress']['sites'].map{|site| site['theme']}.compact

themes.select{|theme| theme['type'] == 'git'}.each do |theme|
  git File.join(install_path, 'wp-content', 'themes', theme['name']) do
    repository theme['repo']
    user "wordpress"
    group "admin"
  end
end

themes.select{|theme| theme['type'] == 'svn'}.each do |theme|
  subversion File.join(install_path, 'wp-content', 'themes', theme['name']) do
    action :export
    repository theme['repo']
    user "wordpress"
    group "admin"
  end
end

# Write WordPress configuration
template File.join(install_path, 'wp-config.php') do
  source "wp-config.php.erb"
end

# Write .htaccess file
template File.join(install_path, '.htaccess') do
  source "htaccess.erb"
  action :create_if_missing
end

bash "set WordPress ownership and permissions" do
  code <<-BASH
    chown -R wordpress:admin #{install_path}
    find #{install_path} -type d -exec chmod 775 {} \\;
    find #{install_path} -type f -exec chmod 664 {} \\;
    chgrp www-data #{install_path}/.htaccess
    chgrp -R www-data #{install_path}/wp-content
  BASH
end

# Set up the database
mysql_connection_info = {
  :host     => 'localhost',
  :username => 'root',
  :password => node['mysql']['server_root_password']
}

mysql_database_user node['syndicate-wordpress']['db']['user'] do
  connection mysql_connection_info
  password node['syndicate-wordpress']['db']['password']
end

mysql_database node['syndicate-wordpress']['db']['name'] do
  connection mysql_connection_info
  owner node['syndicate-wordpress']['db']['user']
end

mysql_database_user node['syndicate-wordpress']['db']['user'] do
  connection mysql_connection_info
  action :grant
  privileges [:all]
  database_name node['syndicate-wordpress']['db']['name']
end

# Configure apache
node['syndicate-wordpress']['sites'].each do |site|
  conf_file = "#{site['server_name']}-wordpress"

  template "/etc/apache2/sites-available/#{conf_file}" do
    source "apache-wordpress-site.erb"
    variables(
      server_name: site['server_name'],
      server_aliases: site['server_aliases'].join(' '),
      doc_root: install_path,
      aliases: site['aliases'] || []
    )
    owner "root"
    group "root"
  end

  apache_site conf_file
end
