require 'date'

module EventMachine
  class Docker
    class Client
      class Container
        attr_reader :id, :image, :command, :created, :status, :size_rw, :size_rootfs, :config, :bind_mounts

        def self.create(opts={})
          req_hash = {}

          mapping = {
            "Hostname" => {
              :source  => :host,
            },
            "User" => {
              :source  => :user,
            },
            "Memory" => {
              :source  => :memory,
            },
            "MemorySwap" => {
              :source  => :memory_swap,
            },
            "AttachStdin" => {
              :source => :attach_stdin,
              :default => false,
            },
            "AttachStdout" => {
              :source => :attach_stdout,
              :default => true,
            },
            "AttachStderr" => {
              :source => :attach_stderr,
              :default => true,
            },
            "PortSpecs" => {
              :source => :port_specs,
            },
            "Tty" => {
              :source => :tty,
              :default => true,
            },
            "OpenStdin" => {
              :source => :open_stdin,
              :default => true,
            },
            "StdinOnce" => {
              :source => :stdin_once,
              :default => true,
            },
            "Env" => {
              :source  => :env,
            },
            "Cmd" => {
              :source  => :cmd,
            },
            "Image" => {
              :source => :image,
            },
            "Volumes" => {
              :source => :volumes,
            },
            "VolumesFrom" => {
              :source => :volumes_from,
            },
            "WorkingDir" => {
              :source => :working_dir,
            },
            "DisableNetwork" => {
              :source => :disable_network,
            },
            "ExposedPorts" => {
              :source => :exposed_ports,
            },
          }

          mapping.each do |k,v|
            if opts.key?( v[:source] )
              req_hash[k] = opts[ v[:source] ]
            else
              if v.key?(:default)
                req_hash[k] = v[:default]
              elsif v.key?(:required)
                raise ArgumentError, "#{k} must be specified when creating container"
              end
            end
          end

          @bind_mounts = opts[:bind_mounts]

          if opts[:bind_mounts]
            req_hash["Volumes"] = {}
            opts[:bind_mounts].each do |bind|
              raise ArgumentError, "bind_mounts must have a dst attribute" unless bind[:dst]
              req_hash["Volumes"][ bind[:dst] ] = {}
            end
          end

          if opts[:cmd]
            req_hash["Cmd"] = Shellwords.shellwords(opts[:cmd])
          end

          @client ||= opts[:client]

          if opts[:name]
            query_params = @client._parse_query_params( ["name"], opts )
          else
            query_params = nil
          end

          res = @client._make_request( :method => 'POST', :path => "/containers/create", :query_params => query_params, :expect => 'json', :content_type => 'application/json', :data => req_hash)
          container_id = res["Id"]

          new(container_id, { :client => @client, :bind_mounts => opts[:bind_mounts] })
        end

        def self.from_hash(hash)
          new(hash[:id], hash)
        end

        def initialize(id, opts={})
          @id = id

          @client = opts[:client]

          @image       = opts[:image]
          @command     = opts[:command]
          @created     = opts[:created]
          @status      = opts[:status]
          @size_rw     = opts[:size_rw]
          @size_rootfs = opts[:size_rootfs]
          @config      = opts[:config]
          @bind_mounts = opts[:bind_mounts]
        end

        def info
          # GET /containers/(id)/json
          res = @client._make_request( :method => 'GET', :path => "/containers/#{@id}/json" )

          # res is a very large hash, so we'll do minimal (mostly automated) processing on it
          res = EM::Docker::Client::Util.process_go_hash(res)
          res[:created] = DateTime.iso8601( res[:created] ).to_time

          if res[:state][:started_at]
            res[:state][:started_at] = DateTime.iso8601( res[:state][:started_at] ).to_time
          end

          @id = res[:id] # update our existing (possibly shortened) id for the full ID
          @created = res[:created]
          @config  = res[:config]
          @command = res[:path] + " " + res[:args].join(" ")

          res
        end

        def processes
          # GET /containers/(id)/top
        end

        def changes
          # GET /containers/(id)/changes
        end

        def export
          # GET /containers/(id)/export
          # streams back export data
        end

        def start(opts={})
          # POST /containers/(id)/start

          req_hash = {}

          mapping = {
            "ContainerIDFile" => {
              :source  => :container_id_file,
            },
            "Privileged" => {
              :source  => :privileged,
            },
            "PortBindings" => {
              :source  => :port_bindings,
            },
            "Links" => {
               :source => :links,
            },
            "PublishAllPorts" => {
               :source => :publish_all_ports,
            },
            "Dns" => {
              :source  => :dns,
            },
            "DnsSearch" => {
              :source  => :dns_search,
            },
            "VolumesFrom" => {
               :source => :volumes_from,
            },
            "NetworkMode" => {
               :source => :network_mode,
            },
          }

          mapping.each do |k,v|
            if opts.key?( v[:source] )
              req_hash[k] = opts[ v[:source] ]
            else
              if v.key?(:default)
                req_hash[k] = v[:default]
              elsif v.key?(:required)
                raise ArgumentError, "#{k} must be specified when starting container"
              end
            end
          end

          if opts[:lxc_conf]
            req_hash["LxcConf"] = []
            opts[:lxc_conf].each do |k,v|
              req_hash["LxcConf"] << { "Key" => k, "Value" => v }
            end
          end

          if opts[:bind_mounts]
            @bind_mounts = opts[:bind_mounts]
          end

          if @bind_mounts
            req_hash["Binds"] = []
            @bind_mounts.each do |mount|
              next unless mount[:src] # in this case, this is a "volume", not a "bind"
              mount[:mode] ||= "rw"
              raise ArgumentError, "bind_mounts must have a dst attribute" unless mount[:dst]
              req_hash["Binds"] << "#{mount[:src]}:#{mount[:dst]}:#{mount[:mode]}"
            end
          end

          @client._make_request( :method => "POST", :path => "/containers/#{@id}/start", :data => req_hash, :content_type => "application/json", :expect => 'boolean')
        end

        def stop(opts={})
          # POST /containers/(id)/stop
          query_params = @client._parse_query_params( ["t"], opts )

          @client._make_request( :method => "POST", :path => "/containers/#{@id}/stop", :query_params => query_params, :expect => 'boolean')
        end

        def restart
          # POST /containers/(id)/restart
          query_params = @client._parse_query_params( ["t"], opts )

          @client._make_request( :method => "POST", :path => "/containers/#{@id}/restart", :query_params => query_params, :expect => 'boolean')
        end

        def kill
          # POST /containers/(id)/kill

          @client._make_request( :method => "POST", :path => "/containers/#{@id}/kill", :expect => 'boolean')
        end

        def attach
          # POST /containers/(id)/attach
          # this is a stream
        end

        def logs(opts={}, &block)
          # GET /containers/(id)/logs
          opts = opts.merge( :follow => block_given? )
          query_params = @client._parse_query_params( ['stdout', 'stderr', 'follow', 'tail', 'timestamps'], opts )
          @client._make_request :method => "GET", :path => "/containers/#{@id}/logs", :query_params => query_params, &block
        end
        
        def wait
          # POST /containers/(id)/wait

          res = @client._make_request( :method => "POST", :path => "/containers/#{@id}/wait", :expect => 'json')
          return res["StatusCode"]
        end

        def delete(opts={})
          # DELETE /containers/(id)
          query_params = @client._parse_query_params( ["v"], opts )

          @client._make_request( :method => "DELETE", :path => "/containers/#{@id}", :query_params => query_params, :expect => 'boolean')
        end

        def copy_out
          # POST /containers/(id)/copy
          # streams back contents of files/dirs
        end
      end
    end
  end
end
