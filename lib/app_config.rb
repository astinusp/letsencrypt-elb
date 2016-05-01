require 'yaml'

# Singleton class for Application Config
class AppConfig
  def self.environmet
    if ENV.key?('ENCRYPT_ENV')
      ENV['ENCRYPT_ENV']
    else
      'default'
    end
  end

  def self.app_config
    @app_config
  end

  def self.load_config_file(filename = 'config.yaml')
    @app_config = YAML.load(File.open(filename))[environmet]
  rescue Errno::ENOENT => e
    puts e
    exit
  end

  def self.method_missing(m, *_args)
    @app_config[m.to_s]
  end
end
