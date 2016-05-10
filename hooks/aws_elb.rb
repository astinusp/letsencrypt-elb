# EBL hook
class AWSElasticBalancer

  include LetsEncryptHelper

  def initialize(config)
    @iam = Aws::IAM::Client.new
    @config = config
    @remove_name = nil
  end

  def delete_unused_cert(name)
    puts "[Debug] Deleting IAM entity #{name}" if @config.debug
    @iam.delete_server_certificate(server_certificate_name: name)
  rescue Aws::IAM::Errors::NoSuchEntity
    puts "[Debug] IAM entity #{name} doesn't exist. Not deleting" if @config.debug
  end

  def iam_cert_upload_by_name(certificate, name)
    puts "[Debug] IAM creating entity #{name}" if @config.debug
    @iam.upload_server_certificate(
      server_certificate_name: name,
      certificate_body: certificate.to_pem,
      private_key: certificate.request.private_key.to_pem,
      certificate_chain: certificate.chain_to_pem)
  end

  def upload_certificate_to_aws(object)
    cert_name = generate_cert_filename(object.name, object.domains)
    begin
      res = iam_cert_upload_by_name(object.certificate, cert_name)
      @remove_name = "#{cert_name}-v2"
    rescue Aws::IAM::Errors::EntityAlreadyExists
      puts "[Debug] IAM entity #{cert_name} already exists. Trying suffix v2" if @config.debug
      res = iam_cert_upload_by_name(object.certificate, "#{cert_name}-v2")
      @remove_name = "#{cert_name}"
    end
    res.server_certificate_metadata.arn.to_s
  end

  def update_elastic_load_balancer(object)
    aws_cert = upload_certificate_to_aws(object)
    puts "[Debug] Certificate stored in IAM as #{aws_cert}"
    puts '[Debug] Waiting 10 secods'
    sleep 10 # Waiting for IAM
    elb = Aws::ElasticLoadBalancing::Client.new
    object.elbs.each do |balancer, port|
      begin
        puts "[Debug] Updating #{balancer} listener on port #{port[0]}" if @config.debug
        elb.set_load_balancer_listener_ssl_certificate(
          load_balancer_name: balancer,
          load_balancer_port: port[0],
          ssl_certificate_id: "#{aws_cert}")
      rescue Aws::ElasticLoadBalancing::Errors::ListenerNotFound
        puts "[Debug] No #{port[0]} listener for #{balancer}" if @config.debug
        puts "[Debug] Creating new listener #{port[0]} (HTTPS) -> #{port[1]} (HTTP) for #{balancer}" if @config.debug
        elb.create_load_balancer_listeners(
          load_balancer_name: balancer,
          listeners: [
            {
              protocol: 'HTTPS',
              load_balancer_port: port[0],
              instance_protocol: 'HTTP',
              instance_port: port[1],
              ssl_certificate_id: "#{aws_cert}"
            }
          ])
      end
    end
    puts '[Debug] Waiting 10 seconds before deleting old certificate' if @config.debug
    sleep 10
    delete_unused_cert(@remove_name)
  end
end
