require 'net/http'
require 'resolv'
require 'uri'

class ApplicationController < ActionController::Base
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :exception

  # Example endpoint that calls the backend nodejs api
  def index
    begin
      req = Net::HTTP::Get.new(nodejs_uri.to_s)
      res = Net::HTTP.start(nodejs_uri.host, nodejs_uri.port) {|http|
        http.read_timeout = 2
        http.open_timeout = 2
        http.request(req)
      }

      if res.code == '200'
        @text = res.body
      else
        @text = "no backend found"
      end

    rescue => e
      logger.error e.message
      logger.error e.backtrace.join("\n")
      @text = "no backend found"
    end

    begin
      crystalreq = Net::HTTP::Get.new(crystal_uri.to_s)
      crystalres = Net::HTTP.start(crystal_uri.host, crystal_uri.port) {|http|
        http.read_timeout = 2
        http.open_timeout = 2
        http.request(crystalreq)
      }

      if crystalres.code == '200'
        @crystal = crystalres.body
      else
        @crystal = "no backend found"
      end

    rescue => e
      logger.error e.message
      logger.error e.backtrace.join("\n")
      @crystal = "no backend found"
    end
  end

  # This endpoint is used for health checks. It should return a 200 OK when the app is up and ready to serve requests.
  def health
    render plain: "OK"
  end

  def crystal_uri
    svc = discover_service_instance('ecsdemo-crystal')
    svc ? URI::HTTP.build(host: svc["AWS_INSTANCE_IPV4"], path: "/crystal", port: 3000) : []
  end

  def nodejs_uri
    svc = discover_service_instance('ecsdemo-nodejs')
    svc ? URI::HTTP.build(host: svc["AWS_INSTANCE_IPV4"], path: "/", port: 3000) : []
  end

  before_action :discover_availability_zone, :discover_namespace
  before_action :code_hash

  private
  ###
  # Looks up service dependencies using cloud map.
  # Supports two types of execution modes
  # Params
  #
  # service_name => The name of the desired service e.g. ecsdemo-nodejs or ecsdemo-crystal
  #
  # mode => [:soft, :hard]
  # :soft =>
  #   In the case that a dependency is not found in the callee availability zone, will do an additional lookup to
  #   discover a running instance in any other availability zone.
  # :hard =>
  #   In the case that a dependency is not found in the callee availability zone, will fail the entire request and
  #   return a blank instance
  #
  def discover_service_instance(service_name, mode=:soft)
    service_discovery_client = Aws::ServiceDiscovery::Client.new
    found_instance = []

    logger.info "sd lookup: trying to find service #{service_name} at availability zone #{@availability_zone} and namespace #{@namespace}"
    response = service_discovery_client.discover_instances(
      namespace_name: @namespace,
      service_name: service_name,
      query_parameters: {
        "AVAILABILITY_ZONE": @availability_zone,
      }
    )

    if response.instances
      found_instance = response.instances.sample if response.instances
    end

    if response.instances.empty? && mode == :soft
      logger.info "soft mode: trying all the availability zones"
      response = service_discovery_client.discover_instances(
          namespace_name: @namespace,
          service_name: service_name,
          )

      found_instance = response.instances.sample if response.instances
    end

    found_instance ? found_instance["attributes"] : []
  end

  def discover_namespace
    @namespace = ENV.fetch('CLOUD_MAP_NAMESPACE')
  end

  def discover_region
    @region = ENV['AWS_REGION']
  end

  def discover_availability_zone
    # Used to query cloud map with.
    @availability_zone = ENV['FULL_AZ']
    # Shorter version to be displayed on the UI
    @az = ENV["AZ"]
  end

  def code_hash
    @code_hash = ENV["CODE_HASH"]
  end

  def custom_header
    response.headers['Cache-Control'] = 'max-age=86400, public'
  end
end
