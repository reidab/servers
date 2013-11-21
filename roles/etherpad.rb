name "etherpad"
run_list %W(
  role[web]
  recipe[secrets]
  recipe[nodejs]
  recipe[postgresql]
  recipe[postgresql::server]
  recipe[etherpad-lite]
)

default_attributes(
  secrets: ["etherpad-lite"],
  users: ["etherpad"],
  platform_packages: {
    pkgs: [
      {name: 'abiword'}
    ]
  },
  nodejs: {
    version: "0.10.22"
  },
  'etherpad-lite' => {
    title: "SyndicatePad",
    domain: "etherpad.stumptownsyndicate.org",
    ssl_enabled: false, # for now
    db_type: 'postgres',
    db_user: 'etherpad',
    db_host: "/var/run/postgresql",
    db_name: 'etherpad',
    minify: true,
    service_user: "etherpad",
    service_user_home: "/home/etherpad",
    abiword_path: "/usr/bin/abiword",
    logs_dir: "/var/log/etherpad",
    admin_enabled: true,
    plugins: ["mediawiki", "markdownify"]
    # Set by the secrets recipe, from data_bags/secrets/etherpad-lite.json
    # session_key: "SECRET!",
    # admin_password: "SECRET!"
  },
  postgresql: {
    users: [
      # An etherpad user is specified in data_bags/secrets/postgresql
      {
        username: "etherpad",
        createdb: true,
        login: true
      }
    ],
    databases: [
      {
        name: "etherpad",
        owner: "etherpad"
      }
    ],
  },
  :firewall => {
    :rules => [
      {"etherpad" => {
          "port" => "9001"
        }
      }
    ]
  }
)
