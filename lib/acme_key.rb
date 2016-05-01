class AcmeClientKey
  attr_reader :private_key
  def initialize(config = nil)
    @config = config || AppConfig.load_config_file
    @private_key = load_private_key || generate_private_key
  end

  def key_filename
    @config.acme_private_key || './acme_key/private.key'
  end

  def load_private_key
    return nil unless File.exist?(key_filename)
    puts "[Debug] Using existing private key from: #{key_filename}..." if @config.debug
    OpenSSL::PKey::RSA.new File.read(key_filename)
  end

  def save_private_key(key)
    puts "[Debug] Private key saved to #{key_filename}" if @config.debug
    File.write(key_filename, key.to_pem)
  end

  def register_private_key(key)
    client = Acme::Client.new(
      private_key: key,
      endpoint: @config.acme_endpoint)
    puts "[Debug] Registering private key to  #{@config.acme_email}" if @config.debug
    registration = client.register(contact: "mailto:#{@config.acme_email}")
    registration.agree_terms
  end

  def generate_private_key
    puts '[Debug] Generating new client private key...' if @config.debug
    private_key = OpenSSL::PKey::RSA.new(4096)
    save_private_key(private_key)
    register_private_key(private_key)
    private_key
  end
end
