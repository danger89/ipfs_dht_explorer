class Node < ApplicationRecord
  has_many :source_edges, class_name: 'Edge', foreign_key: :source_id
  has_many :source_peers, through: :source_edges, class_name: 'Node'

  has_many :target_edges, class_name: 'Edge', foreign_key: :target_id
  has_many :target_peers, through: :target_edges, class_name: 'Node'

  scope :without_boosters, -> { where.not(agent_version: ['hydra-booster/0.7.0', 'hydra-booster/0.7.3', 'dhtbooster/2']) }
  scope :without_storm, -> { where.not(agent_version: ['storm']) }

  GEO_IP_DIR = ENV['GEO_IP_DIR'] || '/usr/local/var/GeoIP'

  GEO_CITY_READER = MaxMind::GeoIP2::Reader.new("#{GEO_IP_DIR}/GeoLite2-City.mmdb")
  GEO_ASN_READER = MaxMind::GeoIP2::Reader.new("#{GEO_IP_DIR}/GeoLite2-ASN.mmdb")
  GEO_DOMAIN_READER = MaxMind::GeoIP2::Reader.new("#{GEO_IP_DIR}/GeoIP2-Domain.mmdb")

  SECIO_PATCH_VERSIONS = [
    '0.4.21',
    '0.4.22',
    '0.4.23',
    '0.4.21-rc3',
    '0.4.21-dev',
    '0.4.21-rc2',
    '0.4.22-rc2',
    '0.4.22-rc1',
    '0.4.22-dev',
    '0.4.23-rc1',
    '0.4.23-rc2'
  ]

  scope :before_secio, -> {where(minor_go_ipfs_version: 4).where.not(patch_go_ipfs_version: SECIO_PATCH_VERSIONS)}

  def to_s
    node_id
  end

  def geo_details
    return nil unless main_ip
    @geo_details ||= begin
      GEO_CITY_READER.city(main_ip.to_s)
    rescue MaxMind::GeoIP2::AddressNotFoundError
      nil
    end
  end

  def asn_details
    return nil unless main_ip
    @asn_details ||= begin
      GEO_ASN_READER.asn(main_ip.to_s)
    rescue MaxMind::GeoIP2::AddressNotFoundError
      nil
    end
  end

  def domain_details
    @domain_details ||= Node.domain_lookup(ip)
  end

  def self.domain_lookup(ip)
    return unless ip
    begin
      GEO_DOMAIN_READER.domain(ip.to_s).try(:domain)
    rescue MaxMind::GeoIP2::AddressNotFoundError
      nil
    end
  end

  def location_details
    return {} unless geo_details.present?
    return {} unless asn_details.present?
    {
      country_iso_code:               geo_details.country.iso_code,
      country_name:                   geo_details.country.name,
      most_specific_subdivision_name: geo_details.most_specific_subdivision.try(:name),
      city_name:                      geo_details.city.name,
      postal_code:                    geo_details.postal.code,
      accuracy_radius:                geo_details.location.accuracy_radius,
      latitude:                       geo_details.location.latitude,
      longitude:                      geo_details.location.longitude,
      network:                        geo_details.traits.network,
      autonomous_system_number:       asn_details.autonomous_system_number,
      autonomous_system_organization: asn_details.autonomous_system_organization
      }
  end

  def update_location_details
    return unless geo_details.present?
    return unless asn_details.present?
    update(location_details)
  end

  def update_domains
    update(domains: domain_names)
  end

  def domain_names
    ip_addresses.map{|ip| Node.domain_lookup(ip) }.compact.uniq
  end

  def main_ip
    main_ip4 || main_ip6
  end

  def main_ip4
    ip4_addresses.first
  end

  def main_ip6
    ip6_addresses.first
  end

  def ip_addresses
    ip4_addresses + ip6_addresses
  end

  def ip4_addresses
    return [] unless multiaddrs
    multiaddrs.select{|a| a.split('/')[1] == 'ip4' }.map{|a| IPAddr.new(a.split('/')[2]) }.uniq.select{|a| !a.loopback? && !a.private? && !a.link_local?  }
  end

  def ip6_addresses
    return [] unless multiaddrs
    multiaddrs.select{|a| a.split('/')[1] == 'ip6' }.map{|a| IPAddr.new(a.split('/')[2]) }.uniq.select{|a| !a.loopback? && !a.private? && !a.link_local?  }
  end

  def minor_go_ipfs_version
    return unless agent_version.present?
    return unless agent_version.include?('go-ipfs')
    agent_version.split('/')[agent_version.split('/').index('go-ipfs')+1].split('.')[1]
  end

  def update_minor_go_ipfs_version
    return unless minor_go_ipfs_version.present?
    update(minor_go_ipfs_version: minor_go_ipfs_version)
  end

  def patch_go_ipfs_version
    return unless agent_version.present?
    return unless agent_version.include?('go-ipfs')
    agent_version.split('/')[agent_version.split('/').index('go-ipfs')+1]
  end

  def update_patch_go_ipfs_version
    return unless patch_go_ipfs_version.present?
    update(patch_go_ipfs_version: patch_go_ipfs_version)
  end

  def update_peers_count
    update(peers_count: peers.count)
  end

  def self.update_peers_counts
    e = Edge.group(:source_id).count
    Node.where(reachable: true).each {|n| n.update(peers_count: e[n.id] || 0)}
  end

  def self.import_from_crawler
    file = File.open("/Users/andrewnesbitt/go/src/ipfs-crawler/output_data_crawls/visitedPeers_05-10-20--10:42:16_05-10-20--10:46:52.json")
    data = JSON.load(file)
    data['Nodes'].each do |node|
      n = Node.find_or_create_by(node_id: node['NodeID'])
      n.update(multiaddrs: node['MultiAddrs'], reachable: node['reachable'], agent_version: node['agent_version'])
    end
  end

  def self.import_from_other_crawler
    file = File.open("/Users/andrewnesbitt/code/libp2p-dht-scrape-client/output.json")
    data = JSON.load(file)
    data.each do |peer_id, node|
      n = Node.find_or_create_by(node_id: node['peerID'])

      updates = {}
      updates[:multiaddrs] = (Array(node['addresses']) + Array(n.multiaddrs)).uniq
      updates[:protocols] = (Array(node['protocols']) + Array(n.protocols)).uniq
      updates[:reachable] = node['agentVersion'].present?
      updates[:agent_version] = node['agentVersion'] if node['agentVersion'].present?

      n.update(updates)
    end
    return true
  end

  def self.import_from_counter
    file = File.open("data/output.json")
    data = JSON.load(file)
    data.each do |peer_id, peer_values|
      puts peer_id
      # TODO sightings
      # TODO last connected

      n = Node.find_by_node_id(peer_id)
      if n
        updates = {}
        updates[:sightings] = n.sightings + peer_values['n']
        updates[:updated_at] = peer_values['ls']
        updates[:created_at] = peer_values['fs']
        updates[:protocols] = (Array(peer_values['ps']) + Array(n.protocols)).uniq

        if peer_values['a'].present? && Array(peer_values['a']) != Array(n.multiaddrs)
          n.multiaddrs = (Array(peer_values['a']) + Array(n.multiaddrs)).uniq
          updates[:multiaddrs] = (Array(peer_values['a']) + Array(n.multiaddrs)).uniq
          updates[:domains] = n.domain_names
          updates.merge!(n.location_details)
        end

        if peer_values['av'].present? && n.agent_version != peer_values['av']
          n.agent_version = peer_values['av']
          updates[:agent_version] = peer_values['av']
          updates[:minor_go_ipfs_version] = n.minor_go_ipfs_version
          updates[:patch_go_ipfs_version] = n.patch_go_ipfs_version
          updates[:reachable] = true
        end
        n.update_columns(updates)
      else

        node_attrs = {
          node_id: peer_id,
          multiaddrs: Array(peer_values['a']),
          agent_version: peer_values['av'],
          protocols: Array(peer_values['ps']),
          reachable: peer_values['av'].present?,
          updated_at: peer_values['ls'],
          created_at: peer_values['fs'],
          sightings: peer_values['n']
        }
        node = Node.new(node_attrs)

        if node.multiaddrs.any?
          node.domains = node.domain_names
          node.assign_attributes(node.location_details)
        end

        if node.agent_version.present?
          node.minor_go_ipfs_version = node.minor_go_ipfs_version
          node.patch_go_ipfs_version = node.patch_go_ipfs_version
        end

        node.save
      end
    end
    puts "#{data.keys.length} peers imported"
    return nil
  end

  def self.update_location_details
    Node.all.find_each(&:update_location_details)
  end

  def self.update_minor_go_ipfs_version
    Node.where.not(agent_version: '').where(minor_go_ipfs_version: nil).find_each(&:update_minor_go_ipfs_version)
  end

  def self.import_and_update
    Node.import_from_other_crawler
    Node.import_from_crawler
    Node.update_peers_counts
    Node.update_location_details
    Node.update_minor_go_ipfs_version
  end
end
