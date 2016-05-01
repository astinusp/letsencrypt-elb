require 'aws-sdk'
# ROUTE53 HOOK
class AWSRoute53
  def initialize(config)
    @route = Aws::Route53::Client.new
    @config = config
  end

  def route53_domain(domain)
    puts "[Debug] Looking for #{domain} in Route53" if @config.debug
    @route.list_hosted_zones_by_name(dns_name: "#{domain}.").hosted_zones[0]
  end

  def construct_change_element(type, name, challenge)
    puts "[Debug] DNS prep. #{name} IN TXT #{challenge.record_content}" if @config.debug
    {
      action: type,
      resource_record_set: {
        name: "_acme-challenge.#{name}.",
        type: 'TXT',
        ttl: 60,
        resource_records: [value: "\"#{challenge.record_content}\""]
      }
    }
  end

  def construct_change_element_insert(name, challenge)
    construct_change_element('UPSERT', name, challenge)
  end

  def construct_change_element_remove(name, challenge)
    construct_change_element('DELETE', name, challenge)
  end

  def update_route53(domain, changes)
    zone = route53_domain(domain)
    puts "[Debug] updating zone #{zone.id}" if @config.debug
    @route.change_resource_record_sets(
      hosted_zone_id: zone.id,
      change_batch: { changes: changes })
  end

  def insert_challenges(object)
    object.challenges.each do |domain, challenges|
      changes = []
      challenges.each do |element|
        changes.push(
          construct_change_element_insert(element[:host], element[:challenge]))
      end
      puts "[Debug] Creating new records in #{domain}" if @config.debug
      update_route53(domain, changes)
    end
  end

  def remove_challenges(object)
    object.challenges.each do |domain, challenges|
      changes = []
      challenges.each do |element|
        changes.push(
          construct_change_element_remove(element[:host], element[:challenge]))
      end
      puts "[Debug] Removing challenge records from #{object.domain}" if @config.debug
      update_route53(domain, changes)
    end
  end
end
