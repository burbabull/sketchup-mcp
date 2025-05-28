module SketchupMCP
  class Server
    @@instance_count = 0
    @@global_servers = {}  # Track all server instances globally
    
    def initialize
      @@instance_count += 1
      @instance_id = @@instance_count
      
      log "Creating Server instance ##{@instance_id}"
      
      # Check if there's already a server for this port
      if @@global_servers[@port || 9876]
        log "Warning: Server instance already exists for port #{@port || 9876}"
      end
      
      @port = 9876
      @server = nil
      @running = false
      @active_clients = {}
      @operation_queue = []
      @processing_operation = false
      @consecutive_failures = 0
      @timer = nil
      @log_file = File.join(File.dirname(__FILE__), 'mcp_server.log')
      
      # Long-running operation tracking
      @pending_operations = {}  # operation_id => operation_info
      @operation_counter = 0
      @max_operation_time = 300.0  # 5 minutes max for any operation
      @operation_check_interval = 5.0  # Check operation status every 5 seconds
      @retry_failed_operations = true
      @max_operation_retries = 3
      
      # Register this instance globally
      @@global_servers[@port] = self
      
      log "Server instance ##{@instance_id} initialized"
    end

    def log(msg)
      SketchupMCP::Logging.log(msg)
    end

    def status
      if @running && @server
        log "Server Status: RUNNING on port #{@port}"
        log "Active clients: #{@active_clients.length}"
        log "Operation queue length: #{@operation_queue.length}"
        log "Processing operation: #{@processing_operation}"
        {
          running: true,
          port: @port,
          active_clients: @active_clients.length,
          operation_queue_length: @operation_queue.length
        }
      else
        log "Server Status: STOPPED"
        { running: false }
      end
    end

    def check_port_availability
      begin
        test_server = TCPServer.new('127.0.0.1', @port)
        test_server.close
        log "Port #{@port} is available"
        true
      rescue Errno::EADDRINUSE
        log "Port #{@port} is already in use"
        false
      rescue StandardError => e
        log "Error checking port #{@port}: #{e.message}"
        false
      end
    end

    def start
      if @running
        log "Server instance ##{@instance_id} is already running, skipping start"
        return
      end
      
      # Check if another server instance is already running on this port
      other_server = @@global_servers[@port]
      if other_server && other_server != self && other_server.instance_variable_get(:@running)
        log "Another server instance is already running on port #{@port}, skipping start"
        return
      end
      
      begin
        log "Starting server instance ##{@instance_id} on localhost:#{@port}..."
        
        # Check if port is available first
        unless check_port_availability
          raise "Port #{@port} is not available"
        end
        
        @server = TCPServer.new('127.0.0.1', @port)
        log "Server created on port #{@port}"
        
        @running = true
        @operation_queue = []
        @processing_operation = false
        @active_clients = {}
        @client_counter = 0
        @last_operation_time = Time.now
        @consecutive_failures = 0
        
        # Use adaptive timer frequency for better responsiveness
        @timer_id = UI.start_timer(0.01, true) {  # Start with 10ms intervals
          begin
            if @running
              # Adaptive timing based on load
              current_time = Time.now
              time_since_last = current_time - @last_operation_time
              
              # Process pending operations first with priority handling
              process_operation_queue_with_priority
              
              # Then check for new connections (less frequently if busy)
              if time_since_last > 0.05 || @operation_queue.empty?
                check_for_connections
              end
              
              # Clean up dead clients (even less frequently)
              if @operation_queue.length < 5
                cleanup_dead_clients
              end
              
              # Adjust timer frequency based on load
              adjust_timer_frequency
            end
          rescue StandardError => e
            log "Timer error: #{e.message}"
            log "Timer error backtrace: #{e.backtrace.join("\n")}"
            
            # Track consecutive failures for adaptive behavior
            @consecutive_failures += 1
            if @consecutive_failures > 10
              log "Too many consecutive timer failures, reducing frequency"
              # Don't restart timer immediately, let it recover
            end
          end
        }
        
        log "Server started and listening with adaptive timing"
        
      rescue StandardError => e
        log "Error in start: #{e.message}"
        log "Start error backtrace: #{e.backtrace.join("\n")}"
        stop
        raise e  # Re-raise to show the error in initialization
      end
    end

    def stop
      log "Stopping server..."
      @running = false
      
      if @timer_id
        UI.stop_timer(@timer_id)
        @timer_id = nil
      end
      
      # Close all active clients
      @active_clients.each_value { |client| client[:socket].close rescue nil }
      @active_clients.clear
      
      @server.close if @server
      @server = nil
      
      # Remove from global registry
      @@global_servers.delete(@port) if @@global_servers[@port] == self
      
      log "Server stopped"
    end

    def cleanup
      log "Cleaning up server resources..."
      stop
    end

    private

    def check_for_connections
      return unless @server
      
      begin
        # Accept new connections with timeout
        client_socket = @server.accept_nonblock
        
        # Generate unique client ID
        client_id = "client_#{Time.now.to_i}_#{rand(1000)}"
        
        # Set up client info
        @active_clients[client_id] = {
          socket: client_socket,
          connected_at: Time.now,
          last_activity: Time.now,
          buffer: ""
        }
        
        log "New client connected: #{client_id} from #{client_socket.peeraddr.last}"
        
        # Start reading from this client
        @operation_queue << {
          type: :read_from_client,
          client_id: client_id,
          created_at: Time.now
        }
        
        # Schedule periodic cleanup if not already scheduled
        if @pending_operations.any?
          schedule_pending_operations_cleanup
        end
        
      rescue IO::WaitReadable
        # No connections waiting - this is normal
      rescue StandardError => e
        log "Error accepting connection: #{e.message}"
      end
    end

    def cleanup_dead_clients
      return if @active_clients.empty?
      
      now = Time.now
      dead_clients = []
      
      @active_clients.each do |client_id, client_info|
        # Remove clients that haven't been active for 60 seconds
        if now - client_info[:last_activity] > 60
          dead_clients << client_id
        end
      end
      
      dead_clients.each do |client_id|
        log "Cleaning up dead client #{client_id}"
        client_info = @active_clients.delete(client_id)
        client_info[:socket].close rescue nil if client_info
      end
    end

    def process_operation_queue_with_priority
      return if @processing_operation || @operation_queue.empty?
      
      @processing_operation = true
      operation = @operation_queue.shift
      
      begin
        case operation[:type]
        when :check_for_connections
          check_for_connections
          
        when :cleanup_dead_clients
          cleanup_dead_clients
          
        when :read_from_client
          read_from_client_operation(operation[:client_id])
          
        when :execute_request
          # Create a long-running operation instead of executing immediately
          operation_id = SketchupMCP::Operations.create_long_running_operation(operation, @pending_operations, @operation_counter)
          @operation_counter = @operation_counter + 1
          
          # Only execute if operation was created (not a duplicate)
          if operation_id
            SketchupMCP::Operations.execute_long_running_operation(operation_id, @pending_operations, @active_clients)
          else
            log "Skipped duplicate request execution"
          end
          
        when :retry_failed_operation
          SketchupMCP::Operations.retry_failed_operation_by_id(operation[:operation_id], @pending_operations)
          
        else
          log "Unknown operation type: #{operation[:type]}"
        end
        
        @consecutive_failures = 0
        
      rescue StandardError => e
        log "Error processing operation: #{e.message}"
        log "Operation error backtrace: #{e.backtrace.join("\n")}"
        @consecutive_failures += 1
        
        # For long-running operations, mark as failed but don't close connection
        if operation[:type] == :execute_request && operation[:operation_id]
          SketchupMCP::Operations.mark_operation_failed(operation[:operation_id], e.message, @pending_operations)
        end
        
      ensure
        @processing_operation = false
        
        # Adjust timer frequency based on load and failures
        adjust_timer_frequency
      end
    end

    def read_from_client_operation(client_id)
      client_info = @active_clients[client_id]
      return unless client_info
      
      client_socket = client_info[:socket]
      
      begin
        # Try to read data with timeout
        data = nil
        begin
          # Use a timeout to prevent hanging
          Timeout::timeout(1.0) do
            chunk = client_socket.read_nonblock(8192)
            client_info[:buffer] += chunk if chunk
            client_info[:last_activity] = Time.now
          end
        rescue IO::WaitReadable
          # No data available - schedule retry if client is still young
          if Time.now - client_info[:connected_at] < 5.0
            @operation_queue << {
              type: :read_from_client,
              client_id: client_id,
              created_at: Time.now
            }
          else
            # Client has been idle too long, close it
            log "Client #{client_id} idle timeout - closing"
            @active_clients.delete(client_id)
            client_socket.close rescue nil
          end
          return
        rescue Timeout::Error
          log "Client #{client_id} read timeout"
          @active_clients.delete(client_id)
          client_socket.close rescue nil
          return
        rescue EOFError
          log "Client #{client_id} closed connection"
          @active_clients.delete(client_id)
          client_socket.close rescue nil
          return
        rescue StandardError => e
          log "Error reading from client #{client_id}: #{e.message}"
          @active_clients.delete(client_id)
          client_socket.close rescue nil
          return
        end
        
        # Check if we have complete JSON messages in the buffer
        buffer = client_info[:buffer]
        while buffer.include?("\n")
          line, buffer = buffer.split("\n", 2)
          next if line.strip.empty?
          
          # Queue the request processing
          @operation_queue << {
            type: :execute_request,
            request: line.strip,
            client_id: client_id,
            created_at: Time.now
          }
        end
        
        # Update the buffer
        client_info[:buffer] = buffer
        
        # Continue reading if client is still connected
        if @active_clients[client_id]
          @operation_queue << {
            type: :read_from_client,
            client_id: client_id,
            created_at: Time.now
          }
        end
        
      rescue StandardError => e
        log "Error in read_from_client_operation: #{e.message}"
        @active_clients.delete(client_id)
        client_socket.close rescue nil
      end
    end

    def adjust_timer_frequency
      # Adaptive timer frequency based on current load
      queue_length = @operation_queue.length
      pending_count = @pending_operations.length
      
      # Set frequency based on combined load from queue and pending operations
      total_load = queue_length + pending_count
      
      if total_load > 10
        @timer_frequency = 0.05  # 50ms for very high load
      elsif total_load > 5
        @timer_frequency = 0.1   # 100ms for high load
      elsif total_load > 2
        @timer_frequency = 0.2   # 200ms for moderate load
      else
        @timer_frequency = 0.5   # 500ms for low load
      end
      
      # Also schedule periodic cleanup of old pending operations
      schedule_pending_operations_cleanup
    end
    
    def schedule_pending_operations_cleanup
      # Check for operations that have been running too long
      UI.start_timer(@operation_check_interval, false) do
        SketchupMCP::Operations.cleanup_old_pending_operations(@pending_operations, @max_operation_time, @active_clients)
      end
    end
  end
end 