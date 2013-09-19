require 'em-http-request'

require 'fiber'
require 'uri'
require 'json'

require 'em/docker/client/container'
require 'em/docker/client/image'

module EventMachine
  class Docker
    class Client
      def initialize(opts={})
        @host      = opts[:host] || "127.0.0.1"
        @port      = opts[:port] || 4243
        @synchrony = opts[:synchrony] || true

        if opts[:synchrony] == false
          raise "Non-fibered execution is not yet supported by EM::Docker::Client."
        end
      end

      def info
        # GET /info
        res = _make_request( :method => 'GET', :path => '/info', :expect => 'json' )
        
        {
          :containers      => res["Containers"],
          :images          => res["Images"],
          :debug           => res["Debug"],
          :nfd             => res["NFd"],
          :ngoroutines     => res["NGoroutines"],
          :memory_limit    => res["MemoryLimit"],
          :swap_limit      => res["SwapLimit"],
          :ipv4_forwarding => res["IPv4Forwarding"], 
        }
      end

      def version
        # GET /version
        res = _make_request( :method => 'GET', :path => '/version', :expect => 'json' )
        
        {
          :version    => res["Version"],
          :git_commit => res["GitCommit"],
          :go_version => res["GoVersion"],
        }
      end

      def containers(opts={})
        # GET /containers/json
        
        query_params = _parse_query_params( ["all", "limit", "since", "before", "size"], opts )

        containers = []

        j_containers = _make_request( :method => 'GET', :path => '/containers/json', :expect => 'json', :query_params => query_params )
        j_containers.each do |container_hash|
          container = EM::Docker::Client::Container.from_hash({
            :id          => container_hash["Id"],
            :image       => container_hash["Image"],
            :command     => container_hash["Command"],
            :created     => Time.at( container_hash["Created"] ),
            :status      => container_hash["Status"],
            # :ports     => container_hash["Ports"],
            :size_rw     => container_hash["SizeRw"],
            :size_rootfs => container_hash["SizeRootFs"],
          })

          containers << container
        end

        containers
      end

      def create_container
        # POST /containers/create
        # EM::Docker::Client::Container.create()
        # return EM::Docker::Client::Container object
      end

      def container(id)
        # GET /containers/(id)/json
        # return EM::Docker::Client::Container object
      end

      def images(opts={})
        # GET /images/json
        
        query_params = _parse_query_params( ["all"], opts )

        images = []

        j_images = _make_request( :method => 'GET', :path => '/images/json', :expect => 'json', :query_params => query_params )
        j_images.each do |image_hash|
          image = EM::Docker::Client::Image.from_hash({
            :id           => image_hash["Id"],
            :repository   => image_hash["Repository"],
            :tag          => image_hash["Tag"],
            :created      => Time.at( image_hash["Created"] ),
            :size         => image_hash["Size"],
            :virtual_size => image_hash["VirtualSize"],
          })

          images << image
        end

        images
      end

      def create_image
        # POST /images/create
        # returns EM::Docker::Client::Image object
      end

      def image(name)
        # GET /images/(name)/json
        # returns EM::Docker::Client::Image object
      end

      def _parse_query_params(params, opts)
        query_params = {}

        params.each do |param|
          query_params[param] = opts[ param.to_sym ] if opts[ param.to_sym ]
        end

        query_params 
      end

      def _make_request(opts)
        method       = opts[:method].downcase
        path         = opts[:path]
        expect       = opts[:expect] || 'json'
        query_params = opts[:query_params] || {}

        uri = URI("http://#{@host}/")
        uri.port = @port
        uri.path = path

        full_path = uri.to_s

        f = Fiber.current

        http = EventMachine::HttpRequest.new(full_path).send(method, { :query => query_params })
        http.errback { f.resume(http) }
        http.callback { f.resume(http) }

        Fiber.yield 

        if http.error
          raise "request #{method.upcase} #{path} failed, error #{http.error}"
        end

        res = http.response

        if expect == 'json'
          return JSON.parse(res)
        else
          raise "unable to parse expected value #{expect}"
        end
      end
    end
  end
end
  