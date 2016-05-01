require 'acme/client'
require 'aws-sdk'
require 'openssl'
require 'digest/md5'
require 'date'
require 'ostruct'

# Helper module for cert_filename generation
module LetsEncryptHelper
  def generate_cert_filename(domain, hosts)
    Digest::MD5.hexdigest("#{domain}-#{hosts}")
  end
end
include LetsEncryptHelper

Dir['./hooks/*.rb', './lib/*.rb'].each { |file| require file }

def create_lets_object(hash = {})
  OpenStruct.new(
    domains: hash[:domains] || {},
    elbs: hash[:elbs] || nil,
    challenges: hash[:challenges] || {},
    cerificate: hash[:certificate] || nil)
end

def verification_error(host, object)
  puts "challenge verification failed for: #{host}"
  @dns_hook.remove_challenges(object)
  exit
end

def extract_hostnames(object)
  hostnames = []
  object.challenges.each do |_domain, data|
    hostnames.push(data.map { |e|  e[:host] })
  end
  hostnames.flatten
end

def save_certificate(client, object)
  hostnames = extract_hostnames(object)
  csr = Acme::Client::CertificateRequest.new(names: hostnames)
  certificate = client.new_certificate(csr)
  filename = generate_cert_filename(object.name, object.domains)
  File.write("./certs/#{filename}.cert", certificate.to_pem)
  certificate
end

def certificate_expiring?(cert, config)
  expiration_day = config.days_to_expiration || 25
  time = DateTime.now + expiration_day.to_i
  return true if time.to_i >= cert.not_after.to_i
  false
end

def check_certificate_expiration(config)
  domains = {}
  config.certificates.each do |element, element_config|
    filename = "./certs/#{generate_cert_filename(element, element_config['domains'])}.cert"
    if File.exist?(filename)
      cert = OpenSSL::X509::Certificate.new(File.read(filename))
      next unless certificate_expiring?(cert, config)
    end
    domains[element] = element_config
  end
  domains
end

def normalize_hostname(domain, host)
  return host.chop if host.last == '.'
  "#{host}.#{domain}"
end

# Load Configuration file. Default is config.yaml
AppConfig.load_config_file

Aws.config.update(
  region: AppConfig.aws_region,
  access_key_id: ENV['AWS_ACCESS_KEY_ID'] || AppConfig.aws_access_key_id,
  secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'] || AppConfig.aws_secret_access_key)

client_key = AcmeClientKey.new(AppConfig)
@dns_hook = (AppConfig.dns_hook || 'AWSRoute53').constantize.new(AppConfig)
@upload_hook = (AppConfig.uload_hook || 'AWSElasticBalancer').constantize.new(AppConfig)

# Main program
Kernel.loop do
  client = Acme::Client.new(
    private_key: client_key.private_key,
    endpoint: AppConfig.acme_endpoint)

  renewal = check_certificate_expiration(AppConfig)

  renewal.each do |element, domain_config|
    lets_object = create_lets_object(
      name: element,
      domains: domain_config['domains'],
      elbs: domain_config['elbs'])

    lets_object.domains.each do |domain, hosts|
      hosts.each do |host|
        host = normalize_hostname(domain, host)
        puts "[Debug] Authorizing #{host}" if AppConfig.debug
        authorization = client.authorize(domain: host)
        puts "[Debug] Requesting challenge for #{host}" if AppConfig.debug
        challenge = authorization.dns01
        lets_object.challenges[domain] ||= []
        lets_object.challenges[domain].push(host: host, challenge: challenge)
      end
    end
    @dns_hook.insert_challenges(lets_object)
    puts "[Debug] Waiting #{AppConfig.dns_hook_sleep || 20} seconds" if AppConfig.debug
    sleep AppConfig.dns_hook_sleep || 20 # Let's wait for AWS Route53

    lets_object.challenges.each do |_domain, hosts|
      hosts.each do |host|
        puts "[Debug] Requesting verification for #{host[:host]}" if AppConfig.debug
        host[:challenge].request_verification
        sleep AppConfig.acme_verification_sleep || 2 # brief moment
        verification_error(host, lets_object) unless host[:challenge].verify_status == 'valid'
      end
    end
    @dns_hook.remove_challenges(lets_object)
    lets_object.certificate = save_certificate(client, lets_object)

    @upload_hook.update_elastic_load_balancer(lets_object)
  end
  exit unless ARGV.include?('-d')
  sleep 86_400
end
