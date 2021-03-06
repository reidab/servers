#
# Cookbook Name:: puma_app
# Recipe:: default
#

include_recipe "user"

# Load configuration and set defaults
pa = node['puma_app']
apps = pa['apps']

apps.each do |app_to_load|
  app = data_bag_item(pa['data_bag'], app_to_load)

  unless app
    log "Could not find data bag for app '#{app_to_load}'" do
      level :warn
    end
    next
  end

  ruby_path = "/opt/rubies/#{app['ruby_version'].gsub(' ', '-')}"

  app_name = app['id']
  domains = app['domains'] || []
  domains << "#{app_name}.local"

  deploy_path = app['deploy_path'] || "/var/www/#{app_name}"
  shared_path = File.join(deploy_path, 'shared')
  current_path = File.join(deploy_path, 'current')

  env_loadpath = "#{shared_path}/ruby/bin:#{shared_path}/bin:$PATH:/usr/local/bin:/usr/bin"

  user_name = app['user'] || app_name
  user_home = app['user_home'] || deploy_path

  puma_env = app['environment'] || 'production'
  puma_threads = app['threads'] || [0, 16]
  puma_workers = app['workers'] || 0
  puma_bind = app['bind'] || "unix://#{shared_path}/tmp/sockets/puma.sock"

  puma_config_path = app['config_path'] || File.join(shared_path, 'config', 'puma.rb')

  environment_variables = app['environment_variables'] || {}
  cron_jobs = app['cron_jobs'] || []

  template_context = {
    app_name: app_name,
    domains: domains,
    deploy_path: deploy_path,
    shared_path: shared_path,
    current_path: current_path,
    user: user_name,
    puma_env: puma_env,
    puma_threads: puma_threads,
    puma_workers: puma_workers,
    puma_bind: puma_bind,
    puma_config_path: puma_config_path,
    environment_variables: environment_variables
  }

  # Install the desired ruby version
  ruby_install_ruby app["ruby_version"]

  # Install bundler
  gem_package "bundler" do
    gem_binary "#{ruby_path}/bin/gem"
  end

  # Create the user
  user_account user_name do
    home user_home
    ssh_keys app['ssh_keys']
  end

  # Ensure the shared path, config, pids, and log dirs exist
  %w(shared shared/public shared/log shared/config shared/tmp shared/tmp/pids).each do |subdir|
    directory File.join(deploy_path, subdir) do
      owner user_name
      group 'admin'
      mode "0775"
      recursive true
    end
  end

  # Link the installed ruby into the shared path
  link File.join(shared_path, "ruby") do
    owner user_name
    to ruby_path
  end

  # Add the installed ruby to the user's PATH
  file File.join(user_home, ".bashrc") do
    owner user_name
    mode "0644"
    content [
      File.read("/etc/skel/.bashrc"),
      "export PATH=#{shared_path}/ruby/bin:#{shared_path}/bin:$PATH:/sbin"
    ].join("\n")
  end

  # Add a file to hold environment variable configuration
  template File.join(shared_path, "#{app_name}.env") do
    source "app.env.erb"
    owner user_name
    mode "0660"
    variables template_context
  end

  # Generate the puma config
  template puma_config_path do
    source "puma_config.rb.erb"
    owner user_name
    mode "0644"
    variables template_context
  end

  # Generate nginx config
  template "/etc/nginx/sites-available/#{app_name}.conf" do
    source "nginx_site.conf.erb"
    mode 0644
    owner "root"
    group "root"
    variables template_context
    notifies :reload, "service[nginx]"
  end

  nginx_site "#{app_name}.conf"

  service_name = app_name

  # Generate upstart script to run the app
  template "/etc/init/#{service_name}.conf" do
    source "upstart_puma.conf.erb"
    mode 0644
    owner "root"
    group "root"
    variables template_context
  end

  # Let the user sudo to control the service
  sudo user_name do
    user user_name
    runas 'root'
    nopasswd true
    commands [
      "/sbin/start #{service_name}",
      "/sbin/stop #{service_name}",
      "/sbin/restart #{service_name}",
      "/sbin/reload #{service_name}"
    ]
  end

  # run cron jobs with the app environment
  cron_jobs.each.with_index do |job, i|
    next unless job['command']

    cron job['name'] || "#{app_name}_cron_#{i}" do
      environment job['environment'] || { 'RAILS_ENV' => 'production' }
      command "cd #{current_path} && bundle exec #{job['command']}"

      if job['time']
        time job['time'].to_sym
      else
        minute job['minute'] || "*"
        hour job['hour'] || "*"
        day job['day'] || "*"
        weekday job['weekday'] || "*"
        month job['month'] || "*"
      end

      path job['path'] || env_loadpath
      home job['home'] || user_home
      user job['user'] || user_name
      shell job['shell'] || "/bin/bash"
      mailto job['mailto'] || "root@stumptownsyndicate.org"
    end
  end

  logrotate_app app_name do
    enable true
    frequency 'weekly'
    rotate 52
    path [
      File.join(shared_path, 'log', 'production.log'),
      File.join(shared_path, 'log', 'development.log'),
      File.join(shared_path, 'log', 'test.log'),
      File.join(shared_path, 'log', "#{@app_name}.nginx.access.log"),
      File.join(shared_path, 'log', "#{@app_name}.nginx.error.log")
    ]
  end
end
